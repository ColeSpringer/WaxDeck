package service

import (
	"context"
	"sync"
	"sync/atomic"
	"testing"
)

// raceGenerations runs publishers that each read the generation, publish
// under it, and sometimes move it first, and reports whether the cached
// generation, seen under the cache's own lock, ever went back.
func raceGenerations(t *testing.T, svc *Library, publish func(gen facetGeneration), held func() facetGeneration) bool {
	t.Helper()
	ctx := context.Background()
	head, err := svc.lib.LatestChangeSeq(ctx)
	if err != nil {
		t.Fatal(err)
	}
	svc.Reads.CatalogContentSeq(ctx)
	svc.Reads.trackFacts.headHook = func(context.Context) (int64, error) { return head, nil }
	var (
		mu         sync.Mutex
		seen       int64
		rolledBack bool
	)
	var wg sync.WaitGroup
	for w := range 8 {
		wg.Go(func() {
			for i := range 3000 {
				if i%4 == w%4 {
					svc.Reads.genres.version.Add(1)
				}
				publish(svc.Reads.facetGeneration(ctx))
				mu.Lock()
				if v := held().vocab; v < seen {
					rolledBack = true
				} else {
					seen = v
				}
				mu.Unlock()
			}
		})
	}
	wg.Wait()
	return rolledBack
}

// A publisher holding an older generation never rolls the enumeration
// cache back past a newer publish, however the two interleave.
func TestFacetPublishesNeverRollTheCacheBack(t *testing.T) {
	t.Parallel()
	_, svc, _ := newCatalogFixture(t)
	settleCatalogFeed(t, svc)
	ctx := context.Background()
	rolled := raceGenerations(t, svc,
		func(gen facetGeneration) {
			svc.Reads.publishFacetBuckets(ctx, gen, facetCacheKey{dimension: "artist", sort: FacetSortCount}, nil)
		},
		func() facetGeneration {
			svc.Reads.facets.mu.Lock()
			defer svc.Reads.facets.mu.Unlock()
			return svc.Reads.facets.gen
		})
	if rolled {
		t.Fatal("an older enumeration rolled the cache's generation back")
	}
}

// The spellings memo publishes the same way and never rolls back either.
func TestTagValuePublishesNeverRollTheMemoBack(t *testing.T) {
	t.Parallel()
	_, svc, _ := newCatalogFixture(t)
	settleCatalogFeed(t, svc)
	ctx := context.Background()
	rolled := raceGenerations(t, svc,
		func(gen facetGeneration) { svc.Reads.publishTagValues(ctx, gen, "tag.MOOD", nil) },
		func() facetGeneration {
			svc.Reads.tagValues.mu.Lock()
			defer svc.Reads.tagValues.mu.Unlock()
			return svc.Reads.tagValues.gen
		})
	if rolled {
		t.Fatal("an older spellings read rolled the memo's generation back")
	}
}

// A publish reads the catalog position before it takes its cache's lock,
// so a caller checking the enumeration cache or the spellings memo never
// waits on another caller's catalog read.
func TestPublishesLookAtTheLogOutsideTheirLocks(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	settleCatalogFeed(t, svc)
	var under atomic.Int64
	svc.Reads.trackFacts.headHook = func(ctx context.Context) (int64, error) {
		for _, mu := range []*sync.Mutex{&svc.Reads.facets.mu, &svc.Reads.tagValues.mu} {
			if mu.TryLock() {
				mu.Unlock()
			} else {
				under.Add(1)
			}
		}
		return svc.lib.LatestChangeSeq(ctx)
	}
	if _, err := svc.Reads.Facets(ctx, uc, FacetQuery{Dimension: "artist", Limit: 50}); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Reads.tagSpellings(ctx, "tag.MOOD", "calm"); err != nil {
		t.Fatal(err)
	}
	if n := under.Load(); n != 0 {
		t.Fatalf("%d change-log looks ran under a publish's lock, want none", n)
	}
}
