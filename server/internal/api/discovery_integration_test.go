package api

import (
	"testing"
)

// The instant mix's exclusion accounting over the wire: an all-excluded
// request answers an empty mix that says why, and an open one carries a
// zero count even though the seed was dropped from its own pools.
func TestInstantMixReportsExclusions(t *testing.T) {
	t.Parallel()
	h := newHarness(t)

	page := h.items(t, "")
	if len(page.Items) != 4 {
		t.Fatalf("scanned %d items, want 4", len(page.Items))
	}
	seed := page.Items[0].Pid
	others := []string{page.Items[1].Pid, page.Items[2].Pid, page.Items[3].Pid}

	resp := h.postJSON(t, "/api/v1/mixes/instant", map[string]any{
		"seedPid":     seed,
		"size":        10,
		"excludePids": others,
	})
	if resp.StatusCode != 200 {
		t.Fatalf("all-excluded mix status = %d", resp.StatusCode)
	}
	empty := decode[InstantMix](t, resp)
	if len(empty.Items) != 0 {
		t.Fatalf("mix items = %+v, want none with the rest of the library excluded", empty.Items)
	}
	if empty.Excluded == nil || *empty.Excluded != 3 {
		t.Fatalf("excluded = %v, want 3", empty.Excluded)
	}

	resp = h.postJSON(t, "/api/v1/mixes/instant", map[string]any{
		"seedPid": seed,
		"size":    10,
	})
	if resp.StatusCode != 200 {
		t.Fatalf("open mix status = %d", resp.StatusCode)
	}
	open := decode[InstantMix](t, resp)
	if len(open.Items) == 0 {
		t.Fatal("open mix came back empty")
	}
	if open.Excluded == nil || *open.Excluded != 0 {
		t.Fatalf("open mix excluded = %v, want 0", open.Excluded)
	}
}
