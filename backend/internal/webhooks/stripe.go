// Package webhooks handles inbound Stripe webhook events.
//
// Signature verification uses stripe.ConstructEvent() with the
// STRIPE_WEBHOOK_SECRET — NOT the custom HMAC middleware used on /v1/auth/jit.
// Using the wrong scheme would either reject all legitimate Stripe events or
// leave the endpoint completely unprotected.
package webhooks

import (
	"database/sql"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	stripe "github.com/stripe/stripe-go/v82"
	"github.com/stripe/stripe-go/v82/webhook"
	"github.com/tally/backend/internal/config"
	"github.com/tally/backend/internal/ledger"
	"github.com/tally/backend/internal/settlement"
	"github.com/tally/backend/internal/stripepayment"
	"github.com/tally/backend/internal/waterfall"
)

// StripeHandler handles all incoming Stripe webhook events.
type StripeHandler struct {
	db     *sql.DB
	stripe stripepayment.PaymentClient
	cfg    *config.Config
}

// NewStripeHandler wires dependencies.
func NewStripeHandler(db *sql.DB, stripeClient stripepayment.PaymentClient, cfg *config.Config) *StripeHandler {
	return &StripeHandler{db: db, stripe: stripeClient, cfg: cfg}
}

// ── POST /v1/webhooks/stripe/issuing-authorization ────────────────────────────
//
// Production path: Stripe Issuing sends this event when a member swipes their
// card. Same logic as /v1/auth/jit but using Stripe's native signature scheme.

