package service

import (
	"context"
	"crypto/md5"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/colespringer/waxbin/model"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// The Navidrome/Subsonic import. A minimal stdlib REST client pulls
// starred songs, albums, and artists, per-song ratings and play counts
// (walking the album list, which is the protocol's own offset-paged
// surface), and bookmark positions; each song matches a local track
// through the resolve ladder and the state replays through the service
// paths the API uses. A starred album or artist reaches the catalog
// through one of its member songs and the same ladder.

// subsonicClient covers exactly what the migration reads. Auth is the
// Subsonic token scheme: t = md5(password + salt) with a fresh random
// salt per request (md5 is the protocol's contract, not a WaxDeck
// choice), and every answer rides the {"subsonic-response": ...}
// envelope with f=json.
type subsonicClient struct {
	base     string
	username string
	password string
	hc       *http.Client
}

func newSubsonicClient(base, username, password string) *subsonicClient {
	return &subsonicClient{
		base:     strings.TrimRight(base, "/"),
		username: username,
		password: password,
		hc:       migrateHTTPClient(),
	}
}

// subsonicAPIError is a status:"failed" answer: the server understood
// the request and refused it, so retrying cannot help.
type subsonicAPIError struct {
	Code    int
	Message string
}

func (e *subsonicAPIError) Error() string {
	if e.Message == "" {
		return fmt.Sprintf("subsonic error %d", e.Code)
	}
	return fmt.Sprintf("subsonic error %d: %s", e.Code, e.Message)
}

// call performs one Subsonic REST call and unmarshals the envelope's
// payload into out (which names the payload field it expects).
func (c *subsonicClient) call(ctx context.Context, method string, params url.Values, out any) error {
	saltBytes := make([]byte, 8)
	if _, err := rand.Read(saltBytes); err != nil {
		return fmt.Errorf("subsonic salt: %w", err)
	}
	salt := hex.EncodeToString(saltBytes)
	sum := md5.Sum([]byte(c.password + salt))
	q := url.Values{}
	for k, vs := range params {
		q[k] = vs
	}
	q.Set("u", c.username)
	q.Set("t", hex.EncodeToString(sum[:]))
	q.Set("s", salt)
	q.Set("v", "1.16.1")
	q.Set("c", migrateClientName)
	q.Set("f", "json")
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.base+"/rest/"+method+"?"+q.Encode(), nil)
	if err != nil {
		return err
	}
	resp, err := c.hc.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return &migrateHTTPError{Status: resp.StatusCode, URL: c.base + "/rest/" + method}
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 64<<20))
	if err != nil {
		return err
	}
	var env struct {
		Response json.RawMessage `json:"subsonic-response"`
	}
	if err := json.Unmarshal(body, &env); err != nil {
		return fmt.Errorf("subsonic %s: unparseable answer: %w", method, err)
	}
	if len(env.Response) == 0 {
		return fmt.Errorf("subsonic %s: no subsonic-response envelope", method)
	}
	var status struct {
		Status string `json:"status"`
		Error  *struct {
			Code    int    `json:"code"`
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.Unmarshal(env.Response, &status); err != nil {
		return fmt.Errorf("subsonic %s: unparseable envelope: %w", method, err)
	}
	if status.Status == "failed" {
		apiErr := &subsonicAPIError{}
		if status.Error != nil {
			apiErr.Code, apiErr.Message = status.Error.Code, status.Error.Message
		}
		return apiErr
	}
	if out != nil {
		if err := json.Unmarshal(env.Response, out); err != nil {
			return fmt.Errorf("subsonic %s: unparseable payload: %w", method, err)
		}
	}
	return nil
}

// subsonicSong is the per-song shape shared by getAlbum, getStarred2,
// and bookmark entries. Duration is whole seconds by the protocol;
// played is the last-played time Navidrome emits, starred the time the
// star was set (the protocol carries it on both getStarred2 and
// getAlbum entries).
type subsonicSong struct {
	ID            string `json:"id"`
	Title         string `json:"title"`
	Artist        string `json:"artist"`
	Album         string `json:"album"`
	Duration      int64  `json:"duration"`
	UserRating    int    `json:"userRating"`
	PlayCount     int64  `json:"playCount"`
	Played        string `json:"played"`
	Starred       string `json:"starred"`
	MusicBrainzID string `json:"musicBrainzId"`
}

type subsonicAlbumRef struct {
	ID string `json:"id"`
}

// subsonicStarredEntity is one starred album or artist from
// getStarred2: identity plus the star's set time, which the import
// replays in.
type subsonicStarredEntity struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	Artist  string `json:"artist"`
	Starred string `json:"starred"`
}

