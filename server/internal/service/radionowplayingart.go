package service

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"net/url"
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
// Behind a toggle rather than a constant, because it sends strings a
// third party chose - a station's announced title - from a self-hosted
// server to api.deezer.com, musicbrainz.org and coverartarchive.org, and
// that is a decision a self-hoster is entitled to make. On by default: only about
// one station in twenty announces a picture of its own, so leaving this
// off meant the full-screen player drew a monogram for the rest with
// nothing to explain it. Turned off, nothing outbound happens and the
// station mark is what a listener sees, which is a designed answer
// rather than a gap.

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
// and holds no cover for this recording. Cached for a day; anything else
// - a refusal, a timeout, a budget the walk never finished inside - for
// minutes.
var ErrNoRadioArt = errors.New("service: no external artwork for this title")

// errRadioArtNotImage marks a fetched body that was never going to be a
// picture: a declared type outside the set, bytes that sniff as
// something else, an empty body, one over the cap. Distinct from a
// timeout or a 5xx because the two deserve different memories - HTML
// today is HTML tomorrow, and a station that put its homepage in
// StreamUrl should cost one fetch a day rather than one a poll.
var errRadioArtNotImage = errors.New("service: the fetched body is not usable artwork")

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
	// a stranger's input gets to grow unbounded. External covers run tens
	// of kilobytes; an announced one is capped at 512 KB, so a station
	// that cache-busts its art is what actually sizes this.
	radioArtCacheBytes = 32 << 20
	// radioArtCacheEntries bounds the cache by count as well as by
	// bytes, because the byte ceiling cannot see the entries that matter
	// most here: a miss and a failure are stored with no bytes at all,
	// so a cache full of them weighs nothing and never evicts. The
	// announced rung makes that reachable rather than theoretical - it
	// is keyed by a URL the station chooses, is not behind the toggle,
	// and a station that cache-busts its cover (`.../art?t=1699...`)
	// mints a fresh key on every poll. Counting keeps the promise the
	// byte bound was making on its own: nothing that grows on a
	// stranger's input grows without a ceiling.
	radioArtCacheEntries = 4096
	// radioArtLookupBudget bounds one lookup - a search plus up to six
	// paced archive fetches - so a worker cannot hold its slot on an
	// upstream that has stopped answering. Reaching it is a failure like
	// any other and backs off for as long.
	radioArtLookupBudget = 60 * time.Second
)

// radioArtEntry is one cached lookup. Empty Bytes means there is nothing
// to draw, and fresh says for how long that stands - which is the whole
// point of caching the two outcomes separately.
type radioArtEntry struct {
	art     RadioLogo
	fetched time.Time
	fresh   time.Duration
	// announced marks a picture the station named in its own stream
	// rather than one this server went and asked a third party for. The
	// toggle does not govern these, and neither does the forget that
	// comes with switching it off: nothing was sent anywhere to get
	// them.
	announced bool
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
	if key == "" {
		return RadioLogo{}, errNotFound("no artwork for this station")
	}
	entry, ok := l.cachedRadioArt(key)
	if !ok || len(entry.art.Bytes) == 0 {
		return RadioLogo{}, errNotFound("no artwork for this station")
	}
	// The toggle governs the read as well as the fetch. Otherwise an
	// operator who switched the rung off would keep serving third-party
	// covers from their own origin for as long as the cache held them,
	// which is not what turning it off means.
	//
	// An announced picture is not one of those. The station named it in
	// the stream this listener is already receiving, which is the same
	// trust footing its logo has always been fetched on, and nothing
	// about this library was sent anywhere to learn of it. What the
	// toggle exists to decide - whether a title a station chose leaves
	// this server for a third party - is not in question here.
	if !entry.announced && !l.RadioExternalArtEnabled() {
		return RadioLogo{}, errNotFound("no artwork for this station")
	}
	return entry.art, nil
}

