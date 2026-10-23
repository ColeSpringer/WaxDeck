package api

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// One track of a cue rip cannot be deleted alone, and the refusal
// carries a reason the app words itself and every track of the rip, for
// the app to offer them together.
func TestDeletingOneTrackOfACueRipSaysWhy(t *testing.T) {
	t.Parallel()
	rips := t.TempDir()
	if _, err := fixtures.Generate(rips, fixtures.Spec{
		Name: "Rip Album", Codec: fixtures.CodecFLAC, Duration: 6 * time.Second,
		Tags: map[string]string{"ALBUM": "Rip Album", "ARTIST": "Rip Artist"},
	}); err != nil {
		t.Fatal(err)
	}
	sheet := "PERFORMER \"Rip Artist\"\nTITLE \"Rip Album\"\nFILE \"Rip Album.flac\" WAVE\n" +
		"  TRACK 01 AUDIO\n    TITLE \"Rip One\"\n    INDEX 01 00:00:00\n" +
		"  TRACK 02 AUDIO\n    TITLE \"Rip Two\"\n    INDEX 01 00:03:00\n"
	if err := os.WriteFile(filepath.Join(rips, "Rip Album.cue"), []byte(sheet), 0o644); err != nil {
		t.Fatal(err)
	}
	h := newHarness(t, service.Root{Name: "rips", Path: rips})
	var one, two string
	for _, it := range h.items(t, "?limit=200").Items {
		switch it.Title {
		case "Rip One":
			one = it.Pid
		case "Rip Two":
			two = it.Pid
		}
	}
	if one == "" || two == "" {
		t.Fatal("the rip's tracks were not cataloged")
	}

	resp := h.postJSON(t, "/api/v1/library/items/delete", map[string]any{"pids": []string{one}, "dryRun": true})
	defer resp.Body.Close()
	if resp.StatusCode != 400 {
		t.Fatalf("status = %d, want 400", resp.StatusCode)
	}
	e := decode[Error](t, resp)
	if e.Params == nil || (*e.Params)["reason"] != "cue-rip" {
		t.Fatalf("refusal = %+v, want reason cue-rip", e)
	}
	if got := (*e.Params)["tracks"]; got != one+","+two {
		t.Fatalf("refusal tracks = %q, want the rip's two tracks in order", got)
	}
	// The rip's file, deleted from one track's files, is refused the same
	// way, with the same tracks to offer.
	files := h.itemFiles(t, h.token, one)
	if len(files) != 1 {
		t.Fatalf("files = %+v, want the rip", files)
	}
	resp = h.postJSON(t, "/api/v1/items/"+one+"/files/delete", map[string]any{"filePids": []string{files[0].FilePid}, "dryRun": true})
	defer resp.Body.Close()
	if resp.StatusCode != 400 {
		t.Fatalf("file delete status = %d, want 400", resp.StatusCode)
	}
	if e := decode[Error](t, resp); e.Params == nil || (*e.Params)["reason"] != "cue-rip" || (*e.Params)["tracks"] != one+","+two {
		t.Fatalf("file delete refusal = %+v, want reason cue-rip with the rip's two tracks", e)
	}
	plan := decodeStatus[DeleteItemsResult](t, h.postJSON(t, "/api/v1/library/items/delete", map[string]any{
		"pids": []string{one, two}, "dryRun": true,
	}), 200, "the whole rip's plan")
	if len(plan.Entries) == 0 || plan.Entries[0].Paths == nil || (*plan.Entries[0].Paths)[0] != "Rip Album.flac" {
		t.Fatalf("plan = %+v, want the rip's one file named", plan.Entries)
	}
}
