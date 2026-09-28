package db

import (
	"context"
	"fmt"
	"time"
)

// youtubePendingHorizon is how long an entry is held after a listing
// last showed it live. Premieres are scheduled weeks out.
const youtubePendingHorizon = 90 * 24 * time.Hour

// YouTubePending lists the entries held for one playlist at nowNS,
// least recently probed first: those past the horizon are left for the
// prune, and one handed over but not yet confirmed is still held.
func (d *DB) YouTubePending(ctx context.Context, sourceID string, nowNS int64) ([]string, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT video_id FROM youtube_pending
		WHERE source_id = ? AND seen_ns >= ?
		ORDER BY last_probed_ns, seen_ns, video_id`, sourceID, nowNS-int64(youtubePendingHorizon))
	if err != nil {
		return nil, fmt.Errorf("db: listing pending youtube entries: %w", err)
	}
	defer rows.Close()
	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, fmt.Errorf("db: listing pending youtube entries: %w", err)
		}
		ids = append(ids, id)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("db: listing pending youtube entries: %w", err)
	}
	return ids, nil
}

// RememberYouTubePending holds ids a listing showed live. An id already
// held takes the new sighting, which restarts its horizon, and keeps
// its probe stamp.
func (d *DB) RememberYouTubePending(ctx context.Context, sourceID string, ids []string, nowNS int64) error {
	tx, err := d.w.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("db: remembering pending youtube entries: %w", err)
	}
	defer tx.Rollback()
	for _, id := range ids {
		if _, err := tx.ExecContext(ctx, `
			INSERT INTO youtube_pending (source_id, video_id, seen_ns, last_probed_ns)
			VALUES (?, ?, ?, ?)
			ON CONFLICT (source_id, video_id) DO UPDATE SET seen_ns = excluded.seen_ns`,
			sourceID, id, nowNS, nowNS); err != nil {
			return fmt.Errorf("db: remembering pending youtube entries: %w", err)
		}
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("db: remembering pending youtube entries: %w", err)
	}
	return nil
}

// MarkYouTubePendingProbed stamps a look that left an entry pending.
func (d *DB) MarkYouTubePendingProbed(ctx context.Context, sourceID, videoID string, nowNS int64) error {
	if _, err := d.w.ExecContext(ctx, `
		UPDATE youtube_pending SET last_probed_ns = ?
		WHERE source_id = ? AND video_id = ?`,
		nowNS, sourceID, videoID); err != nil {
		return fmt.Errorf("db: stamping a pending youtube probe: %w", err)
	}
	return nil
}

// HandOverYouTubePending marks ids as handed to the catalog under token;
// they stay held until ConfirmYouTubePending names it.
func (d *DB) HandOverYouTubePending(ctx context.Context, sourceID string, ids []string, token int64) error {
	tx, err := d.w.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("db: handing over pending youtube entries: %w", err)
	}
	defer tx.Rollback()
	for _, id := range ids {
		if _, err := tx.ExecContext(ctx, `
			UPDATE youtube_pending SET handover = ?
			WHERE source_id = ? AND video_id = ?`,
			token, sourceID, id); err != nil {
			return fmt.Errorf("db: handing over pending youtube entries: %w", err)
		}
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("db: handing over pending youtube entries: %w", err)
	}
	return nil
}

// ConfirmYouTubePending drops one playlist's entries handed over under
// token, which the catalog has written.
func (d *DB) ConfirmYouTubePending(ctx context.Context, sourceID string, token int64) error {
	if _, err := d.w.ExecContext(ctx, `
		DELETE FROM youtube_pending WHERE source_id = ? AND handover = ?`,
		sourceID, token); err != nil {
		return fmt.Errorf("db: confirming handed-over youtube entries: %w", err)
	}
	return nil
}

// ForgetYouTubePending drops ids from one playlist's held entries.
func (d *DB) ForgetYouTubePending(ctx context.Context, sourceID string, ids []string) error {
	tx, err := d.w.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("db: forgetting pending youtube entries: %w", err)
	}
	defer tx.Rollback()
	for _, id := range ids {
		if _, err := tx.ExecContext(ctx, `
			DELETE FROM youtube_pending WHERE source_id = ? AND video_id = ?`,
			sourceID, id); err != nil {
			return fmt.Errorf("db: forgetting pending youtube entries: %w", err)
		}
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("db: forgetting pending youtube entries: %w", err)
	}
	return nil
}

// PruneYouTubePending drops every entry, of any playlist, past the
// horizon at nowNS.
func (d *DB) PruneYouTubePending(ctx context.Context, nowNS int64) (int64, error) {
	res, err := d.w.ExecContext(ctx, `
		DELETE FROM youtube_pending WHERE seen_ns < ?`, nowNS-int64(youtubePendingHorizon))
	if err != nil {
		return 0, fmt.Errorf("db: pruning pending youtube entries: %w", err)
	}
	return res.RowsAffected()
}