// subsonicBookmark is one saved position; position is milliseconds.
type subsonicBookmark struct {
	Position int64        `json:"position"`
	Entry    subsonicSong `json:"entry"`
}

// subsonicStarred is one getStarred2 answer: the three lists the
// protocol groups stars into, all of which WaxDeck can hold now that
// the catalog carries entity-scoped stars beside item ones.
type subsonicStarred struct {
	Songs   []subsonicSong
	Albums  []subsonicStarredEntity
	Artists []subsonicStarredEntity
}

// starred reads getStarred2.
func (c *subsonicClient) starred(ctx context.Context) (subsonicStarred, error) {
	var res struct {
		Starred2 struct {
			Song   []subsonicSong          `json:"song"`
			Album  []subsonicStarredEntity `json:"album"`
			Artist []subsonicStarredEntity `json:"artist"`
		} `json:"starred2"`
	}
	if err := c.call(ctx, "getStarred2", nil, &res); err != nil {
		return subsonicStarred{}, err
	}
	return subsonicStarred{
		Songs:   res.Starred2.Song,
		Albums:  res.Starred2.Album,
		Artists: res.Starred2.Artist,
	}, nil
}

// albumSongCache memoizes getAlbum, the importer's most expensive
// request class: the album walk and the entity-star pass both reach for
// the same albums, and two starred artists can share one.
//
// It remembers selectively. An album the walk visits once and never
// revisits would otherwise hold the whole source library in memory, so
// only ids a caller has marked are kept; everything else passes through
// uncached.
type albumSongCache struct {
	client *subsonicClient
	songs  map[string][]subsonicSong
	keep   map[string]bool
}

func newAlbumSongCache(client *subsonicClient) *albumSongCache {
	return &albumSongCache{
		client: client,
		songs:  map[string][]subsonicSong{},
		keep:   map[string]bool{},
	}
}

// remember marks album ids worth caching, before or after they are
// fetched.
func (c *albumSongCache) remember(ids ...string) {
	for _, id := range ids {
		c.keep[id] = true
	}
}

func (c *albumSongCache) get(ctx context.Context, id string) ([]subsonicSong, error) {
	if songs, ok := c.songs[id]; ok {
		return songs, nil
	}
	songs, err := c.client.albumSongs(ctx, id)
	if err != nil {
		return nil, migrateClientErr(err)
	}
	if c.keep[id] {
		c.songs[id] = songs
	}
	return songs, nil
}

// artistAlbumIDs reads one artist's albums via getArtist, which is how
// a starred artist reaches a member song.
func (c *subsonicClient) artistAlbumIDs(ctx context.Context, id string) ([]string, error) {
	var res struct {
		Artist struct {
			Album []subsonicAlbumRef `json:"album"`
		} `json:"artist"`
	}
	params := url.Values{}
	params.Set("id", id)
	if err := c.call(ctx, "getArtist", params, &res); err != nil {
		return nil, err
	}
	ids := make([]string, 0, len(res.Artist.Album))
	for _, al := range res.Artist.Album {
		if al.ID != "" {
			ids = append(ids, al.ID)
		}
	}
	return ids, nil
}

// albumIDs walks getAlbumList2 alphabetically. The Subsonic list API is
// offset-paged by its own contract, so offsets are the source's idiom
// here, not a WaxDeck pagination choice.
func (c *subsonicClient) albumIDs(ctx context.Context) ([]string, error) {
	const pageSize = 500
	seen := map[string]bool{}
	var ids []string
	for offset := 0; ; offset += pageSize {
		var res struct {
			AlbumList2 struct {
				Album []subsonicAlbumRef `json:"album"`
			} `json:"albumList2"`
		}
		params := url.Values{}
		params.Set("type", "alphabeticalByName")
		params.Set("size", strconv.Itoa(pageSize))
		params.Set("offset", strconv.Itoa(offset))
		if err := c.call(ctx, "getAlbumList2", params, &res); err != nil {
			return nil, err
		}
		page := res.AlbumList2.Album
		fresh := 0
		for _, al := range page {
			if al.ID == "" || seen[al.ID] {
				continue
			}
			seen[al.ID] = true
			ids = append(ids, al.ID)
			fresh++
		}
		// A short page ends the walk; a page of repeats stops a server
		// that ignores offsets from looping us forever.
		if len(page) < pageSize || fresh == 0 {
			return ids, nil
		}
	}
}

