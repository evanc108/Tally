-- Payment Sessions: pre-authorization records created before card tap.
-- Tracks lifecycle: draft → receipt → splitting → confirming → ready → completed | cancelled | expired

CREATE TABLE IF NOT EXISTS payment_sessions (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id             UUID NOT NULL REFERENCES tally_groups(id) ON DELETE CASCADE,
    created_by_user_id   TEXT NOT NULL REFERENCES users(id),
    created_by_member_id UUID NOT NULL REFERENCES members(id),
    receipt_id           UUID REFERENCES receipts(id) ON DELETE SET NULL,
    total_cents          BIGINT CHECK (total_cents > 0),
    currency             CHAR(3) NOT NULL DEFAULT 'USD',
    split_method         TEXT NOT NULL DEFAULT 'equal'
                         CHECK (split_method IN ('equal','percentage','custom','itemized')),
    assignment_mode      TEXT NOT NULL DEFAULT 'leader'
                         CHECK (assignment_mode IN ('leader','everyone')),
    card_token           TEXT,
    status               TEXT NOT NULL DEFAULT 'draft'
                         CHECK (status IN ('draft','receipt','splitting','confirming','ready','completed','cancelled','expired')),
    merchant_name        TEXT,
    armed_at             TIMESTAMPTZ,
    expires_at           TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '2 hours'),
    idempotency_key      TEXT UNIQUE,
    transaction_id       UUID REFERENCES transactions(id),
    metadata             JSONB,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Fast lookup for active session per group (JIT handler <20ms budget)
CREATE INDEX IF NOT EXISTS idx_ps_active ON payment_sessions (group_id, status)
    WHERE status NOT IN ('completed','cancelled','expired');

-- Per-member split within a payment session
CREATE TABLE IF NOT EXISTS payment_session_splits (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id      UUID NOT NULL REFERENCES payment_sessions(id) ON DELETE CASCADE,
    member_id       UUID NOT NULL REFERENCES members(id),
    amount_cents    BIGINT NOT NULL DEFAULT 0 CHECK (amount_cents >= 0),
    funding_source  TEXT NOT NULL DEFAULT 'card' CHECK (funding_source IN ('card','wallet')),
    tip_cents       BIGINT NOT NULL DEFAULT 0 CHECK (tip_cents >= 0),
    confirmed       BOOL NOT NULL DEFAULT FALSE,
    confirmed_at    TIMESTAMPTZ,
    metadata        JSONB,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (session_id, member_id)
);

-- Claim columns for "everyone selects items" flow
ALTER TABLE receipt_items
    ADD COLUMN IF NOT EXISTS claimed_by_member_id UUID REFERENCES members(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS claimed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS claim_expires_at TIMESTAMPTZ;
