package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
)

// Playlist source-entry states. fetching says this playlist's sync
// queued the entry's download, which is what later makes the file the
// sync's own to trash; attached says a sync added the entry's item to
// the playlist AND owns the file's presence (its own download brought
// it in); linked says the sync added the item but the file was already
// in the library - a hand acquisition's, another binding's - so
// mirror-trash must never touch it. An attached or linked member's
// later absence is the owner removing it by hand; tombstoned is the
// do-not-re-download memory that removal (or a review discard) leaves.
const (
	PlaylistEntryFetching   = "fetching"
	PlaylistEntryAttached   = "attached"
	PlaylistEntryLinked     = "linked"
	PlaylistEntryTombstoned = "tombstoned"
)

// PlaylistSyncCounts is one completed sync run's accounting.
type PlaylistSyncCounts struct {
	Added       int
	Removed     int
	Trashed     int
	Queued      int
	Unavailable int
	Missing     int
}

// PlaylistSourceRow is a playlist's external source binding: the stored
// settings, the resolved source identity, and the sync scheduler's
// health record (the feed_state shape).
type PlaylistSourceRow struct {
	PlaylistPID         string
	Source              string
	Live                bool
	URL                 string
	IdentityKey         string
	SourceID            string
	Title               string
	RefsJSON            string
	Mode                string
	IntervalHours       int
	CoverURL            string
	ConsecutiveFailures int
	Disabled            bool
	LastError           string
	LastAttemptNS       int64
	LastSyncedNS        int64
	LastCounts          PlaylistSyncCounts
	CreatedAtNS         int64
	UpdatedAtNS         int64
}

const playlistSourceCols = `playlist_pid, source, live, url, identity_key, source_id, title,
	refs_json, mode, interval_hours, cover_url, consecutive_failures, disabled, last_error,
	last_attempt_ns, last_synced_ns, last_added, last_removed, last_trashed, last_queued,
	last_unavailable, last_missing, created_at_ns, updated_at_ns`

func scanPlaylistSource(scan func(...any) error) (PlaylistSourceRow, error) {
	var row PlaylistSourceRow
	var live, disabled int64
	err := scan(&row.PlaylistPID, &row.Source, &live, &row.URL, &row.IdentityKey,
		&row.SourceID, &row.Title, &row.RefsJSON, &row.Mode, &row.IntervalHours,
		&row.CoverURL, &row.ConsecutiveFailures, &disabled, &row.LastError,
		&row.LastAttemptNS, &row.LastSyncedNS, &row.LastCounts.Added,
		&row.LastCounts.Removed, &row.LastCounts.Trashed, &row.LastCounts.Queued,
		&row.LastCounts.Unavailable, &row.LastCounts.Missing,
		&row.CreatedAtNS, &row.UpdatedAtNS)
	if err != nil {
		return PlaylistSourceRow{}, err
	}
	row.Live = live != 0
	row.Disabled = disabled != 0
	return row, nil
}

// PlaylistSourceFor reads one playlist's binding; ErrNotFound when it
// has none.
func (d *DB) PlaylistSourceFor(ctx context.Context, playlistPID string) (PlaylistSourceRow, error) {
	row, err := scanPlaylistSource(d.r.QueryRowContext(ctx, `
		SELECT `+playlistSourceCols+` FROM playlist_source WHERE playlist_pid = ?`,
		playlistPID).Scan)
	if errors.Is(err, sql.ErrNoRows) {
		return PlaylistSourceRow{}, ErrNotFound
	}
	if err != nil {
		return PlaylistSourceRow{}, fmt.Errorf("db: reading playlist source: %w", err)
	}
	return row, nil
}

