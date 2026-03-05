// Package waterfall implements the simplified Stripe-only funding logic for the
// JIT authorization handler.
//
// Architecture decision: because every member must link a debit card
// (stripe_payment_method_id) before joining a group, the JIT handler can
// always approve — there is no need to check balances at authorization time.
// Actual card charging happens in the settlement worker after the merchant
// charge has already been fronted by Stripe Issuing.
//
// The "balance waterfall" (Plaid checks, tier 2/3) has been removed. All
// members receive a direct_pull funding plan at JIT time, and the settlement
// worker handles retries + leader cover when charges fail.
package waterfall

import (
	"context"
	"database/sql"
	"fmt"

	"github.com/google/uuid"
	"github.com/tally/backend/internal/ledger"
)

// MemberRow holds the fields fetched from the members + accounts tables
// needed to run the JIT funding plan.
type MemberRow struct {
	ID                            uuid.UUID
	AccountID                     uuid.UUID // member's asset account in the ledger
	StripePaymentMethodID         string
	StripeBackupPaymentMethodID   string
	TallyBalanceCents             int64
	SplitWeight                   float64
	IsLeader                      bool
	LeaderPreAuthorized           bool
	LeaderPreAuthorizedAt         sql.NullTime
}

// ResolveCard looks up every member in the group that owns cardToken and
// returns their ledger accounts alongside the group's clearing account.
// cardToken is the Stripe Issuing card ID stored in members.card_token.
func ResolveCard(ctx context.Context, db *sql.DB, cardToken string) (
	groupID uuid.UUID,
	members []MemberRow,
	groupAccountID uuid.UUID,
	err error,
) {
	const q = `
		SELECT
			m.id,
			ma.id                                                    AS account_id,
			COALESCE(m.stripe_payment_method_id,        '')          AS stripe_payment_method_id,
			COALESCE(m.stripe_backup_payment_method_id, '')          AS stripe_backup_payment_method_id,
			m.tally_balance_cents,
			m.split_weight::float8,
			m.is_leader,
			m.leader_pre_authorized,
			m.leader_pre_authorized_at,
			m.group_id,
			ga.id                                                    AS group_account_id
		FROM members m
		JOIN accounts ma ON ma.owner_id   = m.id       AND ma.account_type = 'asset'
		JOIN accounts ga ON ga.owner_id   = m.group_id AND ga.account_type = 'liability'
		WHERE m.group_id = (
			SELECT group_id FROM members WHERE card_token = $1 LIMIT 1
		)
	`

	rows, err := db.QueryContext(ctx, q, cardToken)
	if err != nil {
		return uuid.Nil, nil, uuid.Nil, fmt.Errorf("query members: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var m MemberRow
		var gID, gaID uuid.UUID
		if err = rows.Scan(
			&m.ID, &m.AccountID,
			&m.StripePaymentMethodID, &m.StripeBackupPaymentMethodID,
			&m.TallyBalanceCents, &m.SplitWeight,
			&m.IsLeader, &m.LeaderPreAuthorized,
			&m.LeaderPreAuthorizedAt,
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

// BuildFundingPlan assigns direct_pull to every member. Because a linked
// stripe_payment_method_id is required before joining a group, every member
// is guaranteed to have a card on file. If any member is missing a PM
// (data integrity error), the transaction is declined.
//
// Leader cover and retry logic are handled by the settlement worker, not here.
func BuildFundingPlan(
	members []MemberRow,
	totalAmountCents int64,
) (splits []ledger.SplitEntry, err error) {
	splits = make([]ledger.SplitEntry, 0, len(members))

	for _, m := range members {
		if m.StripePaymentMethodID == "" {
			return nil, fmt.Errorf("member %s has no linked payment method", m.ID)
		}

		share := int64(float64(totalAmountCents) * m.SplitWeight)

		splits = append(splits, ledger.SplitEntry{
			MemberID:    m.ID,
			AccountID:   m.AccountID,
			AmountCents: share,
			FundingType: ledger.FundingDirectPull,
		})
	}

	return splits, nil
}

// ResolveReceiptSplit looks for a finalized receipt for the group that has not
// yet been linked to a transaction. Returns the receipt ID and a per-member
// amount map derived from receipt_item_assignments.
//
// Returns (uuid.Nil, nil, nil) when no active receipt exists — JIT should
// fall back to BuildFundingPlan with split_weight in that case.
//
// Receipts older than 2 hours are ignored to prevent stale sessions from
// affecting future transactions.
func ResolveReceiptSplit(
	ctx context.Context,
	db *sql.DB,
	groupID uuid.UUID,
) (receiptID uuid.UUID, memberAmounts map[uuid.UUID]int64, err error) {
	// Fix 5: use updated_at (set when the receipt is finalized) not created_at,
	// so the 2-hour window starts from finalization, not receipt creation.
	err = db.QueryRowContext(ctx, `
		SELECT id FROM receipts
		WHERE group_id       = $1
		  AND status         = 'finalized'
		  AND transaction_id IS NULL
		  AND updated_at     > NOW() - INTERVAL '2 hours'
		ORDER BY updated_at DESC
		LIMIT 1`,
		groupID,
	).Scan(&receiptID)
	if err == sql.ErrNoRows {
		return uuid.Nil, nil, nil
	}
	if err != nil {
		return uuid.Nil, nil, fmt.Errorf("query receipt: %w", err)
	}

	// Sum amount_cents per member across all assigned items.
	rows, err := db.QueryContext(ctx, `
		SELECT ria.member_id, SUM(ria.amount_cents)
		FROM receipt_item_assignments ria
		JOIN receipt_items ri ON ri.id = ria.receipt_item_id
		WHERE ri.receipt_id = $1
		GROUP BY ria.member_id`,
		receiptID,
	)
	if err != nil {
		return uuid.Nil, nil, fmt.Errorf("query assignments: %w", err)
	}
	defer rows.Close()

	memberAmounts = make(map[uuid.UUID]int64)
	for rows.Next() {
		var mid uuid.UUID
		var amount int64
		if err := rows.Scan(&mid, &amount); err != nil {
			return uuid.Nil, nil, fmt.Errorf("scan assignment: %w", err)
		}
		memberAmounts[mid] = amount
	}
	if err := rows.Err(); err != nil {
		return uuid.Nil, nil, fmt.Errorf("rows error: %w", err)
	}

	if len(memberAmounts) == 0 {
		// Receipt has no assignments yet — treat as if no receipt exists.
		return uuid.Nil, nil, nil
	}

	return receiptID, memberAmounts, nil
}

// BuildReceiptFundingPlan builds a funding plan from pre-computed per-member
// amounts derived from receipt item assignments. Members with no assigned
// items (amount = 0 or absent) are skipped — they owe nothing for this
// transaction.
//
// Called by the JIT handler when ResolveReceiptSplit finds an active session.
func BuildReceiptFundingPlan(
	members []MemberRow,
	memberAmounts map[uuid.UUID]int64,
) ([]ledger.SplitEntry, error) {
	splits := make([]ledger.SplitEntry, 0, len(memberAmounts))

	// Index members by ID for O(1) lookup.
	membersByID := make(map[uuid.UUID]MemberRow, len(members))
	for _, m := range members {
		membersByID[m.ID] = m
	}

	for mid, amount := range memberAmounts {
		if amount <= 0 {
			continue
		}
		m, ok := membersByID[mid]
		if !ok {
			// Assignment references a member no longer in the group — skip.
			continue
		}
		if m.StripePaymentMethodID == "" {
			return nil, fmt.Errorf("member %s has no linked payment method", m.ID)
		}
		splits = append(splits, ledger.SplitEntry{
			MemberID:    m.ID,
			AccountID:   m.AccountID,
			AmountCents: amount,
			FundingType: ledger.FundingDirectPull,
		})
	}

	return splits, nil
}
