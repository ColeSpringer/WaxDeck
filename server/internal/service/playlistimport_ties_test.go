package service

import (
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxdeck/fixtures"
)

// An entry naming a recording two items share an id for lands on the
// copy whose album it names: the tie on the id is taken only when nothing
// else in the entry tells the copies apart, and then it takes the copy
// with the lowest pid.
func TestPlaylistImportKeepsTheCopyTheAlbumNames(t *testing.T) {
	t.Parallel()
	ctx, f := newMigrateFixtureWith(t, copiesOfOneRecording)
	const mbid = "00000000-0000-4000-8000-0000000000dd"
	namesakes := f.itemsTitled(t, ctx, "Twice Song")
	if len(namesakes) != 2 {
		t.Fatalf("namesakes = %d items, want two", len(namesakes))
	}
	for _, it := range namesakes {
		if err := f.svc.lib.EditFields(ctx, it.PID, map[string]string{"mbid": mbid}, waxbin.EditOptions{}); err != nil {
			t.Fatal(err)
		}
	}
	lowest, named := namesakes[0], namesakes[1]

	out, err := f.svc.Playlists.ImportStreamingPlaylist(ctx, f.uc, PlaylistImportInput{
		Source: "portable", Name: "Named copy",
		Refs: []PortableRefDTO{
			{Kind: "track", MBID: mbid, Artist: "Twice Artist", Title: "Twice Song", Album: named.Album},
			{Kind: "track", MBID: mbid, Artist: "Twice Artist", Title: "Twice Song"},
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	if out.Resolved != 2 {
		t.Fatalf("import = %+v, want both entries resolved", out)
	}
	want := []string{apiPID(PrefixTrack, named.PID), apiPID(PrefixTrack, lowest.PID)}
	if got := memberPIDs(t, ctx, f.svc, f.uc, out.PlaylistPID); !samePIDs(got, want) {
		t.Fatalf("members = %v, want the %s copy, then the lowest pid for the entry naming no album (%v)", got, named.Album, want)
	}
}

// One recording held in two libraries, a copy in each with one recording
// id as enrichment gives them, and an importer granted only one library.
// An entry naming the hidden copy's album resolves to the visible copy
// where the tie reaches it, the lowest pid, and never to the hidden one.
func TestPlaylistImportLooksPastAHiddenCopy(t *testing.T) {
	t.Parallel()
	split := func(name, album string) fixtures.Spec {
		return fixtures.Spec{
			Name: name, Codec: fixtures.CodecFLAC, Duration: 3 * time.Second,
			Tags: map[string]string{"TITLE": "Split Song", "ARTIST": "Split Artist", "ALBUM": album},
		}
	}
	elsewhere := t.TempDir()
	if _, err := fixtures.Generate(elsewhere, split("split-elsewhere", "Compilation")); err != nil {
		t.Fatal(err)
	}
	ctx, f := newMigrateFixtureWith(t, func(t *testing.T, libDir string) {
		if _, err := fixtures.Generate(filepath.Join(libDir, "single"), split("split-home", "Single")); err != nil {
			t.Fatal(err)
		}
	}, Root{Name: "elsewhere", Path: elsewhere})
	const mbid = "00000000-0000-4000-8000-0000000000ee"
	copies := f.itemsTitled(t, ctx, "Split Song")
	if len(copies) != 2 {
		t.Fatalf("copies = %d items, want one in each library", len(copies))
	}
	for _, it := range copies {
		if err := f.svc.lib.EditFields(ctx, it.PID, map[string]string{"mbid": mbid}, waxbin.EditOptions{}); err != nil {
			t.Fatal(err)
		}
	}
	libs, err := f.svc.Roots.Libraries(ctx)
	if err != nil {
		t.Fatal(err)
	}
	libraryOf := map[string]string{} // album -> bare library pid
	for _, lib := range libs {
		album := "Single"
		if lib.Name == "elsewhere" {
			album = "Compilation"
		}
		libraryOf[album] = strings.TrimPrefix(lib.PID, PrefixLibrary+"-")
	}

	for _, c := range []struct {
		what            string
		visible, hidden int
		want            []string
	}{
		{"the visible copy has the lower pid", 0, 1, []string{apiPID(PrefixTrack, copies[0].PID)}},
		{"the visible copy has the higher pid", 1, 0, nil},
	} {
		reader := &UserCtx{
			ID: f.uc.ID, CatalogPID: f.uc.CatalogPID,
			Libraries: map[string]bool{libraryOf[copies[c.visible].Album]: true},
		}
		out, err := f.svc.Playlists.ImportStreamingPlaylist(ctx, reader, PlaylistImportInput{
			Source: "portable", Name: c.what,
			Refs: []PortableRefDTO{{
				Kind: "track", MBID: mbid, Artist: "Split Artist", Title: "Split Song", Album: copies[c.hidden].Album,
			}},
		})
		if err != nil {
			t.Fatal(err)
		}
		if out.Resolved != len(c.want) {
			t.Errorf("%s: import = %+v, want %d resolved", c.what, out, len(c.want))
			continue
		}
		if len(c.want) > 0 {
			if got := memberPIDs(t, ctx, f.svc, f.uc, out.PlaylistPID); !samePIDs(got, c.want) {
				t.Errorf("%s: members = %v, want %v", c.what, got, c.want)
			}
		}
	}
}
