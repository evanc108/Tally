-- Revert migration 000008
ALTER TABLE members DROP COLUMN IF EXISTS kyc_status;