// announcedArtKey names a picture by the URL it came from and the song
// it was announced with.
//
// The URL alone was the first answer, on the reasoning that it changes
// exactly when the picture does. It does not: serving mutable bytes from
// one stable path (`.../nowplaying.jpg`) is a common automation, and
// under a URL-only key the token never changed, so the image URL the
// client draws never changed either - and behind a long Cache-Control
// one song's cover stayed on the face for the rest of the week.
//
// The announced title rides the hash for that reason, raw rather than
// parsed so a station whose line does not split into an artist and a
// song still gets a key that moves with the music. The prefix keeps this
// key space disjoint from radioArtKey's.
func announcedArtKey(artURL, announced string) string {
	sum := sha256.Sum256([]byte("announced\x00" + artURL + "\x00" + announced))
	return hex.EncodeToString(sum[:16])
}

// EnsureRadioAnnouncedArt starts a fetch for a picture the station
// announced, and answers the key it will be held under plus whether the
// caller should fall through to the external rung.
//
// The two returns are the whole design. A fetch that is *in flight* is
// worth waiting a poll for, so it holds the rung below off: the
// announced picture is the better answer and it is seconds away. A
// fetch that already *failed* does not hold anything, and answers so
// immediately - plenty of stations put their homepage in `StreamUrl` on
// every single track, and a station whose announced URL will never be a
// picture must not lose its external cover for it.
//
// Fetched through fetchRadioLogo, so the announced URL gets exactly the
// guarantees a station's logo URL gets: the SSRF-guarded client, the
// 512 KB cap read as one-past-and-refuse, the declared-type gate, and
// the served type decided by sniffing the bytes rather than by what the
// host called them.
func (l *Library) EnsureRadioAnnouncedArt(artURL, announced string) (string, bool) {
	if artURL == "" {
		return "", true
	}
	// Stations put all sorts of things in these keys. Something that is
	// not an http(s) URL is not worth a fetch and not worth holding the
	// rung below for - no request is made and no failure is cached,
	// because there is nothing here that could change tomorrow.
	u, err := url.Parse(artURL)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
		return "", true
	}
	key := announcedArtKey(artURL, announced)
	if entry, cached := l.cachedRadioArt(key); cached {
		if len(entry.art.Bytes) == 0 {
			return "", true
		}
		return key, false
	}
	if !l.claimRadioArtLookup(key) {
		return "", false
	}
	// procCtx for the same reason the external lookup uses it: the poll
	// that started this is answered long before the fetch lands, and a
	// station nobody polls twice would otherwise never resolve.
	l.workers.GoOnce(l.procCtx, "radio-announced-art", func(ctx context.Context) error {
		defer l.releaseRadioArtLookup(key)
		logo, fetchErr := l.fetchRadioLogo(ctx, artURL)
		switch {
		case fetchErr == nil && len(logo.Bytes) > 0:
			l.storeRadioArt(key, radioArtEntry{
				art:       logo,
				fetched:   time.Now(),
				fresh:     radioArtFreshFor,
				announced: true,
			})
			l.wakeRadioListeners()
		// A body that is not a picture will not be one tomorrow either:
		// a station that set its homepage here answers HTML every time.
		// Remembered for a day, so that costs one fetch a day rather
		// than one every fifteen seconds for as long as anybody listens.
		case errors.Is(fetchErr, errRadioArtNotImage):
			l.storeRadioArt(key, radioArtEntry{
				fetched: time.Now(), fresh: radioArtMissFreshFor, announced: true,
			})
		default:
			// A timeout, a refused connection, a 5xx: this one may well
			// answer next time, so it is remembered for minutes.
			l.log.Debug("announced radio artwork fetch failed", "err", fetchErr)
			l.storeRadioArt(key, radioArtEntry{
				fetched: time.Now(), fresh: radioArtFailureFreshFor, announced: true,
			})
		}
		return nil
	})
	return "", false
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
	artist, title := radioSearchField(rawArtist), radioSearchField(rawTitle)
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
		ctx, cancel := context.WithTimeout(ctx, l.radioArtBudget)
		defer cancel()
		data, mime, err := l.radioArtResolver.FrontCover(ctx, artist, title)
		// Asked again on the way out: the walk takes up to a minute, and
		// storing past a switch-off leaves third-party bytes resident for a
		// week after the forget that ran when the operator said stop.
		if !l.RadioExternalArtEnabled() {
			return nil
		}
		switch {
		case err == nil && len(data) > 0:
			l.storeRadioArt(key, radioArtEntry{
				art:     radioLogoFromBytes(data, mime),
				fetched: time.Now(),
				fresh:   radioArtFreshFor,
			})
			l.wakeRadioListeners()
		case errors.Is(err, ErrNoRadioArt):
			l.storeRadioArt(key, radioArtEntry{fetched: time.Now(), fresh: radioArtMissFreshFor})
		default:
			// Answered nothing and may answer next time: remembered for
			// minutes so a bad interval upstream does not become a day
			// of blank faces, and so a retry storm cannot form either.
			// A budget the walk never finished inside lands here too - an
			// upstream that cannot answer in a minute is having an
			// afternoon, and asking it again sooner helps nobody.
			l.log.Debug("radio artwork lookup failed", "err", err)
			l.storeRadioArt(key, radioArtEntry{fetched: time.Now(), fresh: radioArtFailureFreshFor})
		}
		return nil
	})
	return ""
}

