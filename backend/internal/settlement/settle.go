// Package settlement implements the async worker that charges each member's
// Stripe PaymentMethod after a transaction is approved by the JIT handler.
//
// Settlement is intentionally decoupled from authorization:
//  - JIT approves immediately (~20–50 ms, Postgres-only).
//  - Settlement runs right after JIT responds (or on a 30-second poll as a
//    safety net) and handles card charges, retries, and leader cover.
//
// Retry logic (per member):
//  1. Charge stripe_payment_method_id (primary).
//  2. On failure: retry primary once.
//  3. On retry failure: charge stripe_backup_payment_method_id (backup).
//  4. On both fail + valid leader authorization (within 24h):
//     a. Charge leader's stripe_payment_method_id.
//     b. Write iou_entry (debtor=member, creditor=leader).
//     c. Set funding_pull.funding_type = 'leader_overwrite'.
//  5. On all paths fail: set funding_pull.status = 'FAILED', log alert.
//
// After all members are processed, ledger.SettleTransaction() marks the
// transaction as SETTLED and the journal entries as SETTLED.
package settlement

import (
	"context"
	"database/sql"
	"fmt"
	"log/slog"
	"time"

	"github.com/google/uuid"
	"github.com/tally/backend/internal/ledger"
	"github.com/tally/backend/internal/stripepayment"
)

const leaderAuthWindow = 24 * time.Hour

// memberFunding holds the data needed to settle one member's share.
type memberFunding struct {
	MemberID                    uuid.UUID
	AccountID                   uuid.UUID
	AmountCents                 int64
	Currency                    string
	FundingType                 string
	StripePaymentMethodID       string
	StripeBackupPaymentMethodID string
}

// leaderInfo holds the group leader's payment details for cover logic.
type leaderInfo struct {
	MemberID              uuid.UUID
	StripePaymentMethodID string
	AuthorizedAt          time.Time
}

