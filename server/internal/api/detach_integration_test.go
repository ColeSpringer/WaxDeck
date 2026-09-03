package api

import (
	"io"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// detachSpecs are three members of one release pinned by a MusicBrainz
// release id. Three, because detaching an album's last member is
// refused: two must stay behind for the third to leave.
func detachSpecs() []fixtures.Spec {
	mk := func(name, title string, sec int) fixtures.Spec {
		return fixtures.Spec{
			Name: name, Codec: fixtures.CodecFLAC,
			Duration: time.Duration(sec) * time.Second,
			Tags: map[string]string{
				"TITLE": title, "ARTIST": "Pinned Trio", "ALBUMARTIST": "Pinned Trio",
				"ALBUM": "Pinned Release", "DATE": "2011",
				"MUSICBRAINZ_ALBUMID": "55555555-5555-5555-5555-555555555555",
			},
		}
	}
	return []fixtures.Spec{
		mk("pin-one", "Pin One", 5),
		mk("pin-two", "Pin Two", 6),
		mk("pin-three", "Pin Three", 7),
	}
}

// TestDetachItemLeavesThePinnedRelease covers the per-member escape
// hatch: a track a release id put on the wrong album leaves it for the
// heuristic album its own tags imply, and the album it left keeps the
// rest.
func TestDetachItemLeavesThePinnedRelease(t *testing.T) {
	t.Parallel()
	pinned := t.TempDir()
	if _, err := fixtures.Generate(pinned, detachSpecs()...); err != nil {
		t.Fatalf("generating the pinned fixtures: %v", err)
	}
	h := newHarness(t, service.Root{Name: "pinned", Path: pinned})

	var pid, album string
	for _, it := range h.items(t, "?limit=100").Items {
		if it.Title == "Pin One" && it.AlbumPid != nil {
			pid, album = it.Pid, *it.AlbumPid
		}
	}
	if pid == "" {
		t.Fatal("the pinned fixture did not scan")
	}

	resp := h.postJSON(t, "/api/v1/items/"+pid+"/detach", map[string]any{})
	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		t.Fatalf("detach status = %d: %s", resp.StatusCode, body)
	}
	out := decode[DetachResult](t, resp)
	if out.ItemPid != pid {
		t.Fatalf("itemPid = %s, want %s", out.ItemPid, pid)
	}
	if out.OldAlbumPid != album {
		t.Fatalf("oldAlbumPid = %s, want the release it left (%s)", out.OldAlbumPid, album)
	}
	if out.NewAlbumPid == nil || *out.NewAlbumPid == album {
		t.Fatalf("newAlbumPid = %v, want an album of its own", out.NewAlbumPid)
	}

	// The catalog agrees, and the two it left behind stayed put. Only
	// the pinned release is looked at: the harness also carries the
	// demo library, whose album is nobody's business here.
	for _, it := range h.items(t, "?limit=100").Items {
		if it.AlbumPid == nil || !strings.HasPrefix(it.Title, "Pin ") {
			continue
		}
		want := album
		if it.Pid == pid {
			want = *out.NewAlbumPid
		}
		if *it.AlbumPid != want {
			t.Fatalf("%s sits on album %s, want %s", it.Title, *it.AlbumPid, want)
		}
	}
}

// TestDetachItemRefusals pins the three cases upstream turns away, each
// with a sentence the client shows as typed.
func TestDetachItemRefusals(t *testing.T) {
	t.Parallel()
	h := newHarness(t)

	// The demo library's album carries no MusicBrainz id, so there is
	// no pin to leave.
	loose := h.items(t, "").Items[0].Pid
	wantStatus(t, h.postJSON(t, "/api/v1/items/"+loose+"/detach", map[string]any{}),
		400, "detaching from an unpinned album")

	single := t.TempDir()
	if _, err := fixtures.Generate(single, fixtures.Spec{
		Name: "solo", Codec: fixtures.CodecFLAC, Duration: 8 * time.Second,
		Tags: map[string]string{
			"TITLE": "Solo Pin", "ARTIST": "Lone Pin", "ALBUM": "Lone Release",
			"MUSICBRAINZ_ALBUMID": "66666666-6666-6666-6666-666666666666",
		},
	}); err != nil {
		t.Fatalf("generating the single fixture: %v", err)
	}
	h2 := newHarness(t, service.Root{Name: "single", Path: single})
	var solo string
	for _, it := range h2.items(t, "?limit=100").Items {
		if it.Title == "Solo Pin" {
			solo = it.Pid
		}
	}
	if solo == "" {
		t.Fatal("the single fixture did not scan")
	}
	// An album's last member has nothing to detach onto; the refusal
	// names the whole-entity clear instead.
	wantStatus(t, h2.postJSON(t, "/api/v1/items/"+solo+"/detach", map[string]any{}),
		400, "detaching an album's last member")

	wantStatus(t, h.postJSON(t, "/api/v1/items/tr-01JZX5N8QW3F4V9T2B7KD3M9R6/detach", map[string]any{}),
		404, "detaching an unknown item")
}
