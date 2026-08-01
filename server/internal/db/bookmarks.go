package db

import (
	"context"
	"fmt"
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

// BookmarksFor returns one user's bookmarks in one book, in timeline
// order.
func (d *DB) BookmarksFor(ctx context.Context, userID, bookPID string) ([]Bookmark, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT id, user_id, book_pid, position_ms, note, created_at_ns
		FROM book_bookmarks WHERE user_id = ? AND book_pid = ?
		ORDER BY position_ms, id`, userID, bookPID)
	if err != nil {
		return nil, fmt.Errorf("db: listing bookmarks: %w", err)
	}
	defer rows.Close()
	var out []Bookmark
	for rows.Next() {
		var b Bookmark
		if err := rows.Scan(&b.ID, &b.UserID, &b.BookPID, &b.PositionMS, &b.Note, &b.CreatedAtNS); err != nil {
			return nil, fmt.Errorf("db: scanning bookmark: %w", err)
		}
		out = append(out, b)
	}
	return out, rows.Err()
}

// CreateBookmark inserts a mark, enforcing the per-book cap inside the
// statement so concurrent creates cannot slip past it. ErrConflict means
// the book is full.
func (d *DB) CreateBookmark(ctx context.Context, b Bookmark) error {
	res, err := d.w.ExecContext(ctx, `
		INSERT INTO book_bookmarks (id, user_id, book_pid, position_ms, note, created_at_ns)
		SELECT ?, ?, ?, ?, ?, ?
		WHERE (SELECT COUNT(*) FROM book_bookmarks WHERE user_id = ? AND book_pid = ?) < ?`,
		b.ID, b.UserID, b.BookPID, b.PositionMS, b.Note, b.CreatedAtNS,
		b.UserID, b.BookPID, bookmarkCap)
	if err != nil {
		return fmt.Errorf("db: creating bookmark: %w", err)
	}
	n, err := res.RowsAffected()
	if err != nil {
		return fmt.Errorf("db: creating bookmark: %w", err)
	}
	if n == 0 {
		return ErrConflict
	}
	return nil
}

// DeleteBookmark removes one of a user's marks from one of their books.
//
// Scoped by all three, and the book is not decoration: the route names
// it, so a mark that belongs to another book is not the one this call
// asked to remove. Without it a delete under the wrong book answered
// 204 and took the mark anyway, leaving the client that asked with a
// cached list it never held and the book that owned it still showing
// it.
//
// Deleting one that is already gone is not an error: the caller asked
// for it to be absent and it is.
func (d *DB) DeleteBookmark(ctx context.Context, userID, bookPID, id string) error {
	if _, err := d.w.ExecContext(ctx,
		`DELETE FROM book_bookmarks WHERE user_id = ? AND book_pid = ? AND id = ?`,
		userID, bookPID, id); err != nil {
		return fmt.Errorf("db: deleting bookmark: %w", err)
	}
	return nil
}
