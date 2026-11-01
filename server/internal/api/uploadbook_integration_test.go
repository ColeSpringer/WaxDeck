package api

import (
	"testing"

	"github.com/colespringer/waxdeck/fixtures"
)

// looseBook writes the two-part MP3 book outside the library.
func looseBook(t *testing.T) []string {
	t.Helper()
	parts, err := fixtures.GenerateLooseMP3Book(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	return parts
}

// bookOfParts finds the one book titled title and reads its parts'
// display names in reading order.
func bookOfParts(t *testing.T, h *harness, title string) (string, []string) {
	t.Helper()
	pid := h.itemTitled(t, h.token, title).Pid
	detail := decodeStatus[BookDetail](t, get(t, h.ts, "/api/v1/books/"+pid, h.token), 200, "book "+title)
	var names []string
	for _, p := range detail.Parts {
		if p.DisplayName != nil {
			names = append(names, *p.DisplayName)
		}
	}
	return pid, names
}

// wantTwoParts checks a book holds its two chapters in reading order
// under names of their own.
func wantTwoParts(t *testing.T, h *harness, label string) {
	t.Helper()
	pid, names := bookOfParts(t, h, "The Loose Chapters")
	if len(names) != 2 || names[0] == names[1] {
		t.Fatalf("%s: book %s parts = %q, want two under names of their own", label, pid, names)
	}
}

// Two MP3 parts uploaded as one audiobook import whole: as one batch
// decided by a person, as one batch that declined identification, as
// one folder the server groups itself, and as two sessions sent in the
// wrong order. Files uploaded as separate books stay separate.
func TestMultiPartAudiobookBatchImportsWhole(t *testing.T) {
	t.Parallel()

	t.Run("decided", func(t *testing.T) {
		t.Parallel()
		h, bob := joinHarness(t)
		parts := looseBook(t)
		batch := createBatch(t, h, bob, "album", "audiobook")
		var ids []string
		for _, p := range parts {
			ids = append(ids, uploadBatchMember(t, h, bob, p, "audiobook", batch.Id, "").Id)
		}
		entryID := finalizeBatch(t, h, bob, batch.Id).ReviewEntryIds[0]
		drainMatches(t, h)
		decideAs(t, h, bob, entryID, map[string]any{"action": "as-is"})
		for _, id := range ids {
			if u := decode[Upload](t, reqAs(t, h, "GET", "/api/v1/uploads/"+id, bob, nil)); u.State != "imported" {
				t.Fatalf("session %s = %s, want imported", id, u.State)
			}
		}
		h.rescanAndWait(t)
		wantTwoParts(t, h, "decided")
		// WaxBin logs that it found no primary or alternate file to stamp
		// for part two (a part is neither); the book, stamped at part
		// one, keeps its origin.
		pid := h.itemTitled(t, h.token, "The Loose Chapters").Pid
		if acq := h.itemMeta(t, pid).Acquisition; acq == nil || acq.SourceType != "manual" {
			t.Fatalf("book acquisition = %+v, want its manual origin", acq)
		}
	})

	t.Run("declined identification", func(t *testing.T) {
		t.Parallel()
		h, bob := joinHarness(t)
		parts := looseBook(t)
		batch := decodeStatus[UploadBatch](t, postJSONAs(t, h, bob, "/api/v1/uploads/batches",
			map[string]any{"grouping": "album", "mediaType": "audiobook", "identify": false}), 201, "batch")
		for _, p := range parts {
			uploadBatchMember(t, h, bob, p, "audiobook", batch.Id, "")
		}
		entryID := finalizeBatch(t, h, bob, batch.Id).ReviewEntryIds[0]
		if e := reviewAs(t, h, bob, entryID); e.Status != "as-is" {
			t.Fatalf("declined unit = %s, want imported as-is at finalize", e.Status)
		}
		wantTwoParts(t, h, "declined")
	})

	t.Run("auto from a folder", func(t *testing.T) {
		t.Parallel()
		h, bob := joinHarness(t)
		parts := looseBook(t)
		batch := createBatch(t, h, bob, "auto", "audiobook")
		for _, p := range parts {
			uploadBatchMember(t, h, bob, p, "audiobook", batch.Id, "The Loose Chapters")
		}
		entryIDs := finalizeBatch(t, h, bob, batch.Id).ReviewEntryIds
		if len(entryIDs) != 1 {
			t.Fatalf("auto from one folder opened %d entries, want one book", len(entryIDs))
		}
		drainMatches(t, h)
		decideAs(t, h, bob, entryIDs[0], map[string]any{"action": "as-is"})
		h.rescanAndWait(t)
		wantTwoParts(t, h, "auto from a folder")
	})

	t.Run("separate books", func(t *testing.T) {
		t.Parallel()
		h, bob := joinHarness(t)
		first := looseBook(t)[0]
		lectures, err := fixtures.GenerateMisfiledBook(t.TempDir())
		if err != nil {
			t.Fatal(err)
		}
		batch := createBatch(t, h, bob, "tracks", "audiobook")
		for _, p := range []string{first, lectures[0]} {
			uploadBatchMember(t, h, bob, p, "audiobook", batch.Id, "")
		}
		entryIDs := finalizeBatch(t, h, bob, batch.Id).ReviewEntryIds
		if len(entryIDs) != 2 {
			t.Fatalf("tracks opened %d entries, want one per file", len(entryIDs))
		}
		drainMatches(t, h)
		for _, id := range entryIDs {
			decideAs(t, h, bob, id, map[string]any{"action": "as-is"})
		}
		h.rescanAndWait(t)
		for _, title := range []string{"The Loose Chapters", "The Misfiled Lectures"} {
			if pid, names := bookOfParts(t, h, title); len(names) != 1 {
				t.Fatalf("book %q (%s) parts = %q, want one book of its own", title, pid, names)
			}
		}
	})

	t.Run("out of order", func(t *testing.T) {
		t.Parallel()
		h, bob := joinHarness(t)
		parts := looseBook(t)
		for _, p := range []string{parts[1], parts[0]} {
			importAs(t, h, bob, p, "audiobook")
		}
		pid, names := bookOfParts(t, h, "The Loose Chapters")
		if len(names) != 2 || names[0] == names[1] {
			t.Fatalf("book %s parts = %q, want two", pid, names)
		}
		detail := decode[BookDetail](t, get(t, h.ts, "/api/v1/books/"+pid, h.token))
		if detail.Parts[0].DurationMs >= detail.Parts[1].DurationMs {
			t.Fatalf("parts = %+v, want chapter one (the shorter) first", detail.Parts)
		}
	})
}
