// Package stripeidentity handles Stripe Identity verification (ID document scan) and webhook.
package stripeidentity

import (
	"database/sql"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/stripe/stripe-go/v82"
	"github.com/stripe/stripe-go/v82/identity/verificationsession"
	"github.com/stripe/stripe-go/v82/webhook"
	"github.com/tally/backend/internal/config"
	"github.com/tally/backend/internal/middleware"
)

// Handler handles Stripe Identity verification session creation and webhook.
type Handler struct {
	db  *sql.DB
	cfg *config.Config
	mu  sync.Mutex
}

// NewHandler creates a new Identity handler.
func NewHandler(db *sql.DB, cfg *config.Config) *Handler {
	return &Handler{db: db, cfg: cfg}
}

func (h *Handler) setStripeKey() {
	h.mu.Lock()
	defer h.mu.Unlock()
	stripe.Key = h.cfg.StripeSecretKey
}

// CreateVerificationSessionRequest is the body for creating a verification session.
type CreateVerificationSessionRequest struct {
	MemberID string `json:"member_id" binding:"required"`
}

// CreateVerificationSessionResponse returns the client_secret for the client to open Stripe's verification UI.
type CreateVerificationSessionResponse struct {
	ClientSecret string `json:"client_secret"`
	URL          string `json:"url,omitempty"`
}

// CreateSession creates a Stripe Identity VerificationSession for document verification.
// The authenticated user must own the member (member's user_id = JWT user). Returns client_secret for the client SDK.
func (h *Handler) CreateSession(c *gin.Context) {
	if h.cfg.StripeSecretKey == "" {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "identity verification not configured"})
		return
	}
	var req CreateVerificationSessionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	memberID, err := uuid.Parse(req.MemberID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid member_id"})
		return
	}
	userID, _ := c.Get(middleware.ClerkUserIDKey)
	if userID == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	uid, _ := uuid.Parse(userID.(string))
	var actualUserID uuid.UUID
	if err := h.db.QueryRowContext(c.Request.Context(),
		`SELECT user_id FROM members WHERE id = $1`, memberID).Scan(&actualUserID); err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "member not found"})
		return
	} else if err != nil {
		slog.ErrorContext(c.Request.Context(), "identity session member lookup failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	if actualUserID != uid {
		c.JSON(http.StatusForbidden, gin.H{"error": "member does not belong to you"})
		return
	}

	h.setStripeKey()
	params := &stripe.IdentityVerificationSessionParams{
		Type: stripe.String("document"),
		Metadata: map[string]string{
			"tally_member_id": memberID.String(),
		},
	}
	session, err := verificationsession.New(params)
	if err != nil {
		slog.ErrorContext(c.Request.Context(), "Stripe VerificationSession create failed", "error", err)
		c.JSON(http.StatusBadGateway, gin.H{"error": "verification service unavailable"})
		return
	}
	resp := CreateVerificationSessionResponse{ClientSecret: session.ClientSecret}
	if session.URL != "" {
		resp.URL = session.URL
	}
	c.JSON(http.StatusOK, resp)
}

// IdentityWebhook handles Stripe webhook events for Identity. Expects identity.verification_session.verified.
// On verified, updates members.identity_verified_at and members.stripe_verification_session_id for the member in metadata.
func (h *Handler) IdentityWebhook(c *gin.Context) {
	if h.cfg.StripeWebhookSecret == "" {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "webhook not configured"})
		return
	}
	payload, err := io.ReadAll(c.Request.Body)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "failed to read body"})
		return
	}
	sig := c.GetHeader("Stripe-Signature")
	event, err := webhook.ConstructEvent(payload, sig, h.cfg.StripeWebhookSecret)
	if err != nil {
		slog.WarnContext(c.Request.Context(), "Stripe identity webhook signature invalid", "error", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid signature"})
		return
	}
	if event.Type != "identity.verification_session.verified" {
		c.JSON(http.StatusOK, gin.H{"received": true})
		return
	}

	var session stripe.IdentityVerificationSession
	if err := json.Unmarshal(event.Data.Raw, &session); err != nil {
		slog.ErrorContext(c.Request.Context(), "identity session unmarshal failed", "error", err)
		c.JSON(http.StatusOK, gin.H{"received": true})
		return
	}
	memberIDStr := session.Metadata["tally_member_id"]
	if memberIDStr == "" {
		slog.WarnContext(c.Request.Context(), "identity webhook missing tally_member_id in metadata")
		c.JSON(http.StatusOK, gin.H{"received": true})
		return
	}
	memberID, err := uuid.Parse(memberIDStr)
	if err != nil {
		slog.WarnContext(c.Request.Context(), "identity webhook invalid member_id", "member_id", memberIDStr)
		c.JSON(http.StatusOK, gin.H{"received": true})
		return
	}

	_, err = h.db.ExecContext(c.Request.Context(),
		`UPDATE members SET identity_verified_at = $1, stripe_verification_session_id = $2, updated_at = $1 WHERE id = $3`,
		time.Now().UTC(), session.ID, memberID)
	if err != nil {
		slog.ErrorContext(c.Request.Context(), "identity verified update failed", "member_id", memberID, "error", err)
	}
	slog.InfoContext(c.Request.Context(), "identity verified", "member_id", memberID, "session_id", session.ID)
	c.JSON(http.StatusOK, gin.H{"received": true})
}
