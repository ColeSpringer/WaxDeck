package api

import (
	"context"
	"testing"

	"github.com/colespringer/waxdeck/fixtures"
)

// drainAnalyses runs the analysis worker inline until it finds nothing.
func drainAnalyses(h *harness) {
	for h.svc.DrainAnalysisQueue(context.Background()) {
	}
}

// While the engine is away a part with no skip map yet waits on it, and
// is not unmappable: the read answers the engine-away refusal, and the
// analysis it asked for is kept, so once the engine answers the worker
// builds the map without anyone asking again.
func TestASkipMapAskedForWhileTheEngineIsAwayIsBuiltOnItsReturn(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	if _, err := fixtures.GenerateBook(h.library); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	books := h.items(t, "?mediaType=audiobook").Items
	if len(books) != 1 {
		t.Fatalf("audiobooks = %d, want the fixture book", len(books))
	}
	mapURL := "/api/v1/items/" + books[0].Pid + "/skip-map?partIndex=1"
	takeEngineAway(t, h)
	wantEngineDown(t, get(t, h.ts, mapURL, h.token), "a skip map read while the engine is away")
	drainAnalyses(h)
	bringEngineBack(t, h)
	drainAnalyses(h)
	if sm := decode[SkipMap](t, get(t, h.ts, mapURL, h.token)); sm.State != "ready" {
		t.Fatalf("the skip map once the engine answered = %q, want it built without asking again", sm.State)
	}
}

// An episode fetched while the engine is away keeps the analysis its
// landing queues: once the engine answers, the worker builds its skip
// map without anyone asking for it.
func TestAnEpisodeFetchedWhileTheEngineIsAwayIsAnalyzedOnItsReturn(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	feed := newFeedServer(t, 2)
	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
	if resp.StatusCode != 201 {
		t.Fatalf("subscribe status = %d", resp.StatusCode)
	}
	sub := decode[Subscription](t, resp)
	page := decode[EpisodePage](t, get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token))
	if len(page.Items) != 2 {
		t.Fatalf("episodes = %d, want 2", len(page.Items))
	}
	ep := page.Items[1]
	takeEngineAway(t, h)
	resp = h.postJSON(t, "/api/v1/episodes/"+ep.Pid+"/fetch", nil)
	if resp.StatusCode != 202 {
		t.Fatalf("fetch status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	drainFetches(t, h)
	drainAnalyses(h)
	bringEngineBack(t, h)
	drainAnalyses(h)
	if sm := decode[SkipMap](t, get(t, h.ts, "/api/v1/items/"+ep.Pid+"/skip-map", h.token)); sm.State != "ready" {
		t.Fatalf("the skip map once the engine answered = %q, want the fetch's analysis run", sm.State)
	}
}
