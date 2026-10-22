package service

import (
	"testing"
	"time"
)

// An enumeration counts what the catalog holds, so a play, which moves the
// change log but none of that, leaves the cached one served, and a change
// to what the catalog holds refreshes it.
func TestAPlayLeavesTheEnumerationCacheWarm(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	settleCatalogFeed(t, svc)
	artists := func() map[string]int {
		t.Helper()
		page, err := svc.Facets(ctx, uc, FacetQuery{Dimension: "artist", Limit: 500})
		if err != nil {
			t.Fatal(err)
		}
		out := map[string]int{}
		for _, b := range page.Buckets {
			out[b.Label] = b.Count
		}
		return out
	}
	if got := artists(); got["Test Ensemble"] != 3 || got["Brass Nine"] != 1 {
		t.Fatalf("artists = %v, want the fixture's", got)
	}
	if !servesFromCache(svc, "artist") {
		t.Fatal("the enumeration did not cache")
	}

	amber, _ := fixtureTrackPID(t, ctx, svc, uc, "Amber Waves")
	tail := svc.CatalogTailSeq()
	if _, err := svc.Checkpoint(ctx, uc, amber, 1000, nil); err != nil {
		t.Fatal(err)
	}
	for deadline := time.Now().Add(10 * time.Second); svc.CatalogTailSeq() == tail; {
		if time.Now().After(deadline) {
			t.Fatal("the feed position never moved after a checkpoint")
		}
		time.Sleep(10 * time.Millisecond)
	}
	if !servesFromCache(svc, "artist") {
		t.Fatal("a play emptied the enumeration cache")
	}

	if _, err := svc.EditItemMetadata(ctx, uc, amber, map[string]string{"artist": "Brass Nine"}, MetadataEditParams{}); err != nil {
		t.Fatal(err)
	}
	for deadline := time.Now().Add(10 * time.Second); servesFromCache(svc, "artist"); {
		if time.Now().After(deadline) {
			t.Fatal("an edit to what the catalog holds left the enumeration cached")
		}
		time.Sleep(10 * time.Millisecond)
	}
	// The catalog's own follow-up writes to an edit land a moment after it.
	settleCatalogFeed(t, svc)
	if got := artists(); got["Test Ensemble"] != 2 || got["Brass Nine"] != 2 {
		t.Errorf("artists after the edit = %v, want the track moved to Brass Nine", got)
	}
	if !servesFromCache(svc, "artist") {
		t.Error("the refreshed enumeration did not cache")
	}
}

// A content rule compiles from the spellings the catalog holds, memoized on
// the content position, and a value nothing carried when the memo filled
// compiles to no condition. So a play, which changes no spelling, leaves the
// memo where it was, and a track that gains the denied value later is gone
// from the account's listing and sweep once the catalog has it.
func TestADenyRuleCatchesAValueATrackGainsLater(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	settleCatalogFeed(t, svc)
	kid := &UserCtx{ID: uc.ID, CatalogPID: uc.CatalogPID, AllLibraries: true, Explicit: true,
		TagDeny: []TagRule{{Key: advisoryTagKey, Value: "1"}}}
	shows := func(title string) (listed, swept bool) {
		t.Helper()
		page, err := svc.Items(ctx, kid, ItemFilter{MediaType: "music"}, "", 50)
		if err != nil {
			t.Fatal(err)
		}
		for _, it := range page.Items {
			listed = listed || it.Title == title
		}
		facts, err := svc.TrackFacts(ctx, kid)
		if err != nil {
			t.Fatal(err)
		}
		for _, f := range facts {
			swept = swept || f.Title == title
		}
		return listed, swept
	}
	memo := func() facetGeneration {
		svc.tagValues.mu.Lock()
		defer svc.tagValues.mu.Unlock()
		return svc.tagValues.gen
	}
	if listed, swept := shows("Amber Waves"); !listed || !swept {
		t.Fatalf("before any track carries the value: listed %v, swept %v; want both", listed, swept)
	}
	filled := memo()

	amber, _ := fixtureTrackPID(t, ctx, svc, uc, "Amber Waves")
	tail := svc.CatalogTailSeq()
	if _, err := svc.Checkpoint(ctx, uc, amber, 1000, nil); err != nil {
		t.Fatal(err)
	}
	for deadline := time.Now().Add(10 * time.Second); svc.CatalogTailSeq() == tail; {
		if time.Now().After(deadline) {
			t.Fatal("the feed position never moved after a checkpoint")
		}
		time.Sleep(10 * time.Millisecond)
	}
	shows("Amber Waves")
	if got := memo(); got != filled {
		t.Fatalf("a play moved the spellings memo from %+v to %+v", filled, got)
	}

	if _, err := svc.SetItemTag(ctx, uc, amber, advisoryTagKey, []string{"1"}, MetadataEditParams{}); err != nil {
		t.Fatal(err)
	}
	settleCatalogFeed(t, svc)
	if listed, swept := shows("Amber Waves"); listed || swept {
		t.Errorf("after the track gained the denied value: listed %v, swept %v; want neither", listed, swept)
	}
}
