package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
)

// radioSavedSongCap bounds one listener's saved songs. The list is a
// hunt-these-down shelf rather than a collection, and the cap is what
// keeps a heart wired to a poll from turning a stuck client into
// unbounded rows carrying unbounded blobs.
const radioSavedSongCap = 500

// RadioSavedArtMaxBytes caps one snapshot cover. Past this the row saves
// artless and the list draws a monogram, which is a designed state: the
// point of the snapshot is that the picture the listener saw survives,
// not that every picture does. With the row cap this bounds the feature
// at a worst case in the low hundreds of megabytes and a typical one in
// the tens of kilobytes per row.
//
// Exported because the snapshot ladder above this layer reads it too: a
// rung whose picture would not fit has not answered, and the rung below
// it deserves its turn rather than the row saving artless with a cover
// going spare. This layer keeps enforcing it regardless - the cap is a
// property of the column, not of one caller's politeness.
const RadioSavedArtMaxBytes = 256 << 10

// RadioSavedSong is one song a listener kept off the air.
//
// Everything about the moment is denormalized on purpose: the station's
// name and pid are snapshots, so a row outlives the station being
// renamed, re-added under a new pid, or deleted outright, and RawLine is
// the announcement exactly as the listener saw it even when nothing
// parsed out of it.
type RadioSavedSong struct {
	ID          string
	UserID      string
	IdentityKey string
	RawLine     string
	Artist      string
	Title       string
	StationPID  string
	StationName string
	// Art is the snapshot cover. Read only by the artwork endpoint;
	// every listing leaves it behind and reports HasArt instead.
	Art     []byte
	ArtMime string
	ArtETag string
	HasArt  bool

	CreatedAtNS int64
}

// CreateRadioSavedSong saves a song, or answers the row already saved
// under the same identity.
//
// Idempotent by identity rather than refusing: the heart is a toggle a
// listener taps, two devices can poll and tap across one rollover, and a
// second save of the same announcement means "keep this", which it
// already is. ErrConflict is the cap and only the cap.
//
// The cap lives inside the statement so concurrent saves cannot slip
// past it, and the conflict re-read runs first when the insert stores
// nothing. That order is the whole subtlety: at the cap every insert
// affects zero rows, so checking the cap first would answer "full" for a
// song this listener already saved - the one case where nothing needed
// to be stored at all.
func (d *DB) CreateRadioSavedSong(ctx context.Context, s RadioSavedSong) (RadioSavedSong, error) {
	if len(s.Art) > RadioSavedArtMaxBytes {
		// Saved artless rather than refused: the row is the point and the
		// cover is a nicety, and a station serving a half-megabyte JPEG
		// must not cost a listener the save.
		s.Art, s.ArtMime, s.ArtETag = nil, "", ""
	}
	var art any
	if len(s.Art) > 0 {
		art = s.Art
	}
	res, err := d.w.ExecContext(ctx, `
		INSERT INTO radio_saved_songs
			(id, user_id, identity_key, raw_line, artist, title,
			 station_pid, station_name, art, art_mime, art_etag, created_at_ns)
		SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
		WHERE (SELECT COUNT(*) FROM radio_saved_songs WHERE user_id = ?) < ?
		ON CONFLICT (user_id, identity_key) DO NOTHING`,
		s.ID, s.UserID, s.IdentityKey, s.RawLine, s.Artist, s.Title,
		s.StationPID, s.StationName, art, s.ArtMime, s.ArtETag, s.CreatedAtNS,
		s.UserID, radioSavedSongCap)
	if err != nil {
		return RadioSavedSong{}, fmt.Errorf("db: saving radio song: %w", err)
	}
	n, err := res.RowsAffected()
	if err != nil {
		return RadioSavedSong{}, fmt.Errorf("db: saving radio song: %w", err)
	}
	if n > 0 {
		s.HasArt = len(s.Art) > 0
		return s, nil
	}
	held, err := d.radioSavedByIdentityWrite(ctx, s.UserID, s.IdentityKey)
	if errors.Is(err, ErrNotFound) {
		return RadioSavedSong{}, ErrConflict
	}
	if err != nil {
		return RadioSavedSong{}, err
	}
	return held, nil
}

// radioSavedListColumns is every column but the blob. The cover is read
// only by the artwork endpoint, so a page of fifty rows never carries
// megabytes it will not draw.
const radioSavedListColumns = `id, user_id, identity_key, raw_line, artist, title,
	station_pid, station_name, COALESCE(LENGTH(art), 0) > 0, art_mime, art_etag, created_at_ns`

