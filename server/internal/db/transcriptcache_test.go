package db

import (
	"context"
	"fmt"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

// writesOn is how many rows the write connection has changed since it
// opened.
func writesOn(t *testing.T, d *DB) int64 {
	t.Helper()
	var n int64
	if err := d.w.QueryRowContext(context.Background(), `SELECT total_changes()`).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n
}

// The cache keeps its size beside it, so a store under the bound writes
// its row and the size and runs no eviction; past the bound the rows read
// longest ago go, a remembered failure counting what it holds.
func TestTheTranscriptCacheKeepsItsBound(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	const bound = 4000
	store := func(pid string, cues int, at int64) int64 {
		t.Helper()
		row := TranscriptRow{EpisodePID: pid, Format: "vtt", Cues: strings.Repeat("x", cues), FetchedAtNS: at}
		if cues == 0 {
			row = TranscriptRow{EpisodePID: pid, Negative: true, FailReason: "host-error", FetchedAtNS: at}
		}
		evicted, err := d.StoreTranscriptCache(ctx, row, bound)
		if err != nil {
			t.Fatal(err)
		}
		return evicted
	}
	for i, cues := range []int{1000, 1000, 0, 1000} {
		before := writesOn(t, d)
		if evicted := store(fmt.Sprintf("ep-%d", i+1), cues, int64(i+1)); evicted != 0 {
			t.Fatalf("a store under the bound evicted %d rows", evicted)
		}
		if n := writesOn(t, d) - before; n != 2 {
			t.Errorf("a store under the bound changed %d rows, want its own and the size", n)
		}
	}
	if n := d.transcriptEvictions.Load(); n != 0 {
		t.Fatalf("stores under the bound ran %d eviction passes", n)
	}
	if err := d.TouchTranscriptCache(ctx, "ep-1", 10); err != nil {
		t.Fatal(err)
	}
	if row, err := d.TranscriptCacheFor(ctx, "ep-1"); err != nil || row.ReadAtNS != 10 || row.FetchedAtNS != 1 {
		t.Fatalf("ep-1 = %+v (%v), want read at 10 and fetched at 1", row, err)
	}
	if evicted := store("ep-5", 1000, 11); evicted != 1 {
		t.Fatalf("a store past the bound evicted %d rows, want the one read longest ago", evicted)
	}
	var kept []string
	for i := 1; i <= 5; i++ {
		if _, err := d.TranscriptCacheFor(ctx, fmt.Sprintf("ep-%d", i)); err == nil {
			kept = append(kept, fmt.Sprintf("ep-%d", i))
		} else if err != ErrNotFound {
			t.Fatal(err)
		}
	}
	if !slices.Equal(kept, []string{"ep-1", "ep-3", "ep-4", "ep-5"}) {
		t.Errorf("kept %v, want all but ep-2, the row read longest ago", kept)
	}
	store("ep-4", 10, 12)
	var summed int64
	if err := d.r.QueryRowContext(ctx, `SELECT SUM(row_bytes) FROM transcript_cache`).Scan(&summed); err != nil {
		t.Fatal(err)
	}
	if rows, size, err := d.TranscriptCacheSize(ctx); err != nil || rows != 4 || size != summed || size > bound {
		t.Errorf("cache = %d rows, %d bytes (%v), want 4 rows and the %d bytes they hold, at most %d", rows, size, err, summed, bound)
	}
}

// An eviction pass reads the rows read longest ago through the read-time
// index, in order and a batch at a time, and sorts nothing.
func TestTranscriptEvictionWalksTheReadIndex(t *testing.T) {
	d := openTest(t)
	plan := queryPlan(t, d.w, transcriptEvictQuery, "ep-1", transcriptEvictBatch)
	if !strings.Contains(plan, "USING COVERING INDEX transcript_cache_by_read") || strings.Contains(plan, "TEMP B-TREE") {
		t.Errorf("eviction plan =\n%s\nwant a walk of the read-time index", plan)
	}
	if plan := queryPlan(t, d.w, transcriptSumQuery); !strings.Contains(plan, "USING COVERING INDEX transcript_cache_by_read") {
		t.Errorf("recount plan =\n%s\nwant the read-time index, not the rows", plan)
	}
}

// transcriptBytes is what the cache's rows hold, counted from the rows.
func transcriptBytes(t *testing.T, d *DB) int64 {
	t.Helper()
	var n int64
	if err := d.r.QueryRowContext(context.Background(), `SELECT COALESCE(SUM(row_bytes), 0) FROM transcript_cache`).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n
}

// A size row that drifted from its rows, by a hand edit or a writer that
// forgot it, is counted again as soon as it shows: a store that finds the
// cache past its bound before its own row recounts rather than evicting
// rows that fit, a pass that finds nothing left to evict recounts, and
// opening the database recounts once.
func TestTheTranscriptCacheSizeReconciles(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "waxdeck.db")
	d, err := Open(ctx, path)
	if err != nil {
		t.Fatal(err)
	}
	store := func(pid string, bound int64) int64 {
		t.Helper()
		evicted, err := d.StoreTranscriptCache(ctx, TranscriptRow{EpisodePID: pid, Format: "vtt", Cues: strings.Repeat("x", 1000), FetchedAtNS: 1}, bound)
		if err != nil {
			t.Fatal(err)
		}
		return evicted
	}
	size := func() int64 {
		t.Helper()
		_, n, err := d.TranscriptCacheSize(ctx)
		if err != nil {
			t.Fatal(err)
		}
		return n
	}
	drift := func(stmt string) {
		t.Helper()
		if _, err := d.w.ExecContext(ctx, stmt); err != nil {
			t.Fatal(err)
		}
	}
	for _, pid := range []string{"ep-1", "ep-2", "ep-3"} {
		store(pid, 10_000)
	}
	drift(`UPDATE transcript_cache_size SET bytes = bytes + 20000`)
	if evicted := store("ep-4", 10_000); evicted != 0 {
		t.Errorf("a store over a phantom evicted %d rows that fit", evicted)
	}
	if rows, _, _ := d.TranscriptCacheSize(ctx); rows != 4 || size() != transcriptBytes(t, d) {
		t.Errorf("after the phantom: %d rows, size %d for %d bytes of rows", rows, size(), transcriptBytes(t, d))
	}

	drift(`DELETE FROM transcript_cache`)
	if evicted := store("ep-5", 2000); evicted != 0 || size() != transcriptBytes(t, d) {
		t.Errorf("after rows went behind its back: evicted %d, size %d for %d bytes of rows", evicted, size(), transcriptBytes(t, d))
	}

	drift(`UPDATE transcript_cache_size SET bytes = 0`)
	if err := d.Close(); err != nil {
		t.Fatal(err)
	}
	if d, err = Open(ctx, path); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { d.Close() })
	if size() != transcriptBytes(t, d) || size() == 0 {
		t.Errorf("after reopening: size %d for %d bytes of rows", size(), transcriptBytes(t, d))
	}
}
