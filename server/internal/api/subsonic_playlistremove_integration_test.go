package api

import (
	"io"
	"net/url"
	"testing"
)

// TestSubsonicRemoveTakesTheTrackTheClientSaw is a data-loss regression.
//
// getPlaylist renders the caller's own filtered membership and the
// protocol carries no position field, so the array index is a client's
// only handle on a member. songIndexToRemove used to be passed straight
// through as a catalog position, which is a different number the moment
// anything is hidden - here a trashed member ahead of the target - so
// the client asked for one track and a different one was deleted.
// Unrecoverable through that client, which cannot see what it lost.
func TestSubsonicRemoveTakesTheTrackTheClientSaw(t *testing.T) {
	h := newHarness(t)
	secret := newSubsonicSecret(t, h)
	items := h.items(t, "")
	if len(items.Items) < 4 {
		t.Fatalf("fixture library has %d items, want at least 4", len(items.Items))
	}
	pids := []string{
		items.Items[0].Pid, items.Items[1].Pid,
		items.Items[2].Pid, items.Items[3].Pid,
	}

	created := h.postJSON(t, "/api/v1/playlists", map[string]any{
		"name": "Four", "kind": "static", "itemPids": pids,
	})
	if created.StatusCode != 201 {
		body, _ := io.ReadAll(created.Body)
		created.Body.Close()
		t.Fatalf("playlist create status = %d (%s)", created.StatusCode, body)
	}
	pl := decode[Playlist](t, created)

	// Trash the member at stored position 1, so every later member's
	// rendered index sits one below its catalog position.
	resp := h.postJSON(t, "/api/v1/library/items/delete", map[string]any{
		"pids": []string{pids[1]}, "mode": "trash",
	})
	wantStatus(t, resp, 200, "delete to trash")

	rendered := subsonicPlaylistEntryIDs(t, h, secret, pl.Pid)
	if len(rendered) != 3 {
		t.Fatalf("rendered membership = %v, want the three untrashed members", rendered)
	}
	// Index 2 of what the client sees is the last stored member, which is
	// catalog position 3. Passing the index through would have removed
	// catalog position 2 - the track at rendered index 1.
	target := rendered[2]
	bystander := rendered[1]

	subsonicJSON(t, h, "updatePlaylist", secret,
		"&playlistId="+url.QueryEscape(pl.Pid)+"&songIndexToRemove=2", &struct{}{})

	after := subsonicPlaylistEntryIDs(t, h, secret, pl.Pid)
	for _, id := range after {
		if id == target {
			t.Errorf("the track the client asked to remove (%s) is still there: %v", target, after)
		}
	}
	found := false
	for _, id := range after {
		if id == bystander {
			found = true
		}
	}
	if !found {
		t.Errorf("removing index 2 took %s instead: %v", bystander, after)
	}
}

// subsonicPlaylistEntryIDs reads one playlist's rendered membership in
// the order a client receives it.
func subsonicPlaylistEntryIDs(t *testing.T, h *harness, secret, pid string) []string {
	t.Helper()
	var got struct {
		Playlist struct {
			Entry []struct {
				ID string `json:"id"`
			} `json:"entry"`
		} `json:"playlist"`
	}
	subsonicJSON(t, h, "getPlaylist", secret, "&id="+url.QueryEscape(pid), &got)
	out := make([]string, 0, len(got.Playlist.Entry))
	for _, e := range got.Playlist.Entry {
		out = append(out, e.ID)
	}
	return out
}