// PutPlaylistSource stores a binding whole, replacing any previous one.
// Health starts over deliberately: the owner just changed what the sync
// follows or how, so stale failure accounting has nothing to say about
// the new settings.
func (d *DB) PutPlaylistSource(ctx context.Context, row PlaylistSourceRow) error {
	live, disabled := boolInt(row.Live), boolInt(row.Disabled)
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO playlist_source (`+playlistSourceCols+`)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT (playlist_pid) DO UPDATE SET
			source = excluded.source,
			live = excluded.live,
			url = excluded.url,
			identity_key = excluded.identity_key,
			source_id = excluded.source_id,
			title = excluded.title,
			refs_json = excluded.refs_json,
			mode = excluded.mode,
			interval_hours = excluded.interval_hours,
			cover_url = excluded.cover_url,
			consecutive_failures = excluded.consecutive_failures,
			disabled = excluded.disabled,
			last_error = excluded.last_error,
			last_attempt_ns = excluded.last_attempt_ns,
			last_synced_ns = excluded.last_synced_ns,
			last_added = excluded.last_added,
			last_removed = excluded.last_removed,
			last_trashed = excluded.last_trashed,
			last_queued = excluded.last_queued,
			last_unavailable = excluded.last_unavailable,
			last_missing = excluded.last_missing,
			updated_at_ns = excluded.updated_at_ns`,
		row.PlaylistPID, row.Source, live, row.URL, row.IdentityKey, row.SourceID,
		row.Title, row.RefsJSON, row.Mode, row.IntervalHours, row.CoverURL,
		row.ConsecutiveFailures, disabled, row.LastError, row.LastAttemptNS,
		row.LastSyncedNS, row.LastCounts.Added, row.LastCounts.Removed,
		row.LastCounts.Trashed, row.LastCounts.Queued, row.LastCounts.Unavailable,
		row.LastCounts.Missing, row.CreatedAtNS, row.UpdatedAtNS)
	if err != nil {
		return fmt.Errorf("db: storing playlist source: %w", err)
	}
	return nil
}

// DeletePlaylistSource removes a binding and the playlist's per-entry
// sync bookkeeping. The shared entry-to-item map stays: what a video
// became in the library is a fact about the library, and it is what
// spares a later re-bind from downloading everything again.
func (d *DB) DeletePlaylistSource(ctx context.Context, playlistPID string) error {
	if _, err := d.w.ExecContext(ctx, `DELETE FROM playlist_source WHERE playlist_pid = ?`, playlistPID); err != nil {
		return fmt.Errorf("db: deleting playlist source: %w", err)
	}
	if _, err := d.w.ExecContext(ctx, `DELETE FROM playlist_source_entries WHERE playlist_pid = ?`, playlistPID); err != nil {
		return fmt.Errorf("db: deleting playlist source entries: %w", err)
	}
	return nil
}

// DuePlaylistSources lists live, enabled bindings whose interval has
// elapsed since the last attempt, oldest attempt first.
func (d *DB) DuePlaylistSources(ctx context.Context, nowNS int64) ([]PlaylistSourceRow, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT `+playlistSourceCols+` FROM playlist_source
		WHERE live = 1 AND disabled = 0
		  AND last_attempt_ns + interval_hours * 3600000000000 <= ?
		ORDER BY last_attempt_ns`, nowNS)
	if err != nil {
		return nil, fmt.Errorf("db: listing due playlist sources: %w", err)
	}
	defer rows.Close()
	var out []PlaylistSourceRow
	for rows.Next() {
		row, err := scanPlaylistSource(rows.Scan)
		if err != nil {
			return nil, fmt.Errorf("db: scanning playlist source: %w", err)
		}
		out = append(out, row)
	}
	return out, rows.Err()
}

// RecordPlaylistSyncAttempt stamps that a run started, so the due check
// measures from run start and a long run is not immediately due again.
func (d *DB) RecordPlaylistSyncAttempt(ctx context.Context, playlistPID string, ns int64) error {
	_, err := d.w.ExecContext(ctx, `
		UPDATE playlist_source SET last_attempt_ns = ? WHERE playlist_pid = ?`,
		ns, playlistPID)
	if err != nil {
		return fmt.Errorf("db: recording playlist sync attempt: %w", err)
	}
	return nil
}

// RecordPlaylistSyncSuccess resets failure accounting after a run that
// worked (which also re-enables a disabled binding; a successful manual
// sync is the recovery path) and stores the run's counts.
func (d *DB) RecordPlaylistSyncSuccess(ctx context.Context, playlistPID string, ns int64, c PlaylistSyncCounts) error {
	_, err := d.w.ExecContext(ctx, `
		UPDATE playlist_source SET
			consecutive_failures = 0,
			disabled = 0,
			last_error = '',
			last_attempt_ns = ?,
			last_synced_ns = ?,
			last_added = ?,
			last_removed = ?,
			last_trashed = ?,
			last_queued = ?,
			last_unavailable = ?,
			last_missing = ?
		WHERE playlist_pid = ?`,
		ns, ns, c.Added, c.Removed, c.Trashed, c.Queued, c.Unavailable, c.Missing,
		playlistPID)
	if err != nil {
		return fmt.Errorf("db: recording playlist sync success: %w", err)
	}
	return nil
}

