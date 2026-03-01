package highnote

import (
	"context"
	"fmt"
	"math/rand"
	"sync"
	"time"

	"github.com/google/uuid"
)

// MockClient simulates Highnote card-issuing operations in memory.
// It is safe for concurrent use. Configurable latency and error rate
// mirror the Plaid mock pattern for consistency.
type MockClient struct {
	mu          sync.RWMutex
	cardholders map[string]string // cardholderID → externalID
	cards       map[string]string // cardID → cardholderID
	wallets     map[string]int64  // cardholderID → balance cents
	latency     time.Duration
	errorRate   float64 // 0.0–1.0 probability of returning a transient error
}

// NewMockClient returns a MockClient with realistic defaults:
//   - 20 ms simulated round-trip latency
//   - 2 % transient error rate
func NewMockClient() *MockClient {
	return &MockClient{
		cardholders: make(map[string]string),
		cards:       make(map[string]string),
		wallets:     make(map[string]int64),
		latency:     20 * time.Millisecond,
		errorRate:   0.02,
	}
}

// SeedWallet pre-populates a wallet balance for deterministic tests.
func (c *MockClient) SeedWallet(cardholderID string, balanceCents int64) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.wallets[cardholderID] = balanceCents
}

func (c *MockClient) CreateCardholder(ctx context.Context, req CreateCardholderRequest) (string, error) {
	if err := c.simulate(ctx); err != nil {
		return "", err
	}
	id := "mock_cardholder_" + uuid.New().String()
	c.mu.Lock()
	c.cardholders[id] = req.ExternalID
	c.mu.Unlock()
	return id, nil
}

func (c *MockClient) IssueCard(ctx context.Context, cardholderID, _ string) (string, string, error) {
	if err := c.simulate(ctx); err != nil {
		return "", "", err
	}
	c.mu.RLock()
	_, ok := c.cardholders[cardholderID]
	c.mu.RUnlock()
	if !ok {
		return "", "", fmt.Errorf("highnote mock: cardholder %s not found", cardholderID)
	}

	cardID := "mock_card_" + uuid.New().String()
	cardToken := "mock_tok_" + uuid.New().String()

	c.mu.Lock()
	c.cards[cardID] = cardholderID
	c.mu.Unlock()
	return cardID, cardToken, nil
}

func (c *MockClient) LoadWallet(ctx context.Context, cardholderID string, amountCents int64) error {
	if err := c.simulate(ctx); err != nil {
		return err
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	c.wallets[cardholderID] += amountCents
	return nil
}

// simulate blocks for the configured latency, respects context cancellation,
// and occasionally returns a transient error.
func (c *MockClient) simulate(ctx context.Context) error {
	select {
	case <-ctx.Done():
		return fmt.Errorf("highnote mock: context cancelled: %w", ctx.Err())
	case <-time.After(c.latency):
	}
	if rand.Float64() < c.errorRate {
		return fmt.Errorf("highnote mock: transient error (simulated)")
	}
	return nil
}
