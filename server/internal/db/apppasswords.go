package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"
)

// AppPassword is one per-client compatibility-API credential as stored.
// SecretEnc is the sealed secret (the Subsonic token scheme needs it
// recoverable); SecretHash is its SHA-256 for apiKey-style lookup.
type AppPassword struct {
	ID         string
	UserID     string
	Label      string
	SecretEnc  []byte
	SecretHash []byte
	CreatedAt  time.Time
	LastUsedAt time.Time
}

// InsertAppPassword stores a new app password, enforcing the per-user
// cap in the same statement (zero rows means the cap was hit).
func (d *DB) InsertAppPassword(ctx context.Context, ap *AppPassword, cap int) (bool, error) {
	res, err := d.w.ExecContext(ctx, `
		INSERT INTO app_passwords (id, user_id, label, secret_enc, secret_hash, created_at_ns)
		SELECT ?, ?, ?, ?, ?, ?
		WHERE (SELECT COUNT(*) FROM app_passwords WHERE user_id = ?) < ?`,
		ap.ID, ap.UserID, ap.Label, ap.SecretEnc, ap.SecretHash,
		time.Now().UnixNano(), ap.UserID, cap)
	if err != nil {
		return false, fmt.Errorf("db: inserting app password: %w", err)
	}
	n, err := res.RowsAffected()
	if err != nil {
		return false, fmt.Errorf("db: inserting app password: %w", err)
	}
	return n > 0, nil
}

// AppPasswordsByUser lists one user's app passwords, newest first.
func (d *DB) AppPasswordsByUser(ctx context.Context, userID string) ([]AppPassword, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT id, user_id, label, secret_enc, secret_hash, created_at_ns, last_used_ns
		FROM app_passwords WHERE user_id = ? ORDER BY created_at_ns DESC`,
		userID)
	if err != nil {
		return nil, fmt.Errorf("db: listing app passwords: %w", err)
	}
	defer rows.Close()
	var out []AppPassword
	for rows.Next() {
		ap, err := scanAppPassword(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, ap)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("db: listing app passwords: %w", err)
	}
	return out, nil
}

// AppPasswordBySecretHash resolves a presented secret (by its SHA-256)
// to its row, or nil when unknown. The apiKey path and the cache-miss
// token path both come through here.
func (d *DB) AppPasswordBySecretHash(ctx context.Context, hash []byte) (*AppPassword, error) {
	row := d.r.QueryRowContext(ctx, `
		SELECT id, user_id, label, secret_enc, secret_hash, created_at_ns, last_used_ns
		FROM app_passwords WHERE secret_hash = ?`, hash)
	ap, err := scanAppPassword(row)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &ap, nil
}

// DeleteAppPassword revokes one of a user's app passwords; false when
// no such row belongs to them.
func (d *DB) DeleteAppPassword(ctx context.Context, userID, id string) (bool, error) {
	res, err := d.w.ExecContext(ctx,
		`DELETE FROM app_passwords WHERE user_id = ? AND id = ?`, userID, id)
	if err != nil {
		return false, fmt.Errorf("db: deleting app password: %w", err)
	}
	n, err := res.RowsAffected()
	if err != nil {
		return false, fmt.Errorf("db: deleting app password: %w", err)
	}
	return n > 0, nil
}

// TouchAppPassword records a successful use, coarsely: callers keep the
// cadence to about a minute so polling clients do not churn the writer.
func (d *DB) TouchAppPassword(ctx context.Context, id string) error {
	_, err := d.w.ExecContext(ctx,
		`UPDATE app_passwords SET last_used_ns = ? WHERE id = ?`,
		time.Now().UnixNano(), id)
	if err != nil {
		return fmt.Errorf("db: touching app password: %w", err)
	}
	return nil
}

type scanner interface{ Scan(...any) error }

func scanAppPassword(row scanner) (AppPassword, error) {
	var ap AppPassword
	var created, lastUsed int64
	err := row.Scan(&ap.ID, &ap.UserID, &ap.Label, &ap.SecretEnc, &ap.SecretHash,
		&created, &lastUsed)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return AppPassword{}, err
		}
		return AppPassword{}, fmt.Errorf("db: scanning app password: %w", err)
	}
	ap.CreatedAt = time.Unix(0, created).UTC()
	if lastUsed > 0 {
		ap.LastUsedAt = time.Unix(0, lastUsed).UTC()
	}
	return ap, nil
}
