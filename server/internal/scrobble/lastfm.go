package scrobble

import (
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
	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return nil, fmt.Errorf("lastfm: reading response: %w", err)
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
