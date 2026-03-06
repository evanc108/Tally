package stripeissuing

import (
	"context"
	"fmt"
	"sync/atomic"

	"github.com/google/uuid"
)

// MockClient returns unique fake IDs — suitable for local development
// and unit tests without real Stripe credentials. Card IDs include a UUID
// so they stay unique across process restarts and avoid members_card_token_key
// duplicate errors when re-issuing or running tests multiple times.
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

func (m *MockClient) FindCardholderByMemberID(_ context.Context, _ string) (string, error) {
	return "", nil // mock never reuses
}

func (m *MockClient) IssueCard(_ context.Context, cardholderID, _ string) (string, string, error) {
	cardID := fmt.Sprintf("ic_mock_%s", uuid.New().String()[:8])
	return cardID, cardID, nil
}

func (m *MockClient) ApproveAuthorization(_ context.Context, _ string) error { return nil }
func (m *MockClient) DeclineAuthorization(_ context.Context, _ string) error { return nil }
