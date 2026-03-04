-- Migration 000011: Cards table for Stripe Issuing virtual/physical cards.
--
-- Decouples card lifecycle from the members table. A member can hold multiple
-- cards over time (e.g. reissued after expiry) with one flagged as primary.
-- ListGroups LEFT JOINs this table to show card info per member.

CREATE TABLE IF NOT EXISTS cards (
    id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id             UUID        NOT NULL REFERENCES members(id) ON DELETE CASCADE,
    user_id               TEXT        NOT NULL REFERENCES users(id),
    card_token            TEXT        UNIQUE,
    stripe_cardholder_id  TEXT,
    stripe_card_id        TEXT        UNIQUE,
    last_four             TEXT,
    expiry_month          INT,
    expiry_year           INT,
    brand                 TEXT        NOT NULL DEFAULT 'Visa',
    card_type             TEXT        NOT NULL DEFAULT 'virtual'
                                      CHECK (card_type IN ('virtual','physical')),
    status                TEXT        NOT NULL DEFAULT 'active'
                                      CHECK (status IN ('active','inactive','cancelled','expired')),
    is_primary            BOOLEAN     NOT NULL DEFAULT TRUE,
    metadata              JSONB,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cards_member_id ON cards (member_id);
CREATE INDEX IF NOT EXISTS idx_cards_user_id   ON cards (user_id);
CREATE INDEX IF NOT EXISTS idx_cards_token     ON cards (card_token) WHERE card_token IS NOT NULL;

-- Fast lookup for ListGroups: primary active card per member
CREATE INDEX IF NOT EXISTS idx_cards_primary_active
    ON cards (member_id, is_primary, status)
    WHERE is_primary = TRUE AND status = 'active';
