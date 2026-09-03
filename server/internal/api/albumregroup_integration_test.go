package api

import (
	"testing"
)

// These two probes pin what happens to a release when a bulk edit
// rewrites a field that keys it. WaxBin re-resolves entities inside the
// edit transaction and the album key is mbid-first, else built from the
// normalized album/album-artist names, the year, and the folder - but a
// rename pre-pass runs first and detects "every member of this entity
// moves at once to one new key". When it fires the entity chain is
// rewritten in place, so the album keeps its al- pid along with its
// curation, art, play state and enrichment marker; when it does not,
// the members fork onto a fresh pid and the old row is left behind.
// Full coverage takes the first path, partial coverage the second.
//
// The bulk-edit surface also locks every edited field unconditionally,
// so a second bulk edit of the same field refuses with field-locked
// unless it forces or skips. Album-editing UI is built against exactly
// these behaviors; if either changes upstream, these tests are the
// tripwire.
func TestBulkEditAlbumFieldsRenamesInPlaceOnFullCoverage(t *testing.T) {
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

	// Playlist membership references track pids, which the rename must
	// leave alone.
	resp := h.postJSON(t, "/api/v1/playlists", map[string]any{
		"name": "Rename Canary", "kind": "static", "itemPids": []string{pids[0], pids[2]},
	})
	if resp.StatusCode != 201 {
		t.Fatalf("create playlist status = %d", resp.StatusCode)
	}
	pl := decode[Playlist](t, resp)

	// probe bulk-edits one release-keying field on all four members and
	// asserts they stayed on the album they started on.
	probe := func(field, value string) {
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
		// The response still names the album the members sit on. It
		// answers "where is the release now", not "did it move": under
		// full coverage that is the pid the caller was already looking
		// at, which is exactly the news.
		if out.ResultingAlbumPid == nil {
			t.Fatalf("%s bulk edit reported no resultingAlbumPid", field)
		}
		if *out.ResultingAlbumPid != album {
			t.Fatalf("%s: resultingAlbumPid = %s, want the album kept in place (%s)",
				field, *out.ResultingAlbumPid, album)
		}
		after := h.items(t, "")
		surviving := map[string]bool{}
		for _, it := range after.Items {
			surviving[it.Pid] = true
			if it.AlbumPid == nil {
				t.Fatalf("%s: item %s lost its album", field, it.Pid)
			}
			if *it.AlbumPid != album {
				t.Fatalf("%s: item %s moved to album %s; expected a rename in place",
					field, it.Pid, *it.AlbumPid)
			}
		}
		for _, pid := range pids {
			if !surviving[pid] {
				t.Fatalf("%s: track pid %s did not survive the edit", field, pid)
			}
		}
	}

	probe("album", "Renamed Fixture Album")
	probe("album_artist", "Renamed Fixture Artist")
	probe("year", "1999")

	// A field outside the release key touches no entity, and the
	// response says nothing about albums: reporting a pid at all would
	// read as "your release moved" to a caller that only checks
	// presence.
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

	// A keying edit that changes nothing reports the same pid, which is
	// what every full-coverage keying edit reports now.
	resp = h.postJSON(t, "/api/v1/items/bulk-edit", map[string]any{
		"itemPids": pids, "fields": map[string]string{"year": "1999"}, "force": true,
	})
	if resp.StatusCode != 200 {
		t.Fatalf("noop year bulk edit status = %d", resp.StatusCode)
	}
	noop := decode[BulkEditResult](t, resp)
	if noop.ResultingAlbumPid == nil || *noop.ResultingAlbumPid != album {
		t.Fatalf("noop keying edit resultingAlbumPid = %v, want %s", noop.ResultingAlbumPid, album)
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

	// Playlist membership rode through all three renames.
	entries := playlistItems(t, h, h.token, pl.Pid)
	if !samePids(entryPids(entries), []string{pids[0], pids[2]}) {
		t.Fatalf("playlist members after rename = %v", entryPids(entries))
	}

	// The album that kept its pid carries the edited identity and still
	// holds every member.
	fresh := decode[AlbumDetail](t, get(t, h.ts, "/api/v1/albums/"+album, h.token))
	if fresh.Title != "Renamed Fixture Album" {
		t.Fatalf("renamed album title = %q, want the edited identity", fresh.Title)
	}
	if fresh.ItemCount == nil || *fresh.ItemCount != 4 {
		t.Fatalf("renamed album itemCount = %v, want 4", fresh.ItemCount)
	}
}

// TestBulkEditAlbumFieldsRegroupsOnPartialCoverage is the other half:
// when the batch moves only some of an album's members, the rename
// pre-pass cannot fire (the entity still has references on the old key)
// and the edited members fork onto a fresh al- pid. This is the case
// ResultingAlbumPID exists for - the caller who asked for the edit is
// looking at a pid that no longer holds the tracks it selected.
func TestBulkEditAlbumFieldsRegroupsOnPartialCoverage(t *testing.T) {
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
	moving := []string{pids[0], pids[1]}
	staying := map[string]bool{pids[2]: true, pids[3]: true}

	resp := h.postJSON(t, "/api/v1/items/bulk-edit", map[string]any{
		"itemPids": moving, "fields": map[string]string{"album": "Split Off Album"},
	})
	if resp.StatusCode != 200 {
		t.Fatalf("partial bulk edit status = %d", resp.StatusCode)
	}
	out := decode[BulkEditResult](t, resp)
	if len(out.Edited) != 2 || len(out.Skipped) != 0 {
		t.Fatalf("partial bulk edit outcome = %+v", out)
	}
	if out.ResultingAlbumPid == nil {
		t.Fatalf("partial bulk edit reported no resultingAlbumPid")
	}
	if *out.ResultingAlbumPid == album {
		t.Fatalf("resultingAlbumPid = %s, the pre-edit album", album)
	}
	forked := *out.ResultingAlbumPid

	after := h.items(t, "")
	surviving := map[string]bool{}
	for _, it := range after.Items {
		surviving[it.Pid] = true
		if it.AlbumPid == nil {
			t.Fatalf("item %s lost its album", it.Pid)
		}
		want := forked
		if staying[it.Pid] {
			want = album
		}
		if *it.AlbumPid != want {
			t.Fatalf("item %s sits on album %s, want %s", it.Pid, *it.AlbumPid, want)
		}
	}
	for _, pid := range pids {
		if !surviving[pid] {
			t.Fatalf("track pid %s did not survive the edit", pid)
		}
	}

	// The album the batch left behind is not a ghost: it keeps its pid,
	// its identity, and the members that did not move.
	stale := decode[AlbumDetail](t, get(t, h.ts, "/api/v1/albums/"+album, h.token))
	if stale.Title != "Fixture Album" {
		t.Fatalf("original album title = %q, want the pre-edit identity", stale.Title)
	}
	if stale.ItemCount == nil || *stale.ItemCount != 2 {
		t.Fatalf("original album itemCount = %v, want 2", stale.ItemCount)
	}

	fresh := decode[AlbumDetail](t, get(t, h.ts, "/api/v1/albums/"+forked, h.token))
	if fresh.Title != "Split Off Album" {
		t.Fatalf("forked album title = %q, want the edited identity", fresh.Title)
	}
	if fresh.ItemCount == nil || *fresh.ItemCount != 2 {
		t.Fatalf("forked album itemCount = %v, want 2", fresh.ItemCount)
	}
}
