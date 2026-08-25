package api

import (
	"testing"
)

// This probe pins what happens to a release when a bulk edit rewrites a
// field that keys it. WaxBin re-resolves entities inside the edit
// transaction, and the album key is mbid-first, else built from the
// normalized album/album-artist names, the year, and the folder - so for
// an unidentified release, editing album, album_artist, or year moves
// the members onto a fresh al- pid. The old entity is left behind as a
// ghost (a zero-rollup row the orphan GC removes later) rather than
// renamed in place; its pid keeps answering reads until then. Track pids
// and playlist membership ride through untouched.
//
// The bulk-edit surface also locks every edited field unconditionally,
// so a second bulk edit of the same field refuses with field-locked
// unless it forces or skips. Album-editing UI is built against exactly
// these behaviors; if either changes upstream, this test is the tripwire.
func TestBulkEditAlbumFieldsRegroupsTheRelease(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	page := h.items(t, "")
	if len(page.Items) != 4 {
		t.Fatalf("fixture library has %d items, want 4", len(page.Items))
	}
	pids := make([]string, 0, 4)
	for _, it := range page.Items {
		pids = append(pids, it.Pid)
	}
	if page.Items[0].AlbumPid == nil {
		t.Fatal("fixture track carries no album pid")
	}
	album := *page.Items[0].AlbumPid

	// Playlist membership references track pids, which the regroup must
	// leave alone.
	resp := h.postJSON(t, "/api/v1/playlists", map[string]any{
		"name": "Regroup Canary", "kind": "static", "itemPids": []string{pids[0], pids[2]},
	})
	if resp.StatusCode != 201 {
		t.Fatalf("create playlist status = %d", resp.StatusCode)
	}
	pl := decode[Playlist](t, resp)

	// probe bulk-edits one release-keying field on all four members and
	// returns the album pid they regrouped onto.
	probe := func(field, value, oldAlbum string) string {
		t.Helper()
		resp := h.postJSON(t, "/api/v1/items/bulk-edit", map[string]any{
			"itemPids": pids, "fields": map[string]string{field: value},
		})
		if resp.StatusCode != 200 {
			t.Fatalf("%s bulk edit status = %d", field, resp.StatusCode)
		}
		out := decode[BulkEditResult](t, resp)
		if len(out.Edited) != 4 || len(out.Skipped) != 0 {
			t.Fatalf("%s bulk edit outcome = %+v", field, out)
		}
		// The response names the album the members landed on: the caller
		// who asked for the rename is looking at a pid that no longer
		// holds them.
		if out.ResultingAlbumPid == nil {
			t.Fatalf("%s bulk edit reported no resultingAlbumPid", field)
		}
		if *out.ResultingAlbumPid == oldAlbum {
			t.Fatalf("%s: resultingAlbumPid = %s, the pre-edit album", field, oldAlbum)
		}
		after := h.items(t, "")
		surviving := map[string]bool{}
		newAlbum := ""
		for _, it := range after.Items {
			surviving[it.Pid] = true
			if it.AlbumPid == nil {
				t.Fatalf("%s: item %s lost its album", field, it.Pid)
			}
			if newAlbum == "" {
				newAlbum = *it.AlbumPid
			} else if *it.AlbumPid != newAlbum {
				t.Fatalf("%s: members split across albums (%s vs %s)", field, newAlbum, *it.AlbumPid)
			}
		}
		for _, pid := range pids {
			if !surviving[pid] {
				t.Fatalf("%s: track pid %s did not survive the edit", field, pid)
			}
		}
		if newAlbum == oldAlbum {
			t.Fatalf("%s: members kept album %s; expected a regroup", field, oldAlbum)
		}
		if *out.ResultingAlbumPid != newAlbum {
			t.Fatalf("%s: resultingAlbumPid = %s, members landed on %s",
				field, *out.ResultingAlbumPid, newAlbum)
		}
		return newAlbum
	}

	renamed := probe("album", "Renamed Fixture Album", album)
	reartisted := probe("album_artist", "Renamed Fixture Artist", renamed)
	reyeared := probe("year", "1999", reartisted)

	// A field outside the release key regroups nothing, and the response
	// says nothing about albums: reporting the unchanged pid would read
	// as "your release moved" to a caller that only checks presence.
	resp = h.postJSON(t, "/api/v1/items/bulk-edit", map[string]any{
		"itemPids": pids, "fields": map[string]string{"comment": "still here"},
	})
	if resp.StatusCode != 200 {
		t.Fatalf("comment bulk edit status = %d", resp.StatusCode)
	}
	flat := decode[BulkEditResult](t, resp)
	if len(flat.Edited) != 4 {
		t.Fatalf("comment bulk edit outcome = %+v", flat)
	}
	if flat.ResultingAlbumPid != nil {
		t.Fatalf("comment bulk edit reported resultingAlbumPid = %q", *flat.ResultingAlbumPid)
	}

	// A keying edit that changes nothing still reports where the members
	// sit - the same pid, deliberately. The response answers "where is
	// the release now", not "did it move"; callers compare pids rather
	// than checking presence, and the field's presence marks the edit as
	// release-keying either way.
	resp = h.postJSON(t, "/api/v1/items/bulk-edit", map[string]any{
		"itemPids": pids, "fields": map[string]string{"year": "1999"}, "force": true,
	})
	if resp.StatusCode != 200 {
		t.Fatalf("noop year bulk edit status = %d", resp.StatusCode)
	}
	noop := decode[BulkEditResult](t, resp)
	if noop.ResultingAlbumPid == nil || *noop.ResultingAlbumPid != reyeared {
		t.Fatalf("noop keying edit resultingAlbumPid = %v, want %s", noop.ResultingAlbumPid, reyeared)
	}

	// The abandoned entity is a ghost, not a dangling pointer: until the
	// orphan GC sweeps it, its pid still answers reads under its old
	// identity, with no members (a zero itemCount is omitted on the wire).
	stale := decode[AlbumDetail](t, get(t, h.ts, "/api/v1/albums/"+album, h.token))
	if stale.Title != "Fixture Album" {
		t.Fatalf("stale album title = %q, want the pre-edit identity", stale.Title)
	}
	if stale.ItemCount != nil {
		t.Fatalf("stale album itemCount = %d, want absent (zero members)", *stale.ItemCount)
	}

	// The bulk edit locked each edited field on every member, so editing
	// the same field again refuses without force or skipLocked.
	md := h.itemMeta(t, pids[0])
	for _, field := range []string{"album", "album_artist", "year"} {
		if !containsString(md.LockedFields, field) {
			t.Fatalf("bulk edit left %s unlocked; lockedFields = %v", field, md.LockedFields)
		}
	}
	resp = h.postJSON(t, "/api/v1/items/bulk-edit", map[string]any{
		"itemPids": pids, "fields": map[string]string{"album": "Renamed Twice"},
	})
	wantStatus(t, resp, 409, "re-edit of a bulk-locked field")

	// Playlist membership rode through all three regroups.
	entries := playlistItems(t, h, h.token, pl.Pid)
	if !samePids(entryPids(entries), []string{pids[0], pids[2]}) {
		t.Fatalf("playlist members after regroup = %v", entryPids(entries))
	}

	// The members' new home carries the edited identity.
	fresh := decode[AlbumDetail](t, get(t, h.ts, "/api/v1/albums/"+reyeared, h.token))
	if fresh.ItemCount == nil || *fresh.ItemCount != 4 {
		t.Fatalf("regrouped album itemCount = %v, want 4", fresh.ItemCount)
	}
}
