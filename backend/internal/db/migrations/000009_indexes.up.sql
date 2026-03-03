-- Migration 000009: Add missing performance indexes.
--
-- idx_transactions_status_updated: speeds up the settlement sweep worker which
-- queries WHERE status = 'APPROVED' AND updated_at < NOW() - INTERVAL '30s'.
CREATE INDEX IF NOT EXISTS idx_transactions_status_updated
    ON transactions (status, updated_at);

-- idx_funding_pulls_txn_status: speeds up loading pending funding pulls per
-- transaction in SettleApprovedTransaction.
CREATE INDEX IF NOT EXISTS idx_funding_pulls_txn_status
    ON funding_pulls (transaction_id, status);
