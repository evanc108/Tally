-- Migration 000012: Wallet tables for pre-funded member balances.
--
-- wallets              — one per user, holds a spendable balance
-- wallet_transactions  — immutable ledger of credits/debits against the wallet

CREATE TABLE IF NOT EXISTS wallets (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       TEXT        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    balance_cents BIGINT      NOT NULL DEFAULT 0 CHECK (balance_cents >= 0),
    currency      CHAR(3)     NOT NULL DEFAULT 'USD',
    status        TEXT        NOT NULL DEFAULT 'active'
                              CHECK (status IN ('active','frozen','closed')),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, currency)
);

CREATE INDEX IF NOT EXISTS idx_wallets_user_id ON wallets (user_id);

CREATE TABLE IF NOT EXISTS wallet_transactions (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id     UUID        NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    amount_cents  BIGINT      NOT NULL,
    type          TEXT        NOT NULL CHECK (type IN ('credit','debit')),
    description   TEXT,
    reference_id  UUID,
    balance_after BIGINT      NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_wallet_txns_wallet_id ON wallet_transactions (wallet_id);
CREATE INDEX IF NOT EXISTS idx_wallet_txns_ref       ON wallet_transactions (reference_id)
    WHERE reference_id IS NOT NULL;