// albumSongs reads one album's songs via getAlbum.
func (c *subsonicClient) albumSongs(ctx context.Context, id string) ([]subsonicSong, error) {
	var res struct {
		Album struct {
			Song []subsonicSong `json:"song"`
		} `json:"album"`
	}
	params := url.Values{}
	params.Set("id", id)
	if err := c.call(ctx, "getAlbum", params, &res); err != nil {
		return nil, err
	}
	return res.Album.Song, nil
}

// bookmarks reads getBookmarks.
func (c *subsonicClient) bookmarks(ctx context.Context) ([]subsonicBookmark, error) {
	var res struct {
		Bookmarks struct {
			Bookmark []subsonicBookmark `json:"bookmark"`
		} `json:"bookmarks"`
	}
	if err := c.call(ctx, "getBookmarks", nil, &res); err != nil {
		return nil, err
	}
	return res.Bookmarks.Bookmark, nil
}

// parseSubsonicTime reads a timestamp Navidrome emits (RFC 3339,
// fractional seconds included) plus the legacy Subsonic spelling;
// anything unparseable means no anchor and the caller decides what
// that costs.
func parseSubsonicTime(s string) time.Time {
	if s == "" {
		return time.Time{}
	}
	for _, layout := range []string{time.RFC3339Nano, "2006-01-02 15:04:05"} {
		if ts, err := time.Parse(layout, s); err == nil {
			return ts
		}
	}
	return time.Time{}
}

// recordedTime projects a parsed source timestamp onto the recordedAt
// argument the state writers take: nil for an absent or unparseable
// one, which lands the write in server-now instead of source time.
func recordedTime(ts time.Time) *time.Time {
	if ts.IsZero() {
		return nil
	}
	return &ts
}

// subsonicSongState is everything the source holds for one song worth
// importing.
type subsonicSongState struct {
	song        subsonicSong
	starred     bool
	bookmarkMS  int64
	hasBookmark bool
}

