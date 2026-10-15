package api

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// Resolving an upgrade that would trash a cue rip's file from under
// tracks the call does not name is refused with the reason the app words
// itself, as a delete is: within one track, whose copy of the rip plays
// its sibling too, and across tracks, naming one of the rip's.
func TestResolvingAnUpgradeThatSplitsACueRipSaysWhy(t *testing.T) {
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
	// A byte-identical copy of the rip carves the same two tracks, which
	// take its file as theirs too.
	again := filepath.Join(rips, "again")
	if err := os.MkdirAll(again, 0o755); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"Rip Album.flac", "Rip Album.cue"} {
		raw, err := os.ReadFile(filepath.Join(rips, name))
		if err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(again, name), raw, 0o644); err != nil {
			t.Fatal(err)
		}
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
	files := h.itemFiles(t, h.token, one)
	if len(files) != 2 {
		t.Fatalf("files = %+v, want the rip and its copy", files)
	}
	for _, c := range []struct {
		name string
		body map[string]any
	}{
		{"within a track", map[string]any{"keepItemPid": one, "keepFilePid": files[0].FilePid, "removeFilePids": []string{files[1].FilePid}}},
		{"across tracks", map[string]any{"keepItemPid": two, "removeItemPids": []string{one}}},
	} {
		resp := h.postJSON(t, "/api/v1/library/upgrades/resolve", c.body)
		if resp.StatusCode != 400 {
			resp.Body.Close()
			t.Fatalf("%s: status = %d, want 400", c.name, resp.StatusCode)
		}
		e := decode[Error](t, resp)
		if e.Params == nil || (*e.Params)["reason"] != "cue-rip" {
			t.Fatalf("%s: refusal = %+v, want reason cue-rip", c.name, e)
		}
	}
	for _, f := range files {
		if _, err := os.Stat(*f.Path); err != nil {
			t.Fatalf("a rip's file went: %v", err)
		}
	}
}
