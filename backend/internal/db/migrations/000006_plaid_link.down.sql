DROP INDEX IF EXISTS idx_members_backup_plaid_item_id;
DROP INDEX IF EXISTS idx_members_plaid_item_id;

ALTER TABLE members
    DROP COLUMN IF EXISTS backup_plaid_item_id,
    DROP COLUMN IF EXISTS plaid_item_id;
