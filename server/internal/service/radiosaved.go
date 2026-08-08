package service

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"strings"
	"time"

	"github.com/oklog/ulid/v2"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// Songs a listener kept off the air.
//
// A saved song is a playlist in shape and deliberately not in kind:
// nothing on the list is in the library, so nothing on it plays, and
// the rows exist to be hunted down and crossed off. That is why these
// live here rather than as catalog entities - waxbin holds items, and
// an announcement is not one.

// radioSavedLineMax bounds the announcement a save may carry. The
// contract says the same, and it is checked here as well because the
// line comes from a station: this is the one field a caller relays
// verbatim from an untrusted host into durable storage.
const radioSavedLineMax = 400

// radioSavedSnapshotPx is the size the matched item's cover is copied
// at. Big enough for the list's rows and a full-width phone tile,
// small enough that five hundred of them are tens of megabytes rather
// than the original masters.
const radioSavedSnapshotPx = 512

// RadioSavedSong is the API-facing shape of one kept announcement.
type RadioSavedSong struct {
	PID         string
	NowPlaying  string
	Artist      string
	Title       string
	StationPID  string
	StationName string
	HeardAt     time.Time
	// InLibraryPid is filled at read time when the row's announcement
	// now matches something this caller can see. Never stored: a
	// library grows, and a row saved before an album arrived should
	// cross itself off the day it does.
	InLibraryPID string
	HasArt       bool
}

// RadioSavedPage is one keyset page of saved songs.
type RadioSavedPage struct {
	Songs []RadioSavedSong
	Next  string
}

// radioSavedIdentity names one song across announcements, which is what
// makes the heart a toggle: the same track announced twice, or on two
// stations, is one row.
//
// Two disjoint key spaces, and the prefixes are what keep them that
// way. A line that parsed is keyed by its normalized artist and title,
// so "Charlie Parker - Ornithology (Live)" and "charlie parker -
// ornithology" are one song. A line that did not parse is keyed by the
// line itself, lightly folded - a bumper, a station ident, a title in a
// shape nothing recognises still saves, and saves once.
//
// The prefixes are not decoration. Without them a title that folded
// down to the same bytes as some raw line would collide across the two
// meanings, and this key is unchangeable the moment rows exist. Same
// shape as radioArtKey and deliberately not the same key: what a cover
// is filed under and what a save is identified by are different
// questions that happen to start from the same two strings.
func radioSavedIdentity(artist, title, raw string) string {
	// Both halves have to survive normalization, the same rule the
	// local-match rung applies. A name that was all punctuation
	// normalizes to nothing, and keying on what is left would file every
	// such line under one identity - so a line whose halves do not
	// survive falls back to being itself.
	na, nt := normalizeRadioField(artist), normalizeRadioField(title)
	var sum [32]byte
	if na != "" && nt != "" {
		sum = sha256.Sum256([]byte("parsed\x00" + na + "\x00" + nt))
	} else {
		sum = sha256.Sum256([]byte("raw\x00" + foldRadioLine(raw)))
	}
	return hex.EncodeToString(sum[:16])
}

// foldRadioLine folds an unparsed announcement just enough that the
// same line twice is one row: case and runs of whitespace, nothing
// else. Deliberately lighter than normalizeRadioField, which strips
// bracketed spans and would collapse "[ad break]" and "[promo]" onto
// one identity - two different things a listener might have kept.
func foldRadioLine(raw string) string {
	return strings.ToLower(strings.Join(strings.Fields(raw), " "))
}

// SaveRadioSong keeps the announcement a listener is looking at.
//
// The line is the caller's rather than read here, and that is the
// point: a station rolls its title over every few minutes while a
// client polls every fifteen seconds, so a save resolved against
// whatever is announced by the time this request lands would sometimes
// keep the next song instead of the tapped one.
//
// Idempotent on identity. A second save answers the row already held,
// so a filled heart tapped twice on two devices cannot mint two rows,
// and the only refusal is the list being full.
func (l *Library) SaveRadioSong(ctx context.Context, uc *UserCtx, apiStationPID, nowPlaying string) (RadioSavedSong, error) {
	line := strings.TrimSpace(nowPlaying)
	if line == "" {
		return RadioSavedSong{}, errInvalid("a saved song needs the announced line")
	}
	if len(line) > radioSavedLineMax {
		return RadioSavedSong{}, errInvalid("the announced line is too long to save")
	}
	station, err := l.radioStationRow(ctx, apiStationPID)
	if err != nil {
		return RadioSavedSong{}, err
	}
	// The same strict split scrobbling trusts. A line it does not
	// recognise still saves - as its raw self, which is what the
	// listener saw - rather than refusing the tap.
	artist, title, _ := parseRadioTitle(line, station.Name)
	row := wdb.RadioSavedSong{
		ID:          PrefixRadioSaved + "-" + ulid.Make().String(),
		UserID:      uc.ID,
		IdentityKey: radioSavedIdentity(artist, title, line),
		RawLine:     line,
		Artist:      artist,
		Title:       title,
		StationPID:  apiStationPID,
		StationName: station.Name,
		CreatedAtNS: time.Now().UnixNano(),
	}
	row.Art, row.ArtMime, row.ArtETag = l.radioSavedSnapshot(ctx, uc, apiStationPID, station.Name, line, artist, title)

	saved, err := l.db.CreateRadioSavedSong(ctx, row)
	if errors.Is(err, wdb.ErrConflict) {
		return RadioSavedSong{}, &Error{
			Kind: KindConflict,
			Msg:  "the saved songs list is full; remove something first",
		}
	}
	if err != nil {
		return RadioSavedSong{}, &Error{Kind: KindInternal, Err: err}
	}
	return radioSavedDTO(saved), nil
}

