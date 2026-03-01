-- Migration 000004: Add users table and FK from members.user_id
--
-- users.id is the Clerk user ID (e.g. "user_xxxxxxxxxxxxxxxxxxxxxxxxxx").
-- Clerk owns name/email/phone — we only mirror the ID here to establish
-- referential integrity and give user-level data a home.
--
-- The FK on members.user_id means:
--   1. A user row must exist before a member record can be created.
--   2. Deleting a user cascades to all their member records.

CREATE TABLE users (
    id         TEXT        PRIMARY KEY,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE members
    ADD CONSTRAINT members_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
