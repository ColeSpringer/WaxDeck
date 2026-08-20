package service

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"strconv"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/providers"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// fakeRadioArt stands in for the MusicBrainz plus Cover Art Archive
// pair, counting calls so the tests can assert what did and did not go
// out over the wire.
type fakeRadioArt struct {
	calls    atomic.Int64
	data     []byte
	mime     string
	provider string
	srcURL   string
	err      error

	mu    sync.Mutex
	asked [][2]string
}

func (f *fakeRadioArt) FrontCover(ctx context.Context, artist, title string) (providers.TitleCoverResult, error) {
	f.calls.Add(1)
	f.mu.Lock()
	f.asked = append(f.asked, [2]string{artist, title})
	f.mu.Unlock()
	if f.err != nil {
		return providers.TitleCoverResult{}, f.err
	}
	return providers.TitleCoverResult{
		Data: f.data, MIME: f.mime, Provider: f.provider, SourceURL: f.srcURL,
	}, nil
}

func (f *fakeRadioArt) queries() [][2]string {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([][2]string(nil), f.asked...)
}

// waitForRadioArt polls the cache until the detached lookup lands. The
// key is built the way the service builds it - normalized first, so the
// entry and the query that produced it cannot be filed apart.
func waitForRadioArt(t *testing.T, svc *Library, artist, title string) radioArtEntry {
	t.Helper()
	key := radioArtKey(radioSearchField(artist), radioSearchField(title))
	deadline := time.Now().Add(5 * time.Second)
	for {
		if entry, ok := svc.cachedRadioArt(key); ok {
			return entry
		}
		if time.Now().After(deadline) {
			t.Fatal("the artwork lookup never landed")
		}
		time.Sleep(5 * time.Millisecond)
	}
}

// TestRadioArtIsAskedOncePerTitle is the pacing property the whole
// design is built around: MusicBrainz rate-limits at roughly one request
// a second and a household polls play-info every fifteen seconds per
// device, so a title that has been asked about is never asked about
// again while its answer stands.
func TestRadioArtIsAskedOncePerTitle(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newCatalogFixture(t)
	resolver := &fakeRadioArt{data: coverPNG(t, 40), mime: "image/png"}
	svc.radioArtResolver = resolver
	enableRadioExternalArt(t, ctx, svc)

	// The first poll starts the lookup and answers false: nothing is
	// cached yet and it must not wait on a paced third party.
	if key := svc.EnsureRadioNowPlayingArt("Test FM", "Charlie Parker - Ornithology"); key != "" {
		t.Fatalf("the first poll reported key %q before the lookup could land", key)
	}
	entry := waitForRadioArt(t, svc, "Charlie Parker", "Ornithology")
	if len(entry.art.Bytes) == 0 {
		t.Fatal("the lookup landed with no bytes")
	}

	// Ten more polls of the same title, as ten devices on one station
	// would make.
	// The key both says there is art and is what the image URL is built
	// from, so a station changing what it plays changes the URL a face
	// draws. One URL per station drew the first matched track forever.
	var key string
	for range 10 {
		key = svc.EnsureRadioNowPlayingArt("Test FM", "Charlie Parker - Ornithology")
		if key == "" {
			t.Fatal("a later poll did not report the cached art")
		}
	}
	if _, err := svc.RadioNowPlayingArt(key); err != nil {
		t.Errorf("the reported key does not resolve: %v", err)
	}
	// A different announced title is a different key, which is the whole
	// point of returning one.
	other := radioArtKey(radioSearchField("Miles Davis"), radioSearchField("So What"))
	if other == key {
		t.Error("two different titles share one key")
	}
	if got := resolver.calls.Load(); got != 1 {
		t.Errorf("upstream was asked %d times for one title, want 1", got)
	}
}

