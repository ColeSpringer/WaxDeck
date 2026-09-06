package scrobble

import (
	"bytes"
	"context"
	"crypto/md5"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"sort"
	"strconv"
	"strings"
)

// Lastfm speaks the Last.fm web service API with server API
// credentials. Per-user session keys come from the authorization
// callback flow and are stored by the service layer.
type Lastfm struct {
	apiKey string
	secret string
	// BaseURL and AuthBaseURL are overridable for tests.
	BaseURL     string
	AuthBaseURL string
	HTTP        *http.Client
}

// NewLastfm builds a client with the server's API credentials.
func NewLastfm(apiKey, secret string) *Lastfm {
	return &Lastfm{
		apiKey:      apiKey,
		secret:      secret,
		BaseURL:     "https://ws.audioscrobbler.com/2.0/",
		AuthBaseURL: "https://www.last.fm/api/auth/",
		HTTP:        httpClient,
	}
}

// AuthURL is the user-facing authorization URL; Last.fm redirects to
// callback with a token appended after approval.
func (c *Lastfm) AuthURL(callback string) string {
	return c.AuthBaseURL + "?api_key=" + url.QueryEscape(c.apiKey) + "&cb=" + url.QueryEscape(callback)
}

// GetSession exchanges an authorization token for a session key and
// the account's username.
func (c *Lastfm) GetSession(ctx context.Context, token string) (sessionKey, username string, err error) {
	params := map[string]string{
		"method":  "auth.getSession",
		"api_key": c.apiKey,
		"token":   token,
	}
	body, err := c.call(ctx, params)
	if err != nil {
		return "", "", err
	}
	var out struct {
		Session struct {
			Name string `json:"name"`
			Key  string `json:"key"`
		} `json:"session"`
	}
	if err := json.Unmarshal(body, &out); err != nil || out.Session.Key == "" {
		return "", "", &Permanent{Err: fmt.Errorf("lastfm: unexpected session response")}
	}
	return out.Session.Key, out.Session.Name, nil
}

// Scrobble submits one listen.
func (c *Lastfm) Scrobble(ctx context.Context, sessionKey string, t Track) error {
	params := map[string]string{
		"method":       "track.scrobble",
		"api_key":      c.apiKey,
		"sk":           sessionKey,
		"artist[0]":    t.Artist,
		"track[0]":     t.Title,
		"timestamp[0]": strconv.FormatInt(t.ListenedAt, 10),
	}
	if t.Album != "" {
		params["album[0]"] = t.Album
	}
	if t.DurationMS > 0 {
		params["duration[0]"] = strconv.FormatInt(t.DurationMS/1000, 10)
	}
	_, err := c.call(ctx, params)
	return err
}

// NowPlaying updates the account's now-playing display; best effort by
// nature (there is nothing durable to retry).
func (c *Lastfm) NowPlaying(ctx context.Context, sessionKey string, t Track) error {
	params := map[string]string{
		"method":  "track.updateNowPlaying",
		"api_key": c.apiKey,
		"sk":      sessionKey,
		"artist":  t.Artist,
		"track":   t.Title,
	}
	if t.Album != "" {
		params["album"] = t.Album
	}
	if t.DurationMS > 0 {
		params["duration"] = strconv.FormatInt(t.DurationMS/1000, 10)
	}
	_, err := c.call(ctx, params)
	return err
}

// HistoryTrack is one row of a user's scrobble history, as the read
// methods report it. Timestamps are epoch seconds; a zero one is the
// now-playing row, which is not a scrobble.
type HistoryTrack struct {
	Artist     string
	ArtistMBID string
	Title      string
	MBID       string
	Album      string
	At         int64
}

