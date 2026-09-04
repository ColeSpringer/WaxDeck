package db

import (
	"context"
	"fmt"
)

// TimelineStash is one minted gapless timeline: the key a client
// presents on the HLS surface (the sidecar's digest and the rendering
// asked of it, since one queue can be live in two formats at once), the
// signed upstream master URL the proxy reconstructs from it, and the
// instant both stop being useful (the media token minted alongside
// expires with the row).
//
// SignedMaster is a bearer credential, so persisting it widens where one
// lives, and that is a deliberate trade rather than an oversight. What
// it grants: the master playlist for one timeline, from the sidecar
// directly, until ExpiresAtNS (the queue's duration plus fifteen
// minutes, at least thirty). Who can spend it: only a caller who can
// already reach the sidecar's internal address, which never faces
// clients. Against what a reader of this file already holds: the
// sidecar API key, which the server reads from its own environment and
// which authorizes every root and every transcode outright. The
// credential here is strictly narrower and expires on its own.
//
// Two things would change that calculus. A longer TTL, or a deployment
// that exposes the sidecar. Either makes it worth storing the mint
// parameters instead and re-signing on restore, which the bridge can do
// (it holds the API key) and which would leave nothing bearer-shaped at
// rest, the way shares already derive their capability tokens rather
// than storing them.
type TimelineStash struct {
	Key          string
	SignedMaster string
	ExpiresAtNS  int64
}

// LoadTimelineStash returns the live mints and drops the expired ones in
// the same pass. The load is the first thing that runs after a restart,
// and a server that was down past every stored expiry would otherwise
// carry dead rows until a later mint swept them.
//
// Both halves run on the write connection, against the package's usual
// read/write split: pruning and reading what survived are one operation,
// and splitting them across connections would let the answer describe a
// table state neither statement saw.
func (d *DB) LoadTimelineStash(ctx context.Context, nowNS int64) ([]TimelineStash, error) {
	tx, err := d.w.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("db: reading the timeline stash: %w", err)
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx,
		`DELETE FROM timeline_stash WHERE expires_at_ns <= ?`, nowNS); err != nil {
		return nil, fmt.Errorf("db: pruning the timeline stash: %w", err)
	}
	rows, err := tx.QueryContext(ctx,
		`SELECT tl_key, signed_master, expires_at_ns FROM timeline_stash`)
	if err != nil {
		return nil, fmt.Errorf("db: reading the timeline stash: %w", err)
	}
	var out []TimelineStash
	for rows.Next() {
		var t TimelineStash
		if err := rows.Scan(&t.Key, &t.SignedMaster, &t.ExpiresAtNS); err != nil {
			rows.Close()
			return nil, fmt.Errorf("db: reading the timeline stash: %w", err)
		}
		out = append(out, t)
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		return nil, fmt.Errorf("db: reading the timeline stash: %w", err)
	}
	rows.Close()
	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("db: pruning the timeline stash: %w", err)
	}
	return out, nil
}

// PutTimelineStash records one mint and drops the expired rows,
// mirroring the sweep the in-memory stash runs on the same mint so the
// two never disagree about what is still live.
func (d *DB) PutTimelineStash(ctx context.Context, t TimelineStash, nowNS int64) error {
	tx, err := d.w.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("db: writing the timeline stash: %w", err)
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, `
		INSERT INTO timeline_stash (tl_key, signed_master, expires_at_ns)
		VALUES (?, ?, ?)
		ON CONFLICT (tl_key) DO UPDATE SET
			signed_master = excluded.signed_master,
			expires_at_ns = excluded.expires_at_ns`,
		t.Key, t.SignedMaster, t.ExpiresAtNS); err != nil {
		return fmt.Errorf("db: writing the timeline stash: %w", err)
	}
	if _, err := tx.ExecContext(ctx,
		`DELETE FROM timeline_stash WHERE expires_at_ns <= ?`, nowNS); err != nil {
		return fmt.Errorf("db: pruning the timeline stash: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("db: writing the timeline stash: %w", err)
	}
	return nil
}

// ForgetTimelineStash drops one mint, for a rendering the sidecar no
// longer serves.
func (d *DB) ForgetTimelineStash(ctx context.Context, key string) error {
	if _, err := d.w.ExecContext(ctx,
		`DELETE FROM timeline_stash WHERE tl_key = ?`, key); err != nil {
		return fmt.Errorf("db: deleting from the timeline stash: %w", err)
	}
	return nil
}