// RecordPlaylistSyncFailure bumps the failure counter and disables the
// binding once it reaches disableAfter. Returns the updated row, read
// through the write connection so the disable edge is visible to the
// caller that has to notify exactly once.
func (d *DB) RecordPlaylistSyncFailure(ctx context.Context, playlistPID, msg string, ns int64, disableAfter int) (PlaylistSourceRow, error) {
	_, err := d.w.ExecContext(ctx, `
		UPDATE playlist_source SET
			consecutive_failures = consecutive_failures + 1,
			disabled = CASE WHEN consecutive_failures + 1 >= ? THEN 1 ELSE disabled END,
			last_error = ?,
			last_attempt_ns = ?
		WHERE playlist_pid = ?`,
		disableAfter, msg, ns, playlistPID)
	if err != nil {
		return PlaylistSourceRow{}, fmt.Errorf("db: recording playlist sync failure: %w", err)
	}
	row, err := scanPlaylistSource(d.w.QueryRowContext(ctx, `
		SELECT `+playlistSourceCols+` FROM playlist_source WHERE playlist_pid = ?`,
		playlistPID).Scan)
	if errors.Is(err, sql.ErrNoRows) {
		return PlaylistSourceRow{}, ErrNotFound
	}
	if err != nil {
		return PlaylistSourceRow{}, fmt.Errorf("db: reading playlist source: %w", err)
	}
	return row, nil
}

// SetPlaylistSourceEnumerated stores what the latest enumeration said
// about the source itself: its title and its cover thumbnail URL.
func (d *DB) SetPlaylistSourceEnumerated(ctx context.Context, playlistPID, title, coverURL string) error {
	_, err := d.w.ExecContext(ctx, `
		UPDATE playlist_source SET title = ?, cover_url = ? WHERE playlist_pid = ?`,
		title, coverURL, playlistPID)
	if err != nil {
		return fmt.Errorf("db: recording playlist source enumeration: %w", err)
	}
	return nil
}

// PlaylistSourceMapRow says what one source entry became in the library.
// ItemPID is empty while the download is still in flight or its review
// entry has not resolved.
type PlaylistSourceMapRow struct {
	Source      string
	EntryID     string
	UploadID    string
	ItemPID     string
	Essence     string
	UpdatedAtNS int64
}

// PlaylistSourceMapFor batch-reads map rows for the given entry ids,
// keyed by entry id. Absent entries are simply absent. Chunked so a
// long-lived binding's accumulated ids never outgrow SQLite's variable
// cap.
func (d *DB) PlaylistSourceMapFor(ctx context.Context, source string, entryIDs []string) (map[string]PlaylistSourceMapRow, error) {
	out := map[string]PlaylistSourceMapRow{}
	for start := 0; start < len(entryIDs); start += 400 {
		chunk := entryIDs[start:min(start+400, len(entryIDs))]
		args := make([]any, 0, len(chunk)+1)
		args = append(args, source)
		for _, id := range chunk {
			args = append(args, id)
		}
		rows, err := d.r.QueryContext(ctx, `
			SELECT source, entry_id, upload_id, item_pid, essence, updated_at_ns
			FROM playlist_source_map
			WHERE source = ? AND entry_id IN (?`+strings.Repeat(",?", len(chunk)-1)+`)`,
			args...)
		if err != nil {
			return nil, fmt.Errorf("db: reading playlist source map: %w", err)
		}
		for rows.Next() {
			var m PlaylistSourceMapRow
			if err := rows.Scan(&m.Source, &m.EntryID, &m.UploadID, &m.ItemPID, &m.Essence, &m.UpdatedAtNS); err != nil {
				rows.Close()
				return nil, fmt.Errorf("db: scanning playlist source map row: %w", err)
			}
			out[m.EntryID] = m
		}
		err = rows.Err()
		rows.Close()
		if err != nil {
			return nil, fmt.Errorf("db: reading playlist source map: %w", err)
		}
	}
	return out, nil
}

// MarkLivePlaylistSourcesDue makes every enabled live binding due at
// the sweeper's next tick. Called when a sync download's review entry
// settles into an item, so the attach lands within a minute of the
// decision instead of at the next interval.
func (d *DB) MarkLivePlaylistSourcesDue(ctx context.Context) error {
	_, err := d.w.ExecContext(ctx, `
		UPDATE playlist_source SET last_attempt_ns = 0 WHERE live = 1 AND disabled = 0`)
	if err != nil {
		return fmt.Errorf("db: marking playlist sources due: %w", err)
	}
	return nil
}

