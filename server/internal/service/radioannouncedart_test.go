package service

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"
)

// waitForAnnouncedArt polls the cache until the detached fetch lands.
func waitForAnnouncedArt(t *testing.T, svc *Library, artURL, announced string) radioArtEntry {
	t.Helper()
	key := announcedArtKey(artURL, announced)
	deadline := time.Now().Add(5 * time.Second)
	for {
		if entry, ok := svc.cachedRadioArt(key); ok {
			return entry
		}
		if time.Now().After(deadline) {
			t.Fatal("the announced artwork fetch never landed")
		}
		time.Sleep(5 * time.Millisecond)
	}
}

// artHost serves one body under one content type, counting requests.
func artHost(t *testing.T, hits *atomic.Int64, mime string, body []byte) *httptest.Server {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		hits.Add(1)
		w.Header().Set("Content-Type", mime)
		w.Write(body)
	}))
	t.Cleanup(srv.Close)
	return srv
}

// The rung the whole feature is for: a station that names its own cover
// gets that cover drawn, and nothing about this library leaves the
// building to make it happen -- which is why the external toggle, off
// here as it is by default, has no say in it.
func TestAnnouncedArtIsServedWithTheExternalRungOff(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newCatalogFixture(t)
	svc.allowPrivateRadioHosts = true
	var hits atomic.Int64
	host := artHost(t, &hits, "image/png", coverPNG(t, 60))

	// Switched off on purpose. The rung below ships on now, so "off" is
	// the household that opted out - and this rung has to keep drawing
	// for them, because nothing was sent anywhere to fill it.
	disableRadioExternalArt(t, ctx, svc)

	// The first poll starts the fetch and holds the rung below: the
	// station's own answer is seconds away and is the better one.
	key, tryExternal := svc.EnsureRadioAnnouncedArt(host.URL+"/cover.png", "Fixture - Song")
	if key != "" || tryExternal {
		t.Fatalf("first poll = (%q, %v), want the fetch started and the rung held", key, tryExternal)
	}
	entry := waitForAnnouncedArt(t, svc, host.URL+"/cover.png", "Fixture - Song")
	if len(entry.art.Bytes) == 0 || !entry.announced {
		t.Fatalf("landed entry = %d bytes, announced = %v", len(entry.art.Bytes), entry.announced)
	}

	// Ten more polls, as a household on one station makes: one fetch.
	for range 10 {
		key, tryExternal = svc.EnsureRadioAnnouncedArt(host.URL+"/cover.png", "Fixture - Song")
		if key == "" || tryExternal {
			t.Fatalf("later poll = (%q, %v), want the cached key", key, tryExternal)
		}
	}
	if got := hits.Load(); got != 1 {
		t.Fatalf("station was asked %d times, want 1", got)
	}

	// And the endpoint serves it with the toggle off, which is the
	// difference between this rung and the one below.
	art, err := svc.RadioNowPlayingArt(key)
	if err != nil || len(art.Bytes) == 0 {
		t.Fatalf("serving announced art = %v (%d bytes)", err, len(art.Bytes))
	}
	if art.MimeType != "image/png" {
		t.Fatalf("served type = %q, want the sniffed one", art.MimeType)
	}

	// An operator switching the external rung off drops what was fetched
	// from a third party and keeps what the station announced: the
	// decision was about talking to musicbrainz.org.
	svc.forgetRadioArt()
	if _, err := svc.RadioNowPlayingArt(key); err != nil {
		t.Fatalf("announced art should survive the forget: %v", err)
	}
}

// A station that puts its homepage in StreamUrl -- which many do, on
// every single track -- must not lose its external cover for it. The
// failure is remembered so the fetch is not repeated, and it yields the
// rung below immediately rather than holding it.
func TestAnnouncedArtFailureYieldsToTheExternalRung(t *testing.T) {
	t.Parallel()
	_, svc, _ := newCatalogFixture(t)
	svc.allowPrivateRadioHosts = true
	var hits atomic.Int64
	host := artHost(t, &hits, "text/html", []byte("<html><body>Station of the year</body></html>"))

	if key, tryExternal := svc.EnsureRadioAnnouncedArt(host.URL, "Fixture - Song"); key != "" || tryExternal {
		t.Fatalf("first poll = (%q, %v), want the fetch started and the rung held", key, tryExternal)
	}
	entry := waitForAnnouncedArt(t, svc, host.URL, "Fixture - Song")
	if len(entry.art.Bytes) != 0 {
		t.Fatal("markup should not have been stored as artwork")
	}
	// HTML today is HTML tomorrow, so the refusal is remembered for a
	// day rather than for the minutes a timeout gets.
	if entry.fresh != radioArtMissFreshFor {
		t.Fatalf("failure kept for %v, want the day a sniff refusal gets", entry.fresh)
	}

	// Every later poll answers at once and lets the external rung have
	// its turn, without asking the station host again.
	for range 10 {
		key, tryExternal := svc.EnsureRadioAnnouncedArt(host.URL, "Fixture - Song")
		if key != "" || !tryExternal {
			t.Fatalf("cached failure = (%q, %v), want the external rung offered", key, tryExternal)
		}
	}
	if got := hits.Load(); got != 1 {
		t.Fatalf("station was asked %d times, want 1", got)
	}
}

