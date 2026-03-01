-- ── Rollback migration 000002 ─────────────────────────────────────────────────

DROP TABLE IF EXISTS iou_entries;

-- Restore original funding_type constraint
ALTER TABLE funding_pulls
    DROP CONSTRAINT IF EXISTS funding_pulls_funding_type_check;

ALTER TABLE funding_pulls
    ADD CONSTRAINT funding_pulls_funding_type_check
    CHECK (funding_type IN ('tally_balance', 'direct_pull'));

ALTER TABLE members
    DROP COLUMN IF EXISTS highnote_cardholder_id,
    DROP COLUMN IF EXISTS highnote_card_id,
    DROP COLUMN IF EXISTS backup_plaid_access_token,
    DROP COLUMN IF EXISTS backup_plaid_account_id,
    DROP COLUMN IF EXISTS is_leader,
    DROP COLUMN IF EXISTS leader_pre_authorized;
