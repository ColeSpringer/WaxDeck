package api

import (
	"os"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
)

// looseTitles are the titles the loose book's files catalog under,
// whichever kind they take.
var looseTitles = []string{"Chapter One", "Chapter Two", "The Loose Chapters"}

// looseKinds answers the media type each loose-book item carries, by
// title.
func looseKinds(t *testing.T, h *harness) map[string]string {
	t.Helper()
	out := map[string]string{}
	for _, it := range h.items(t, "?limit=500").Items {
		if slices.Contains(looseTitles, it.Title) {
			out[it.Title] = string(it.MediaType)
		}
	}
	return out
}

// eventuallyKinds polls until the loose book's items read as want.
func eventuallyKinds(t *testing.T, h *harness, label string, want map[string]string) {
	t.Helper()
	var got map[string]string
	for deadline := time.Now().Add(30 * time.Second); time.Now().Before(deadline); time.Sleep(50 * time.Millisecond) {
		if got = looseKinds(t, h); len(got) == len(want) {
			same := true
			for title, kind := range want {
				same = same && got[title] == kind
			}
			if same {
				return
			}
		}
	}
	t.Fatalf("%s: items = %v, want %v", label, got, want)
}

// waitForScans waits until no scan job is queued or running.
func waitForScans(t *testing.T, h *harness) {
	t.Helper()
	for deadline := time.Now().Add(30 * time.Second); ; time.Sleep(50 * time.Millisecond) {
		busy := false
		for _, j := range decode[JobList](t, get(t, h.ts, "/api/v1/jobs?limit=50", h.token)).Jobs {
			busy = busy || (j.Kind == "scan" && (j.State == "queued" || j.State == "running"))
		}
		if !busy {
			return
		}
		if time.Now().After(deadline) {
			t.Fatal("a scan did not finish")
		}
	}
}

// A library's media changes in place: onto audiobook, its plain MP3
// parts become one book on the scan the change starts; onto music, the
// book is read again as its tracks. Asking for what it already holds
// starts nothing, and a media no library holds refuses.
func TestChangingALibrarysMediaConvertsAndRestores(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	dir := t.TempDir()
	if _, err := fixtures.GenerateLooseMP3Book(dir); err != nil {
		t.Fatal(err)
	}
	lib := decodeStatus[Library](t, h.postJSON(t, "/api/v1/libraries", map[string]any{
		"name": "spoken", "path": dir, "media": "mixed",
	}), 201, "a mixed library")
	tracks := map[string]string{"Chapter One": "music", "Chapter Two": "music"}
	eventuallyKinds(t, h, "mixed", tracks)
	links := map[string]string{}
	for _, title := range []string{"Chapter One", "Chapter Two"} {
		links[title] = decodeStatus[Share](t, h.postJSON(t, "/api/v1/shares",
			map[string]any{"pid": h.itemTitled(t, h.token, title).Pid}), 201, "share "+title).Url
	}

	// After the scan before it, or the change's own scan cannot start.
	set := func(media string) LibraryMediaChanged {
		t.Helper()
		waitForScans(t, h)
		return decodeStatus[LibraryMediaChanged](t, h.putJSON(t, "/api/v1/libraries/"+lib.Pid+"/media",
			map[string]any{"media": media}), 200, "media "+media)
	}
	if got := set("audiobook"); got.Media == nil || *got.Media != "audiobook" || !got.ScanStarted {
		t.Fatalf("onto audiobook = %+v, want it holding books with its scan started", got)
	}
	eventuallyKinds(t, h, "audiobook", map[string]string{"The Loose Chapters": "audiobook"})
	// A chapter's link never widens into the whole book its track became.
	for title, url := range links {
		wantStatus(t, get(t, h.ts, url, ""), 404, "the link to "+title+" once it is part of a book")
	}
	if got := set("audiobook"); got.ScanStarted {
		t.Fatalf("the same media again = %+v, want nothing started", got)
	}

	if got := set("music"); got.Media == nil || *got.Media != "music" {
		t.Fatalf("off audiobook = %+v, want music", got)
	}
	eventuallyKinds(t, h, "onto music", tracks)

	wantStatus(t, h.putJSON(t, "/api/v1/libraries/"+lib.Pid+"/media", map[string]any{"media": "podcast"}), 400, "podcast media")
}

