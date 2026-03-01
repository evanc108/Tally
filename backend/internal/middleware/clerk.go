package middleware

import (
	"context"
	"net/http"
	"strings"
	"time"

	"github.com/MicahParks/keyfunc/v3"
	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
)

// ClerkUserIDKey is the gin context key under which the Clerk user ID is stored.
const ClerkUserIDKey = "clerk_user_id"

// ClerkAuth returns a gin.HandlerFunc that validates a Clerk-issued JWT from
// the "Authorization: Bearer <token>" header.
//
// On success: stores the Clerk user ID (JWT "sub" claim) in the gin context
// under ClerkUserIDKey for downstream handlers to read.
//
// On failure: aborts the request with 401 Unauthorized.
//
// Panics at startup if the JWKS endpoint cannot be reached — the service is
// misconfigured and should not begin accepting requests.
func ClerkAuth(jwksURL string) gin.HandlerFunc {
	// NewDefaultCtx fetches the JWKS on startup and launches a background
	// goroutine to refresh it hourly. context.Background() keeps the goroutine
	// alive for the life of the process.
	jwks, err := keyfunc.NewDefaultCtx(context.Background(), []string{jwksURL})
	if err != nil {
		panic("clerk: failed to initialize JWKS from " + jwksURL + ": " + err.Error())
	}

	return func(c *gin.Context) {
		raw := c.GetHeader("Authorization")
		if !strings.HasPrefix(raw, "Bearer ") {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"error": "missing_token",
			})
			return
		}
		tokenStr := strings.TrimPrefix(raw, "Bearer ")

		token, err := jwt.ParseWithClaims(
			tokenStr,
			&jwt.RegisteredClaims{},
			jwks.Keyfunc,
			jwt.WithValidMethods([]string{"RS256"}),
			jwt.WithLeeway(5*time.Second),
		)
		if err != nil || !token.Valid {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"error": "invalid_token",
			})
			return
		}

		claims, ok := token.Claims.(*jwt.RegisteredClaims)
		if !ok || claims.Subject == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"error": "invalid_claims",
			})
			return
		}

		c.Set(ClerkUserIDKey, claims.Subject)
		c.Next()
	}
}
