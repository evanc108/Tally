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
	"fmt"
	"log/slog"
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
	"github.com/tally/backend/internal/config"
	"github.com/tally/backend/internal/ledger"
	"github.com/tally/backend/internal/plaid"
)

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

// ── Internal types ────────────────────────────────────────────────────────────

type memberRow struct {
	ID                     uuid.UUID
	AccountID              uuid.UUID // member's asset account in the ledger
	PlaidAccessToken       string
	PlaidAccountID         string
	BackupPlaidAccessToken string
	BackupPlaidAccountID   string
	TallyBalanceCents      int64
	SplitWeight            float64
	IsLeader               bool
	LeaderPreAuthorized    bool
}

type balanceResult struct {
	member           memberRow
	primaryBalance   int64
	secondaryBalance int64
	primaryErr       error
	secondaryErr     error
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
func (h *JITHandler) Authorize(c *gin.Context) {
	var req JITRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Budget 8 s total — Plaid checks + ledger write must fit inside this window
	// before the card processor times out.
	ctx, cancel := context.WithTimeout(c.Request.Context(), 8*time.Second)
	defer cancel()

	log := slog.With("idempotency_key", req.IdempotencyKey, "card_token", req.CardToken)

	// ── Step 1: Resolve card → group + members ────────────────────────────────
	groupID, members, groupAccountID, err := h.resolveCard(ctx, req.CardToken)
	if err != nil {
		log.ErrorContext(ctx, "card resolution failed", "error", err)
		c.JSON(http.StatusUnprocessableEntity, JITResponse{Decision: "DECLINE", Reason: "card_not_found"})
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
	balances := h.parallelBalanceCheck(ctx, members)

	// ── Step 4: 5-tier funding waterfall ──────────────────────────────────────
	splits, ious, approvedCents, planErr := buildFundingPlan(balances, req.AmountCents)
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

// resolveCard looks up every member in the group that owns card_token and
// returns their ledger accounts alongside the group's clearing account.
func (h *JITHandler) resolveCard(ctx context.Context, cardToken string) (
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
		JOIN accounts ma ON ma.owner_id   = m.id       AND ma.account_type = 'asset'
		JOIN accounts ga ON ga.owner_id   = m.group_id AND ga.account_type = 'liability'
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
		return uuid.Nil, nil, uuid.Nil, fmt.Errorf("rows error: %w", err)
	}
	if len(members) == 0 {
		return uuid.Nil, nil, uuid.Nil, fmt.Errorf("no members found for card_token")
	}
	return
}

// parallelBalanceCheck fans out one Goroutine per member to Plaid and collects
// all results, honouring ctx cancellation.
// If a member has a backup bank account configured, both primary and secondary
// balance checks are issued simultaneously.
func (h *JITHandler) parallelBalanceCheck(ctx context.Context, members []memberRow) []balanceResult {
	results := make([]balanceResult, len(members))
	var wg sync.WaitGroup
	wg.Add(len(members))

	for i, m := range members {
		go func(idx int, member memberRow) {
			defer wg.Done()
			r := balanceResult{member: member}

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

// buildFundingPlan applies the 5-tier waterfall to each member's balance
// and returns the splits, any leader IOU entries, and the total approved amount.
//
// approvedCents == 0 signals a full decline (every member had zero available).
// approvedCents < totalAmountCents signals a partial auth.
func buildFundingPlan(
	results []balanceResult,
	totalAmountCents int64,
) (splits []ledger.SplitEntry, ious []ledger.IOUEntry, approvedCents int64, err error) {
	// Locate the pre-authorised leader (nil if the group has no leader yet).
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
			slog.Warn("primary balance check error — treating as zero",
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
		}

		// Tier 1 — internal wallet covers the whole share.
		if wallet >= share {
			entry.FundingType = ledger.FundingTallyBalance
			splits = append(splits, entry)
			approvedCents += share
			continue
		}

		// Tier 2 — wallet + primary bank covers the whole share.
		if r.primaryErr == nil && wallet+primary >= share {
			entry.FundingType = ledger.FundingDirectPull
			splits = append(splits, entry)
			approvedCents += share
			continue
		}

		// Tier 3 — wallet + primary + secondary bank covers the whole share.
		if r.member.BackupPlaidAccountID != "" && r.secondaryErr == nil {
			if wallet+primary+secondary >= share {
				entry.FundingType = ledger.FundingSecondaryBank
				splits = append(splits, entry)
				approvedCents += share
				continue
			}
		}

		// Tier 4 — leader overwrite: leader pre-covers the shortfall (IOU recorded).
		if leader != nil && leader.member.ID != r.member.ID {
			available := wallet
			if r.primaryErr == nil {
				available += primary
			}
			if r.member.BackupPlaidAccountID != "" && r.secondaryErr == nil {
				available += secondary
			}
			shortfall := share - available
			leaderCap := leader.member.TallyBalanceCents + leader.primaryBalance
			if shortfall > 0 && leaderCap >= shortfall {
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

		// Tier 5 — partial auth: approve only what the member can actually cover.
		available := wallet
		if r.primaryErr == nil {
			available += primary
		}
		if r.member.BackupPlaidAccountID != "" && r.secondaryErr == nil {
			available += secondary
		}
		if available > share {
			available = share
		}
		if available > 0 {
			entry.AmountCents = available
			if available <= wallet {
				entry.FundingType = ledger.FundingTallyBalance
			} else {
				entry.FundingType = ledger.FundingDirectPull
			}
			splits = append(splits, entry)
		}
		approvedCents += available
	}

	return splits, ious, approvedCents, nil
}

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
