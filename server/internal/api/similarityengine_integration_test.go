package api

import (
	"context"
	"strings"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
)

// pullWork asks for analysis work as an external worker would.
func pullWork(t *testing.T, h *harness) SimilarityWorkPage {
	t.Helper()
	ctx := context.WithValue(context.Background(), ctxWorkerKey{}, true)
	resp, err := h.srv.PullSimilarityWork(ctx, PullSimilarityWorkRequestObject{})
	if err != nil {
		t.Fatal(err)
	}
	page, ok := resp.(PullSimilarityWork200JSONResponse)
	if !ok {
		t.Fatalf("pull = %#v, want a page", resp)
	}
	return SimilarityWorkPage(page)
}

// While a configured engine is away no analysis work is leased: a worker
// pulling its audio could not fetch it, and every lease spends one of the
// few attempts a track gets. The worker is told to ask again when the
// engine's own refusals say to, and once the engine answers the same
// work is leased.
func TestNoAnalysisWorkIsLeasedWhileTheEngineIsAway(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	alpha := strings.TrimPrefix(musicPid(t, h, "Alpha Song"), "tr-")
	if err := h.store.EnqueueSimilarity(context.Background(), "essence-of-alpha", alpha); err != nil {
		t.Fatal(err)
	}
	takeEngineAway(t, h)
	if page := pullWork(t, h); len(page.Items) != 0 || page.RetryAfterSeconds != flow.EngineRetrySeconds {
		t.Fatalf("pull while away = %+v, want no work and a retry in %ds", page, flow.EngineRetrySeconds)
	}
	bringEngineBack(t, h)
	if page := pullWork(t, h); len(page.Items) != 1 || page.Items[0].Essence != "essence-of-alpha" {
		t.Fatalf("pull once the engine answered = %+v, want the queued work leased", page)
	}
}
