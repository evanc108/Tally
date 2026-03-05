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
	"strings"
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
	FundingTallyBalance    FundingType = "tally_balance"    // Tier 1: internal wallet
	FundingDirectPull      FundingType = "direct_pull"      // Tier 2: primary card
	FundingSecondaryBank   FundingType = "secondary_bank"   // Tier 3: backup bank (legacy)
	FundingLeaderOverwrite FundingType = "leader_overwrite" // Tier 4: leader covers shortfall
)

// SplitEntry is one member's allocation within a group transaction.
type SplitEntry struct {
	MemberID    uuid.UUID
	AccountID   uuid.UUID   // member's asset account
	AmountCents int64
	FundingType FundingType
	// LeaderMemberID is set (non-nil) when FundingType is FundingLeaderOverwrite.
	LeaderMemberID *uuid.UUID
}

// IOUEntry records a leader-covered shortfall that the debtor must repay.
type IOUEntry struct {
	DebtorMemberID   uuid.UUID
	CreditorMemberID uuid.UUID
	AmountCents      int64
}

// PostPendingTransaction atomically creates PENDING journal entries for every
// member split and records each member's funding plan in funding_pulls.
//
// Uses SERIALIZABLE isolation to prevent phantom reads when multiple
// authorisations arrive in quick succession for the same group.
//
// journal_entries and funding_pulls are written as single multi-row INSERTs
// to minimise lock hold time.
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

	if len(splits) > 0 {
		// ── Bulk insert journal_entries ───────────────────────────────────────
		entryArgs := make([]interface{}, 0, len(splits)*8)
		entryPlaceholders := make([]string, 0, len(splits))
		for i, s := range splits {
			base := i * 8
			memo := fmt.Sprintf("split allocation — txn %s", txnID)
			entryPlaceholders = append(entryPlaceholders,
				fmt.Sprintf("($%d::uuid,$%d::uuid,$%d::uuid,$%d::uuid,$%d::bigint,$%d::text,$%d::text,$%d::timestamptz)", base+1, base+2, base+3, base+4, base+5, base+6, base+7, base+8),
			)
			entryArgs = append(entryArgs,
				uuid.New(), txnID,
				s.AccountID,            // debit:  member owes their share
				groupClearingAccountID, // credit: group clearing account
				s.AmountCents, string(StatusPending), memo, now,
			)
		}

		entrySQL := `INSERT INTO journal_entries
			(id, transaction_id, debit_account_id, credit_account_id,
			 amount_cents, status, memo, created_at)
			VALUES ` + strings.Join(entryPlaceholders, ", ")
		if _, err = tx.ExecContext(ctx, entrySQL, entryArgs...); err != nil {
			return fmt.Errorf("bulk insert journal entries: %w", err)
		}

		// ── Bulk insert funding_pulls ─────────────────────────────────────────
		pullArgs := make([]interface{}, 0, len(splits)*6)
		pullPlaceholders := make([]string, 0, len(splits))
		for i, s := range splits {
			base := i * 6
		pullPlaceholders = append(pullPlaceholders,
			fmt.Sprintf("($%d::uuid,$%d::uuid,$%d::uuid,$%d::bigint,$%d::text,$%d::timestamptz)", base+1, base+2, base+3, base+4, base+5, base+6),
		)
			pullArgs = append(pullArgs,
				uuid.New(), s.MemberID, txnID, s.AmountCents, string(s.FundingType), now,
			)
		}

		pullSQL := `INSERT INTO funding_pulls
			(id, member_id, transaction_id, amount_cents, funding_type, status, created_at)
			SELECT id, member_id, transaction_id, amount_cents, funding_type, 'PENDING', created_at
			FROM (VALUES ` + strings.Join(pullPlaceholders, ", ") + `) AS v(id, member_id, transaction_id, amount_cents, funding_type, created_at)
			ON CONFLICT (member_id, transaction_id) DO NOTHING`
		if _, err = tx.ExecContext(ctx, pullSQL, pullArgs...); err != nil {
			return fmt.Errorf("bulk insert funding pulls: %w", err)
		}
	}

	// ── Insert any leader IOU entries ─────────────────────────────────────────
	for _, iou := range ious {
		if _, err = tx.ExecContext(ctx, `
			INSERT INTO iou_entries
				(id, debtor_member_id, creditor_member_id, transaction_id,
				 amount_cents, status, created_at, updated_at)
			VALUES ($1, $2, $3, $4, $5, 'OUTSTANDING', $6, $6)`,
			uuid.New(), iou.DebtorMemberID, iou.CreditorMemberID, txnID, iou.AmountCents, now,
		); err != nil {
			return fmt.Errorf("insert IOU (debtor %s): %w", iou.DebtorMemberID, err)
		}
	}

	// Flip the transaction to APPROVED.
	if _, err = tx.ExecContext(ctx,
		`UPDATE transactions SET status = 'APPROVED', updated_at = $1 WHERE id = $2 AND status = 'PENDING'`,
		now, txnID,
	); err != nil {
		return fmt.Errorf("approve transaction: %w", err)
	}

	return tx.Commit()
}

