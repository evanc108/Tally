// Package stripeidentity wraps the Stripe Identity API for KYC verification.
package stripeidentity

import (
	"context"
	"fmt"
	"sync/atomic"

	"github.com/stripe/stripe-go/v82"
	"github.com/stripe/stripe-go/v82/identity/verificationsession"
)

// IdentityClient abstracts Stripe Identity so handlers can be tested without
// real Stripe credentials.
type IdentityClient interface {
	// CreateVerificationSession starts a new Stripe Identity session.
	// Returns the session ID and the URL the iOS app should open.
	CreateVerificationSession(ctx context.Context, memberID string) (sessionID, url string, err error)
}

// ── Real client ───────────────────────────────────────────────────────────────

type realClient struct {
	secretKey string
}

// NewRealClient returns an IdentityClient backed by the live Stripe Identity API.
func NewRealClient(secretKey string) IdentityClient {
	return &realClient{secretKey: secretKey}
}

func (c *realClient) CreateVerificationSession(ctx context.Context, memberID string) (string, string, error) {
	stripe.Key = c.secretKey

	params := &stripe.IdentityVerificationSessionParams{
		Type: stripe.String(string(stripe.IdentityVerificationSessionTypeDocument)),
	}
	params.AddMetadata("tally_member_id", memberID)
	params.Context = ctx

	session, err := verificationsession.New(params)
	if err != nil {
		return "", "", fmt.Errorf("stripe CreateVerificationSession: %w", err)
	}
	return session.ID, session.URL, nil
}

// ── Mock client ───────────────────────────────────────────────────────────────

type mockClient struct {
	counter atomic.Int64
}

// NewMockClient returns an IdentityClient that never calls Stripe.
func NewMockClient() IdentityClient {
	return &mockClient{}
}

func (m *mockClient) CreateVerificationSession(_ context.Context, memberID string) (string, string, error) {
	n := m.counter.Add(1)
	prefix := memberID
	if len(prefix) > 8 {
		prefix = prefix[:8]
	}
	sessionID := fmt.Sprintf("vs_mock_%s_%d", prefix, n)
	url := fmt.Sprintf("https://verify.stripe.com/mock/%s", sessionID)
	return sessionID, url, nil
}
