// Package stripepayment wraps the Stripe PaymentIntents and SetupIntents APIs.
// SetupIntent is used to attach a debit card (PaymentMethod) to a member.
// PaymentIntent is used at settlement time to charge a member's card.
package stripepayment

import (
	"context"
	"fmt"
	"sync/atomic"

	"github.com/stripe/stripe-go/v82"
	"github.com/stripe/stripe-go/v82/paymentintent"
	"github.com/stripe/stripe-go/v82/setupintent"
)

// PaymentClient abstracts Stripe payment operations so handlers can be tested
// without real Stripe credentials.
type PaymentClient interface {
	// CreateSetupIntent creates a Stripe SetupIntent for attaching a debit
	// card. Returns the client_secret the iOS app uses to complete the flow.
	CreateSetupIntent(ctx context.Context, customerID string) (clientSecret string, err error)

	// ChargePaymentMethod charges an existing PaymentMethod. The idempotencyKey
	// is passed as the Stripe idempotency key header to prevent double charges
	// on retries.
	ChargePaymentMethod(ctx context.Context, pmID string, amountCents int64, currency, idempotencyKey string) (chargeID string, err error)
}

// ── Real client ───────────────────────────────────────────────────────────────

type realClient struct {
	secretKey string
}

// NewRealClient returns a PaymentClient backed by the live Stripe API.
func NewRealClient(secretKey string) PaymentClient {
	return &realClient{secretKey: secretKey}
}

func (c *realClient) CreateSetupIntent(ctx context.Context, customerID string) (string, error) {
	stripe.Key = c.secretKey

	params := &stripe.SetupIntentParams{
		PaymentMethodTypes: []*string{stripe.String("us_bank_account")},
	}
	if customerID != "" {
		params.Customer = stripe.String(customerID)
	}
	params.Context = ctx

	si, err := setupintent.New(params)
	if err != nil {
		return "", fmt.Errorf("stripe CreateSetupIntent: %w", err)
	}
	return si.ClientSecret, nil
}

func (c *realClient) ChargePaymentMethod(ctx context.Context, pmID string, amountCents int64, currency, idempotencyKey string) (string, error) {
	stripe.Key = c.secretKey

	params := &stripe.PaymentIntentParams{
		Amount:        stripe.Int64(amountCents),
		Currency:      stripe.String(currency),
		PaymentMethod: stripe.String(pmID),
		Confirm:       stripe.Bool(true),
		// off_session = card-not-present charge during settlement (no 3DS)
		OffSession: stripe.Bool(true),
	}
	params.Context = ctx
	params.SetIdempotencyKey(idempotencyKey)

	pi, err := paymentintent.New(params)
	if err != nil {
		return "", fmt.Errorf("stripe ChargePaymentMethod: %w", err)
	}
	return pi.ID, nil
}

// ── Mock client ───────────────────────────────────────────────────────────────

type mockClient struct {
	counter atomic.Int64
}

// NewMockClient returns a PaymentClient that never calls Stripe.
func NewMockClient() PaymentClient {
	return &mockClient{}
}

func (m *mockClient) CreateSetupIntent(_ context.Context, _ string) (string, error) {
	n := m.counter.Add(1)
	return fmt.Sprintf("seti_mock_%d_secret_mock", n), nil
}

func (m *mockClient) ChargePaymentMethod(_ context.Context, pmID string, amountCents int64, _, _ string) (string, error) {
	n := m.counter.Add(1)
	return fmt.Sprintf("pi_mock_%s_%d_%d", pmID, amountCents, n), nil
}
