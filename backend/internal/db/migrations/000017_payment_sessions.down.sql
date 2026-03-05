ALTER TABLE receipt_items DROP COLUMN IF EXISTS claimed_by_member_id, DROP COLUMN IF EXISTS claimed_at, DROP COLUMN IF EXISTS claim_expires_at;
DROP TABLE IF EXISTS payment_session_splits;
DROP TABLE IF EXISTS payment_sessions;
