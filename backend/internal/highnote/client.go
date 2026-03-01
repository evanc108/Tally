// Package highnote wraps Highnote card-issuing operations.
//
// In development / CI use NewMockClient(). Swap in NewRealClient(apiKey)
// when live Highnote credentials are available.
//
// Highnote uses a GraphQL API. The real client sends HTTP POST requests with
// GraphQL mutation bodies. The mock keeps everything in memory.
package highnote

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

const highnoteGraphQLEndpoint = "https://api.us-west-2.highnote.com/graphql"

// CardIssuingClient defines the Highnote operations Tally uses.
type CardIssuingClient interface {
	// CreateCardholder registers a person with Highnote (required before issuing a card).
	CreateCardholder(ctx context.Context, req CreateCardholderRequest) (cardholderID string, err error)
	// IssueCard creates a new virtual card for an existing cardholder.
	IssueCard(ctx context.Context, cardholderID, cardProductID string) (cardID, cardToken string, err error)
	// LoadWallet credits a cardholder's Highnote account balance.
	LoadWallet(ctx context.Context, cardholderID string, amountCents int64) error
}

// CreateCardholderRequest carries the minimum fields Highnote requires.
type CreateCardholderRequest struct {
	ExternalID string // our member UUID — stored in Highnote for cross-reference
	FirstName  string
	LastName   string
	Email      string
}

// ── Real client (stub) ────────────────────────────────────────────────────────

// RealClient sends live GraphQL mutations to the Highnote API.
// Wire this in main.go by calling NewRealClient(cfg.HighnoteAPIKey) when you
// have production credentials.
type RealClient struct {
	apiKey     string
	httpClient *http.Client
}

// NewRealClient returns a RealClient authenticated with apiKey.
func NewRealClient(apiKey string) *RealClient {
	return &RealClient{
		apiKey: apiKey,
		httpClient: &http.Client{
			Timeout: 10 * time.Second,
		},
	}
}

func (c *RealClient) CreateCardholder(ctx context.Context, req CreateCardholderRequest) (string, error) {
	const mutation = `mutation CreateCardholder($input: CreateCardholderInput!) {
		createCardholder(input: $input) { id }
	}`
	input := map[string]any{
		"externalId": req.ExternalID,
		"firstName":  req.FirstName,
		"lastName":   req.LastName,
		"email":      req.Email,
	}
	var resp struct {
		Data struct {
			CreateCardholder struct{ ID string `json:"id"` } `json:"createCardholder"`
		} `json:"data"`
		Errors []struct{ Message string `json:"message"` } `json:"errors"`
	}
	if err := c.gql(ctx, mutation, map[string]any{"input": input}, &resp); err != nil {
		return "", fmt.Errorf("highnote CreateCardholder: %w", err)
	}
	if len(resp.Errors) > 0 {
		return "", fmt.Errorf("highnote CreateCardholder: %s", resp.Errors[0].Message)
	}
	return resp.Data.CreateCardholder.ID, nil
}

func (c *RealClient) IssueCard(ctx context.Context, cardholderID, cardProductID string) (string, string, error) {
	const mutation = `mutation IssueCard($input: IssuePaymentCardInput!) {
		issuePaymentCard(input: $input) { id cardToken }
	}`
	input := map[string]any{
		"cardholderId":    cardholderID,
		"cardProductId":   cardProductID,
		"cardPresenceType": "VIRTUAL",
	}
	var resp struct {
		Data struct {
			IssuePaymentCard struct {
				ID        string `json:"id"`
				CardToken string `json:"cardToken"`
			} `json:"issuePaymentCard"`
		} `json:"data"`
		Errors []struct{ Message string `json:"message"` } `json:"errors"`
	}
	if err := c.gql(ctx, mutation, map[string]any{"input": input}, &resp); err != nil {
		return "", "", fmt.Errorf("highnote IssueCard: %w", err)
	}
	if len(resp.Errors) > 0 {
		return "", "", fmt.Errorf("highnote IssueCard: %s", resp.Errors[0].Message)
	}
	card := resp.Data.IssuePaymentCard
	return card.ID, card.CardToken, nil
}

func (c *RealClient) LoadWallet(ctx context.Context, cardholderID string, amountCents int64) error {
	const mutation = `mutation LoadWallet($input: CreateWalletTransactionInput!) {
		createWalletTransaction(input: $input) { id }
	}`
	input := map[string]any{
		"cardholderId": cardholderID,
		"amount": map[string]any{
			"value":        amountCents,
			"currencyCode": "USD",
		},
		"type": "CREDIT",
	}
	var resp struct {
		Errors []struct{ Message string `json:"message"` } `json:"errors"`
	}
	if err := c.gql(ctx, mutation, map[string]any{"input": input}, &resp); err != nil {
		return fmt.Errorf("highnote LoadWallet: %w", err)
	}
	if len(resp.Errors) > 0 {
		return fmt.Errorf("highnote LoadWallet: %s", resp.Errors[0].Message)
	}
	return nil
}

// gql executes a GraphQL mutation against the Highnote endpoint.
func (c *RealClient) gql(ctx context.Context, query string, variables map[string]any, dst any) error {
	body, err := json.Marshal(map[string]any{"query": query, "variables": variables})
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, highnoteGraphQLEndpoint, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+c.apiKey)

	res, err := c.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()

	raw, err := io.ReadAll(res.Body)
	if err != nil {
		return err
	}
	if res.StatusCode != http.StatusOK {
		return fmt.Errorf("highnote HTTP %d: %s", res.StatusCode, raw)
	}
	return json.Unmarshal(raw, dst)
}
