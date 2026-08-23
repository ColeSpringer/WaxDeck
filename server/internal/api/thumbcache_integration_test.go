package api

import (
	"testing"
)

// The thumbnail cache's admin surface: what the census reports, and what
// a prune drops.
//
// The cache is the one piece of stored artwork state nothing else on the
// admin screens accounts for, and it is derived end to end - which is
// what makes a prune safe and what the test asserts on both sides: the
// rows go, and the picture comes back.
func TestThumbnailCacheCensusAndPrune(t *testing.T) {
	t.Parallel()
	h := newHarness(t)

	page := h.items(t, "?mediaType=music")
	if len(page.Items) == 0 {
		t.Fatal("no items to hang a cover on")
	}
	pid := page.Items[0].Pid

	// A source big enough that every rung below it is a real re-encode
	// rather than the original handed back whole.
	resp := metadataPutBytes(t, h.ts, "/api/v1/items/"+pid+"/artwork", h.token, bigPNG(t, 300))
	wantStatus(t, resp, 200, "set a cover")

	// Two rungs of the same source, asked for as sizes that round to
	// them. 200 is not a rung; the derivative it generates is the 256
	// one, which is what the census must report.
	for _, size := range []string{"64", "200"} {
		resp = get(t, h.ts, "/api/v1/items/"+pid+"/art?size="+size, h.token)
		wantStatus(t, resp, 200, "art at size "+size)
		resp.Body.Close()
	}

	rep := thumbCensus(t, h)
	if rep.Rows < 2 {
		t.Fatalf("census rows = %d, want at least the two just generated", rep.Rows)
	}
	if rep.Bytes <= 0 || rep.ArtSourceBytes <= 0 {
		t.Errorf("census bytes = %d, source bytes = %d, want both positive",
			rep.Bytes, rep.ArtSourceBytes)
	}
	if rep.Sources > rep.ArtSources {
		t.Errorf("sources with derivatives = %d exceeds sources held = %d",
			rep.Sources, rep.ArtSources)
	}
	if rep.OldestAt == nil || rep.NewestAt == nil {
		t.Errorf("a non-empty cache reported no oldest/newest entry")
	}
	// The requested 200 was rounded up before anything was generated, so
	// the census names the rung and not the size that was typed.
	rungs := map[int]int{}
	for _, r := range rep.Rungs {
		rungs[r.Size] = r.Rows
	}
	if rungs[64] == 0 || rungs[256] == 0 {
		t.Errorf("rung breakdown = %+v, want rows at 64 and 256", rep.Rungs)
	}
	if rungs[200] != 0 {
		t.Errorf("rung breakdown holds a 200 row; sizes round to the ladder before they are cached")
	}

	// A policy with no bound at all is refused rather than read as
	// "everything": a client that forgot its fields must not wipe the
	// cache.
	resp = h.postJSON(t, "/api/v1/admin/thumbnails/prune", map[string]any{})
	wantStatus(t, resp, 400, "a prune with neither bound")

	// An age past what a Duration's nanoseconds hold. The spec's only
	// bound on the field is a floor, so an operator meaning "keep
	// everything" can type one - and a wrapped Duration is a small
	// positive age, which is a cache wipe answering the opposite
	// request. Refused rather than clamped: prune is not a verb to
	// guess at.
	resp = h.postJSON(t, "/api/v1/admin/thumbnails/prune",
		map[string]any{"olderThanSeconds": int64(20_000_000_000)})
	wantStatus(t, resp, 400, "an age that would overflow a Duration")

	// Zero is a bound and not an absence, on both axes.
	resp = h.postJSON(t, "/api/v1/admin/thumbnails/prune", map[string]any{"maxBytes": 0})
	if resp.StatusCode != 200 {
		t.Fatalf("prune to nothing status = %d", resp.StatusCode)
	}
	pruned := decode[ThumbnailPruneResult](t, resp)
	if pruned.Removed < rep.Rows || pruned.FreedBytes <= 0 {
		t.Errorf("prune removed %d rows / %d bytes, want at least the %d the census held",
			pruned.Removed, pruned.FreedBytes, rep.Rows)
	}

	if after := thumbCensus(t, h); after.Rows != 0 || after.Bytes != 0 {
		t.Errorf("cache after an empty-everything prune = %d rows / %d bytes", after.Rows, after.Bytes)
	}

	// And nothing was lost. A rung that was already asked for still
	// serves, off the in-process cache the prune does not reach; a rung
	// that was not is generated afresh and written back, which is the
	// half that proves a pruned row is a decode away rather than a
	// picture gone.
	resp = get(t, h.ts, "/api/v1/items/"+pid+"/art?size=64", h.token)
	wantStatus(t, resp, 200, "a pruned rung after the prune")

	resp = get(t, h.ts, "/api/v1/items/"+pid+"/art?size=128", h.token)
	wantStatus(t, resp, 200, "a rung this test had not asked for")

	if refilled := thumbCensus(t, h); refilled.Rows == 0 {
		t.Error("the cache stayed empty after a request that had to generate")
	}
}

func thumbCensus(t *testing.T, h *harness) ThumbnailCacheReport {
	t.Helper()
	resp := get(t, h.ts, "/api/v1/admin/thumbnails", h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("thumbnail census status = %d", resp.StatusCode)
	}
	return decode[ThumbnailCacheReport](t, resp)
}
