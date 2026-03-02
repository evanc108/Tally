package config

import "os"

// Config holds all runtime configuration, populated from environment variables.
type Config struct {
	DatabaseURL   string
	RedisURL      string
	WebhookSecret string
	Port          string
	Environment   string
	// Plaid credentials — leave empty to use the mock client in development.
	PlaidClientID string
	PlaidSecret   string
	PlaidEnv      string // "sandbox" | "development" | "production"
	// Highnote credentials — leave empty to use the mock client in development.
	HighnoteAPIKey         string // leave empty → mock client
	HighnoteCardProductID  string // card product configured in the Highnote dashboard
	HighnoteWebhookSecret  string // shared secret for verifying Highnote webhook signatures
	// Clerk — leave empty to disable JWT auth (local development only).
	ClerkJWKSURL string // e.g. https://<clerk-domain>/.well-known/jwks.json
	// DevUserID is injected as the authenticated user when CLERK_JWKS_URL is
	// unset. Never used in production (Validate() blocks that path).
	DevUserID string
}

func Load() *Config {
	return &Config{
		DatabaseURL:            getEnv("DATABASE_URL", "postgres://tally:tally_secret@localhost:5432/tally?sslmode=disable"),
		RedisURL:               getEnv("REDIS_URL", "redis://localhost:6379"),
		WebhookSecret:          getEnv("WEBHOOK_SECRET", "dev_webhook_secret_change_in_prod"),
		Port:                   getEnv("PORT", "8080"),
		Environment:            getEnv("ENV", "development"),
		PlaidClientID:          getEnv("PLAID_CLIENT_ID", ""),
		PlaidSecret:            getEnv("PLAID_SECRET", ""),
		PlaidEnv:               getEnv("PLAID_ENV", "sandbox"),
		HighnoteAPIKey:         getEnv("HIGHNOTE_API_KEY", ""),
		HighnoteCardProductID:  getEnv("HIGHNOTE_CARD_PRODUCT_ID", "dev_card_product"),
		HighnoteWebhookSecret:  getEnv("HIGHNOTE_WEBHOOK_SECRET", "dev_hn_webhook_secret"),
		ClerkJWKSURL:           getEnv("CLERK_JWKS_URL", ""),
		DevUserID:              getEnv("DEV_USER_ID", "dev-user-local"),
	}
}

// Validate panics at startup if production-critical secrets are still set to
// their insecure development defaults. Call this immediately after Load().
func (c *Config) Validate() {
	if c.Environment != "production" {
		return
	}
	if c.WebhookSecret == "dev_webhook_secret_change_in_prod" {
		panic("WEBHOOK_SECRET must be overridden in production — refusing to start with default value")
	}
	if c.HighnoteWebhookSecret == "dev_hn_webhook_secret" {
		panic("HIGHNOTE_WEBHOOK_SECRET must be overridden in production — refusing to start with default value")
	}
	if c.HighnoteCardProductID == "dev_card_product" {
		panic("HIGHNOTE_CARD_PRODUCT_ID must be overridden in production — refusing to start with default value")
	}
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