// HandleIssuingAuthorization processes issuing_authorization.created events.
func (h *StripeHandler) HandleIssuingAuthorization(c *gin.Context) {
	event, ok := h.parseStripeEvent(c)
	if !ok {
		return
	}

	if event.Type != "issuing_authorization.created" {
		c.JSON(http.StatusOK, gin.H{"received": true})
		return
	}

	var auth stripe.IssuingAuthorization
	if err := json.Unmarshal(event.Data.Raw, &auth); err != nil {
		slog.Error("unmarshal issuing_authorization failed", "error", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid event data"})
		return
	}

	if auth.Amount <= 0 {
		c.JSON(http.StatusOK, gin.H{"received": true})
		return
	}

	ctx := c.Request.Context()
	cardToken := auth.Card.ID

	groupID, members, groupAccountID, err := waterfall.ResolveCard(ctx, h.db, cardToken)
	if err != nil {
		slog.Error("issuing webhook: card resolution failed", "card_id", cardToken, "error", err)
		c.JSON(http.StatusOK, gin.H{"received": true}) // return 200 so Stripe doesn't retry
		return
	}

	txnID := uuid.New()
	idempKey := auth.ID // Stripe authorization ID is globally unique

	if _, err := h.db.ExecContext(ctx, `
		INSERT INTO transactions
			(id, group_id, idempotency_key, amount_cents, currency,
			 merchant_name, status, card_token)
		VALUES ($1, $2, $3, $4, $5, $6, 'PENDING', $7)
		ON CONFLICT (idempotency_key) DO NOTHING`,
		txnID, groupID, idempKey,
		auth.Amount, string(auth.Currency),
		auth.MerchantData.Name,
		cardToken,
	); err != nil {
		slog.Error("issuing webhook: insert transaction failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}

	splits, err := waterfall.BuildFundingPlan(members, auth.Amount)
	if err != nil {
		slog.Error("issuing webhook: funding plan failed", "error", err)
		h.db.ExecContext(ctx, `UPDATE transactions SET status='DECLINED', updated_at=NOW() WHERE id=$1`, txnID) //nolint:errcheck
		c.JSON(http.StatusOK, gin.H{"received": true})
		return
	}

	if err := ledger.PostPendingTransaction(ctx, h.db, txnID, groupAccountID, splits, nil); err != nil {
		slog.Error("issuing webhook: ledger post failed", "error", err)
		h.db.ExecContext(ctx, `UPDATE transactions SET status='DECLINED', updated_at=NOW() WHERE id=$1`, txnID) //nolint:errcheck
		c.JSON(http.StatusOK, gin.H{"received": true})
		return
	}

	// Kick off settlement asynchronously.
	go func() {
		if err := settlement.SettleApprovedTransaction(ctx, h.db, h.stripe, txnID); err != nil {
			slog.Error("async settlement failed", "transaction_id", txnID, "error", err)
		}
	}()

	slog.Info("issuing webhook: approved", "transaction_id", txnID, "amount", auth.Amount)
	c.JSON(http.StatusOK, gin.H{"received": true})
}

// ── POST /v1/webhooks/stripe/reversal ─────────────────────────────────────────

// HandleReversal processes issuing_transaction.created events of type reversal.
func (h *StripeHandler) HandleReversal(c *gin.Context) {
	event, ok := h.parseStripeEvent(c)
	if !ok {
		return
	}

	if event.Type != "issuing_transaction.created" {
		c.JSON(http.StatusOK, gin.H{"received": true})
		return
	}

	var txn stripe.IssuingTransaction
	if err := json.Unmarshal(event.Data.Raw, &txn); err != nil {
		slog.Error("unmarshal issuing_transaction failed", "error", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid event data"})
		return
	}

	// Only handle refund/reversal transaction types.
	if txn.Type != stripe.IssuingTransactionTypeRefund {
		c.JSON(http.StatusOK, gin.H{"received": true})
		return
	}

	ctx := c.Request.Context()

	// Look up the original transaction by card_token + amount.
	var txnID uuid.UUID
	var groupAccountID uuid.UUID
	err := h.db.QueryRowContext(ctx, `
		SELECT t.id, a.id
		FROM transactions t
		JOIN accounts a ON a.owner_id = t.group_id AND a.account_type = 'liability'
		WHERE t.card_token = $1 AND t.status = 'APPROVED'
		ORDER BY t.created_at DESC
		LIMIT 1`,
		txn.Card.ID,
	).Scan(&txnID, &groupAccountID)
	if err == sql.ErrNoRows {
		slog.Warn("reversal: no matching APPROVED transaction found", "card_id", txn.Card.ID)
		c.JSON(http.StatusOK, gin.H{"received": true})
		return
	} else if err != nil {
		slog.Error("reversal: db lookup failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}

	// Load the splits to reverse.
	rows, err := h.db.QueryContext(ctx, `
		SELECT fp.member_id, ma.id, fp.amount_cents, fp.funding_type
		FROM funding_pulls fp
		JOIN accounts ma ON ma.owner_id = fp.member_id AND ma.account_type = 'asset'
		WHERE fp.transaction_id = $1`,
		txnID,
	)
	if err != nil {
		slog.Error("reversal: load funding pulls failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	defer rows.Close()

	var splits []ledger.SplitEntry
	for rows.Next() {
		var s ledger.SplitEntry
		var ft string
		if err := rows.Scan(&s.MemberID, &s.AccountID, &s.AmountCents, &ft); err != nil {
			slog.Error("reversal: scan failed", "error", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "scan failed"})
			return
		}
		s.FundingType = ledger.FundingType(ft)
		splits = append(splits, s)
	}

	if err := ledger.ReverseTransaction(ctx, h.db, txnID, groupAccountID, splits); err != nil {
		slog.Error("reversal: ledger reverse failed", "transaction_id", txnID, "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ledger error"})
		return
	}

	slog.Info("transaction reversed", "transaction_id", txnID)
	c.JSON(http.StatusOK, gin.H{"received": true})
}

// ── POST /v1/webhooks/stripe/identity ─────────────────────────────────────────

// HandleIdentity processes identity.verification_session.verified/failed events.
func (h *StripeHandler) HandleIdentity(c *gin.Context) {
	event, ok := h.parseStripeEvent(c)
	if !ok {
		return
	}

	var kycStatus string
	switch event.Type {
	case "identity.verification_session.verified":
		kycStatus = "approved"
	case "identity.verification_session.requires_input":
		kycStatus = "rejected"
	default:
		c.JSON(http.StatusOK, gin.H{"received": true})
		return
	}

	var session stripe.IdentityVerificationSession
	if err := json.Unmarshal(event.Data.Raw, &session); err != nil {
		slog.Error("unmarshal verification_session failed", "error", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid event data"})
		return
	}

	memberID, ok2 := session.Metadata["tally_member_id"]
	if !ok2 || memberID == "" {
		slog.Warn("identity webhook: missing tally_member_id in metadata", "session_id", session.ID)
		c.JSON(http.StatusOK, gin.H{"received": true})
		return
	}

	_, err := h.db.ExecContext(c.Request.Context(), `
		UPDATE members SET kyc_status = $1, updated_at = NOW() WHERE id = $2`,
		kycStatus, memberID,
	)
	if err != nil {
		slog.Error("identity webhook: update kyc_status failed", "member_id", memberID, "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}

	slog.Info("KYC status updated", "member_id", memberID, "kyc_status", kycStatus)
	c.JSON(http.StatusOK, gin.H{"received": true})
}

// ── Helpers ───────────────────────────────────────────────────────────────────

// parseStripeEvent reads the raw body, verifies the Stripe signature, and
// returns the parsed event. Returns false and writes the error response if
// verification fails.
func (h *StripeHandler) parseStripeEvent(c *gin.Context) (stripe.Event, bool) {
	body, err := io.ReadAll(c.Request.Body)
	if err != nil {
		slog.Error("stripe webhook: read body failed", "error", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": "read body failed"})
		return stripe.Event{}, false
	}

	sigHeader := c.GetHeader("Stripe-Signature")
	if sigHeader == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "missing Stripe-Signature header"})
		return stripe.Event{}, false
	}

	event, err := webhook.ConstructEvent(body, sigHeader, h.cfg.StripeWebhookSecret)
	if err != nil {
		slog.Warn("stripe webhook: signature verification failed", "error", err)
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid signature"})
		return stripe.Event{}, false
	}

	return event, true
}
