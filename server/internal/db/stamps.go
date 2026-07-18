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
