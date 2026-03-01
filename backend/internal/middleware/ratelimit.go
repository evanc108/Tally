package middleware

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
)

const rateLimitKeyPrefix = "rl:"

// RateLimit enforces a maximum of maxRequests per window per client IP using a
// Redis counter. If Redis is unavailable the middleware fails open (logs a
// warning and continues) so that a cache outage never blocks all traffic.
func RateLimit(rdb *redis.Client, maxRequests int, window time.Duration) gin.HandlerFunc {
	return func(c *gin.Context) {
		key := fmt.Sprintf("%s%s", rateLimitKeyPrefix, c.ClientIP())
		ctx, cancel := context.WithTimeout(c.Request.Context(), 2*time.Second)
		defer cancel()

		count, err := rdb.Incr(ctx, key).Result()
		if err != nil {
			slog.WarnContext(c.Request.Context(), "rate limit Redis error — bypassing",
				"client_ip", c.ClientIP(), "error", err)
			c.Next()
			return
		}

		// Set expiry only on the first request in a new window.
		if count == 1 {
			rdb.Expire(ctx, key, window) //nolint:errcheck
		}

		if count > int64(maxRequests) {
			c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{
				"error":   "rate_limit_exceeded",
				"message": fmt.Sprintf("Too many requests. Limit is %d per %s.", maxRequests, window),
			})
			return
		}

		c.Next()
	}
}