// runSubsonicImport pulls stars, ratings, play history, and bookmark
// positions from a Navidrome or Subsonic server and replays them into
// the catalog for the task's user. Only songs carrying state are
// matched (a library walk resolving every song would be pure cost); a
// dry run resolves and counts but writes nothing. Request volume is
// one getAlbum per album, O(albums), plus one per starred album and up
// to one per album of a starred artist, with progress and lease renewal
// as the walk goes.
func (l *Library) runSubsonicImport(ctx context.Context, t *wdb.ToolTask, uc *UserCtx, p migrationParams, secret string) (migrationSummary, error) {
	sum := migrationSummary{Source: p.Source, DryRun: p.DryRun, Samples: migrationSamples{Unmatched: []string{}}}
	client := newSubsonicClient(p.ServerURL, p.Username, secret)
	prog := newMigrateProgress(l, t)

	cache := newAlbumSongCache(client)

	// One state per source song id, in first-seen order so the summary
	// and its samples come out deterministic.
	states := map[string]*subsonicSongState{}
	var order []string
	note := func(song subsonicSong) *subsonicSongState {
		if song.ID == "" {
			return nil
		}
		st := states[song.ID]
		if st == nil {
			st = &subsonicSongState{song: song}
			states[song.ID] = st
			order = append(order, song.ID)
			return st
		}
		// Different answers describe the same song with different
		// completeness; keep the richest view.
		if song.PlayCount > st.song.PlayCount {
			st.song.PlayCount = song.PlayCount
		}
		if song.UserRating > 0 {
			st.song.UserRating = song.UserRating
		}
		if st.song.Played == "" {
			st.song.Played = song.Played
		}
		if st.song.Starred == "" {
			st.song.Starred = song.Starred
		}
		if st.song.MusicBrainzID == "" {
			st.song.MusicBrainzID = song.MusicBrainzID
		}
		return st
	}

	starred, err := client.starred(ctx)
	if err != nil {
		return sum, migrateClientErr(err)
	}
	for _, s := range starred.Songs {
		if st := note(s); st != nil {
			st.starred = true
		}
	}
	// The album walk below is about to fetch every album; the ones the
	// entity-star pass will ask for again are worth keeping.
	for _, al := range starred.Albums {
		cache.remember(al.ID)
	}

	// The album walk exists only to gather ratings and play history;
	// a stars-and-bookmarks-only run skips its O(albums) requests.
	var albums []string
	if p.Ratings || p.History {
		albums, err = client.albumIDs(ctx)
		if err != nil {
			return sum, migrateClientErr(err)
		}
	}
	for i, id := range albums {
		if ctx.Err() != nil {
			return sum, ctx.Err()
		}
		songs, err := cache.get(ctx, id)
		if err != nil {
			return sum, err
		}
		for _, s := range songs {
			if s.UserRating > 0 || s.PlayCount > 0 {
				note(s)
			}
		}
		prog.report(ctx, float64(i+1)/float64(len(albums))*90)
	}

	marks, err := client.bookmarks(ctx)
	if err != nil {
		return sum, migrateClientErr(err)
	}
	for _, b := range marks {
		if st := note(b.Entry); st != nil {
			st.bookmarkMS = b.Position
			st.hasBookmark = true
		}
	}

	for _, id := range order {
		if ctx.Err() != nil {
			return sum, ctx.Err()
		}
		st := states[id]
		s := st.song
		ref := model.PortableRef{
			Kind:       model.KindTrack,
			MBID:       s.MusicBrainzID,
			Artist:     s.Artist,
			Title:      s.Title,
			Album:      s.Album,
			DurationMS: s.Duration * 1000,
		}
		it, rung, err := l.resolveMigrationRef(ctx, ref)
		if err != nil {
			return sum, classify(err)
		}
		if it == nil || rung == model.MatchNone {
			sum.noteUnmatched(s.Artist, s.Title)
			continue
		}
		sum.Matched++
		pid := apiPID(PrefixTrack, it.PID)
		// write runs one state write unless this is a dry run; a
		// skippable failure (the item vanished mid-import) drops that
		// one write instead of failing the task.
		write := func(fn func() error) (bool, error) {
			if p.DryRun {
				return true, nil
			}
			if err := fn(); err != nil {
				if migrateWriteSkippable(err) {
					l.log.Warn("migration write skipped", "task", t.ID, "item", pid, "err", err)
					return false, nil
				}
				return false, err
			}
			return true, nil
		}
		if p.Stars && st.starred {
			// Land the star in the time the source recorded it, not
			// import time: the catalog orders star writes by recorded
			// time, so a backdated import cannot overwrite a star the
			// user set here more recently.
			starredAt := recordedTime(parseSubsonicTime(s.Starred))
			ok, err := write(func() error {
				_, err := l.SetStar(ctx, uc, pid, true, starredAt)
				return err
			})
			if err != nil {
				return sum, err
			}
			if ok {
				sum.Stars++
			}
		}
		if p.Ratings && s.UserRating > 0 {
			r := s.UserRating
			if r > 5 {
				r = 5
			}
			scaled := r * 20
			ok, err := write(func() error {
				_, err := l.SetRating(ctx, uc, pid, &scaled, nil)
				return err
			})
			if err != nil {
				return sum, err
			}
			if ok {
				sum.Ratings++
			}
		}
		if p.History && s.PlayCount > 0 {
			count := int(s.PlayCount)
			if count > migrateListenCap {
				count = migrateListenCap
				sum.ListensCapped++
			}
			if p.DryRun {
				sum.Listens += count
			} else {
				n, err := l.migrateListens(ctx, uc, p.Source, s.ID, pid,
					it.DurationMS, count, parseSubsonicTime(s.Played))
				if err != nil {
					return sum, err
				}
				sum.Listens += n
			}
		}
		if p.Progress && st.hasBookmark {
			ok, err := write(func() error {
				// A live replay (no recorded time) always applies, so
				// there is no skipped case to account for here.
				_, err := l.Checkpoint(ctx, uc, pid, st.bookmarkMS, nil)
				return err
			})
			if err != nil {
				return sum, err
			}
			if ok {
				sum.Progress++
			}
		}
	}
	if p.Stars {
		if err := l.importSubsonicEntityStars(ctx, t, uc, p, client, prog, starred, &sum, cache); err != nil {
			return sum, err
		}
	}
	prog.report(ctx, 95)
	return sum, nil
}

