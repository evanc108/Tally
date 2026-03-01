package middleware

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
)

const (
	idempotencyHeader = "Idempotency-Key"
	cacheKeyPrefix    = "idem:resp:"
	lockKeyPrefix     = "idem:lock:"
	cacheTTL          = 24 * time.Hour
	lockTTL           = 30 * time.Second
)

// cachedResponse is the envelope stored in Redis.
type cachedResponse struct {
	StatusCode int             `json:"sc"`
	Body       json.RawMessage `json:"b"`
}

// Idempotency caches responses by the Idempotency-Key header so that network
// retries get an identical reply without re-executing handler logic.
//
// Race-condition protection:
//   - A Redis SET NX lock is acquired before processing.
//   - A concurrent duplicate receives 409 and should retry after ~1 s.
//   - Once the response is cached, the lock is released and future duplicates
//     get the cached reply immediately.
func Idempotency(rdb *redis.Client) gin.HandlerFunc {
	return func(c *gin.Context) {
		key := c.GetHeader(idempotencyHeader)
		if key == "" {
			// No key supplied — treat as a non-idempotent request.
			c.Next()
			return
		}

		ctx := c.Request.Context()
		cacheKey := cacheKeyPrefix + key
		lockKey := lockKeyPrefix + key

		// ── 1. Check cache (warm path) ────────────────────────────────────────
		if raw, err := rdb.Get(ctx, cacheKey).Bytes(); err == nil {
			var resp cachedResponse
			if json.Unmarshal(raw, &resp) == nil {
				c.Data(resp.StatusCode, "application/json", resp.Body)
				c.Abort()
				return
			}
		}

		// ── 2. Acquire processing lock (cold path) ────────────────────────────
		acquired, err := rdb.SetNX(ctx, lockKey, "1", lockTTL).Result()
		if err != nil || !acquired {
			c.AbortWithStatusJSON(http.StatusConflict, gin.H{
				"error":   "duplicate_in_flight",
				"message": "An identical request is being processed. Retry in ~1s.",
			})
			return
		}
		// Release lock after this function returns (regardless of panic).
		defer rdb.Del(context.Background(), lockKey) //nolint:errcheck

		// ── 3. Execute handler, intercept the response ────────────────────────
		rw := &bodyCapture{
			ResponseWriter: c.Writer,
			body:           &bytes.Buffer{},
			status:         http.StatusOK,
		}
		c.Writer = rw
		c.Next()

		// ── 4. Cache only deterministic responses (not 5xx) ───────────────────
		if rw.status < 500 {
			resp := cachedResponse{
				StatusCode: rw.status,
				Body:       rw.body.Bytes(),
			}
			if data, err := json.Marshal(resp); err == nil {
				// Fire-and-forget; a cache miss is safer than blocking the response.
				go rdb.Set(context.Background(), cacheKey, data, cacheTTL) //nolint:errcheck
			}
		}
	}
}

// bodyCapture wraps gin.ResponseWriter to record the response for caching.
type bodyCapture struct {
	gin.ResponseWriter
	body   *bytes.Buffer
	status int
}

func (bc *bodyCapture) Write(b []byte) (int, error) {
	bc.body.Write(b)
	return bc.ResponseWriter.Write(b)
}

func (bc *bodyCapture) WriteHeader(code int) {
	bc.status = code
	bc.ResponseWriter.WriteHeader(code)
}

func (bc *bodyCapture) WriteHeaderNow() {
	bc.ResponseWriter.WriteHeaderNow()
}
