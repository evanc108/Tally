package config

import "os"

// Config holds all runtime configuration, populated from environment variables.
type Config struct {
	DatabaseURL string
	RedisURL    string
	// WebhookSecret is the HMAC secret for the /v1/auth/jit endpoint (Tally's
	// own signing scheme — not Stripe's).
	WebhookSecret string
	Port          string
	Environment   string
	// Stripe credentials.
	StripeSecretKey         string // Issuing, PaymentMethods, Identity, Financial Connections
	StripeWebhookSecret     string // for stripe.ConstructEvent() on /v1/webhooks/stripe/*
	StripeIssuingCardProduct string // card product ID configured in the Stripe dashboard
	// Clerk — leave empty to disable JWT auth (local development only).
	ClerkJWKSURL string // e.g. https://<clerk-domain>/.well-known/jwks.json
	// DevUserID is injected as the authenticated user when CLERK_JWKS_URL is
	// unset. Never used in production (Validate() blocks that path).
	DevUserID string
}

func Load() *Config {
	return &Config{
		DatabaseURL:              getEnv("DATABASE_URL", "postgres://tally:tally_secret@localhost:5432/tally?sslmode=disable"),
		RedisURL:                 getEnv("REDIS_URL", "redis://localhost:6379"),
		WebhookSecret:            getEnv("WEBHOOK_SECRET", "dev_webhook_secret_change_in_prod"),
		Port:                     getEnv("PORT", "8080"),
		Environment:              getEnv("ENV", "development"),
		StripeSecretKey:          getEnv("STRIPE_SECRET_KEY", ""),
		StripeWebhookSecret:      getEnv("STRIPE_WEBHOOK_SECRET", ""),
		StripeIssuingCardProduct: getEnv("STRIPE_ISSUING_CARD_PRODUCT", ""),
		ClerkJWKSURL:             getEnv("CLERK_JWKS_URL", ""),
		DevUserID:                getEnv("DEV_USER_ID", "dev-user-local"),
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
	if c.StripeSecretKey == "" {
		panic("STRIPE_SECRET_KEY must be set in production — refusing to start without Stripe credentials")
	}
	if c.StripeWebhookSecret == "" {
		panic("STRIPE_WEBHOOK_SECRET must be set in production — refusing to start without Stripe webhook secret")
	}
	if c.ClerkJWKSURL == "" {
		panic("CLERK_JWKS_URL must be set in production — refusing to start without JWT authentication")
	}
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
