package db

import (
	"database/sql"
	"fmt"
	"time"

	_ "github.com/lib/pq"
	"github.com/redis/go-redis/v9"
)

// Connect returns a tuned PostgreSQL connection pool.
func Connect(dsn string) (*sql.DB, error) {
	pool, err := sql.Open("postgres", dsn)
	if err != nil {
		return nil, fmt.Errorf("opening postgres: %w", err)
	}

	// Tune for a typical containerised workload.
	pool.SetMaxOpenConns(25)
	pool.SetMaxIdleConns(5)
	pool.SetConnMaxLifetime(5 * time.Minute)
	pool.SetConnMaxIdleTime(2 * time.Minute)

	if err := pool.Ping(); err != nil {
		return nil, fmt.Errorf("pinging postgres: %w", err)
	}
	return pool, nil
}

// ConnectRedis returns a Redis client parsed from a redis:// URL.
func ConnectRedis(rawURL string) (*redis.Client, error) {
	opts, err := redis.ParseURL(rawURL)
	if err != nil {
		return nil, fmt.Errorf("parsing redis URL: %w", err)
	}
	return redis.NewClient(opts), nil
}
