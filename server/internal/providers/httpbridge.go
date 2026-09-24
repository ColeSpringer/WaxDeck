package providers

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log/slog"
	"mime"
	"net/http"
	"strings"
	"time"

	"github.com/colespringer/waxbin/art"
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
	// Log records the images an answer carried that were refused; nil
	// discards.
	Log *slog.Logger
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
	log  *slog.Logger
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
		log:  cfg.Log,
	}
	if b.log == nil {
		b.log = slog.New(slog.DiscardHandler)
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
		b.caps |= parseCapability(strings.ToLower(strings.TrimSpace(c)))
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
	Type             string   `json:"type"`
	Force            bool     `json:"force,omitempty"`
	Wants            []string `json:"wants,omitempty"`
	Title            string   `json:"title,omitempty"`
	Artist           string   `json:"artist,omitempty"`
	Album            string   `json:"album,omitempty"`
	MBID             string   `json:"mbid,omitempty"`
	ASIN             string   `json:"asin,omitempty"`
	ISBN             string   `json:"isbn,omitempty"`
	ISRC             string   `json:"isrc,omitempty"`
	Barcode          string   `json:"barcode,omitempty"`
	CatalogNumber    string   `json:"catalogNumber,omitempty"`
	ReleaseGroupMBID string   `json:"releaseGroupMbid,omitempty"`
	GroupFrontHash   string   `json:"groupFrontHash,omitempty"`
	DurationSec      int      `json:"durationSec,omitempty"`
}

// bridgeImage is one picture on the wire, its bytes base64 in `data`.
type bridgeImage struct {
	Data      string `json:"data"`
	MediaType string `json:"mediaType,omitempty"`
	SourceURL string `json:"sourceUrl,omitempty"`
}

// bridgeCandidate is the contract's answer, the port's Candidate
// spelled onto the wire.
type bridgeCandidate struct {
	Confidence        float64                 `json:"confidence,omitempty"`
	MBID              string                  `json:"mbid,omitempty"`
	ASIN              string                  `json:"asin,omitempty"`
	ISBN              string                  `json:"isbn,omitempty"`
	Type              string                  `json:"type,omitempty"`
	Genres            []string                `json:"genres,omitempty"`
	Cover             *bridgeImage            `json:"cover,omitempty"`
	Art               map[string]*bridgeImage `json:"art,omitempty"`
	FrontIsGroupFront bool                    `json:"frontIsGroupFront,omitempty"`
	Publisher         string                  `json:"publisher,omitempty"`
	Lyrics            *struct {
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
		Type: string(req.Type), Force: req.Force, Wants: CapabilityNames(req.Want),
		Title: req.Title, Artist: req.Artist, Album: req.Album,
		MBID: req.MBID, ASIN: req.ASIN, ISBN: req.ISBN,
		ISRC: req.ISRC, Barcode: req.Barcode, CatalogNumber: req.CatalogNumber,
		ReleaseGroupMBID: req.ReleaseGroupMBID, GroupFrontHash: req.GroupFrontHash,
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
		// Only where it was asked: elsewhere it would end the walk bare.
		FrontIsGroupFront: wire.FrontIsGroupFront && req.Type == enrich.TargetRelease && req.GroupFrontHash != "",
	}
	if len(wire.Fields) > 0 {
		cand.Fields = wire.Fields
	}
	cand.Cover = b.usableImage(wire.Cover, "cover")
	for role, img := range wire.Art {
		r := model.ArtRole(role)
		if !r.Valid() {
			continue
		}
		if pic := b.usableImage(img, role); pic != nil {
			if cand.Art == nil {
				cand.Art = map[model.ArtRole]*model.ArtImage{}
			}
			cand.Art[r] = pic
		}
	}
	// The artist-art walk reads the role map alone.
	if req.Type == enrich.TargetArtist && cand.Cover != nil && cand.Art[model.ArtRoleFront] == nil {
		if cand.Art == nil {
			cand.Art = map[model.ArtRole]*model.ArtImage{}
		}
		cand.Art[model.ArtRoleFront] = cand.Cover
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
		cand.Publisher == "" && len(cand.Genres) == 0 && cand.Cover == nil && len(cand.Art) == 0 &&
		!cand.FrontIsGroupFront && cand.Lyrics == nil && len(cand.Fields) == 0 {
		return nil, nil
	}
	return cand, nil
}

// usableImage is image with a refusal logged and dropped: one bad picture
// costs itself, not the rest of the answer.
func (b *HTTPBridge) usableImage(img *bridgeImage, role string) *model.ArtImage {
	pic, err := b.image(img)
	if err != nil {
		b.log.Warn("custom enrichment provider sent an unusable image; dropping it",
			"provider", b.name, "role", role, "err", err)
	}
	return pic
}

// image decodes one picture with the refusals fetchImage applies to a
// remote-chosen URL: too large, not an image, or SVG, which a browser runs
// rather than paints. Nil for an empty one.
func (b *HTTPBridge) image(img *bridgeImage) (*model.ArtImage, error) {
	if img == nil || img.Data == "" {
		return nil, nil
	}
	data, err := base64.StdEncoding.DecodeString(img.Data)
	if err != nil {
		return nil, fmt.Errorf("providers: decode %s image bytes: %w", b.name, err)
	}
	if int64(len(data)) > maxImageBytes {
		return nil, fmt.Errorf("providers: %s image exceeds %d bytes", b.name, maxImageBytes)
	}
	mt := strings.TrimSpace(img.MediaType)
	if parsed, _, err := mime.ParseMediaType(mt); err == nil {
		mt = parsed
	}
	mt = strings.ToLower(mt)
	if mt != "" && !strings.HasPrefix(mt, "image/") {
		return nil, fmt.Errorf("providers: %s image media type %q is not an image", b.name, mt)
	}
	if strings.HasSuffix(mt, "/svg+xml") || strings.HasSuffix(mt, "/svg") {
		return nil, fmt.Errorf("providers: %s image media type %q is markup", b.name, mt)
	}
	// The bytes decide, as the archive's own fetch does: SVG under any
	// label is text, and nothing here would serve what it cannot read.
	if art.Describe(data).Format == "" {
		return nil, fmt.Errorf("providers: %s image bytes are not a recognizable picture", b.name)
	}
	return coverImage(data, mt, img.SourceURL), nil
}