func scanRadioSavedSong(rows interface{ Scan(...any) error }) (RadioSavedSong, error) {
	var s RadioSavedSong
	err := rows.Scan(&s.ID, &s.UserID, &s.IdentityKey, &s.RawLine, &s.Artist, &s.Title,
		&s.StationPID, &s.StationName, &s.HasArt, &s.ArtMime, &s.ArtETag, &s.CreatedAtNS)
	return s, err
}

// ListRadioSavedSongs pages one listener's saved songs newest first. The
// cursor is the previous page's last id; empty starts at the head.
//
// The id is a ULID, so its descending order is the order they were
// heard in and the keyset needs no second column to break ties.
func (d *DB) ListRadioSavedSongs(ctx context.Context, userID, afterID string, limit int) ([]RadioSavedSong, error) {
	q := `SELECT ` + radioSavedListColumns + `
	      FROM radio_saved_songs WHERE user_id = ?`
	args := []any{userID}
	if afterID != "" {
		q += ` AND id < ?`
		args = append(args, afterID)
	}
	q += ` ORDER BY id DESC LIMIT ?`
	args = append(args, limit)
	rows, err := d.r.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, fmt.Errorf("db: listing saved radio songs: %w", err)
	}
	defer rows.Close()
	var out []RadioSavedSong
	for rows.Next() {
		s, err := scanRadioSavedSong(rows)
		if err != nil {
			return nil, fmt.Errorf("db: scanning saved radio song: %w", err)
		}
		out = append(out, s)
	}
	return out, rows.Err()
}

// RadioSavedSongByIdentity reads the row one listener holds under an
// identity; ErrNotFound when they hold none.
//
// This is the play-info poll's membership lookup, so it is one indexed
// read against the unique constraint and never touches the blob.
func (d *DB) RadioSavedSongByIdentity(ctx context.Context, userID, identityKey string) (RadioSavedSong, error) {
	row := d.r.QueryRowContext(ctx,
		`SELECT `+radioSavedListColumns+`
		 FROM radio_saved_songs WHERE user_id = ? AND identity_key = ?`,
		userID, identityKey)
	return radioSavedRow(row, "reading saved radio song")
}

// radioSavedByIdentityWrite is the same read through the write
// connection, so a row the guard statement just conflicted with is
// visible regardless of read-pool snapshot timing.
func (d *DB) radioSavedByIdentityWrite(ctx context.Context, userID, identityKey string) (RadioSavedSong, error) {
	row := d.w.QueryRowContext(ctx,
		`SELECT `+radioSavedListColumns+`
		 FROM radio_saved_songs WHERE user_id = ? AND identity_key = ?`,
		userID, identityKey)
	return radioSavedRow(row, "reading saved radio song")
}

func radioSavedRow(row *sql.Row, what string) (RadioSavedSong, error) {
	s, err := scanRadioSavedSong(row)
	if errors.Is(err, sql.ErrNoRows) {
		return RadioSavedSong{}, ErrNotFound
	}
	if err != nil {
		return RadioSavedSong{}, fmt.Errorf("db: %s: %w", what, err)
	}
	return s, nil
}

// RadioSavedSongArt reads one row's snapshot cover; ErrNotFound when the
// row is absent, belongs to someone else, or saved without a picture.
// The caller draws a monogram for all three.
func (d *DB) RadioSavedSongArt(ctx context.Context, userID, id string) (RadioSavedSong, error) {
	var s RadioSavedSong
	var art []byte
	err := d.r.QueryRowContext(ctx,
		`SELECT id, art, art_mime, art_etag FROM radio_saved_songs
		 WHERE user_id = ? AND id = ?`, userID, id).
		Scan(&s.ID, &art, &s.ArtMime, &s.ArtETag)
	if errors.Is(err, sql.ErrNoRows) {
		return RadioSavedSong{}, ErrNotFound
	}
	if err != nil {
		return RadioSavedSong{}, fmt.Errorf("db: reading saved radio song art: %w", err)
	}
	if len(art) == 0 {
		return RadioSavedSong{}, ErrNotFound
	}
	s.UserID, s.Art, s.HasArt = userID, art, true
	return s, nil
}

// DeleteRadioSavedSong removes one of a listener's saved songs.
//
// Deleting one that is already gone is not an error: the caller asked
// for it to be absent and it is. A row belonging to someone else is the
// same answer, and deliberately so - the scope is what keeps one
// listener's id from naming another's row, and reporting the difference
// would say whether that row exists.
func (d *DB) DeleteRadioSavedSong(ctx context.Context, userID, id string) error {
	if _, err := d.w.ExecContext(ctx,
		`DELETE FROM radio_saved_songs WHERE user_id = ? AND id = ?`,
		userID, id); err != nil {
		return fmt.Errorf("db: deleting saved radio song: %w", err)
	}
	return nil
}
