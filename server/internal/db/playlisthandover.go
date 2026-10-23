package db

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"strings"
	"time"
)

// RepointPlaylistPins rewrites every account's home pins of one playlist
// to name another, for a playlist that was replaced by a copy under a new
// pid, and answers the accounts whose pins changed. from and to are API
// pids ("pl-..."). Pins are stored canonical, and the document is read
// whole, so the pid is replaced in the text: one statement, with nothing
// read first that an account's own save could overwrite.
func (d *DB) RepointPlaylistPins(ctx context.Context, from, to string) ([]string, error) {
	fail := func(err error) ([]string, error) {
		return nil, fmt.Errorf("db: repointing playlist pins: %w", err)
	}
	rows, err := d.w.QueryContext(ctx, `
		UPDATE prefs SET json = replace(json, ?, ?), updated_at_ns = ?
		WHERE instr(json, ?) > 0
		RETURNING user_id`,
		quoted(from), quoted(to), time.Now().UnixNano(), quoted(from))
	if err != nil {
		return fail(err)
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return fail(err)
		}
		out = append(out, id)
	}
	if err := rows.Err(); err != nil {
		return fail(err)
	}
	return out, nil
}

// quoted is a pid as it reads inside a JSON document.
func quoted(pid string) string { return `"` + pid + `"` }

// playlistHandoverPrefix keys the records below among the settings rows,
// by the bare pid of the playlist being handed over.
const playlistHandoverPrefix = "playlist-handover:"

// PlaylistHandover is the record of a smart playlist being handed over as
// a fixed copy, kept from before the copy is made until the playlist is
// gone, so that a handover that stops anywhere can be run again and finish
// with the copy it made rather than make another.
type PlaylistHandover struct {
	// SourcePID is the bare pid of the playlist being handed over.
	SourcePID string `json:"-"`
	// CopyPID is the bare pid of its fixed copy; empty from when the copy
	// is about to be made until it is named.
	CopyPID string `json:"copy,omitempty"`
	// UserID is the account the playlist belongs to, which is being
	// deleted, and TakerID the account the copy is for.
	UserID  string `json:"user"`
	TakerID string `json:"taker"`
}

// PutPlaylistHandover stores a record whole, replacing any for the same
// playlist.
func (d *DB) PutPlaylistHandover(ctx context.Context, h PlaylistHandover) error {
	raw, err := json.Marshal(h)
	if err != nil {
		return fmt.Errorf("db: encoding a playlist handover: %w", err)
	}
	return d.SettingSet(ctx, playlistHandoverPrefix+h.SourcePID, string(raw), time.Now().UnixNano())
}

// PlaylistHandoverFor reads the record of one playlist's handover;
// ErrNotFound when there is none.
func (d *DB) PlaylistHandoverFor(ctx context.Context, sourcePID string) (PlaylistHandover, error) {
	raw, err := d.SettingGet(ctx, playlistHandoverPrefix+sourcePID)
	if err != nil {
		return PlaylistHandover{}, err
	}
	return decodePlaylistHandover(sourcePID, raw)
}

func decodePlaylistHandover(sourcePID, raw string) (PlaylistHandover, error) {
	h := PlaylistHandover{SourcePID: sourcePID}
	if err := json.Unmarshal([]byte(raw), &h); err != nil {
		return PlaylistHandover{}, fmt.Errorf("db: reading the handover of playlist %s: %w", sourcePID, err)
	}
	return h, nil
}

// DeletePlaylistHandover removes one record; a missing one is a no-op.
func (d *DB) DeletePlaylistHandover(ctx context.Context, sourcePID string) error {
	return d.SettingDelete(ctx, playlistHandoverPrefix+sourcePID)
}

// PlaylistHandoversOf reads every record of an account's playlists, by
// source pid, for the account's deletion to deal with what a handover that
// stopped left. A record this build cannot read is nobody's here.
func (d *DB) PlaylistHandoversOf(ctx context.Context, userID string) ([]PlaylistHandover, error) {
	rows, err := d.SettingsWithPrefix(ctx, playlistHandoverPrefix)
	if err != nil {
		return nil, err
	}
	var out []PlaylistHandover
	for key, raw := range rows {
		h, err := decodePlaylistHandover(key[len(playlistHandoverPrefix):], raw)
		if err == nil && h.UserID == userID {
			out = append(out, h)
		}
	}
	slices.SortFunc(out, func(a, b PlaylistHandover) int { return strings.Compare(a.SourcePID, b.SourcePID) })
	return out, nil
}

// DeletePlaylistHandoversOf removes every record of an account's
// playlists, for the account's deletion to clear what a handover that
// stopped left.
func (d *DB) DeletePlaylistHandoversOf(ctx context.Context, userID string) error {
	records, err := d.PlaylistHandoversOf(ctx, userID)
	if err != nil {
		return err
	}
	var failed error
	for _, h := range records {
		failed = errors.Join(failed, d.DeletePlaylistHandover(ctx, h.SourcePID))
	}
	return failed
}
