-- Migration 000008: KYC status column
--
-- Stripe Identity verification result is stored here.
-- Card issuance (POST /v1/cards/issue) is gated behind kyc_status = 'approved'.
ALTER TABLE members
    ADD COLUMN IF NOT EXISTS kyc_status TEXT NOT NULL DEFAULT 'pending'
        CHECK (kyc_status IN ('pending', 'approved', 'rejected'));
