package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
)

// UploadBatch groups several upload sessions into review units by a
// declared grouping intent. ReviewEntryIDs is a JSON array of the
// review entry ids finalization opened, read and written whole.
type UploadBatch struct {
	ID             string
	UserID         string
	Grouping       string
	MediaType      string
	LibraryPID     string
	State          string
	ReviewEntryIDs string
	CreatedAtNS    int64
	ExpiresAtNS    int64
}

const uploadBatchCols = `id, user_id, grouping, media_type, library_pid, state,
	review_entry_ids, created_at_ns, expires_at_ns`

func scanUploadBatch(row interface{ Scan(...any) error }) (UploadBatch, error) {
	var b UploadBatch
	err := row.Scan(&b.ID, &b.UserID, &b.Grouping, &b.MediaType, &b.LibraryPID,
		&b.State, &b.ReviewEntryIDs, &b.CreatedAtNS, &b.ExpiresAtNS)
	return b, err
}

// InsertUploadBatch stores a new batch.
func (d *DB) InsertUploadBatch(ctx context.Context, b UploadBatch) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO upload_batches (`+uploadBatchCols+`)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		b.ID, b.UserID, b.Grouping, b.MediaType, b.LibraryPID, b.State,
		b.ReviewEntryIDs, b.CreatedAtNS, b.ExpiresAtNS)
	if err != nil {
		return fmt.Errorf("db: inserting upload batch: %w", err)
	}
	return nil
}

// UploadBatchByID fetches one batch.
func (d *DB) UploadBatchByID(ctx context.Context, id string) (UploadBatch, error) {
	b, err := scanUploadBatch(d.r.QueryRowContext(ctx,
		`SELECT `+uploadBatchCols+` FROM upload_batches WHERE id = ?`, id))
	if errors.Is(err, sql.ErrNoRows) {
		return UploadBatch{}, ErrNotFound
	}
	if err != nil {
		return UploadBatch{}, fmt.Errorf("db: reading upload batch: %w", err)
	}
	return b, nil
}

// StageBatchMember persists a completed member's staged state and its
// parsed track document, but only while its batch is still open; the
// batch check rides inside the statement so it serializes against
// FinalizeUploadBatch on the single write connection. staged=false
// means the batch closed mid-completion and nothing was written (the
// caller falls through to the per-file entry path).
func (d *DB) StageBatchMember(ctx context.Context, u Upload, trackDoc string) (bool, error) {
	res, err := d.w.ExecContext(ctx, `
		UPDATE uploads SET received_bytes = ?, state = ?, staging_path = ?,
			track_doc = ?, duplicate_pid = ?, duplicate_kind = ?
		WHERE id = ? AND (SELECT state FROM upload_batches WHERE id = ?) = 'open'`,
		u.ReceivedBytes, u.State, u.StagingPath, trackDoc, u.DuplicatePID,
		u.DuplicateKind, u.ID, u.BatchID)
	if err != nil {
		return false, fmt.Errorf("db: staging batch member: %w", err)
	}
	n, err := res.RowsAffected()
	if err != nil {
		return false, fmt.Errorf("db: staging batch member: %w", err)
	}
	return n == 1, nil
}

