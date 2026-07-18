package db

import (
	"context"
	"database/sql"
	"errors"
	"time"
)

// PrefsJSON returns the account's stored preference document, or "" when
// none was ever saved.
func (d *DB) PrefsJSON(ctx context.Context, userID string) (string, error) {
	var doc string
	err := d.r.QueryRowContext(ctx, `SELECT json FROM prefs WHERE user_id = ?`, userID).Scan(&doc)
	if errors.Is(err, sql.ErrNoRows) {
		return "", nil
	}
	return doc, err
}

// PutPrefsJSON replaces the account's preference document.
func (d *DB) PutPrefsJSON(ctx context.Context, userID, doc string) error {
	_, err := d.w.ExecContext(ctx,
		`INSERT INTO prefs (user_id, json, updated_at_ns) VALUES (?,?,?)
		 ON CONFLICT (user_id) DO UPDATE SET json = excluded.json, updated_at_ns = excluded.updated_at_ns`,
		userID, doc, time.Now().UnixNano())
	return err
}
