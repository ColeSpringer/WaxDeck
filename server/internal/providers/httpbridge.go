package providers

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/colespringer/waxbin/enrich"
	"github.com/colespringer/waxbin/model"
)

// The HTTP bridge to a custom enrichment provider: a self-hosted
// service implementing the two-endpoint contract published in
// docs/custom-provider-api/ (a capabilities read and one enrich call,
// mirroring the in-process port). Built on the same core as every other
// client here, so pacing, caching, response caps, and the identifying
// User-Agent come for free.

// HTTPBridgeConfig configures one bridged provider. Zero values take
// the documented defaults.
type HTTPBridgeConfig struct {
	// Label is the operator's configured name for this provider, used
	// only in wiring errors; the provenance name is what the remote
	// advertises.
	Label string
	// BaseURL is the remote's base; required.
	BaseURL string
	// Token, when set, rides every request as a bearer Authorization
	// header.
	Token string
	// UserAgent defaults to the WaxDeck identifying string.
	UserAgent string
	// HTTPClient defaults to a 15s-timeout client.
	HTTPClient *http.Client
	// MinInterval defaults to 500ms. Self-hosted remotes tolerate more,
	// but the bridge cannot know what the remote itself calls out to.
	MinInterval time.Duration
}

// HTTPBridge implements enrich.Provider over the published contract.
// Enrich responses are deliberately uncached: an answer can carry a
// whole cover inline, so caching bodies would hold megabytes resident
// per entry, and the remote is expected to keep its own cache (which
// Force asks it to bypass).
type HTTPBridge struct {
	base string
	name string
	caps enrich.Capability
	core *core
}

// bridgeCapabilities maps the contract's capability tokens onto the
// port's bitset. Unknown tokens are ignored rather than refused, so a
// remote built against a newer contract still serves what this build
// understands.
var bridgeCapabilities = map[string]enrich.Capability{
	"identity":   enrich.CapIdentity,
	"genres":     enrich.CapGenres,
	"cover":      enrich.CapCover,
	"lyrics":     enrich.CapLyrics,
	"book":       enrich.CapBookMeta,
	"aux-art":    enrich.CapAuxArt,
	"artist-art": enrich.CapArtistArt,
}

const (
	// bridgeProbeAttempts and bridgeProbeTimeout bound the startup
	// capabilities read. Retried because compose starts the provider
	// container and this server together, and losing that race must not
	// crash-loop the whole server before the sidecar's first breath; a
	// remote still unreachable after the retries is a configuration
	// error, not a race.
	bridgeProbeAttempts = 5
	bridgeProbeTimeout  = 5 * time.Second
)

// NewHTTPBridge builds a bridge and validates the remote at startup:
// the capabilities document is fetched (with a short retry ladder for
// boot races), and a remote that cannot be reached or advertises no
// name is a configuration error - the alternative is a silently absent
// provider the operator explicitly wired. A remote advertising only
// capabilities this build does not understand constructs fine with an
// empty set; the caller decides whether registering it is worth it.
func NewHTTPBridge(ctx context.Context, cfg HTTPBridgeConfig) (*HTTPBridge, error) {
	if cfg.BaseURL == "" {
		return nil, fmt.Errorf("providers: enrich provider %q has no url", cfg.Label)
	}
	ua := cfg.UserAgent
	if ua == "" {
		ua = defaultUserAgent
	}
	interval := cfg.MinInterval
	if interval == 0 {
		interval = defaultEnrichInterval
	}
	b := &HTTPBridge{
		base: strings.TrimRight(cfg.BaseURL, "/"),
		core: newCore(cfg.HTTPClient, ua, interval),
	}
	if cfg.Token != "" {
		b.core.authorization = "Bearer " + cfg.Token
	}
	var body []byte
	var status int
	var err error
	for attempt := range bridgeProbeAttempts {
		if attempt > 0 {
			backoff := time.Duration(1<<(attempt-1)) * time.Second
			select {
			case <-ctx.Done():
				return nil, ctx.Err()
			case <-time.After(backoff):
			}
		}
		probeCtx, cancel := context.WithTimeout(ctx, bridgeProbeTimeout)
		body, status, err = b.core.get(probeCtx, b.base+"/capabilities", 0)
		cancel()
		if err == nil {
			break
		}
	}
	if err != nil {
		return nil, fmt.Errorf("providers: enrich provider %q: reading capabilities: %w", cfg.Label, err)
	}
	if status != http.StatusOK {
		return nil, fmt.Errorf("providers: enrich provider %q: capabilities: status %d", cfg.Label, status)
	}
	var caps struct {
		Name         string   `json:"name"`
		Capabilities []string `json:"capabilities"`
	}
	if err := json.Unmarshal(body, &caps); err != nil {
		return nil, fmt.Errorf("providers: enrich provider %q: decode capabilities: %w", cfg.Label, err)
	}
	if strings.TrimSpace(caps.Name) == "" {
		return nil, fmt.Errorf("providers: enrich provider %q advertises no name; the name is the provenance mark its values are stored under", cfg.Label)
	}
	for _, c := range caps.Capabilities {
		b.caps |= bridgeCapabilities[strings.ToLower(strings.TrimSpace(c))]
	}
	b.name = strings.TrimSpace(caps.Name)
	return b, nil
}

// Name is the remote's advertised provenance id.
func (b *HTTPBridge) Name() string { return b.name }

// Capabilities reports what the remote advertised at startup.
func (b *HTTPBridge) Capabilities() enrich.Capability { return b.caps }

