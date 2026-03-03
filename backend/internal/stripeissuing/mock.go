package stripeissuing

import (
	"context"
	"fmt"
	"sync/atomic"
)

// MockClient returns deterministic fake IDs — suitable for local development
// and unit tests without real Stripe credentials.
type MockClient struct {
	counter atomic.Int64
}

// NewMockClient returns a CardIssuingClient that never calls Stripe.
func NewMockClient() CardIssuingClient {
	return &MockClient{}
}

func (m *MockClient) CreateCardholder(_ context.Context, req CreateCardholderRequest) (string, error) {
	n := m.counter.Add(1)
	return fmt.Sprintf("ich_mock_%s_%d", req.ExternalID[:8], n), nil
}

func (m *MockClient) IssueCard(_ context.Context, cardholderID, _ string) (string, string, error) {
	n := m.counter.Add(1)
	cardID := fmt.Sprintf("ic_mock_%d", n)
	return cardID, cardID, nil
}

func (m *MockClient) ApproveAuthorization(_ context.Context, _ string) error { return nil }
func (m *MockClient) DeclineAuthorization(_ context.Context, _ string) error { return nil }
