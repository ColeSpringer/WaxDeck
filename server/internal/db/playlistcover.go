package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strconv"
)

// Cover origins. The catalog stores both kinds identically -- a
// front-role art row on the playlist entity -- so this is the only
// place that knows which one a playlist is showing.
const (
	// CoverCustom is an image a user uploaded. It wins over the mosaic
	// and is never regenerated; clearing it drops back to CoverGenerated.
	CoverCustom = "custom"
	// CoverGenerated is a mosaic (or single member cover) WaxDeck built
	// from the playlist's members, refreshed when the membership moves.
	CoverGenerated = "generated"
)

// artEpochKey is the sync_state row counting artwork writes anywhere in
// the catalog. A generated playlist cover records the epoch it was built
// at, so a member replacing its own cover in place -- which changes no
// membership and so no member-pid fingerprint -- still refreshes the
// mosaic built from it.
const artEpochKey = "art-epoch"

// ArtEpoch reads the artwork-write counter; 0 before the first write.
func (d *DB) ArtEpoch(ctx context.Context) (int64, error) {
	raw, err := d.SyncStateGet(ctx, artEpochKey)
	if err != nil {
		return 0, err
	}
	if raw == "" {
		return 0, nil
	}
	n, err := strconv.ParseInt(raw, 10, 64)
	if err != nil {
		return 0, fmt.Errorf("db: reading the art epoch: %w", err)
	}
	return n, nil
}

// BumpArtEpoch records that artwork somewhere in the catalog changed.
// It is a single counter rather than per-entity bookkeeping: the reader
// only needs to know something moved, and a coarse signal costs one
// regeneration per playlist on its next read instead of a fan-out over
// every playlist holding the edited item.
func (d *DB) BumpArtEpoch(ctx context.Context) error {
	if _, err := d.w.ExecContext(ctx, `
		INSERT INTO sync_state (key, value) VALUES (?, '1')
		ON CONFLICT (key) DO UPDATE SET
			value = CAST(CAST(sync_state.value AS INTEGER) + 1 AS TEXT)`,
		artEpochKey); err != nil {
		return fmt.Errorf("db: bumping the art epoch: %w", err)
	}
	return nil
}

// PlaylistCover records where one playlist's stored cover came from.
// Fingerprint is over the member list and the art epoch a generated
// cover was built from, and is empty for a custom one.
type PlaylistCover struct {
	PlaylistPID string
	Origin      string
	Fingerprint string
	UpdatedAtNS int64
}

// PutPlaylistCover stores or replaces one playlist's cover provenance.
func (d *DB) PutPlaylistCover(ctx context.Context, c PlaylistCover) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO playlist_cover (playlist_pid, origin, fingerprint, updated_at_ns)
		VALUES (?, ?, ?, ?)
		ON CONFLICT (playlist_pid) DO UPDATE SET
			origin = excluded.origin,
			fingerprint = excluded.fingerprint,
			updated_at_ns = excluded.updated_at_ns`,
		c.PlaylistPID, c.Origin, c.Fingerprint, c.UpdatedAtNS)
	if err != nil {
		return fmt.Errorf("db: writing playlist cover: %w", err)
	}
	return nil
}

// PlaylistCoverFor reads one playlist's cover provenance; ErrNotFound
// when the playlist has never had a cover stored.
func (d *DB) PlaylistCoverFor(ctx context.Context, playlistPID string) (PlaylistCover, error) {
	var c PlaylistCover
	err := d.r.QueryRowContext(ctx, `
		SELECT playlist_pid, origin, fingerprint, updated_at_ns
		FROM playlist_cover WHERE playlist_pid = ?`, playlistPID).
		Scan(&c.PlaylistPID, &c.Origin, &c.Fingerprint, &c.UpdatedAtNS)
	if errors.Is(err, sql.ErrNoRows) {
		return PlaylistCover{}, ErrNotFound
	}
	if err != nil {
		return PlaylistCover{}, fmt.Errorf("db: reading playlist cover: %w", err)
	}
	return c, nil
}

// DeletePlaylistCover forgets one playlist's cover provenance. The
// catalog drops the art rows when the playlist goes; this drops the
// row that says where they came from, so a later playlist minted with
// the same pid does not inherit a stale origin.
func (d *DB) DeletePlaylistCover(ctx context.Context, playlistPID string) error {
	if _, err := d.w.ExecContext(ctx,
		`DELETE FROM playlist_cover WHERE playlist_pid = ?`, playlistPID); err != nil {
		return fmt.Errorf("db: deleting playlist cover: %w", err)
	}
	return nil
}
