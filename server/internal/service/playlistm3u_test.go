package service

import (
	"path/filepath"
	"strings"
	"testing"
)

// The preview reads a document as the import does: a file named twice
// through two spellings is one entry and a merged line carrying the same
// item, a path naming nothing is unmatched, and for a reader who cannot
// see the item the merged line shares the line before's verdict. Nothing
// is created either way.
func TestPreviewM3UReadsTheMergedLine(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	blind := blindReader(t, ctx, svc, uc)
	track := fixtureItemPIDs(t, ctx, svc, uc)[0]
	it, err := svc.getVisibleItem(ctx, uc, track)
	if err != nil {
		t.Fatal(err)
	}
	paths := []string{it.DisplayPath, filepath.Base(it.DisplayPath), "nowhere/missing.flac"}
	doc := "#EXTM3U\n" + strings.Join(paths, "\n") + "\n"
	listed := func() int {
		t.Helper()
		page, err := svc.Playlists(ctx, uc, "", "", 200)
		if err != nil {
			t.Fatal(err)
		}
		return len(page.Playlists)
	}
	before := listed()

	got, err := svc.PreviewPlaylistM3U(ctx, uc, doc)
	if err != nil {
		t.Fatal(err)
	}
	if got.Matched != 1 || got.Merged != 1 || got.Unmatched != 1 || len(got.Lines) != 3 {
		t.Fatalf("preview = %+v, want one matched, one merged, one unmatched", got)
	}
	for i, want := range []string{M3uMatched, M3uMerged, M3uUnmatched} {
		ln := got.Lines[i]
		hasItem := want != M3uUnmatched
		if ln.Path != paths[i] || ln.Outcome != want || (ln.Item != nil) != hasItem ||
			(hasItem && ln.Item.PID != track) {
			t.Errorf("line %d = %+v, want %s %s naming %s: %v", i, ln, paths[i], want, track, hasItem)
		}
	}

	theirs, err := svc.PreviewPlaylistM3U(ctx, blind, doc)
	if err != nil {
		t.Fatal(err)
	}
	if theirs.Matched != 0 || theirs.Merged != 0 || theirs.Unmatched != 3 {
		t.Fatalf("restricted preview = %+v, want every line unmatched", theirs)
	}
	for i, ln := range theirs.Lines {
		if ln.Item != nil {
			t.Errorf("restricted line %d carries %+v, want no item", i, ln.Item)
		}
	}
	if n := listed(); n != before {
		t.Fatalf("playlists after two previews = %d, want %d", n, before)
	}

	// The same path twice in a row is a repeat, not another path to the
	// item: two entries, in the preview and the import alike.
	twice := "#EXTM3U\n" + it.DisplayPath + "\n" + it.DisplayPath + "\n"
	repeat, err := svc.PreviewPlaylistM3U(ctx, uc, twice)
	if err != nil {
		t.Fatal(err)
	}
	if repeat.Matched != 2 || repeat.Merged != 0 || len(repeat.Lines) != 2 ||
		repeat.Lines[1].Outcome != M3uMatched || repeat.Lines[1].Item == nil || repeat.Lines[1].Item.PID != track {
		t.Fatalf("a path given twice = %+v, want two matched lines naming %s", repeat, track)
	}
	imported, err := svc.ImportPlaylistM3U(ctx, uc, "Twice", "", twice)
	if err != nil {
		t.Fatal(err)
	}
	if got := memberPIDs(t, ctx, svc, uc, imported.Playlist.PID); !samePIDs(got, []string{track, track}) {
		t.Fatalf("the import of a path given twice holds %v, want %s twice", got, track)
	}
}
