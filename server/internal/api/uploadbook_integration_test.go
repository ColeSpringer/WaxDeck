package api

import (
	"context"
	"fmt"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxdeck/server/internal/service"
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

// untitledBook writes the two-part MP3 book whose parts carry chapter
// titles and no album.
func untitledBook(t *testing.T) []string {
	t.Helper()
	parts, err := fixtures.GenerateUntitledMP3Book(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	return parts
}

// splitAlbumBook writes a two-part MP3 book whose parts disagree on
// their album.
func splitAlbumBook(t *testing.T) []string {
	t.Helper()
	dir := t.TempDir()
	var parts []string
	for i, album := range []string{"The Split Hours", "The Split Hours, Part Two"} {
		paths, err := fixtures.Generate(dir, fixtures.Spec{
			Name: fmt.Sprintf("%02d - Hour %d", i+1, i+1), Codec: fixtures.CodecMP3,
			Duration: time.Duration(3+i) * time.Second,
			Tags: map[string]string{"TITLE": fmt.Sprintf("Hour %d", i+1), "ARTIST": "Juno Marsh",
				"ALBUM": album, "TRACKNUMBER": fmt.Sprint(i + 1)},
		})
		if err != nil {
			t.Fatal(err)
		}
		parts = append(parts, paths...)
	}
	return parts
}

// uploadBookUnit uploads parts as one batch of the given grouping and
// medium from one folder, decides what it opened as it is, and rescans,
// answering the entry's title.
func uploadBookUnit(t *testing.T, h *harness, token, grouping, media, folder string, parts []string) string {
	t.Helper()
	titles := uploadBookUnits(t, h, token, grouping, media, folder, parts)
	if len(titles) != 1 {
		t.Fatalf("%s %s from one folder opened %d entries (%q), want one", grouping, media, len(titles), titles)
	}
	return titles[0]
}

// uploadBookUnits is uploadBookUnit for a batch that may open several
// entries, answering their titles.
func uploadBookUnits(t *testing.T, h *harness, token, grouping, media, folder string, parts []string) []string {
	t.Helper()
	sent := make([]sentFile, 0, len(parts))
	for _, p := range parts {
		sent = append(sent, sentFile{p, folder})
	}
	return uploadSentFiles(t, h, token, grouping, media, sent)
}

// sentFile is a file and the folder a batch sends it from.
type sentFile struct{ path, folder string }

// uploadSentFiles uploads files as one batch of the given grouping and
// medium, each from its own folder, decides what it opened as it is,
// and rescans, answering the entries' titles.
func uploadSentFiles(t *testing.T, h *harness, token, grouping, media string, files []sentFile) []string {
	t.Helper()
	batch := createBatch(t, h, token, grouping, media)
	for _, f := range files {
		uploadBatchMember(t, h, token, f.path, media, batch.Id, f.folder)
	}
	entryIDs := finalizeBatch(t, h, token, batch.Id).ReviewEntryIds
	drainMatches(t, h)
	var titles []string
	for _, id := range entryIDs {
		var title string
		if e := reviewAs(t, h, token, id); e.Title != nil {
			title = *e.Title
		}
		titles = append(titles, title)
		decideAs(t, h, token, id, map[string]any{"action": "as-is"})
	}
	h.rescanAndWait(t)
	return titles
}

// wholeBooks writes three single-file MP3 books, none numbered: two
// naming themselves as their album, one by its title alone.
func wholeBooks(t *testing.T) []string {
	t.Helper()
	dir := t.TempDir()
	var out []string
	for _, b := range []struct{ title, album, author string }{
		{"Emma", "Emma", "Jane Austen"},
		{"Dracula", "Dracula", "Bram Stoker"},
		{"Middlemarch", "", "George Eliot"},
	} {
		tags := map[string]string{"TITLE": b.title, "ARTIST": b.author}
		if b.album != "" {
			tags["ALBUM"] = b.album
		}
		paths, err := fixtures.Generate(dir, fixtures.Spec{
			Name: b.title, Codec: fixtures.CodecMP3, Duration: 3 * time.Second, Tags: tags,
		})
		if err != nil {
			t.Fatal(err)
		}
		out = append(out, paths...)
	}
	return out
}

// wantOneBook checks the library holds one book titled title, of two
// parts, by author, and no item titled after either chapter.
func wantOneBook(t *testing.T, h *harness, title, author string, chapters ...string) {
	t.Helper()
	pid, names := bookOfParts(t, h, title)
	if !strings.HasPrefix(pid, "bk-") || len(names) != 2 || names[0] == names[1] {
		t.Fatalf("book %q = %s parts %q, want one book of two parts", title, pid, names)
	}
	detail := decode[BookDetail](t, get(t, h.ts, "/api/v1/books/"+pid, h.token))
	if len(detail.Authors) != 1 || detail.Authors[0] != author {
		t.Errorf("book %q authors = %q, want %q", title, detail.Authors, author)
	}
	for _, it := range decode[ItemPage](t, get(t, h.ts, "/api/v1/library/items?limit=500", h.token)).Items {
		if slices.Contains(chapters, it.Title) {
			t.Errorf("item %s %q is a chapter listed on its own", it.Pid, it.Title)
		}
	}
}

// wantPartsInOrder checks the library holds one book titled title, by
// author, whose parts are the chapters in reading order, and no item
// titled after a chapter. Parts land under names numbered for the book,
// so each chapter is told by its length: the i-th lasts 3+i seconds.
func wantPartsInOrder(t *testing.T, h *harness, title, author string, chapters ...string) {
	t.Helper()
	pid := h.itemTitled(t, h.token, title).Pid
	detail := decodeStatus[BookDetail](t, get(t, h.ts, "/api/v1/books/"+pid, h.token), 200, "book "+title)
	var seconds []int64
	for _, p := range detail.Parts {
		seconds = append(seconds, (p.DurationMs+500)/1000)
	}
	if !strings.HasPrefix(pid, "bk-") || len(seconds) != len(chapters) {
		t.Fatalf("book %q = %s parts of %v seconds, want one book of the parts %q", title, pid, seconds, chapters)
	}
	for i := range chapters {
		if seconds[i] != int64(3+i) {
			t.Errorf("book %q parts last %v seconds, want %q in reading order", title, seconds, chapters)
			break
		}
	}
	if len(detail.Authors) != 1 || detail.Authors[0] != author {
		t.Errorf("book %q authors = %q, want %q", title, detail.Authors, author)
	}
	for _, it := range decode[ItemPage](t, get(t, h.ts, "/api/v1/library/items?limit=500", h.token)).Items {
		if slices.Contains(chapters, it.Title) {
			t.Errorf("item %s %q is a chapter listed on its own", it.Pid, it.Title)
		}
	}
}

// Audiobook parts that do not share an album still make one book, named
// never after a chapter: from the folder, what the file names share, or
// a fixed title. Parts sent as one book whose albums disagree are one
// book named from their folder. Whole books picked together stay apart,
// tags untouched, and music keeps its tags.
func TestAudiobookPartsWithNoSharedAlbumMakeOneBook(t *testing.T) {
	t.Parallel()

	for _, grouping := range []string{"album", "auto"} {
		t.Run("parts with no album as "+grouping, func(t *testing.T) {
			t.Parallel()
			h, bob := joinHarness(t)
			if title := uploadBookUnit(t, h, bob, grouping, "audiobook", "Wren Hollis/The Untitled Hours", untitledBook(t)); title != "The Untitled Hours" {
				t.Errorf("review entry titled %q, want the book's title", title)
			}
			wantOneBook(t, h, "The Untitled Hours", "Wren Hollis", "Chapter 1", "Chapter 2")
		})
	}

	t.Run("parts numbered with no total and named for their chapters", func(t *testing.T) {
		t.Parallel()
		h, bob := joinHarness(t)
		dir := t.TempDir()
		chapters := []string{"The Lighthouse", "A Storm Breaks", "Harbour Lights"}
		var parts []string
		for i, chapter := range chapters {
			paths, err := fixtures.Generate(dir, fixtures.Spec{
				Name: chapter, Codec: fixtures.CodecMP3, Duration: time.Duration(3+i) * time.Second,
				Tags: map[string]string{"TITLE": chapter, "ARTIST": "Wren Hollis", "TRACKNUMBER": fmt.Sprint(i + 1)},
			})
			if err != nil {
				t.Fatal(err)
			}
			parts = append(parts, paths...)
		}
		if title := uploadBookUnit(t, h, bob, "auto", "audiobook", "Wren Hollis/The Long Harbour", parts); title != "The Long Harbour" {
			t.Errorf("review entry titled %q, want the folder's name", title)
		}
		wantPartsInOrder(t, h, "The Long Harbour", "Wren Hollis", chapters...)
	})

	t.Run("parts in part folders", func(t *testing.T) {
		t.Parallel()
		h, bob := joinHarness(t)
		dir := t.TempDir()
		var sent []sentFile
		for _, f := range []struct {
			folder, name string
			place        int
		}{
			{"Wren Hollis/The Parted Hours/Part 2", "01 - Chapter 3", 2},
			{"Wren Hollis/The Parted Hours/Part 1", "02 - Chapter 2", 1},
			{"Wren Hollis/The Parted Hours/Part 1", "01 - Chapter 1", 0},
			{"Wren Hollis/The Parted Hours/Part 2", "02 - Chapter 4", 3},
			{"Wren Hollis/The Other Hours", "01 - Opening", 0},
			{"Wren Hollis/The Other Hours", "02 - Closing", 1},
		} {
			chapter := strings.SplitN(f.name, " - ", 2)[1]
			paths, err := fixtures.Generate(dir, fixtures.Spec{
				Name: f.name, Codec: fixtures.CodecMP3, Duration: time.Duration(3+f.place) * time.Second,
				Tags: map[string]string{"TITLE": chapter, "ARTIST": "Wren Hollis", "TRACKNUMBER": f.name[:2]},
			})
			if err != nil {
				t.Fatal(err)
			}
			sent = append(sent, sentFile{paths[0], f.folder})
		}
		titles := uploadSentFiles(t, h, bob, "auto", "audiobook", sent)
		slices.Sort(titles)
		if want := []string{"The Other Hours", "The Parted Hours"}; !slices.Equal(titles, want) {
			t.Fatalf("entries = %q, want one per book folder %q", titles, want)
		}
		wantPartsInOrder(t, h, "The Parted Hours", "Wren Hollis", "Chapter 1", "Chapter 2", "Chapter 3", "Chapter 4")
		wantPartsInOrder(t, h, "The Other Hours", "Wren Hollis", "Opening", "Closing")
	})

	t.Run("parts with conflicting albums", func(t *testing.T) {
		t.Parallel()
		h, bob := joinHarness(t)
		title := uploadBookUnit(t, h, bob, "album", "audiobook", "Juno Marsh/The Divided Hours/CD1", splitAlbumBook(t))
		if title != "The Divided Hours" {
			t.Errorf("review entry titled %q, want the folder's name", title)
		}
		wantOneBook(t, h, "The Divided Hours", "Juno Marsh", "Hour 1", "Hour 2",
			"The Split Hours", "The Split Hours, Part Two")
	})

	for name, folder := range map[string]string{"picked loosely": "", "from one folder": "Shelf"} {
		t.Run("whole books "+name, func(t *testing.T) {
			t.Parallel()
			h, bob := joinHarness(t)
			titles := uploadBookUnits(t, h, bob, "auto", "audiobook", folder, wholeBooks(t))
			slices.Sort(titles)
			if want := []string{"Dracula", "Emma", "Middlemarch"}; !slices.Equal(titles, want) {
				t.Fatalf("entries = %q, want one per book %q", titles, want)
			}
			for title, author := range map[string]string{"Emma": "Jane Austen", "Dracula": "Bram Stoker", "Middlemarch": "George Eliot"} {
				pid, names := bookOfParts(t, h, title)
				detail := decode[BookDetail](t, get(t, h.ts, "/api/v1/books/"+pid, h.token))
				if len(names) != 1 || len(detail.Authors) != 1 || detail.Authors[0] != author {
					t.Errorf("book %q = %s parts %q by %q, want one part by %q", title, pid, names, detail.Authors, author)
				}
			}
		})
	}

	t.Run("parts from no folder named alike", func(t *testing.T) {
		t.Parallel()
		h, bob := joinHarness(t)
		dir := t.TempDir()
		var parts []string
		for i := range 2 {
			paths, err := fixtures.Generate(dir, fixtures.Spec{
				Name: fmt.Sprintf("The Quiet Year - Part %02d", i+1), Codec: fixtures.CodecMP3,
				Duration: time.Duration(3+i) * time.Second,
				Tags:     map[string]string{"TITLE": fmt.Sprintf("Chapter %d", i+1), "ARTIST": "Odile Fen"},
			})
			if err != nil {
				t.Fatal(err)
			}
			parts = append(parts, paths...)
		}
		uploadBookUnit(t, h, bob, "album", "audiobook", "", parts)
		wantOneBook(t, h, "The Quiet Year", "Odile Fen", "Chapter 1", "Chapter 2")
	})

	t.Run("parts from no folder named only by number", func(t *testing.T) {
		t.Parallel()
		h, bob := joinHarness(t)
		title := uploadBookUnit(t, h, bob, "auto", "audiobook", "", untitledBook(t))
		if !strings.HasPrefix(title, "Untitled audiobook (") {
			t.Errorf("review entry titled %q, want an untitled book's title", title)
		}
		wantOneBook(t, h, title, "Wren Hollis", "Chapter 1", "Chapter 2")
	})

	t.Run("several whole books from one folder", func(t *testing.T) {
		t.Parallel()
		h, bob := joinHarness(t)
		dir := t.TempDir()
		batch := createBatch(t, h, bob, "auto", "audiobook")
		for i, title := range []string{"The First Whole Book", "The Second Whole Book"} {
			m4b, err := fixtures.GenerateM4B(dir, fixtures.Spec{
				Name: fmt.Sprintf("whole-%d", i+1), Duration: time.Duration(3+i) * time.Second,
				Tags: map[string]string{"TITLE": title, "ARTIST": "Pia Sorel"},
			})
			if err != nil {
				t.Fatal(err)
			}
			uploadBatchMember(t, h, bob, m4b, "audiobook", batch.Id, "Pia Sorel")
		}
		if ids := finalizeBatch(t, h, bob, batch.Id).ReviewEntryIds; len(ids) != 2 {
			t.Fatalf("two .m4b books from one folder opened %d entries, want one each", len(ids))
		}
	})

	t.Run("a music batch", func(t *testing.T) {
		t.Parallel()
		h, bob := joinHarness(t)
		uploadBookUnit(t, h, bob, "album", "music", "Wren Hollis/The Untitled Hours", untitledBook(t))
		for _, chapter := range []string{"Chapter 1", "Chapter 2"} {
			it := h.itemTitled(t, h.token, chapter)
			if !strings.HasPrefix(it.Pid, "tr-") || (it.Album != nil && *it.Album != "") {
				t.Errorf("music %q = %s album %v, want a track whose tags were left alone", chapter, it.Pid, it.Album)
			}
		}
	})
}

// An audiobook acquired from a list is one book titled by the list, even
// when the videos name only their chapters, and even when the list is
// titled like one of them.
func TestAnAudiobookListAcquiresAsOneBook(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct{ list, chapter string }{
		{"Test Playlist", "Chapter 1"},
		{"Chapter 1", ""},
	} {
		t.Run("titled "+tc.list, func(t *testing.T) {
			t.Parallel()
			parts := untitledBook(t)
			src := &fakeAcquireSource{
				playlistURL: "https://tube.example/playlist?list=PLbook",
				listTitle:   tc.list,
				entries: []struct{ title, url string }{
					{"Chapter 1", "https://tube.example/watch?v=ch1"},
					{"Chapter 2", "https://tube.example/watch?v=ch2"},
				},
				files: map[string]string{
					"https://tube.example/watch?v=ch1": parts[0],
					"https://tube.example/watch?v=ch2": parts[1],
				},
			}
			h := newHarnessWith(t, func(cfg *service.Config) {
				cfg.SourceProviders = append(cfg.SourceProviders, src)
				for i := range cfg.Roots {
					cfg.Roots[i].Managed = true
				}
				cfg.AllowPrivateFeedHosts = true
			})
			task := decodeStatus[ToolTask](t, h.postJSON(t, "/api/v1/acquisitions",
				map[string]any{"url": src.playlistURL, "mediaType": "audiobook"}), 202, "acquisition")
			drainTools(t, h)
			got := decode[ToolTask](t, get(t, h.ts, "/api/v1/tools/tasks/"+task.Id, h.token))
			if got.State != "done" || got.ResultPids == nil || len(*got.ResultPids) != 1 {
				t.Fatalf("acquire task = %+v, want one entry for the list", got)
			}
			entryID := (*got.ResultPids)[0]
			drainMatches(t, h)
			if e := reviewAs(t, h, h.token, entryID); e.Title == nil || *e.Title != tc.list {
				t.Errorf("review entry titled %v, want the list's title %q", e.Title, tc.list)
			}
			decideAs(t, h, h.token, entryID, map[string]any{"action": "as-is"})
			h.rescanAndWait(t)
			chapters := []string{"Chapter 2"}
			if tc.chapter != "" {
				chapters = append(chapters, tc.chapter)
			}
			wantOneBook(t, h, tc.list, "Wren Hollis", chapters...)
		})
	}
}

// A unit sent as music and decided as an audiobook lands as one book:
// the decision's medium reaches the import, and becomes the entry's.
// A medium the decision cannot import as is refused before anything
// lands. The entry says its medium is fixed once its files are in.
func TestAMusicUnitDecidedAsAnAudiobookLandsOneBook(t *testing.T) {
	t.Parallel()
	h, bob := joinHarness(t)
	batch := createBatch(t, h, bob, "album", "music")
	for _, p := range untitledBook(t) {
		uploadBatchMember(t, h, bob, p, "music", batch.Id, "Wren Hollis/The Untitled Hours")
	}
	ids := finalizeBatch(t, h, bob, batch.Id).ReviewEntryIds
	if len(ids) != 1 {
		t.Fatalf("the batch opened %d entries, want one", len(ids))
	}
	drainMatches(t, h)
	if e := reviewAs(t, h, bob, ids[0]); e.MediumFixed != nil {
		t.Errorf("staged entry mediumFixed = %v, want absent", *e.MediumFixed)
	}
	path := "/api/v1/review/queue/" + ids[0] + "/decide"
	if e := decodeStatus[Error](t, postJSONAs(t, h, bob, path, map[string]any{"action": "approve", "mediaType": "audiobook"}),
		400, "approve as audiobook"); e.Code != "invalid-request" || !strings.Contains(e.Message, "audiobook") {
		t.Errorf("approve as audiobook = %q %q, want invalid-request over the audiobook", e.Code, e.Message)
	}
	res := decideAs(t, h, bob, ids[0], map[string]any{"action": "as-is", "mediaType": "audiobook"})
	if res.Entry.MediaType != "audiobook" {
		t.Errorf("decided entry medium = %q, want audiobook", res.Entry.MediaType)
	}
	if e := reviewAs(t, h, bob, ids[0]); e.MediumFixed == nil || !*e.MediumFixed {
		t.Errorf("decided entry mediumFixed = %v, want true", e.MediumFixed)
	}
	h.rescanAndWait(t)
	wantOneBook(t, h, "The Untitled Hours", "Wren Hollis", "Chapter 1", "Chapter 2")
}

// audiobookList is a server reading a four-chapter audiobook list whose
// failing chapter's first fetches fail, times of them.
func audiobookList(t *testing.T, failing, times int) (*harness, *fakeAcquireSource) {
	t.Helper()
	dir := t.TempDir()
	src := &fakeAcquireSource{
		playlistURL: "https://tube.example/playlist?list=PLretry",
		files:       map[string]string{},
		fails:       map[string]int{fmt.Sprintf("https://tube.example/watch?v=ch%d", failing): times},
	}
	for i := range 4 {
		paths, err := fixtures.Generate(dir, fixtures.Spec{
			Name: fmt.Sprintf("%02d - Chapter %d", i+1, i+1), Codec: fixtures.CodecMP3,
			Duration: time.Duration(3+i) * time.Second,
			Tags:     map[string]string{"TITLE": fmt.Sprintf("Chapter %d", i+1), "ARTIST": "Wren Hollis"},
		})
		if err != nil {
			t.Fatal(err)
		}
		url := fmt.Sprintf("https://tube.example/watch?v=ch%d", i+1)
		src.entries = append(src.entries, struct{ title, url string }{fmt.Sprintf("Chapter %d", i+1), url})
		src.files[url] = paths[0]
	}
	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.SourceProviders = append(cfg.SourceProviders, src)
		for i := range cfg.Roots {
			cfg.Roots[i].Managed = true
		}
		cfg.AllowPrivateFeedHosts = true
	})
	return h, src
}

