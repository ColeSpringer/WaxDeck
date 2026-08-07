package service

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"slices"
	"sync"
	"time"
)

// The second rung of radio artwork: a cover for a song this library does
// not hold.
//
// The first rung is RadioNowPlayingItem, which matches the announced
// title against the catalog and costs no network at all. That one runs
// first and answers most of the time somebody is listening to a station
// playing music they own. This one runs only on its miss.
//
// Off by default, and that is the whole reason the toggle exists rather
// than a constant: it sends strings a third party chose - a station's
// announced title - from a self-hosted server to musicbrainz.org and
// coverartarchive.org. That is a decision a self-hoster is entitled to
// make, and a much easier argument to have before shipping than after.
// With it off nothing outbound happens and the station mark is what a
// listener sees, which is why the mark landed first.

// RadioArtResolver answers a front cover for an announced artist and
// title. The composite of the MusicBrainz and Cover Art Archive
// providers implements it; nil leaves the external rung unavailable
// however the toggle is set.
//
// The narrow interface is what keeps the service free of both upstream
// vocabularies, the same shape ISRCResolver takes. It also has to
// distinguish its two failures, which is what the sentinel is for: a
// resolver that answered and found nothing returns ErrNoRadioArt, and
// anything else is "could not ask".
type RadioArtResolver interface {
	FrontCover(ctx context.Context, artist, title string) (data []byte, mime string, err error)
}

// ErrNoRadioArt is the answered-and-empty outcome: upstream was reached
// and holds no cover for this recording. Cached for a day; every other
// failure is cached for minutes.
var ErrNoRadioArt = errors.New("service: no external artwork for this title")

const (
	// radioArtFreshFor is how long a fetched cover is reused. A release's
	// front cover does not change.
	radioArtFreshFor = 7 * 24 * time.Hour
	// radioArtMissFreshFor is how long "upstream has nothing for this"
	// is remembered. Finite on purpose, and short enough to matter: a
	// track released this week can have no Cover Art Archive entry today
	// and one tomorrow, and a permanent miss would never find it.
	radioArtMissFreshFor = 24 * time.Hour
	// radioArtFailureFreshFor is how long a transient failure is
	// remembered - a 503, a rate-limit refusal, a timeout. Minutes, not
	// a day: caching one bad minute upstream for a day turns it into a
	// day of blank faces, and this is the case most likely to be
	// upstream's problem rather than this title's.
	radioArtFailureFreshFor = 5 * time.Minute
	// radioArtCacheBytes bounds the whole cache, which is what the
	// station-logo cache next door bounds and what matters: an entry
	// count times the fetch cap is a resident ceiling in the gigabytes,
	// and the key is a title a station chooses, so nothing that grows on
	// a stranger's input gets to grow unbounded. A front-500 cover runs
	// tens of kilobytes, so this holds a long dial-sitting.
	radioArtCacheBytes = 32 << 20
	// radioArtLookupBudget bounds one lookup. Two paced calls at roughly
	// a second each, plus slack: past this the answer is "not this poll",
	// and the next one re-asks.
	radioArtLookupBudget = 20 * time.Second
)

// radioArtEntry is one cached lookup. Empty Bytes means there is nothing
// to draw, and fresh says for how long that stands - which is the whole
// point of caching the two outcomes separately.
type radioArtEntry struct {
	art     RadioLogo
	fetched time.Time
	fresh   time.Duration
}

func (e radioArtEntry) stale() bool { return time.Since(e.fetched) >= e.fresh }

// radioArt is the announced-title cover cache, plus the single-flight
// that keeps a household of listeners on one station from starting one
// upstream lookup per device.
type radioArt struct {
	mu       sync.Mutex
	entries  map[string]radioArtEntry
	order    []string
	bytes    int
	inFlight map[string]bool
}

// radioArtKey names one cover by the normalized artist and title it was
// fetched for. The caller normalizes before calling, so the query that
// produced the entry and the key it is filed under cannot disagree.
func radioArtKey(artist, title string) string {
	sum := sha256.Sum256([]byte(artist + "\x00" + title))
	return hex.EncodeToString(sum[:16])
}

// radioLogoFromBytes wraps already-validated image bytes in the shape
// the artwork endpoints serve. The resolver decided the type by sniffing
// the body, so nothing is trusted here that was not trusted there; the
// ETag is content-addressed like every other picture WaxDeck serves.
func radioLogoFromBytes(data []byte, mime string) RadioLogo {
	sum := sha256.Sum256(data)
	return RadioLogo{
		Bytes:    data,
		MimeType: mime,
		ETag:     `"` + hex.EncodeToString(sum[:16]) + `"`,
	}
}

