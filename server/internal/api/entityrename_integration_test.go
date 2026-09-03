package api

import (
	"path/filepath"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
)

// The explicit rename is the entity-rung answer to the bulk edit these
// tests sit beside: where a bulk edit moves the members it covers and
// leaves the rest behind, this moves the whole entity and keeps the
// row. These probes pin the three outcomes upstream reports and the
// lock refusal, because the album pane's rewrite section is built
// against exactly them.
func TestRenameEntityKeepsThePid(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	page := h.items(t, "")
	if len(page.Items) != 4 {
		t.Fatalf("fixture library has %d items, want 4", len(page.Items))
	}
	if page.Items[0].AlbumPid == nil {
		t.Fatal("fixture track carries no album pid")
	}
	album := *page.Items[0].AlbumPid

	resp := h.postJSON(t, "/api/v1/entities/album/"+album+"/rename", map[string]any{
		"fields": map[string]string{"album": "Renamed In Place"},
	})
	if resp.StatusCode != 200 {
		t.Fatalf("rename status = %d", resp.StatusCode)
	}
	out := decode[EntityRenameResult](t, resp)
	if out.Outcome != Renamed {
		t.Fatalf("outcome = %q, want renamed", out.Outcome)
	}
	if out.EntityPid != album {
		t.Fatalf("entityPid = %s, want the album kept in place (%s)", out.EntityPid, album)
	}
	if out.Members != 4 {
		t.Fatalf("members = %d, want every member carried", out.Members)
	}
	if out.MergedInto != nil {
		t.Fatalf("mergedInto = %q on a plain rename", *out.MergedInto)
	}

	fresh := decode[AlbumDetail](t, get(t, h.ts, "/api/v1/albums/"+album, h.token))
	if fresh.Title != "Renamed In Place" {
		t.Fatalf("album title = %q, want the renamed identity", fresh.Title)
	}
	if fresh.ItemCount == nil || *fresh.ItemCount != 4 {
		t.Fatalf("album itemCount = %v, want 4", fresh.ItemCount)
	}

	// The rename locked album on every member, so a second one refuses
	// until it forces.
	resp = h.postJSON(t, "/api/v1/entities/album/"+album+"/rename", map[string]any{
		"fields": map[string]string{"album": "RENAMED IN PLACE"},
	})
	wantStatus(t, resp, 409, "rename over a locked keying field")

	// Case-only: the match key folds case, so the key does not move and
	// only the display columns do.
	resp = h.postJSON(t, "/api/v1/entities/album/"+album+"/rename", map[string]any{
		"fields": map[string]string{"album": "RENAMED IN PLACE"}, "force": true,
	})
	if resp.StatusCode != 200 {
		t.Fatalf("case-only rename status = %d", resp.StatusCode)
	}
	cased := decode[EntityRenameResult](t, resp)
	if cased.Outcome != Refreshed {
		t.Fatalf("case-only outcome = %q, want refreshed", cased.Outcome)
	}
	if cased.EntityPid != album {
		t.Fatalf("case-only entityPid = %s, want %s", cased.EntityPid, album)
	}
	fresh = decode[AlbumDetail](t, get(t, h.ts, "/api/v1/albums/"+album, h.token))
	if fresh.Title != "RENAMED IN PLACE" {
		t.Fatalf("album title after a case-only rename = %q", fresh.Title)
	}
}

// TestRenameEntityMergesOntoATakenName is the branch a client has to
// follow: the new name is already an album's, so the renamed row folds
// into the incumbent and the caller's pid is gone.
func TestRenameEntityMergesOntoATakenName(t *testing.T) {
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

	// Fork two members onto an album of their own. Partial coverage is
	// what makes a second album exist to collide with, and the bulk
	// edit locks album on the two it moved.
	resp := h.postJSON(t, "/api/v1/items/bulk-edit", map[string]any{
		"itemPids": []string{pids[0], pids[1]}, "fields": map[string]string{"album": "Split Off Album"},
	})
	if resp.StatusCode != 200 {
		t.Fatalf("fork bulk edit status = %d", resp.StatusCode)
	}
	forked := decode[BulkEditResult](t, resp)
	if forked.ResultingAlbumPid == nil || *forked.ResultingAlbumPid == album {
		t.Fatalf("fork did not produce a second album: %+v", forked)
	}
	split := *forked.ResultingAlbumPid

	resp = h.postJSON(t, "/api/v1/entities/album/"+split+"/rename", map[string]any{
		"fields": map[string]string{"album": "Fixture Album"}, "force": true,
	})
	if resp.StatusCode != 200 {
		t.Fatalf("merging rename status = %d", resp.StatusCode)
	}
	out := decode[EntityRenameResult](t, resp)
	if out.Outcome != Merged {
		t.Fatalf("outcome = %q, want merged", out.Outcome)
	}
	if out.MergedInto == nil || *out.MergedInto != album {
		t.Fatalf("mergedInto = %v, want the incumbent %s", out.MergedInto, album)
	}

	// The row the caller named is gone and every track sits on the
	// survivor.
	wantStatus(t, get(t, h.ts, "/api/v1/albums/"+split, h.token), 404, "the merged-away album")
	after := h.items(t, "")
	for _, it := range after.Items {
		if it.AlbumPid == nil || *it.AlbumPid != album {
			t.Fatalf("item %s sits on album %v, want the survivor %s", it.Pid, it.AlbumPid, album)
		}
	}
}

