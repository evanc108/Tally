// Package cards implements HTTP handlers for card issuing, wallet loading,
// and the Highnote JIT authorization webhook.
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
	"github.com/tally/backend/internal/highnote"
	"github.com/tally/backend/internal/ledger"
	"github.com/tally/backend/internal/plaid"
	"github.com/tally/backend/internal/waterfall"
)

const (
	issueCardTimeout    = 15 * time.Second
	loadWalletTimeout   = 10 * time.Second
	highnoteAuthTimeout = 7 * time.Second // Highnote webhook timeout is ~10 s; leave headroom
)

// Handler handles card-issuing and wallet-loading routes.
type Handler struct {
	db       *sql.DB
	rdb      *redis.Client
	cfg      *config.Config
	highnote highnote.CardIssuingClient
	plaid    plaid.BalanceClient
}

// NewHandler wires dependencies. Pass highnote.NewMockClient() in development.
func NewHandler(
	db *sql.DB,
	rdb *redis.Client,
	cfg *config.Config,
	hn highnote.CardIssuingClient,
	pl plaid.BalanceClient,
) *Handler {
	return &Handler{db: db, rdb: rdb, cfg: cfg, highnote: hn, plaid: pl}
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

// IssueCard creates a Highnote cardholder and virtual card for a member,
// then stores the identifiers in the members table.
//
// @Summary      Issue a virtual card
// @Description  Creates a Highnote cardholder and virtual card for a member. The returned card_token is used to identify the card in JIT authorization webhooks.
// @Tags         cards
// @Accept       json
// @Produce      json
// @Param        body body issueCardRequest true "Member identity"
// @Success      201  {object} issueCardResponse
// @Failure      400  {object} map[string]string
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

	// 1. Create cardholder in Highnote.
	cardholderID, err := h.highnote.CreateCardholder(ctx, highnote.CreateCardholderRequest{
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
	cardID, cardToken, err := h.highnote.IssueCard(ctx, cardholderID, h.cfg.HighnoteCardProductID)
	if err != nil {
		slog.ErrorContext(ctx, "IssueCard failed", "member_id", memberID, "error", err)
		c.JSON(http.StatusBadGateway, gin.H{"error": "card issuer unavailable"})
		return
	}

	// 3. Persist to the members row.
	const q = `
		UPDATE members
		SET highnote_cardholder_id = $1,
		    highnote_card_id       = $2,
		    card_token             = $3,
		    updated_at             = NOW()
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

// ── POST /v1/wallets/load ────────────────────────────────────────────────────

type loadWalletRequest struct {
	MemberID    string `json:"member_id"    binding:"required"`
	AmountCents int64  `json:"amount_cents" binding:"required,gt=0"`
}

type loadWalletResponse struct {
	NewBalanceCents int64 `json:"new_balance_cents"`
}

// LoadWallet credits a member's Tally wallet and syncs the balance in Highnote.
//
// @Summary      Load a member's wallet
// @Description  Credits a member's Tally wallet balance (Tier 1 funding source). Also syncs the load to Highnote on a best-effort basis.
// @Tags         cards
// @Accept       json
// @Produce      json
// @Param        body body loadWalletRequest true "Load details"
// @Success      200  {object} loadWalletResponse
// @Failure      400  {object} map[string]string
// @Failure      404  {object} map[string]string
// @Failure      500  {object} map[string]string
// @Router       /v1/wallets/load [post]
func (h *Handler) LoadWallet(c *gin.Context) {
	var req loadWalletRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	memberID, err := uuid.Parse(req.MemberID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid member_id"})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), loadWalletTimeout)
	defer cancel()

	// Fetch the cardholder ID and current balance in one query.
	var cardholderID string
	var newBalance int64
	const q = `
		UPDATE members
		SET tally_balance_cents = tally_balance_cents + $1,
		    updated_at          = NOW()
		WHERE id = $2
		RETURNING tally_balance_cents, COALESCE(highnote_cardholder_id, '')
	`
	if err := h.db.QueryRowContext(ctx, q, req.AmountCents, memberID).
		Scan(&newBalance, &cardholderID); err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "member not found"})
		return
	} else if err != nil {
		slog.ErrorContext(ctx, "wallet load DB update failed", "member_id", memberID, "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db write failed"})
		return
	}

	// Mirror the load in Highnote (best-effort — DB is the source of truth).
	if cardholderID != "" {
		if err := h.highnote.LoadWallet(ctx, cardholderID, req.AmountCents); err != nil {
			// Log but do not fail — Highnote is kept in sync on a best-effort basis.
			slog.WarnContext(ctx, "Highnote wallet sync failed", "member_id", memberID, "error", err)
		}
	}

	slog.InfoContext(ctx, "wallet loaded",
		"member_id", memberID,
		"amount_cents", req.AmountCents,
		"new_balance_cents", newBalance,
	)
	c.JSON(http.StatusOK, loadWalletResponse{NewBalanceCents: newBalance})
}

// ── POST /v1/webhooks/highnote/authorization ─────────────────────────────────
//
// Highnote sends this webhook when a card is swiped. We must respond within
// ~2 s with APPROVED or DO_NOT_HONOR (plus an optional partial amount).

type hnAmount struct {
	Value        int64  `json:"value"`
	CurrencyCode string `json:"currencyCode"`
}

type hnMerchant struct {
	Name         string `json:"name"`
	CategoryCode string `json:"categoryCode"`
}

type hnAuthRequest struct {
	ID                     string     `json:"id"`
	Type                   string     `json:"type"`
	AuthorizationRequestID string     `json:"authorizationRequestId"`
	CardID                 string     `json:"cardId"`
	TransactionAmount      hnAmount   `json:"transactionAmount"`
	MerchantDetails        hnMerchant `json:"merchantDetails"`
}

type hnAuthResponse struct {
	AuthorizationResponseCode string    `json:"authorizationResponseCode"`
	ApprovedTransactionAmount *hnAmount `json:"approvedTransactionAmount,omitempty"`
}

// HighnoteAuthorize handles Highnote's JIT authorization webhook.
// It delegates to the same 5-tier waterfall used by /v1/auth/jit.
//
// @Summary      Highnote JIT authorization webhook
// @Description  Receives Highnote card authorization events and runs the 5-tier funding waterfall (Tally balance → primary bank → secondary bank → leader overwrite → partial auth). Requires X-Tally-Signature and Idempotency-Key headers.
// @Tags         webhooks
// @Accept       json
// @Produce      json
// @Param        X-Tally-Signature header string true  "HMAC-SHA256 signature: sha256=<hex>"
// @Param        Idempotency-Key   header string true  "Unique key to deduplicate retries"
// @Param        body              body   hnAuthRequest true "Highnote authorization event"
// @Success      200  {object} hnAuthResponse
// @Failure      400  {object} map[string]string
// @Router       /v1/webhooks/highnote/authorization [post]
func (h *Handler) HighnoteAuthorize(c *gin.Context) {
	var req hnAuthRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		// Highnote retries on 5xx; return 400 for malformed payloads.
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if req.TransactionAmount.Value <= 0 {
		c.JSON(http.StatusOK, hnAuthResponse{AuthorizationResponseCode: "DO_NOT_HONOR"})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), highnoteAuthTimeout)
	defer cancel()

	log := slog.With(
		"highnote_event_id", req.ID,
		"card_id", req.CardID,
		"amount_cents", req.TransactionAmount.Value,
	)

	// Resolve card → group + members.
	groupID, members, groupAccountID, err := waterfall.ResolveCard(ctx, h.db, req.CardID)
	if err != nil {
		log.ErrorContext(ctx, "card resolution failed", "error", err)
		c.JSON(http.StatusOK, hnAuthResponse{AuthorizationResponseCode: "DO_NOT_HONOR"})
		return
	}

	// Create a PENDING transaction row.
	txnID := uuid.New()
	idempotencyKey := req.AuthorizationRequestID
	if idempotencyKey == "" {
		idempotencyKey = req.ID
	}
	if err := h.insertPendingTransaction(ctx, txnID, groupID, idempotencyKey, req); err != nil {
		log.ErrorContext(ctx, "insert pending transaction failed", "error", err)
		c.JSON(http.StatusOK, hnAuthResponse{AuthorizationResponseCode: "DO_NOT_HONOR"})
		return
	}

	// Fan out balance checks.
	balances := waterfall.ParallelBalanceCheck(ctx, h.plaid, members)

	// Run the 5-tier waterfall.
	splits, ious, approvedCents, err := waterfall.BuildFundingPlan(balances, req.TransactionAmount.Value)
	if err != nil || approvedCents == 0 {
		reason := "insufficient_funds"
		if err != nil {
			log.ErrorContext(ctx, "funding plan error", "error", err)
			reason = "balance_check_error"
		}
		_ = h.setTransactionStatus(ctx, txnID, "DECLINED")
		log.InfoContext(ctx, "JIT declined", "reason", reason)
		c.JSON(http.StatusOK, hnAuthResponse{AuthorizationResponseCode: "DO_NOT_HONOR"})
		return
	}

	// Post ledger entries.
	if err := ledger.PostPendingTransaction(ctx, h.db, txnID, groupAccountID, splits, ious); err != nil {
		log.ErrorContext(ctx, "ledger post failed", "error", err)
		_ = h.setTransactionStatus(ctx, txnID, "DECLINED")
		c.JSON(http.StatusOK, hnAuthResponse{AuthorizationResponseCode: "DO_NOT_HONOR"})
		return
	}

	log.InfoContext(ctx, "Highnote JIT approved",
		"transaction_id", txnID,
		"requested_cents", req.TransactionAmount.Value,
		"approved_cents", approvedCents,
		"iou_count", len(ious),
	)

	c.JSON(http.StatusOK, hnAuthResponse{
		AuthorizationResponseCode: "APPROVED",
		ApprovedTransactionAmount: &hnAmount{
			Value:        approvedCents,
			CurrencyCode: req.TransactionAmount.CurrencyCode,
		},
	})
}

// ── Helpers ───────────────────────────────────────────────────────────────────

func (h *Handler) insertPendingTransaction(
	ctx context.Context,
	txnID, groupID uuid.UUID,
	idempotencyKey string,
	req hnAuthRequest,
) error {
	const q = `
		INSERT INTO transactions
			(id, group_id, idempotency_key, amount_cents, currency,
			 merchant_name, merchant_category, status, card_token)
		VALUES ($1, $2, $3, $4, $5, $6, $7, 'PENDING', $8)
		ON CONFLICT (idempotency_key) DO NOTHING
	`
	_, err := h.db.ExecContext(ctx, q,
		txnID, groupID, idempotencyKey,
		req.TransactionAmount.Value, req.TransactionAmount.CurrencyCode,
		req.MerchantDetails.Name, req.MerchantDetails.CategoryCode,
		req.CardID,
	)
	return err
}

func (h *Handler) setTransactionStatus(ctx context.Context, txnID uuid.UUID, status string) error {
	_, err := h.db.ExecContext(ctx,
		`UPDATE transactions SET status = $1, updated_at = NOW() WHERE id = $2`,
		status, txnID,
	)
	return err
}
