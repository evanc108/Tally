-- Migration 000006: Add Plaid item IDs for webhook handling
--
-- plaid_item_id / backup_plaid_item_id are needed so that Plaid webhook events
-- (e.g. ITEM_ERROR, PENDING_EXPIRATION) — which identify the item by item_id,
-- not access_token — can be mapped back to the correct member row.

ALTER TABLE members
    ADD COLUMN IF NOT EXISTS plaid_item_id        TEXT,
    ADD COLUMN IF NOT EXISTS backup_plaid_item_id TEXT;

-- Partial index: only index rows that actually have an item_id linked.
CREATE INDEX IF NOT EXISTS idx_members_plaid_item_id
    ON members (plaid_item_id)
    WHERE plaid_item_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_members_backup_plaid_item_id
    ON members (backup_plaid_item_id)
    WHERE backup_plaid_item_id IS NOT NULL;