// lastfmHistoryPage is the shape both read methods answer in: a list of
// tracks under a named key, plus the paging attributes.
type lastfmHistoryPage struct {
	Tracks []struct {
		Name   string `json:"name"`
		MBID   string `json:"mbid"`
		Artist struct {
			Text string `json:"#text"`
			Name string `json:"name"`
			MBID string `json:"mbid"`
		} `json:"artist"`
		Album struct {
			Text string `json:"#text"`
		} `json:"album"`
		Date struct {
			UTS string `json:"uts"`
		} `json:"date"`
		Attr struct {
			NowPlaying string `json:"nowplaying"`
		} `json:"@attr"`
	}
	TotalPages int
}

// decodeHistory pulls one page out of the envelope. The wrapper key
// differs per method and the track list is nested one deeper, so the
// two names are passed in rather than modelled twice.
func decodeHistory(body []byte, wrapper, list string) (lastfmHistoryPage, error) {
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(body, &raw); err != nil {
		return lastfmHistoryPage{}, &Permanent{Err: fmt.Errorf("lastfm: unparseable %s answer", wrapper)}
	}
	inner, ok := raw[wrapper]
	if !ok {
		return lastfmHistoryPage{}, &Permanent{Err: fmt.Errorf("lastfm: no %s in the answer", wrapper)}
	}
	var envelope map[string]json.RawMessage
	if err := json.Unmarshal(inner, &envelope); err != nil {
		return lastfmHistoryPage{}, &Permanent{Err: fmt.Errorf("lastfm: unparseable %s answer", wrapper)}
	}
	var page lastfmHistoryPage
	if tracks, ok := envelope[list]; ok {
		// A page holding one row answers an object rather than an array,
		// which is this API's long-standing shape.
		if trimmed := bytes.TrimSpace(tracks); len(trimmed) > 0 && trimmed[0] == '{' {
			tracks = append(append([]byte("["), trimmed...), ']')
		}
		if err := json.Unmarshal(tracks, &page.Tracks); err != nil {
			return lastfmHistoryPage{}, &Permanent{Err: fmt.Errorf("lastfm: unparseable %s list", list)}
		}
	}
	// Read as raw and unquoted rather than as a string: this API has
	// shipped totalPages both ways, and a decode that insisted on one
	// of them leaves the count at zero, which the walk reads as "one
	// page" and reports as the whole history.
	var attr struct {
		TotalPages json.RawMessage `json:"totalPages"`
	}
	if a, ok := envelope["@attr"]; ok {
		_ = json.Unmarshal(a, &attr)
	}
	page.TotalPages, _ = strconv.Atoi(string(bytes.Trim(attr.TotalPages, `"`)))
	return page, nil
}

// history reads one page of a user list method and flattens it.
func (c *Lastfm) history(ctx context.Context, method, wrapper, list, user string, page, limit int, to int64) (HistoryPage, error) {
	params := map[string]string{
		"method":  method,
		"api_key": c.apiKey,
		"user":    user,
		"limit":   strconv.Itoa(limit),
		"page":    strconv.Itoa(page),
	}
	if to > 0 {
		params["to"] = strconv.FormatInt(to, 10)
	}
	body, err := c.call(ctx, params)
	if err != nil {
		return HistoryPage{}, err
	}
	decoded, err := decodeHistory(body, wrapper, list)
	if err != nil {
		return HistoryPage{}, err
	}
	rows := len(decoded.Tracks)
	out := make([]HistoryTrack, 0, rows)
	for _, t := range decoded.Tracks {
		if t.Attr.NowPlaying == "true" {
			// Not a scrobble: it has no time and has not finished.
			continue
		}
		at, _ := strconv.ParseInt(t.Date.UTS, 10, 64)
		artist := t.Artist.Text
		if artist == "" {
			artist = t.Artist.Name
		}
		out = append(out, HistoryTrack{
			Artist:     artist,
			ArtistMBID: t.Artist.MBID,
			Title:      t.Name,
			MBID:       t.MBID,
			Album:      t.Album.Text,
			At:         at,
		})
	}
	return HistoryPage{Tracks: out, Rows: rows, TotalPages: decoded.TotalPages}, nil
}

