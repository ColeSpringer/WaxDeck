package service

import (
	"context"
	"testing"

	"github.com/colespringer/waxbin/model"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/similarity"
)

// TestTrashingATrackKeepsItsEmbedding is the sweep's premise catching up
// with ADR-0048.
//
// The prune built its live set from visibleItems(), which excludes
// archived, and dropped any vector whose essence was not in it. That was
// right when archived meant gone; a trashed item is restorable and its
// audio is still on disk, so every trash and restore cost a full
// re-analysis of a file that never moved. The question the sweep is
// actually asking is whether the audio is still there.
func TestTrashingATrackKeepsItsEmbedding(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	enableSonicAnalysis(t, ctx, svc, uc)

	pids := fixtureItemPIDs(t, ctx, svc, uc)
	for _, apiPID := range pids {
		essence, bare := essenceFor(t, ctx, svc, uc, apiPID)
		// The bare catalog pid, which is what IngestEmbeddings records.
		storeEmbedding(t, ctx, svc, essence, string(bare))
	}

	if _, err := svc.SimilaritySweep(ctx); err != nil {
		t.Fatalf("first sweep: %v", err)
	}
	if got := embeddingCount(t, ctx, svc); got != len(pids) {
		t.Fatalf("embeddings after the first sweep = %d, want %d", got, len(pids))
	}

	doomed := pids[0]
	if _, err := svc.DeleteItems(ctx, uc, []string{doomed}, "trash", false); err != nil {
		t.Fatalf("trashing: %v", err)
	}
	if _, err := svc.SimilaritySweep(ctx); err != nil {
		t.Fatalf("sweep after trashing: %v", err)
	}
	if got := embeddingCount(t, ctx, svc); got != len(pids) {
		t.Errorf("embeddings after trashing one track = %d, want all %d kept", got, len(pids))
	}
	// Nothing was queued either: the vector is still there, so a restore
	// costs no analysis.
	if depth := queueDepth(t, ctx, svc); depth != 0 {
		t.Errorf("analysis queue depth after trashing = %d, want 0", depth)
	}

	entries, err := svc.TrashEntries(ctx, uc, false, 50)
	if err != nil {
		t.Fatalf("listing trash: %v", err)
	}
	if len(entries) != 1 {
		t.Fatalf("trash holds %d entries, want 1", len(entries))
	}
	if err := svc.RestoreTrashEntry(ctx, uc, entries[0].ID); err != nil {
		t.Fatalf("restoring: %v", err)
	}
	if _, err := svc.SimilaritySweep(ctx); err != nil {
		t.Fatalf("sweep after restoring: %v", err)
	}
	if got := embeddingCount(t, ctx, svc); got != len(pids) {
		t.Errorf("embeddings after restoring = %d, want %d", got, len(pids))
	}
	if depth := queueDepth(t, ctx, svc); depth != 0 {
		t.Errorf("analysis queue depth after restoring = %d, want 0", depth)
	}
}

func enableSonicAnalysis(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx) {
	t.Helper()
	cur, err := svc.AdminSettingsGet(ctx)
	if err != nil {
		t.Fatalf("reading settings: %v", err)
	}
	cur.SonicAnalysis = true
	if _, err := svc.AdminSettingsPut(ctx, uc, cur); err != nil {
		t.Fatalf("enabling sonic analysis: %v", err)
	}
}

// essenceFor answers the audio essence hash backing one item, which is
// what an embedding is keyed by, plus the item's bare catalog pid.
func essenceFor(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, apiPID string) (string, model.PID) {
	t.Helper()
	it, err := svc.getVisibleItem(ctx, uc, apiPID)
	if err != nil {
		t.Fatalf("resolving %s: %v", apiPID, err)
	}
	f, err := svc.lib.File(ctx, it.FilePID)
	if err != nil {
		t.Fatalf("reading the file behind %s: %v", apiPID, err)
	}
	if f.EssenceHash == "" {
		t.Fatalf("item %s has no essence hash", apiPID)
	}
	return f.EssenceHash, it.PID
}

// storeEmbedding stands in for the analyzer: the sweep only cares that a
// vector exists for an essence, not what is in it.
func storeEmbedding(t *testing.T, ctx context.Context, svc *Library, essence, itemPID string) {
	t.Helper()
	vec := []float32{1, 0, 0, 0}
	if _, err := svc.db.UpsertEmbedding(ctx, wdb.Embedding{
		Essence: essence,
		ItemPID: itemPID,
		Model:   "test",
		Dims:    len(vec),
		Vector:  similarity.Encode(vec),
	}); err != nil {
		t.Fatalf("storing an embedding: %v", err)
	}
	svc.sim.Load(essence, vec)
}

func embeddingCount(t *testing.T, ctx context.Context, svc *Library) int {
	t.Helper()
	n := 0
	if _, _, err := svc.db.Embeddings(ctx, func(wdb.Embedding) { n++ }); err != nil {
		t.Fatalf("counting embeddings: %v", err)
	}
	return n
}

func queueDepth(t *testing.T, ctx context.Context, svc *Library) int {
	t.Helper()
	n, err := svc.db.SimilarityQueueDepth(ctx)
	if err != nil {
		t.Fatalf("reading queue depth: %v", err)
	}
	return n
}
