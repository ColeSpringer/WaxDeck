package service

import (
	"context"
	"errors"
	"sync/atomic"
	"testing"
)

// The content position never goes back: a look that cannot read the log
// answers the last position a good look gave, so the caches keyed on it
// keep their entries rather than missing once on the way up and again on
// the way back.
func TestContentPositionNeverGoesBack(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newCatalogFixture(t)
	settleCatalogFeed(t, svc)
	good := svc.CatalogContentSeq(ctx)
	// The feed ahead of the last content row, as it is after any play.
	svc.trackFacts.feedHook = func() int64 { return good + 3 }
	if got := svc.CatalogContentSeq(ctx); got != good {
		t.Fatalf("a good look answered %d, want the content position %d", got, good)
	}
	svc.trackFacts.headHook = func(context.Context) (int64, error) { return 0, errors.New("catalog busy") }
	if got := svc.CatalogContentSeq(ctx); got != good {
		t.Errorf("a failed look answered %d, want the last good %d", got, good)
	}
	svc.trackFacts.headHook = nil
	if got := svc.CatalogContentSeq(ctx); got != good {
		t.Errorf("the next good look answered %d, want %d", got, good)
	}
}

// TrackFacts reads the change log before it takes the lock its cached
// sweep sits under, so a caller checking that cache never waits on
// another caller's catalog read.
func TestTrackFactsLooksAtTheLogOutsideItsLock(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	var underLock atomic.Bool
	svc.trackFacts.headHook = func(ctx context.Context) (int64, error) {
		if svc.trackFacts.mu.TryLock() {
			svc.trackFacts.mu.Unlock()
		} else {
			underLock.Store(true)
		}
		return svc.lib.LatestChangeSeq(ctx)
	}
	if _, err := svc.TrackFacts(ctx, uc); err != nil {
		t.Fatal(err)
	}
	if underLock.Load() {
		t.Fatal("a change-log look ran under the sweep cache's lock")
	}
}

// A sweep finished late never replaces one made at a newer position.
func TestTrackFactsKeepTheNewerSweep(t *testing.T) {
	t.Parallel()
	_, svc, _ := newCatalogFixture(t)
	newer := []TrackFacts{{PID: "tr-newer"}}
	svc.publishTrackFacts(9, newer)
	svc.publishTrackFacts(7, []TrackFacts{{PID: "tr-older"}})
	svc.trackFacts.mu.Lock()
	defer svc.trackFacts.mu.Unlock()
	if svc.trackFacts.tail != 9 || len(svc.trackFacts.rows) != 1 || svc.trackFacts.rows[0].PID != "tr-newer" {
		t.Fatalf("held sweep = %d %+v, want the one made at 9", svc.trackFacts.tail, svc.trackFacts.rows)
	}
}
