package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
)

// PlayStamp carries when the resume position last changed for one
// (user, item), in server-clock nanoseconds. Offline position replays
// reconcile against it; WaxBin's play_state row keeps only one
// UpdatedAt, which every position checkpoint bumps, so it cannot order
// a replay against the observation it competes with. Stars and ratings
// carried stamps here too until the catalog grew recorded-time
// last-writer-wins on its own writes; ordering those is its job now,
// and this table is purely the resume shelf.
type PlayStamp struct {
	PositionNS int64
}

// PlayStamp reads the stamp for one (user, item); zero when never
// stamped.
func (d *DB) PlayStamp(ctx context.Context, userID, itemPID string) (PlayStamp, error) {
	var st PlayStamp
	err := d.r.QueryRowContext(ctx, `
		SELECT position_ns FROM play_state_stamps
		WHERE user_id = ? AND item_pid = ?`,
		userID, itemPID).Scan(&st.PositionNS)
	if errors.Is(err, sql.ErrNoRows) {
		return PlayStamp{}, nil
	}
	if err != nil {
		return PlayStamp{}, fmt.Errorf("db: reading play stamp: %w", err)
	}
	return st, nil
}

// StampPlayState records when the resume position changed.
func (d *DB) StampPlayState(ctx context.Context, userID, itemPID string, ns int64) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO play_state_stamps (user_id, item_pid, position_ns)
		VALUES (?, ?, ?)
		ON CONFLICT (user_id, item_pid) DO UPDATE SET position_ns = excluded.position_ns`,
		userID, itemPID, ns)
	if err != nil {
		return fmt.Errorf("db: writing play stamp: %w", err)
	}
	return nil
}

// PruneStamps drops stamp rows last changed before the cutoff. The
// stamps exist to guard offline position replays and to serve the
// in-progress surface; a pair untouched for the retention window serves
// neither.
func (d *DB) PruneStamps(ctx context.Context, olderThanNS int64) (int64, error) {
	res, err := d.w.ExecContext(ctx, `
		DELETE FROM play_state_stamps
		WHERE position_ns < ?`, olderThanNS)
	if err != nil {
		return 0, fmt.Errorf("db: pruning play stamps: %w", err)
	}
	return res.RowsAffected()
}

// RecentPositionStamps lists item pids the user holds position stamps
// for, most recently stamped first, skipping the first offset rows.
// This is the in-progress surface: the catalog's recently-played list
// requires a completed play, while a resume position exists from the
// first checkpoint.
//
// The offset exists because the caller filters what it reads - kind,
// trashed, library visibility, subscription - and a bare limit spends
// the whole budget on rows that may all drop, so a ten-slot shelf came
// back with eight. The tiebreaker makes the order total, so paging over
// stamps written in the same nanosecond cannot skip a row; the caller
// still de-duplicates, because a concurrent checkpoint can move a row
// between pages.
func (d *DB) RecentPositionStamps(ctx context.Context, userID string, limit, offset int) ([]string, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT item_pid FROM play_state_stamps
		WHERE user_id = ? AND position_ns > 0
		ORDER BY position_ns DESC, item_pid DESC LIMIT ? OFFSET ?`, userID, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("db: listing position stamps: %w", err)
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var pid string
		if err := rows.Scan(&pid); err != nil {
			return nil, fmt.Errorf("db: scanning position stamp: %w", err)
		}
		out = append(out, pid)
	}
	return out, rows.Err()
}
