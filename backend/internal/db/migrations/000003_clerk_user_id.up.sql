-- Migration 000003: Change members.user_id from UUID to TEXT
--
-- Clerk user IDs are strings of the form "user_xxxxxxxxxxxxxxxxxxxxxxxxxx"
-- (not valid UUIDs). This migration relaxes the column type to TEXT so the
-- Clerk sub claim can be stored directly without mapping.

ALTER TABLE members
    DROP CONSTRAINT IF EXISTS members_group_id_user_id_key;

ALTER TABLE members
    ALTER COLUMN user_id TYPE TEXT USING user_id::TEXT;

ALTER TABLE members
    ADD CONSTRAINT members_group_id_user_id_key UNIQUE (group_id, user_id);
