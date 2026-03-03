-- Migration 000008: Remove Plaid and Highnote columns from members
-- Card issuing and funding use Stripe only.

ALTER TABLE members
    DROP COLUMN IF EXISTS plaid_access_token,
    DROP COLUMN IF EXISTS plaid_account_id,
    DROP COLUMN IF EXISTS backup_plaid_access_token,
    DROP COLUMN IF EXISTS backup_plaid_account_id,
    DROP COLUMN IF EXISTS plaid_item_id,
    DROP COLUMN IF EXISTS backup_plaid_item_id,
    DROP COLUMN IF EXISTS highnote_cardholder_id,
    DROP COLUMN IF EXISTS highnote_card_id;

DROP INDEX IF EXISTS idx_members_plaid_item_id;
DROP INDEX IF EXISTS idx_members_backup_plaid_item_id;
