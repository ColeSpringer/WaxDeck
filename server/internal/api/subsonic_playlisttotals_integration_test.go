package api

import (
	"io"
	"testing"
)

// A list row used to report zero for both, because it has no members to
// add up. It computes them now, so the two surfaces have to agree.
func TestSubsonicPlaylistTotalsAgreeAcrossSurfaces(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	secret := newSubsonicSecret(t, h)
	items := h.items(t, "")
	if len(items.Items) < 3 {
		t.Fatalf("fixture library has %d items, want at least 3", len(items.Items))
	}
	pids := []string{items.Items[0].Pid, items.Items[1].Pid, items.Items[2].Pid}
	// Rounded the way the protocol reports it: seconds off summed ms.
	var wholeMS int64
	for i := range pids {
		wholeMS += items.Items[i].DurationMs
	}
	wantWhole := int(wholeMS / 1000)
	wantOne := int(items.Items[0].DurationMs / 1000)

	created := h.postJSON(t, "/api/v1/playlists", map[string]any{
		"name": "Totals", "kind": "static", "itemPids": pids,
	})
	if created.StatusCode != 201 {
		body, _ := io.ReadAll(created.Body)
		created.Body.Close()
		t.Fatalf("playlist create status = %d (%s)", created.StatusCode, body)
	}
	pl := decode[Playlist](t, created)

	type header struct {
		ID        string `json:"id"`
		SongCount int    `json:"songCount"`
		Duration  int    `json:"duration"`
	}
	var list struct {
		Playlists struct {
			Playlist []header `json:"playlist"`
		} `json:"playlists"`
	}
	subsonicJSON(t, h, "getPlaylists", secret, "", &list)

	var row *header
	for i := range list.Playlists.Playlist {
		if list.Playlists.Playlist[i].ID == pl.Pid {
			row = &list.Playlists.Playlist[i]
		}
	}
	if row == nil {
		t.Fatalf("the playlist is missing from getPlaylists: %+v", list.Playlists.Playlist)
	}
	if row.SongCount != len(pids) {
		t.Fatalf("list row songCount = %d, want %d", row.SongCount, len(pids))
	}
	if row.Duration != wantWhole {
		t.Fatalf("list row duration = %d, want %d (the members added up)", row.Duration, wantWhole)
	}

	var detail struct {
		Playlist struct {
			header
			Entry []struct {
				ID string `json:"id"`
			} `json:"entry"`
		} `json:"playlist"`
	}
	subsonicJSON(t, h, "getPlaylist", secret, "&id="+pl.Pid, &detail)
	if detail.Playlist.SongCount != row.SongCount || detail.Playlist.Duration != row.Duration {
		t.Fatalf("detail says %d songs / %ds, the list row says %d / %ds",
			detail.Playlist.SongCount, detail.Playlist.Duration, row.SongCount, row.Duration)
	}

	// updatedAt is in the cache key, so an edit shows at once.
	shortened := h.putJSON(t, "/api/v1/playlists/"+pl.Pid+"/items",
		map[string]any{"itemPids": pids[:1]})
	if shortened.StatusCode != 204 {
		body, _ := io.ReadAll(shortened.Body)
		shortened.Body.Close()
		t.Fatalf("replacing members status = %d (%s)", shortened.StatusCode, body)
	}
	shortened.Body.Close()

	subsonicJSON(t, h, "getPlaylists", secret, "", &list)
	for _, r := range list.Playlists.Playlist {
		if r.ID != pl.Pid {
			continue
		}
		if r.SongCount != 1 {
			t.Fatalf("after the edit the list row says %d songs, want 1", r.SongCount)
		}
		if r.Duration != wantOne {
			t.Fatalf("after the edit the list row reports %ds, want %ds", r.Duration, wantOne)
		}
		return
	}
	t.Fatal("the playlist left getPlaylists after an edit to its members")
}
