package api

import (
	"testing"
)

// TestResolveEntitiesNamesTheDeparted drives the batch resolver over
// the wire: cards for what resolves, and the departed list naming
// exactly the pids that are gone for everyone, which is what a pinned
// client prunes on.
func TestResolveEntitiesNamesTheDeparted(t *testing.T) {
	t.Parallel()
	h := newHarness(t)

	items := h.items(t, "?limit=1")
	if len(items.Items) == 0 || items.Items[0].AlbumPid == nil {
		t.Fatalf("the demo library should answer an item with an album pid, got %+v", items.Items)
	}
	album := *items.Items[0].AlbumPid
	gone := "al-01JZX5N8QW3F4V9T2B7KD3M9R6"

	resp := h.postJSON(t, "/api/v1/library/entities", map[string]any{
		"pids": []string{gone, album},
	})
	if resp.StatusCode != 200 {
		t.Fatalf("resolve status = %d", resp.StatusCode)
	}
	list := decode[EntityCardList](t, resp)
	if len(list.Entities) != 1 || list.Entities[0].Pid != album {
		t.Fatalf("entities = %+v, want only %s", list.Entities, album)
	}
	if list.Departed == nil || len(*list.Departed) != 1 || (*list.Departed)[0] != gone {
		t.Fatalf("departed = %v, want [%s]", list.Departed, gone)
	}

	// Every miss merely out of sight leaves the field absent, so a
	// client never has to tell an empty list from a missing one; the
	// all-resolved case is the everyday shape of that.
	resp = h.postJSON(t, "/api/v1/library/entities", map[string]any{
		"pids": []string{album},
	})
	if resp.StatusCode != 200 {
		t.Fatalf("resolve status = %d", resp.StatusCode)
	}
	if list := decode[EntityCardList](t, resp); list.Departed != nil {
		t.Fatalf("departed should be absent when nothing is, got %v", *list.Departed)
	}
}
