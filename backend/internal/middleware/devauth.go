package middleware

import "github.com/gin-gonic/gin"

// DevAuth is a development-only middleware that injects a hardcoded user ID
// into the gin context, bypassing Clerk JWT verification.
//
// It is ONLY activated when CLERK_JWKS_URL is unset. main.go never uses it
// in production (config.Validate() blocks startup with default secrets, and
// ClerkAuth is used whenever ClerkJWKSURL is set).
func DevAuth(userID string) gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Set(ClerkUserIDKey, userID)
		c.Next()
	}
}
