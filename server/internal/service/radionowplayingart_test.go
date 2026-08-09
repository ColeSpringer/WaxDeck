package service

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// fakeRadioArt stands in for the MusicBrainz plus Cover Art Archive
// pair, counting calls so the tests can assert what did and did not go
// out over the wire.
type fakeRadioArt struct {
	calls atomic.Int64
	data  []byte
	mime  string
	err   error

	mu    sync.Mutex
	asked [][2]string
}

func (f *fakeRadioArt) FrontCover(ctx context.Context, artist, title string) ([]byte, string, error) {
	f.calls.Add(1)
	f.mu.Lock()
	f.asked = append(f.asked, [2]string{artist, title})
	f.mu.Unlock()
	if f.err != nil {
		return nil, "", f.err
	}
	return f.data, f.mime, nil
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

func (b *blockingRadioArt) FrontCover(ctx context.Context, artist, title string) ([]byte, string, error) {
	close(b.started)
	<-ctx.Done()
	close(b.cancelled)
	return nil, "", ctx.Err()
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
