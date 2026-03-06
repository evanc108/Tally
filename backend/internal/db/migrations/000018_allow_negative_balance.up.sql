-- Allow tally_balance_cents to go negative.
-- The iOS UI adds a hardcoded starting balance offset, so the displayed
-- value is always (starting_balance + tally_balance_cents). Negative values
-- represent spending; the CHECK >= 0 constraint blocked autoSettle.
ALTER TABLE members DROP CONSTRAINT IF EXISTS members_tally_balance_cents_check;
