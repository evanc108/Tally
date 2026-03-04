-- Migration 000015: Ensure tally_groups has display_name and archived_at columns.
-- These are referenced by the groups handler but may be missing if prior
-- migrations (000010) were consolidated.

ALTER TABLE tally_groups ADD COLUMN IF NOT EXISTS display_name TEXT;
ALTER TABLE tally_groups ADD COLUMN IF NOT EXISTS archived_at  TIMESTAMPTZ;

-- Index for the common filter: WHERE archived_at IS NULL
CREATE INDEX IF NOT EXISTS idx_tally_groups_archived
    ON tally_groups (archived_at) WHERE archived_at IS NULL;
