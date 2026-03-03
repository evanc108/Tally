-- Migration 000010: User profile expansion + global payment methods + feed indices
--
-- The users table previously held only id (Clerk user ID) and created_at.
-- This migration adds full profile data, a global Stripe customer ID, push token,
-- and a JSONB preferences bag.
--
-- Also adds:
--   user_payment_methods — global payment methods at user scope (for wallet top-ups)
--   idx_members_user_id  — critical for cross-circle transaction feed queries
--   idx_transactions_group_feed — covering index for per-circle feed (group_id + created_at)
--
-- Backward compatibility:
--   All new columns are nullable or have safe defaults. Existing code that only
--   reads/writes users.id is unaffected.

-- ── Expand users table ────────────────────────────────────────────────────────
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS first_name         TEXT,
    ADD COLUMN IF NOT EXISTS last_name          TEXT,
    ADD COLUMN IF NOT EXISTS email              TEXT,
    ADD COLUMN IF NOT EXISTS phone              TEXT,
    ADD COLUMN IF NOT EXISTS avatar_url         TEXT,
    -- Global Stripe customer ID (distinct from per-member Stripe Issuing cardholder IDs).
    -- Used for wallet top-ups via Financial Connections and global payment methods.
    ADD COLUMN IF NOT EXISTS stripe_customer_id TEXT UNIQUE,
    -- APNs/FCM push token. Nullable: user may not have granted notification permission.
    ADD COLUMN IF NOT EXISTS push_token         TEXT,
    -- JSONB bag for future user-level settings (notification prefs, theme, language).
    -- Avoids schema migrations for minor preference additions.
    ADD COLUMN IF NOT EXISTS preferences        JSONB NOT NULL DEFAULT '{}',
    -- Soft delete: preserves ledger history while deactivating the account.
    -- Application code filters WHERE deleted_at IS NULL.
    ADD COLUMN IF NOT EXISTS deleted_at         TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- Partial unique index: allows NULLs for users whose email hasn't been synced yet.
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email_unique
    ON users (email)
    WHERE email IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_users_stripe_customer_id
    ON users (stripe_customer_id)
    WHERE stripe_customer_id IS NOT NULL;

-- ── Global user payment methods ───────────────────────────────────────────────
-- Stores Stripe PaymentMethod IDs at user scope, separate from the per-circle
-- members.stripe_payment_method_id (used for settlement pulls).
--
-- Use cases:
--   - Wallet top-up: user loads funds from any linked PM without picking a circle.
--   - Future: cross-circle default payment method for new memberships.
--
-- Multiple rows per user allowed; is_default flags the active one.
CREATE TABLE IF NOT EXISTS user_payment_methods (
    id                              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                         TEXT        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    -- Stripe PaymentMethod object ID (pm_xxx)
    stripe_payment_method_id        TEXT        NOT NULL,
    -- Display info mirrored from Stripe to avoid extra API round-trips in the iOS UI.
    -- Authoritative source is Stripe; these are cached display values.
    last_four                       CHAR(4),
    expiry_month                    SMALLINT    CHECK (expiry_month BETWEEN 1 AND 12),
    expiry_year                     SMALLINT    CHECK (expiry_year >= 2024),
    brand                           TEXT,       -- visa / mastercard / amex / discover
    bank_name                       TEXT,       -- for us_bank_account type
    pm_type                         TEXT        NOT NULL DEFAULT 'card'
                                                CHECK (pm_type IN ('card', 'us_bank_account')),
    -- Only one default per user. Enforced via partial unique index.
    is_default                      BOOL        NOT NULL DEFAULT FALSE,
    -- Stripe Financial Connections account ID. Set when linked via FC flow.
    -- Enables future ACH top-ups without re-linking.
    financial_connections_account_id TEXT,
    status                          TEXT        NOT NULL DEFAULT 'active'
                                                CHECK (status IN ('active', 'detached')),
    metadata                        JSONB,
    created_at                      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, stripe_payment_method_id)
);

CREATE INDEX IF NOT EXISTS idx_upm_user_id
    ON user_payment_methods (user_id);

-- Partial unique: at most one default active PM per user at the DB level,
-- preventing application-layer race conditions on default-switching.
CREATE UNIQUE INDEX IF NOT EXISTS idx_upm_default
    ON user_payment_methods (user_id)
    WHERE is_default = TRUE AND status = 'active';

-- ── Feed performance indices ──────────────────────────────────────────────────

-- Cross-circle feed: members.user_id currently has no index.
-- Required for: "get all recent transactions across all of a user's circles"
-- Query pattern: SELECT t.* FROM transactions t JOIN members m ON t.group_id = m.group_id
--                WHERE m.user_id = $1 ORDER BY t.created_at DESC LIMIT 20
CREATE INDEX IF NOT EXISTS idx_members_user_id
    ON members (user_id);

-- Per-circle feed: covering index on (group_id, created_at DESC) for the
-- GET /v1/groups/:id/transactions endpoint. Filters out DECLINED transactions
-- which are noise in the feed.
CREATE INDEX IF NOT EXISTS idx_transactions_group_feed
    ON transactions (group_id, created_at DESC)
    WHERE status != 'DECLINED';