// Moving a library from audiobook to mixed keeps a book whose parts
// already make one: outside a music library a file stays in the book it
// backs while its tags name no other.
func TestAMixedLibraryKeepsTheBooksItWasGiven(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	dir := t.TempDir()
	if _, err := fixtures.GenerateLooseMP3Book(dir); err != nil {
		t.Fatal(err)
	}
	lib := decodeStatus[Library](t, h.postJSON(t, "/api/v1/libraries", map[string]any{
		"name": "spoken", "path": dir, "media": "audiobook",
	}), 201, "an audiobook library")
	book := map[string]string{"The Loose Chapters": "audiobook"}
	eventuallyKinds(t, h, "audiobook", book)
	waitForScans(t, h)
	got := decodeStatus[LibraryMediaChanged](t, h.putJSON(t, "/api/v1/libraries/"+lib.Pid+"/media",
		map[string]any{"media": "mixed"}), 200, "media mixed")
	if !got.ScanStarted {
		t.Fatalf("off audiobook = %+v, want its forced scan started", got)
	}
	waitForScans(t, h)
	if kinds := looseKinds(t, h); len(kinds) != 1 || kinds["The Loose Chapters"] != "audiobook" {
		t.Fatalf("after the move to mixed: %v, want the book kept", kinds)
	}
}

// A share made through the other prefix of an item is recorded as what
// the item is, under the pid every answer carries.
func TestAShareTakesTheItemsOwnKind(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	dir := t.TempDir()
	if _, err := fixtures.GenerateLooseMP3Book(dir); err != nil {
		t.Fatal(err)
	}
	decodeStatus[Library](t, h.postJSON(t, "/api/v1/libraries", map[string]any{
		"name": "spoken", "path": dir, "media": "audiobook",
	}), 201, "an audiobook library")
	eventuallyKinds(t, h, "audiobook", map[string]string{"The Loose Chapters": "audiobook"})
	book := h.itemTitled(t, h.token, "The Loose Chapters").Pid
	share := decodeStatus[Share](t, h.postJSON(t, "/api/v1/shares",
		map[string]any{"pid": "tr-" + strings.TrimPrefix(book, "bk-")}), 201, "a share through tr-")
	if share.TargetKind != "book" || share.TargetPid != book {
		t.Fatalf("share = %s %s, want book %s", share.TargetKind, share.TargetPid, book)
	}
}

// A library declared to hold audiobooks makes one book of a folder of
// plain MP3 parts, nothing of it music, and the book keeps its pid
// through a forced rescan and one that finds its files touched.
func TestAnAudiobookLibraryMakesBooksOfPlainMP3Folders(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	dir := t.TempDir()
	parts, err := fixtures.GenerateLooseMP3Book(dir)
	if err != nil {
		t.Fatal(err)
	}
	decodeStatus[Library](t, h.postJSON(t, "/api/v1/libraries", map[string]any{
		"name": "spoken", "path": dir, "media": "audiobook",
	}), 201, "an audiobook library")
	eventuallyKinds(t, h, "audiobook", map[string]string{"The Loose Chapters": "audiobook"})
	// The book shows with its first part read; the scan that made it
	// has the second to go.
	waitForScans(t, h)
	pid, names := bookOfParts(t, h, "The Loose Chapters")
	if len(names) != 2 {
		t.Fatalf("book %s parts = %q, want both chapters", pid, names)
	}

	h.rescanAndWaitWith(t, `{"force": true}`)
	later := time.Now().Add(time.Minute)
	for _, p := range parts {
		if err := os.Chtimes(p, later, later); err != nil {
			t.Fatal(err)
		}
	}
	h.rescanAndWait(t)
	if got := looseKinds(t, h); len(got) != 1 || got["The Loose Chapters"] != "audiobook" {
		t.Fatalf("after the rescans: %v, want the one book", got)
	}
	if again := h.itemTitled(t, h.token, "The Loose Chapters").Pid; again != pid {
		t.Fatalf("book pid after the rescans = %s, want %s", again, pid)
	}
}
