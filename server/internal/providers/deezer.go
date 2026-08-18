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

// maxTitleCoverBytes bounds one cover fetched for an announced title.
// The shared image cap is 8 MiB, which is a lot to leave resident in a
// cache keyed by what a station chose to announce.
const maxTitleCoverBytes = 2 << 20

// FrontCover answers a cover for an announced artist and title, from the
// album the track belongs to. A track search rather than Enrich's album
// search, and both names matched: a wrong cover is worse than none.
func (d *Deezer) FrontCover(ctx context.Context, artist, title string) ([]byte, string, error) {
	if artist == "" || title == "" {
		return nil, "", ErrNoCover
	}
	q := url.Values{}
	q.Set("q", `artist:"`+artist+`" track:"`+title+`"`)
	body, status, err := d.core.get(ctx, d.base+"/search?"+q.Encode(), d.ttl)
	if err != nil {
		return nil, "", err
	}
	if status != http.StatusOK {
		return nil, "", fmt.Errorf("providers: deezer search: status %d", status)
	}
	var parsed struct {
		Data []struct {
			Title  string `json:"title"`
			Artist struct {
				Name string `json:"name"`
			} `json:"artist"`
			Album struct {
				CoverBig string `json:"cover_big"`
			} `json:"album"`
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &parsed); err != nil {
		return nil, "", fmt.Errorf("providers: decode deezer search: %w", err)
	}
	// A song is routinely listed several times over - a single, an album,
	// a deluxe edition - so one unusable cover is not the end of the walk.
	var reachErr error
	for _, hit := range parsed.Data {
		if hit.Album.CoverBig == "" ||
			!coverNameMatch(hit.Artist.Name, artist) ||
			!coverNameMatch(hit.Title, title) {
			continue
		}
		data, _, err := fetchImage(ctx, d.core, hit.Album.CoverBig)
		if err != nil {
			reachErr = err
			continue
		}
		// The type comes from the bytes, not the header - these are served
		// from WaxDeck's own origin - and both refusals are facts about
		// this picture, so neither counts as Deezer being unreachable.
		mime, ok := coverArtMimes[http.DetectContentType(data)]
		if !ok || len(data) > maxTitleCoverBytes {
			continue
		}
		return data, mime, nil
	}
	if reachErr != nil {
		return nil, "", reachErr
	}
	return nil, "", ErrNoCover
}

// ForgetMisses drops the track searches this rung cached, built as they
// are from strings a station announced. Enrichment's album searches go
// through the same client and are not the radio toggle's to clear.
func (d *Deezer) ForgetMisses() { d.core.forgetPrefix(d.base + "/search?") }