// TestRadioArtCachesItsTwoFailuresDifferently is the finite negative
// cache. Answered-and-empty stands for a day, because a track released
// this week can have no archive entry today and one tomorrow; a service
// that could not be reached stands for minutes, because caching one bad
// minute upstream for a day turns it into a day of blank faces.
func TestRadioArtCachesItsTwoFailuresDifferently(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newCatalogFixture(t)
	enableRadioExternalArt(t, ctx, svc)

	svc.radioArtResolver = &fakeRadioArt{err: ErrNoRadioArt}
	svc.EnsureRadioNowPlayingArt("Test FM", "Nobody - Unreleased")
	miss := waitForRadioArt(t, svc, "Nobody", "Unreleased")
	if len(miss.art.Bytes) != 0 {
		t.Fatal("an answered-empty lookup cached bytes")
	}
	if miss.fresh != radioArtMissFreshFor {
		t.Errorf("answered-empty cached for %v, want %v", miss.fresh, radioArtMissFreshFor)
	}

	svc.radioArtResolver = &fakeRadioArt{err: errors.New("503 from upstream")}
	svc.EnsureRadioNowPlayingArt("Test FM", "Nobody - Also Unreleased")
	failed := waitForRadioArt(t, svc, "Nobody", "Also Unreleased")
	if failed.fresh != radioArtFailureFreshFor {
		t.Errorf("a transient failure cached for %v, want %v", failed.fresh, radioArtFailureFreshFor)
	}
	if failed.fresh >= miss.fresh {
		t.Error("a transient failure is remembered at least as long as a real miss")
	}
}

// TestRadioArtMakesNoRequestWhileOff is the toggle, and it is the
// property the whole rung ships behind: with it off nothing about a
// station's announced title leaves this server.
func TestRadioArtMakesNoRequestWhileOff(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newCatalogFixture(t)
	resolver := &fakeRadioArt{data: coverPNG(t, 40), mime: "image/png"}
	svc.radioArtResolver = resolver
	disableRadioExternalArt(t, ctx, svc)

	for range 5 {
		if svc.EnsureRadioNowPlayingArt("Test FM", "Charlie Parker - Ornithology") != "" {
			t.Fatal("art was reported with the rung switched off")
		}
	}
	time.Sleep(50 * time.Millisecond)
	if got := resolver.calls.Load(); got != 0 {
		t.Errorf("upstream was asked %d times with the rung off, want 0", got)
	}
}

// blockingRadioArt holds a lookup open until its own context ends, and
// records which way it ended.
type blockingRadioArt struct {
	started   chan struct{}
	cancelled chan struct{}
}

func (b *blockingRadioArt) FrontCover(ctx context.Context, artist, title string) (providers.TitleCoverResult, error) {
	close(b.started)
	<-ctx.Done()
	close(b.cancelled)
	return providers.TitleCoverResult{}, ctx.Err()
}

// TestRadioArtLookupEndsWithTheProcess is the shutdown property.
//
// The lookup deliberately outlives the request that started it, and the
// obvious way to write that - context.WithoutCancel - strips the
// shutdown signal along with the request's. Group.Wait blocks until
// every worker returns, so an uncancellable lookup would hold a
// shutdown open for the whole twenty-second budget while an HTTP call to
// a paced third party ran to completion. procCtx is what outlives a
// request and still ends with the process.
func TestRadioArtLookupEndsWithTheProcess(t *testing.T) {
	t.Parallel()
	procCtx, shutdown := context.WithCancel(context.Background())
	group := supervise.NewGroup(slog.New(slog.NewTextHandler(io.Discard, nil)))
	resolver := &blockingRadioArt{
		started:   make(chan struct{}),
		cancelled: make(chan struct{}),
	}
	// A bare Library: this is about the worker's context and nothing
	// else, so a scanned catalog would only slow it down.
	l := &Library{
		log:              slog.New(slog.NewTextHandler(io.Discard, nil)),
		procCtx:          procCtx,
		workers:          group,
		radioArtResolver: resolver,
	}
	l.toggles.Store(&runtimeToggles{
		readOnlyLibs:     map[string]bool{},
		radioExternalArt: true,
	})

	l.EnsureRadioNowPlayingArt("Test FM", "Charlie Parker - Ornithology")
	select {
	case <-resolver.started:
	case <-time.After(5 * time.Second):
		t.Fatal("the lookup never started")
	}

	shutdown()
	select {
	case <-resolver.cancelled:
	case <-time.After(5 * time.Second):
		t.Fatal("the lookup ignored the shutdown; Group.Wait would block on it")
	}

	done := make(chan struct{})
	go func() { group.Wait(); close(done) }()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("Group.Wait did not return after the shutdown")
	}
}

