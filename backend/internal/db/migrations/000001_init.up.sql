-- ─────────────────────────────────────────────────────────────────────────────
-- Tally — Initial Schema
--
-- Design principles:
--   • All monetary amounts are stored as integer cents to avoid float rounding.
--   • A double-entry ledger (journal_entries) is the source of truth for money
--     movement; application-level balances are derived views.
--   • Every multi-row write uses serializable transactions at the application
--     layer for strict consistency.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Groups ────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS tally_groups (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT        NOT NULL,
    currency    CHAR(3)     NOT NULL DEFAULT 'USD',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Members ───────────────────────────────────────────────────────────────────
-- Each row represents one user's membership in one group.
-- A user can belong to multiple groups (multiple rows, same user_id).
CREATE TABLE IF NOT EXISTS members (
    id                   UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id             UUID           NOT NULL REFERENCES tally_groups(id) ON DELETE CASCADE,
    user_id              UUID           NOT NULL,
    display_name         TEXT           NOT NULL,
    -- card_token is the processor-issued virtual card identifier for this member
    card_token           TEXT           UNIQUE,
    -- Plaid link credentials for real-time balance checks
    plaid_access_token   TEXT,
    plaid_account_id     TEXT,
    -- Pre-funded wallet balance (cents). Checked before falling back to direct_pull.
    tally_balance_cents  BIGINT         NOT NULL DEFAULT 0 CHECK (tally_balance_cents >= 0),
    -- Fractional share of the group's expenses (e.g. 0.25 for equal-4-way split)
    split_weight         NUMERIC(7, 6)  NOT NULL DEFAULT 0.250000,
    created_at           TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    UNIQUE (group_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_members_card_token  ON members (card_token);
CREATE INDEX IF NOT EXISTS idx_members_group_id    ON members (group_id);

-- ── Ledger Accounts ───────────────────────────────────────────────────────────
-- Each member gets one 'asset' account.
-- Each group gets one 'liability' (clearing) account.
CREATE TABLE IF NOT EXISTS accounts (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_type   TEXT        NOT NULL CHECK (owner_type IN ('member', 'group')),
    owner_id     UUID        NOT NULL,
    account_type TEXT        NOT NULL CHECK (account_type IN ('asset', 'liability')),
    currency     CHAR(3)     NOT NULL DEFAULT 'USD',
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (owner_id, account_type)
);

CREATE INDEX IF NOT EXISTS idx_accounts_owner ON accounts (owner_id, owner_type);

-- ── Transactions ──────────────────────────────────────────────────────────────
-- One row per card swipe. Status lifecycle: PENDING → APPROVED/DECLINED → SETTLED/REVERSED
CREATE TABLE IF NOT EXISTS transactions (
    id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id             UUID        NOT NULL REFERENCES tally_groups(id),
    idempotency_key      TEXT        NOT NULL UNIQUE,
    amount_cents         BIGINT      NOT NULL CHECK (amount_cents > 0),
    currency             CHAR(3)     NOT NULL DEFAULT 'USD',
    merchant_name        TEXT,
    merchant_category    TEXT,
    status               TEXT        NOT NULL DEFAULT 'PENDING'
                                     CHECK (status IN ('PENDING','APPROVED','DECLINED','SETTLED','REVERSED')),
    card_token           TEXT,
    initiating_member_id UUID        REFERENCES members(id),
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_transactions_group_id ON transactions (group_id);
CREATE INDEX IF NOT EXISTS idx_transactions_status   ON transactions (status);

-- ── Journal Entries (double-entry ledger) ─────────────────────────────────────
-- Every financial event creates at least one entry.
-- Invariant: for each entry, debit_account_id ≠ credit_account_id.
CREATE TABLE IF NOT EXISTS journal_entries (
    id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id    UUID        NOT NULL REFERENCES transactions(id),
    debit_account_id  UUID        NOT NULL REFERENCES accounts(id),
    credit_account_id UUID        NOT NULL REFERENCES accounts(id),
    amount_cents      BIGINT      NOT NULL CHECK (amount_cents > 0),
    currency          CHAR(3)     NOT NULL DEFAULT 'USD',
    status            TEXT        NOT NULL DEFAULT 'PENDING'
                                  CHECK (status IN ('PENDING','SETTLED','REVERSED')),
    memo              TEXT,
    metadata          JSONB,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    settled_at        TIMESTAMPTZ,
    CONSTRAINT chk_no_self_entry CHECK (debit_account_id <> credit_account_id)
);

CREATE INDEX IF NOT EXISTS idx_journal_entries_txn_id ON journal_entries (transaction_id);
CREATE INDEX IF NOT EXISTS idx_journal_entries_status  ON journal_entries (status);

-- ── Funding Pulls ─────────────────────────────────────────────────────────────
-- Records each member's funding decision and status per transaction.
CREATE TABLE IF NOT EXISTS funding_pulls (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id      UUID        NOT NULL REFERENCES members(id),
    transaction_id UUID        NOT NULL REFERENCES transactions(id),
    amount_cents   BIGINT      NOT NULL CHECK (amount_cents > 0),
    funding_type   TEXT        NOT NULL CHECK (funding_type IN ('tally_balance', 'direct_pull')),
    status         TEXT        NOT NULL DEFAULT 'PENDING'
                               CHECK (status IN ('PENDING','COMPLETED','FAILED')),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (member_id, transaction_id)
);

CREATE INDEX IF NOT EXISTS idx_funding_pulls_txn_id   ON funding_pulls (transaction_id);
CREATE INDEX IF NOT EXISTS idx_funding_pulls_member_id ON funding_pulls (member_id);