// Junk in the key costs nothing: no request, no cached failure, and the
// rung below is not held for it.
func TestAnnouncedArtIgnoresWhatIsNotAURL(t *testing.T) {
	t.Parallel()
	_, svc, _ := newCatalogFixture(t)
	for _, announced := range []string{
		"", "-", "no", "ftp://example.invalid/cover.png", "javascript:alert(1)", "http://",
	} {
		key, tryExternal := svc.EnsureRadioAnnouncedArt(announced, "Fixture - Song")
		if key != "" || !tryExternal {
			t.Fatalf("announced %q = (%q, %v), want it skipped and the rung offered", announced, key, tryExternal)
		}
		if _, cached := svc.cachedRadioArt(announcedArtKey(announced, "Fixture - Song")); cached {
			t.Fatalf("announced %q cached a failure it never fetched", announced)
		}
	}
}

// The art belongs to the announcement, not to the station. A song
// announced with a cover followed by one announced without leaves no
// cover behind: a bumper must not wear the last song's sleeve.
func TestAnnouncedArtDoesNotStickToTheNextSong(t *testing.T) {
	t.Parallel()
	_, svc, _ := newCatalogFixture(t)

	svc.NoteRadioMeta("rs-1", "Charlie Parker - Ornithology", "https://art.example/orn.png")
	title, artURL := svc.RadioNowPlayingMeta("rs-1")
	if title != "Charlie Parker - Ornithology" || artURL != "https://art.example/orn.png" {
		t.Fatalf("first announcement = (%q, %q)", title, artURL)
	}

	svc.NoteRadioMeta("rs-1", "Station ident", "")
	title, artURL = svc.RadioNowPlayingMeta("rs-1")
	if title != "Station ident" || artURL != "" {
		t.Fatalf("artless announcement = (%q, %q), want the picture cleared with it", title, artURL)
	}
}

// A logo the station named in its own connect headers is tried before
// the discovery walk, and a hint that does not answer costs the station
// nothing: the walk still runs.
func TestRadioLogoHintIsTriedBeforeDiscovery(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	svc.allowPrivateRadioHosts = true
	var hits atomic.Int64
	host := artHost(t, &hits, "image/png", coverPNG(t, 90))

	station, err := svc.CreateRadioStation(ctx, uc, RadioStationEdit{
		Name: "Hint FM", StreamURL: "http://198.51.100.9/stream",
	})
	if err != nil {
		t.Fatal(err)
	}
	svc.NoteRadioLogoHint(station.PID, host.URL+"/logo.png")

	logo, err := svc.RadioStationLogo(ctx, station.PID)
	if err != nil || len(logo.Bytes) == 0 {
		t.Fatalf("hinted logo = %v (%d bytes)", err, len(logo.Bytes))
	}
	if got := hits.Load(); got != 1 {
		t.Fatalf("hint host asked %d times, want 1", got)
	}
}

