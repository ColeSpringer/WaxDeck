package providers

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"slices"
	"strings"
	"sync"
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
	// HTTPClient defaults to a client bounded by RequestTimeout.
	HTTPClient *http.Client
	// MinInterval defaults to 1100ms, the same one-per-second pacing the
	// MusicBrainz client keeps.
	MinInterval time.Duration
	// MaxBytes bounds one downloaded image; defaults to 2 MiB, an order
	// of magnitude past what the 500px rendition weighs.
	MaxBytes int64
	// RequestTimeout bounds one archive fetch, pacing excluded; defaults
	// to 15s and is what the default client's own timeout is built from,
	// so raising it raises the bound rather than colliding with it.
	RequestTimeout time.Duration
	// MissTTL is how long a 404 is remembered; defaults to 24h. Finite
	// because a release entered this week can have a cover next week.
	MissTTL time.Duration
	// MaxMisses bounds that memory by entry count; defaults to 4096.
	MaxMisses int
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

	// misses remembers the releases the archive answered 404 for; not
	// core's response cache, which keeps 200 bodies. The TTL is uniform,
	// so missOrder is expiry order and both bound and sweep read the front.
	missTTL   time.Duration
	maxMisses int
	missMu    sync.Mutex
	misses    map[string]time.Time
	missOrder []string

	reqTimeout time.Duration
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
	reqTimeout := cfg.RequestTimeout
	if reqTimeout == 0 {
		reqTimeout = 15 * time.Second
	}
	client := cfg.HTTPClient
	if client == nil {
		client = &http.Client{Timeout: reqTimeout}
	}
	missTTL := cfg.MissTTL
	if missTTL == 0 {
		missTTL = 24 * time.Hour
	}
	maxMisses := cfg.MaxMisses
	if maxMisses <= 0 {
		maxMisses = maxCacheEntries
	}
	return &CoverArt{
		base:       strings.TrimRight(base, "/"),
		maxBytes:   maxBytes,
		client:     client,
		agent:      ua,
		core:       newCore(client, ua, interval),
		missTTL:    missTTL,
		maxMisses:  maxMisses,
		misses:     map[string]time.Time{},
		reqTimeout: reqTimeout,
	}
}

// ErrNoCover reports that the archive answered and holds no front cover
// for the release. A distinct error because the caller caches "answered,
// nothing there" for far longer than "could not ask".
var ErrNoCover = errors.New("providers: no front cover for this release")

// errNotAnImage is a 200 whose body is not a raster - the archive's
// storage answers an HTML error page with one under load, and reading
// that as ErrNoCover files a release that has a cover as bare.
var errNotAnImage = errors.New("providers: the archive answered with something that is not an image")

// FrontCoverURL is the address FrontCover fetches a release's front
// cover from. Exposed so a caller that reports where a picture came
// from names the same URL the fetch used, rather than rebuilding it.
func (c *CoverArt) FrontCoverURL(releaseMBID string) string {
	if releaseMBID == "" {
		return ""
	}
	return c.base + "/release/" + url.PathEscape(releaseMBID) + "/front-500"
}

// FrontCover downloads a release's front cover, at the archive's 500px
// rendition rather than the original: an original scan can be a 20 MB
// TIFF, and the archive's storage is slow enough that the bytes are the
// wait. 500px is what a station face needs.
//
// The 404 case is ErrNoCover, which is the ordinary answer - most
// releases have no art - and is what lets the caller tell an empty
// archive from an unreachable one.
func (c *CoverArt) FrontCover(ctx context.Context, releaseMBID string) ([]byte, string, error) {
	if releaseMBID == "" {
		return nil, "", ErrNoCover
	}
	// Asked and answered. Releases with nothing on file are the bulk of
	// any walk, so this is what makes a second walk cheap.
	if c.knownBare(releaseMBID) {
		return nil, "", ErrNoCover
	}
	raw := c.FrontCoverURL(releaseMBID)
	u, err := url.Parse(raw)
	if err != nil {
		return nil, "", err
	}
	if err := c.core.pace(ctx, u.Host); err != nil {
		return nil, "", err
	}
	// After the pacer, so queueing is not charged as request time. One
	// unresponsive release must not spend the whole walk's budget.
	ctx, cancel := context.WithTimeout(ctx, c.reqTimeout)
	defer cancel()
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
		// The only outcome that is about this release rather than about
		// the archive's afternoon, so the only one remembered.
		c.rememberBare(releaseMBID)
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
		return nil, "", errNotAnImage
	}
	return data, mime, nil
}

// knownBare reports whether the archive has already said it holds no
// front cover for this release. Expired entries drop where they are
// found, so a server that went quiet does not hold them for its life.
func (c *CoverArt) knownBare(releaseMBID string) bool {
	c.missMu.Lock()
	defer c.missMu.Unlock()
	at, ok := c.misses[releaseMBID]
	if !ok {
		return false
	}
	if time.Since(at) >= c.missTTL {
		delete(c.misses, releaseMBID)
		return false
	}
	return true
}

// rememberBare files a release the archive answered 404 for. Bounded
// oldest-first: the ids come from searches for titles a station chooses.
func (c *CoverArt) rememberBare(releaseMBID string) {
	c.missMu.Lock()
	defer c.missMu.Unlock()
	if c.misses == nil {
		c.misses = map[string]time.Time{}
	}
	if _, exists := c.misses[releaseMBID]; exists {
		c.misses[releaseMBID] = time.Now()
		return
	}
	// The expired go first, because a release the walk never revisits is
	// never passed to knownBare and would otherwise hold its slot for the
	// life of the process.
	drop := 0
	for drop < len(c.missOrder) {
		at, ok := c.misses[c.missOrder[drop]]
		if ok && time.Since(at) < c.missTTL {
			break
		}
		delete(c.misses, c.missOrder[drop])
		drop++
	}
	for len(c.missOrder)-drop >= c.maxMisses {
		delete(c.misses, c.missOrder[drop])
		drop++
	}
	c.missOrder = append(slices.Delete(c.missOrder, 0, drop), releaseMBID)
	c.misses[releaseMBID] = time.Now()
}

