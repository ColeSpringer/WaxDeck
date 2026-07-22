package db

import (
	"context"
	"database/sql"
	"fmt"
	"time"
)

// Share is one public share link's row. The capability token is not
// stored: it derives from ID with the server key, so revocation is row
// state and the database holds no share secrets.
type Share struct {
	ID            string
	UserID        string
	TargetPID     string
	TargetKind    string
	AllowDownload bool
	PositionMs    int64
	Plays         int
	CreatedAt     time.Time
	ExpiresAt     time.Time // zero = never expires
	Revoked       bool
}

// InsertShare records a new share link.
func (d *DB) InsertShare(ctx context.Context, s Share) error {
	var expires int64
	if !s.ExpiresAt.IsZero() {
		expires = s.ExpiresAt.UnixNano()
	}
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO shares
			(id, user_id, target_pid, target_kind, allow_download,
			 position_ms, created_at_ns, expires_at_ns)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
		s.ID, s.UserID, s.TargetPID, s.TargetKind, boolInt(s.AllowDownload),
		s.PositionMs, s.CreatedAt.UnixNano(), expires)
	if err != nil {
		return fmt.Errorf("db: inserting share: %w", err)
	}
	return nil
}

// ShareByID loads one share row, revoked ones included (the caller
// decides what a revoked share means for its surface).
func (d *DB) ShareByID(ctx context.Context, id string) (*Share, error) {
	row := d.r.QueryRowContext(ctx, `
		SELECT id, user_id, target_pid, target_kind, allow_download,
		       position_ms, plays, created_at_ns, expires_at_ns, revoked
		FROM shares WHERE id = ?`, id)
	return scanShare(row)
}

// Shares pages share links newest first: one user's, or everyone's when
// userID is empty (the admin listing). Revoked shares are omitted. The
// cursor is the previous page's last (created_at_ns, id) pair.
func (d *DB) Shares(ctx context.Context, userID string, beforeNS int64, beforeID string, limit int) ([]Share, error) {
	if beforeNS == 0 {
		beforeNS = time.Now().Add(time.Hour).UnixNano()
		beforeID = ""
	}
	q := `
		SELECT id, user_id, target_pid, target_kind, allow_download,
		       position_ms, plays, created_at_ns, expires_at_ns, revoked
		FROM shares
		WHERE revoked = 0 AND (created_at_ns < ? OR (created_at_ns = ? AND id < ?))`
	args := []any{beforeNS, beforeNS, beforeID}
	if userID != "" {
		q += ` AND user_id = ?`
		args = append(args, userID)
	}
	q += ` ORDER BY created_at_ns DESC, id DESC LIMIT ?`
	args = append(args, limit)
	rows, err := d.r.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, fmt.Errorf("db: listing shares: %w", err)
	}
	defer rows.Close()
	var out []Share
	for rows.Next() {
		s, err := scanShare(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *s)
	}
	return out, rows.Err()
}

// RevokeShare marks a share revoked. Not-found when the id is unknown
// or already revoked.
func (d *DB) RevokeShare(ctx context.Context, id string) error {
	res, err := d.w.ExecContext(ctx,
		`UPDATE shares SET revoked = 1 WHERE id = ? AND revoked = 0`, id)
	if err != nil {
		return fmt.Errorf("db: revoking share: %w", err)
	}
	n, err := res.RowsAffected()
	if err != nil {
		return fmt.Errorf("db: revoking share: %w", err)
	}
	if n == 0 {
		return ErrNotFound
	}
	return nil
}

// CountSharePlay bumps a share's anonymous play counter.
func (d *DB) CountSharePlay(ctx context.Context, id string) error {
	_, err := d.w.ExecContext(ctx,
		`UPDATE shares SET plays = plays + 1 WHERE id = ?`, id)
	if err != nil {
		return fmt.Errorf("db: counting share play: %w", err)
	}
	return nil
}

type rowScanner interface{ Scan(dest ...any) error }

func scanShare(row rowScanner) (*Share, error) {
	var s Share
	var allowDownload, revoked int
	var createdNS, expiresNS int64
	err := row.Scan(&s.ID, &s.UserID, &s.TargetPID, &s.TargetKind,
		&allowDownload, &s.PositionMs, &s.Plays, &createdNS, &expiresNS, &revoked)
	if err == sql.ErrNoRows {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("db: reading share: %w", err)
	}
	s.AllowDownload = allowDownload != 0
	s.Revoked = revoked != 0
	s.CreatedAt = time.Unix(0, createdNS).UTC()
	if expiresNS != 0 {
		s.ExpiresAt = time.Unix(0, expiresNS).UTC()
	}
	return &s, nil
}
