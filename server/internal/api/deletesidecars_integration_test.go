package api

import (
	"os"
	"path/filepath"
	"slices"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// A plan entry says the sidecars that go with its files where it has
// them, and nothing where it has none.
func TestADeleteResultCarriesTheSidecarsItNames(t *testing.T) {
	t.Parallel()
	res := deleteResultJSON(service.DeleteItemsResultDTO{Entries: []service.DeletePlanDTO{
		{PID: "tr-1", Files: 1, Paths: []string{"Album/one.flac"}, Sidecars: []string{"Album/one.lrc", "Album/one.jpg"}},
		{PID: "tr-2", Files: 1, Paths: []string{"Album/two.flac"}},
	}})
	if got := res.Entries[0].Sidecars; got == nil || !slices.Equal(*got, []string{"Album/one.lrc", "Album/one.jpg"}) {
		t.Errorf("entry with sidecars = %v, want both, in order", got)
	}
	if got := res.Entries[1].Sidecars; got != nil {
		t.Errorf("entry with none = %v, want it absent", *got)
	}
}

// Both delete verbs preview the sidecars that go with a file and report
// them once it has gone, each as a place in the library.
func TestBothDeleteVerbsNameTheSidecarsThatGoWithAFile(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	folder := filepath.Join(h.library, "lyrics")
	if _, err := fixtures.Generate(folder, fixtures.Spec{
		Name: "words", Codec: fixtures.CodecFLAC, Duration: 6 * time.Second,
		Tags: map[string]string{"TITLE": "Words", "ARTIST": "Lyricist", "ALBUM": "Sung"},
	}); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"words.lrc", "words.jpg"} {
		if err := os.WriteFile(filepath.Join(folder, name), []byte("sidecar"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	h.rescanAndWait(t)
	pid := h.itemTitled(t, h.token, "Words").Pid
	files := h.itemFiles(t, h.token, pid)
	if len(files) != 1 {
		t.Fatalf("files = %+v, want the one", files)
	}
	want := []string{"lyrics/words.jpg", "lyrics/words.lrc"}

	plan := decodeStatus[DeleteItemsResult](t, h.postJSON(t, "/api/v1/library/items/delete", map[string]any{
		"pids": []string{pid}, "dryRun": true,
	}), 200, "dry run of the item delete")
	if len(plan.Entries) != 1 || plan.Entries[0].Sidecars == nil || !sameSidecars(*plan.Entries[0].Sidecars, want) {
		t.Fatalf("item plan = %+v, want the sidecars %q", plan.Entries, want)
	}
	plan = decodeStatus[DeleteItemsResult](t, h.postJSON(t, "/api/v1/items/"+pid+"/files/delete", map[string]any{
		"filePids": []string{files[0].FilePid}, "dryRun": true,
	}), 200, "dry run of the file delete")
	if len(plan.Entries) != 1 || plan.Entries[0].Sidecars == nil || !sameSidecars(*plan.Entries[0].Sidecars, want) {
		t.Fatalf("file plan = %+v, want the sidecars %q", plan.Entries, want)
	}

	applied := decodeStatus[DeleteItemsResult](t, h.postJSON(t, "/api/v1/library/items/delete", map[string]any{
		"pids": []string{pid},
	}), 200, "the delete itself")
	if !applied.Applied || len(applied.Entries) != 1 || applied.Entries[0].Sidecars == nil ||
		!sameSidecars(*applied.Entries[0].Sidecars, want) {
		t.Fatalf("applied = %+v, want the sidecars %q", applied.Entries, want)
	}
	for _, name := range []string{"words.lrc", "words.jpg"} {
		if _, err := os.Stat(filepath.Join(folder, name)); !os.IsNotExist(err) {
			t.Errorf("%s is still in the library: %v", name, err)
		}
	}
}

// sameSidecars reports whether two lists hold the same strings.
func sameSidecars(a, b []string) bool {
	a, b = slices.Sorted(slices.Values(a)), slices.Sorted(slices.Values(b))
	return slices.Equal(a, b)
}
