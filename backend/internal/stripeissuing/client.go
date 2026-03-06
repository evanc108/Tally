// Package stripeissuing wraps the Stripe Issuing API for cardholder and
// virtual card creation. Use NewRealClient in production and NewMockClient
// in development / tests.
package stripeissuing

import (
	"context"
	"fmt"

	"github.com/stripe/stripe-go/v82"
	"github.com/stripe/stripe-go/v82/issuing/authorization"
	"github.com/stripe/stripe-go/v82/issuing/card"
	"github.com/stripe/stripe-go/v82/issuing/cardholder"
)

// CardIssuingClient abstracts Stripe Issuing so handlers can be tested
// without real Stripe credentials.
type CardIssuingClient interface {
	// CreateCardholder provisions a new Stripe Issuing cardholder and returns
	// the cardholder ID (e.g. "ich_xxx").
	CreateCardholder(ctx context.Context, req CreateCardholderRequest) (cardholderID string, err error)

	// FindCardholderByMemberID returns an existing Stripe cardholder ID for the
	// given Tally member ID (metadata tally_member_id), or empty string if none.
	// Used to reuse a cardholder after fixing requirements in Dashboard and retrying.
	FindCardholderByMemberID(ctx context.Context, memberID string) (cardholderID string, err error)

	// IssueCard creates a virtual card for the cardholder and returns the
	// Stripe card ID ("ic_xxx") used as the card_token for JIT routing.
	IssueCard(ctx context.Context, cardholderID, cardProductID string) (cardID, cardToken string, err error)

	// ApproveAuthorization calls the Stripe API to approve a pending issuing
	// authorization. Must be called within Stripe's 2-second window.
	ApproveAuthorization(ctx context.Context, authID string) error

	// DeclineAuthorization calls the Stripe API to decline a pending issuing
	// authorization.
	DeclineAuthorization(ctx context.Context, authID string) error
}

// CreateCardholderRequest contains the fields needed to create a new cardholder.
type CreateCardholderRequest struct {
	ExternalID   string // Tally member UUID — stored as metadata
	FirstName    string
	LastName     string
	Email        string
	DOBDay       int    // 1-31
	DOBMonth     int    // 1-12
	DOBYear      int    // 4-digit year (cardholder must be 13+)
	AddressLine1 string
	City         string
	State        string
	PostalCode   string
	Country      string
	// Celtic Authorized User Terms: required for Celtic-backed programs. Set when user accepted terms in UI.
	UserTermsAcceptedAt *int64 // Unix timestamp
	ClientIP            string // IP from which user accepted terms
	UserAgent           string // User-Agent from request
}

// ── Real client ───────────────────────────────────────────────────────────────

// realClient has no fields — stripe.Key is set once at startup in NewRealClient.
// Per-method stripe.Key assignments caused a data race under concurrency.
type realClient struct{}

// NewRealClient returns a CardIssuingClient backed by the live Stripe API.
// stripe.Key is set once here; removing per-request global writes eliminates
// the data race that occurs when multiple goroutines call stripe.Key = key.
func NewRealClient(secretKey string) CardIssuingClient {
	stripe.Key = secretKey
	return &realClient{}
}