// decideAudiobookEntries takes every pending entry as it is, oldest first,
// after checking they hold the files counts says, and wants one book
// holding each chapter once, in the list's order.
func decideAudiobookEntries(t *testing.T, h *harness, counts ...int) {
	t.Helper()
	drainMatches(t, h)
	page := decode[ReviewEntryPage](t, get(t, h.ts, "/api/v1/review/queue?status=pending", h.token))
	slices.SortFunc(page.Entries, func(a, b ReviewEntry) int { return a.CreatedAt.Compare(b.CreatedAt) })
	var got []int
	for _, e := range page.Entries {
		got = append(got, e.TrackCount)
	}
	if !slices.Equal(got, counts) {
		t.Fatalf("pending entries hold %v files, want %v", got, counts)
	}
	for _, e := range page.Entries {
		decideAs(t, h, h.token, e.Id, map[string]any{"action": "as-is"})
	}
	h.rescanAndWait(t)
	pid := h.itemTitled(t, h.token, "Test Playlist").Pid
	detail := decodeStatus[BookDetail](t, get(t, h.ts, "/api/v1/books/"+pid, h.token), 200, "book")
	var lengths []int64
	for _, p := range detail.Parts {
		lengths = append(lengths, (p.DurationMs+500)/1000)
	}
	if want := []int64{3, 4, 5, 6}; !slices.Equal(lengths, want) {
		t.Errorf("book %s parts last %v seconds, want each chapter once in list order %v", pid, lengths, want)
	}
}

