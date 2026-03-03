-- Migration 000007: Stripe (Issuing, PaymentMethods, Identity)
--
-- Add Stripe-related columns to members. Plaid/Highnote columns are dropped in 000008.
-- in this migration to allow phased rollout and rollback.

ALTER TABLE members
    ADD COLUMN IF NOT EXISTS stripe_customer_id              TEXT,
    ADD COLUMN IF NOT EXISTS stripe_payment_method_id        TEXT,
    ADD COLUMN IF NOT EXISTS stripe_backup_payment_method_id TEXT,
    ADD COLUMN IF NOT EXISTS stripe_cardholder_id            TEXT,
    ADD COLUMN IF NOT EXISTS stripe_card_id                  TEXT,
    ADD COLUMN IF NOT EXISTS identity_verified_at             TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS stripe_verification_session_id  TEXT;

CREATE INDEX IF NOT EXISTS idx_members_stripe_customer_id
    ON members (stripe_customer_id)
    WHERE stripe_customer_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_members_stripe_card_id
    ON members (stripe_card_id)
    WHERE stripe_card_id IS NOT NULL;
