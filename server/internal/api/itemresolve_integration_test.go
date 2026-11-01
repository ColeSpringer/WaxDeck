package api

import (
	"slices"
	"testing"
)

// TestResolveItemsNamesTheDeparted drives the batch item read over the
// wire: summaries for what resolves, in request order, and the departed
// list naming exactly the pids no item answers to, which is what a client
// holding a queue drops.
func TestResolveItemsNamesTheDeparted(t *testing.T) {
	t.Parallel()
	h := newHarness(t)

	page := h.items(t, "?limit=2")
	if len(page.Items) != 2 {
		t.Fatalf("the demo library should answer two items, got %+v", page.Items)
	}
	a, b := page.Items[0].Pid, page.Items[1].Pid
	gone := "tr-01JZX5N8QW3F4V9T2B7KD3M9R6"

	resp := h.postJSON(t, "/api/v1/library/items/resolve", map[string]any{
		"pids": []string{b, gone, a},
	})
	if resp.StatusCode != 200 {
		t.Fatalf("resolve status = %d", resp.StatusCode)
	}
	list := decode[ItemResolution](t, resp)
	var got []string
	for _, it := range list.Items {
		got = append(got, it.Pid)
	}
	if !slices.Equal(got, []string{b, a}) {
		t.Fatalf("items = %v, want [%s %s]", got, b, a)
	}
	if list.Departed == nil || !slices.Equal(*list.Departed, []string{gone}) {
		t.Fatalf("departed = %v, want [%s]", list.Departed, gone)
	}

	// Everything resolved leaves the field absent rather than empty.
	resp = h.postJSON(t, "/api/v1/library/items/resolve", map[string]any{
		"pids": []string{a},
	})
	if resp.StatusCode != 200 {
		t.Fatalf("resolve status = %d", resp.StatusCode)
	}
	if list := decode[ItemResolution](t, resp); list.Departed != nil {
		t.Fatalf("departed should be absent when nothing is, got %v", *list.Departed)
	}

	over := make([]string, 101)
	for i := range over {
		over[i] = a
	}
	resp = h.postJSON(t, "/api/v1/library/items/resolve", map[string]any{"pids": over})
	if resp.StatusCode != 400 {
		t.Fatalf("over the cap = %d, want 400", resp.StatusCode)
	}
	if e := decode[Error](t, resp); e.Code != "invalid-request" {
		t.Fatalf("over the cap answered %q, want invalid-request", e.Code)
	}
}
