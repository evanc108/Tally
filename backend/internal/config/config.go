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
	}
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
