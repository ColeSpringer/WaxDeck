package service

import (
	"context"
	"fmt"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
	"github.com/colespringer/waxbin/read"

	"github.com/colespringer/waxdeck/fixtures"
)

// foldRelease is one artist's one-track release, filed in folder.
type foldRelease struct{ folder, artist, title string }

// foldLibrary scans the releases and answers each one's item by artist.
func foldLibrary(t *testing.T, releases ...foldRelease) (context.Context, *Library, *UserCtx, map[string]*model.ItemView) {
	t.Helper()
	var root string
	ctx, svc, admin := openEnrichFixture(t, func(c *Config) { root = c.Roots[0].Path })
	for i, r := range releases {
		spec := fixtures.Spec{
			Name: r.artist, Codec: fixtures.CodecFLAC, Duration: time.Duration(i+1) * time.Second,
			Tags: map[string]string{"TITLE": r.artist + " song", "ARTIST": r.artist, "ALBUMARTIST": r.artist, "ALBUM": r.title},
		}
		if _, err := fixtures.Generate(filepath.Join(root, r.folder), spec); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	views, err := svc.lib.Query(ctx, visibleItems().Build(), "")
	if err != nil {
		t.Fatal(err)
	}
	by := map[string]*model.ItemView{}
	for _, v := range views {
		by[v.Artist] = v
	}
	if len(by) != len(releases) {
		t.Fatalf("scanned %d artists' items, want %d", len(by), len(releases))
	}
	return ctx, svc, admin, by
}

// An artist renamed onto another's name merges into it, and a release of
// a title the survivor already has folds into the survivor's: the answer
// names each one that stopped answering and the one it became.
func TestAnArtistMergeNamesTheReleasesItFolded(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		name          string
		releases      []foldRelease
		albums, group bool
	}{
		// One folder: the editions share a key once the artist does.
		{"a same-titled release in one folder", []foldRelease{
			{"shared", "Ash Vale", "Common Ground"}, {"shared", "Birch Lane", "Common Ground"},
		}, true, true},
		// The folder keeps the editions apart; the release group is one.
		{"a same-titled release in two folders", []foldRelease{
			{"ash", "Ash Vale", "Common Ground"}, {"birch", "Birch Lane", "Common Ground"},
		}, false, true},
		{"releases titled apart", []foldRelease{
			{"ash", "Ash Vale", "Low Tide"}, {"birch", "Birch Lane", "High Tide"},
		}, false, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			ctx, svc, _, by := foldLibrary(t, tc.releases...)
			gone, kept := by["Ash Vale"], by["Birch Lane"]
			out, err := svc.Editor.RenameEntity(ctx, "artist", apiPID(PrefixArtist, gone.ArtistPID),
				map[string]string{"name": "Birch Lane"}, MetadataEditParams{})
			if err != nil {
				t.Fatal(err)
			}
			if out.Outcome != string(model.EntityRenameMerged) {
				t.Fatalf("outcome = %q, want merged", out.Outcome)
			}
			var want []FoldedDTO
			if tc.albums {
				want = append(want, FoldedDTO{apiPID(PrefixAlbum, gone.AlbumPID), apiPID(PrefixAlbum, kept.AlbumPID)})
			}
			if tc.group {
				want = append(want, FoldedDTO{
					apiPID(PrefixReleaseGroup, gone.ReleaseGroupPID), apiPID(PrefixReleaseGroup, kept.ReleaseGroupPID)})
			}
			if !slices.Equal(out.Folded, want) {
				t.Fatalf("folded = %+v, want %+v", out.Folded, want)
			}
			kinds := map[string]read.EntityKind{PrefixAlbum: read.EntityAlbum, PrefixReleaseGroup: read.EntityReleaseGroup}
			for _, f := range out.Folded {
				prefix, from, _ := parseAPIPID(f.PID)
				_, into, _ := parseAPIPID(f.Into)
				found, err := svc.lib.EntityByPIDs(ctx, kinds[prefix], []model.PID{from, into})
				if err != nil {
					t.Fatal(err)
				}
				if found[from] != nil || found[into] == nil {
					t.Errorf("%s answers %v and %s answers %v, want only the one it became", f.PID, found[from] != nil, f.Into, found[into] != nil)
				}
			}
		})
	}
}

