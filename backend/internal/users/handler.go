// Package users implements the user registration endpoint.
package users

import (
	"database/sql"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/tally/backend/internal/middleware"
)

// Handler handles user routes.
type Handler struct {
	db *sql.DB
}

func NewHandler(db *sql.DB) *Handler {
	return &Handler{db: db}
}

type meResponse struct {
	UserID    string `json:"user_id"`
	CreatedAt string `json:"created_at"`
}

// Me upserts the authenticated Clerk user into the local users table and
// returns their record. Safe to call on every app launch — idempotent.
//
// @Summary      Register / fetch current user
// @Description  Upserts the Clerk user ID into the users table. Call this once after sign-in before making any other API calls. Returns the user record.
// @Tags         users
// @Produce      json
// @Success      200  {object} meResponse
// @Failure      401  {object} map[string]string
// @Failure      500  {object} map[string]string
// @Router       /v1/users/me [post]
func (h *Handler) Me(c *gin.Context) {
	userID, _ := c.Get(middleware.ClerkUserIDKey)
	id, _ := userID.(string)
	if id == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "missing_user_identity"})
		return
	}

	var createdAt time.Time
	err := h.db.QueryRowContext(c.Request.Context(), `
		INSERT INTO users (id) VALUES ($1)
		ON CONFLICT (id) DO UPDATE SET id = EXCLUDED.id
		RETURNING created_at`,
		id,
	).Scan(&createdAt)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}

	c.JSON(http.StatusOK, meResponse{
		UserID:    id,
		CreatedAt: createdAt.UTC().Format(time.RFC3339),
	})
}