// expireToolWait ends a task's wait, as its retryAt passing would.
func expireToolWait(t *testing.T, h *harness, taskID string) {
	t.Helper()
	if _, err := h.store.Writer().ExecContext(context.Background(), `UPDATE tool_tasks SET lease_until_ns = 0 WHERE id = ?`, taskID); err != nil {
		t.Fatal(err)
	}
}

// An audiobook list whose fetch failed waits and tries again, fetching
// only what is left, and ends as one book holding each chapter once, in
// the list's order, however few chapters the next try stages.
func TestAnAudiobookListRetriedAfterAFailedFetchIsOneBook(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		failing int
		counts  []int
	}{
		{3, []int{2, 2}},
		{4, []int{3, 1}},
	} {
		t.Run(fmt.Sprintf("chapter %d", tc.failing), func(t *testing.T) {
			t.Parallel()
			h, src := audiobookList(t, tc.failing, 1)
			task := decodeStatus[ToolTask](t, h.postJSON(t, "/api/v1/acquisitions",
				map[string]any{"url": src.playlistURL, "mediaType": "audiobook"}), 202, "acquisition")
			drainTools(t, h)
			if got := decode[ToolTask](t, get(t, h.ts, "/api/v1/tools/tasks/"+task.Id, h.token)); got.WaitReason == nil || *got.WaitReason != "source-retry" {
				t.Fatalf("first try = %+v, want it waiting to try the failed chapter again", got)
			}
			expireToolWait(t, h, task.Id)
			drainTools(t, h)
			if got := decode[ToolTask](t, get(t, h.ts, "/api/v1/tools/tasks/"+task.Id, h.token)); got.State != "done" {
				t.Fatalf("the next try = %+v, want it done", got)
			}
			// The next try fetched only what the first did not stage.
			decideAudiobookEntries(t, h, tc.counts...)
		})
	}
}

