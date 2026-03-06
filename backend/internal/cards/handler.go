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
	"github.com/tally/backend/internal/middleware"
	"github.com/tally/backend/internal/stripeissuing"
)

const issueCardTimeout = 15 * time.Second

// cardIssuerErrorResponse returns a 502 body. In non-production, includes "detail" with the underlying error.
func cardIssuerErrorResponse(err error, env string) gin.H {
	resp := gin.H{"error": "card issuer unavailable"}
	if env != "production" && err != nil {
		resp["detail"] = err.Error()
	}
	return resp
}

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
	MemberID     string `json:"member_id"     binding:"required"`
	FirstName    string `json:"first_name"    binding:"required"`
	LastName     string `json:"last_name"     binding:"required"`
	Email        string `json:"email"         binding:"required"`
	DOB          *struct {
		Day   int `json:"day"   binding:"required,min=1,max=31"`
		Month int `json:"month" binding:"required,min=1,max=12"`
		Year  int `json:"year"  binding:"required,min=1900,max=2100"`
	} `json:"dob" binding:"required"`
	// UserTermsAcceptedAt is the Unix timestamp when the user accepted Authorized User Terms (required for Celtic programs).
	UserTermsAcceptedAt *int64 `json:"user_terms_accepted_at"`
	AddressLine1        string `json:"address_line1"`
	City                string `json:"city"`
	State               string `json:"state"`
	PostalCode          string `json:"postal_code"`
	Country             string `json:"country"`
}

type issueCardResponse struct {
	CardholderID string `json:"cardholder_id"`
	CardID       string `json:"card_id"`
	CardToken    string `json:"card_token"`
}

// IssueCard creates a Stripe Issuing cardholder and virtual card for a member.
// Requires the member to have passed KYC (kyc_status = 'approved') and to be
// owned by the authenticated user.
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

	// Ownership check: the authenticated user must own this member row.
	callerID, ok := c.Get(middleware.ClerkUserIDKey)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "missing_user_identity"})
		return
	}
	userID, ok := callerID.(string)
	if !ok || userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "missing_user_identity"})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), issueCardTimeout)
	defer cancel()

	// Gate on KYC approval and ownership before issuing a card.
	var kycStatus string
	err = h.db.QueryRowContext(ctx,
		`SELECT kyc_status FROM members WHERE id = $1 AND user_id = $2`, memberID, userID,
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
	if req.DOB == nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "dob is required"})
		return
	}

	// 1. Reuse an existing Stripe cardholder for this member if one exists with no
	//    outstanding requirements (Stripe API: Requirements.PastDue empty); otherwise create new.
	cardholderID, err := h.issuing.FindCardholderByMemberID(ctx, memberID.String())
	if err != nil {
		slog.ErrorContext(ctx, "FindCardholderByMemberID failed", "member_id", memberID, "error", err)
		c.JSON(http.StatusBadGateway, cardIssuerErrorResponse(err, h.cfg.Environment))
		return
	}
	if cardholderID == "" {
		creq := stripeissuing.CreateCardholderRequest{
			ExternalID:   memberID.String(),
			FirstName:    req.FirstName,
			LastName:     req.LastName,
			Email:        req.Email,
			DOBDay:       req.DOB.Day,
			DOBMonth:     req.DOB.Month,
			DOBYear:      req.DOB.Year,
			AddressLine1: req.AddressLine1,
			City:         req.City,
			State:        req.State,
			PostalCode:   req.PostalCode,
			Country:      req.Country,
			ClientIP:     c.ClientIP(),
			UserAgent:    c.GetHeader("User-Agent"),
		}
		if req.UserTermsAcceptedAt != nil {
			creq.UserTermsAcceptedAt = req.UserTermsAcceptedAt
		}
		cardholderID, err = h.issuing.CreateCardholder(ctx, creq)
		if err != nil {
			slog.ErrorContext(ctx, "CreateCardholder failed", "member_id", memberID, "error", err)
			c.JSON(http.StatusBadGateway, cardIssuerErrorResponse(err, h.cfg.Environment))
			return
		}
	}

	// 2. Issue a virtual card.
	cardID, cardToken, err := h.issuing.IssueCard(ctx, cardholderID, h.cfg.StripeIssuingCardProduct)
	if err != nil {
		slog.ErrorContext(ctx, "IssueCard failed", "member_id", memberID, "error", err)
		c.JSON(http.StatusBadGateway, cardIssuerErrorResponse(err, h.cfg.Environment))
		return
	}

	// 3. Persist: INSERT into cards (trigger syncs to members.card_token for JIT).
	// If the cards table does not exist (older migrations only), fall back to UPDATE members.
	const insertCards = `
		INSERT INTO cards (member_id, user_id, card_token, stripe_cardholder_id, stripe_card_id, status, is_primary)
		VALUES ($1, $2, $3, $4, $5, 'active', TRUE)
	`
	_, err = h.db.ExecContext(ctx, insertCards, memberID, userID, cardToken, cardholderID, cardID)
	if err != nil {
		// Fallback: update members directly (pre-000015 schema or trigger missing).
		const updateMembers = `
			UPDATE members
			SET stripe_cardholder_id = $1, stripe_card_id = $2, card_token = $3, updated_at = NOW()
			WHERE id = $4 AND user_id = $5
		`
		res, upErr := h.db.ExecContext(ctx, updateMembers, cardholderID, cardID, cardToken, memberID, userID)
		if upErr != nil {
			slog.ErrorContext(ctx, "card persist failed", "member_id", memberID, "error", err, "fallback_error", upErr)
			body := gin.H{"error": "db write failed"}
			if h.cfg.Environment != "production" {
				body["insert_error"] = err.Error()
				body["fallback_error"] = upErr.Error()
			}
			c.JSON(http.StatusInternalServerError, body)
			return
		}
		if n, _ := res.RowsAffected(); n == 0 {
			c.JSON(http.StatusNotFound, gin.H{"error": "member not found"})
			return
		}
	}

	slog.InfoContext(ctx, "card issued", "member_id", memberID, "card_id", cardID)
	c.JSON(http.StatusCreated, issueCardResponse{
		CardholderID: cardholderID,
		CardID:       cardID,
		CardToken:    cardToken,
	})
}