// disableRadioExternalArt switches the rung off, which since the
// default flipped is a thing a test has to say rather than inherit.
func disableRadioExternalArt(t *testing.T, ctx context.Context, svc *Library) {
	t.Helper()
	if err := svc.db.SettingSet(ctx, settingRadioExternalArt, "false", time.Now().UnixNano()); err != nil {
		t.Fatalf("disabling the external rung: %v", err)
	}
	svc.loadRuntimeToggles(ctx)
	if svc.RadioExternalArtEnabled() {
		t.Fatal("the external rung did not go off")
	}
}

func enableRadioExternalArt(t *testing.T, ctx context.Context, svc *Library) {
	t.Helper()
	if err := svc.db.SettingSet(ctx, settingRadioExternalArt, "true", time.Now().UnixNano()); err != nil {
		t.Fatalf("enabling the external rung: %v", err)
	}
	svc.loadRuntimeToggles(ctx)
	if !svc.RadioExternalArtEnabled() {
		t.Fatal("the external rung did not come on")
	}
}

// setRadioExternalArt flips the toggle the way the admin endpoint does,
// forget and all, so a test sees what an operator's switch does.
func setRadioExternalArt(t *testing.T, ctx context.Context, svc *Library, on bool) {
	t.Helper()
	if err := svc.db.SettingSet(ctx, settingRadioExternalArt, strconv.FormatBool(on), time.Now().UnixNano()); err != nil {
		t.Fatalf("setting the external rung: %v", err)
	}
	svc.loadRuntimeToggles(ctx)
	if !on {
		svc.forgetRadioArt()
	}
}

// gatedRadioArt holds its answer until the test lets it go, which is how
// a lookup gets to still be running when the toggle moves.
type gatedRadioArt struct {
	gate <-chan struct{}
	data []byte
	mime string
}

func (g *gatedRadioArt) FrontCover(ctx context.Context, _, _ string) (providers.TitleCoverResult, error) {
	select {
	case <-g.gate:
		return providers.TitleCoverResult{Data: g.data, MIME: g.mime}, nil
	case <-ctx.Done():
		return providers.TitleCoverResult{}, ctx.Err()
	}
}

// TestRadioArtQueriesWhatItKeysOn is the normalization seam. The key is
// built from the normalized artist and title; the upstream query has to
// be built from the same values, or two spellings of one track collapse
// onto one entry while whichever arrived first decides the search - and
// the noisy spelling is the one MusicBrainz misses, so it could cache a
// day-long miss against a key the clean spelling would have resolved.
func TestRadioArtQueriesWhatItKeysOn(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newCatalogFixture(t)
	resolver := &fakeRadioArt{data: coverPNG(t, 40), mime: "image/png"}
	svc.radioArtResolver = resolver
	enableRadioExternalArt(t, ctx, svc)

	svc.EnsureRadioNowPlayingArt("Test FM", "Charlie Parker - Ornithology (Official Audio)")
	waitForRadioArt(t, svc, "Charlie Parker", "Ornithology")

	asked := resolver.queries()
	if len(asked) != 1 {
		t.Fatalf("upstream was asked %d times, want 1", len(asked))
	}
	if got := asked[0]; got[0] != "charlie parker" || got[1] != "ornithology" {
		t.Errorf("upstream was asked for %q / %q, want the normalized pair", got[0], got[1])
	}

	// The clean spelling is the same entry, so it costs no second call.
	if key := svc.EnsureRadioNowPlayingArt("Test FM", "Charlie Parker - Ornithology"); key == "" {
		t.Error("the clean spelling did not resolve to the entry the noisy one filled")
	}
	if got := resolver.calls.Load(); got != 1 {
		t.Errorf("upstream was asked %d times across two spellings, want 1", got)
	}
}

