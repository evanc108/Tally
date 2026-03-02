// Package stripepayment handles Stripe SetupIntent and PaymentMethod attachment for debit card linking.
package stripepayment

import (
	"database/sql"
	"log/slog"
	"net/http"
	"sync"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/stripe/stripe-go/v82"
	"github.com/stripe/stripe-go/v82/customer"
	"github.com/stripe/stripe-go/v82/paymentmethod"
	"github.com/stripe/stripe-go/v82/setupintent"
	"github.com/tally/backend/internal/config"
	"github.com/tally/backend/internal/middleware"
)

// Handler handles Stripe payment method setup and attach.
type Handler struct {
	db  *sql.DB
	cfg *config.Config
	mu  sync.Mutex
}

// NewHandler creates a new Stripe payment handler.
func NewHandler(db *sql.DB, cfg *config.Config) *Handler {
	return &Handler{db: db, cfg: cfg}
}

func (h *Handler) setStripeKey() {
	h.mu.Lock()
	defer h.mu.Unlock()
	stripe.Key = h.cfg.StripeSecretKey
}

// CreateSetupIntentRequest is the body for creating a SetupIntent.
type CreateSetupIntentRequest struct {
	MemberID string `json:"member_id" binding:"required"`
}

// CreateSetupIntentResponse returns the client_secret for the client to confirm and attach a card.
type CreateSetupIntentResponse struct {
	ClientSecret string `json:"client_secret"`
}

// CreateSetupIntent creates a Stripe Customer (if needed) and a SetupIntent so the client can attach a PaymentMethod.
func (h *Handler) CreateSetupIntent(c *gin.Context) {
	if h.cfg.StripeSecretKey == "" {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "stripe not configured"})
		return
	}
	var req CreateSetupIntentRequest
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

	var stripeCustomerID sql.NullString
	if err := h.db.QueryRowContext(c.Request.Context(),
		`SELECT stripe_customer_id FROM members WHERE id = $1 AND user_id = $2`, memberID, uid).Scan(&stripeCustomerID); err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "member not found"})
		return
	} else if err != nil {
		slog.ErrorContext(c.Request.Context(), "setup intent member lookup failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}

	h.setStripeKey()
	custID := stripeCustomerID.String
	if !stripeCustomerID.Valid || custID == "" {
		cust, err := customer.New(&stripe.CustomerParams{
			Metadata: map[string]string{"tally_member_id": memberID.String()},
		})
		if err != nil {
			slog.ErrorContext(c.Request.Context(), "Stripe customer create failed", "error", err)
			c.JSON(http.StatusBadGateway, gin.H{"error": "payment service unavailable"})
			return
		}
		custID = cust.ID
		_, _ = h.db.ExecContext(c.Request.Context(),
			`UPDATE members SET stripe_customer_id = $1, updated_at = NOW() WHERE id = $2`, custID, memberID)
	}

	si, err := setupintent.New(&stripe.SetupIntentParams{
		Customer: stripe.String(custID),
		PaymentMethodTypes: stripe.StringSlice([]string{"card"}),
		Usage: stripe.String("off_session"),
	})
	if err != nil {
		slog.ErrorContext(c.Request.Context(), "Stripe SetupIntent create failed", "error", err)
		c.JSON(http.StatusBadGateway, gin.H{"error": "payment service unavailable"})
		return
	}
	c.JSON(http.StatusOK, CreateSetupIntentResponse{ClientSecret: si.ClientSecret})
}

// AttachPaymentMethodRequest is the body for attaching a PaymentMethod to a member.
type AttachPaymentMethodRequest struct {
	MemberID       string `json:"member_id" binding:"required"`
	PaymentMethodID string `json:"payment_method_id" binding:"required"`
	AsBackup       bool   `json:"as_backup"` // if true, set as backup; else primary
}

// AttachPaymentMethod attaches the given PaymentMethod to the member's Stripe Customer and saves to DB.
func (h *Handler) AttachPaymentMethod(c *gin.Context) {
	if h.cfg.StripeSecretKey == "" {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "stripe not configured"})
		return
	}
	var req AttachPaymentMethodRequest
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

	var stripeCustomerID string
	if err := h.db.QueryRowContext(c.Request.Context(),
		`SELECT COALESCE(stripe_customer_id, '') FROM members WHERE id = $1 AND user_id = $2`, memberID, uid).Scan(&stripeCustomerID); err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "member not found"})
		return
	} else if err != nil || stripeCustomerID == "" {
		if err != nil {
			slog.ErrorContext(c.Request.Context(), "attach PM member lookup failed", "error", err)
		} else {
			c.JSON(http.StatusBadRequest, gin.H{"error": "member has no Stripe customer; create a setup intent first"})
		}
		return
	}

	h.setStripeKey()
	_, err = paymentmethod.Attach(req.PaymentMethodID, &stripe.PaymentMethodAttachParams{
		Customer: stripe.String(stripeCustomerID),
	})
	if err != nil {
		slog.ErrorContext(c.Request.Context(), "Stripe PaymentMethod attach failed", "error", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": "failed to attach payment method"})
		return
	}

	if req.AsBackup {
		_, err = h.db.ExecContext(c.Request.Context(),
			`UPDATE members SET stripe_backup_payment_method_id = $1, updated_at = NOW() WHERE id = $2`, req.PaymentMethodID, memberID)
	} else {
		_, err = h.db.ExecContext(c.Request.Context(),
			`UPDATE members SET stripe_payment_method_id = $1, updated_at = NOW() WHERE id = $2`, req.PaymentMethodID, memberID)
	}
	if err != nil {
		slog.ErrorContext(c.Request.Context(), "attach PM db update failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db update failed"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"ok": true})
}