// FinalizeUploadBatch flips an open batch to state (finalized or
// expired) and gathers its staged members still awaiting a review
// entry, in one transaction on the write connection: StageBatchMember
// serializes against this, so every member is either gathered here
// exactly once or falls through to its own per-file entry exactly
// once. flipped=false reports the batch was already closed; members
// are gathered regardless so a finalize interrupted between the flip
// and entry opening is repaired by the retry.
func (d *DB) FinalizeUploadBatch(ctx context.Context, id, state string) (UploadBatch, []Upload, bool, error) {
	tx, err := d.w.BeginTx(ctx, nil)
	if err != nil {
		return UploadBatch{}, nil, false, fmt.Errorf("db: finalizing upload batch: %w", err)
	}
	defer tx.Rollback()
	b, err := scanUploadBatch(tx.QueryRowContext(ctx,
		`SELECT `+uploadBatchCols+` FROM upload_batches WHERE id = ?`, id))
	if errors.Is(err, sql.ErrNoRows) {
		return UploadBatch{}, nil, false, ErrNotFound
	}
	if err != nil {
		return UploadBatch{}, nil, false, fmt.Errorf("db: reading upload batch: %w", err)
	}
	flipped := false
	if b.State == "open" {
		if _, err := tx.ExecContext(ctx,
			`UPDATE upload_batches SET state = ? WHERE id = ?`, state, id); err != nil {
			return UploadBatch{}, nil, false, fmt.Errorf("db: closing upload batch: %w", err)
		}
		b.State = state
		flipped = true
	}
	rows, err := tx.QueryContext(ctx, `
		SELECT `+uploadCols+` FROM uploads
		WHERE batch_id = ? AND state = 'staged' AND review_entry_id = ''
		ORDER BY created_at_ns, id`, id)
	if err != nil {
		return UploadBatch{}, nil, false, fmt.Errorf("db: gathering batch members: %w", err)
	}
	defer rows.Close()
	var members []Upload
	for rows.Next() {
		u, err := scanUpload(rows)
		if err != nil {
			return UploadBatch{}, nil, false, fmt.Errorf("db: scanning batch member: %w", err)
		}
		members = append(members, u)
	}
	if err := rows.Err(); err != nil {
		return UploadBatch{}, nil, false, fmt.Errorf("db: gathering batch members: %w", err)
	}
	rows.Close()
	if err := tx.Commit(); err != nil {
		return UploadBatch{}, nil, false, fmt.Errorf("db: finalizing upload batch: %w", err)
	}
	return b, members, flipped, nil
}

// SetUploadBatchEntries records the review entries finalization
// opened.
func (d *DB) SetUploadBatchEntries(ctx context.Context, id, entryIDsJSON string) error {
	_, err := d.w.ExecContext(ctx,
		`UPDATE upload_batches SET review_entry_ids = ? WHERE id = ?`, entryIDsJSON, id)
	if err != nil {
		return fmt.Errorf("db: recording batch entries: %w", err)
	}
	return nil
}

// ExpiredUploadBatches returns batches the janitor owes work: open
// ones past their window, plus already-expired ones still holding a
// staged member with no review entry — the state an entry opening
// interrupted by a crash or a database failure leaves behind, which
// nothing else revisits (the client finalize answers conflict on an
// expired batch before opening entries). Fully processed batches
// drop out of both arms, so a persistent failure retries once per
// janitor tick, never hotter.
func (d *DB) ExpiredUploadBatches(ctx context.Context, nowNS int64, limit int) ([]UploadBatch, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT `+uploadBatchCols+` FROM upload_batches
		WHERE (state = 'open' AND expires_at_ns < ?)
			OR (state = 'expired' AND EXISTS (
				SELECT 1 FROM uploads u
				WHERE u.batch_id = upload_batches.id
					AND u.state = 'staged' AND u.review_entry_id = ''))
		ORDER BY expires_at_ns LIMIT ?`, nowNS, limit)
	if err != nil {
		return nil, fmt.Errorf("db: listing expired upload batches: %w", err)
	}
	defer rows.Close()
	var out []UploadBatch
	for rows.Next() {
		b, err := scanUploadBatch(rows)
		if err != nil {
			return nil, fmt.Errorf("db: scanning expired upload batch: %w", err)
		}
		out = append(out, b)
	}
	return out, rows.Err()
}

// LinkUploadReviewEntry records the review entry a batch member
// landed in, claiming only a still-unlinked staged row. A member that
// vanished (deleted mid-finalize) or was already linked affects zero
// rows and reports false — nothing to do, not a failure — and the
// narrow claim never clobbers concurrent state changes the way a
// whole-row rewrite from a stale gather would.
func (d *DB) LinkUploadReviewEntry(ctx context.Context, uploadID, entryID string) (bool, error) {
	res, err := d.w.ExecContext(ctx, `
		UPDATE uploads SET review_entry_id = ?
		WHERE id = ? AND review_entry_id = '' AND state = 'staged'`,
		entryID, uploadID)
	if err != nil {
		return false, fmt.Errorf("db: linking upload to review entry: %w", err)
	}
	n, err := res.RowsAffected()
	if err != nil {
		return false, fmt.Errorf("db: linking upload to review entry: %w", err)
	}
	return n == 1, nil
}