// TestRadioArtCacheIsBoundedByBytes is the resident ceiling. An entry
// count times the fetch cap is a ceiling in the gigabytes, which is why
// the station-logo cache next door counts bytes; this one has to as
// well.
func TestRadioArtCacheIsBoundedByBytes(t *testing.T) {
	t.Parallel()
	l := &Library{log: slog.New(slog.NewTextHandler(io.Discard, nil))}
	big := make([]byte, radioArtCacheBytes/4)
	for i := range 12 {
		l.storeRadioArt(radioArtKey("artist", string(rune('a'+i))), radioArtEntry{
			art:     radioLogoFromBytes(big, "image/png"),
			fetched: time.Now(),
			fresh:   radioArtFreshFor,
		})
	}
	if l.radioArtCache.bytes > radioArtCacheBytes {
		t.Errorf("cache holds %d bytes, over the %d budget", l.radioArtCache.bytes, radioArtCacheBytes)
	}
	if len(l.radioArtCache.entries) != len(l.radioArtCache.order) {
		t.Errorf("the map holds %d entries and the order list %d",
			len(l.radioArtCache.entries), len(l.radioArtCache.order))
	}
}

// TestRadioArtDropsStaleOnRead is the other half of the ceiling. A
// server that met a few hundred titles and then went quiet inserts
// nothing, so eviction-on-insert never runs and every image body stays
// resident for the life of the process.
func TestRadioArtDropsStaleOnRead(t *testing.T) {
	t.Parallel()
	l := &Library{log: slog.New(slog.NewTextHandler(io.Discard, nil))}
	key := radioArtKey("artist", "title")
	l.storeRadioArt(key, radioArtEntry{
		art:     radioLogoFromBytes(coverPNG(t, 40), "image/png"),
		fetched: time.Now().Add(-2 * radioArtFreshFor),
		fresh:   radioArtFreshFor,
	})
	if _, ok := l.cachedRadioArt(key); ok {
		t.Fatal("a stale entry answered as a hit")
	}
	if len(l.radioArtCache.entries) != 0 || l.radioArtCache.bytes != 0 {
		t.Errorf("the stale entry survived the read: %d entries, %d bytes",
			len(l.radioArtCache.entries), l.radioArtCache.bytes)
	}
}

// TestRadioArtIsNotServedWhileOff is the toggle governing the read as
// well as the fetch: an operator who switches the rung off must stop
// serving third-party covers from their own origin, not keep serving
// what is already cached for the week the entry stays fresh.
func TestRadioArtIsNotServedWhileOff(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newCatalogFixture(t)
	resolver := &fakeRadioArt{data: coverPNG(t, 40), mime: "image/png"}
	svc.radioArtResolver = resolver
	enableRadioExternalArt(t, ctx, svc)

	svc.EnsureRadioNowPlayingArt("Test FM", "Charlie Parker - Ornithology")
	waitForRadioArt(t, svc, "Charlie Parker", "Ornithology")
	key := svc.EnsureRadioNowPlayingArt("Test FM", "Charlie Parker - Ornithology")
	if key == "" {
		t.Fatal("the lookup never landed")
	}
	if _, err := svc.RadioNowPlayingArt(key); err != nil {
		t.Fatalf("the cover does not serve while the rung is on: %v", err)
	}

	cur, err := svc.AdminSettingsGet(ctx)
	if err != nil {
		t.Fatal(err)
	}
	cur.RadioExternalArt = false
	if _, err := svc.AdminSettingsPut(ctx, nil, cur); err != nil {
		t.Fatalf("switching the rung off: %v", err)
	}
	if _, err := svc.RadioNowPlayingArt(key); KindOf(err) != KindNotFound {
		t.Errorf("a cached cover still served with the rung off: %v", err)
	}
	// And the bytes are gone, not merely unreachable.
	if len(svc.radioArtCache.entries) != 0 {
		t.Errorf("%d cached covers survived the switch", len(svc.radioArtCache.entries))
	}
}

