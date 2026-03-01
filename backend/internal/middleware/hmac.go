package middleware

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"io"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
)

const hmacHeader = "X-Tally-Signature"

// HMACVerification validates that each incoming request was signed by the
// authorised card processor.
//
// Expected header format:
//
//	X-Tally-Signature: sha256=<hex(HMAC-SHA256(webhookSecret, rawBody))>
//
// The body is fully buffered and restored so downstream handlers can re-read it.
func HMACVerification(secret string) gin.HandlerFunc {
	secretBytes := []byte(secret)

	return func(c *gin.Context) {
		sig := c.GetHeader(hmacHeader)
		if sig == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"error": "missing_signature",
				"hint":  "include " + hmacHeader + ": sha256=<hex>",
			})
			return
		}

		body, err := io.ReadAll(c.Request.Body)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusBadRequest, gin.H{"error": "cannot_read_body"})
			return
		}
		// Restore the body so JSON binding works in the handler.
		c.Request.Body = io.NopCloser(strings.NewReader(string(body)))

		expected := computeHMAC(secretBytes, body)

		// Constant-time comparison prevents timing-oracle attacks.
		if !hmac.Equal([]byte(expected), []byte(sig)) {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid_signature"})
			return
		}

		c.Next()
	}
}

// computeHMAC returns the HMAC-SHA256 digest in "sha256=<hex>" format.
func computeHMAC(secret, body []byte) string {
	mac := hmac.New(sha256.New, secret)
	mac.Write(body)
	return "sha256=" + hex.EncodeToString(mac.Sum(nil))
}