// SettleTransaction marks journal entries SETTLED and, for tally_balance
// splits, deducts the amount from the member's wallet.
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

	if _, err = tx.ExecContext(ctx,
		`UPDATE journal_entries SET status = 'SETTLED', settled_at = $1 WHERE transaction_id = $2 AND status = 'PENDING'`,
		now, txnID,
	); err != nil {
		return fmt.Errorf("settle journal entries: %w", err)
	}

	for _, s := range splits {
		if s.FundingType == FundingTallyBalance {
			res, err := tx.ExecContext(ctx, `
				UPDATE members
				SET    tally_balance_cents = tally_balance_cents - $1,
				       updated_at          = $2
				WHERE  id                  = $3
				  AND  tally_balance_cents >= $1`,
				s.AmountCents, now, s.MemberID)
			if err != nil {
				return fmt.Errorf("deduct tally_balance (member %s): %w", s.MemberID, err)
			}
			if n, _ := res.RowsAffected(); n == 0 {
				return fmt.Errorf("insufficient tally_balance for member %s", s.MemberID)
			}
		}

		if _, err = tx.ExecContext(ctx,
			`UPDATE funding_pulls SET status = 'COMPLETED', updated_at = $1 WHERE member_id = $2 AND transaction_id = $3`,
			now, s.MemberID, txnID,
		); err != nil {
			return fmt.Errorf("update funding pull (member %s): %w", s.MemberID, err)
		}
	}

	if _, err = tx.ExecContext(ctx,
		`UPDATE transactions SET status = 'SETTLED', updated_at = $1 WHERE id = $2`,
		now, txnID,
	); err != nil {
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

	for _, s := range splits {
		memo := fmt.Sprintf("reversal — txn %s", txnID)
		if _, err = tx.ExecContext(ctx, `
			INSERT INTO journal_entries
				(id, transaction_id, debit_account_id, credit_account_id,
				 amount_cents, status, memo, created_at)
			VALUES ($1, $2, $3, $4, $5, 'REVERSED', $6, $7)`,
			uuid.New(), txnID,
			groupClearingAccountID, // debit:  unwind the original credit
			s.AccountID,            // credit: unwind the original debit
			s.AmountCents, memo, now,
		); err != nil {
			return fmt.Errorf("insert reversal (member %s): %w", s.MemberID, err)
		}
	}

	if _, err = tx.ExecContext(ctx,
		`UPDATE transactions SET status = 'REVERSED', updated_at = $1 WHERE id = $2`,
		now, txnID,
	); err != nil {
		return fmt.Errorf("reverse transaction: %w", err)
	}

	return tx.Commit()
}
