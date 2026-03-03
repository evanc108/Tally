-- Migration 000011: Global per-user wallet
--
-- Creates a user-scoped wallet (one per user, usable across all circles) and
-- a wallet_transactions table for the immutable audit trail of every balance change.
--
-- Why global (not per-circle):
--   The existing members.tally_balance_cents is per-circle and documented as
--   "reserved; not currently used." A wallet should be a single account a user
--   can top up once and use across any circle, like a prepaid balance.
--
-- Deprecation of members.tally_balance_cents:
--   The column is zeroed but NOT dropped here — waterfall.go still references it
--   in MemberRow.TallyBalanceCents. It will be removed in a future migration
--   once the Go code is updated to use the wallets table.
--
-- wallet_transactions is IMMUTABLE (no updated_at). Credits and debits are
-- separate rows with an explicit direction column — never a signed amount_cents.
-- This matches the existing journal_entries pattern and makes aggregates safe.

-- ── Global wallets (one per user) ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS wallets (
    id                              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    -- One wallet per user across all circles. UNIQUE enforced at DB level.
    user_id                         TEXT        NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    -- Authoritative current balance. CHECK prevents it from going negative.
    -- Must only be updated inside a serializable transaction that simultaneously
    -- writes a wallet_transactions row (application-layer invariant).
    balance_cents                   BIGINT      NOT NULL DEFAULT 0
                                                CHECK (balance_cents >= 0),
    currency                        CHAR(3)     NOT NULL DEFAULT 'USD',
    -- Stripe Financial Connections account ID. When set, enables ACH top-ups
    -- without the user re-linking their bank.
    stripe_financial_connections_id TEXT,
    metadata                        JSONB,
    created_at                      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_wallets_user_id ON wallets (user_id);

-- ── Wallet transaction history (immutable audit log) ──────────────────────────
-- Every change to wallets.balance_cents produces exactly one row here.
-- Reversals add a new row (direction='credit', tx_type='refund') — never modify
-- existing rows. Same append-only principle as journal_entries.
CREATE TABLE IF NOT EXISTS wallet_transactions (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id       UUID        NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    -- Explicit direction keeps aggregates safe and avoids signed-amount bugs.
    direction       TEXT        NOT NULL CHECK (direction IN ('credit', 'debit')),
    amount_cents    BIGINT      NOT NULL CHECK (amount_cents > 0),
    currency        CHAR(3)     NOT NULL DEFAULT 'USD',
    -- Why this movement occurred.
    tx_type         TEXT        NOT NULL
                                CHECK (tx_type IN (
                                    'top_up',           -- User added funds to wallet
                                    'settlement_pull',  -- Settlement debited wallet instead of card
                                    'iou_repayment',    -- Member repaid an IOU via wallet
                                    'refund'            -- Reversal credited funds back
                                )),
    -- Optional links to source records for full traceability.
    transaction_id  UUID        REFERENCES transactions(id),
    iou_id          UUID        REFERENCES iou_entries(id),
    status          TEXT        NOT NULL DEFAULT 'COMPLETED'
                                CHECK (status IN ('PENDING', 'COMPLETED', 'FAILED', 'REVERSED')),
    -- Stripe PaymentIntent or Transfer ID for the underlying Stripe event.
    stripe_ref      TEXT,
    metadata        JSONB,
    -- No updated_at: these rows are immutable once written.
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_wt_wallet_id
    ON wallet_transactions (wallet_id);

CREATE INDEX IF NOT EXISTS idx_wt_transaction_id
    ON wallet_transactions (transaction_id)
    WHERE transaction_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_wt_iou_id
    ON wallet_transactions (iou_id)
    WHERE iou_id IS NOT NULL;

-- Partial index for monitoring: quickly find stuck PENDING or FAILED wallet ops.
CREATE INDEX IF NOT EXISTS idx_wt_status_pending
    ON wallet_transactions (wallet_id, created_at DESC)
    WHERE status IN ('PENDING', 'FAILED');

-- ── Deprecate members.tally_balance_cents ─────────────────────────────────────
-- Zero out any non-zero values. The column was documented as "reserved; not
-- currently used" — this makes the transition to wallets clean.
-- DO NOT DROP: waterfall.go MemberRow still scans this column.
-- Remove in a future migration after waterfall.go is updated.
UPDATE members SET tally_balance_cents = 0 WHERE tally_balance_cents != 0;