// radioSavedSnapshot copies whatever cover the listener was looking at.
//
// Copied rather than resolved later, because "resolve it again" turns
// the list into a pile of third-party lookups against a rung an
// operator may have switched off - and a picture that changes after the
// fact is not the one that was kept.
//
// The order is the live ladder's, so the snapshot is the picture that
// was on the face: the matched item's own cover first, then the one the
// station announced, then the external lookup's. Nothing is fetched
// here; every rung reads only what this server already holds, so a save
// costs no network and never blocks on one.
// A rung answers only with a picture that will actually be stored: past
// the column's cap the row saves artless, so a rung holding an oversize
// cover has not answered and the one below it gets its turn. Without
// this a 400 KB library cover took the ladder and left the row drawing a
// monogram while the announced cover - tens of kilobytes, and a fit -
// went unasked.
func (l *Library) radioSavedSnapshot(ctx context.Context, uc *UserCtx, apiStationPID, stationName, line, artist, title string) ([]byte, string, string) {
	fits := func(data []byte) bool {
		return len(data) > 0 && len(data) <= wdb.RadioSavedArtMaxBytes
	}
	if pid := l.RadioNowPlayingItem(ctx, uc, apiStationPID, stationName, line); pid != "" {
		if blob, err := l.Art(ctx, uc, pid, "front", radioSavedSnapshotPx); err == nil && fits(blob.Bytes) {
			return blob.Bytes, blob.MimeType, radioSavedETag(blob.Bytes)
		}
	}
	// The picture the station named in its own stream, if it is still
	// the picture for this line. Read under the same title the caller
	// sent, so a rollover between the tap and the save cannot hand this
	// row the next song's cover.
	if announced, artURL := l.RadioNowPlayingMeta(apiStationPID); announced == line && artURL != "" {
		if entry, ok := l.cachedRadioArt(announcedArtKey(artURL, line)); ok && fits(entry.art.Bytes) {
			return entry.art.Bytes, entry.art.MimeType, entry.art.ETag
		}
	}
	// The external rung, and only while the operator has it switched on.
	// The live cover's read path enforces the same rule for the same
	// reason - turning the rung off means "stop serving third-party
	// covers from this origin" - and a snapshot outlives both the toggle
	// and the forget that comes with it, so copying one here would put
	// that decision permanently out of reach. Reachable despite the
	// forget: a lookup already in flight when the switch goes off stores
	// its result afterwards.
	if artist != "" && title != "" && l.RadioExternalArtEnabled() {
		key := radioArtKey(radioSearchField(artist), radioSearchField(title))
		if entry, ok := l.cachedRadioArt(key); ok && fits(entry.art.Bytes) {
			return entry.art.Bytes, entry.art.MimeType, entry.art.ETag
		}
	}
	return nil, "", ""
}

func radioSavedETag(data []byte) string {
	sum := sha256.Sum256(data)
	return `"` + hex.EncodeToString(sum[:16]) + `"`
}

