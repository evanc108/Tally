-- Rollback: re-add Plaid and Highnote columns (nullable, no data restored)

ALTER TABLE members
    ADD COLUMN IF NOT EXISTS plaid_access_token TEXT,
    ADD COLUMN IF NOT EXISTS plaid_account_id TEXT,
    ADD COLUMN IF NOT EXISTS backup_plaid_access_token TEXT,
    ADD COLUMN IF NOT EXISTS backup_plaid_account_id TEXT,
    ADD COLUMN IF NOT EXISTS plaid_item_id TEXT,
    ADD COLUMN IF NOT EXISTS backup_plaid_item_id TEXT,
    ADD COLUMN IF NOT EXISTS highnote_cardholder_id TEXT,
    ADD COLUMN IF NOT EXISTS highnote_card_id TEXT;

CREATE INDEX IF NOT EXISTS idx_members_plaid_item_id
    ON members (plaid_item_id)
    WHERE plaid_item_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_members_backup_plaid_item_id
    ON members (backup_plaid_item_id)
    WHERE backup_plaid_item_id IS NOT NULL;
