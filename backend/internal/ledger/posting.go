// Package ledger implements the double-entry accounting engine for Tally.
//
// Every monetary event is recorded as a journal entry with a debit account
// and a credit account so that the books always balance.
//
// Accounting model for a group card swipe:
//
//	Debit  → member's asset account   (member now "owes" their share)
//	Credit → group clearing account   (group absorbed the merchant charge)
//
// On settlement the asset accounts are funded from tally_balance or via
// an async direct_pull from the member's linked bank.
package ledger

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	"github.com/google/uuid"
)

// EntryStatus mirrors the CHECK constraint in journal_entries.status.
type EntryStatus string

const (
	StatusPending  EntryStatus = "PENDING"
	StatusSettled  EntryStatus = "SETTLED"
	StatusReversed EntryStatus = "REVERSED"
)

// FundingType describes how a member's share will be collected.
type FundingType string

const (
	FundingTallyBalance    FundingType = "tally_balance"   // Tier 1: internal wallet
	FundingDirectPull      FundingType = "direct_pull"     // Tier 2: primary bank
	FundingSecondaryBank   FundingType = "secondary_bank"  // Tier 3: backup bank
	FundingLeaderOverwrite FundingType = "leader_overwrite" // Tier 4: leader covers shortfall
)

// SplitEntry is one member's allocation within a group transaction.
type SplitEntry struct {
	MemberID    uuid.UUID
	AccountID   uuid.UUID   // member's asset account
	AmountCents int64
	FundingType FundingType
	// LeaderMemberID is set (non-nil) when FundingType is FundingLeaderOverwrite.
	// It identifies the leader whose funds covered the shortfall.
	LeaderMemberID *uuid.UUID
}

// IOUEntry records a leader-covered shortfall that the debtor must repay.
// Rows are written to iou_entries within the same transaction as the journal entries.
type IOUEntry struct {
	DebtorMemberID   uuid.UUID // member who was short
	CreditorMemberID uuid.UUID // leader who covered
	AmountCents      int64
}

// PostPendingTransaction atomically creates PENDING journal entries for every
// member split, records each member's funding plan in funding_pulls, and
// writes any leader IOU entries that arise from Tier 4 (leader overwrite).
//
// Uses SERIALIZABLE isolation to prevent phantom reads when multiple
// authorisations arrive in quick succession for the same group.
func PostPendingTransaction(
	ctx context.Context,
	db *sql.DB,
	txnID uuid.UUID,
	groupClearingAccountID uuid.UUID,
	splits []SplitEntry,
	ious []IOUEntry,
) error {
	tx, err := db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelSerializable})
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback() //nolint:errcheck

	now := time.Now().UTC()

	const insertEntry = `
		INSERT INTO journal_entries
			(id, transaction_id, debit_account_id, credit_account_id,
			 amount_cents, status, memo, created_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
	`

	const insertFundingPull = `
		INSERT INTO funding_pulls
			(id, member_id, transaction_id, amount_cents, funding_type, status, created_at)
		VALUES ($1, $2, $3, $4, $5, 'PENDING', $6)
		ON CONFLICT (member_id, transaction_id) DO NOTHING
	`

	for _, s := range splits {
		memo := fmt.Sprintf("split allocation — txn %s", txnID)
		if _, err = tx.ExecContext(ctx, insertEntry,
			uuid.New(), txnID,
			s.AccountID,            // debit:  member owes their share
			groupClearingAccountID, // credit: group clearing account
			s.AmountCents, StatusPending, memo, now,
		); err != nil {
			return fmt.Errorf("insert journal entry (member %s): %w", s.MemberID, err)
		}

		if _, err = tx.ExecContext(ctx, insertFundingPull,
			uuid.New(), s.MemberID, txnID, s.AmountCents, string(s.FundingType), now,
		); err != nil {
			return fmt.Errorf("insert funding pull (member %s): %w", s.MemberID, err)
		}
	}

	// Write any leader IOU entries.
	const insertIOU = `
		INSERT INTO iou_entries
			(id, debtor_member_id, creditor_member_id, transaction_id,
			 amount_cents, status, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, 'OUTSTANDING', $6, $6)
	`
	for _, iou := range ious {
		if _, err = tx.ExecContext(ctx, insertIOU,
			uuid.New(), iou.DebtorMemberID, iou.CreditorMemberID, txnID, iou.AmountCents, now,
		); err != nil {
			return fmt.Errorf("insert IOU (debtor %s): %w", iou.DebtorMemberID, err)
		}
	}

	// Flip the transaction to APPROVED now that the ledger is consistent.
	const approveTxn = `
		UPDATE transactions
		SET status = 'APPROVED', updated_at = $1
		WHERE id = $2 AND status = 'PENDING'
	`
	if _, err = tx.ExecContext(ctx, approveTxn, now, txnID); err != nil {
		return fmt.Errorf("approve transaction: %w", err)
	}

	return tx.Commit()
}

