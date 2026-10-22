package service

import (
	"context"
	"errors"
	"testing"
)

// failing is a fallback hook failing the named reads.
func failing(reads ...string) func(string) error {
	return func(read string) error {
		for _, r := range reads {
			if r == read {
				return errors.New("disk on fire")
			}
		}
		return nil
	}
}

// A sweep whose advisory read failed is served without its explicit
// flags, and never kept: the next sweep, with the store well again,
// carries them.
func TestASweepOverAFailedAdvisoryReadIsNotKept(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newAdvisoryFixture(t)
	settleCatalogFeed(t, svc)
	flagged := func() bool {
		t.Helper()
		rows, err := svc.TrackFacts(ctx, uc)
		if err != nil {
			t.Fatal(err)
		}
		for _, r := range rows {
			if r.Title == "Flagged" {
				return r.Explicit
			}
		}
		t.Fatal("no Flagged track in the sweep")
		return false
	}
	svc.trackFacts.fallbackHook = failing("advisory tags")
	if flagged() {
		t.Fatal("a sweep whose advisory read failed still flagged the track")
	}
	svc.trackFacts.fallbackHook = nil
	if !flagged() {
		t.Fatal("the sweep made over the failed advisory read was kept")
	}
}

// A genre enumeration whose vocabulary read failed shows the stored
// labels for that request and is not kept for the next caller.
func TestAGenreEnumerationOverAFailedVocabularyReadIsNotKept(t *testing.T) {
	t.Parallel()
	f := newGenreFixture(t)
	f.sweepToQuiet(t)
	settleCatalogFeed(t, f.svc)
	f.svc.trackFacts.fallbackHook = failing("genre vocabulary")
	facetsOf(t, f, "genre")
	if servesFromCache(f.svc, "genre") {
		t.Fatal("the enumeration made over a failed vocabulary read was kept")
	}
	f.svc.trackFacts.fallbackHook = nil
	var canonical bool
	for _, b := range facetsOf(t, f, "genre") {
		canonical = canonical || b.Label == "Hip Hop"
	}
	if !canonical || !servesFromCache(f.svc, "genre") {
		t.Fatalf("the next enumeration: canonical label %v, kept %v; want both", canonical, servesFromCache(f.svc, "genre"))
	}
}

// A read that falls back tells every watcher it runs under, a sweep and a
// listing alike, and one that does not leaves them clear.
func TestAFallbackReachesItsWatchers(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newAdvisoryFixture(t)
	kid := &UserCtx{ID: uc.ID, CatalogPID: uc.CatalogPID, AllLibraries: true, Explicit: true,
		TagDeny: []TagRule{{Key: advisoryTagKey, Value: "1"}}}
	svc.trackFacts.fallbackHook = failing("tag spellings")
	outer, outerFell := WatchDegraded(ctx)
	inner, innerFell := WatchDegraded(outer)
	if _, err := svc.TrackFacts(inner, kid); err != nil {
		t.Fatal(err)
	}
	if !innerFell() || !outerFell() {
		t.Fatalf("a sweep over a failed spelling read: inner %v, outer %v; want both told", innerFell(), outerFell())
	}

	svc.trackFacts.fallbackHook = nil
	well, wellFell := WatchDegraded(ctx)
	if _, err := svc.TrackFacts(well, kid); err != nil {
		t.Fatal(err)
	}
	if wellFell() {
		t.Fatal("a sweep with every read well reported a fallback")
	}

	// A vocabulary edit moves the spellings memo's generation, so the next
	// rule compiles from a fresh read.
	svc.genres.version.Add(1)
	svc.trackFacts.fallbackHook = failing("tag spellings")
	listing, listingFell := WatchDegraded(ctx)
	if _, err := svc.Browse(listing, kid, "recently-added", ItemFilter{MediaType: "music"}, 0, "", 50); err != nil {
		t.Fatal(err)
	}
	if !listingFell() {
		t.Fatal("a listing over a failed spelling read reported no fallback")
	}
}

// The follow set and a per-item tag read fall back too, an episode hidden
// or an item refused for want of an answer, and they say so.
func TestTheFollowSetAndTagReadsReportTheirFallbacks(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newAdvisoryFixture(t)
	gone, cancel := context.WithCancel(ctx)
	cancel()

	follows, followsFell := WatchDegraded(gone)
	subs := svc.newSubscriptionFilter(uc)
	subs.ensure(follows, svc)
	if !subs.failed || !followsFell() {
		t.Fatalf("a follow set that could not be read: failed %v, watcher told %v; want both", subs.failed, followsFell())
	}

	kid := &UserCtx{ID: uc.ID, CatalogPID: uc.CatalogPID, AllLibraries: true, Explicit: true,
		TagDeny: []TagRule{{Key: advisoryTagKey, Value: "1"}}}
	_, pid := fixtureTrackPID(t, ctx, svc, uc, "Unsaid")
	it, err := svc.lib.Get(ctx, pid)
	if err != nil {
		t.Fatal(err)
	}
	tags, tagsFell := WatchDegraded(gone)
	if allowed := svc.allowedByContent(tags, kid, it); allowed || !tagsFell() {
		t.Fatalf("a tag read that failed: allowed %v, watcher told %v; want refused and told", allowed, tagsFell())
	}
}
