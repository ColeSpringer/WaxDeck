package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"
)

// bookmarkCap bounds one user's marks in one book. A listener marking a
// passage does it a handful of times a book; the cap is what keeps an
// unpaginated listing honest against a client stuck in a retry loop.
const bookmarkCap = 200

// Bookmark is one place a listener marked in a book. Positions are
// book-timeline milliseconds, spanning every part.
type Bookmark struct {
	ID          string
	UserID      string
	BookPID     string
	PositionMS  int64
	Note        string
	CreatedAtNS int64
}

// bookmarkColumns is what scanBookmark reads, in its order.
const bookmarkColumns = `id, user_id, book_pid, position_ms, note, created_at_ns`

func scanBookmark(row interface{ Scan(...any) error }) (Bookmark, error) {
	var b Bookmark
	err := row.Scan(&b.ID, &b.UserID, &b.BookPID, &b.PositionMS, &b.Note, &b.CreatedAtNS)
	return b, err
}

// BookmarksFor returns one user's bookmarks in one book, in timeline
// order.
func (d *DB) BookmarksFor(ctx context.Context, userID, bookPID string) ([]Bookmark, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT `+bookmarkColumns+`
		FROM book_bookmarks WHERE user_id = ? AND book_pid = ?
		ORDER BY position_ms, id`, userID, bookPID)
	if err != nil {
		return nil, fmt.Errorf("db: listing bookmarks: %w", err)
	}
	defer rows.Close()
	var out []Bookmark
	for rows.Next() {
		b, err := scanBookmark(rows)
		if err != nil {
			return nil, fmt.Errorf("db: scanning bookmark: %w", err)
		}
		out = append(out, b)
	}
	return out, rows.Err()
}

// ErrBookmarkFull means the book already holds bookmarkCap marks.
var ErrBookmarkFull = errors.New("db: bookmark cap reached")

// ErrBookmarkRemoved means the id named a mark that has since been removed.
var ErrBookmarkRemoved = errors.New("db: bookmark removed")

// CreateBookmark inserts a mark, checking its id and the cap in one
// transaction. A stored id answers its row (created false), or ErrConflict
// or ErrBookmarkRemoved; only a new mark is put to check, whose error is returned.
func (d *DB) CreateBookmark(ctx context.Context, b Bookmark, check func() error) (Bookmark, bool, error) {
	fail := func(err error) (Bookmark, bool, error) {
		return Bookmark{}, false, fmt.Errorf("db: creating bookmark: %w", err)
	}
	tx, err := d.w.BeginTx(ctx, nil)
	if err != nil {
		return fail(err)
	}
	defer tx.Rollback()
	stored, err := scanBookmark(tx.QueryRowContext(ctx,
		`SELECT `+bookmarkColumns+` FROM book_bookmarks WHERE id = ?`, b.ID))
	switch {
	case err == nil && (stored.UserID != b.UserID || stored.BookPID != b.BookPID):
		return Bookmark{}, false, ErrConflict
	case err == nil:
		return stored, false, nil
	case !errors.Is(err, sql.ErrNoRows):
		return fail(err)
	}
	var owner string
	err = tx.QueryRowContext(ctx,
		`SELECT user_id FROM book_bookmark_tombstones WHERE id = ?`, b.ID).Scan(&owner)
	switch {
	case err == nil && owner != b.UserID:
		return Bookmark{}, false, ErrConflict
	case err == nil:
		return Bookmark{}, false, ErrBookmarkRemoved
	case !errors.Is(err, sql.ErrNoRows):
		return fail(err)
	}
	if err := check(); err != nil {
		return Bookmark{}, false, err
	}
	var held int
	if err := tx.QueryRowContext(ctx,
		`SELECT COUNT(*) FROM book_bookmarks WHERE user_id = ? AND book_pid = ?`,
		b.UserID, b.BookPID).Scan(&held); err != nil {
		return fail(err)
	}
	if held >= bookmarkCap {
		return Bookmark{}, false, ErrBookmarkFull
	}
	if _, err := tx.ExecContext(ctx, `
		INSERT INTO book_bookmarks (`+bookmarkColumns+`) VALUES (?, ?, ?, ?, ?, ?)`,
		b.ID, b.UserID, b.BookPID, b.PositionMS, b.Note, b.CreatedAtNS); err != nil {
		return fail(err)
	}
	if err := tx.Commit(); err != nil {
		return fail(err)
	}
	return b, true, nil
}

// DeleteBookmark removes a user's mark from the book the route names,
// keeping its id so a replayed create cannot bring it back. One already
// gone is not an error; the bool says whether a row went.
func (d *DB) DeleteBookmark(ctx context.Context, userID, bookPID, id string) (bool, error) {
	fail := func(err error) (bool, error) {
		return false, fmt.Errorf("db: deleting bookmark: %w", err)
	}
	tx, err := d.w.BeginTx(ctx, nil)
	if err != nil {
		return fail(err)
	}
	defer tx.Rollback()
	res, err := tx.ExecContext(ctx,
		`DELETE FROM book_bookmarks WHERE user_id = ? AND book_pid = ? AND id = ?`,
		userID, bookPID, id)
	if err != nil {
		return fail(err)
	}
	n, err := res.RowsAffected()
	if err != nil {
		return fail(err)
	}
	if n == 0 {
		return false, nil
	}
	if _, err := tx.ExecContext(ctx, `
		INSERT INTO book_bookmark_tombstones (id, user_id, removed_at_ns) VALUES (?, ?, ?)
		ON CONFLICT (id) DO NOTHING`,
		id, userID, time.Now().UnixNano()); err != nil {
		return fail(err)
	}
	if err := tx.Commit(); err != nil {
		return fail(err)
	}
	return true, nil
}

// PruneBookmarkTombstones drops the tombstones of marks removed before
// the cutoff. Each refuses a replay of its mark's create; past a device's
// longest time offline, one guards nothing.
func (d *DB) PruneBookmarkTombstones(ctx context.Context, olderThanNS int64) (int64, error) {
	res, err := d.w.ExecContext(ctx, `
		DELETE FROM book_bookmark_tombstones
		WHERE removed_at_ns < ?`, olderThanNS)
	if err != nil {
		return 0, fmt.Errorf("db: pruning bookmark tombstones: %w", err)
	}
	return res.RowsAffected()
}
