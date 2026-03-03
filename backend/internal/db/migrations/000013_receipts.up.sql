-- Migration 000013: Persisted receipts (itemized bills / recipes)
--
-- The receipt parser (POST /v1/receipts/parse) is currently stateless — it
-- parses and returns, never saving anything. This migration adds three tables
-- so receipts can be stored per circle, linked to a transaction, and split
-- item-by-item among members.
--
-- Three tables:
--
--   receipts                  — header: linked to a circle, optionally to a
--                               transaction. Stores aggregate totals (subtotal,
--                               tax, tip, total), parse confidence, and raw text.
--
--   receipt_items             — one row per line item, mirroring ReceiptItem in
--                               receipts/types.go (name, quantity, unit_cents,
--                               total_cents). sort_order preserves display order.
--
--   receipt_item_assignments  — which portion of a line item each member claims.
--                               Fractional splits supported via numerator/denominator
--                               (e.g. two people splitting one entrée = 1/2 each).
--                               amount_cents is pre-computed and stored to lock
--                               rounding at assignment time.
--
-- Backward compatibility:
--   The existing parse endpoint continues to work unchanged (stateless).
--   Persisting is additive — the handler gains an optional save path when
--   circle_id is provided and the caller opts in.

-- ── Receipt headers ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS receipts (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    -- The circle this receipt belongs to.
    group_id                UUID        NOT NULL REFERENCES tally_groups(id) ON DELETE CASCADE,
    -- Optional link to the transaction that this receipt corresponds to.
    -- NULL when a receipt is saved before a card swipe (pre-split planning)
    -- or for cash purchases. SET NULL on transaction delete preserves the receipt.
    transaction_id          UUID        REFERENCES transactions(id) ON DELETE SET NULL,
    -- The user who captured/submitted this receipt.
    created_by_user_id      TEXT        REFERENCES users(id) ON DELETE SET NULL,
    -- Aggregate totals in cents. All nullable: OCR may not parse every field.
    -- These mirror the *int64 optional fields in ParsedReceipt (receipts/types.go).
    subtotal_cents          BIGINT      CHECK (subtotal_cents >= 0),
    tax_cents               BIGINT      CHECK (tax_cents >= 0),
    tip_cents               BIGINT      CHECK (tip_cents >= 0),
    total_cents             BIGINT      CHECK (total_cents >= 0),
    currency                CHAR(3)     NOT NULL DEFAULT 'USD',
    -- Parse quality from the OCR/parser. NUMERIC(5,4) stores values like 0.9375
    -- without float drift. Mirrors ParsedReceipt.Confidence (float64 in Go).
    confidence              NUMERIC(5,4) CHECK (confidence BETWEEN 0 AND 1),
    -- Parse warnings from the parser (e.g. ["item_total_mismatch"]).
    -- Stored as JSONB text array to mirror ParsedReceipt.Warnings []string.
    warnings                JSONB       NOT NULL DEFAULT '[]',
    -- Merchant name from OCR (may differ from transactions.merchant_name which
    -- comes from the card network).
    merchant_name           TEXT,
    -- Lifecycle:
    --   draft     — items captured, assignments not yet confirmed
    --   finalized — assignments locked; ready to use for splitting
    --   deleted   — soft-deleted; excluded from default queries
    status                  TEXT        NOT NULL DEFAULT 'draft'
                                        CHECK (status IN ('draft', 'finalized', 'deleted')),
    -- Raw OCR text preserved for debugging and re-parsing without re-upload.
    raw_text                TEXT,
    metadata                JSONB,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- All receipts for a circle, most recent first (the common list query).
CREATE INDEX IF NOT EXISTS idx_receipts_group_id
    ON receipts (group_id);

-- Partial covering index for the active receipt feed (excludes deleted).
-- Supports: SELECT * FROM receipts WHERE group_id = $1 AND status != 'deleted'
--           ORDER BY created_at DESC
CREATE INDEX IF NOT EXISTS idx_receipts_group_active
    ON receipts (group_id, created_at DESC)
    WHERE status != 'deleted';

-- Lookup receipts linked to a specific transaction (usually 0 or 1 per txn).
CREATE INDEX IF NOT EXISTS idx_receipts_transaction_id
    ON receipts (transaction_id)
    WHERE transaction_id IS NOT NULL;

-- ── Receipt line items ────────────────────────────────────────────────────────
-- One row per parsed line item, in receipt display order (sort_order).
-- Mirrors ReceiptItem struct in backend/internal/receipts/types.go.
CREATE TABLE IF NOT EXISTS receipt_items (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    receipt_id          UUID        NOT NULL REFERENCES receipts(id) ON DELETE CASCADE,
    -- Item name as parsed from the receipt text (e.g. "Margherita Pizza").
    name                TEXT        NOT NULL,
    -- Quantity as an integer (e.g. 2 for "2x Burger"). 0 for ambiguous qty.
    quantity            INT         NOT NULL DEFAULT 1 CHECK (quantity >= 0),
    -- Per-unit price in cents.
    unit_cents          BIGINT      NOT NULL CHECK (unit_cents >= 0),
    -- Total for this line item. May differ from quantity * unit_cents due to
    -- discounts or parsing imprecision — store what the receipt shows.
    total_cents         BIGINT      NOT NULL CHECK (total_cents >= 0),
    -- Preserves the order items appear on the receipt for display.
    sort_order          INT         NOT NULL DEFAULT 0,
    -- True when all total_cents for this item have been assigned to members.
    -- Set by the application after saving assignments.
    is_fully_assigned   BOOL        NOT NULL DEFAULT FALSE,
    metadata            JSONB,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_receipt_items_receipt_id
    ON receipt_items (receipt_id);

-- ── Receipt item assignments ───────────────────────────────────────────────────
-- Records which member claims which portion of a receipt line item.
--
-- Fractional quantities: if two members share one pizza, each gets
-- quantity_numerator=1, quantity_denominator=2.
--
-- amount_cents is DELIBERATELY DENORMALIZED (pre-computed).
-- Reason: quantity_numerator / quantity_denominator * total_cents involves
-- integer division. Rounding must happen exactly once at assignment time —
-- not recalculated on every read. Storing the rounded cents amount is the
-- fintech-correct approach (same reasoning as BIGINT cents over NUMERIC).
--
-- The sum of amount_cents across all assignments for an item should equal
-- the item's total_cents. This invariant is enforced at the application layer
-- (not at DB level, because rounding distributes remainder deterministically
-- at assignment time rather than via a constraint that would deadlock).
CREATE TABLE IF NOT EXISTS receipt_item_assignments (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    receipt_item_id         UUID        NOT NULL REFERENCES receipt_items(id) ON DELETE CASCADE,
    -- The circle member who claims this portion of the item.
    member_id               UUID        NOT NULL REFERENCES members(id) ON DELETE CASCADE,
    -- Fractional share of the item (default = whole item = 1/1).
    -- For three-way share of one appetizer: 1/3 each.
    quantity_numerator      INT         NOT NULL DEFAULT 1 CHECK (quantity_numerator > 0),
    quantity_denominator    INT         NOT NULL DEFAULT 1 CHECK (quantity_denominator > 0),
    -- Pre-computed cent amount for this assignment. Locked at assignment time.
    amount_cents            BIGINT      NOT NULL CHECK (amount_cents >= 0),
    metadata                JSONB,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- One assignment row per (item, member) pair.
    -- To increase a member's share, update quantity_numerator — don't insert twice.
    UNIQUE (receipt_item_id, member_id)
);

CREATE INDEX IF NOT EXISTS idx_ria_receipt_item_id
    ON receipt_item_assignments (receipt_item_id);

CREATE INDEX IF NOT EXISTS idx_ria_member_id
    ON receipt_item_assignments (member_id);
