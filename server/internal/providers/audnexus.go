package providers

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/colespringer/waxbin/enrich"
	"github.com/colespringer/waxbin/model"
)

// AudnexusConfig configures the Audnexus audiobook provider. Zero values
// take the documented defaults.
type AudnexusConfig struct {
	// BaseURL defaults to "https://api.audnex.us" (key-free API).
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

// Audnexus supplies audiobook metadata and cover art keyed on ASIN.
type Audnexus struct {
	base string
	ttl  time.Duration
	core *core
}

// NewAudnexus builds a provider from cfg, applying defaults for zero
// fields.
func NewAudnexus(cfg AudnexusConfig) *Audnexus {
	base := cfg.BaseURL
	if base == "" {
		base = "https://api.audnex.us"
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
	return &Audnexus{
		base: strings.TrimRight(base, "/"),
		ttl:  ttl,
		core: newCore(cfg.HTTPClient, ua, interval),
	}
}

// Name is the stable provenance id.
func (a *Audnexus) Name() string { return "audnexus" }

// Capabilities reports audiobook metadata and cover art.
func (a *Audnexus) Capabilities() enrich.Capability {
	return enrich.CapBookMeta | enrich.CapCover
}

// Enrich answers a book lookup by ASIN: narrators, publisher, release
// year, a tag-stripped description, genre names, and the cover image.
// Requests without an ASIN are clean misses.
func (a *Audnexus) Enrich(ctx context.Context, req enrich.Request) (*enrich.Candidate, error) {
	if req.Type != enrich.TargetBook || req.ASIN == "" {
		return nil, nil
	}
	u := a.base + "/books/" + url.PathEscape(req.ASIN)
	body, status, err := a.core.get(ctx, u, a.ttl)
	if err != nil {
		return nil, err
	}
	switch status {
	case http.StatusOK:
	case http.StatusNotFound:
		return nil, nil
	default:
		return nil, fmt.Errorf("providers: audnexus book %s: status %d", req.ASIN, status)
	}
	var book struct {
		Narrators []struct {
			Name string `json:"name"`
		} `json:"narrators"`
		PublisherName string `json:"publisherName"`
		ReleaseDate   string `json:"releaseDate"`
		Summary       string `json:"summary"`
		Genres        []struct {
			Name string `json:"name"`
			Type string `json:"type"`
		} `json:"genres"`
		Image string `json:"image"`
	}
	if err := json.Unmarshal(body, &book); err != nil {
		return nil, fmt.Errorf("providers: decode audnexus book %s: %w", req.ASIN, err)
	}
	cand := &enrich.Candidate{
		Confidence: 0.9,
		Publisher:  book.PublisherName,
		Fields:     map[string]string{},
	}
	var narrators []string
	for _, n := range book.Narrators {
		if n.Name != "" {
			narrators = append(narrators, n.Name)
		}
	}
	if len(narrators) > 0 {
		cand.Fields["narrator"] = strings.Join(narrators, ", ")
	}
	if book.PublisherName != "" {
		cand.Fields["publisher"] = book.PublisherName
	}
	if y := yearString(book.ReleaseDate); y != "" {
		cand.Fields["year"] = y
	}
	if desc := stripHTML(book.Summary); desc != "" {
		cand.Fields["description"] = desc
	}
	for _, g := range book.Genres {
		if g.Type == "genre" && g.Name != "" {
			cand.Genres = append(cand.Genres, g.Name)
		}
	}
	if book.Image != "" {
		data, mediaType, err := fetchImage(ctx, a.core, book.Image)
		if err != nil {
			return nil, err
		}
		cand.Cover = &model.ArtImage{Data: data, Format: imageFormat(mediaType)}
	}
	if len(cand.Fields) == 0 {
		cand.Fields = nil
	}
	return cand, nil
}

// htmlTagRE matches markup tags in a summary; entities are left alone.
var htmlTagRE = regexp.MustCompile(`<[^>]*>`)

// stripHTML drops markup tags and collapses whitespace, leaving plain
// prose for the description field.
func stripHTML(s string) string {
	return collapseSpace(htmlTagRE.ReplaceAllString(s, " "))
}

// yearString extracts the leading four-digit year of a release date
// ("2014-06-17T00:00:00.000Z"); empty when absent or malformed.
func yearString(d string) string {
	if len(d) < 4 {
		return ""
	}
	if y, err := strconv.Atoi(d[:4]); err != nil || y <= 0 {
		return ""
	}
	return d[:4]
}