// importSubsonicEntityStars replays getStarred2's album and artist
// stars. There is no entity matcher and this does not add one: a
// starred group reaches the catalog through one of its member songs,
// which the resolve ladder already matches, and the matched item's own
// entity handles name the album or artist to star. The extra requests
// are per starred group, not per library item.
func (l *Library) importSubsonicEntityStars(ctx context.Context, t *wdb.ToolTask, uc *UserCtx, p migrationParams, client *subsonicClient, prog *migrateProgress, starred subsonicStarred, sum *migrationSummary, cache *albumSongCache) error {
	// resolveMember walks candidate source albums, and every song
	// within one, until the resolve ladder matches a local item, which
	// is the item whose entity handles name what to star.
	//
	// The search does not stop at the first song or the first album: one
	// remote song missing locally says nothing about the rest of the
	// group, and giving up there would silently drop the star for a
	// group most of which is present. Cost is bounded by the group, and
	// paid only for a starred one: one getAlbum per candidate album
	// (memoized, so the main walk's fetches and albums shared between
	// starred artists are not re-requested), and a local lookup per song
	// until one matches.
	resolveMember := func(albumIDs []string) (*model.ItemView, error) {
		for _, albumID := range albumIDs {
			songs, err := cache.get(ctx, albumID)
			if err != nil {
				return nil, err
			}
			for _, s := range songs {
				if ctx.Err() != nil {
					return nil, ctx.Err()
				}
				it, rung, err := l.resolveMigrationRef(ctx, model.PortableRef{
					Kind:       model.KindTrack,
					MBID:       s.MusicBrainzID,
					Artist:     s.Artist,
					Title:      s.Title,
					Album:      s.Album,
					DurationMS: s.Duration * 1000,
				})
				if err != nil {
					return nil, classify(err)
				}
				if it != nil && rung != model.MatchNone {
					return it, nil
				}
			}
		}
		return nil, nil
	}

	// star records the entity star for a group, given the local item one
	// of its members resolved to. A group that matches nothing local is
	// an unmatched sample, like a song that misses.
	star := func(albumIDs []string, label string, entityPID func(*model.ItemView) model.PID, prefix string, at string, count *int) error {
		it, err := resolveMember(albumIDs)
		if err != nil {
			return err
		}
		var pid model.PID
		if it != nil {
			pid = entityPID(it)
		}
		if pid == "" {
			// Either nothing matched, or the match carries no such
			// entity handle: a loose track has no album, so there is
			// nothing to star.
			sum.noteUnmatchedEntity(label)
			return nil
		}
		if p.DryRun {
			*count++
			return nil
		}
		if _, err := l.SetEntityStar(ctx, uc, apiPID(prefix, pid), true, recordedTime(parseSubsonicTime(at))); err != nil {
			if migrateWriteSkippable(err) {
				l.log.Warn("migration entity star skipped", "task", t.ID, "entity", label, "err", err)
				return nil
			}
			return err
		}
		*count++
		return nil
	}

	albumEntity := func(it *model.ItemView) model.PID { return it.AlbumPID }
	// The protocol's starred artist is an album artist; the catalog's
	// own album-artist handle does not fall back to the track artist,
	// so mirror the fallback the rest of the surface applies.
	artistEntity := func(it *model.ItemView) model.PID {
		if it.AlbumArtistPID != "" {
			return it.AlbumArtistPID
		}
		return it.ArtistPID
	}

	// Every group renews the task lease: this pass can spend many
	// requests, and prog.report is the importer's only renewal point.
	// The percentage does not move (the walk already reported 90 and
	// the caller reports 95), which report tolerates.
	for _, al := range starred.Albums {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		prog.report(ctx, 90)
		label := al.Name
		if al.Artist != "" {
			label = al.Artist + " - " + al.Name
		}
		if err := star([]string{al.ID}, label, albumEntity, PrefixAlbum, al.Starred, &sum.AlbumStars); err != nil {
			return err
		}
	}

	for _, ar := range starred.Artists {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		prog.report(ctx, 90)
		albumIDs, err := client.artistAlbumIDs(ctx, ar.ID)
		if err != nil {
			return migrateClientErr(err)
		}
		// Artists share albums (a compilation, a split release), and the
		// walk stops at the first that resolves, so the leading ones
		// repeat across artists.
		cache.remember(albumIDs...)
		if err := star(albumIDs, ar.Name, artistEntity, PrefixArtist, ar.Starred, &sum.ArtistStars); err != nil {
			return err
		}
	}
	return nil
}
