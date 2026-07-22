package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
)

// PlayStamp carries when each play-state field last changed for one
// (user, item), in server-clock nanoseconds. Offline replay
// reconciliation compares against these; WaxBin's play_state row keeps
// only one UpdatedAt, which every position checkpoint bumps. A star
// stamp is written on set and on clear, so a stale offline star can
// never resurrect an undone one.
type PlayStamp struct {
	PositionNS int64
	StarNS     int64
	RatingNS   int64
}

// PlayStamp reads the stamps for one (user, item); zero when never
// stamped.
func (d *DB) PlayStamp(ctx context.Context, userID, itemPID string) (PlayStamp, error) {
	var st PlayStamp
	err := d.r.QueryRowContext(ctx, `
		SELECT position_ns, star_ns, rating_ns FROM play_state_stamps
		WHERE user_id = ? AND item_pid = ?`,
		userID, itemPID).Scan(&st.PositionNS, &st.StarNS, &st.RatingNS)
	if errors.Is(err, sql.ErrNoRows) {
		return PlayStamp{}, nil
	}
	if err != nil {
		return PlayStamp{}, fmt.Errorf("db: reading play stamp: %w", err)
	}
	return st, nil
}

// Stampable play-state fields.
const (
	StampPosition = "position_ns"
	StampStar     = "star_ns"
	StampRating   = "rating_ns"
)

// StampPlayState records when one field changed. field must be one of
// the Stamp constants (compiled into the statement, never user input).
func (d *DB) StampPlayState(ctx context.Context, userID, itemPID, field string, ns int64) error {
	switch field {
	case StampPosition, StampStar, StampRating:
	default:
		return fmt.Errorf("db: unknown play stamp field %q", field)
	}
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO play_state_stamps (user_id, item_pid, `+field+`)
		VALUES (?, ?, ?)
		ON CONFLICT (user_id, item_pid) DO UPDATE SET `+field+` = excluded.`+field,
		userID, itemPID, ns)
	if err != nil {
		return fmt.Errorf("db: writing play stamp: %w", err)
	}
	return nil
}

// PruneStamps drops stamp rows whose every field last changed before
// the cutoff. The stamps exist to guard offline replays and to serve
// the in-progress surface; a pair untouched for the retention window
// serves neither.
func (d *DB) PruneStamps(ctx context.Context, olderThanNS int64) (int64, error) {
	res, err := d.w.ExecContext(ctx, `
		DELETE FROM play_state_stamps
		WHERE MAX(position_ns, star_ns, rating_ns) < ?`, olderThanNS)
	if err != nil {
		return 0, fmt.Errorf("db: pruning play stamps: %w", err)
	}
	return res.RowsAffected()
}

// RecentPositionStamps lists item pids the user holds position stamps
// for, most recently stamped first. This is the in-progress surface:
// the catalog's recently-played list requires a completed play, while
// a resume position exists from the first checkpoint.
func (d *DB) RecentPositionStamps(ctx context.Context, userID string, limit int) ([]string, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT item_pid FROM play_state_stamps
		WHERE user_id = ? AND position_ns > 0
		ORDER BY position_ns DESC LIMIT ?`, userID, limit)
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
