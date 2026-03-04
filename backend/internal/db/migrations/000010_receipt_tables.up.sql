-- Migration 000010: Receipt tables for persistence and item assignment.
--
-- receipts        — one row per scanned/entered receipt
-- receipt_items   — line items on the receipt
-- receipt_item_assignments — tracks which member owes which item (or fraction)

-- ── Receipts ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS receipts (
    id                 UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id           UUID        NOT NULL REFERENCES tally_groups(id) ON DELETE CASCADE,
    created_by_user_id TEXT        NOT NULL REFERENCES users(id),
    subtotal_cents     BIGINT      NOT NULL DEFAULT 0,
    tax_cents          BIGINT      NOT NULL DEFAULT 0,
    tip_cents          BIGINT      NOT NULL DEFAULT 0,
    total_cents        BIGINT      NOT NULL DEFAULT 0,
    currency           CHAR(3)     NOT NULL DEFAULT 'USD',
    merchant_name      TEXT,
    status             TEXT        NOT NULL DEFAULT 'draft'
                                   CHECK (status IN ('draft','active','finalized','deleted')),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_receipts_group_id ON receipts (group_id);
CREATE INDEX IF NOT EXISTS idx_receipts_status   ON receipts (group_id, status)
    WHERE status != 'deleted';

-- ── Receipt Items ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS receipt_items (
    id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    receipt_id        UUID        NOT NULL REFERENCES receipts(id) ON DELETE CASCADE,
    name              TEXT        NOT NULL,
    quantity          INT         NOT NULL DEFAULT 1,
    unit_cents        BIGINT      NOT NULL DEFAULT 0,
    total_cents       BIGINT      NOT NULL DEFAULT 0,
    sort_order        INT         NOT NULL DEFAULT 0,
    is_fully_assigned BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_receipt_items_receipt_id ON receipt_items (receipt_id);

-- ── Receipt Item Assignments ─────────────────────────────────────────────────
-- Tracks which member is responsible for which item (or a fraction of it).
-- quantity_numerator/quantity_denominator supports partial claims (e.g. 1/3 of an appetizer).
CREATE TABLE IF NOT EXISTS receipt_item_assignments (
    id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    receipt_item_id      UUID        NOT NULL REFERENCES receipt_items(id) ON DELETE CASCADE,
    member_id            UUID        NOT NULL REFERENCES members(id) ON DELETE CASCADE,
    quantity_numerator   INT         NOT NULL DEFAULT 1,
    quantity_denominator INT         NOT NULL DEFAULT 1,
    amount_cents         BIGINT      NOT NULL DEFAULT 0,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (receipt_item_id, member_id)
);

CREATE INDEX IF NOT EXISTS idx_ria_receipt_item_id ON receipt_item_assignments (receipt_item_id);
CREATE INDEX IF NOT EXISTS idx_ria_member_id       ON receipt_item_assignments (member_id);