// ListRadioSaved pages one listener's saved songs newest first, marking
// the ones their library has since acquired.
//
// The marking is per page and per caller: it runs the same best-effort
// text match the full-screen face runs, under this caller's own
// visibility, so two accounts looking at the same song can honestly
// disagree about whether it is in the library.
func (l *Library) ListRadioSaved(ctx context.Context, uc *UserCtx, cursor string, limit int) (RadioSavedPage, error) {
	// Guarded here as well as at the handler, because the page slice
	// below is a slice: a limit under one makes `rows[:limit]` a panic
	// rather than a wrong answer, and that is not a failure mode to
	// leave resting on one caller remembering to bound it.
	if limit < 1 {
		return RadioSavedPage{}, errInvalid("limit must be at least 1")
	}
	if cursor != "" {
		if prefix, _, ok := parseAPIPID(cursor); !ok || prefix != PrefixRadioSaved {
			return RadioSavedPage{}, errInvalid("bad cursor")
		}
	}
	rows, err := l.db.ListRadioSavedSongs(ctx, uc.ID, cursor, limit+1)
	if err != nil {
		return RadioSavedPage{}, &Error{Kind: KindInternal, Err: err}
	}
	page := RadioSavedPage{}
	more := len(rows) > limit
	if more {
		rows = rows[:limit]
	}
	live := l.liveStationPIDs(ctx)
	for _, r := range rows {
		dto := radioSavedDTO(r)
		// A pid nobody can open is worse than no pid: the row outlives
		// the station, so a station since removed leaves the snapshot
		// name and nothing to tap. A nil set is a read that failed, and
		// keeping the pid is the better failure - it answers 404 at
		// worst, where dropping every one would report the whole dial
		// gone.
		if live != nil && !live[dto.StationPID] {
			dto.StationPID = ""
		}
		if r.Artist != "" && r.Title != "" {
			dto.InLibraryPID = l.matchLibraryTrack(ctx, uc, r.Artist, r.Title)
		}
		page.Songs = append(page.Songs, dto)
	}
	if more && len(rows) > 0 {
		page.Next = rows[len(rows)-1].ID
	}
	return page, nil
}

// liveStationPIDs is the set of stations still in the library, read
// once per page rather than per row: the station library is capped at
// five hundred shared rows and this is one query, where a per-row
// existence check would be fifty.
func (l *Library) liveStationPIDs(ctx context.Context) map[string]bool {
	rows, err := l.db.ListRadioStations(ctx)
	if err != nil {
		// Best effort. A read that failed is not a reason to tell the
		// client every station is gone, and the pid it keeps answers 404
		// at worst.
		l.log.Debug("reading stations for saved songs", "err", err)
		return nil
	}
	live := make(map[string]bool, len(rows))
	for _, r := range rows {
		live[PrefixRadioStation+"-"+r.ID] = true
	}
	return live
}

// RemoveRadioSaved drops one of the caller's saved songs. Removing one
// that is already gone is success: an untap racing a second device is
// not an error, and the caller asked for it to be absent.
func (l *Library) RemoveRadioSaved(ctx context.Context, uc *UserCtx, apiPID string) error {
	if prefix, _, ok := parseAPIPID(apiPID); !ok || prefix != PrefixRadioSaved {
		// Nothing under that name to remove, which is the same answer as
		// having removed it.
		return nil
	}
	if err := l.db.DeleteRadioSavedSong(ctx, uc.ID, apiPID); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	return nil
}

// RadioSavedArt answers a saved song's snapshot cover, in the shape the
// station-logo and now-playing-art endpoints already serve.
//
// A read and only a read: the bytes were copied at save time and never
// change, so there is no lookup to start and no freshness to reason
// about. Every way there is nothing to draw is a not-found, because the
// client draws a monogram for all of them.
func (l *Library) RadioSavedArt(ctx context.Context, uc *UserCtx, apiPID string) (RadioLogo, error) {
	missing := errNotFound("no artwork for saved song " + apiPID)
	if prefix, _, ok := parseAPIPID(apiPID); !ok || prefix != PrefixRadioSaved {
		return RadioLogo{}, missing
	}
	row, err := l.db.RadioSavedSongArt(ctx, uc.ID, apiPID)
	if errors.Is(err, wdb.ErrNotFound) {
		return RadioLogo{}, missing
	}
	if err != nil {
		return RadioLogo{}, &Error{Kind: KindInternal, Err: err}
	}
	mime := row.ArtMime
	if mime == "" {
		mime = "image/jpeg"
	}
	etag := row.ArtETag
	if etag == "" {
		etag = radioSavedETag(row.Art)
	}
	return RadioLogo{Bytes: row.Art, MimeType: mime, ETag: etag}, nil
}

// RadioSavedPIDForNowPlaying answers the pid of the caller's saved row
// for an announcement, empty when they have not kept it.
//
// One indexed read against the unique constraint, run per play-info
// poll. That is what keeps the heart honest across devices without a
// push: a save made on the phone fills the desktop's heart on its next
// poll, and a rollover empties it.
func (l *Library) RadioSavedPIDForNowPlaying(ctx context.Context, uc *UserCtx, stationName, raw string) string {
	if raw == "" {
		return ""
	}
	artist, title, _ := parseRadioTitle(raw, stationName)
	row, err := l.db.RadioSavedSongByIdentity(ctx, uc.ID, radioSavedIdentity(artist, title, raw))
	if err != nil {
		return ""
	}
	return row.ID
}

func radioSavedDTO(r wdb.RadioSavedSong) RadioSavedSong {
	return RadioSavedSong{
		PID:         r.ID,
		NowPlaying:  r.RawLine,
		Artist:      r.Artist,
		Title:       r.Title,
		StationPID:  r.StationPID,
		StationName: r.StationName,
		HeardAt:     time.Unix(0, r.CreatedAtNS).UTC(),
		HasArt:      r.HasArt,
	}
}
