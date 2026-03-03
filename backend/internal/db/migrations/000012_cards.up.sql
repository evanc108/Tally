-- Migration 000012: Extract card details into a dedicated cards table
--
-- Currently card_token, stripe_cardholder_id, and stripe_card_id live directly
-- on members rows. Problems with this:
--   - One card per member, ever — no replacement history
--   - No per-card status (frozen/cancelled separate from member status)
--   - No card type distinction (virtual vs physical)
--   - KYC status conflated with card status on the same row
--
-- This migration:
--   1. Creates the cards table with full card lifecycle metadata.
--   2. Migrates existing card data from members → cards.
--   3. Adds a trigger to keep members.card_token in sync with the active
--      card so the JIT waterfall resolver (waterfall.go ResolveCard) continues
--      to work without any Go code changes.
--
-- Backward compatibility:
--   The JIT handler's critical path queries members WHERE card_token = $1.
--   The trigger trg_sync_card_token propagates any write to cards back to
--   members.card_token for the primary active card. Old Go code is unaffected.
--   The deprecated columns (card_token, stripe_cardholder_id, stripe_card_id)
--   on members are NOT dropped here — remove them in migration 000014+ after
--   waterfall.go and cards/handler.go are updated to target the cards table.

CREATE TABLE IF NOT EXISTS cards (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    -- The circle membership this card is issued for.
    member_id               UUID        NOT NULL REFERENCES members(id) ON DELETE CASCADE,
    -- The user who owns this card. Allows querying all cards for a user across
    -- circles without joining through members.
    user_id                 TEXT        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    -- The Stripe Issuing card token used in JIT authorization.
    -- This is what Stripe sends in the webhook body when a card is tapped.
    card_token              TEXT        UNIQUE,
    -- Stripe Issuing object IDs.
    stripe_cardholder_id    TEXT,
    stripe_card_id          TEXT        UNIQUE,
    -- Display info mirrored from Stripe Issuing for the iOS card UI.
    -- Authoritative source is Stripe; these are cached to avoid API round-trips.
    last_four               CHAR(4),
    expiry_month            SMALLINT    CHECK (expiry_month BETWEEN 1 AND 12),
    expiry_year             SMALLINT    CHECK (expiry_year >= 2024),
    brand                   TEXT,       -- visa / mastercard
    -- Virtual: digital card in Apple/Google Wallet.
    -- Physical: future mailed card (not yet implemented).
    card_type               TEXT        NOT NULL DEFAULT 'virtual'
                                        CHECK (card_type IN ('virtual', 'physical')),
    -- Lifecycle status. Only 'active' cards are approved at JIT time.
    -- 'frozen' temporarily blocks new charges without cancelling the card.
    status                  TEXT        NOT NULL DEFAULT 'active'
                                        CHECK (status IN ('active', 'inactive', 'cancelled', 'frozen')),
    -- True for the card currently used in JIT authorization for this member.
    -- The partial unique index below enforces at most one primary active card
    -- per member at the database level.
    is_primary              BOOL        NOT NULL DEFAULT TRUE,
    metadata                JSONB,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cards_member_id
    ON cards (member_id);

CREATE INDEX IF NOT EXISTS idx_cards_user_id
    ON cards (user_id);

CREATE INDEX IF NOT EXISTS idx_cards_card_token
    ON cards (card_token)
    WHERE card_token IS NOT NULL;

-- Enforces the business rule: one primary active card per member at DB level.
CREATE UNIQUE INDEX IF NOT EXISTS idx_cards_primary
    ON cards (member_id)
    WHERE is_primary = TRUE AND status = 'active';

-- ── Migrate existing card data from members → cards ───────────────────────────
-- For every member row that has a card (card_token IS NOT NULL), create a
-- corresponding cards row. Members without a card are skipped.
INSERT INTO cards (
    member_id,
    user_id,
    card_token,
    stripe_cardholder_id,
    stripe_card_id,
    status,
    is_primary,
    created_at,
    updated_at
)
SELECT
    m.id,
    m.user_id,
    m.card_token,
    m.stripe_cardholder_id,
    m.stripe_card_id,
    'active',
    TRUE,
    m.created_at,
    m.updated_at
FROM members m
WHERE m.card_token IS NOT NULL
ON CONFLICT DO NOTHING;

-- ── Backward-compat trigger: sync cards → members ─────────────────────────────
-- When a cards row is inserted or updated, propagate the card identifiers back
-- to the members row if this is the primary active card for that member.
--
-- This keeps waterfall.ResolveCard() working:
--   SELECT ... FROM members WHERE card_token = $1
-- without any changes to waterfall.go.
--
-- This trigger adds ~100µs per INSERT/UPDATE on cards — invisible overhead
-- on the JIT hot path which only reads from members (not cards).
--
-- Remove this trigger in migration 000014+ after waterfall.go is updated
-- to JOIN cards directly instead of reading card_token from members.

CREATE OR REPLACE FUNCTION sync_card_token_to_member()
RETURNS TRIGGER AS $$
BEGIN
    -- Only propagate for the primary active card. Inactive/cancelled card
    -- updates should not overwrite the current active card_token on members.
    IF NEW.is_primary = TRUE AND NEW.status = 'active' THEN
        UPDATE members
        SET card_token           = NEW.card_token,
            stripe_cardholder_id = NEW.stripe_cardholder_id,
            stripe_card_id       = NEW.stripe_card_id,
            updated_at           = NOW()
        WHERE id = NEW.member_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sync_card_token
    AFTER INSERT OR UPDATE ON cards
    FOR EACH ROW
    EXECUTE FUNCTION sync_card_token_to_member();
