// Package cards implements HTTP handlers for card issuing, wallet loading,
// and the Highnote JIT authorization webhook.
package cards

import (
	"context"
	"database/sql"
	"fmt"
	"log/slog"
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
	"github.com/tally/backend/internal/config"
	"github.com/tally/backend/internal/highnote"
	"github.com/tally/backend/internal/ledger"
	"github.com/tally/backend/internal/plaid"
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

	ctx, cancel := context.WithTimeout(c.Request.Context(), 15*time.Second)
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

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
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
	ID                    string     `json:"id"`
	Type                  string     `json:"type"`
	AuthorizationRequestID string    `json:"authorizationRequestId"`
	CardID                string     `json:"cardId"`
	TransactionAmount     hnAmount   `json:"transactionAmount"`
	MerchantDetails       hnMerchant `json:"merchantDetails"`
}

type hnAuthResponse struct {
	AuthorizationResponseCode  string    `json:"authorizationResponseCode"`
	ApprovedTransactionAmount  *hnAmount `json:"approvedTransactionAmount,omitempty"`
}

// HighnoteAuthorize handles Highnote's JIT authorization webhook.
// It delegates to the same 5-tier waterfall used by /v1/auth/jit.
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

	// Budget 7 s — Highnote's webhook timeout is ~10 s; we need headroom.
	ctx, cancel := context.WithTimeout(c.Request.Context(), 7*time.Second)
	defer cancel()

	log := slog.With(
		"highnote_event_id", req.ID,
		"card_id", req.CardID,
		"amount_cents", req.TransactionAmount.Value,
	)

	// Resolve card → group + members (reuse the same SQL as the JIT handler).
	groupID, members, groupAccountID, err := h.resolveCard(ctx, req.CardID)
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
	balances := h.parallelBalanceCheck(ctx, members)

	// Run the 5-tier waterfall.
	splits, ious, approvedCents, err := buildFundingPlan(balances, req.TransactionAmount.Value)
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

// ── Shared helpers ────────────────────────────────────────────────────────────

type memberRow struct {
	ID                    uuid.UUID
	AccountID             uuid.UUID
	PlaidAccessToken      string
	PlaidAccountID        string
	BackupPlaidAccessToken string
	BackupPlaidAccountID  string
	TallyBalanceCents     int64
	SplitWeight           float64
	IsLeader              bool
	LeaderPreAuthorized   bool
}

type balanceResult struct {
	member          memberRow
	primaryBalance  int64
	secondaryBalance int64
	primaryErr      error
	secondaryErr    error
}

