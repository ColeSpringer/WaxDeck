// Package db owns waxdeck.db: WaxDeck's own state beside (never inside)
// the WaxBin catalog. One dedicated write connection and a small read
// pool, WAL with synchronous=NORMAL, and a busy timeout as
// belt-and-braces; intra-process SQLITE_BUSY is structurally avoided
// rather than retried.
package db

import (
	"context"
	"database/sql"
	"fmt"

	_ "modernc.org/sqlite"
)

// DB is the open database pair: w serializes every write, r serves
// concurrent reads.
type DB struct {
	w *sql.DB
	r *sql.DB
}

// migrations are applied in order; user_version tracks the last applied
// index + 1. Migrations are append-only.
var migrations = []string{
	`CREATE TABLE listen_sessions (
		id            INTEGER PRIMARY KEY,
		user_id       TEXT    NOT NULL,
		session_id    TEXT    NOT NULL,
		item_pid      TEXT    NOT NULL,
		media_type    TEXT    NOT NULL,
		started_at_ns INTEGER NOT NULL,
		ms_played     INTEGER NOT NULL,
		finished      INTEGER NOT NULL DEFAULT 0,
		client        TEXT    NOT NULL DEFAULT '',
		source        TEXT    NOT NULL DEFAULT 'live',
		received_at_ns INTEGER NOT NULL,
		UNIQUE (user_id, session_id)
	);
	CREATE INDEX listen_sessions_by_item ON listen_sessions (user_id, item_pid, started_at_ns);`,
}

// Open opens (creating if needed) the database at path and applies
// pending migrations.
func Open(ctx context.Context, path string) (*DB, error) {
	dsn := "file:" + path +
		"?_pragma=journal_mode(WAL)" +
		"&_pragma=synchronous(NORMAL)" +
		"&_pragma=busy_timeout(10000)" +
		"&_pragma=foreign_keys(ON)"

	w, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, fmt.Errorf("db: opening %s: %w", path, err)
	}
	w.SetMaxOpenConns(1)

	r, err := sql.Open("sqlite", dsn)
	if err != nil {
		w.Close()
		return nil, fmt.Errorf("db: opening read pool: %w", err)
	}
	r.SetMaxOpenConns(8)

	d := &DB{w: w, r: r}
	if err := d.migrate(ctx); err != nil {
		d.Close()
		return nil, err
	}
	return d, nil
}

func (d *DB) migrate(ctx context.Context) error {
	var version int
	if err := d.w.QueryRowContext(ctx, "PRAGMA user_version").Scan(&version); err != nil {
		return fmt.Errorf("db: reading schema version: %w", err)
	}
	if version > len(migrations) {
		return fmt.Errorf("db: schema version %d is newer than this build understands (%d); refusing to open", version, len(migrations))
	}
	for i := version; i < len(migrations); i++ {
		tx, err := d.w.BeginTx(ctx, nil)
		if err != nil {
			return fmt.Errorf("db: migration %d: %w", i+1, err)
		}
		if _, err := tx.ExecContext(ctx, migrations[i]); err != nil {
			tx.Rollback()
			return fmt.Errorf("db: migration %d: %w", i+1, err)
		}
		// PRAGMA cannot be parameterized; the value is a trusted integer.
		if _, err := tx.ExecContext(ctx, fmt.Sprintf("PRAGMA user_version = %d", i+1)); err != nil {
			tx.Rollback()
			return fmt.Errorf("db: migration %d: %w", i+1, err)
		}
		if err := tx.Commit(); err != nil {
			return fmt.Errorf("db: migration %d: %w", i+1, err)
		}
	}
	return nil
}

// Writer returns the single-connection write handle.
func (d *DB) Writer() *sql.DB { return d.w }

// Reader returns the read pool.
func (d *DB) Reader() *sql.DB { return d.r }

// Close closes both handles.
func (d *DB) Close() error {
	rerr := d.r.Close()
	werr := d.w.Close()
	if werr != nil {
		return werr
	}
	return rerr
}