// SettleApprovedTransaction charges all members for an APPROVED transaction
// and transitions it to SETTLED (or marks individual funding_pulls as FAILED).
// It is safe to call multiple times — idempotency is handled by the
// funding_pull status check.
func SettleApprovedTransaction(ctx context.Context, db *sql.DB, stripe stripepayment.PaymentClient, txnID uuid.UUID) error {
	// Load transaction details.
	var groupID uuid.UUID
	var currency string
	var status string
	err := db.QueryRowContext(ctx,
		`SELECT group_id, currency, status FROM transactions WHERE id = $1`,
		txnID,
	).Scan(&groupID, &currency, &status)
	if err == sql.ErrNoRows {
		return fmt.Errorf("transaction %s not found", txnID)
	}
	if err != nil {
		return fmt.Errorf("load transaction: %w", err)
	}
	if status != "APPROVED" {
		slog.Info("settlement skipped — transaction not in APPROVED state",
			"transaction_id", txnID, "status", status)
		return nil
	}

	// Load pending funding pulls with member payment method info.
	rows, err := db.QueryContext(ctx, `
		SELECT
			fp.member_id,
			ma.id                                                    AS account_id,
			fp.amount_cents,
			fp.funding_type,
			COALESCE(m.stripe_payment_method_id,        '')          AS pm_id,
			COALESCE(m.stripe_backup_payment_method_id, '')          AS backup_pm_id
		FROM funding_pulls fp
		JOIN members m  ON m.id  = fp.member_id
		JOIN accounts ma ON ma.owner_id = fp.member_id AND ma.account_type = 'asset'
		WHERE fp.transaction_id = $1 AND fp.status = 'PENDING'`,
		txnID,
	)
	if err != nil {
		return fmt.Errorf("load funding pulls: %w", err)
	}
	defer rows.Close()

	var members []memberFunding
	for rows.Next() {
		var mf memberFunding
		mf.Currency = currency
		if err := rows.Scan(
			&mf.MemberID, &mf.AccountID, &mf.AmountCents, &mf.FundingType,
			&mf.StripePaymentMethodID, &mf.StripeBackupPaymentMethodID,
		); err != nil {
			return fmt.Errorf("scan funding pull: %w", err)
		}
		members = append(members, mf)
	}
	if err := rows.Err(); err != nil {
		return fmt.Errorf("funding pulls rows: %w", err)
	}
	if len(members) == 0 {
		slog.Info("settlement: no pending funding pulls", "transaction_id", txnID)
		return nil
	}

	// Load leader info for potential cover.
	var leader *leaderInfo
	var lMemberID uuid.UUID
	var lPMID string
	var lAuthAt sql.NullTime
	err = db.QueryRowContext(ctx, `
		SELECT id, COALESCE(stripe_payment_method_id, ''), leader_pre_authorized_at
		FROM members
		WHERE group_id = $1 AND is_leader = true AND leader_pre_authorized = true
		LIMIT 1`,
		groupID,
	).Scan(&lMemberID, &lPMID, &lAuthAt)
	if err == nil && lAuthAt.Valid && time.Since(lAuthAt.Time) <= leaderAuthWindow && lPMID != "" {
		leader = &leaderInfo{
			MemberID:              lMemberID,
			StripePaymentMethodID: lPMID,
			AuthorizedAt:          lAuthAt.Time,
		}
	}

	// Settle each member.
	var settledSplits []ledger.SplitEntry
	allSettled := true

	for _, mf := range members {
		charged, newFundingType, iouEntry := settleOneMember(ctx, db, stripe, txnID, mf, leader)

		if charged {
			split := ledger.SplitEntry{
				MemberID:    mf.MemberID,
				AccountID:   mf.AccountID,
				AmountCents: mf.AmountCents,
				FundingType: ledger.FundingType(newFundingType),
			}
			if newFundingType == string(ledger.FundingLeaderOverwrite) && leader != nil {
				split.LeaderMemberID = &leader.MemberID
			}
			settledSplits = append(settledSplits, split)

			// Write IOU if leader covered this member.
			if iouEntry != nil {
				if _, err := db.ExecContext(ctx, `
					INSERT INTO iou_entries
						(id, debtor_member_id, creditor_member_id, transaction_id,
						 amount_cents, status, created_at, updated_at)
					VALUES ($1, $2, $3, $4, $5, 'OUTSTANDING', NOW(), NOW())`,
					uuid.New(), iouEntry.DebtorMemberID, iouEntry.CreditorMemberID,
					txnID, iouEntry.AmountCents,
				); err != nil {
					slog.Error("failed to write IOU entry",
						"transaction_id", txnID,
						"debtor", iouEntry.DebtorMemberID,
						"error", err,
					)
				}
			}
		} else {
			allSettled = false
		}
	}

	if len(settledSplits) == 0 {
		slog.Error("settlement: all member charges failed",
			"transaction_id", txnID,
			"group_id", groupID,
		)
		return nil
	}

	// Mark ledger entries as settled.
	if err := ledger.SettleTransaction(ctx, db, txnID, settledSplits); err != nil {
		return fmt.Errorf("ledger settle: %w", err)
	}

	if allSettled {
		slog.Info("transaction settled",
			"transaction_id", txnID,
			"member_count", len(settledSplits),
		)
	} else {
		slog.Warn("transaction partially settled — some members failed",
			"transaction_id", txnID,
			"settled", len(settledSplits),
			"total", len(members),
		)
	}
	return nil
}