// TestRenameEntityRefusesWhatCannotBeRenamed pins the two doors the
// service holds itself: an entity type with no keying fields, and an
// empty body.
func TestRenameEntityRefusesWhatCannotBeRenamed(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	page := h.items(t, "")
	if page.Items[0].AlbumPid == nil {
		t.Fatal("fixture track carries no album pid")
	}
	album := *page.Items[0].AlbumPid

	resp := h.postJSON(t, "/api/v1/entities/genre/"+album+"/rename", map[string]any{
		"fields": map[string]string{"album": "Nope"},
	})
	wantStatus(t, resp, 400, "renaming a genre")

	resp = h.postJSON(t, "/api/v1/entities/album/"+album+"/rename", map[string]any{
		"fields": map[string]string{},
	})
	wantStatus(t, resp, 400, "an empty rename")

	// The vocabulary is upstream's, and a field outside the rung's
	// keying set is a refusal with a sentence rather than a silent
	// no-op.
	resp = h.postJSON(t, "/api/v1/entities/album/"+album+"/rename", map[string]any{
		"fields": map[string]string{"barcode": "0123456789012"},
	})
	wantStatus(t, resp, 400, "renaming a non-keying field")

	resp = h.postJSON(t, "/api/v1/entities/album/"+album+"/rename", map[string]any{
		"fields": map[string]string{"album": "   "},
	})
	wantStatus(t, resp, 400, "renaming to nothing")
}

// mbidTwinSpecs are two members of one album in one folder, alike in
// every heuristic key segment, where only the first carries a release
// id. The scan therefore keys them onto two album rows: one on the id,
// one on the heuristic key. Clearing the first's id drops it onto the
// key the second already holds.
func mbidTwinSpecs() []fixtures.Spec {
	mk := func(name, title, mbid string, sec int) fixtures.Spec {
		tags := map[string]string{
			"TITLE":       title,
			"ARTIST":      "Harbor Twins",
			"ALBUMARTIST": "Harbor Twins",
			"ALBUM":       "Twin Harbour",
			"DATE":        "2004",
		}
		if mbid != "" {
			tags["MUSICBRAINZ_ALBUMID"] = mbid
		}
		return fixtures.Spec{
			Name: name, Codec: fixtures.CodecFLAC,
			Duration: time.Duration(sec) * time.Second, Tags: tags,
		}
	}
	return []fixtures.Spec{
		mk("twin-one", "Pier Light", "33333333-3333-3333-3333-333333333333", 6),
		mk("twin-two", "Pier Dark", "", 7),
	}
}

// TestEditEntityClearingAnMBIDReportsTheSurvivor pins the one entity
// edit that can leave the caller's pid gone. The editor screen follows
// mergedInto to keep talking about the release; without it the page
// sits on a 404.
func TestEditEntityClearingAnMBIDReportsTheSurvivor(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	if _, err := fixtures.Generate(filepath.Join(h.library, "twin"), mbidTwinSpecs()...); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)

	page := h.items(t, "?limit=100")
	var identified, twin string
	for _, it := range page.Items {
		switch it.Title {
		case "Pier Light":
			if it.AlbumPid == nil {
				t.Fatal("the identified member carries no album pid")
			}
			identified = *it.AlbumPid
		case "Pier Dark":
			if it.AlbumPid == nil {
				t.Fatal("the heuristic member carries no album pid")
			}
			twin = *it.AlbumPid
		}
	}
	if identified == "" || twin == "" {
		t.Fatalf("twin fixture did not scan: %+v", page.Items)
	}
	if identified == twin {
		t.Fatalf("both members landed on album %s; the release id did not fork them", identified)
	}

	resp := h.patchJSON(t, "/api/v1/entities/album/"+identified, map[string]any{
		"edits": map[string]string{"mbid": ""},
	})
	if resp.StatusCode != 200 {
		t.Fatalf("mbid clear status = %d", resp.StatusCode)
	}
	out := decode[MetadataEditResult](t, resp)
	if out.MergedInto == nil || *out.MergedInto != twin {
		t.Fatalf("mergedInto = %v, want the heuristic twin %s", out.MergedInto, twin)
	}

	wantStatus(t, get(t, h.ts, "/api/v1/albums/"+identified, h.token), 404, "the merged-away album")
	survivor := decode[AlbumDetail](t, get(t, h.ts, "/api/v1/albums/"+twin, h.token))
	if survivor.ItemCount == nil || *survivor.ItemCount != 2 {
		t.Fatalf("survivor itemCount = %v, want both members", survivor.ItemCount)
	}
}
