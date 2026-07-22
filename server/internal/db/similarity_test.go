package db

import (
	"context"
	"fmt"
	"testing"
	"time"
)

const simTestPID = "01JZX5N8QW3F4V9T2B7KDEXAMPLE"

func testEmbedding(essence, itemPID string) Embedding {
	return Embedding{
		Essence: essence,
		ItemPID: itemPID,
		Model:   "m1",
		Dims:    4,
		Vector:  []byte{0, 0, 128, 63, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	}
}

func queueDepth(t *testing.T, d *DB) int {
	t.Helper()
	n, err := d.SimilarityQueueDepth(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	return n
}

func graphEdgeCount(t *testing.T, d *DB) int {
	t.Helper()
	n := 0
	if err := d.GraphEdges(context.Background(), func(GraphEdge) { n++ }); err != nil {
		t.Fatal(err)
	}
	return n
}

func TestUpsertEmbeddingReportsReplacement(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	replaced, err := d.UpsertEmbedding(ctx, testEmbedding("ess-1", simTestPID))
	if err != nil || replaced {
		t.Fatalf("first upsert = (%v, %v), want (false, nil)", replaced, err)
	}
	second := testEmbedding("ess-1", "01JZX5N8QW3F4V9T2B7KDOTHER00")
	replaced, err = d.UpsertEmbedding(ctx, second)
	if err != nil || !replaced {
		t.Fatalf("second upsert = (%v, %v), want (true, nil)", replaced, err)
	}
	// The replacement refreshed the item pointer.
	pid, err := d.EmbeddingItemPID(ctx, "ess-1")
	if err != nil || pid != second.ItemPID {
		t.Fatalf("EmbeddingItemPID = (%q, %v), want the replacing pid", pid, err)
	}
}

func TestEnqueueSimilaritySkipsEmbeddedAndDuplicates(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	if _, err := d.UpsertEmbedding(ctx, testEmbedding("ess-done", simTestPID)); err != nil {
		t.Fatal(err)
	}
	// An already-embedded essence never queues.
	if err := d.EnqueueSimilarity(ctx, "ess-done", simTestPID); err != nil {
		t.Fatal(err)
	}
	if n := queueDepth(t, d); n != 0 {
		t.Fatalf("queue depth after embedded enqueue = %d, want 0", n)
	}
	// A fresh essence queues once, replays are absorbed.
	if err := d.EnqueueSimilarity(ctx, "ess-new", simTestPID); err != nil {
		t.Fatal(err)
	}
	if err := d.EnqueueSimilarity(ctx, "ess-new", simTestPID); err != nil {
		t.Fatal(err)
	}
	if n := queueDepth(t, d); n != 1 {
		t.Fatalf("queue depth = %d, want 1", n)
	}
}

func TestLeaseSimilarityWorkExpiry(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	if err := d.EnqueueSimilarity(ctx, "ess-work", simTestPID); err != nil {
		t.Fatal(err)
	}
	const lease = 30 * time.Millisecond
	work, err := d.LeaseSimilarityWork(ctx, 10, lease)
	if err != nil || len(work) != 1 {
		t.Fatalf("first lease = (%v, %v), want one item", work, err)
	}
	if work[0].Essence != "ess-work" || work[0].ItemPID != simTestPID {
		t.Fatalf("leased item = %+v", work[0])
	}
	// A live lease hides the row.
	work, err = d.LeaseSimilarityWork(ctx, 10, lease)
	if err != nil || len(work) != 0 {
		t.Fatalf("re-lease inside the window = (%v, %v), want empty", work, err)
	}
	// After expiry the item returns on its own; a crashed worker needs
	// no cleanup.
	time.Sleep(2 * lease)
	work, err = d.LeaseSimilarityWork(ctx, 10, lease)
	if err != nil || len(work) != 1 {
		t.Fatalf("post-expiry lease = (%v, %v), want one item", work, err)
	}
	// Completion retires the row for good.
	if err := d.CompleteSimilarityWork(ctx, "ess-work"); err != nil {
		t.Fatal(err)
	}
	if n := queueDepth(t, d); n != 0 {
		t.Fatalf("queue depth after completion = %d, want 0", n)
	}
	time.Sleep(2 * lease)
	if work, err := d.LeaseSimilarityWork(ctx, 10, lease); err != nil || len(work) != 0 {
		t.Fatalf("lease after completion = (%v, %v), want empty", work, err)
	}
}

func TestRemoveEmbeddingCleansEverythingAndNamesNeighbors(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	for _, e := range []string{"ess-a", "ess-b"} {
		if _, err := d.UpsertEmbedding(ctx, testEmbedding(e, simTestPID)); err != nil {
			t.Fatal(err)
		}
	}
	if err := d.ReplaceGraphNode(ctx, "ess-a", []GraphEdge{{Rank: 0, Neighbor: "ess-b", Distance: 0.1}}); err != nil {
		t.Fatal(err)
	}
	if err := d.ReplaceGraphNode(ctx, "ess-b", []GraphEdge{{Rank: 0, Neighbor: "ess-a", Distance: 0.1}}); err != nil {
		t.Fatal(err)
	}
	affected, err := d.RemoveEmbedding(ctx, "ess-b")
	if err != nil {
		t.Fatal(err)
	}
	if len(affected) != 1 || affected[0] != "ess-a" {
		t.Fatalf("affected = %v, want the node that lost an edge", affected)
	}
	if _, err := d.EmbeddingItemPID(ctx, "ess-b"); err != ErrNotFound {
		t.Fatalf("removed embedding lookup = %v, want ErrNotFound", err)
	}
	if _, err := d.EmbeddingItemPID(ctx, "ess-a"); err != nil {
		t.Fatalf("surviving embedding lookup = %v", err)
	}
	// Both directions of the graph are gone: ess-b's own edges and the
	// edge pointing at it.
	if n := graphEdgeCount(t, d); n != 0 {
		t.Fatalf("graph edges after removal = %d, want 0", n)
	}
	// The queue slot reopens: the essence is no longer embedded.
	if err := d.EnqueueSimilarity(ctx, "ess-b", simTestPID); err != nil {
		t.Fatal(err)
	}
	if n := queueDepth(t, d); n != 1 {
		t.Fatalf("queue depth after re-enqueue = %d, want 1", n)
	}
	// A queued-but-never-embedded essence loses its queue row too.
	if _, err := d.RemoveEmbedding(ctx, "ess-b"); err != nil {
		t.Fatal(err)
	}
	if n := queueDepth(t, d); n != 0 {
		t.Fatalf("queue depth after removing a queued essence = %d, want 0", n)
	}
}

func TestSimilarityBackfillDrains(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	if err := d.AddSimilarityBackfill(ctx, []string{"ess-a", "ess-b"}); err != nil {
		t.Fatal(err)
	}
	// Replays and overlaps are absorbed.
	if err := d.AddSimilarityBackfill(ctx, []string{"ess-b", "ess-c"}); err != nil {
		t.Fatal(err)
	}
	got, err := d.TakeSimilarityBackfill(ctx, 10)
	if err != nil {
		t.Fatal(err)
	}
	seen := map[string]bool{}
	for _, e := range got {
		seen[e] = true
	}
	if len(got) != 3 || !seen["ess-a"] || !seen["ess-b"] || !seen["ess-c"] {
		t.Fatalf("first take = %v, want the three distinct essences", got)
	}
	// Taking pops: a second sweep finds nothing.
	if again, err := d.TakeSimilarityBackfill(ctx, 10); err != nil || len(again) != 0 {
		t.Fatalf("second take = (%v, %v), want empty", again, err)
	}
}

func TestDeleteEmbeddingsNotModelDropsGraph(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	for _, e := range []string{"ess-a", "ess-b"} {
		if _, err := d.UpsertEmbedding(ctx, testEmbedding(e, simTestPID)); err != nil {
			t.Fatal(err)
		}
	}
	if err := d.ReplaceGraphNode(ctx, "ess-a", []GraphEdge{{Rank: 0, Neighbor: "ess-b", Distance: 0.1}}); err != nil {
		t.Fatal(err)
	}
	// The stored model survives its own sweep, graph intact.
	n, err := d.DeleteEmbeddingsNotModel(ctx, "m1")
	if err != nil || n != 0 {
		t.Fatalf("same-model sweep = (%d, %v), want (0, nil)", n, err)
	}
	if g := graphEdgeCount(t, d); g != 1 {
		t.Fatalf("graph after same-model sweep = %d edges, want 1", g)
	}
	// A model switch drops every vector and the whole graph with it.
	n, err = d.DeleteEmbeddingsNotModel(ctx, "m2")
	if err != nil || n != 2 {
		t.Fatalf("model-switch sweep = (%d, %v), want (2, nil)", n, err)
	}
	count, _, _, _, err := d.EmbeddingStats(ctx)
	if err != nil || count != 0 {
		t.Fatalf("embeddings after switch = (%d, %v), want 0", count, err)
	}
	if g := graphEdgeCount(t, d); g != 0 {
		t.Fatalf("graph after switch = %d edges, want 0", g)
	}
}

func TestLeaseSimilarityWorkAttemptCap(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	if err := d.EnqueueSimilarity(ctx, "ess-poison", simTestPID); err != nil {
		t.Fatal(err)
	}
	// An item a worker leases but never reports must not re-lease
	// forever: past the cap it stops being offered and leaves the
	// reported queue depth.
	for i := 0; i < maxAnalysisAttempts; i++ {
		work, err := d.LeaseSimilarityWork(ctx, 10, 0)
		if err != nil || len(work) != 1 {
			t.Fatalf("lease %d = (%v, %v), want the item", i+1, work, err)
		}
	}
	work, err := d.LeaseSimilarityWork(ctx, 10, 0)
	if err != nil || len(work) != 0 {
		t.Fatalf("post-cap lease = (%v, %v), want empty", work, err)
	}
	if n := queueDepth(t, d); n != 0 {
		t.Fatalf("queue depth = %d, want exhausted rows excluded", n)
	}
}

func TestEmbeddingItemPIDsBatch(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	for i, essence := range []string{"ess-x", "ess-y", "ess-z"} {
		if _, err := d.UpsertEmbedding(ctx, Embedding{
			Essence: essence,
			ItemPID: fmt.Sprintf("pid-%d", i),
			Model:   "m", Dims: 2, Vector: []byte{0, 0, 0, 0, 0, 0, 0, 0},
		}); err != nil {
			t.Fatal(err)
		}
	}
	got, err := d.EmbeddingItemPIDs(ctx, []string{"ess-z", "ess-missing", "ess-x"})
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 || got["ess-z"] != "pid-2" || got["ess-x"] != "pid-0" {
		t.Fatalf("batch = %v, want the two present essences", got)
	}
	if _, ok := got["ess-missing"]; ok {
		t.Fatal("absent essence must be an absent key, not an empty value")
	}
	empty, err := d.EmbeddingItemPIDs(ctx, nil)
	if err != nil || len(empty) != 0 {
		t.Fatalf("empty batch = (%v, %v), want empty map", empty, err)
	}
}
