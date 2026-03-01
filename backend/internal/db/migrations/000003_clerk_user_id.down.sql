-- Rollback 000003: Restore members.user_id to UUID.
--
-- WARNING: Only safe on a fresh database or before any Clerk string IDs have
-- been written. Existing rows with non-UUID user_id values will cause this
-- migration to fail.

ALTER TABLE members
    DROP CONSTRAINT IF EXISTS members_group_id_user_id_key;

ALTER TABLE members
    ALTER COLUMN user_id TYPE UUID USING user_id::UUID;

ALTER TABLE members
    ADD CONSTRAINT members_group_id_user_id_key UNIQUE (group_id, user_id);
