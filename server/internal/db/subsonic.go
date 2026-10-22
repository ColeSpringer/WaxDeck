package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
)

// The Subsonic surface's own state: the folder id each music library
// keeps, and the protocol's bookmarks.

// MusicFolderIDs answers the folder id of each library, assigning one the
// first time a library is asked for. Ids are never reused or moved, so a
// client that stored one keeps reading the library it named.
func (d *DB) MusicFolderIDs(ctx context.Context, libraryPIDs []string) (map[string]int64, error) {
	out := make(map[string]int64, len(libraryPIDs))
	if len(libraryPIDs) == 0 {
		return out, nil
	}
	read := func(q interface {
		QueryContext(context.Context, string, ...any) (*sql.Rows, error)
	}) error {
		args := make([]any, len(libraryPIDs))
		for i, pid := range libraryPIDs {
			args[i] = pid
		}
		rows, err := q.QueryContext(ctx, `SELECT id, library_pid FROM subsonic_music_folders
			WHERE library_pid IN (?`+strings.Repeat(",?", len(args)-1)+`)`, args...)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var id int64
			var pid string
			if err := rows.Scan(&id, &pid); err != nil {
				return err
			}
			out[pid] = id
		}
		return rows.Err()
	}
	// Clients list folders on every connect, so the common case is a read.
	if err := read(d.r); err != nil {
		return nil, fmt.Errorf("db: reading music folders: %w", err)
	}
	if len(out) == len(libraryPIDs) {
		return out, nil
	}
	tx, err := d.w.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("db: assigning music folders: %w", err)
	}
	defer tx.Rollback()
	for _, pid := range libraryPIDs {
		if _, held := out[pid]; held {
			continue
		}
		if _, err := tx.ExecContext(ctx, `INSERT INTO subsonic_music_folders (library_pid) VALUES (?)
			ON CONFLICT (library_pid) DO NOTHING`, pid); err != nil {
			return nil, fmt.Errorf("db: assigning music folders: %w", err)
		}
	}
	if err := read(tx); err != nil {
		return nil, fmt.Errorf("db: assigning music folders: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("db: assigning music folders: %w", err)
	}
	return out, nil
}

// MusicFolderLibrary answers the library a folder id names; ok is false
// for an id never assigned.
func (d *DB) MusicFolderLibrary(ctx context.Context, id int64) (string, bool, error) {
	var pid string
	err := d.r.QueryRowContext(ctx, `SELECT library_pid FROM subsonic_music_folders WHERE id = ?`, id).Scan(&pid)
	if errors.Is(err, sql.ErrNoRows) {
		return "", false, nil
	}
	if err != nil {
		return "", false, fmt.Errorf("db: reading music folder: %w", err)
	}
	return pid, true, nil
}

// SubsonicBookmark is one protocol bookmark: a position in an item and
// the client's comment on it.
type SubsonicBookmark struct {
	UserID      string
	ItemPID     string
	PositionMS  int64
	Comment     string
	CreatedAtNS int64
	UpdatedAtNS int64
}

// SubsonicBookmarkCap bounds one account's bookmarks. The protocol's
// listing is unpaginated, and clients bookmark the tracks they stop part
// way through, which is a short list for a listener and an endless one
// for a client stuck in a loop.
const SubsonicBookmarkCap = 1000

// ErrSubsonicBookmarksFull means the account already holds
// SubsonicBookmarkCap bookmarks and the write would add another.
var ErrSubsonicBookmarksFull = errors.New("db: subsonic bookmark cap reached")

// SubsonicBookmarks lists one account's bookmarks, most recently changed
// first.
func (d *DB) SubsonicBookmarks(ctx context.Context, userID string) ([]SubsonicBookmark, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT user_id, item_pid, position_ms, comment, created_at_ns, updated_at_ns
		FROM subsonic_bookmarks WHERE user_id = ?
		ORDER BY updated_at_ns DESC, item_pid`, userID)
	if err != nil {
		return nil, fmt.Errorf("db: listing subsonic bookmarks: %w", err)
	}
	defer rows.Close()
	var out []SubsonicBookmark
	for rows.Next() {
		var b SubsonicBookmark
		if err := rows.Scan(&b.UserID, &b.ItemPID, &b.PositionMS, &b.Comment, &b.CreatedAtNS, &b.UpdatedAtNS); err != nil {
			return nil, fmt.Errorf("db: scanning subsonic bookmark: %w", err)
		}
		out = append(out, b)
	}
	return out, rows.Err()
}

// PutSubsonicBookmark creates or replaces the account's bookmark on the
// item, keeping a replaced row's creation time. A new row is refused with
// ErrSubsonicBookmarksFull once the account holds SubsonicBookmarkCap
// rows beside the uncounted ones.
func (d *DB) PutSubsonicBookmark(ctx context.Context, b SubsonicBookmark, uncounted ...string) error {
	fail := func(err error) error {
		return fmt.Errorf("db: saving subsonic bookmark: %w", err)
	}
	tx, err := d.w.BeginTx(ctx, nil)
	if err != nil {
		return fail(err)
	}
	defer tx.Rollback()
	args := []any{b.ItemPID, b.UserID}
	notIn := ""
	if len(uncounted) > 0 {
		notIn = ` AND item_pid NOT IN (?` + strings.Repeat(",?", len(uncounted)-1) + `)`
		for _, pid := range uncounted {
			args = append(args, pid)
		}
	}
	var held, existing int
	if err := tx.QueryRowContext(ctx, `
		SELECT COUNT(*), COALESCE(SUM(item_pid = ?), 0) FROM subsonic_bookmarks WHERE user_id = ?`+notIn,
		args...).Scan(&held, &existing); err != nil {
		return fail(err)
	}
	if existing == 0 && held >= SubsonicBookmarkCap {
		return ErrSubsonicBookmarksFull
	}
	if _, err := tx.ExecContext(ctx, `
		INSERT INTO subsonic_bookmarks (user_id, item_pid, position_ms, comment, created_at_ns, updated_at_ns)
		VALUES (?, ?, ?, ?, ?, ?)
		ON CONFLICT (user_id, item_pid) DO UPDATE SET
			position_ms = excluded.position_ms, comment = excluded.comment, updated_at_ns = excluded.updated_at_ns`,
		b.UserID, b.ItemPID, b.PositionMS, b.Comment, b.CreatedAtNS, b.UpdatedAtNS); err != nil {
		return fail(err)
	}
	if err := tx.Commit(); err != nil {
		return fail(err)
	}
	return nil
}

// DeleteSubsonicBookmarks removes the account's bookmarks on the items;
// ones never held are not an error.
func (d *DB) DeleteSubsonicBookmarks(ctx context.Context, userID string, itemPIDs ...string) error {
	if len(itemPIDs) == 0 {
		return nil
	}
	args := make([]any, 0, len(itemPIDs)+1)
	args = append(args, userID)
	for _, pid := range itemPIDs {
		args = append(args, pid)
	}
	if _, err := d.w.ExecContext(ctx, `DELETE FROM subsonic_bookmarks WHERE user_id = ? AND item_pid IN (?`+
		strings.Repeat(",?", len(itemPIDs)-1)+`)`, args...); err != nil {
		return fmt.Errorf("db: deleting subsonic bookmarks: %w", err)
	}
	return nil
}
