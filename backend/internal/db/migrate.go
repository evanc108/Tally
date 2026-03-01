package db

import (
	"database/sql"
	"embed"
	"fmt"

	"github.com/golang-migrate/migrate/v4"
	"github.com/golang-migrate/migrate/v4/database/postgres"
	"github.com/golang-migrate/migrate/v4/source/iofs"
	_ "github.com/lib/pq"
)

//go:embed migrations/*.sql
var migrationFiles embed.FS

// Migrate runs all pending up-migrations embedded in the binary.
// It is idempotent — safe to call on every boot.
func Migrate(dsn string) error {
	db, err := sql.Open("postgres", dsn)
	if err != nil {
		return fmt.Errorf("open db for migrate: %w", err)
	}
	defer db.Close()

	driver, err := postgres.WithInstance(db, &postgres.Config{})
	if err != nil {
		return fmt.Errorf("create postgres driver: %w", err)
	}

	src, err := iofs.New(migrationFiles, "migrations")
	if err != nil {
		return fmt.Errorf("create iofs source: %w", err)
	}

	m, err := migrate.NewWithInstance("iofs", src, "postgres", driver)
	if err != nil {
		return fmt.Errorf("create migrator: %w", err)
	}

	if err := m.Up(); err != nil && err != migrate.ErrNoChange {
		return fmt.Errorf("run migrations: %w", err)
	}
	return nil
}
