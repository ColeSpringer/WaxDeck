package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
)

// Upload is one resumable upload session.
type Upload struct {
	ID            string
	UserID        string
	FileName      string
	SizeBytes     int64
	ReceivedBytes int64
	MediaType     string
	LibraryPID    string
	// BatchID and BatchPath join the session to an upload batch:
	// BatchPath is the file's directory relative to the picked folder,
	// the auto grouping's clustering hint.
	BatchID       string
	BatchPath     string
	SHA256        string
	State         string
	StagingPath   string
	ReviewEntryID string
	// TrackDoc holds a batch member's parsed review track document
	// (JSON) between completion and batch finalize, so finalization
	// never re-parses or re-fingerprints.
	TrackDoc      string
	DuplicatePID  string
	DuplicateKind string
	// ItemPID links an imported session to the catalog item it became,
	// which is what grants the uploader item-scoped editing rights.
	ItemPID     string
	CreatedAtNS int64
	ExpiresAtNS int64
}

const uploadCols = `id, user_id, file_name, size_bytes, received_bytes, media_type,
	library_pid, batch_id, batch_path, sha256, state, staging_path, review_entry_id,
	track_doc, duplicate_pid, duplicate_kind, item_pid, created_at_ns, expires_at_ns`

func scanUpload(row interface{ Scan(...any) error }) (Upload, error) {
	var u Upload
	err := row.Scan(&u.ID, &u.UserID, &u.FileName, &u.SizeBytes, &u.ReceivedBytes,
		&u.MediaType, &u.LibraryPID, &u.BatchID, &u.BatchPath, &u.SHA256, &u.State,
		&u.StagingPath, &u.ReviewEntryID, &u.TrackDoc, &u.DuplicatePID,
		&u.DuplicateKind, &u.ItemPID, &u.CreatedAtNS, &u.ExpiresAtNS)
	return u, err
}

// InsertUpload stores a new session.
func (d *DB) InsertUpload(ctx context.Context, u Upload) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO uploads (`+uploadCols+`)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		u.ID, u.UserID, u.FileName, u.SizeBytes, u.ReceivedBytes, u.MediaType,
		u.LibraryPID, u.BatchID, u.BatchPath, u.SHA256, u.State, u.StagingPath,
		u.ReviewEntryID, u.TrackDoc, u.DuplicatePID, u.DuplicateKind, u.ItemPID,
		u.CreatedAtNS, u.ExpiresAtNS)
	if err != nil {
		return fmt.Errorf("db: inserting upload: %w", err)
	}
	return nil
}

// UploadByID fetches one session.
func (d *DB) UploadByID(ctx context.Context, id string) (Upload, error) {
	u, err := scanUpload(d.r.QueryRowContext(ctx,
		`SELECT `+uploadCols+` FROM uploads WHERE id = ?`, id))
	if errors.Is(err, sql.ErrNoRows) {
		return Upload{}, ErrNotFound
	}
	if err != nil {
		return Upload{}, fmt.Errorf("db: reading upload: %w", err)
	}
	return u, nil
}

// ContentDuplicateByHash returns the item pid an earlier upload of the same
// byte-identical content resolved to: the most recent session whose sha256
// matches, that reached state, and that itself carried a duplicate item. It
// answers the upload pre-check directly by hash, so a duplicate uploaded any
// time before is caught rather than only within a capped recent window. ok is
// false when no such session exists.
func (d *DB) ContentDuplicateByHash(ctx context.Context, sha, state string) (string, bool, error) {
	var pid string
	err := d.r.QueryRowContext(ctx, `
		SELECT duplicate_pid FROM uploads
		WHERE sha256 = ? AND state = ? AND duplicate_pid != ''
		ORDER BY created_at_ns DESC LIMIT 1`, sha, state).Scan(&pid)
	if errors.Is(err, sql.ErrNoRows) {
		return "", false, nil
	}
	if err != nil {
		return "", false, fmt.Errorf("db: content duplicate lookup: %w", err)
	}
	return pid, true, nil
}

// UpdateUpload rewrites a stored session (same id).
func (d *DB) UpdateUpload(ctx context.Context, u Upload) error {
	res, err := d.w.ExecContext(ctx, `
		UPDATE uploads SET received_bytes = ?, state = ?, staging_path = ?,
			review_entry_id = ?, duplicate_pid = ?, duplicate_kind = ?, item_pid = ?,
			expires_at_ns = ?
		WHERE id = ?`,
		u.ReceivedBytes, u.State, u.StagingPath, u.ReviewEntryID, u.DuplicatePID,
		u.DuplicateKind, u.ItemPID, u.ExpiresAtNS, u.ID)
	if err != nil {
		return fmt.Errorf("db: updating upload: %w", err)
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrNotFound
	}
	return nil
}

// DeleteUpload removes a session row.
func (d *DB) DeleteUpload(ctx context.Context, id string) error {
	res, err := d.w.ExecContext(ctx, `DELETE FROM uploads WHERE id = ?`, id)
	if err != nil {
		return fmt.Errorf("db: deleting upload: %w", err)
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrNotFound
	}
	return nil
}

