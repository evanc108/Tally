-- Rollback 000007: Remove Stripe columns from members

DROP INDEX IF EXISTS idx_members_stripe_card_id;
DROP INDEX IF EXISTS idx_members_stripe_customer_id;

ALTER TABLE members
    DROP COLUMN IF EXISTS stripe_verification_session_id,
    DROP COLUMN IF EXISTS identity_verified_at,
    DROP COLUMN IF EXISTS stripe_card_id,
    DROP COLUMN IF EXISTS stripe_cardholder_id,
    DROP COLUMN IF EXISTS stripe_backup_payment_method_id,
    DROP COLUMN IF EXISTS stripe_payment_method_id,
    DROP COLUMN IF EXISTS stripe_customer_id;
