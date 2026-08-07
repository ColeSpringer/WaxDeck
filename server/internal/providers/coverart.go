package providers

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// CoverArtConfig configures the Cover Art Archive client. Zero values
// take the documented defaults.
type CoverArtConfig struct {
	// BaseURL defaults to "https://coverartarchive.org".
	BaseURL string
	// UserAgent is required by MusicBrainz etiquette (the archive is
	// theirs); defaults to the WaxDeck identifying string.
	UserAgent string
	// HTTPClient defaults to a 15s-timeout client.
	HTTPClient *http.Client
	// MinInterval defaults to 1100ms, the same one-per-second pacing the
	// MusicBrainz client keeps.
	MinInterval time.Duration
	// MaxBytes bounds one downloaded image; defaults to 2 MiB.
	MaxBytes int64
}

// CoverArt fetches release front covers from the Cover Art Archive.
//
// Its own client rather than a method on MusicBrainz, because it is a
// different host serving image bytes rather than JSON - but the same
// etiquette, and deliberately the same shape: an identifying agent and
// a one-per-second floor. Radio's now-playing lookup composes the two.
type CoverArt struct {
	base     string
	maxBytes int64
	client   *http.Client
	agent    string
	core     *core
}

// NewCoverArt builds a client from cfg, applying defaults for zero
// fields.
func NewCoverArt(cfg CoverArtConfig) *CoverArt {
	base := cfg.BaseURL
	if base == "" {
		base = "https://coverartarchive.org"
	}
	ua := cfg.UserAgent
	if ua == "" {
		ua = defaultUserAgent
	}
	interval := cfg.MinInterval
	if interval == 0 {
		interval = 1100 * time.Millisecond
	}
	maxBytes := cfg.MaxBytes
	if maxBytes == 0 {
		maxBytes = 2 << 20
	}
	client := cfg.HTTPClient
	if client == nil {
		client = &http.Client{Timeout: defaultTimeout}
	}
	return &CoverArt{
		base:     strings.TrimRight(base, "/"),
		maxBytes: maxBytes,
		client:   client,
		agent:    ua,
		core:     newCore(client, ua, interval),
	}
}

// ErrNoCover reports that the archive answered and holds no front cover
// for the release. A distinct error because the caller caches "answered,
// nothing there" for far longer than "could not ask".
var ErrNoCover = errors.New("providers: no front cover for this release")

// FrontCover downloads a release's front cover, at the archive's 500px
// rendition rather than the original: this ends up behind a station
// face, and an original scan can be a 20 MB TIFF.
//
// The 404 case is ErrNoCover, which is the ordinary answer - most
// releases have no art - and is what lets the caller tell an empty
// archive from an unreachable one.
func (c *CoverArt) FrontCover(ctx context.Context, releaseMBID string) ([]byte, string, error) {
	if releaseMBID == "" {
		return nil, "", ErrNoCover
	}
	raw := c.base + "/release/" + url.PathEscape(releaseMBID) + "/front-500"
	u, err := url.Parse(raw)
	if err != nil {
		return nil, "", err
	}
	if err := c.core.pace(ctx, u.Host); err != nil {
		return nil, "", err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, raw, nil)
	if err != nil {
		return nil, "", err
	}
	req.Header.Set("User-Agent", c.agent)
	resp, err := c.client.Do(req)
	if err != nil {
		return nil, "", err
	}
	defer resp.Body.Close()
	switch resp.StatusCode {
	case http.StatusOK:
	case http.StatusNotFound:
		return nil, "", ErrNoCover
	default:
		return nil, "", fmt.Errorf("providers: cover art archive: status %d", resp.StatusCode)
	}
	data, err := readCapped(resp.Body, c.maxBytes)
	if err != nil {
		return nil, "", err
	}
	// The type comes from the bytes, not from the header. These are
	// served back from WaxDeck's own origin, so what they actually are
	// is the only thing worth trusting - the same rule the station logo
	// path settled on.
	mime, ok := coverArtMimes[http.DetectContentType(data)]
	if !ok {
		return nil, "", ErrNoCover
	}
	return data, mime, nil
}

// coverArtMimes is the raster allow-list, keyed by what the sniffer
// reports. Nothing that can carry script is on it: these bytes are
// served from WaxDeck's own origin.
var coverArtMimes = map[string]string{
	"image/jpeg": "image/jpeg",
	"image/png":  "image/png",
	"image/webp": "image/webp",
	"image/gif":  "image/gif",
}

// RecordingReleaseLookup is the MusicBrainz half of a recording cover
// lookup. *MusicBrainz implements it.
type RecordingReleaseLookup interface {
	ReleaseMBIDForRecording(ctx context.Context, artist, title string) (string, error)
}

// RecordingCover composes the two calls a cover for an announced track
// takes: a MusicBrainz recording search for a release id, then the
// archive for that release's front cover.
//
// Composed here rather than in the service so the caller stays free of
// both upstream vocabularies, and so the shared MusicBrainz client is
// the one that gets used - a second client would be an unthrottled
// second caller against a service that rate-limits at roughly one
// request per second and requires an identifying agent, which is how an
// instance gets blocked.
type RecordingCover struct {
	MB  RecordingReleaseLookup
	CAA *CoverArt
	// NoCover is returned when upstream answered and holds nothing. The
	// caller sets it to its own sentinel so it can tell that outcome
	// from an unreachable service and cache the two for different
	// lengths of time; nil falls back to ErrNoCover.
	NoCover error
}

// FrontCover answers a front cover for an announced artist and title.
func (r RecordingCover) FrontCover(ctx context.Context, artist, title string) ([]byte, string, error) {
	missing := r.NoCover
	if missing == nil {
		missing = ErrNoCover
	}
	if r.MB == nil || r.CAA == nil {
		return nil, "", missing
	}
	mbid, err := r.MB.ReleaseMBIDForRecording(ctx, artist, title)
	if err != nil {
		return nil, "", err
	}
	if mbid == "" {
		// Asked and answered: MusicBrainz knows no recording by this
		// name, which will still be true tomorrow far more often than
		// not. That is the long-cached outcome, not the short one.
		return nil, "", missing
	}
	data, mime, err := r.CAA.FrontCover(ctx, mbid)
	if errors.Is(err, ErrNoCover) {
		return nil, "", missing
	}
	if err != nil {
		return nil, "", err
	}
	return data, mime, nil
}