// ListUploads pages sessions newest first; userID empty lists everyone
// (administrators). The cursor is the previous page's last
// (created_at_ns, id).
func (d *DB) ListUploads(ctx context.Context, userID string, beforeNS int64, beforeID string, limit int) ([]Upload, error) {
	q := `SELECT ` + uploadCols + ` FROM uploads WHERE 1=1`
	args := []any{}
	if userID != "" {
		q += ` AND user_id = ?`
		args = append(args, userID)
	}
	if beforeID != "" {
		q += ` AND (created_at_ns < ? OR (created_at_ns = ? AND id < ?))`
		args = append(args, beforeNS, beforeNS, beforeID)
	}
	q += ` ORDER BY created_at_ns DESC, id DESC LIMIT ?`
	args = append(args, limit)
	rows, err := d.r.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, fmt.Errorf("db: listing uploads: %w", err)
	}
	defer rows.Close()
	var out []Upload
	for rows.Next() {
		u, err := scanUpload(rows)
		if err != nil {
			return nil, fmt.Errorf("db: scanning upload: %w", err)
		}
		out = append(out, u)
	}
	return out, rows.Err()
}

// ListUploadsByReviewEntry returns every session linked to one review
// entry, oldest first. The settle and discard paths walk an entry's own
// sessions through this rather than a capped newest-first page of the
// uploader's whole history, which would miss rows past the cap.
func (d *DB) ListUploadsByReviewEntry(ctx context.Context, entryID string) ([]Upload, error) {
	if entryID == "" {
		return nil, nil // '' is the column default, not a real entry
	}
	rows, err := d.r.QueryContext(ctx, `SELECT `+uploadCols+` FROM uploads
		WHERE review_entry_id = ? ORDER BY created_at_ns, id`, entryID)
	if err != nil {
		return nil, fmt.Errorf("db: listing entry uploads: %w", err)
	}
	defer rows.Close()
	var out []Upload
	for rows.Next() {
		u, err := scanUpload(rows)
		if err != nil {
			return nil, fmt.Errorf("db: scanning upload: %w", err)
		}
		out = append(out, u)
	}
	return out, rows.Err()
}

// UploadOwnsItem reports whether one of the user's sessions produced
// the catalog item, which grants item-scoped editing rights.
func (d *DB) UploadOwnsItem(ctx context.Context, userID, itemPID string) (bool, error) {
	var one int
	err := d.r.QueryRowContext(ctx, `
		SELECT 1 FROM uploads WHERE item_pid = ? AND user_id = ? LIMIT 1`,
		itemPID, userID).Scan(&one)
	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("db: checking upload ownership: %w", err)
	}
	return true, nil
}

// UploadedItemPIDs reports which of the given catalog items an upload
// session produced. The discovery sweeper asks: a file that arrived
// through the upload pipeline was already reviewed on its way in, and
// the scan that indexes it afterwards must not open a second entry for
// the same audio.
func (d *DB) UploadedItemPIDs(ctx context.Context, itemPIDs []string) (map[string]bool, error) {
	out := make(map[string]bool, len(itemPIDs))
	if len(itemPIDs) == 0 {
		return out, nil
	}
	args := make([]any, 0, len(itemPIDs))
	placeholders := make([]byte, 0, len(itemPIDs)*2)
	for i, pid := range itemPIDs {
		if i > 0 {
			placeholders = append(placeholders, ',')
		}
		placeholders = append(placeholders, '?')
		args = append(args, pid)
	}
	rows, err := d.r.QueryContext(ctx,
		`SELECT DISTINCT item_pid FROM uploads WHERE item_pid IN (`+string(placeholders)+`)`, args...)
	if err != nil {
		return nil, fmt.Errorf("db: listing uploaded items: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var pid string
		if err := rows.Scan(&pid); err != nil {
			return nil, fmt.Errorf("db: listing uploaded items: %w", err)
		}
		out[pid] = true
	}
	return out, rows.Err()
}

// UploadBytesInUse sums the declared sizes of a user's sessions still
// sitting in staging, which is what quota checks charge.
//
// Neither discarded nor imported counts. The quota is a ceiling on
// in-flight footprint - what may wait in staging for a decision - not a
// cap on what an account has contributed, so a session that reached the
// library releases the room it held. Charging imported sessions instead
// made a filled quota permanent: nothing releases them, and deleting the
// item they became does not touch this table.
func (d *DB) UploadBytesInUse(ctx context.Context, userID string) (int64, error) {
	var n sql.NullInt64
	err := d.r.QueryRowContext(ctx, `
		SELECT SUM(size_bytes) FROM uploads
		WHERE user_id = ? AND state NOT IN ('discarded', 'imported')`, userID).Scan(&n)
	if err != nil {
		return 0, fmt.Errorf("db: summing upload use: %w", err)
	}
	return n.Int64, nil
}

// ExpiredUploads returns sessions past their expiry that still hold
// staged bytes, for the janitor to reclaim. Members of a still-open
// batch are exempt: under the default retention this never bites
// (member retention far exceeds the batch window), but the retention
// is operator-configurable and a short one must not let the session
// janitor reap staged members before their batch finalizes. Once the
// batch closes, members return to normal retention.
func (d *DB) ExpiredUploads(ctx context.Context, nowNS int64, limit int) ([]Upload, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT `+uploadCols+` FROM uploads
		WHERE expires_at_ns > 0 AND expires_at_ns < ? AND state IN ('receiving', 'staged')
			AND (batch_id = '' OR NOT EXISTS (
				SELECT 1 FROM upload_batches b WHERE b.id = batch_id AND b.state = 'open'))
		ORDER BY expires_at_ns LIMIT ?`, nowNS, limit)
	if err != nil {
		return nil, fmt.Errorf("db: listing expired uploads: %w", err)
	}
	defer rows.Close()
	var out []Upload
	for rows.Next() {
		u, err := scanUpload(rows)
		if err != nil {
			return nil, fmt.Errorf("db: scanning expired upload: %w", err)
		}
		out = append(out, u)
	}
	return out, rows.Err()
}
