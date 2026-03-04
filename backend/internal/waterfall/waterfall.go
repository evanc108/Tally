// Package waterfall implements the simplified Stripe-only funding logic for the
// JIT authorization handler.
//
// Architecture decision: because every member must link a bank account (ACH)
// (stripe_payment_method_id) before joining a group, the JIT handler can
// always approve — there is no need to check balances at authorization time.
// Actual ACH pulls happen in the settlement worker after the merchant
// charge has already been fronted by Stripe Issuing.
//
// The "balance waterfall" (Plaid checks, tier 2/3) has been removed. All
// members receive a direct_pull funding plan at JIT time, and the settlement
// worker handles retries + leader cover when ACH charges fail.
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
// stripe_payment_method_id (bank account) is required before joining a group, every member
// is guaranteed to have a payment method on file. If any member is missing a PM
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
