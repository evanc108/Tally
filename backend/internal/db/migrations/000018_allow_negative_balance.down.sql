-- Restore the non-negative constraint (will fail if any rows are negative).
ALTER TABLE members ADD CONSTRAINT members_tally_balance_cents_check CHECK (tally_balance_cents >= 0);
