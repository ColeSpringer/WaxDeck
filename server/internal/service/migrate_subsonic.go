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
// starred songs, per-song ratings and play counts (walking the album
// list, which is the protocol's own offset-paged surface), and bookmark
// positions; each song matches a local track through the resolve
// ladder and the state replays through the service paths the API uses.

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
// played is the last-played time Navidrome emits.
type subsonicSong struct {
	ID            string `json:"id"`
	Title         string `json:"title"`
	Artist        string `json:"artist"`
	Album         string `json:"album"`
	Duration      int64  `json:"duration"`
	UserRating    int    `json:"userRating"`
	PlayCount     int64  `json:"playCount"`
	Played        string `json:"played"`
	MusicBrainzID string `json:"musicBrainzId"`
}

type subsonicAlbumRef struct {
	ID string `json:"id"`
}

// subsonicBookmark is one saved position; position is milliseconds.
type subsonicBookmark struct {
	Position int64        `json:"position"`
	Entry    subsonicSong `json:"entry"`
}

// starredSongs reads getStarred2. Starred albums and artists ride the
// same answer but WaxDeck's star surface is per-item, so only songs
// import.
func (c *subsonicClient) starredSongs(ctx context.Context) ([]subsonicSong, error) {
	var res struct {
		Starred2 struct {
			Song []subsonicSong `json:"song"`
		} `json:"starred2"`
	}
	if err := c.call(ctx, "getStarred2", nil, &res); err != nil {
		return nil, err
	}
	return res.Starred2.Song, nil
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

// parseSubsonicTime reads the last-played time Navidrome emits
// (RFC 3339, fractional seconds included) plus the legacy Subsonic
// spelling; anything unparseable means no anchor and the caller falls
// back to the recent past.
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
// one getAlbum per album, O(albums), with progress and lease renewal
// as the walk goes.
func (l *Library) runSubsonicImport(ctx context.Context, t *wdb.ToolTask, uc *UserCtx, p migrationParams, secret string) (migrationSummary, error) {
	sum := migrationSummary{Source: p.Source, DryRun: p.DryRun, Samples: migrationSamples{Unmatched: []string{}}}
	client := newSubsonicClient(p.ServerURL, p.Username, secret)
	prog := newMigrateProgress(l, t)

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
		if st.song.MusicBrainzID == "" {
			st.song.MusicBrainzID = song.MusicBrainzID
		}
		return st
	}

	starred, err := client.starredSongs(ctx)
	if err != nil {
		return sum, migrateClientErr(err)
	}
	for _, s := range starred {
		if st := note(s); st != nil {
			st.starred = true
		}
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
		songs, err := client.albumSongs(ctx, id)
		if err != nil {
			return sum, migrateClientErr(err)
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
			ok, err := write(func() error {
				_, err := l.SetStar(ctx, uc, pid, true, nil)
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
				return l.Checkpoint(ctx, uc, pid, st.bookmarkMS, nil)
			})
			if err != nil {
				return sum, err
			}
			if ok {
				sum.Progress++
			}
		}
	}
	prog.report(ctx, 95)
	return sum, nil
}