// The station a hint arrives for is exactly the one that has "no logo"
// cached: the dial painted, discovery came up empty, and the answer was
// remembered for an hour. The hint has to clear that, or it sits unread
// for the whole hour it exists to save.
func TestRadioLogoHintClearsACachedMiss(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	svc.allowPrivateRadioHosts = true
	var hits atomic.Int64
	host := artHost(t, &hits, "image/png", coverPNG(t, 70))

	station, err := svc.CreateRadioStation(ctx, uc, RadioStationEdit{
		Name: "Late Hint FM", StreamURL: "http://198.51.100.11/stream",
	})
	if err != nil {
		t.Fatal(err)
	}

	// The dial paints first and finds nothing, which is remembered.
	if _, err := svc.RadioStationLogo(ctx, station.PID); err == nil {
		t.Fatal("a station with no logo anywhere should answer not-found")
	}
	if _, cached := cachedLogo(svc, station.PID); !cached {
		t.Fatal("the miss should have been remembered")
	}

	// Then somebody plays it and the station names its mark.
	svc.NoteRadioLogoHint(station.PID, host.URL+"/mark.png")
	logo, err := svc.RadioStationLogo(ctx, station.PID)
	if err != nil || len(logo.Bytes) == 0 {
		t.Fatalf("hinted logo after a cached miss = %v (%d bytes)", err, len(logo.Bytes))
	}

	// Deleting the station takes the hint with it, so the map cannot
	// grow with every station ever streamed.
	if err := svc.DeleteRadioStation(ctx, station.PID); err != nil {
		t.Fatal(err)
	}
	if got := svc.radioLogoHint(station.PID); got != "" {
		t.Fatalf("hint survived the delete: %q", got)
	}
}

// Misses and failures weigh nothing, so the byte ceiling cannot see
// them. A station that cache-busts its cover mints a fresh key every
// poll, and without a count bound that is a map with no ceiling at all.
func TestRadioArtCacheBoundsEntryCount(t *testing.T) {
	t.Parallel()
	l := &Library{}
	for i := range radioArtCacheEntries + 500 {
		l.storeRadioArt(fmt.Sprintf("key-%d", i), radioArtEntry{
			fetched: time.Now(), fresh: radioArtMissFreshFor, announced: true,
		})
	}
	l.radioArtCache.mu.Lock()
	entries, order := len(l.radioArtCache.entries), len(l.radioArtCache.order)
	l.radioArtCache.mu.Unlock()
	if entries > radioArtCacheEntries || order > radioArtCacheEntries {
		t.Fatalf("cache holds %d entries / %d order, want at most %d",
			entries, order, radioArtCacheEntries)
	}
	// The newest survive: eviction is oldest-first.
	if _, ok := l.cachedRadioArt(fmt.Sprintf("key-%d", radioArtCacheEntries+499)); !ok {
		t.Fatal("the most recent entry was evicted")
	}
}

// A channel logo announced on every track is the station's mark, not the
// song's cover. Ranked as a cover it would sit on the full-screen face
// forever and outrank the lookup that finds the actual sleeve, so it is
// demoted to the rung that wanted it all along.
func TestRepeatedAnnouncedPictureBecomesTheStationLogo(t *testing.T) {
	t.Parallel()
	_, svc, _ := newCatalogFixture(t)
	const logo = "https://somafm.example/logos/groovesalad.jpg"

	// One song with a picture: nothing yet says it is fixed.
	svc.NoteRadioMeta("rs-1", "Tetris - Green Hair", logo)
	if _, art := svc.RadioNowPlayingMeta("rs-1"); art != logo {
		t.Fatalf("first announcement art = %q, want the announced picture", art)
	}

	// The same picture against a different song is a mark.
	svc.NoteRadioMeta("rs-1", "Fascinating Earthbound Objects - Charm", logo)
	if _, art := svc.RadioNowPlayingMeta("rs-1"); art != "" {
		t.Fatalf("repeated picture still offered as cover art: %q", art)
	}
	if got := svc.radioLogoHint("rs-1"); got != logo {
		t.Fatalf("logo hint = %q, want the station's own mark", got)
	}

	// A station whose picture moves with the title keeps its covers.
	svc.NoteRadioMeta("rs-2", "Savoy Brown - I'm Tired", "https://rp.example/9696.jpg")
	svc.NoteRadioMeta("rs-2", "Jay Farrar - Vitamins", "https://rp.example/14411.jpg")
	if _, art := svc.RadioNowPlayingMeta("rs-2"); art != "https://rp.example/14411.jpg" {
		t.Fatalf("per-track art = %q, want the current song's cover", art)
	}
}

// One stable path serving mutable bytes is a common automation, so the
// token has to move with the song or the client draws one cover for the
// life of its cache.
func TestAnnouncedArtKeyMovesWithTheTitle(t *testing.T) {
	t.Parallel()
	const url = "https://station.example/nowplaying.jpg"
	first := announcedArtKey(url, "Artist - One")
	second := announcedArtKey(url, "Artist - Two")
	if first == second {
		t.Fatal("one URL and two songs share a key, so the picture cannot change")
	}
	if announcedArtKey(url, "Artist - One") != first {
		t.Fatal("the same announcement must key the same way twice")
	}
}
