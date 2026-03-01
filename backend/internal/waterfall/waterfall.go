// Package waterfall implements the 5-tier funding logic shared by the
// /v1/auth/jit handler and the Highnote authorization webhook.
//
// Extracting this into its own package eliminates the duplicate implementation
// that previously lived in both auth/jit.go and cards/handler.go, and
// ensures both code paths stay in sync.
package waterfall

import (
	"context"
	"database/sql"
	"fmt"
	"log/slog"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/tally/backend/internal/ledger"
	"github.com/tally/backend/internal/plaid"
)

// leaderAuthWindow is how long a leader's pre-authorization remains valid.
// Any leader_pre_authorized_at older than this is treated as expired.
const leaderAuthWindow = 24 * time.Hour

// MemberRow holds the fields fetched from the members + accounts tables
// that are needed to run the funding waterfall.
type MemberRow struct {
	ID                     uuid.UUID
	AccountID              uuid.UUID    // member's asset account in the ledger
	PlaidAccessToken       string
	PlaidAccountID         string
	BackupPlaidAccessToken string
	BackupPlaidAccountID   string
	TallyBalanceCents      int64
	SplitWeight            float64
	IsLeader               bool
	LeaderPreAuthorized    bool
	LeaderPreAuthorizedAt  sql.NullTime // NULL = authorization never set or has expired
}

// BalanceResult bundles a member row with the live balances fetched from Plaid.
type BalanceResult struct {
	Member           MemberRow
	PrimaryBalance   int64
	SecondaryBalance int64
	PrimaryErr       error
	SecondaryErr     error
}

// ResolveCard looks up every member in the group that owns cardToken and
// returns their ledger accounts alongside the group's clearing account.
// cardToken may be a Tally card_token or a Highnote cardId — both are stored
// in the members.card_token column.
func ResolveCard(ctx context.Context, db *sql.DB, cardToken string) (
	groupID uuid.UUID,
	members []MemberRow,
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
			m.leader_pre_authorized_at,
			m.group_id,
			ga.id                                      AS group_account_id
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
			&m.PlaidAccessToken, &m.PlaidAccountID,
			&m.BackupPlaidAccessToken, &m.BackupPlaidAccountID,
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

// ParallelBalanceCheck fans out one goroutine per member to Plaid and collects
// all results, honouring ctx cancellation. Primary and secondary bank checks
// for the same member run concurrently.
func ParallelBalanceCheck(ctx context.Context, pl plaid.BalanceClient, members []MemberRow) []BalanceResult {
	results := make([]BalanceResult, len(members))
	var wg sync.WaitGroup
	wg.Add(len(members))

	for i, m := range members {
		go func(idx int, member MemberRow) {
			defer wg.Done()
			r := BalanceResult{Member: member}

			var inner sync.WaitGroup
			inner.Add(1)
			go func() {
				defer inner.Done()
				bal, err := pl.GetAccountBalance(ctx, member.PlaidAccessToken, member.PlaidAccountID)
				r.PrimaryBalance = bal
				r.PrimaryErr = err
			}()

			if member.BackupPlaidAccountID != "" {
				inner.Add(1)
				go func() {
					defer inner.Done()
					bal, err := pl.GetAccountBalance(ctx, member.BackupPlaidAccessToken, member.BackupPlaidAccountID)
					r.SecondaryBalance = bal
					r.SecondaryErr = err
				}()
			}
			inner.Wait()
			results[idx] = r
		}(i, m)
	}

	wg.Wait()
	return results
}

// BuildFundingPlan applies the 5-tier waterfall to each member's available
// funds and returns the splits, IOU entries, and the total approved amount.
//
// Tier 1 — tally_balance (internal wallet)
// Tier 2 — primary bank pull (direct_pull via Plaid)
// Tier 3 — secondary bank pull (secondary_bank via Plaid)
// Tier 4 — leader overwrite: pre-authorised leader covers the shortfall + IOU
// Tier 5 — partial auth: approve only what the member actually has
//
// approvedCents == 0 signals a full decline.
// approvedCents < totalAmountCents signals a partial auth.
func BuildFundingPlan(
	results []BalanceResult,
	totalAmountCents int64,
) (splits []ledger.SplitEntry, ious []ledger.IOUEntry, approvedCents int64, err error) {
	// Find the pre-authorised leader, if any. Require a recent authorization
	// timestamp so that a stale boolean cannot silently enable Tier 4.
	var leader *BalanceResult
	now := time.Now().UTC()
	for i := range results {
		m := &results[i].Member
		if !m.IsLeader || !m.LeaderPreAuthorized {
			continue
		}
		if !m.LeaderPreAuthorizedAt.Valid || now.Sub(m.LeaderPreAuthorizedAt.Time) > leaderAuthWindow {
			slog.Warn("leader pre-authorization expired or never set — Tier 4 disabled",
				"leader_member_id", m.ID,
				"authorized_at", m.LeaderPreAuthorizedAt,
			)
			continue
		}
		leader = &results[i]
		break
	}

	splits = make([]ledger.SplitEntry, 0, len(results))

	for _, r := range results {
		if r.PrimaryErr != nil {
			slog.Warn("primary balance check error — treating as zero",
				"member_id", r.Member.ID, "error", r.PrimaryErr)
		}

		share := int64(float64(totalAmountCents) * r.Member.SplitWeight)
		wallet := r.Member.TallyBalanceCents
		primary := r.PrimaryBalance
		secondary := r.SecondaryBalance

		entry := ledger.SplitEntry{
			MemberID:    r.Member.ID,
			AccountID:   r.Member.AccountID,
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
		if r.PrimaryErr == nil && wallet+primary >= share {
			entry.FundingType = ledger.FundingDirectPull
			splits = append(splits, entry)
			approvedCents += share
			continue
		}

		// Tier 3 — wallet + primary + secondary bank covers the whole share.
		if r.Member.BackupPlaidAccountID != "" && r.SecondaryErr == nil &&
			wallet+primary+secondary >= share {
			entry.FundingType = ledger.FundingSecondaryBank
			splits = append(splits, entry)
			approvedCents += share
			continue
		}

		// Tier 4 — leader overwrite: leader pre-covers the shortfall (IOU recorded).
		if leader != nil && leader.Member.ID != r.Member.ID {
			available := wallet
			if r.PrimaryErr == nil {
				available += primary
			}
			if r.Member.BackupPlaidAccountID != "" && r.SecondaryErr == nil {
				available += secondary
			}
			shortfall := share - available
			leaderCap := leader.Member.TallyBalanceCents + leader.PrimaryBalance
			if shortfall > 0 && leaderCap >= shortfall {
				leaderID := leader.Member.ID
				entry.FundingType = ledger.FundingLeaderOverwrite
				entry.LeaderMemberID = &leaderID
				splits = append(splits, entry)
				ious = append(ious, ledger.IOUEntry{
					DebtorMemberID:   r.Member.ID,
					CreditorMemberID: leader.Member.ID,
					AmountCents:      shortfall,
				})
				approvedCents += share
				// Compliance audit trail — every leader overwrite must be logged.
				slog.Info("leader_overwrite_applied",
					"debtor_member_id", r.Member.ID,
					"leader_member_id", leader.Member.ID,
					"shortfall_cents", shortfall,
					"total_share_cents", share,
					"leader_authorized_at", leader.Member.LeaderPreAuthorizedAt.Time,
				)
				continue
			}
		}

		// Tier 5 — partial auth: approve only what the member can actually cover.
		available := wallet
		if r.PrimaryErr == nil {
			available += primary
		}
		if r.Member.BackupPlaidAccountID != "" && r.SecondaryErr == nil {
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
