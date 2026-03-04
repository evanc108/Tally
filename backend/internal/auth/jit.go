// Package auth implements the Just-In-Time card authorization handler.
//
// Flow overview:
//  1. Card processor → POST /v1/auth/jit  (HMAC-verified, idempotent)
//  2. Resolve card_token → group + all member rows  (Postgres, single query)
//  3. Verify every member has a stripe_payment_method_id (bank account)  (data integrity check)
//  4. Build funding plan  → direct_pull for every member
//  5. Post PENDING ledger entries atomically
//  6. Respond APPROVE (or DECLINE if any step fails)
//
// No external API calls are made in this handler. All data needed for the
// authorization decision is in Postgres. The 2-second Stripe deadline is met
// with a 40× safety margin (~20–50 ms actual latency).
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
	"github.com/tally/backend/internal/waterfall"
)

// jitTimeout is the total budget for a JIT authorization. With Postgres-only
// logic (~20–50 ms), this leaves a 30× safety margin inside Stripe's 2-second
// window.
const jitTimeout = 1500 * time.Millisecond

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
	Decision      string `json:"decision"`                  // "APPROVE" | "DECLINE"
	TransactionID string `json:"transaction_id,omitempty"`  // populated on APPROVE
	Reason        string `json:"reason,omitempty"`          // populated on DECLINE
}

// ── Handler ───────────────────────────────────────────────────────────────────

// JITHandler handles POST /v1/auth/jit.
type JITHandler struct {
	db  *sql.DB
	rdb *redis.Client
	cfg *config.Config
}

func NewJITHandler(db *sql.DB, rdb *redis.Client, cfg *config.Config) *JITHandler {
	return &JITHandler{db: db, rdb: rdb, cfg: cfg}
}

// Authorize is the core JIT authorization logic.
//
// @Summary      JIT card authorization
// @Description  Generic card-processor JIT authorization endpoint. Verifies all members have a linked payment method and writes PENDING ledger entries. Returns APPROVE or DECLINE. Requires X-Tally-Signature and Idempotency-Key headers.
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

	// ── Step 3: Build direct_pull funding plan for every member ──────────────
	// BuildFundingPlan returns an error if any member is missing a payment
	// method — enforced at join time, so this is a data-integrity assertion.
	splits, err := waterfall.BuildFundingPlan(members, req.AmountCents)
	if err != nil {
		log.ErrorContext(ctx, "funding plan failed", "error", err)
		_ = h.setTransactionStatus(ctx, txnID, "DECLINED")
		c.JSON(http.StatusOK, JITResponse{Decision: "DECLINE", Reason: "card_not_linked"})
		return
	}

	// ── Step 4: Atomically post PENDING journal entries ───────────────────────
	if err := ledger.PostPendingTransaction(ctx, h.db, txnID, groupAccountID, splits, nil); err != nil {
		log.ErrorContext(ctx, "ledger post failed", "error", err)
		_ = h.setTransactionStatus(ctx, txnID, "DECLINED")
		c.JSON(http.StatusInternalServerError, JITResponse{Decision: "DECLINE", Reason: "ledger_error"})
		return
	}

	log.InfoContext(ctx, "JIT approved",
		"transaction_id", txnID,
		"amount_cents", req.AmountCents,
		"member_count", len(members),
	)

	c.JSON(http.StatusOK, JITResponse{
		Decision:      "APPROVE",
		TransactionID: txnID.String(),
	})
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