// ForgetMisses drops the bare-release memory, for an operator switching
// the rung off: without it a purge upstream of this leaves a day-old
// private map deciding what gets asked about after the rung comes back.
func (c *CoverArt) ForgetMisses() {
	c.missMu.Lock()
	defer c.missMu.Unlock()
	c.misses = map[string]time.Time{}
	c.missOrder = nil
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

// ProviderCoverArtArchive is the provider id the archive rung reports,
// matching the ids the enrichment providers answer to Name().
const ProviderCoverArtArchive = "coverartarchive"

// RecordingReleaseLookup is the MusicBrainz half of a recording cover
// lookup. *MusicBrainz implements it.
type RecordingReleaseLookup interface {
	ReleaseMBIDsForRecording(ctx context.Context, artist, title string) ([]string, error)
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
func (r RecordingCover) FrontCover(ctx context.Context, artist, title string) (TitleCoverResult, error) {
	missing := r.NoCover
	if missing == nil {
		missing = ErrNoCover
	}
	if r.MB == nil || r.CAA == nil {
		return TitleCoverResult{}, missing
	}
	mbids, err := r.MB.ReleaseMBIDsForRecording(ctx, artist, title)
	if err != nil {
		return TitleCoverResult{}, err
	}
	if len(mbids) == 0 {
		// Asked and answered: MusicBrainz knows no recording by this
		// name, which will still be true tomorrow far more often than
		// not. That is the long-cached outcome, not the short one.
		return TitleCoverResult{}, missing
	}
	// Down the releases in the order the lookup ranked them - album
	// before single before the rest, compilations demoted. Having a
	// release is not having a picture of it: a current single is
	// routinely entered twice, once for a digital release nobody
	// uploaded a sleeve for and once for the album that has one, and
	// asking only the first is why a track playing on the radio drew
	// nothing while its cover sat in the archive one release along.
	var reachErr error
	for _, mbid := range mbids {
		// The budget is spent on the walk, so a deadline reached partway
		// down it ends the walk: every call after this one would fail at
		// the pacer without asking anybody anything. Either way the
		// caller hears an error rather than a miss, which is what decides
		// how long the outcome is remembered.
		if err := ctx.Err(); err != nil {
			return TitleCoverResult{}, err
		}
		data, mime, err := r.CAA.FrontCover(ctx, mbid)
		switch {
		case err == nil:
			return TitleCoverResult{
				Data: data, MIME: mime,
				Provider:  ProviderCoverArtArchive,
				SourceURL: r.CAA.FrontCoverURL(mbid),
			}, nil
		case errors.Is(err, ErrNoCover):
			continue
		default:
			// Held rather than returned: a release the archive could not
			// be asked about says nothing about the next one, and the
			// error only matters if none of them answers.
			reachErr = err
		}
	}
	if reachErr != nil {
		return TitleCoverResult{}, reachErr
	}
	return TitleCoverResult{}, missing
}

// ForgetMisses drops the archive's bare-release memory, so the caller's
// own purge reaches all of what this composite remembers.
func (r RecordingCover) ForgetMisses() {
	if r.CAA != nil {
		r.CAA.ForgetMisses()
	}
}

// TitleCoverResult is one answer for an announced title: the picture,
// its type, and where it came from. Provider names the rung that
// answered so a listening surface can caption a third party's cover as
// theirs rather than presenting it as the station's own; SourceURL is
// the address the bytes were fetched from, empty where the rung does
// not have a single one.
type TitleCoverResult struct {
	Data      []byte
	MIME      string
	Provider  string
	SourceURL string
}

// TitleCover answers a front cover for an announced artist and title.
// Deezer and RecordingCover both implement it.
type TitleCover interface {
	FrontCover(ctx context.Context, artist, title string) (TitleCoverResult, error)
}

// CoverChain asks its sources in order and takes the first cover, so a
// fast one can sit in front of a thorough one. A source that could not be
// reached is held, and surfaces only if nothing below it answers either.
type CoverChain struct {
	Sources []TitleCover
	// NoCover is returned when every source answered and none held a
	// picture. The caller sets it to its own sentinel so it can tell that
	// from an unreachable service; nil falls back to ErrNoCover.
	NoCover error
}

// FrontCover walks the sources in order.
func (c CoverChain) FrontCover(ctx context.Context, artist, title string) (TitleCoverResult, error) {
	missing := c.NoCover
	if missing == nil {
		missing = ErrNoCover
	}
	var reachErr error
	for _, src := range c.Sources {
		if err := ctx.Err(); err != nil {
			return TitleCoverResult{}, err
		}
		got, err := src.FrontCover(ctx, artist, title)
		switch {
		case err == nil && len(got.Data) > 0:
			return got, nil
		case err == nil, errors.Is(err, ErrNoCover), errors.Is(err, missing):
			continue
		default:
			reachErr = err
		}
	}
	if reachErr != nil {
		return TitleCoverResult{}, reachErr
	}
	return TitleCoverResult{}, missing
}

// ForgetMisses passes an operator's purge down to whichever sources keep
// a memory of their own.
func (c CoverChain) ForgetMisses() {
	for _, src := range c.Sources {
		if forgetful, ok := src.(interface{ ForgetMisses() }); ok {
			forgetful.ForgetMisses()
		}
	}
}