// An audiobook list acquired again after its first acquisition finally
// failed fetches the whole list again; the two entries overlap, and the
// book still holds each chapter once, in the list's order.
func TestAnAudiobookListAcquiredAgainAfterItFailedIsOneBook(t *testing.T) {
	t.Parallel()
	h, src := audiobookList(t, 3, 4)
	first := decodeStatus[ToolTask](t, h.postJSON(t, "/api/v1/acquisitions",
		map[string]any{"url": src.playlistURL, "mediaType": "audiobook"}), 202, "first acquisition")
	drainTools(t, h)
	for range 3 {
		expireToolWait(t, h, first.Id)
		drainTools(t, h)
	}
	if got := decode[ToolTask](t, get(t, h.ts, "/api/v1/tools/tasks/"+first.Id, h.token)); got.State != "failed" {
		t.Fatalf("first acquisition = %+v, want it failed at the third chapter after its waits", got)
	}
	second := decodeStatus[ToolTask](t, h.postJSON(t, "/api/v1/acquisitions",
		map[string]any{"url": src.playlistURL, "mediaType": "audiobook"}), 202, "second acquisition")
	drainTools(t, h)
	if got := decode[ToolTask](t, get(t, h.ts, "/api/v1/tools/tasks/"+second.Id, h.token)); got.State != "done" {
		t.Fatalf("second acquisition = %+v, want it done", got)
	}
	decideAudiobookEntries(t, h, 2, 4)
}
