// Package cards implements HTTP handlers for Stripe Issuing card management.
package cards

import (
	"context"
	"database/sql"
	"log/slog"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
	"github.com/tally/backend/internal/config"
	"github.com/tally/backend/internal/stripeissuing"
)

const issueCardTimeout = 15 * time.Second

// Handler handles card-issuing routes.
type Handler struct {
	db      *sql.DB
	rdb     *redis.Client
	cfg     *config.Config
	issuing stripeissuing.CardIssuingClient
}

// NewHandler wires dependencies. Pass stripeissuing.NewMockClient() in development.
func NewHandler(
	db *sql.DB,
	rdb *redis.Client,
	cfg *config.Config,
	issuing stripeissuing.CardIssuingClient,
) *Handler {
	return &Handler{db: db, rdb: rdb, cfg: cfg, issuing: issuing}
}

// ── POST /v1/cards/issue ─────────────────────────────────────────────────────

type issueCardRequest struct {
	MemberID  string `json:"member_id"  binding:"required"`
	FirstName string `json:"first_name" binding:"required"`
	LastName  string `json:"last_name"  binding:"required"`
	Email     string `json:"email"      binding:"required"`
}

type issueCardResponse struct {
	CardholderID string `json:"cardholder_id"`
	CardID       string `json:"card_id"`
	CardToken    string `json:"card_token"`
}

// IssueCard creates a Stripe Issuing cardholder and virtual card for a member.
// Requires the member to have passed KYC (kyc_status = 'approved').
//
// @Summary      Issue a virtual card
// @Description  Creates a Stripe Issuing cardholder and virtual card for a member. KYC approval is required.
// @Tags         cards
// @Accept       json
// @Produce      json
// @Param        body body issueCardRequest true "Member identity"
// @Success      201  {object} issueCardResponse
// @Failure      400  {object} map[string]string
// @Failure      403  {object} map[string]string
// @Failure      404  {object} map[string]string
// @Failure      502  {object} map[string]string
// @Failure      500  {object} map[string]string
// @Router       /v1/cards/issue [post]
func (h *Handler) IssueCard(c *gin.Context) {
	var req issueCardRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	memberID, err := uuid.Parse(req.MemberID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid member_id"})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), issueCardTimeout)
	defer cancel()

	// Gate on KYC approval before issuing a card.
	var kycStatus string
	err = h.db.QueryRowContext(ctx,
		`SELECT kyc_status FROM members WHERE id = $1`, memberID,
	).Scan(&kycStatus)
	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "member not found"})
		return
	} else if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	if kycStatus != "approved" {
		c.JSON(http.StatusForbidden, gin.H{
			"error":      "kyc_required",
			"kyc_status": kycStatus,
		})
		return
	}

	// 1. Create cardholder in Stripe Issuing.
	cardholderID, err := h.issuing.CreateCardholder(ctx, stripeissuing.CreateCardholderRequest{
		ExternalID: memberID.String(),
		FirstName:  req.FirstName,
		LastName:   req.LastName,
		Email:      req.Email,
	})
	if err != nil {
		slog.ErrorContext(ctx, "CreateCardholder failed", "member_id", memberID, "error", err)
		c.JSON(http.StatusBadGateway, gin.H{"error": "card issuer unavailable"})
		return
	}

	// 2. Issue a virtual card.
	cardID, cardToken, err := h.issuing.IssueCard(ctx, cardholderID, h.cfg.StripeIssuingCardProduct)
	if err != nil {
		slog.ErrorContext(ctx, "IssueCard failed", "member_id", memberID, "error", err)
		c.JSON(http.StatusBadGateway, gin.H{"error": "card issuer unavailable"})
		return
	}

	// 3. Persist to the members row.
	const q = `
		UPDATE members
		SET stripe_cardholder_id = $1,
		    stripe_card_id       = $2,
		    card_token           = $3,
		    updated_at           = NOW()
		WHERE id = $4
	`
	res, err := h.db.ExecContext(ctx, q, cardholderID, cardID, cardToken, memberID)
	if err != nil {
		slog.ErrorContext(ctx, "update member card IDs failed", "member_id", memberID, "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db write failed"})
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "member not found"})
		return
	}

	slog.InfoContext(ctx, "card issued", "member_id", memberID, "card_id", cardID)
	c.JSON(http.StatusCreated, issueCardResponse{
		CardholderID: cardholderID,
		CardID:       cardID,
		CardToken:    cardToken,
	})
}
