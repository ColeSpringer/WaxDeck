package api

import (
	"net/http"
	"testing"
)

// A library's read-only flag is the catalog's: the listing reports it
// beside the library's policy, a delete under it answers read-only, the
// trash names each entry's library, and the flag has no read of its own.
func TestALibrarysReadOnlyFlagIsTheCatalogs(t *testing.T) {
	t.Parallel()
	h := twoLibraryHarness(t)
	libraries := func() map[string]Library {
		out := map[string]Library{}
		for _, lib := range decode[Libraries](t, get(t, h.ts, "/api/v1/libraries", h.token)).Libraries {
			out[lib.Name] = lib
		}
		return out
	}
	guests, lib := libraries()["guests"], libraries()["lib"]
	if guests.ReadOnly || guests.Managed || lib.ReadOnly {
		t.Fatalf("libraries before = %+v, %+v, want both writable and in place", guests, lib)
	}
	wantStatus(t, h.putJSON(t, "/api/v1/libraries/"+guests.Pid+"/read-only", map[string]any{"readOnly": true}),
		200, "flag the guests library read-only")
	if got := libraries()["guests"]; !got.ReadOnly {
		t.Fatalf("guests after = %+v, want it read-only", got)
	}
	wantStatus(t, get(t, h.ts, "/api/v1/libraries/"+guests.Pid+"/read-only", h.token),
		http.StatusMethodNotAllowed, "the flag's own read is gone")

	var guestSong, other string
	for _, it := range h.items(t, "?mediaType=music").Items {
		if it.Title == "Guest Song" {
			guestSong = it.Pid
		} else if other == "" {
			other = it.Pid
		}
	}
	resp := h.postJSON(t, "/api/v1/library/items/delete", map[string]any{"pids": []string{guestSong}, "mode": "trash"})
	if e := decode[Error](t, resp); resp.StatusCode != 409 || e.Code != "read-only" {
		t.Fatalf("delete in a read-only library = %d %q, want 409 read-only", resp.StatusCode, e.Code)
	}
	wantStatus(t, h.postJSON(t, "/api/v1/library/items/delete", map[string]any{"pids": []string{other}, "mode": "trash"}),
		200, "delete a track in the writable library")
	entries := decode[TrashList](t, get(t, h.ts, "/api/v1/admin/trash", h.token)).Entries
	if len(entries) != 1 || deref(entries[0].LibraryPid) != lib.Pid || deref(entries[0].LibraryName) != "lib" {
		t.Fatalf("trash = %+v, want the one entry naming its library", entries)
	}
}
