package api

import (
	"os"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
)

// importAs uploads one file as a caller under a media type, decides it
// as-is, and answers the item it became.
func importAs(t *testing.T, h *harness, token, path, mediaType string) string {
	t.Helper()
	up := uploadFile(t, h, token, path, mediaType, "")
	drainMatches(t, h)
	decideAs(t, h, token, *up.ReviewEntryId, map[string]any{"action": "as-is"})
	tracks := reviewAs(t, h, token, *up.ReviewEntryId).Tracks
	if len(tracks) != 1 || tracks[0].Pid == nil {
		t.Fatalf("decided tracks = %+v, want the one imported item", tracks)
	}
	return *tracks[0].Pid
}

// An MP3 uploaded as an audiobook stays one through every kind of scan:
// the import pins its kind, so its pid, and the uploader's right to edit
// it, survive a rescan, a forced one, and one that rereads the file.
func TestUploadedPlainMP3BookSurvivesARescan(t *testing.T) {
	t.Parallel()
	h, bob := joinHarness(t)
	parts, err := fixtures.GenerateLooseMP3Book(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	pid := importAs(t, h, bob, parts[0], "audiobook")
	if !strings.HasPrefix(pid, "bk-") {
		t.Fatalf("uploaded audiobook pid = %s, want a book", pid)
	}
	check := func(label string) {
		t.Helper()
		wantStatus(t, get(t, h.ts, "/api/v1/books/"+pid, h.token), 200, label+": the book")
		for _, it := range h.items(t, "?mediaType=music&limit=500").Items {
			if it.Title == "Chapter One" {
				t.Fatalf("%s: the book is listed as music (%s)", label, it.Pid)
			}
		}
		if !mayCurateAs(t, h, bob, pid) {
			t.Fatalf("%s: the uploader lost the right to edit the book", label)
		}
		if locks := h.itemMeta(t, pid).LockedFields; !slices.Contains(locks, "kind") {
			t.Fatalf("%s: locked fields = %v, want the kind pinned", label, locks)
		}
	}
	check("imported")
	h.rescanAndWait(t)
	check("rescanned")
	h.rescanAndWaitWith(t, `{"force": true}`)
	check("forced")

	files := h.itemFiles(t, h.token, pid)
	if len(files) != 1 || files[0].Path == nil {
		t.Fatalf("book files = %+v, want its one file", files)
	}
	later := time.Now().Add(time.Hour)
	if err := os.Chtimes(*files[0].Path, later, later); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	check("reread")
}

// An .m4b uploaded as music stays a track, whatever its extension says.
func TestAMusicUploadOfAnM4BStaysATrack(t *testing.T) {
	t.Parallel()
	h, bob := joinHarness(t)
	m4b, err := fixtures.GenerateM4B(t.TempDir(), fixtures.Spec{
		Name: "music-in-m4b", Duration: 3 * time.Second,
		Tags: map[string]string{"TITLE": "Container Song", "ARTIST": "Box Band", "ALBUM": "Boxes"},
	})
	if err != nil {
		t.Fatal(err)
	}
	pid := importAs(t, h, bob, m4b, "music")
	if !strings.HasPrefix(pid, "tr-") {
		t.Fatalf("music upload pid = %s, want a track", pid)
	}
	h.rescanAndWaitWith(t, `{"force": true}`)
	if got := h.itemTitled(t, h.token, "Container Song").Pid; got != pid {
		t.Fatalf("after a forced rescan the upload is %s, want the track %s", got, pid)
	}
}

// Unlocking a pinned kind hands the item back to the scan, which files
// it by its library and tags under the same catalog id.
func TestUnlockingTheKindLetsTheScanDecide(t *testing.T) {
	t.Parallel()
	h, bob := joinHarness(t)
	parts, err := fixtures.GenerateLooseMP3Book(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	book := importAs(t, h, bob, parts[0], "audiobook")
	wantStatus(t, h.putJSON(t, "/api/v1/items/"+book+"/locks",
		map[string]any{"fields": []string{"kind"}, "locked": false}), 200, "unlock the kind")
	h.rescanAndWaitWith(t, `{"force": true}`)
	track := "tr-" + strings.TrimPrefix(book, "bk-")
	wantStatus(t, get(t, h.ts, "/api/v1/items/"+track, h.token), 200, "the item, now a track")
	wantStatus(t, get(t, h.ts, "/api/v1/books/"+book, h.token), 404, "the book it was")
}
