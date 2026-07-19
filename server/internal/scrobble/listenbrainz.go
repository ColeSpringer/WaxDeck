package scrobble

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
)

// DefaultListenBrainzAPI is the public instance; connections may point
// at any compatible server (Maloja and friends).
const DefaultListenBrainzAPI = "https://api.listenbrainz.org"

// ListenBrainz speaks the ListenBrainz submission API. Tokens are per
// connection and supplied per call.
type ListenBrainz struct {
	HTTP *http.Client
}

// NewListenBrainz builds a client.
func NewListenBrainz() *ListenBrainz {
	return &ListenBrainz{HTTP: httpClient}
}

// ValidateToken checks a user token and returns the account's username.
func (c *ListenBrainz) ValidateToken(ctx context.Context, apiURL, token string) (string, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, baseURL(apiURL)+"/1/validate-token", nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("Authorization", "Token "+token)
	resp, err := c.HTTP.Do(req)
	if err != nil {
		return "", fmt.Errorf("listenbrainz: %w", err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return "", fmt.Errorf("listenbrainz: reading response: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		return "", statusError(resp.StatusCode)
	}
	var out struct {
		Valid    bool   `json:"valid"`
		UserName string `json:"user_name"`
	}
	if err := json.Unmarshal(body, &out); err != nil {
		return "", fmt.Errorf("listenbrainz: unexpected response")
	}
	if !out.Valid {
		return "", &Permanent{Err: fmt.Errorf("listenbrainz: token is not valid")}
	}
	return out.UserName, nil
}

// Submit delivers one listen (ListenedAt set) or a playing-now update
// (ListenedAt zero).
func (c *ListenBrainz) Submit(ctx context.Context, apiURL, token string, t Track) error {
	meta := map[string]any{
		"artist_name": t.Artist,
		"track_name":  t.Title,
	}
	if t.Album != "" {
		meta["release_name"] = t.Album
	}
	info := map[string]any{
		"media_player":      "WaxDeck",
		"submission_client": "WaxDeck",
	}
	if t.DurationMS > 0 {
		info["duration_ms"] = t.DurationMS
	}
	meta["additional_info"] = info
	entry := map[string]any{"track_metadata": meta}
	listenType := "playing_now"
	if t.ListenedAt > 0 {
		listenType = "single"
		entry["listened_at"] = t.ListenedAt
	}
	payload := map[string]any{
		"listen_type": listenType,
		"payload":     []any{entry},
	}
	raw, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, baseURL(apiURL)+"/1/submit-listens", bytes.NewReader(raw))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Token "+token)
	req.Header.Set("Content-Type", "application/json")
	resp, err := c.HTTP.Do(req)
	if err != nil {
		return fmt.Errorf("listenbrainz: %w", err)
	}
	defer resp.Body.Close()
	io.Copy(io.Discard, io.LimitReader(resp.Body, 1<<16))
	if resp.StatusCode != http.StatusOK {
		return statusError(resp.StatusCode)
	}
	return nil
}

// statusError maps an HTTP status onto the retry taxonomy.
func statusError(code int) error {
	err := fmt.Errorf("listenbrainz: status %d", code)
	if code >= 400 && code < 500 && code != http.StatusTooManyRequests {
		return &Permanent{Err: err}
	}
	return err
}

// baseURL normalizes a connection's API base; empty selects the public
// instance.
func baseURL(apiURL string) string {
	if apiURL == "" {
		return DefaultListenBrainzAPI
	}
	return strings.TrimRight(apiURL, "/")
}
