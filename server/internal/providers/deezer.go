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
	"github.com/colespringer/waxbin/model"
)

// DeezerConfig configures the Deezer cover provider. Zero values take
// the documented defaults.
type DeezerConfig struct {
	// BaseURL defaults to "https://api.deezer.com" (key-free API).
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

// Deezer supplies release-group cover art from the Deezer album search.
type Deezer struct {
	base string
	ttl  time.Duration
	core *core
}

// NewDeezer builds a provider from cfg, applying defaults for zero
// fields.
func NewDeezer(cfg DeezerConfig) *Deezer {
	base := cfg.BaseURL
	if base == "" {
		base = "https://api.deezer.com"
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
	return &Deezer{
		base: strings.TrimRight(base, "/"),
		ttl:  ttl,
		core: newCore(cfg.HTTPClient, ua, interval),
	}
}

// Name is the stable provenance id.
func (d *Deezer) Name() string { return "deezer" }

// Capabilities reports cover art only.
func (d *Deezer) Capabilities() enrich.Capability { return enrich.CapCover }

// Enrich answers a release-group cover lookup: search Deezer albums by
// artist and title, take the first hit whose names match, and fetch its
// extra-large cover.
func (d *Deezer) Enrich(ctx context.Context, req enrich.Request) (*enrich.Candidate, error) {
	if req.Type != enrich.TargetReleaseGroup || req.Title == "" {
		return nil, nil
	}
	query := `album:"` + req.Title + `"`
	if req.Artist != "" {
		query = `artist:"` + req.Artist + `" ` + query
	}
	q := url.Values{}
	q.Set("q", query)
	u := d.base + "/search/album?" + q.Encode()
	body, status, err := d.core.get(ctx, u, d.ttl)
	if err != nil {
		return nil, err
	}
	if status != http.StatusOK {
		return nil, fmt.Errorf("providers: deezer search: status %d", status)
	}
	var parsed struct {
		Data []struct {
			Title   string `json:"title"`
			CoverXL string `json:"cover_xl"`
			Artist  struct {
				Name string `json:"name"`
			} `json:"artist"`
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &parsed); err != nil {
		return nil, fmt.Errorf("providers: decode deezer search: %w", err)
	}
	for _, hit := range parsed.Data {
		if hit.CoverXL == "" || !nameMatch(hit.Title, req.Title) {
			continue
		}
		if req.Artist != "" && !nameMatch(hit.Artist.Name, req.Artist) {
			continue
		}
		data, mediaType, err := fetchImage(ctx, d.core, hit.CoverXL)
		if err != nil {
			return nil, err
		}
		return &enrich.Candidate{
			Confidence: 0.7,
			Cover:      &model.ArtImage{Data: data, Format: imageFormat(mediaType)},
		}, nil
	}
	return nil, nil
}
