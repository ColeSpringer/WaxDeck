package api

import (
	"context"
	"slices"
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

// queueLibrary turns analysis on and sweeps, so every analyzable track
// waits in the queue under its own key.
func queueLibrary(t *testing.T, h *harness) {
	t.Helper()
	wantStatus(t, h.putJSON(t, "/api/v1/admin/settings", map[string]any{"sonicAnalysis": true}), 200, "turning analysis on")
	if _, err := h.svc.SimilaritySweep(context.Background()); err != nil {
		t.Fatal(err)
	}
}

// reportVectors leases the queue as a worker would and reports a vector
// for each named track, leaving the rest queued.
func reportVectors(t *testing.T, h *harness, pids ...string) {
	t.Helper()
	essence := map[string]string{}
	for _, w := range pullWork(t, h).Items {
		essence[w.Pid] = w.Essence
	}
	ups := make([]EmbeddingUpload, 0, len(pids))
	for _, pid := range pids {
		e, ok := essence[pid]
		if !ok {
			t.Fatalf("no work leased for %s", pid)
		}
		ups = append(ups, EmbeddingUpload{Pid: pid, Essence: e, Vector: []float32{1, 0, 0, 0, 0, 0, 0, 0}})
	}
	ctx := context.WithValue(context.Background(), ctxWorkerKey{}, true)
	resp, err := h.srv.ReportEmbeddings(ctx, ReportEmbeddingsRequestObject{Body: &EmbeddingReport{Model: "test", Dims: 8, Embeddings: ups}})
	if err != nil {
		t.Fatal(err)
	}
	if res, ok := resp.(ReportEmbeddings200JSONResponse); !ok || res.Accepted != len(ups) {
		t.Fatalf("report = %#v, want all %d accepted", resp, len(ups))
	}
}

// While a configured engine is away no analysis work is leased: a worker
// pulling its audio could not fetch it, and every lease spends one of the
// few attempts a track gets. The worker is told to ask again when the
// engine's own refusals say to, and once the engine answers the same
// work is leased.
func TestNoAnalysisWorkIsLeasedWhileTheEngineIsAway(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	alpha := musicPid(t, h, "Alpha Song")
	queueLibrary(t, h)
	takeEngineAway(t, h)
	if page := pullWork(t, h); len(page.Items) != 0 || page.RetryAfterSeconds != flow.EngineRetrySeconds {
		t.Fatalf("pull while away = %+v, want no work and a retry in %ds", page, flow.EngineRetrySeconds)
	}
	bringEngineBack(t, h)
	page := pullWork(t, h)
	if !slices.ContainsFunc(page.Items, func(w SimilarityWorkItem) bool { return w.Pid == alpha }) {
		t.Fatalf("pull once the engine answered = %+v, want the queued work leased", page)
	}
}
