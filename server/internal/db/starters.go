package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
)

// StarterPlaylist records one account's copy of one starter list: the
// playlist it was seeded as, and whether the account has since thrown
// it away. A missing row means the account has never been offered this
// starter.
type StarterPlaylist struct {
	PlaylistPID string
	Dismissed   bool
}

// StarterPlaylist reads one account's row for a starter kind; ok is
// false when the account has never been seeded with it.
func (d *DB) StarterPlaylist(ctx context.Context, userID, kind string) (StarterPlaylist, bool, error) {
	var out StarterPlaylist
	err := d.r.QueryRowContext(ctx, `
		SELECT playlist_pid, dismissed FROM starter_playlists
		WHERE user_id = ? AND kind = ?`,
		userID, kind).Scan(&out.PlaylistPID, &out.Dismissed)
	if errors.Is(err, sql.ErrNoRows) {
		return StarterPlaylist{}, false, nil
	}
	if err != nil {
		return StarterPlaylist{}, false, fmt.Errorf("db: reading starter playlist: %w", err)
	}
	return out, true, nil
}

// PutStarterPlaylist records the playlist an account was seeded with,
// clearing any dismissal: a re-seed happens only after the previous
// playlist went missing from the catalog, which is a rebuild rather
// than a refusal.
func (d *DB) PutStarterPlaylist(ctx context.Context, userID, kind, playlistPID string, createdAtNS int64) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO starter_playlists (user_id, kind, playlist_pid, dismissed, created_at_ns)
		VALUES (?, ?, ?, 0, ?)
		ON CONFLICT (user_id, kind) DO UPDATE SET
			playlist_pid = excluded.playlist_pid,
			dismissed = 0,
			created_at_ns = excluded.created_at_ns`,
		userID, kind, playlistPID, createdAtNS)
	if err != nil {
		return fmt.Errorf("db: writing starter playlist: %w", err)
	}
	return nil
}

// DismissStarterPlaylist marks the account's starter as thrown away, so
// the boot reconcile leaves it deleted. Deleting a playlist that is not
// a starter matches no row and is a no-op.
func (d *DB) DismissStarterPlaylist(ctx context.Context, userID, playlistPID string) error {
	_, err := d.w.ExecContext(ctx, `
		UPDATE starter_playlists SET dismissed = 1
		WHERE user_id = ? AND playlist_pid = ?`,
		userID, playlistPID)
	if err != nil {
		return fmt.Errorf("db: dismissing starter playlist: %w", err)
	}
	return nil
}