// PutPlaylistSourceMapPending records that a download for the entry is
// in flight under uploadID. On an existing row only the upload id moves:
// a re-download after a lost item must not erase what the entry once
// resolved to until the new settle overwrites it.
func (d *DB) PutPlaylistSourceMapPending(ctx context.Context, source, entryID, uploadID string, ns int64) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO playlist_source_map (source, entry_id, upload_id, item_pid, essence, updated_at_ns)
		VALUES (?, ?, ?, '', '', ?)
		ON CONFLICT (source, entry_id) DO UPDATE SET
			upload_id = excluded.upload_id,
			updated_at_ns = excluded.updated_at_ns`,
		source, entryID, uploadID, ns)
	if err != nil {
		return fmt.Errorf("db: recording playlist source download: %w", err)
	}
	return nil
}

// CompletePlaylistSourceMap fills the item a settled upload resolved to,
// keyed by the upload row's id; reports whether any map row was waiting
// on it (the common case is none - most uploads are not playlist-sync
// downloads). An empty essence keeps whatever the row already holds,
// for the settle arms that know the pid but not the essence (an episode,
// an already-landed retry).
func (d *DB) CompletePlaylistSourceMap(ctx context.Context, uploadID, itemPID, essence string, ns int64) (bool, error) {
	if uploadID == "" {
		return false, nil
	}
	res, err := d.w.ExecContext(ctx, `
		UPDATE playlist_source_map SET
			item_pid = ?,
			essence = CASE WHEN ? != '' THEN ? ELSE essence END,
			updated_at_ns = ?
		WHERE upload_id = ?`,
		itemPID, essence, essence, ns, uploadID)
	if err != nil {
		return false, fmt.Errorf("db: completing playlist source map: %w", err)
	}
	n, err := res.RowsAffected()
	if err != nil {
		return false, fmt.Errorf("db: completing playlist source map: %w", err)
	}
	return n > 0, nil
}

// SetPlaylistSourceMapItem corrects a map row whose item moved (the
// self-heal path after a merge re-resolved the essence).
func (d *DB) SetPlaylistSourceMapItem(ctx context.Context, source, entryID, itemPID, essence string, ns int64) error {
	_, err := d.w.ExecContext(ctx, `
		UPDATE playlist_source_map SET item_pid = ?, essence = ?, updated_at_ns = ?
		WHERE source = ? AND entry_id = ?`,
		itemPID, essence, ns, source, entryID)
	if err != nil {
		return fmt.Errorf("db: updating playlist source map: %w", err)
	}
	return nil
}

// DeletePlaylistSourceMap forgets what an entry resolved to, so the
// next sync treats it as new.
func (d *DB) DeletePlaylistSourceMap(ctx context.Context, source, entryID string) error {
	_, err := d.w.ExecContext(ctx, `
		DELETE FROM playlist_source_map WHERE source = ? AND entry_id = ?`,
		source, entryID)
	if err != nil {
		return fmt.Errorf("db: deleting playlist source map row: %w", err)
	}
	return nil
}

// PlaylistSourceEntryStates reads a playlist's per-entry sync states,
// keyed by entry id.
func (d *DB) PlaylistSourceEntryStates(ctx context.Context, playlistPID string) (map[string]string, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT entry_id, state FROM playlist_source_entries WHERE playlist_pid = ?`,
		playlistPID)
	if err != nil {
		return nil, fmt.Errorf("db: reading playlist source entries: %w", err)
	}
	defer rows.Close()
	out := map[string]string{}
	for rows.Next() {
		var id, state string
		if err := rows.Scan(&id, &state); err != nil {
			return nil, fmt.Errorf("db: scanning playlist source entry: %w", err)
		}
		out[id] = state
	}
	return out, rows.Err()
}

// SetPlaylistSourceEntryState upserts one entry's per-playlist state.
func (d *DB) SetPlaylistSourceEntryState(ctx context.Context, playlistPID, entryID, state string, ns int64) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO playlist_source_entries (playlist_pid, entry_id, state, at_ns)
		VALUES (?, ?, ?, ?)
		ON CONFLICT (playlist_pid, entry_id) DO UPDATE SET
			state = excluded.state,
			at_ns = excluded.at_ns`,
		playlistPID, entryID, state, ns)
	if err != nil {
		return fmt.Errorf("db: storing playlist source entry state: %w", err)
	}
	return nil
}

// DeletePlaylistSourceEntryState drops one entry's per-playlist state.
func (d *DB) DeletePlaylistSourceEntryState(ctx context.Context, playlistPID, entryID string) error {
	_, err := d.w.ExecContext(ctx, `
		DELETE FROM playlist_source_entries WHERE playlist_pid = ? AND entry_id = ?`,
		playlistPID, entryID)
	if err != nil {
		return fmt.Errorf("db: deleting playlist source entry state: %w", err)
	}
	return nil
}

// ClearPlaylistSourceEntries drops a playlist's whole per-entry state,
// for a re-bind that points the playlist at a different source.
func (d *DB) ClearPlaylistSourceEntries(ctx context.Context, playlistPID string) error {
	_, err := d.w.ExecContext(ctx, `
		DELETE FROM playlist_source_entries WHERE playlist_pid = ?`, playlistPID)
	if err != nil {
		return fmt.Errorf("db: clearing playlist source entries: %w", err)
	}
	return nil
}
