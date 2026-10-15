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
// decided by a person, as one batch that declined identification, and
// as two sessions sent in the wrong order.
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