// deadlineRadioArt stands in for a walk that runs out of budget: it
// holds until its context ends and answers with that.
type deadlineRadioArt struct{ calls atomic.Int64 }

func (d *deadlineRadioArt) FrontCover(ctx context.Context, _, _ string) (providers.TitleCoverResult, error) {
	d.calls.Add(1)
	<-ctx.Done()
	return providers.TitleCoverResult{}, ctx.Err()
}

// waitForRadioArtLookupToSettle blocks until the detached worker has
// released its claim, so a test asserts on what it left rather than
// racing it.
func waitForRadioArtLookupToSettle(t *testing.T, svc *Library, key string) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for {
		svc.radioArtCache.mu.Lock()
		inFlight := svc.radioArtCache.inFlight[key]
		svc.radioArtCache.mu.Unlock()
		if !inFlight {
			return
		}
		if time.Now().After(deadline) {
			t.Fatal("the artwork lookup never released its claim")
		}
		time.Sleep(time.Millisecond)
	}
}

// An upstream that cannot answer inside the budget is upstream failing,
// and is remembered for as long: shorter, and a doomed title spends half
// its wall clock walking a service that paces at a request a second.
func TestRadioArtBacksOffWhenTheBudgetIsSpent(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newCatalogFixture(t)
	enableRadioExternalArt(t, ctx, svc)
	svc.radioArtBudget = 20 * time.Millisecond
	resolver := &deadlineRadioArt{}
	svc.radioArtResolver = resolver

	key := radioArtKey(radioSearchField("Charlie Parker"), radioSearchField("Ornithology"))
	svc.EnsureRadioNowPlayingArt("Test FM", "Charlie Parker - Ornithology")
	waitForRadioArtLookupToSettle(t, svc, key)

	entry, ok := svc.cachedRadioArt(key)
	if !ok {
		t.Fatal("a budget timeout cached nothing, so every poll starts another walk")
	}
	if entry.fresh != radioArtFailureFreshFor {
		t.Errorf("a budget timeout cached for %v, want %v", entry.fresh, radioArtFailureFreshFor)
	}
	if entry.fresh <= radioArtLookupBudget {
		t.Errorf("the backoff is %v against a %v budget, so a doomed title spends "+
			"half its wall clock walking", entry.fresh, radioArtLookupBudget)
	}
	// The backoff holds the retry off while it stands, so the poll behind
	// it does not start a second walk.
	svc.EnsureRadioNowPlayingArt("Test FM", "Charlie Parker - Ornithology")
	if got := resolver.calls.Load(); got != 1 {
		t.Fatalf("upstream was asked %d times, want 1 while the backoff stands", got)
	}
}

// The distinction that stands: upstream answering badly is remembered for
// minutes, upstream answering emptily for a day.
func TestRadioArtBacksOffWhenUpstreamFails(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newCatalogFixture(t)
	enableRadioExternalArt(t, ctx, svc)
	svc.radioArtResolver = &fakeRadioArt{err: errors.New("502 from the archive")}

	svc.EnsureRadioNowPlayingArt("Test FM", "Nobody - Unreachable")
	failed := waitForRadioArt(t, svc, "Nobody", "Unreachable")
	if failed.fresh != radioArtFailureFreshFor {
		t.Errorf("a reach failure cached for %v, want %v", failed.fresh, radioArtFailureFreshFor)
	}
}

