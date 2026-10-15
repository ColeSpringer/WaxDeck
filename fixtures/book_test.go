package fixtures_test

import (
	"context"
	"path/filepath"
	"testing"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/config"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"

	"github.com/colespringer/waxdeck/fixtures"
)

// TestBookFixturesScanAsBooks is the point of the book fixtures: a real
// WaxBin scan over a root holding them must classify both as book items,
// group the three-part book into ONE item backed by three files in
// reading order, and read the chaptered book's embedded markers back.
func TestBookFixturesScanAsBooks(t *testing.T) {
	ctx := context.Background()
	root := t.TempDir()
	if _, err := fixtures.GenerateBook(root); err != nil {
		t.Fatal(err)
	}
	if _, err := fixtures.GenerateChapteredBook(root); err != nil {
		t.Fatal(err)
	}

	lib, err := waxbin.Open(ctx, waxbin.Options{
		DBPath: filepath.Join(t.TempDir(), "catalog.db"),
		Roots:  []config.Root{{Path: root, Mode: model.ModeInPlace}},
	})
	if err != nil {
		t.Fatalf("open catalog: %v", err)
	}
	t.Cleanup(func() { _ = lib.Close() })

	res, err := lib.Scan(ctx, waxbin.ScanRequest{})
	if err != nil {
		t.Fatalf("scan: %v", err)
	}
	if res.Total.AudioFiles != 4 {
		t.Fatalf("scanned %d audio files, want 4 (3 parts + 1 chaptered)", res.Total.AudioFiles)
	}

	books, err := lib.Query(ctx, query.New(query.EntityItems).Where("kind", query.OpIs, "book").Build(), "")
	if err != nil {
		t.Fatalf("query books: %v", err)
	}
	if len(books) != 2 {
		for _, b := range books {
			t.Logf("book item: %q by %q", b.Title, b.Artist)
		}
		t.Fatalf("kind=book items = %d, want 2 (multi-part grouped + chaptered)", len(books))
	}

	byTitle := map[string]model.PID{}
	for _, b := range books {
		byTitle[b.Title] = b.PID
		if b.Artist != "Ada Author" {
			t.Errorf("book %q author = %q, want Ada Author", b.Title, b.Artist)
		}
	}

	t.Run("multi-file", func(t *testing.T) {
		pid, ok := byTitle["The Fixture Book"]
		if !ok {
			t.Fatalf("no book titled The Fixture Book in %v", byTitle)
		}
		d, err := lib.Book(ctx, pid)
		if err != nil {
			t.Fatalf("Book: %v", err)
		}
		if len(d.Files) != 3 {
			t.Fatalf("parts = %d, want 3: %+v", len(d.Files), d.Files)
		}
		wantOrder := []string{"01 - Part One.m4b", "02 - Part Two.m4b", "03 - Part Three.m4b"}
		for i, part := range d.Files {
			if got := filepath.Base(part.DisplayPath); got != wantOrder[i] {
				t.Errorf("part %d = %s, want %s", i, got, wantOrder[i])
			}
		}
		// One synthetic whole-file chapter per part keeps the book
		// navigable part-by-part.
		if len(d.Chapters) != 3 {
			t.Errorf("chapters = %d, want 3 (one per part)", len(d.Chapters))
		}
	})

	t.Run("chaptered", func(t *testing.T) {
		pid, ok := byTitle["The Chaptered Fixture"]
		if !ok {
			t.Fatalf("no book titled The Chaptered Fixture in %v", byTitle)
		}
		d, err := lib.Book(ctx, pid)
		if err != nil {
			t.Fatalf("Book: %v", err)
		}
		if len(d.Files) != 1 {
			t.Fatalf("files = %d, want 1", len(d.Files))
		}
		if len(d.Chapters) != 3 {
			t.Fatalf("chapters = %d, want 3: %+v", len(d.Chapters), d.Chapters)
		}
		wantTitles := []string{"Opening", "Middle", "Ending"}
		for i, ch := range d.Chapters {
			if ch.Title != wantTitles[i] {
				t.Errorf("chapter %d = %q, want %q", i, ch.Title, wantTitles[i])
			}
		}
	})
}

// The loose MP3 book is a book only where its library says so: a plain
// root catalogs its parts as two tracks, and an audiobook root as one
// book of two parts.
func TestLooseMP3BookIsABookOnlyInAnAudiobookRoot(t *testing.T) {
	ctx := context.Background()
	for _, tc := range []struct {
		media model.MediaType
		kind  string
		want  int
	}{
		{media: "", kind: "track", want: 2},
		{media: model.MediaAudiobook, kind: "book", want: 1},
	} {
		root := t.TempDir()
		paths, err := fixtures.GenerateLooseMP3Book(root)
		if err != nil || len(paths) != 2 {
			t.Fatalf("parts = %v (%v), want two", paths, err)
		}
		lib, err := waxbin.Open(ctx, waxbin.Options{
			DBPath: filepath.Join(t.TempDir(), "catalog.db"),
			Roots:  []config.Root{{Path: root, Mode: model.ModeInPlace, Media: tc.media}},
		})
		if err != nil {
			t.Fatalf("open catalog: %v", err)
		}
		t.Cleanup(func() { _ = lib.Close() })
		if _, err := lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
			t.Fatalf("scan: %v", err)
		}
		items, err := lib.Query(ctx, query.New(query.EntityItems).Where("kind", query.OpIs, tc.kind).Build(), "")
		if err != nil {
			t.Fatal(err)
		}
		if len(items) != tc.want {
			t.Errorf("media %q: %d %s items, want %d", tc.media, len(items), tc.kind, tc.want)
		}
	}
}
