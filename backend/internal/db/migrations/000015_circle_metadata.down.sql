-- Reverse migration 000015: remove display_name and archived_at from tally_groups.
DROP INDEX IF EXISTS idx_tally_groups_archived;
ALTER TABLE tally_groups DROP COLUMN IF EXISTS archived_at;
ALTER TABLE tally_groups DROP COLUMN IF EXISTS display_name;