// An artist featured on a single track of another's large album keys
// none of it: the merge keeps no release of that credit to read again,
// and folds only the artist's own.
func TestAMergeReadsNoReleaseItsArtistIsOnlyCreditedOn(t *testing.T) {
	t.Parallel()
	var root string
	ctx, svc, _ := openEnrichFixture(t, func(c *Config) { root = c.Roots[0].Path })
	own := func(folder, artist string, sec int) {
		t.Helper()
		if _, err := fixtures.Generate(filepath.Join(root, folder), fixtures.Spec{
			Name: artist, Codec: fixtures.CodecFLAC, Duration: time.Duration(sec) * time.Second,
			Tags: map[string]string{"TITLE": artist + " song", "ARTIST": artist, "ALBUMARTIST": artist, "ALBUM": "Common Ground"},
		}); err != nil {
			t.Fatal(err)
		}
	}
	own("ash", "Ash Vale", 1)
	own("birch", "Birch Lane", 2)
	var session []fixtures.Spec
	for i := range 12 {
		artist := "Big Band"
		if i == 0 {
			artist = "Big Band feat. Ash Vale"
		}
		session = append(session, fixtures.Spec{
			Name: fmt.Sprintf("session-%02d", i), Codec: fixtures.CodecFLAC, Duration: time.Duration(i%8+3) * time.Second,
			Tags: map[string]string{
				"TITLE": fmt.Sprintf("Take %d", i+1), "ARTIST": artist, "ALBUMARTIST": "Big Band",
				"ALBUM": "Long Session",
			},
		})
	}
	if _, err := fixtures.Generate(filepath.Join(root, "session"), session...); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	views, err := svc.lib.Query(ctx, visibleItems().Build(), "")
	if err != nil {
		t.Fatal(err)
	}
	var ash model.PID
	var long model.PID
	for _, v := range views {
		switch v.Artist {
		case "Ash Vale":
			ash = v.ArtistPID
		case "Big Band":
			long = v.AlbumPID
		}
	}
	credited, err := svc.lib.Query(ctx, visibleItems().Where("credit_artist_pid", query.OpIs, string(ash)).Build(), "")
	featured := false
	for _, v := range credited {
		featured = featured || v.AlbumPID == long
	}
	if err != nil || !featured {
		t.Fatalf("credited items = %d (%v), want the session's featured track among them", len(credited), err)
	}

	places := svc.Editor.placesBefore(ctx, model.MergeArtist, ash)
	if places == nil {
		t.Fatal("no places read before the write")
	}
	if _, ok := places.albums[long]; ok || len(places.albums) != 1 {
		t.Fatalf("kept albums = %v, want only the artist's own, not the session it is credited on", places.albums)
	}
	out, err := svc.Editor.RenameEntity(ctx, "artist", apiPID(PrefixArtist, ash),
		map[string]string{"name": "Birch Lane"}, MetadataEditParams{})
	if err != nil {
		t.Fatal(err)
	}
	if len(out.Folded) != 1 || !strings.HasPrefix(out.Folded[0].PID, PrefixReleaseGroup+"-") {
		t.Fatalf("folded = %+v, want the artist's own release group alone", out.Folded)
	}
}

// A trashed member stops the rename: the catalog cannot key a member
// whose file sits in the trash, so it refuses the write whole. So no
// write that goes through has a trashed member, and the releases read
// before it are the visible members' alone.
func TestAMergeWithATrashedMemberIsRefusedAndFoldsNothing(t *testing.T) {
	t.Parallel()
	ctx, svc, admin, by := foldLibrary(t,
		foldRelease{"shared", "Ash Vale", "Common Ground"}, foldRelease{"shared", "Birch Lane", "Common Ground"})
	gone := by["Ash Vale"]
	if _, err := svc.Tools.DeleteItems(ctx, admin, []string{itemAPIPID(gone)}, "trash", false); err != nil {
		t.Fatal(err)
	}
	out, err := svc.Editor.RenameEntity(ctx, "artist", apiPID(PrefixArtist, gone.ArtistPID),
		map[string]string{"name": "Birch Lane"}, MetadataEditParams{})
	if err == nil || !strings.Contains(err.Error(), "archived") {
		t.Fatalf("rename = %+v (%v), want it refused for the trashed member", out, err)
	}
	if places := svc.Editor.placesBefore(ctx, model.MergeArtist, gone.ArtistPID); places == nil || len(places.albums) != 0 {
		t.Fatalf("kept albums = %+v, want none: the trashed member is not a visible one", places)
	}
}
