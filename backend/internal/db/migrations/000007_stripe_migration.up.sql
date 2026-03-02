-- Migration 000007: Stripe-only migration
--
-- Removes all Plaid and Highnote columns (dead code since the switch to
-- Stripe Issuing + Stripe Financial Connections) and adds the Stripe
-- counterpart columns.
--
-- is_leader, leader_pre_authorized, leader_pre_authorized_at, iou_entries,
-- and the funding_pulls 'leader_overwrite' constraint were already added in
-- migrations 000002 and 000005.

-- ── Drop Plaid indexes (must drop before dropping columns) ──────────────────
DROP INDEX IF EXISTS idx_members_plaid_item_id;
DROP INDEX IF EXISTS idx_members_backup_plaid_item_id;

-- ── Drop all dead Plaid and Highnote columns ────────────────────────────────
ALTER TABLE members
    DROP COLUMN IF EXISTS plaid_access_token,
    DROP COLUMN IF EXISTS plaid_account_id,
    DROP COLUMN IF EXISTS backup_plaid_access_token,
    DROP COLUMN IF EXISTS backup_plaid_account_id,
    DROP COLUMN IF EXISTS plaid_item_id,
    DROP COLUMN IF EXISTS backup_plaid_item_id,
    DROP COLUMN IF EXISTS highnote_cardholder_id,
    DROP COLUMN IF EXISTS highnote_card_id;

-- ── Add Stripe Issuing + PaymentMethod columns ──────────────────────────────
ALTER TABLE members
    ADD COLUMN IF NOT EXISTS stripe_cardholder_id             TEXT,
    ADD COLUMN IF NOT EXISTS stripe_card_id                   TEXT,
    ADD COLUMN IF NOT EXISTS stripe_payment_method_id         TEXT,
    ADD COLUMN IF NOT EXISTS stripe_backup_payment_method_id  TEXT;

-- ── Fast leader lookups at settlement ───────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_members_group_leader
    ON members (group_id, is_leader)
    WHERE is_leader = TRUE;