// RadioNowPlayingArt answers the cover held under one key, or a
// not-found.
//
// Addressed by key, not by whatever the station is announcing right now,
// and that is what makes the endpoint safe to cache and safe to draw. A
// station rolls its title over every few minutes while a client polls
// every fifteen seconds, so resolving against the live title meant an
// image request that crossed a rollover answered 404 for a cover the
// server was holding - and the client's artwork store remembers a 404
// against the URL for the rest of the session. Keyed, the bytes behind a
// URL never change, so the long Cache-Control it carries is true.
//
// Never a lookup: this is the read half and answers only from the cache.
// The lookup is started by the play-info poll, which is what makes it
// safe to reach a paced third-party service at all - a fetch inside this
// request would hold an image response open for two paced round trips,
// and every client on the station would start its own.
func (l *Library) RadioNowPlayingArt(key string) (RadioLogo, error) {
	// The toggle governs the read as well as the fetch. Otherwise an
	// operator who switched the rung off would keep serving third-party
	// covers from their own origin for as long as the cache held them,
	// which is not what turning it off means.
	if !l.RadioExternalArtEnabled() {
		return RadioLogo{}, errNotFound("no artwork for this station")
	}
	if key == "" {
		return RadioLogo{}, errNotFound("no artwork for this station")
	}
	entry, ok := l.cachedRadioArt(key)
	if !ok || len(entry.art.Bytes) == 0 {
		return RadioLogo{}, errNotFound("no artwork for this station")
	}
	return entry.art, nil
}

// EnsureRadioNowPlayingArt starts an external lookup for an announced
// title when the toggle is on, nothing is cached, and no other caller is
// already asking. It answers the key the cover is held under, empty when
// there is none yet.
//
// The key is what the client puts in the image URL, so a station that
// changes what it is playing changes the URL it draws from. Returning a
// bool instead left one URL per station: same URL, same ImageProvider
// key, same decoded bytes out of Flutter's image cache, and a day of
// Cache-Control on top - so only the first matched track of a session
// ever drew.
//
// Started rather than awaited, so a play-info poll never waits on
// musicbrainz.org. The client is already polling every fifteen seconds
// (the contract says so), so the answer arrives on the next poll, which
// is the cadence a station's own titles change at anyway.
//
// No context parameter, deliberately: nothing here is the caller's to
// cancel. The cache read is a mutex and a map, and the lookup runs on
// procCtx - taking a request context would say the poll can call the
// work off, which is the opposite of the point.
func (l *Library) EnsureRadioNowPlayingArt(stationName, announced string) string {
	if l.radioArtResolver == nil || !l.RadioExternalArtEnabled() {
		return ""
	}
	rawArtist, rawTitle, ok := parseRadioTitle(announced, stationName)
	if !ok {
		return ""
	}
	// Normalized once, and both the key and the upstream query are built
	// from the same values. Keying on the normalized form while querying
	// the raw one collapsed "Ornithology (Official Audio)" and
	// "Ornithology" onto one entry and let whichever arrived first decide
	// the search - so the noisy spelling, the one MusicBrainz misses,
	// could cache a day-long miss against a key the clean spelling would
	// have resolved. The local-match rung already normalizes before it
	// searches; this is the same rule one rung down.
	artist, title := normalizeRadioField(rawArtist), normalizeRadioField(rawTitle)
	if artist == "" || title == "" {
		return ""
	}
	key := radioArtKey(artist, title)
	if entry, cached := l.cachedRadioArt(key); cached {
		if len(entry.art.Bytes) == 0 {
			return ""
		}
		return key
	}
	if !l.claimRadioArtLookup(key) {
		return ""
	}
	// procCtx, not the request's: the poll that started this is answered
	// long before the lookup lands, so cancelling on the caller going
	// away would mean a station nobody polls twice never resolves. Not
	// context.WithoutCancel either, which strips the shutdown signal with
	// the request's - Group.Wait blocks until every worker returns, so an
	// uncancellable lookup would hold a shutdown for the whole
	// twenty-second budget while an HTTP call to musicbrainz.org ran to
	// completion. procCtx is the one that outlives a request and still
	// ends with the process.
	l.workers.GoOnce(l.procCtx, "radio-art", func(ctx context.Context) error {
		defer l.releaseRadioArtLookup(key)
		ctx, cancel := context.WithTimeout(ctx, radioArtLookupBudget)
		defer cancel()
		data, mime, err := l.radioArtResolver.FrontCover(ctx, artist, title)
		switch {
		case err == nil && len(data) > 0:
			l.storeRadioArt(key, radioArtEntry{
				art:     radioLogoFromBytes(data, mime),
				fetched: time.Now(),
				fresh:   radioArtFreshFor,
			})
		case errors.Is(err, ErrNoRadioArt):
			l.storeRadioArt(key, radioArtEntry{fetched: time.Now(), fresh: radioArtMissFreshFor})
		default:
			// Answered nothing and may answer next time: remembered for
			// minutes so a bad interval upstream does not become a day
			// of blank faces, and so a retry storm cannot form either.
			l.log.Debug("radio artwork lookup failed", "err", err)
			l.storeRadioArt(key, radioArtEntry{fetched: time.Now(), fresh: radioArtFailureFreshFor})
		}
		return nil
	})
	return ""
}

