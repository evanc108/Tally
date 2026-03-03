-- Migration 000010: Circle (tally_groups) metadata expansion
--
-- Adds display_name, description, emoji, color, archive support, and creator
-- attribution to tally_groups.
--
-- The existing name column is kept as-is (internal API slug / unique identifier).
-- display_name is the human-readable label shown in the iOS UI.
--
-- The Go groups handler already accepts display_name in createGroupRequest but
-- discards it (no DB column existed). This migration gives it a target column.
--
-- Backward compatibility:
--   All new columns are nullable. Existing queries that SELECT by column name
--   (id, name, currency) are unaffected. display_name is backfilled from name
--   so existing circles display correctly in the iOS UI without a data fix.

ALTER TABLE tally_groups
    -- Human-readable label for the iOS UI (e.g. "Weekend in Nashville").
    -- Seeded from name for all existing rows.
    ADD COLUMN IF NOT EXISTS display_name       TEXT,
    -- Optional free-text description of the circle's purpose.
    ADD COLUMN IF NOT EXISTS description        TEXT,
    -- Single emoji character as the circle's avatar icon (e.g. '🍕', '🏠').
    ADD COLUMN IF NOT EXISTS emoji              TEXT,
    -- Hex color for iOS UI theming (e.g. '#FF6B6B'). Stored as TEXT to match
    -- Swift Color(hex:) initializer expectations.
    ADD COLUMN IF NOT EXISTS color              TEXT,
    -- Soft archive: archived circles are hidden in the default list view
    -- but their full transaction and ledger history is preserved.
    -- Active circles: archived_at IS NULL
    -- Archived circles: archived_at = timestamp of archival
    ADD COLUMN IF NOT EXISTS archived_at        TIMESTAMPTZ,
    -- The user who created the circle. SET NULL on user delete preserves the
    -- circle's history even if the creator deletes their account.
    ADD COLUMN IF NOT EXISTS creator_user_id    TEXT
                                                REFERENCES users(id) ON DELETE SET NULL,
    -- JSONB escape hatch for future circle-level settings without new migrations.
    ADD COLUMN IF NOT EXISTS metadata           JSONB;

-- Backfill display_name from name for all existing circles.
-- New circles should supply both; this ensures existing circles aren't blank.
UPDATE tally_groups
    SET display_name = name
    WHERE display_name IS NULL;

-- Index for listing circles created by a specific user.
CREATE INDEX IF NOT EXISTS idx_tally_groups_creator
    ON tally_groups (creator_user_id)
    WHERE creator_user_id IS NOT NULL;

-- Partial index for filtering archived circles (admin/history views).
CREATE INDEX IF NOT EXISTS idx_tally_groups_archived
    ON tally_groups (archived_at)
    WHERE archived_at IS NOT NULL;
