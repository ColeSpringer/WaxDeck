package service

import (
	"sync"
	"testing"
	"time"
)

// A Library with nothing but the logo cache wired, which is all these
// methods touch.
func newLogoCacheLibrary() *Library {
	return &Library{
		radioLogos:       map[string]radioLogo{},
		radioLogoFlights: map[string]chan struct{}{},
	}
}

// The cache read as production reads it, without claiming a fetch the way
// [Library.claimRadioLogo] does.
func cachedLogo(l *Library, apiStationPID string) (RadioLogo, bool) {
	l.radioLogosMu.Lock()
	defer l.radioLogosMu.Unlock()
	return l.freshRadioLogoLocked(apiStationPID)
}

// The logo cache's own behaviour, exercised directly: these methods touch
// nothing but the cache fields, so they need no database behind them.
func TestRadioLogoCache(t *testing.T) {
	l := newLogoCacheLibrary()
	hit := RadioLogo{Bytes: []byte("bytes"), MimeType: "image/png", ETag: `"x"`}

	l.storeRadioLogo("rs-1", hit)
	got, ok := cachedLogo(l, "rs-1")
	if !ok || string(got.Bytes) != "bytes" {
		t.Fatalf("cached = %+v, ok = %v", got, ok)
	}

	// A miss is cached too, and is told apart from "not cached" by the
	// second return rather than by the bytes: the caller has to know the
	// difference between "asked and there is nothing" and "never asked".
	l.storeRadioLogo("rs-2", RadioLogo{})
	got, ok = cachedLogo(l, "rs-2")
	if !ok || len(got.Bytes) != 0 {
		t.Fatalf("cached miss = %+v, ok = %v", got, ok)
	}
	if _, ok := cachedLogo(l, "rs-3"); ok {
		t.Fatal("a station never fetched must not report a cache hit")
	}

	// Misses go stale sooner than hits, so a host that comes back is drawn
	// within the hour rather than the day.
	l.radioLogos["rs-1"] = radioLogo{logo: hit, fetched: time.Now().Add(-2 * time.Hour)}
	l.radioLogos["rs-2"] = radioLogo{fetched: time.Now().Add(-2 * time.Hour)}
	if _, ok := cachedLogo(l, "rs-1"); !ok {
		t.Fatal("a two-hour-old hit is still fresh for a day")
	}
	if _, ok := cachedLogo(l, "rs-2"); ok {
		t.Fatal("a two-hour-old miss should have gone stale")
	}

	// Editing a station's logo URL drops its entry: the cache is keyed by
	// pid, which an edit does not change, so a new URL would otherwise be
	// shadowed by a day-old copy of the old one.
	l.forgetRadioLogo("rs-1")
	if _, ok := cachedLogo(l, "rs-1"); ok {
		t.Fatal("a forgotten logo must be re-fetched")
	}
	if l.radioLogosBytes != 0 {
		t.Fatalf("byte total = %d after forgetting the only sized entry", l.radioLogosBytes)
	}
}

// A re-fetch goes to the back of the eviction order. Left where it was, a
// logo fetched a moment ago would be evicted ahead of one cached hours
// earlier, which is the opposite of what the order is for.
func TestRadioLogoCacheReorder(t *testing.T) {
	l := newLogoCacheLibrary()
	for _, pid := range []string{"rs-1", "rs-2", "rs-3"} {
		l.storeRadioLogo(pid, RadioLogo{Bytes: []byte("x")})
	}
	l.storeRadioLogo("rs-1", RadioLogo{Bytes: []byte("y")})

	want := []string{"rs-2", "rs-3", "rs-1"}
	if len(l.radioLogosOrder) != len(want) {
		t.Fatalf("order = %v, want %v", l.radioLogosOrder, want)
	}
	for i, pid := range want {
		if l.radioLogosOrder[i] != pid {
			t.Fatalf("order = %v, want %v", l.radioLogosOrder, want)
		}
	}
	// One entry per pid, however many times it is stored.
	if len(l.radioLogos) != 3 || l.radioLogosBytes != 3 {
		t.Fatalf("entries = %d, bytes = %d, want 3 and 3", len(l.radioLogos), l.radioLogosBytes)
	}
}

