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
	"github.com/stripe/stripe-go/v82/paymentmethod"
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

	// RetrievePaymentMethod verifies that a PaymentMethod exists in Stripe.
	// Returns an error if the PM is not found or otherwise invalid.
	RetrievePaymentMethod(ctx context.Context, pmID string) error
}

// ── Real client ───────────────────────────────────────────────────────────────

// realClient has no fields — stripe.Key is set once at startup in NewRealClient.
type realClient struct{}

// NewRealClient returns a PaymentClient backed by the live Stripe API.
// stripe.Key is set once here; removing per-request global writes eliminates
// the data race that occurs when multiple goroutines call stripe.Key = key.
func NewRealClient(secretKey string) PaymentClient {
	stripe.Key = secretKey
	return &realClient{}
}

func (c *realClient) CreateSetupIntent(ctx context.Context, customerID string) (string, error) {
	params := &stripe.SetupIntentParams{
		// card + off_session: supports debit/credit cards and allows the PM to
		// be charged without the cardholder present (required for settlement).
		PaymentMethodTypes: []*string{stripe.String("card")},
		Usage:              stripe.String("off_session"),
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

func (c *realClient) RetrievePaymentMethod(ctx context.Context, pmID string) error {
	params := &stripe.PaymentMethodParams{}
	params.Context = ctx
	if _, err := paymentmethod.Get(pmID, params); err != nil {
		return fmt.Errorf("stripe RetrievePaymentMethod: %w", err)
	}
	return nil
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

func (m *mockClient) RetrievePaymentMethod(_ context.Context, _ string) error {
	return nil
}
