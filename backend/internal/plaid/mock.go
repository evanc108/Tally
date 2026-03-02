// Package plaid wraps Plaid balance checks. In development / CI the MockClient
// is used; swap it for the official Plaid Go SDK in production.
package plaid

import (
	"context"
	"fmt"
	"math/rand"
	"sync"
	"time"
)

// BalanceClient is the interface both the mock and the real Plaid client satisfy.
type BalanceClient interface {
	GetAccountBalance(ctx context.Context, accessToken, accountID string) (int64, error)
}

// MockClient simulates Plaid's /accounts/balance/get endpoint.
// It is safe for concurrent use.
type MockClient struct {
	mu          sync.RWMutex
	balances    map[string]int64 // key: accessToken+":"+accountID
	latency     time.Duration
	errorRate   float64 // 0.0–1.0; probability of returning a transient error
}

// NewMockClient returns a MockClient with realistic defaults:
//   - 50 ms simulated round-trip latency
//   - 2 % transient error rate
func NewMockClient() *MockClient {
	return &MockClient{
		balances:  make(map[string]int64),
		latency:   50 * time.Millisecond,
		errorRate: 0.02,
	}
}

// SeedBalance pre-populates a balance for deterministic tests.
func (c *MockClient) SeedBalance(accessToken, accountID string, balanceCents int64) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.balances[accessToken+":"+accountID] = balanceCents
}

// GetAccountBalance returns the available balance in cents for the account.
// Unseeded accounts get a random balance between $0 and $5,000.
func (c *MockClient) GetAccountBalance(ctx context.Context, accessToken, accountID string) (int64, error) {
	// Simulate network latency — respect context cancellation.
	select {
	case <-ctx.Done():
		return 0, fmt.Errorf("plaid: context cancelled: %w", ctx.Err())
	case <-time.After(c.latency):
	}

	// Simulate transient Plaid errors (rate limit, upstream timeout, etc.).
	if rand.Float64() < c.errorRate {
		return 0, fmt.Errorf("plaid: transient error (simulated)")
	}

	c.mu.RLock()
	defer c.mu.RUnlock()

	key := accessToken + ":" + accountID
	if bal, ok := c.balances[key]; ok {
		return bal, nil
	}

	// Default: random balance $0–$5,000 for unseen accounts.
	return int64(rand.Intn(500_001)), nil
}

// ── Link flow mock methods ─────────────────────────────────────────────────────

// CreateLinkToken returns a deterministic mock link token for the given user.
func (c *MockClient) CreateLinkToken(_ context.Context, userID string) (string, error) {
	return "link-sandbox-mock-" + userID, nil
}

// ExchangePublicToken converts a mock public token into a mock access token and
// item ID. The tokens are deterministic so tests can predict them.
func (c *MockClient) ExchangePublicToken(_ context.Context, publicToken string) (string, string, error) {
	select {
	case <-time.After(20 * time.Millisecond):
	}
	return "access-sandbox-mock-" + publicToken, "item-mock-" + publicToken, nil
}

// GetAccounts returns two fixed mock accounts (checking + savings).
func (c *MockClient) GetAccounts(_ context.Context, accessToken string) ([]LinkedAccount, error) {
	select {
	case <-time.After(20 * time.Millisecond):
	}
	return []LinkedAccount{
		{
			AccountID:    accessToken + "-checking",
			Name:         "Mock Checking",
			Mask:         "0001",
			Type:         "depository",
			Subtype:      "checking",
			BalanceCents: 250_000,
		},
		{
			AccountID:    accessToken + "-savings",
			Name:         "Mock Savings",
			Mask:         "0002",
			Type:         "depository",
			Subtype:      "savings",
			BalanceCents: 500_000,
		},
	}, nil
}
