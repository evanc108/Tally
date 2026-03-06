// Package users implements user registration, payment method management, and
// KYC verification endpoints.
package users

import (
	"database/sql"
	"log/slog"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/tally/backend/internal/middleware"
	"github.com/tally/backend/internal/stripeidentity"
	"github.com/tally/backend/internal/stripepayment"
)

// Handler handles user routes.
type Handler struct {
	db       *sql.DB
	payment  stripepayment.PaymentClient
	identity stripeidentity.IdentityClient
}

func NewHandler(db *sql.DB, payment stripepayment.PaymentClient, identity stripeidentity.IdentityClient) *Handler {
	return &Handler{db: db, payment: payment, identity: identity}
}

type meResponse struct {
	UserID    string `json:"user_id"`
	CreatedAt string `json:"created_at"`
}

func (h *Handler) Me(c *gin.Context) {
	raw, ok := c.Get(middleware.ClerkUserIDKey)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "missing_user_identity"})
		return
	}
	id, ok := raw.(string)
	if !ok || id == "" {
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

type createSetupIntentResponse struct {
	ClientSecret string `json:"client_secret"`
}

func (h *Handler) CreateSetupIntent(c *gin.Context) {
	raw, ok := c.Get(middleware.ClerkUserIDKey)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "missing_user_identity"})
		return
	}
	userID, _ := raw.(string)
	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "missing_user_identity"})
		return
	}

	// Get or create Stripe Customer for this user so the SetupIntent attaches the
	// PaymentMethod to a Customer (required for later off-session ACH charges at settlement).
	var stripeCustomerID sql.NullString
	err := h.db.QueryRowContext(c.Request.Context(), `SELECT stripe_customer_id FROM users WHERE id = $1`, userID).Scan(&stripeCustomerID)
	if err != nil {
		if err == sql.ErrNoRows {
			c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
			return
		}
		slog.ErrorContext(c.Request.Context(), "CreateSetupIntent user lookup failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	customerID := stripeCustomerID.String
	if !stripeCustomerID.Valid || customerID == "" {
		customerID, err = h.payment.CreateCustomer(c.Request.Context(), userID)
		if err != nil {
			slog.ErrorContext(c.Request.Context(), "CreateCustomer failed", "error", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "stripe error"})
			return
		}
		_, err = h.db.ExecContext(c.Request.Context(), `UPDATE users SET stripe_customer_id = $1, updated_at = NOW() WHERE id = $2`, customerID, userID)
		if err != nil {
			slog.ErrorContext(c.Request.Context(), "CreateSetupIntent save customer id failed", "error", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
			return
		}
	}

	clientSecret, err := h.payment.CreateSetupIntent(c.Request.Context(), customerID)
	if err != nil {
		slog.ErrorContext(c.Request.Context(), "CreateSetupIntent failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "stripe error"})
		return
	}

	c.JSON(http.StatusOK, createSetupIntentResponse{ClientSecret: clientSecret})
}

type confirmPaymentMethodRequest struct {
	MemberID        string `json:"member_id"         binding:"required"`
	PaymentMethodID string `json:"payment_method_id" binding:"required"`
}

func (h *Handler) ConfirmPaymentMethod(c *gin.Context) {
	var req confirmPaymentMethodRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	raw, ok := c.Get(middleware.ClerkUserIDKey)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "missing_user_identity"})
		return
	}
	id, _ := raw.(string)

	// Verify the PaymentMethod exists in Stripe before persisting it.
	if err := h.payment.RetrievePaymentMethod(c.Request.Context(), req.PaymentMethodID); err != nil {
		slog.ErrorContext(c.Request.Context(), "RetrievePaymentMethod failed", "pm_id", req.PaymentMethodID, "error", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid payment_method_id"})
		return
	}

	res, err := h.db.ExecContext(c.Request.Context(), `
		UPDATE members
		SET stripe_payment_method_id = $1, updated_at = NOW()
		WHERE id = $2 AND user_id = $3`,
		req.PaymentMethodID, req.MemberID, id,
	)
	if err != nil {
		slog.ErrorContext(c.Request.Context(), "confirm PM failed", "member_id", req.MemberID, "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "member not found or not owned by you"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"status": "payment_method_attached"})
}

func (h *Handler) CreateBackupSetupIntent(c *gin.Context) {
	raw, ok := c.Get(middleware.ClerkUserIDKey)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "missing_user_identity"})
		return
	}
	_, _ = raw.(string)

	clientSecret, err := h.payment.CreateSetupIntent(c.Request.Context(), "")
	if err != nil {
		slog.ErrorContext(c.Request.Context(), "CreateBackupSetupIntent failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "stripe error"})
		return
	}

	c.JSON(http.StatusOK, createSetupIntentResponse{ClientSecret: clientSecret})
}

type confirmBackupRequest struct {
	MemberID        string `json:"member_id"         binding:"required"`
	PaymentMethodID string `json:"payment_method_id" binding:"required"`
}

func (h *Handler) ConfirmBackupPaymentMethod(c *gin.Context) {
	var req confirmBackupRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	raw, ok := c.Get(middleware.ClerkUserIDKey)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "missing_user_identity"})
		return
	}
	id, _ := raw.(string)

	// Verify the PaymentMethod exists in Stripe before persisting it.
	if err := h.payment.RetrievePaymentMethod(c.Request.Context(), req.PaymentMethodID); err != nil {
		slog.ErrorContext(c.Request.Context(), "RetrievePaymentMethod failed (backup)", "pm_id", req.PaymentMethodID, "error", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid payment_method_id"})
		return
	}

	res, err := h.db.ExecContext(c.Request.Context(), `
		UPDATE members
		SET stripe_backup_payment_method_id = $1, updated_at = NOW()
		WHERE id = $2 AND user_id = $3`,
		req.PaymentMethodID, req.MemberID, id,
	)
	if err != nil {
		slog.ErrorContext(c.Request.Context(), "confirm backup PM failed", "member_id", req.MemberID, "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "member not found or not owned by you"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"status": "backup_payment_method_attached"})
}

type kycRequest struct {
	MemberID string `json:"member_id" binding:"required"`
}

type kycResponse struct {
	SessionID string `json:"session_id"`
	URL       string `json:"url"`
}

func (h *Handler) StartKYC(c *gin.Context) {
	var req kycRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	sessionID, url, err := h.identity.CreateVerificationSession(c.Request.Context(), req.MemberID)
	if err != nil {
		slog.ErrorContext(c.Request.Context(), "CreateVerificationSession failed", "member_id", req.MemberID, "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "stripe error"})
		return
	}

	c.JSON(http.StatusOK, kycResponse{SessionID: sessionID, URL: url})
}
