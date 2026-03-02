// Package stripeissuing wraps the Stripe Issuing API for cardholder and
// virtual card creation. Use NewRealClient in production and NewMockClient
// in development / tests.
package stripeissuing

import (
	"context"
	"fmt"

	"github.com/stripe/stripe-go/v82"
	"github.com/stripe/stripe-go/v82/issuing/card"
	"github.com/stripe/stripe-go/v82/issuing/cardholder"
)

// CardIssuingClient abstracts Stripe Issuing so handlers can be tested
// without real Stripe credentials.
type CardIssuingClient interface {
	// CreateCardholder provisions a new Stripe Issuing cardholder and returns
	// the cardholder ID (e.g. "ich_xxx").
	CreateCardholder(ctx context.Context, req CreateCardholderRequest) (cardholderID string, err error)

	// IssueCard creates a virtual card for the cardholder and returns the
	// Stripe card ID ("ic_xxx") used as the card_token for JIT routing.
	IssueCard(ctx context.Context, cardholderID, cardProductID string) (cardID, cardToken string, err error)
}

// CreateCardholderRequest contains the fields needed to create a new cardholder.
type CreateCardholderRequest struct {
	ExternalID string // Tally member UUID — stored as metadata
	FirstName  string
	LastName   string
	Email      string
}

// ── Real client ───────────────────────────────────────────────────────────────

type realClient struct {
	secretKey string
}

// NewRealClient returns a CardIssuingClient backed by the live Stripe API.
func NewRealClient(secretKey string) CardIssuingClient {
	return &realClient{secretKey: secretKey}
}

func (c *realClient) CreateCardholder(ctx context.Context, req CreateCardholderRequest) (string, error) {
	stripe.Key = c.secretKey

	params := &stripe.IssuingCardholderParams{
		Name:   stripe.String(req.FirstName + " " + req.LastName),
		Email:  stripe.String(req.Email),
		Type:   stripe.String(string(stripe.IssuingCardholderTypeIndividual)),
		Status: stripe.String(string(stripe.IssuingCardholderStatusActive)),
		Billing: &stripe.IssuingCardholderBillingParams{
			Address: &stripe.AddressParams{
				Line1:      stripe.String("123 Main St"),
				City:       stripe.String("San Francisco"),
				State:      stripe.String("CA"),
				PostalCode: stripe.String("94105"),
				Country:    stripe.String("US"),
			},
		},
	}
	params.AddMetadata("tally_member_id", req.ExternalID)
	params.Context = ctx

	ch, err := cardholder.New(params)
	if err != nil {
		return "", fmt.Errorf("stripe CreateCardholder: %w", err)
	}
	return ch.ID, nil
}

func (c *realClient) IssueCard(ctx context.Context, cardholderID, _ string) (string, string, error) {
	stripe.Key = c.secretKey

	params := &stripe.IssuingCardParams{
		Cardholder: stripe.String(cardholderID),
		Currency:   stripe.String("usd"),
		Type:       stripe.String(string(stripe.IssuingCardTypeVirtual)),
		Status:     stripe.String(string(stripe.IssuingCardStatusActive)),
	}
	params.Context = ctx

	ic, err := card.New(params)
	if err != nil {
		return "", "", fmt.Errorf("stripe IssueCard: %w", err)
	}
	// The card ID is used as card_token — Stripe sends it in webhook events.
	return ic.ID, ic.ID, nil
}
