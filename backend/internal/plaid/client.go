package plaid

import (
	"context"
	"fmt"
	"math"
	"time"

	plaidSDK "github.com/plaid/plaid-go/v29/plaid"
)

// LinkedAccount is a simplified view of a Plaid account returned during bank
// linking. It contains display-safe fields only (no access tokens).
type LinkedAccount struct {
	AccountID    string
	Name         string
	Mask         string // last 4 digits of account number
	Type         string // e.g. "depository"
	Subtype      string // e.g. "checking", "savings"
	BalanceCents int64
}

// LinkClient covers the Plaid Link flow: creating link tokens, exchanging
// public tokens, and listing accounts.
type LinkClient interface {
	CreateLinkToken(ctx context.Context, userID string) (string, error)
	ExchangePublicToken(ctx context.Context, publicToken string) (accessToken, itemID string, err error)
	GetAccounts(ctx context.Context, accessToken string) ([]LinkedAccount, error)
}

// Client combines balance checking (used by the funding waterfall) with the
// Link flow (used by the bank-linking endpoints).
type Client interface {
	BalanceClient
	LinkClient
}

// RealClient calls the live Plaid API.
// It satisfies the Client interface (BalanceClient + LinkClient).
type RealClient struct {
	api     *plaidSDK.PlaidApiService
	authCtx context.Context // carries PLAID-CLIENT-ID + PLAID-SECRET headers
}

// NewRealClient builds a RealClient for the given environment.
// envStr should be "sandbox", "development", or "production".
func NewRealClient(clientID, secret, envStr string) *RealClient {
	cfg := plaidSDK.NewConfiguration()

	switch envStr {
	case "production":
		cfg.UseEnvironment(plaidSDK.Production)
	default: // "sandbox" or anything else falls back to sandbox
		cfg.UseEnvironment(plaidSDK.Sandbox)
	}

	client := plaidSDK.NewAPIClient(cfg)

	// Credentials are injected per-request via context API keys.
	authCtx := context.WithValue(context.Background(), plaidSDK.ContextAPIKeys, map[string]plaidSDK.APIKey{
		"clientId": {Key: clientID},
		"secret":   {Key: secret},
	})

	return &RealClient{
		api:     client.PlaidApi,
		authCtx: authCtx,
	}
}

// GetAccountBalance returns the available balance in cents for the given
// Plaid access token + account ID pair.
// It merges the caller's context with the stored auth context so that
// cancellation / deadlines are respected.
func (c *RealClient) GetAccountBalance(ctx context.Context, accessToken, accountID string) (int64, error) {
	// Merge caller deadline into auth context.
	mergedCtx := mergeContext(ctx, c.authCtx)

	req := plaidSDK.NewAccountsBalanceGetRequest(accessToken)
	resp, _, err := c.api.AccountsBalanceGet(mergedCtx).
		AccountsBalanceGetRequest(*req).
		Execute()
	if err != nil {
		return 0, fmt.Errorf("plaid: balance get failed: %w", err)
	}

	for _, acct := range resp.GetAccounts() {
		if acct.GetAccountId() == accountID {
			bal := acct.GetBalances()
			available, ok := bal.GetAvailableOk()
			if !ok || available == nil {
				// Fall back to current balance when available is null.
				current, currentOk := bal.GetCurrentOk()
				if !currentOk || current == nil {
					return 0, fmt.Errorf("plaid: no balance data for account %s", accountID)
				}
				return dollarsToСents(*current), nil
			}
			return dollarsToСents(*available), nil
		}
	}

	return 0, fmt.Errorf("plaid: account %s not found in response", accountID)
}

// CreateLinkToken creates a Plaid Link token tied to the given user ID.
// The iOS SDK uses this token to open the Plaid Link UI.
func (c *RealClient) CreateLinkToken(ctx context.Context, userID string) (string, error) {
	mergedCtx := mergeContext(ctx, c.authCtx)

	user := plaidSDK.NewLinkTokenCreateRequestUser(userID)
	req := plaidSDK.NewLinkTokenCreateRequest("Tally", "en", []plaidSDK.CountryCode{plaidSDK.COUNTRYCODE_US}, *user)
	req.SetProducts([]plaidSDK.Products{plaidSDK.PRODUCTS_AUTH})

	resp, _, err := c.api.LinkTokenCreate(mergedCtx).LinkTokenCreateRequest(*req).Execute()
	if err != nil {
		return "", fmt.Errorf("plaid: link token create failed: %w", err)
	}
	return resp.GetLinkToken(), nil
}

// ExchangePublicToken exchanges the short-lived public token from Plaid Link
// for a durable access token and item ID.
func (c *RealClient) ExchangePublicToken(ctx context.Context, publicToken string) (string, string, error) {
	mergedCtx := mergeContext(ctx, c.authCtx)

	req := plaidSDK.NewItemPublicTokenExchangeRequest(publicToken)
	resp, _, err := c.api.ItemPublicTokenExchange(mergedCtx).ItemPublicTokenExchangeRequest(*req).Execute()
	if err != nil {
		return "", "", fmt.Errorf("plaid: token exchange failed: %w", err)
	}
	return resp.GetAccessToken(), resp.GetItemId(), nil
}

// GetAccounts returns all accounts associated with the given access token.
func (c *RealClient) GetAccounts(ctx context.Context, accessToken string) ([]LinkedAccount, error) {
	mergedCtx := mergeContext(ctx, c.authCtx)

	req := plaidSDK.NewAccountsGetRequest(accessToken)
	resp, _, err := c.api.AccountsGet(mergedCtx).AccountsGetRequest(*req).Execute()
	if err != nil {
		return nil, fmt.Errorf("plaid: accounts get failed: %w", err)
	}

	accounts := make([]LinkedAccount, 0, len(resp.GetAccounts()))
	for _, acct := range resp.GetAccounts() {
		bal := acct.GetBalances()
		var balCents int64
		if available, ok := bal.GetAvailableOk(); ok && available != nil {
			balCents = dollarsToСents(*available)
		} else if current, ok := bal.GetCurrentOk(); ok && current != nil {
			balCents = dollarsToСents(*current)
		}
		accounts = append(accounts, LinkedAccount{
			AccountID:    acct.GetAccountId(),
			Name:         acct.GetName(),
			Mask:         acct.GetMask(),
			Type:         string(acct.GetType()),
			Subtype:      string(acct.GetSubtype()),
			BalanceCents: balCents,
		})
	}
	return accounts, nil
}

// dollarsToСents converts a dollar float64 to integer cents, rounding half-up.
func dollarsToСents(dollars float64) int64 {
	return int64(math.Round(dollars * 100))
}

// mergeContext returns a new context that carries the values from valCtx but
// respects the deadline/cancellation of deadlineCtx.
func mergeContext(deadlineCtx, valCtx context.Context) context.Context {
	return &mergedCtx{Context: valCtx, deadline: deadlineCtx}
}

type mergedCtx struct {
	context.Context           // provides Values (API keys)
	deadline        context.Context // provides Done / Deadline / Err
}

func (m *mergedCtx) Done() <-chan struct{}         { return m.deadline.Done() }
func (m *mergedCtx) Err() error                    { return m.deadline.Err() }
func (m *mergedCtx) Deadline() (time.Time, bool)   { return m.deadline.Deadline() }
