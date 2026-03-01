DROP INDEX IF EXISTS idx_funding_pulls_status;
DROP INDEX IF EXISTS idx_funding_pulls_funding_type;

ALTER TABLE members DROP COLUMN IF EXISTS leader_pre_authorized_at;