// A worker outlives the toggle it started under, so it asks again on the
// way out: without that, bytes fetched from a third party sit resident
// for a week past the operator saying stop, and nothing evicts them.
func TestRadioArtStoresNothingWhenTheToggleWentOffMidLookup(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newCatalogFixture(t)
	enableRadioExternalArt(t, ctx, svc)
	gate := make(chan struct{})
	svc.radioArtResolver = &gatedRadioArt{gate: gate, data: coverPNG(t, 40), mime: "image/png"}
	var woke atomic.Int64
	svc.SetRadioInvalidator(func() { woke.Add(1) })

	key := radioArtKey(radioSearchField("Charlie Parker"), radioSearchField("Ornithology"))
	svc.EnsureRadioNowPlayingArt("Test FM", "Charlie Parker - Ornithology")
	setRadioExternalArt(t, ctx, svc, false)
	close(gate)
	waitForRadioArtLookupToSettle(t, svc, key)

	if entry, ok := svc.cachedRadioArt(key); ok {
		t.Fatalf("%d bytes landed after the rung was switched off", len(entry.art.Bytes))
	}
	if got := woke.Load(); got != 0 {
		t.Errorf("woke listeners %d times for a cover nothing may serve, want 0", got)
	}
}

// A cover that lands wakes listening clients, which is what saves the
// face a poll interval: the lookup finishes seconds after the poll that
// started it, and without this the key waits out the next one.
func TestRadioArtWakesListenersWhenACoverLands(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newCatalogFixture(t)
	enableRadioExternalArt(t, ctx, svc)
	var woke atomic.Int64
	svc.SetRadioInvalidator(func() { woke.Add(1) })
	svc.radioArtResolver = &fakeRadioArt{data: coverPNG(t, 40), mime: "image/png"}

	key := radioArtKey(radioSearchField("Charlie Parker"), radioSearchField("Ornithology"))
	svc.EnsureRadioNowPlayingArt("Test FM", "Charlie Parker - Ornithology")
	// Settled rather than cached: the store and the wake are two
	// statements, and a wait on the first can read the counter before the
	// second runs. The claim is released after both.
	waitForRadioArtLookupToSettle(t, svc, key)
	if entry, _ := svc.cachedRadioArt(key); len(entry.art.Bytes) == 0 {
		t.Fatal("the cover never landed")
	}
	if got := woke.Load(); got != 1 {
		t.Fatalf("woke listeners %d times, want 1", got)
	}
}

// A miss changes nothing a client could draw, so it wakes nobody: the
// frame is broadcast to every connection, and one per fruitless lookup
// would be a poll storm across listeners it does not concern.
func TestRadioArtDoesNotWakeListenersOnAMiss(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newCatalogFixture(t)
	enableRadioExternalArt(t, ctx, svc)
	var woke atomic.Int64
	svc.SetRadioInvalidator(func() { woke.Add(1) })
	svc.radioArtResolver = &fakeRadioArt{err: ErrNoRadioArt}

	key := radioArtKey(radioSearchField("Nobody"), radioSearchField("Unreleased"))
	svc.EnsureRadioNowPlayingArt("Test FM", "Nobody - Unreleased")
	waitForRadioArtLookupToSettle(t, svc, key)
	if got := woke.Load(); got != 0 {
		t.Fatalf("woke listeners %d times on a miss, want 0", got)
	}
}

// forgetfulRadioArt is a resolver that keeps a memory of its own, which
// is what the operator's purge has to be able to reach.
type forgetfulRadioArt struct {
	fakeRadioArt
	forgot atomic.Int64
}

func (f *forgetfulRadioArt) ForgetMisses() { f.forgot.Add(1) }

// Switching the rung off purges the resolver's memory too. Without it
// the service cache empties, the search re-runs, and a day-old private
// map answers for every release before anything reaches the network.
func TestRadioArtForgetReachesTheResolver(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newCatalogFixture(t)
	enableRadioExternalArt(t, ctx, svc)
	resolver := &forgetfulRadioArt{}
	svc.radioArtResolver = resolver

	setRadioExternalArt(t, ctx, svc, false)

	if got := resolver.forgot.Load(); got != 1 {
		t.Fatalf("the resolver was purged %d times, want 1", got)
	}
}
