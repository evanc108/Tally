package plaid

import (
	"context"
	"fmt"
	"math"
	"time"

	plaidSDK "github.com/plaid/plaid-go/v29/plaid"
)

// RealClient calls the live Plaid /accounts/balance/get endpoint.
// It satisfies the same BalanceClient interface as MockClient.
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
