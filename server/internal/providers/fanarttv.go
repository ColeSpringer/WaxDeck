package providers

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/colespringer/waxbin/enrich"
)

// FanartTVConfig configures the fanart.tv cover provider. Zero values
// take the documented defaults.
type FanartTVConfig struct {
	// BaseURL defaults to "https://webservice.fanart.tv".
	BaseURL string
	// APIKey is required for use; when empty, Enrich always returns a
	// clean miss without a network call.
	APIKey string
	// UserAgent defaults to the WaxDeck identifying string.
	UserAgent string
	// HTTPClient defaults to a 15s-timeout client.
	HTTPClient *http.Client
	// MinInterval defaults to 500ms.
	MinInterval time.Duration
	// CacheTTL defaults to 24h.
	CacheTTL time.Duration
}

// FanartTV supplies release-group cover art keyed on the MusicBrainz
// release group id.
type FanartTV struct {
	base   string
	apiKey string
	ttl    time.Duration
	core   *core
}

// NewFanartTV builds a provider from cfg, applying defaults for zero
// fields.
func NewFanartTV(cfg FanartTVConfig) *FanartTV {
	base := cfg.BaseURL
	if base == "" {
		base = "https://webservice.fanart.tv"
	}
	ua := cfg.UserAgent
	if ua == "" {
		ua = defaultUserAgent
	}
	interval := cfg.MinInterval
	if interval == 0 {
		interval = defaultEnrichInterval
	}
	ttl := cfg.CacheTTL
	if ttl == 0 {
		ttl = defaultEnrichTTL
	}
	return &FanartTV{
		base:   strings.TrimRight(base, "/"),
		apiKey: cfg.APIKey,
		ttl:    ttl,
		core:   newCore(cfg.HTTPClient, ua, interval),
	}
}

// Name is the stable provenance id.
func (f *FanartTV) Name() string { return "fanarttv" }

// Capabilities reports cover art only.
func (f *FanartTV) Capabilities() enrich.Capability { return enrich.CapCover }

// Enrich answers a release-group cover lookup by MusicBrainz release
// group id; requests without an MBID (or without an API key) are clean
// misses.
func (f *FanartTV) Enrich(ctx context.Context, req enrich.Request) (*enrich.Candidate, error) {
	if f.apiKey == "" {
		return nil, nil
	}
	if req.Type != enrich.TargetReleaseGroup || req.MBID == "" {
		return nil, nil
	}
	q := url.Values{}
	q.Set("api_key", f.apiKey)
	u := f.base + "/v3/music/albums/" + url.PathEscape(req.MBID) + "?" + q.Encode()
	body, status, err := f.core.get(ctx, u, f.ttl)
	if err != nil {
		return nil, err
	}
	switch status {
	case http.StatusOK:
	case http.StatusNotFound:
		return nil, nil
	default:
		return nil, fmt.Errorf("providers: fanarttv albums: status %d", status)
	}
	var parsed struct {
		Albums map[string]struct {
			AlbumCover []struct {
				URL string `json:"url"`
			} `json:"albumcover"`
		} `json:"albums"`
	}
	if err := json.Unmarshal(body, &parsed); err != nil {
		return nil, fmt.Errorf("providers: decode fanarttv albums: %w", err)
	}
	album, ok := parsed.Albums[req.MBID]
	if !ok || len(album.AlbumCover) == 0 || album.AlbumCover[0].URL == "" {
		return nil, nil
	}
	data, mediaType, err := fetchImage(ctx, f.core, album.AlbumCover[0].URL)
	if err != nil {
		return nil, err
	}
	return &enrich.Candidate{
		Confidence: 0.8,
		Cover:      coverImage(data, mediaType, album.AlbumCover[0].URL),
	}, nil
}