// settleOneMember attempts to charge a single member and returns whether the
// charge succeeded, the effective funding type, and an optional IOU entry if
// leader cover was applied.
func settleOneMember(
	ctx context.Context,
	db *sql.DB,
	stripe stripepayment.PaymentClient,
	txnID uuid.UUID,
	mf memberFunding,
	leader *leaderInfo,
) (charged bool, fundingType string, iouEntry *ledger.IOUEntry) {
	idempKey := fmt.Sprintf("settle_%s_%s", txnID, mf.MemberID)

	// Attempt primary PM.
	if mf.StripePaymentMethodID != "" {
		if _, err := stripe.ChargePaymentMethod(ctx, mf.StripePaymentMethodID, mf.AmountCents, mf.Currency, idempKey+"_primary"); err == nil {
			markFundingPull(ctx, db, mf.MemberID, txnID, "direct_pull", "COMPLETED")
			return true, "direct_pull", nil
		}
		slog.Warn("primary PM charge failed, retrying", "member_id", mf.MemberID, "transaction_id", txnID)

		// Retry primary once.
		if _, err := stripe.ChargePaymentMethod(ctx, mf.StripePaymentMethodID, mf.AmountCents, mf.Currency, idempKey+"_primary_retry"); err == nil {
			markFundingPull(ctx, db, mf.MemberID, txnID, "direct_pull", "COMPLETED")
			return true, "direct_pull", nil
		}
		slog.Warn("primary PM retry failed", "member_id", mf.MemberID, "transaction_id", txnID)
	}

	// Attempt backup PM.
	if mf.StripeBackupPaymentMethodID != "" {
		if _, err := stripe.ChargePaymentMethod(ctx, mf.StripeBackupPaymentMethodID, mf.AmountCents, mf.Currency, idempKey+"_backup"); err == nil {
			markFundingPull(ctx, db, mf.MemberID, txnID, "direct_pull", "COMPLETED")
			return true, "direct_pull", nil
		}
		slog.Warn("backup PM charge failed", "member_id", mf.MemberID, "transaction_id", txnID)
	}

	// Leader cover: charge leader's card and create IOU.
	if leader != nil && leader.MemberID != mf.MemberID {
		leaderIdempKey := fmt.Sprintf("settle_%s_%s_leader_cover", txnID, mf.MemberID)
		if _, err := stripe.ChargePaymentMethod(ctx, leader.StripePaymentMethodID, mf.AmountCents, mf.Currency, leaderIdempKey); err == nil {
			markFundingPull(ctx, db, mf.MemberID, txnID, "leader_overwrite", "COMPLETED")
			slog.Info("leader_cover_applied",
				"debtor_member_id", mf.MemberID,
				"leader_member_id", leader.MemberID,
				"amount_cents", mf.AmountCents,
				"transaction_id", txnID,
			)
			return true, "leader_overwrite", &ledger.IOUEntry{
				DebtorMemberID:   mf.MemberID,
				CreditorMemberID: leader.MemberID,
				AmountCents:      mf.AmountCents,
			}
		}
		slog.Error("leader cover charge failed",
			"leader_member_id", leader.MemberID,
			"debtor_member_id", mf.MemberID,
			"transaction_id", txnID,
		)
	}

	// All paths exhausted — mark as FAILED for ops review.
	markFundingPull(ctx, db, mf.MemberID, txnID, mf.FundingType, "FAILED")
	slog.Error("settlement failed for member — requires manual review",
		"member_id", mf.MemberID,
		"transaction_id", txnID,
		"amount_cents", mf.AmountCents,
	)
	return false, mf.FundingType, nil
}

// markFundingPull updates funding_pull.funding_type and status atomically.
func markFundingPull(ctx context.Context, db *sql.DB, memberID uuid.UUID, txnID uuid.UUID, fundingType, status string) {
	_, err := db.ExecContext(ctx, `
		UPDATE funding_pulls
		SET funding_type = $1, status = $2, updated_at = NOW()
		WHERE member_id = $3 AND transaction_id = $4`,
		fundingType, status, memberID, txnID,
	)
	if err != nil {
		slog.Error("markFundingPull failed", "member_id", memberID, "transaction_id", txnID, "error", err)
	}
}

// StartSettlementWorker runs a background goroutine that polls for APPROVED
// transactions older than 30 seconds (safety net for any goroutines that were
// missed). Call this once from main() after migrations complete.
func StartSettlementWorker(ctx context.Context, db *sql.DB, stripe stripepayment.PaymentClient) {
	go func() {
		ticker := time.NewTicker(30 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				sweepApproved(ctx, db, stripe)
			}
		}
	}()
}

// sweepApproved finds APPROVED transactions that haven't been settled and
// processes them. This handles crashes or missed goroutines.
func sweepApproved(ctx context.Context, db *sql.DB, stripe stripepayment.PaymentClient) {
	rows, err := db.QueryContext(ctx, `
		SELECT id FROM transactions
		WHERE status = 'APPROVED'
		  AND updated_at < NOW() - INTERVAL '30 seconds'
		LIMIT 50`,
	)
	if err != nil {
		slog.Error("settlement sweep query failed", "error", err)
		return
	}
	defer rows.Close()

	for rows.Next() {
		var txnID uuid.UUID
		if err := rows.Scan(&txnID); err != nil {
			continue
		}
		go func(id uuid.UUID) {
			if err := SettleApprovedTransaction(ctx, db, stripe, id); err != nil {
				slog.Error("sweep settlement failed", "transaction_id", id, "error", err)
			}
		}(txnID)
	}
}