// bridgeRequest is the contract's enrich body, the port's Request
// spelled onto the wire.
type bridgeRequest struct {
	Type        string `json:"type"`
	Force       bool   `json:"force,omitempty"`
	Title       string `json:"title,omitempty"`
	Artist      string `json:"artist,omitempty"`
	Album       string `json:"album,omitempty"`
	MBID        string `json:"mbid,omitempty"`
	ASIN        string `json:"asin,omitempty"`
	ISBN        string `json:"isbn,omitempty"`
	DurationSec int    `json:"durationSec,omitempty"`
}

// bridgeCandidate is the contract's answer, the port's Candidate
// spelled onto the wire. The cover's bytes ride base64 in `data`.
type bridgeCandidate struct {
	Confidence float64  `json:"confidence,omitempty"`
	MBID       string   `json:"mbid,omitempty"`
	ASIN       string   `json:"asin,omitempty"`
	ISBN       string   `json:"isbn,omitempty"`
	Type       string   `json:"type,omitempty"`
	Genres     []string `json:"genres,omitempty"`
	Cover      *struct {
		Data      string `json:"data"`
		MediaType string `json:"mediaType,omitempty"`
		SourceURL string `json:"sourceUrl,omitempty"`
	} `json:"cover,omitempty"`
	Publisher string `json:"publisher,omitempty"`
	Lyrics    *struct {
		Synced []struct {
			TimeMs int64  `json:"timeMs"`
			Text   string `json:"text"`
		} `json:"synced,omitempty"`
		Unsynced string `json:"unsynced,omitempty"`
	} `json:"lyrics,omitempty"`
	Fields map[string]string `json:"fields,omitempty"`
}

// Enrich answers one lookup over the wire. A 204 (or 404) is the clean
// no-match; a 200 carries the candidate.
func (b *HTTPBridge) Enrich(ctx context.Context, req enrich.Request) (*enrich.Candidate, error) {
	payload, err := json.Marshal(bridgeRequest{
		Type: string(req.Type), Force: req.Force,
		Title: req.Title, Artist: req.Artist, Album: req.Album,
		MBID: req.MBID, ASIN: req.ASIN, ISBN: req.ISBN,
		DurationSec: req.DurationSec,
	})
	if err != nil {
		return nil, fmt.Errorf("providers: encode bridge request: %w", err)
	}
	// Uncached (ttl 0): see the type comment. Force still rides the
	// body, asking the remote past its own cache.
	body, status, err := b.core.postJSON(ctx, b.base+"/enrich", payload, 0)
	if err != nil {
		return nil, err
	}
	switch status {
	case http.StatusOK:
	case http.StatusNoContent, http.StatusNotFound:
		return nil, nil
	default:
		return nil, fmt.Errorf("providers: %s enrich: status %d", b.name, status)
	}
	var wire bridgeCandidate
	if err := json.Unmarshal(body, &wire); err != nil {
		return nil, fmt.Errorf("providers: decode %s enrich: %w", b.name, err)
	}
	cand := &enrich.Candidate{
		Confidence: wire.Confidence,
		MBID:       wire.MBID,
		ASIN:       wire.ASIN,
		ISBN:       wire.ISBN,
		Type:       wire.Type,
		Genres:     wire.Genres,
		Publisher:  wire.Publisher,
	}
	if len(wire.Fields) > 0 {
		cand.Fields = wire.Fields
	}
	if wire.Cover != nil && wire.Cover.Data != "" {
		data, err := base64.StdEncoding.DecodeString(wire.Cover.Data)
		if err != nil {
			return nil, fmt.Errorf("providers: decode %s cover bytes: %w", b.name, err)
		}
		if int64(len(data)) > maxImageBytes {
			return nil, fmt.Errorf("providers: %s cover exceeds %d bytes", b.name, maxImageBytes)
		}
		// The same refusals fetchImage applies to a remote-chosen image
		// URL: a declared type that is not a picture, and SVG in
		// particular, which a browser runs rather than paints and which
		// would otherwise ride the declared type into the store when the
		// bytes neither decode nor sniff.
		mt := strings.ToLower(strings.TrimSpace(wire.Cover.MediaType))
		if mt != "" && !strings.HasPrefix(mt, "image/") {
			return nil, fmt.Errorf("providers: %s cover media type %q is not an image", b.name, mt)
		}
		if strings.HasSuffix(mt, "/svg+xml") || strings.HasSuffix(mt, "/svg") {
			return nil, fmt.Errorf("providers: %s cover media type %q is markup", b.name, mt)
		}
		cand.Cover = coverImage(data, wire.Cover.MediaType, wire.Cover.SourceURL)
	}
	if wire.Lyrics != nil {
		lyr := &model.Lyrics{Unsynced: wire.Lyrics.Unsynced}
		for _, line := range wire.Lyrics.Synced {
			lyr.Synced = append(lyr.Synced, model.SyncedLine{TimeMS: line.TimeMs, Text: line.Text})
		}
		if lyr.HasContent() {
			cand.Lyrics = lyr
		}
	}
	// A remote may legitimately answer 200 with an empty object; handing
	// that to the enrichment loops as a non-nil candidate would end a
	// want ("nothing new to fill") that a later provider could still
	// answer. Empty is a clean no-match.
	if cand.MBID == "" && cand.ASIN == "" && cand.ISBN == "" && cand.Type == "" &&
		cand.Publisher == "" && len(cand.Genres) == 0 && cand.Cover == nil &&
		cand.Lyrics == nil && len(cand.Fields) == 0 {
		return nil, nil
	}
	return cand, nil
}