// One fetch at a time per station: the second caller is handed the
// first's channel rather than a claim of its own, and gets nothing until
// the first releases it.
func TestRadioLogoSingleFlight(t *testing.T) {
	l := newLogoCacheLibrary()

	if _, hit, wait := l.claimRadioLogo("rs-1"); hit || wait != nil {
		t.Fatal("the first caller for an uncached station owns the fetch")
	}
	_, hit, wait := l.claimRadioLogo("rs-1")
	if hit || wait == nil {
		t.Fatal("a second caller must be handed the running fetch to wait on")
	}
	select {
	case <-wait:
		t.Fatal("the wait must not be open before the fetch is released")
	default:
	}

	// Releasing wakes the waiter, and the answer it then reads is the one
	// the owner stored.
	l.storeRadioLogo("rs-1", RadioLogo{Bytes: []byte("bytes")})
	l.endRadioLogoFetch("rs-1")
	<-wait
	got, hit, _ := l.claimRadioLogo("rs-1")
	if !hit || string(got.Bytes) != "bytes" {
		t.Fatalf("after the wait: cached = %+v, hit = %v", got, hit)
	}

	// The released flight is gone, so the next stale read claims a fresh
	// one rather than waiting on a channel nobody will close again.
	l.radioLogos["rs-1"] = radioLogo{fetched: time.Now().Add(-2 * time.Hour)}
	if _, _, wait := l.claimRadioLogo("rs-1"); wait != nil {
		t.Fatal("a claim after a release must own the next fetch")
	}
}

// A failure never replaces a logo that is still good. Two callers racing
// on one station can both reach the store, and of two answers about the
// same station the one with a picture in it is the one to keep.
func TestRadioLogoMissDoesNotClobberHit(t *testing.T) {
	l := newLogoCacheLibrary()
	l.storeRadioLogo("rs-1", RadioLogo{Bytes: []byte("bytes"), MimeType: "image/png"})
	l.storeRadioLogo("rs-1", RadioLogo{})

	got, ok := cachedLogo(l, "rs-1")
	if !ok || string(got.Bytes) != "bytes" {
		t.Fatalf("cached = %+v, ok = %v; a miss overwrote a fresh hit", got, ok)
	}
	if l.radioLogosBytes != len("bytes") {
		t.Fatalf("byte total = %d, want %d", l.radioLogosBytes, len("bytes"))
	}

	// Once the hit has gone stale the miss is the newer truth: a station
	// whose host went away stops drawing rather than drawing forever.
	l.radioLogos["rs-1"] = radioLogo{
		logo:    RadioLogo{Bytes: []byte("bytes")},
		fetched: time.Now().Add(-48 * time.Hour),
	}
	l.storeRadioLogo("rs-1", RadioLogo{})
	if got, ok := cachedLogo(l, "rs-1"); !ok || len(got.Bytes) != 0 {
		t.Fatalf("cached = %+v, ok = %v; a stale hit should give way", got, ok)
	}
}

// Nothing in the cache path races: the store and the claim take the same
// lock, so the detector has to agree under -race.
func TestRadioLogoCacheConcurrent(t *testing.T) {
	l := newLogoCacheLibrary()
	var wg sync.WaitGroup
	for i := range 8 {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			pid := "rs-" + string(rune('a'+i%3))
			if _, hit, wait := l.claimRadioLogo(pid); !hit && wait == nil {
				l.storeRadioLogo(pid, RadioLogo{Bytes: []byte("x")})
				l.endRadioLogoFetch(pid)
			}
		}(i)
	}
	wg.Wait()
	if len(l.radioLogoFlights) != 0 {
		t.Fatalf("flights left standing: %v", l.radioLogoFlights)
	}
}

// The byte budget evicts oldest-first, and never empties itself: the
// entry just stored is the one the caller is about to serve.
func TestRadioLogoCacheEvicts(t *testing.T) {
	l := newLogoCacheLibrary()
	big := make([]byte, radioLogoCacheBytes/2+1)
	l.storeRadioLogo("rs-old", RadioLogo{Bytes: big})
	l.storeRadioLogo("rs-new", RadioLogo{Bytes: big})

	if _, ok := cachedLogo(l, "rs-old"); ok {
		t.Fatal("the older entry should have been evicted by the budget")
	}
	if _, ok := cachedLogo(l, "rs-new"); !ok {
		t.Fatal("the entry just stored must survive its own eviction pass")
	}
	if l.radioLogosBytes != len(big) {
		t.Fatalf("byte total = %d, want %d", l.radioLogosBytes, len(big))
	}
}