// SettleTransaction marks journal entries SETTLED and, for tally_balance
// splits, deducts the amount from the member's wallet in the same transaction.
//
// direct_pull settlements are expected to be handled by a separate async
// payment-rails worker that calls this function after ACH confirmation.
func SettleTransaction(
	ctx context.Context,
	db *sql.DB,
	txnID uuid.UUID,
	splits []SplitEntry,
) error {
	tx, err := db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelSerializable})
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback() //nolint:errcheck

	now := time.Now().UTC()

	const settleEntries = `
		UPDATE journal_entries
		SET status = 'SETTLED', settled_at = $1
		WHERE transaction_id = $2 AND status = 'PENDING'
	`
	if _, err = tx.ExecContext(ctx, settleEntries, now, txnID); err != nil {
		return fmt.Errorf("settle journal entries: %w", err)
	}

	for _, s := range splits {
		if s.FundingType == FundingTallyBalance {
			// Deduct wallet balance atomically. The WHERE guard prevents
			// over-drafting if a concurrent request already deducted.
			const deduct = `
				UPDATE members
				SET    tally_balance_cents = tally_balance_cents - $1,
				       updated_at          = $2
				WHERE  id                  = $3
				  AND  tally_balance_cents >= $1
			`
			res, err := tx.ExecContext(ctx, deduct, s.AmountCents, now, s.MemberID)
			if err != nil {
				return fmt.Errorf("deduct tally_balance (member %s): %w", s.MemberID, err)
			}
			if n, _ := res.RowsAffected(); n == 0 {
				return fmt.Errorf("insufficient tally_balance for member %s", s.MemberID)
			}
		}

		const updatePull = `
			UPDATE funding_pulls
			SET status = 'COMPLETED', updated_at = $1
			WHERE member_id = $2 AND transaction_id = $3
		`
		if _, err = tx.ExecContext(ctx, updatePull, now, s.MemberID, txnID); err != nil {
			return fmt.Errorf("update funding pull (member %s): %w", s.MemberID, err)
		}
	}

	const settleTxn = `
		UPDATE transactions SET status = 'SETTLED', updated_at = $1 WHERE id = $2
	`
	if _, err = tx.ExecContext(ctx, settleTxn, now, txnID); err != nil {
		return fmt.Errorf("settle transaction: %w", err)
	}

	return tx.Commit()
}

// ReverseTransaction creates offsetting entries (swapped debit/credit) to
// unwind every split from a previously APPROVED transaction.
func ReverseTransaction(
	ctx context.Context,
	db *sql.DB,
	txnID uuid.UUID,
	groupClearingAccountID uuid.UUID,
	splits []SplitEntry,
) error {
	tx, err := db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelSerializable})
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback() //nolint:errcheck

	now := time.Now().UTC()

	const insertReversal = `
		INSERT INTO journal_entries
			(id, transaction_id, debit_account_id, credit_account_id,
			 amount_cents, status, memo, created_at)
		VALUES ($1, $2, $3, $4, $5, 'REVERSED', $6, $7)
	`

	for _, s := range splits {
		memo := fmt.Sprintf("reversal — txn %s", txnID)
		// Swap debit/credit to mirror the original entry exactly.
		if _, err = tx.ExecContext(ctx, insertReversal,
			uuid.New(), txnID,
			groupClearingAccountID, // debit:  unwind the original credit
			s.AccountID,            // credit: unwind the original debit
			s.AmountCents, memo, now,
		); err != nil {
			return fmt.Errorf("insert reversal (member %s): %w", s.MemberID, err)
		}
	}

	const reverseTxn = `
		UPDATE transactions SET status = 'REVERSED', updated_at = $1 WHERE id = $2
	`
	if _, err = tx.ExecContext(ctx, reverseTxn, now, txnID); err != nil {
		return fmt.Errorf("reverse transaction: %w", err)
	}

	return tx.Commit()
}
