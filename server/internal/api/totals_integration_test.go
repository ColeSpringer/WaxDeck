package api

import (
	"path/filepath"
	"testing"
	"time"

	"github.com/colespringer/waxlabel/tag"

	"github.com/colespringer/waxdeck/fixtures"
)

// A track's total is an editable field, and renumbering past it clears
// it in the catalog and the file alike, so nothing reads "7 of 1".
func TestRenumberingPastATotalClearsIt(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	paths, err := fixtures.Generate(filepath.Join(h.library, "totals"), fixtures.Spec{
		Name: "single", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
		Tags: map[string]string{
			"TITLE": "Counted Once", "ARTIST": "Tallies", "ALBUM": "One of One",
			"TRACKNUMBER": "1", "TRACKTOTAL": "1", "DISCNUMBER": "1", "DISCTOTAL": "1",
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	pid := h.itemTitled(t, h.token, "Counted Once").Pid
	if f := h.itemMeta(t, pid).Fields; f["track_total"] != "1" || f["disc_total"] != "1" {
		t.Fatalf("fields = %v, want both totals read from the file", f)
	}

	wantStatus(t, h.patchJSON(t, "/api/v1/items/"+pid+"/metadata", map[string]any{
		"fields": map[string]string{"disc_total": "2"}, "writeBack": true,
	}), 200, "set the disc total")
	wantStatus(t, h.patchJSON(t, "/api/v1/items/"+pid+"/metadata", map[string]any{
		"fields": map[string]string{"track_no": "7"}, "writeBack": true,
	}), 200, "renumber")
	f := h.itemMeta(t, pid).Fields
	if _, ok := f["track_total"]; ok || f["track_no"] != "7" || f["disc_total"] != "2" {
		t.Fatalf("fields = %v, want track 7 with no total and the disc total kept", f)
	}
	if got := tagOnDisk(t, paths[0], tag.TrackTotal); got != "" {
		t.Fatalf("track total on disk = %q, want it cleared", got)
	}
	if got := tagOnDisk(t, paths[0], tag.DiscTotal); got != "2" {
		t.Fatalf("disc total on disk = %q, want the edited 2", got)
	}
}
