-- Add photo column to tally_groups for circle cover images.
-- Stores compressed JPEG bytes directly in PostgreSQL.
ALTER TABLE tally_groups ADD COLUMN IF NOT EXISTS photo BYTEA;
