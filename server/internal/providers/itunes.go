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

// ITunesConfig configures the iTunes cover provider. Zero values take
// the documented defaults.
type ITunesConfig struct {
	// BaseURL defaults to "https://itunes.apple.com" (key-free API).
	BaseURL string
	// UserAgent defaults to the WaxDeck identifying string.
	UserAgent string
	// HTTPClient defaults to a 15s-timeout client.
	HTTPClient *http.Client
	// MinInterval defaults to 500ms.
	MinInterval time.Duration
	// CacheTTL defaults to 24h.
	CacheTTL time.Duration
}

// ITunes supplies release-group cover art from the iTunes search API,
// upgrading the thumbnail artwork URL to a high-resolution variant.
type ITunes struct {
	base string
	ttl  time.Duration
	core *core
}

// NewITunes builds a provider from cfg, applying defaults for zero
// fields.
func NewITunes(cfg ITunesConfig) *ITunes {
	base := cfg.BaseURL
	if base == "" {
		base = "https://itunes.apple.com"
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
	return &ITunes{
		base: strings.TrimRight(base, "/"),
		ttl:  ttl,
		core: newCore(cfg.HTTPClient, ua, interval),
	}
}

// Name is the stable provenance id.
func (t *ITunes) Name() string { return "itunes" }

// Capabilities reports cover art only.
func (t *ITunes) Capabilities() enrich.Capability { return enrich.CapCover }

// Enrich answers a release-group cover lookup: search iTunes albums by
// artist and title, take the first hit whose names match, and fetch the
// artwork with its size token upgraded from 100x100 to 1200x1200.
func (t *ITunes) Enrich(ctx context.Context, req enrich.Request) (*enrich.Candidate, error) {
	if req.Type != enrich.TargetReleaseGroup || req.Title == "" {
		return nil, nil
	}
	q := url.Values{}
	q.Set("term", strings.TrimSpace(req.Artist+" "+req.Title))
	q.Set("entity", "album")
	q.Set("limit", "5")
	u := t.base + "/search?" + q.Encode()
	body, status, err := t.core.get(ctx, u, t.ttl)
	if err != nil {
		return nil, err
	}
	if status != http.StatusOK {
		return nil, fmt.Errorf("providers: itunes search: status %d", status)
	}
	var parsed struct {
		Results []struct {
			CollectionName string `json:"collectionName"`
			ArtistName     string `json:"artistName"`
			ArtworkURL100  string `json:"artworkUrl100"`
		} `json:"results"`
	}
	if err := json.Unmarshal(body, &parsed); err != nil {
		return nil, fmt.Errorf("providers: decode itunes search: %w", err)
	}
	for _, hit := range parsed.Results {
		if hit.ArtworkURL100 == "" || !nameMatch(hit.CollectionName, req.Title) {
			continue
		}
		if req.Artist != "" && !nameMatch(hit.ArtistName, req.Artist) {
			continue
		}
		artURL := strings.Replace(hit.ArtworkURL100, "100x100", "1200x1200", 1)
		data, mediaType, err := fetchImage(ctx, t.core, artURL)
		if err != nil {
			return nil, err
		}
		return &enrich.Candidate{
			Confidence: 0.6,
			Cover:      coverImage(data, mediaType, artURL),
		}, nil
	}
	return nil, nil
}