func (l *Library) cachedRadioArt(key string) (radioArtEntry, bool) {
	l.radioArtCache.mu.Lock()
	defer l.radioArtCache.mu.Unlock()
	entry, ok := l.radioArtCache.entries[key]
	if !ok {
		return radioArtEntry{}, false
	}
	if entry.stale() {
		// Dropped where it is found, not left for the next insert to
		// evict. A server that met a few hundred titles and then went
		// quiet would otherwise hold every one of those image bodies for
		// the life of the process: nothing inserts, so nothing evicts.
		l.dropRadioArt(key)
		return radioArtEntry{}, false
	}
	return entry, true
}

func (l *Library) storeRadioArt(key string, entry radioArtEntry) {
	l.radioArtCache.mu.Lock()
	defer l.radioArtCache.mu.Unlock()
	if l.radioArtCache.entries == nil {
		l.radioArtCache.entries = map[string]radioArtEntry{}
	}
	if _, exists := l.radioArtCache.entries[key]; exists {
		l.dropRadioArt(key)
	}
	l.radioArtCache.entries[key] = entry
	l.radioArtCache.order = append(l.radioArtCache.order, key)
	l.radioArtCache.bytes += len(entry.art.Bytes)
	// Oldest-first over an insertion list, and bounded by bytes rather
	// than by entry count: a count times the fetch cap is a resident
	// ceiling in the gigabytes, which is why the logo cache next door
	// counts bytes too. An LRU over something this small costs more to
	// keep than the lookups it would save. One entry always survives, so
	// a cover larger than the whole budget is still served once.
	for l.radioArtCache.bytes > radioArtCacheBytes && len(l.radioArtCache.order) > 1 {
		l.dropRadioArt(l.radioArtCache.order[0])
	}
}

// dropRadioArt forgets one entry. The lock is the caller's.
func (l *Library) dropRadioArt(key string) {
	entry, ok := l.radioArtCache.entries[key]
	if !ok {
		return
	}
	l.radioArtCache.bytes -= len(entry.art.Bytes)
	delete(l.radioArtCache.entries, key)
	l.radioArtCache.order = slices.DeleteFunc(l.radioArtCache.order, func(k string) bool {
		return k == key
	})
}

// forgetRadioArt drops every cached cover, for an operator switching the
// external rung off: the read path refuses while it is off either way,
// but bytes fetched from a third party should not sit resident after the
// decision to stop asking for them.
func (l *Library) forgetRadioArt() {
	l.radioArtCache.mu.Lock()
	defer l.radioArtCache.mu.Unlock()
	l.radioArtCache.entries = nil
	l.radioArtCache.order = nil
	l.radioArtCache.bytes = 0
}

// claimRadioArtLookup reports whether this caller owns the lookup for a
// key. One announced title on a station a household is listening to
// reaches this from every device at once; without the claim each would
// start its own pair of paced calls against a service that rate-limits
// at one request a second.
func (l *Library) claimRadioArtLookup(key string) bool {
	l.radioArtCache.mu.Lock()
	defer l.radioArtCache.mu.Unlock()
	if l.radioArtCache.inFlight[key] {
		return false
	}
	if l.radioArtCache.inFlight == nil {
		l.radioArtCache.inFlight = map[string]bool{}
	}
	l.radioArtCache.inFlight[key] = true
	return true
}

func (l *Library) releaseRadioArtLookup(key string) {
	l.radioArtCache.mu.Lock()
	defer l.radioArtCache.mu.Unlock()
	delete(l.radioArtCache.inFlight, key)
}
