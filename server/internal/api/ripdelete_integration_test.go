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
// carries a reason the app words itself.
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
	var one string
	for _, it := range h.items(t, "?limit=200").Items {
		if it.Title == "Rip One" {
			one = it.Pid
		}
	}
	if one == "" {
		t.Fatal("the rip's first track was not cataloged")
	}

	resp := h.postJSON(t, "/api/v1/library/items/delete", map[string]any{"pids": []string{one}, "dryRun": true})
	defer resp.Body.Close()
	if resp.StatusCode != 400 {
		t.Fatalf("status = %d, want 400", resp.StatusCode)
	}
	if e := decode[Error](t, resp); e.Params == nil || (*e.Params)["reason"] != "cue-rip" {
		t.Fatalf("refusal = %+v, want reason cue-rip", e)
	}
}