// HistoryPage is one page of a user list. Rows is what the service
// actually sent, which is not len(Tracks): a now-playing row carries no
// time and is dropped here. A walk needs the raw count to tell a last
// page from a full one when TotalPages did not arrive.
type HistoryPage struct {
	Tracks     []HistoryTrack
	Rows       int
	TotalPages int
}

// RecentTracks reads one page of a user's scrobble history, newest
// first, and reports how many pages there are.
//
// `to` pins the window's newer end at the run's start, because the
// history is being written while it is read: without it a scrobble
// arriving mid-walk shifts every later page by one and the import
// silently skips a track.
func (c *Lastfm) RecentTracks(ctx context.Context, user string, page, limit int, to int64) (HistoryPage, error) {
	return c.history(ctx, "user.getRecentTracks", "recenttracks", "track", user, page, limit, to)
}

// LovedTracks reads one page of a user's loved tracks, newest first.
func (c *Lastfm) LovedTracks(ctx context.Context, user string, page, limit int) (HistoryPage, error) {
	return c.history(ctx, "user.getLovedTracks", "lovedtracks", "track", user, page, limit, 0)
}

// lastfmMaxResponse bounds one answer. A scrobble acknowledgement is a
// few hundred bytes, but a page of two hundred recent tracks with their
// image sets rides the same call and is the largest thing this API
// produces.
const lastfmMaxResponse int64 = 8 << 20

// call signs and posts one API method, mapping the service's error
// codes onto the retry taxonomy: throttling and service trouble stay
// retryable, everything else is permanent.
func (c *Lastfm) call(ctx context.Context, params map[string]string) ([]byte, error) {
	form := url.Values{}
	for k, v := range params {
		form.Set(k, v)
	}
	form.Set("api_sig", c.sign(params))
	form.Set("format", "json")
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.BaseURL, strings.NewReader(form.Encode()))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, err := c.HTTP.Do(req)
	if err != nil {
		return nil, fmt.Errorf("lastfm: %w", err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, lastfmMaxResponse+1))
	if err != nil {
		return nil, fmt.Errorf("lastfm: reading response: %w", err)
	}
	if int64(len(body)) > lastfmMaxResponse {
		// Said rather than truncated: a short read reaches the decoder
		// as malformed JSON, and the import would then retire itself
		// blaming the shape of an answer that was fine.
		return nil, &Permanent{Err: fmt.Errorf("lastfm: the answer is larger than this client reads")}
	}
	var apiErr struct {
		Error   int    `json:"error"`
		Message string `json:"message"`
	}
	if json.Unmarshal(body, &apiErr) == nil && apiErr.Error != 0 {
		err := fmt.Errorf("lastfm: error %d: %s", apiErr.Error, apiErr.Message)
		switch apiErr.Error {
		// 11 service offline, 16 temporarily unavailable, 29 rate limit.
		case 11, 16, 29:
			return nil, err
		default:
			return nil, &Permanent{Err: err}
		}
	}
	if resp.StatusCode != http.StatusOK {
		err := fmt.Errorf("lastfm: status %d", resp.StatusCode)
		if resp.StatusCode >= 400 && resp.StatusCode < 500 && resp.StatusCode != http.StatusTooManyRequests {
			return nil, &Permanent{Err: err}
		}
		return nil, err
	}
	return body, nil
}

// sign computes the method signature: parameter names sorted, name and
// value concatenated, secret appended, md5 hex encoded.
func (c *Lastfm) sign(params map[string]string) string {
	keys := make([]string, 0, len(params))
	for k := range params {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	var b strings.Builder
	for _, k := range keys {
		b.WriteString(k)
		b.WriteString(params[k])
	}
	b.WriteString(c.secret)
	sum := md5.Sum([]byte(b.String()))
	return hex.EncodeToString(sum[:])
}
