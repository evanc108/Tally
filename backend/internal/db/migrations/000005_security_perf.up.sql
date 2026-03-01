-- Migration 000005: Security & performance improvements
--
-- 1. leader_pre_authorized_at: replaces the static boolean with a timestamped
--    authorization so the application can enforce a 24-hour validity window for
--    Tier 4 (leader overwrite) rather than trusting a stale flag indefinitely.
--
-- 2. Missing indexes on funding_pulls to speed up reporting and settlement
--    queries that filter by funding_type or status.

ALTER TABLE members
    ADD COLUMN IF NOT EXISTS leader_pre_authorized_at TIMESTAMPTZ;

-- Index for settlement queries that filter by funding_type.
CREATE INDEX IF NOT EXISTS idx_funding_pulls_funding_type
    ON funding_pulls (funding_type);

-- Index for async workers that poll for PENDING / FAILED pulls.
CREATE INDEX IF NOT EXISTS idx_funding_pulls_status
    ON funding_pulls (status);
