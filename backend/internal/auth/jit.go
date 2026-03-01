// Package auth implements the Just-In-Time card authorization handler.
//
// Flow overview:
//  1. Card processor → POST /v1/auth/jit  (HMAC-verified, idempotent)
//  2. Resolve card_token → group + all member rows
//  3. Fan out Goroutines → parallel Plaid balance checks (primary + secondary bank)
//  4. Build funding plan  → 5-tier fallback waterfall
//  5. If every member can contribute something → APPROVE + post PENDING ledger entries
//  6. Otherwise                                → DECLINE
//
// Funding waterfall (per member):
//   Tier 1 — tally_balance (internal wallet)
//   Tier 2 — primary bank pull (direct_pull via Plaid)
//   Tier 3 — secondary / backup bank pull (secondary_bank via Plaid)
//   Tier 4 — leader overwrite: the pre-authorised leader covers the shortfall + IOU
//   Tier 5 — partial auth: approve only what is actually available
package auth

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
	"github.com/tally/backend/internal/ledger"
	"github.com/tally/backend/internal/plaid"
	"github.com/tally/backend/internal/waterfall"
)

// jitTimeout is the total budget for a JIT authorization — Plaid checks +
// ledger write must complete before the card processor times out.
const jitTimeout = 8 * time.Second

// ── Request / Response ────────────────────────────────────────────────────────

// JITRequest is the payload the card processor sends on every swipe.
type JITRequest struct {
	// IdempotencyKey must also be sent in the Idempotency-Key header so the
	// middleware can deduplicate without parsing the body.
	IdempotencyKey   string `json:"idempotency_key"   binding:"required"`
	CardToken        string `json:"card_token"        binding:"required"`
	AmountCents      int64  `json:"amount_cents"      binding:"required,gt=0"`
	Currency         string `json:"currency"          binding:"required,len=3"`
	MerchantName     string `json:"merchant_name"`
	MerchantCategory string `json:"merchant_category"`
}

// JITResponse is returned to the card processor.
type JITResponse struct {
	Decision            string `json:"decision"`                        // "APPROVE" | "DECLINE"
	TransactionID       string `json:"transaction_id,omitempty"`        // populated on APPROVE
	ApprovedAmountCents int64  `json:"approved_amount_cents,omitempty"` // < requested when partial
	Reason              string `json:"reason,omitempty"`                // populated on DECLINE
}

// ── Handler ───────────────────────────────────────────────────────────────────

// JITHandler handles POST /v1/auth/jit.
type JITHandler struct {
	db    *sql.DB
	rdb   *redis.Client
	plaid plaid.BalanceClient
	cfg   *config.Config
}

func NewJITHandler(db *sql.DB, rdb *redis.Client, cfg *config.Config, pl plaid.BalanceClient) *JITHandler {
	return &JITHandler{
		db:    db,
		rdb:   rdb,
		plaid: pl,
		cfg:   cfg,
	}
}

// Authorize is the core JIT authorization logic.
//
// @Summary      JIT card authorization
// @Description  Generic card-processor JIT authorization endpoint. Runs the 5-tier funding waterfall and returns APPROVE or DECLINE. Requires X-Tally-Signature and Idempotency-Key headers.
// @Tags         auth
// @Accept       json
// @Produce      json
// @Param        X-Tally-Signature header string     true "HMAC-SHA256 signature: sha256=<hex>"
// @Param        Idempotency-Key   header string     true "Unique key to deduplicate retries"
// @Param        body              body   JITRequest true "Authorization request"
// @Success      200 {object} JITResponse
// @Failure      400 {object} map[string]string
// @Failure      422 {object} JITResponse
// @Router       /v1/auth/jit [post]
func (h *JITHandler) Authorize(c *gin.Context) {
	var req JITRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), jitTimeout)
	defer cancel()

	log := slog.With("idempotency_key", req.IdempotencyKey, "card_token", req.CardToken)

	// ── Step 1: Resolve card → group + members ────────────────────────────────
	groupID, members, groupAccountID, err := waterfall.ResolveCard(ctx, h.db, req.CardToken)
	if err != nil {
		log.ErrorContext(ctx, "card resolution failed", "error", err)
		// Use a generic reason to avoid leaking whether a given card token exists.
		c.JSON(http.StatusUnprocessableEntity, JITResponse{Decision: "DECLINE", Reason: "authorization_failed"})
		return
	}

	// ── Step 2: Create PENDING transaction (DB constraint guards idempotency) ──
	txnID := uuid.New()
	if err := h.insertPendingTransaction(ctx, txnID, groupID, req); err != nil {
		log.ErrorContext(ctx, "insert pending transaction failed", "error", err)
		c.JSON(http.StatusInternalServerError, JITResponse{Decision: "DECLINE", Reason: "internal_error"})
		return
	}

	// ── Step 3: Parallel Plaid balance checks (primary + secondary) ───────────
	balances := waterfall.ParallelBalanceCheck(ctx, h.plaid, members)

	// ── Step 4: 5-tier funding waterfall ──────────────────────────────────────
	splits, ious, approvedCents, planErr := waterfall.BuildFundingPlan(balances, req.AmountCents)
	if planErr != nil || approvedCents == 0 {
		reason := "insufficient_funds"
		if planErr != nil {
			log.ErrorContext(ctx, "funding plan error", "error", planErr)
			reason = "balance_check_error"
		}
		_ = h.setTransactionStatus(ctx, txnID, "DECLINED")
		c.JSON(http.StatusOK, JITResponse{Decision: "DECLINE", Reason: reason})
		return
	}

	// ── Step 5: Atomically post PENDING journal entries ───────────────────────
	if err := ledger.PostPendingTransaction(ctx, h.db, txnID, groupAccountID, splits, ious); err != nil {
		log.ErrorContext(ctx, "ledger post failed", "error", err)
		_ = h.setTransactionStatus(ctx, txnID, "DECLINED")
		c.JSON(http.StatusInternalServerError, JITResponse{Decision: "DECLINE", Reason: "ledger_error"})
		return
	}

	log.InfoContext(ctx, "JIT approved",
		"transaction_id", txnID,
		"requested_cents", req.AmountCents,
		"approved_cents", approvedCents,
		"iou_count", len(ious),
	)

	resp := JITResponse{
		Decision:      "APPROVE",
		TransactionID: txnID.String(),
	}
	// Only set ApprovedAmountCents when it differs from the requested amount
	// (i.e., a partial auth occurred).
	if approvedCents < req.AmountCents {
		resp.ApprovedAmountCents = approvedCents
	}
	c.JSON(http.StatusOK, resp)
}

// ── Helpers ───────────────────────────────────────────────────────────────────

func (h *JITHandler) insertPendingTransaction(ctx context.Context, txnID, groupID uuid.UUID, req JITRequest) error {
	const q = `
		INSERT INTO transactions
			(id, group_id, idempotency_key, amount_cents, currency,
			 merchant_name, merchant_category, status, card_token)
		VALUES ($1, $2, $3, $4, $5, $6, $7, 'PENDING', $8)
	`
	_, err := h.db.ExecContext(ctx, q,
		txnID, groupID, req.IdempotencyKey, req.AmountCents, req.Currency,
		req.MerchantName, req.MerchantCategory, req.CardToken,
	)
	return err
}

func (h *JITHandler) setTransactionStatus(ctx context.Context, txnID uuid.UUID, status string) error {
	_, err := h.db.ExecContext(ctx,
		`UPDATE transactions SET status = $1, updated_at = NOW() WHERE id = $2`,
		status, txnID,
	)
	return err
}
