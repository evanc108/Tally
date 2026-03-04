-- Migration 000016: Add first_name and last_name to users table.
-- Populated from Clerk on POST /v1/users/me so the backend can use
-- the user's real name when creating member rows.

ALTER TABLE users ADD COLUMN IF NOT EXISTS first_name TEXT NOT NULL DEFAULT '';
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_name  TEXT NOT NULL DEFAULT '';
