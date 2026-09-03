package providers

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"time"

	"github.com/colespringer/waxbin/enrich"
)

// DiscogsConfig configures the Discogs cover and genre provider. Zero
// values take the documented defaults.
type DiscogsConfig struct {
	// BaseURL defaults to "https://api.discogs.com".
	BaseURL string
	// Token is a personal access token, required for use; when empty,
	// Enrich always returns a clean miss without a network call.
	Token string
	// UserAgent defaults to the WaxDeck identifying string.
	UserAgent string
	// HTTPClient defaults to a 15s-timeout client.
	HTTPClient *http.Client
	// MinInterval defaults to 1100ms: Discogs allows 60 requests a
	// minute per token, and a search that hits fetches an image through
	// the same host budget.
	MinInterval time.Duration
	// CacheTTL defaults to 24h.
	CacheTTL time.Duration
}

// Discogs supplies release-group cover art and genres from the Discogs
// database search.
type Discogs struct {
	base  string
	token string
	ttl   time.Duration
	core  *core
}

// NewDiscogs builds a provider from cfg, applying defaults for zero
// fields.
func NewDiscogs(cfg DiscogsConfig) *Discogs {
	base := cfg.BaseURL
	if base == "" {
		base = "https://api.discogs.com"
	}
	ua := cfg.UserAgent
	if ua == "" {
		ua = defaultUserAgent
	}
	interval := cfg.MinInterval
	if interval == 0 {
		interval = 1100 * time.Millisecond
	}
	ttl := cfg.CacheTTL
	if ttl == 0 {
		ttl = defaultEnrichTTL
	}
	d := &Discogs{
		base:  strings.TrimRight(base, "/"),
		token: cfg.Token,
		ttl:   ttl,
		core:  newCore(cfg.HTTPClient, ua, interval),
	}
	// The header, not a query parameter: a token in the URL rides into
	// every wrapped transport error and from there into the server log.
	if cfg.Token != "" {
		d.core.authorization = "Discogs token=" + cfg.Token
	}
	return d
}

// Name is the stable provenance id.
func (d *Discogs) Name() string { return "discogs" }

// Capabilities reports cover art and genres.
func (d *Discogs) Capabilities() enrich.Capability {
	return enrich.CapCover | enrich.CapGenres
}

// Enrich answers a release-group lookup: search Discogs masters by
// artist and title, take the first hit whose names match, and return
// its genres and styles as one provider-ordered list plus its primary
// image. Requests without a token or a title are clean misses.
//
// The work is restricted to what the request says the pass will read: a
// genres ask skips the image download entirely, which on a genre-less
// library is one saved cover-sized fetch per item. A zero Want means
// everything, which is the whole-library pass's shape.
func (d *Discogs) Enrich(ctx context.Context, req enrich.Request) (*enrich.Candidate, error) {
	if d.token == "" {
		return nil, nil
	}
	if req.Type != enrich.TargetReleaseGroup || req.Title == "" {
		return nil, nil
	}
	q := url.Values{}
	q.Set("type", "master")
	q.Set("release_title", req.Title)
	if req.Artist != "" {
		q.Set("artist", req.Artist)
	}
	body, status, err := d.core.get(ctx, d.base+"/database/search?"+q.Encode(), d.ttl)
	if err != nil {
		return nil, err
	}
	if status != http.StatusOK {
		return nil, fmt.Errorf("providers: discogs search: status %d", status)
	}
	var parsed struct {
		Results []struct {
			// Title is "Artist - Title" on master results; the halves
			// are matched separately below.
			Title      string   `json:"title"`
			CoverImage string   `json:"cover_image"`
			Genre      []string `json:"genre"`
			Style      []string `json:"style"`
		} `json:"results"`
	}
	if err := json.Unmarshal(body, &parsed); err != nil {
		return nil, fmt.Errorf("providers: decode discogs search: %w", err)
	}
	for _, hit := range parsed.Results {
		artist, title, ok := strings.Cut(hit.Title, " - ")
		if !ok || !nameMatch(title, req.Title) {
			continue
		}
		if req.Artist != "" && !nameMatch(discogsBaseName(artist), req.Artist) {
			continue
		}
		cand := &enrich.Candidate{Confidence: 0.7}
		// Genres first, styles after: Discogs's genre is the broad bucket
		// ("Electronic") and style the one worth reading ("House"), but
		// the broad one is what the vocabulary tree folds reliably.
		if req.Wants(enrich.CapGenres) {
			cand.Genres = append(cand.Genres, hit.Genre...)
			cand.Genres = append(cand.Genres, hit.Style...)
		}
		// Spacer images stand in where a master has no photo; skip the
		// fetch rather than store a placeholder as somebody's cover.
		if req.Wants(enrich.CapCover) && hit.CoverImage != "" && !strings.Contains(hit.CoverImage, "spacer.gif") {
			data, mediaType, err := fetchImage(ctx, d.core, hit.CoverImage)
			switch {
			case err == nil:
				cand.Cover = coverImage(data, mediaType, hit.CoverImage)
			case len(cand.Genres) > 0:
				// An unreachable or hotlink-refused image is not the
				// matched genres' problem; the cover want just gets
				// nothing from this provider.
			default:
				return nil, err
			}
		}
		if len(cand.Genres) == 0 && cand.Cover == nil {
			return nil, nil
		}
		return cand, nil
	}
	return nil, nil
}

// discogsDisambiguator is the numeric suffix Discogs appends to
// distinguish same-named artists ("Nirvana (2)").
var discogsDisambiguator = regexp.MustCompile(`\s\(\d+\)$`)

// discogsBaseName strips the disambiguator so the name gate compares
// what the artist is actually called.
func discogsBaseName(artist string) string {
	return discogsDisambiguator.ReplaceAllString(artist, "")
}
