package db

import (
	"context"
	"database/sql"
	"errors"
	"time"
)

// Session is one live session row: a web login or a native device. The
// token itself is never stored, only its hash; PrevTokenHash keeps a
// just-rotated token valid for a short overlap window.
type Session struct {
	ID            string
	UserID        string
	Kind          string // "web" or "device"
	TokenHash     []byte
	PrevTokenHash []byte
	RotatedAt     time.Time
	CSRFToken     string
	DeviceName    string
	Client        string
	CreatedAt     time.Time
	LastSeenAt    time.Time
	ExpiresAt     time.Time
}

const sessionCols = "id, user_id, kind, token_hash, prev_token_hash, rotated_at_ns, csrf_token, device_name, client, created_at_ns, last_seen_ns, expires_at_ns"

func scanSession(row interface{ Scan(...any) error }) (*Session, error) {
	var s Session
	var rotated, created, seen, expires int64
	err := row.Scan(&s.ID, &s.UserID, &s.Kind, &s.TokenHash, &s.PrevTokenHash,
		&rotated, &s.CSRFToken, &s.DeviceName, &s.Client, &created, &seen, &expires)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	if rotated > 0 {
		s.RotatedAt = time.Unix(0, rotated).UTC()
	}
	s.CreatedAt = time.Unix(0, created).UTC()
	s.LastSeenAt = time.Unix(0, seen).UTC()
	s.ExpiresAt = time.Unix(0, expires).UTC()
	return &s, nil
}

// CreateSession inserts a new session row.
func (d *DB) CreateSession(ctx context.Context, s *Session) error {
	now := time.Now()
	_, err := d.w.ExecContext(ctx,
		`INSERT INTO sessions (`+sessionCols+`) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)`,
		s.ID, s.UserID, s.Kind, s.TokenHash, nil, 0, s.CSRFToken,
		s.DeviceName, s.Client, now.UnixNano(), now.UnixNano(), s.ExpiresAt.UnixNano())
	if err != nil {
		if isUniqueViolation(err) {
			return ErrConflict
		}
		return err
	}
	s.CreatedAt = now.UTC()
	s.LastSeenAt = now.UTC()
	return nil
}

// SessionByTokenHash resolves a presented token hash to its session,
// matching the current hash or (within the rotation overlap) the
// previous one.
func (d *DB) SessionByTokenHash(ctx context.Context, hash []byte) (*Session, error) {
	return scanSession(d.r.QueryRowContext(ctx,
		`SELECT `+sessionCols+` FROM sessions WHERE token_hash = ? OR prev_token_hash = ?`, hash, hash))
}

// SessionByID fetches one session row.
func (d *DB) SessionByID(ctx context.Context, id string) (*Session, error) {
	return scanSession(d.r.QueryRowContext(ctx,
		`SELECT `+sessionCols+` FROM sessions WHERE id = ?`, id))
}

// SessionsByUser lists the account's sessions, newest first.
func (d *DB) SessionsByUser(ctx context.Context, userID string) ([]*Session, error) {
	rows, err := d.r.QueryContext(ctx,
		`SELECT `+sessionCols+` FROM sessions WHERE user_id = ? ORDER BY created_at_ns DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []*Session
	for rows.Next() {
		s, err := scanSession(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, s)
	}
	return out, rows.Err()
}

// RotateSessionToken swaps in a new token hash, keeping the old one
// valid until the overlap deadline that TouchSession enforces.
func (d *DB) RotateSessionToken(ctx context.Context, id string, newHash []byte, expiresAt time.Time) error {
	res, err := d.w.ExecContext(ctx,
		`UPDATE sessions SET prev_token_hash = token_hash, token_hash = ?, rotated_at_ns = ?, expires_at_ns = ?
		 WHERE id = ?`,
		newHash, time.Now().UnixNano(), expiresAt.UnixNano(), id)
	if err != nil {
		return err
	}
	return requireRow(res)
}

// ClearPrevToken ends a rotation overlap window.
func (d *DB) ClearPrevToken(ctx context.Context, id string) error {
	_, err := d.w.ExecContext(ctx,
		`UPDATE sessions SET prev_token_hash = NULL WHERE id = ?`, id)
	return err
}

// TouchSession advances last-seen and the sliding expiry. Callers
// coalesce: touch only when last-seen is stale, never per request.
func (d *DB) TouchSession(ctx context.Context, id string, expiresAt time.Time) error {
	_, err := d.w.ExecContext(ctx,
		`UPDATE sessions SET last_seen_ns = ?, expires_at_ns = ? WHERE id = ?`,
		time.Now().UnixNano(), expiresAt.UnixNano(), id)
	return err
}

// DeleteSession revokes one session. Revocation is deletion: the next
// lookup misses and the device is signed out.
func (d *DB) DeleteSession(ctx context.Context, id string) error {
	res, err := d.w.ExecContext(ctx, `DELETE FROM sessions WHERE id = ?`, id)
	if err != nil {
		return err
	}
	return requireRow(res)
}

// DeleteUserSessions revokes all of the account's sessions except
// keepID (pass "" to revoke every one).
func (d *DB) DeleteUserSessions(ctx context.Context, userID, keepID string) error {
	_, err := d.w.ExecContext(ctx,
		`DELETE FROM sessions WHERE user_id = ? AND id != ?`, userID, keepID)
	return err
}

// SweepExpired removes expired sessions, spent OIDC state, and spent
// one-time codes. Called periodically by the janitor.
func (d *DB) SweepExpired(ctx context.Context) error {
	now := time.Now().UnixNano()
	if _, err := d.w.ExecContext(ctx, `DELETE FROM sessions WHERE expires_at_ns < ?`, now); err != nil {
		return err
	}
	if _, err := d.w.ExecContext(ctx, `DELETE FROM oauth_state WHERE expires_at_ns < ?`, now); err != nil {
		return err
	}
	_, err := d.w.ExecContext(ctx, `DELETE FROM oidc_codes WHERE expires_at_ns < ?`, now)
	return err
}
