-- ─────────────────────────────────────────────────────────────────────────────
-- Migration 000002: Highnote card issuing + fallback waterfall additions
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Add Highnote card columns to members ──────────────────────────────────────
ALTER TABLE members
    ADD COLUMN IF NOT EXISTS highnote_cardholder_id    TEXT,
    ADD COLUMN IF NOT EXISTS highnote_card_id          TEXT,
    -- Secondary bank (Tier 3 fallback)
    ADD COLUMN IF NOT EXISTS backup_plaid_access_token TEXT,
    ADD COLUMN IF NOT EXISTS backup_plaid_account_id   TEXT,
    -- Leader overwrite (Tier 4 fallback)
    ADD COLUMN IF NOT EXISTS is_leader                 BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS leader_pre_authorized     BOOLEAN NOT NULL DEFAULT FALSE;

-- ── Expand funding_type to cover new waterfall tiers ─────────────────────────
-- Drop the old constraint and add the expanded one.
ALTER TABLE funding_pulls
    DROP CONSTRAINT IF EXISTS funding_pulls_funding_type_check;

ALTER TABLE funding_pulls
    ADD CONSTRAINT funding_pulls_funding_type_check
    CHECK (funding_type IN (
        'tally_balance',    -- Tier 1: internal wallet
        'direct_pull',      -- Tier 2: primary bank
        'secondary_bank',   -- Tier 3: backup bank
        'leader_overwrite'  -- Tier 4: group leader covers shortfall
    ));

-- ── IOU entries: tracks leader-covered shortfalls ─────────────────────────────
-- When the leader pays a member's shortfall the app records an IOU here
-- and notifies both parties. The member is expected to repay via wallet top-up.
CREATE TABLE IF NOT EXISTS iou_entries (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    debtor_member_id    UUID        NOT NULL REFERENCES members(id),
    creditor_member_id  UUID        NOT NULL REFERENCES members(id),
    transaction_id      UUID        NOT NULL REFERENCES transactions(id),
    amount_cents        BIGINT      NOT NULL CHECK (amount_cents > 0),
    status              TEXT        NOT NULL DEFAULT 'OUTSTANDING'
                                    CHECK (status IN ('OUTSTANDING', 'SETTLED')),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_iou_different_members CHECK (debtor_member_id <> creditor_member_id)
);

CREATE INDEX IF NOT EXISTS idx_iou_debtor  ON iou_entries (debtor_member_id);
CREATE INDEX IF NOT EXISTS idx_iou_creditor ON iou_entries (creditor_member_id);
CREATE INDEX IF NOT EXISTS idx_iou_txn     ON iou_entries (transaction_id);
