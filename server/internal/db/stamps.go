package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"
)

// PlayStamp carries when the resume position last changed for one
// (user, item), in server-clock nanoseconds. Offline position replays
// reconcile against it; WaxBin's play_state row keeps only one
// UpdatedAt, which every position checkpoint bumps, so it cannot order
// a replay against the observation it competes with. Stars and ratings
// carried stamps here too until the catalog grew recorded-time
// last-writer-wins on its own writes; ordering those is its job now,
// so this table stamps resume positions alone.
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

// StampPlayState records when the resume position changed, ns, that the
// server saw it change now, which for a replayed position is later, and
// the id of the stored gpodder action that made the change, 0 for none.
// What the server saw is in flight for the gpodder reads from before it
// waits for the writer until it commits.
func (d *DB) StampPlayState(ctx context.Context, userID, itemPID string, ns, gpodderAction int64) error {
	seen := time.Now().UnixNano()
	defer d.gpodderWrites.hold(userID, seen/int64(time.Second))()
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO play_state_stamps (user_id, item_pid, position_ns, seen_ns, gpodder_action)
		VALUES (?, ?, ?, ?, ?)
		ON CONFLICT (user_id, item_pid) DO UPDATE SET
			position_ns = excluded.position_ns, seen_ns = excluded.seen_ns,
			gpodder_action = excluded.gpodder_action`,
		userID, itemPID, ns, seen, gpodderAction)
	if err != nil {
		return fmt.Errorf("db: writing play stamp: %w", err)
	}
	return nil
}

// TouchPlayStamp records that the server saw the item's played state
// change now, and the id of the stored gpodder action that made the
// change, 0 for none, leaving the position stamp where it was. It is in
// flight for the gpodder reads as StampPlayState is.
func (d *DB) TouchPlayStamp(ctx context.Context, userID, itemPID string, gpodderAction int64) error {
	seen := time.Now().UnixNano()
	defer d.gpodderWrites.hold(userID, seen/int64(time.Second))()
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO play_state_stamps (user_id, item_pid, seen_ns, gpodder_action)
		VALUES (?, ?, ?, ?)
		ON CONFLICT (user_id, item_pid) DO UPDATE SET
			seen_ns = excluded.seen_ns, gpodder_action = excluded.gpodder_action`,
		userID, itemPID, seen, gpodderAction)
	if err != nil {
		return fmt.Errorf("db: touching play stamp: %w", err)
	}
	return nil
}

// PositionStamp is one item whose play state the server saw change.
// FromGpodder marks a change a stored gpodder action made while the
// action log still keeps that action, which then tells it.
type PositionStamp struct {
	ItemPID     string
	PositionNS  int64
	SeenNS      int64
	FromGpodder bool
}

// PositionStampsAfter lists the account's stamps seen after the stamp of
// item afterPID seen at afterNS, first seen first and by pid within a
// nanosecond: what changed since a client last asked, whenever the change
// was recorded, a page at a time. An empty afterPID starts at afterNS
// itself.
func (d *DB) PositionStampsAfter(ctx context.Context, userID string, afterNS int64, afterPID string, limit int) ([]PositionStamp, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT s.item_pid, s.position_ns, s.seen_ns,
			s.gpodder_action <> 0 AND EXISTS (SELECT 1 FROM gpodder_actions a WHERE a.id = s.gpodder_action)
		FROM play_state_stamps s
		WHERE s.user_id = ? AND s.seen_ns >= ? AND (s.seen_ns > ? OR s.item_pid > ?)
		ORDER BY s.seen_ns, s.item_pid LIMIT ?`, userID, afterNS, afterNS, afterPID, limit)
	if err != nil {
		return nil, fmt.Errorf("db: listing play stamps: %w", err)
	}
	defer rows.Close()
	var out []PositionStamp
	for rows.Next() {
		var st PositionStamp
		if err := rows.Scan(&st.ItemPID, &st.PositionNS, &st.SeenNS, &st.FromGpodder); err != nil {
			return nil, fmt.Errorf("db: scanning play stamp: %w", err)
		}
		out = append(out, st)
	}
	return out, rows.Err()
}

// PruneStamps drops stamp rows last changed before the cutoff. The
// stamps exist to guard offline position replays and to tell the gpodder
// surface what changed; a pair untouched for the retention window serves
// neither.
func (d *DB) PruneStamps(ctx context.Context, olderThanNS int64) (int64, error) {
	res, err := d.w.ExecContext(ctx, `
		DELETE FROM play_state_stamps
		WHERE position_ns < ? AND seen_ns < ?`, olderThanNS, olderThanNS)
	if err != nil {
		return 0, fmt.Errorf("db: pruning play stamps: %w", err)
	}
	return res.RowsAffected()
}