// wakeRadioListeners tells live clients a cover landed, so a tuned face
// fills on the fetch rather than on its next poll. Never on a miss: a
// miss changes nothing to draw.
func (l *Library) wakeRadioListeners() {
	if fn := l.radioWake.Load(); fn != nil {
		(*fn)()
	}
}

// SetRadioInvalidator installs the fan-out called when radio artwork
// lands. A setter rather than a Config field because the event hub is
// built over the service, so it does not exist when Config is.
func (l *Library) SetRadioInvalidator(fn func()) {
	if fn == nil {
		l.radioWake.Store(nil)
		return
	}
	l.radioWake.Store(&fn)
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
	// Oldest-first over an insertion list, bounded by bytes because a
	// count times the fetch cap is a ceiling in the gigabytes, and dropped
	// in one pass because dropRadioArt walks the whole slice per element.
	drop := 0
	for len(l.radioArtCache.order)-drop > 1 &&
		(l.radioArtCache.bytes > radioArtCacheBytes ||
			len(l.radioArtCache.order)-drop > radioArtCacheEntries) {
		oldest := l.radioArtCache.order[drop]
		l.radioArtCache.bytes -= len(l.radioArtCache.entries[oldest].art.Bytes)
		delete(l.radioArtCache.entries, oldest)
		drop++
	}
	l.radioArtCache.order = slices.Delete(l.radioArtCache.order, 0, drop)
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
	// Announced covers stay. They were never fetched on the strength of
	// the toggle and are not served on it either: switching the external
	// rung off is a decision about talking to musicbrainz.org, and
	// dropping the pictures stations announce in their own streams would
	// be answering a question nobody asked.
	//
	// Rebuilt in one pass rather than dropped key by key. dropRadioArt
	// walks the whole order slice to remove one element, so calling it
	// per key is quadratic in the size of the cache - and this runs
	// under the mutex every play-info poll contends for, with a settings
	// toggle as its trigger.
	entries := make(map[string]radioArtEntry, len(l.radioArtCache.entries))
	order := make([]string, 0, len(l.radioArtCache.order))
	total := 0
	for _, key := range l.radioArtCache.order {
		entry, ok := l.radioArtCache.entries[key]
		if !ok || !entry.announced {
			continue
		}
		entries[key] = entry
		order = append(order, key)
		total += len(entry.art.Bytes)
	}
	l.radioArtCache.entries = entries
	l.radioArtCache.order = order
	l.radioArtCache.bytes = total
	// The resolver remembers which releases upstream holds no picture of,
	// and a purge that could not reach that would leave a day-old private
	// map deciding what gets asked about when the rung comes back on.
	if forgetful, ok := l.radioArtResolver.(interface{ ForgetMisses() }); ok {
		forgetful.ForgetMisses()
	}
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