// resolveCard is identical to the one in auth/jit.go but lives here so the
// cards package has no import cycle with auth.
func (h *Handler) resolveCard(ctx context.Context, cardToken string) (
	groupID uuid.UUID,
	members []memberRow,
	groupAccountID uuid.UUID,
	err error,
) {
	const q = `
		SELECT
			m.id,
			ma.id                                      AS account_id,
			COALESCE(m.plaid_access_token,         '') AS plaid_access_token,
			COALESCE(m.plaid_account_id,           '') AS plaid_account_id,
			COALESCE(m.backup_plaid_access_token,  '') AS backup_plaid_access_token,
			COALESCE(m.backup_plaid_account_id,    '') AS backup_plaid_account_id,
			m.tally_balance_cents,
			m.split_weight::float8,
			m.is_leader,
			m.leader_pre_authorized,
			m.group_id,
			ga.id                                      AS group_account_id
		FROM members m
		JOIN accounts ma ON ma.owner_id = m.id       AND ma.account_type = 'asset'
		JOIN accounts ga ON ga.owner_id = m.group_id AND ga.account_type = 'liability'
		WHERE m.group_id = (
			SELECT group_id FROM members WHERE card_token = $1 LIMIT 1
		)
	`
	rows, err := h.db.QueryContext(ctx, q, cardToken)
	if err != nil {
		return uuid.Nil, nil, uuid.Nil, fmt.Errorf("query members: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var m memberRow
		var gID, gaID uuid.UUID
		if err = rows.Scan(
			&m.ID, &m.AccountID,
			&m.PlaidAccessToken, &m.PlaidAccountID,
			&m.BackupPlaidAccessToken, &m.BackupPlaidAccountID,
			&m.TallyBalanceCents, &m.SplitWeight,
			&m.IsLeader, &m.LeaderPreAuthorized,
			&gID, &gaID,
		); err != nil {
			return uuid.Nil, nil, uuid.Nil, fmt.Errorf("scan member: %w", err)
		}
		if groupID == uuid.Nil {
			groupID = gID
			groupAccountID = gaID
		}
		members = append(members, m)
	}
	if err = rows.Err(); err != nil {
		return uuid.Nil, nil, uuid.Nil, err
	}
	if len(members) == 0 {
		return uuid.Nil, nil, uuid.Nil, fmt.Errorf("no members found for card_token")
	}
	return
}

func (h *Handler) parallelBalanceCheck(ctx context.Context, members []memberRow) []balanceResult {
	results := make([]balanceResult, len(members))
	var wg sync.WaitGroup

	for i, m := range members {
		wg.Add(1)
		go func(idx int, member memberRow) {
			defer wg.Done()
			r := balanceResult{member: member}

			// Primary and secondary bank checks fan out together.
			var inner sync.WaitGroup
			inner.Add(1)
			go func() {
				defer inner.Done()
				bal, err := h.plaid.GetAccountBalance(ctx, member.PlaidAccessToken, member.PlaidAccountID)
				r.primaryBalance = bal
				r.primaryErr = err
			}()

			if member.BackupPlaidAccountID != "" {
				inner.Add(1)
				go func() {
					defer inner.Done()
					bal, err := h.plaid.GetAccountBalance(ctx, member.BackupPlaidAccessToken, member.BackupPlaidAccountID)
					r.secondaryBalance = bal
					r.secondaryErr = err
				}()
			}
			inner.Wait()
			results[idx] = r
		}(i, m)
	}

	wg.Wait()
	return results
}

// buildFundingPlan applies the 5-tier waterfall and returns splits, IOUs, and
// the total approved amount in cents. If approvedCents == 0 the entire transaction
// should be declined.
//
// Tier 1 — tally_balance (internal wallet)
// Tier 2 — primary bank pull (direct_pull)
// Tier 3 — secondary bank pull (secondary_bank)
// Tier 4 — leader overwrite + IOU (leader_overwrite)
// Tier 5 — partial auth (approve whatever is available)
func buildFundingPlan(
	results []balanceResult,
	totalAmountCents int64,
) (splits []ledger.SplitEntry, ious []ledger.IOUEntry, approvedCents int64, err error) {
	// Find the pre-authorized leader (if any) from the result set.
	var leader *balanceResult
	for i := range results {
		if results[i].member.IsLeader && results[i].member.LeaderPreAuthorized {
			leader = &results[i]
			break
		}
	}

	splits = make([]ledger.SplitEntry, 0, len(results))

	for _, r := range results {
		if r.primaryErr != nil {
			// Treat a bank check error as zero available from that source.
			slog.Warn("primary balance check failed, treating as zero",
				"member_id", r.member.ID, "error", r.primaryErr)
		}

		share := int64(float64(totalAmountCents) * r.member.SplitWeight)
		wallet := r.member.TallyBalanceCents
		primary := r.primaryBalance
		secondary := r.secondaryBalance

		entry := ledger.SplitEntry{
			MemberID:    r.member.ID,
			AccountID:   r.member.AccountID,
			AmountCents: share,
			FundingType: ledger.FundingTallyBalance,
		}

		// Tier 1: internal wallet covers the whole share.
		if wallet >= share {
			entry.FundingType = ledger.FundingTallyBalance
			splits = append(splits, entry)
			approvedCents += share
			continue
		}

		// Tier 2: wallet + primary bank covers the whole share.
		if wallet+primary >= share {
			entry.FundingType = ledger.FundingDirectPull
			splits = append(splits, entry)
			approvedCents += share
			continue
		}

		// Tier 3: wallet + primary + secondary bank covers the whole share.
		if r.member.BackupPlaidAccountID != "" && r.secondaryErr == nil &&
			wallet+primary+secondary >= share {
			entry.FundingType = ledger.FundingSecondaryBank
			splits = append(splits, entry)
			approvedCents += share
			continue
		}

		// Tier 4: leader covers the shortfall.
		if leader != nil && leader.member.ID != r.member.ID {
			available := wallet + primary
			if r.member.BackupPlaidAccountID != "" && r.secondaryErr == nil {
				available += secondary
			}
			shortfall := share - available
			leaderAvailable := leader.member.TallyBalanceCents + leader.primaryBalance
			if leaderAvailable >= shortfall {
				leaderID := leader.member.ID
				entry.FundingType = ledger.FundingLeaderOverwrite
				entry.LeaderMemberID = &leaderID
				splits = append(splits, entry)
				ious = append(ious, ledger.IOUEntry{
					DebtorMemberID:   r.member.ID,
					CreditorMemberID: leader.member.ID,
					AmountCents:      shortfall,
				})
				approvedCents += share
				continue
			}
		}

		// Tier 5: partial auth — approve only what the member actually has.
		available := wallet + primary
		if r.member.BackupPlaidAccountID != "" && r.secondaryErr == nil {
			available += secondary
		}
		if available > share {
			available = share
		}
		if available > 0 {
			entry.AmountCents = available
			entry.FundingType = ledger.FundingDirectPull
			if available <= wallet {
				entry.FundingType = ledger.FundingTallyBalance
			}
			splits = append(splits, entry)
		}
		approvedCents += available
	}

	return splits, ious, approvedCents, nil
}

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