func (c *realClient) CreateCardholder(ctx context.Context, req CreateCardholderRequest) (string, error) {
	// Fall back to placeholder values when optional address fields are omitted
	// (e.g. dev/test environments). Production callers should always supply the
	// member's real address for Stripe compliance.
	line1 := req.AddressLine1
	if line1 == "" {
		line1 = "123 Main St"
	}
	city := req.City
	if city == "" {
		city = "San Francisco"
	}
	state := req.State
	if state == "" {
		state = "CA"
	}
	postalCode := req.PostalCode
	if postalCode == "" {
		postalCode = "94105"
	}
	country := req.Country
	if country == "" {
		country = "US"
	}

	// Individual (first_name, last_name, dob) is required by Stripe "before activating Cards".
	// Celtic programs also require individual.card_issuing.user_terms_acceptance (ip, date, user_agent).
	dobDay := int64(req.DOBDay)
	dobMonth := int64(req.DOBMonth)
	dobYear := int64(req.DOBYear)
	indiv := &stripe.IssuingCardholderIndividualParams{
		FirstName: stripe.String(req.FirstName),
		LastName:  stripe.String(req.LastName),
		DOB: &stripe.IssuingCardholderIndividualDOBParams{
			Day:   stripe.Int64(dobDay),
			Month: stripe.Int64(dobMonth),
			Year:  stripe.Int64(dobYear),
		},
	}
	if req.UserTermsAcceptedAt != nil && *req.UserTermsAcceptedAt > 0 {
		indiv.CardIssuing = &stripe.IssuingCardholderIndividualCardIssuingParams{
			UserTermsAcceptance: &stripe.IssuingCardholderIndividualCardIssuingUserTermsAcceptanceParams{
				Date:     stripe.Int64(*req.UserTermsAcceptedAt),
				IP:       stripe.String(req.ClientIP),
				UserAgent: stripe.String(req.UserAgent),
			},
		}
	}
	params := &stripe.IssuingCardholderParams{
		Name:       stripe.String(req.FirstName + " " + req.LastName),
		Email:      stripe.String(req.Email),
		Type:       stripe.String(string(stripe.IssuingCardholderTypeIndividual)),
		Status:     stripe.String(string(stripe.IssuingCardholderStatusActive)),
		Individual: indiv,
		Billing: &stripe.IssuingCardholderBillingParams{
			Address: &stripe.AddressParams{
				Line1:      stripe.String(line1),
				City:       stripe.String(city),
				State:      stripe.String(state),
				PostalCode: stripe.String(postalCode),
				Country:    stripe.String(country),
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

// FindCardholderByMemberID returns an existing Stripe Issuing cardholder for the given
// Tally member ID. It lists cardholders (we set metadata["tally_member_id"] in CreateCardholder),
// filters to this member and active status, and only returns one with no outstanding
// requirements (Requirements.PastDue empty) so IssueCard will succeed. We Get each candidate
// because List may not include Requirements, and reusing a cardholder with past_due causes
// IssueCard to fail with "outstanding requirements".
func (c *realClient) FindCardholderByMemberID(ctx context.Context, memberID string) (string, error) {
	params := &stripe.IssuingCardholderListParams{
		ListParams: stripe.ListParams{Context: ctx, Limit: stripe.Int64(100)},
	}
	iter := cardholder.List(params)
	for iter.Next() {
		ch := iter.IssuingCardholder()
		if ch == nil || ch.Metadata["tally_member_id"] != memberID || ch.Status != stripe.IssuingCardholderStatusActive {
			continue
		}
		// List may not populate Requirements; fetch full cardholder to verify no past_due.
		getParams := &stripe.IssuingCardholderParams{}
		getParams.Context = ctx
		full, err := cardholder.Get(ch.ID, getParams)
		if err != nil || full == nil {
			continue
		}
		if full.Requirements != nil && len(full.Requirements.PastDue) > 0 {
			continue
		}
		return ch.ID, nil
	}
	if err := iter.Err(); err != nil {
		return "", fmt.Errorf("stripe ListCardholders: %w", err)
	}
	return "", nil
}

func (c *realClient) IssueCard(ctx context.Context, cardholderID, _ string) (string, string, error) {
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

func (c *realClient) ApproveAuthorization(ctx context.Context, authID string) error {
	params := &stripe.IssuingAuthorizationApproveParams{}
	params.Context = ctx
	if _, err := authorization.Approve(authID, params); err != nil {
		return fmt.Errorf("stripe ApproveAuthorization: %w", err)
	}
	return nil
}

func (c *realClient) DeclineAuthorization(ctx context.Context, authID string) error {
	params := &stripe.IssuingAuthorizationDeclineParams{}
	params.Context = ctx
	if _, err := authorization.Decline(authID, params); err != nil {
		return fmt.Errorf("stripe DeclineAuthorization: %w", err)
	}
	return nil
}
