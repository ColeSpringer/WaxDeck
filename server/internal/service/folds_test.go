package service

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/identity"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"

	"github.com/colespringer/waxdeck/fixtures"
)

// foldFixture is a library holding an artist under two spellings and one
// album twice, kept apart by its folders: two duplicate findings to merge.
func foldFixture(t *testing.T) (context.Context, *Library, *UserCtx) {
	t.Helper()
	ctx, svc, uc := openEnrichFixture(t, func(c *Config) {
		for i, s := range []struct{ dir, name, artist, album string }{
			{"one", "a", "Beatles", "Abbey"},
			{"two", "b", "The Beatles", "Road"},
			{"Blue", "c", "Joni", "Blue"},
			{"Blue Again", "d", "Joni", "Blue"},
		} {
			if _, err := fixtures.Generate(filepath.Join(c.Roots[0].Path, s.dir), fixtures.Spec{
				Name: s.name, Codec: fixtures.CodecFLAC, Duration: time.Duration(2+i) * time.Second,
				Tags: map[string]string{"TITLE": "Song " + s.name, "ARTIST": s.artist, "ALBUMARTIST": s.artist,
					"ALBUM": s.album, "TRACKNUMBER": "1"},
			}); err != nil {
				t.Fatal(err)
			}
		}
	})
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	return ctx, svc, uc
}

// mergeFinding merges the duplicates listing's group of entityType,
// answering the group and the outcome.
func mergeFinding(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, entityType string) (DuplicateGroupDTO, MergeResultDTO) {
	t.Helper()
	groups, err := svc.Health.ListDuplicateGroups(ctx, uc)
	if err != nil {
		t.Fatal(err)
	}
	for _, g := range groups {
		if g.EntityType != entityType {
			continue
		}
		losers := make([]string, 0, len(g.Losers))
		for _, l := range g.Losers {
			losers = append(losers, l.PID)
		}
		res, err := svc.Health.MergeDuplicates(ctx, uc, entityType, g.Survivor.PID, losers)
		if err != nil {
			t.Fatal(err)
		}
		return g, res
	}
	t.Fatalf("no %s duplicates in %+v", entityType, groups)
	return DuplicateGroupDTO{}, MergeResultDTO{}
}

func allFolds(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx) []EntityFoldDTO {
	t.Helper()
	folds, next, err := svc.Reads.ListEntityFolds(ctx, uc, "", 0)
	if err != nil || next != "" {
		t.Fatalf("folds = %+v, next %q (%v)", folds, next, err)
	}
	return folds
}

// A merge reports the name it folds into the survivor, and its audit
// names it; the listing then shows each type's folds in order, with the
// entity each files under in the form the app opens it by.
func TestAMergeFoldsTheLosersNameIntoTheSurvivor(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := foldFixture(t)
	artists, artistMerge := mergeFinding(t, ctx, svc, uc, "artist")
	albums, albumMerge := mergeFinding(t, ctx, svc, uc, "album")
	loserKey := strings.ToLower(strings.TrimSpace(artists.Losers[0].Name))
	if !slices.Equal(artistMerge.Folds, []string{loserKey}) {
		t.Fatalf("artist merge folds = %q, want the loser's name %q", artistMerge.Folds, loserKey)
	}
	if len(albumMerge.Folds) != 1 || !strings.HasPrefix(albumMerge.Folds[0], "al:") {
		t.Fatalf("album merge folds = %q, want the loser album's key", albumMerge.Folds)
	}
	page, err := svc.Audit.Events(ctx, AuditFilter{Action: "entity.merge"}, "", 10)
	if err != nil || len(page.Events) != 2 {
		t.Fatalf("audit = %+v (%v), want both merges", page.Events, err)
	}
	if got, _ := page.Events[1].Detail["folds"].([]any); len(got) != 1 || got[0] != loserKey {
		t.Errorf("the artist merge's audit folds = %v, want %q", page.Events[1].Detail["folds"], loserKey)
	}

	folds := allFolds(t, ctx, svc, uc)
	want := []EntityFoldDTO{
		{EntityType: "album", Key: albumMerge.Folds[0], Spelling: "joni - blue", Folder: "Blue Again", Library: "lib",
			EntityPID: "al-" + albums.Survivor.PID, EntityName: albums.Survivor.Name},
		{EntityType: "artist", Key: loserKey, Spelling: loserKey,
			EntityPID: "ar-" + artists.Survivor.PID, EntityName: artists.Survivor.Name},
	}
	if len(folds) != len(want) {
		t.Fatalf("folds = %+v, want %+v", folds, want)
	}
	for i, f := range folds {
		if f.CreatedAt.IsZero() {
			t.Errorf("fold %d has no time", i)
		}
		f.CreatedAt = time.Time{}
		if f != want[i] {
			t.Errorf("fold %d = %+v, want %+v", i, f, want[i])
		}
	}
}

// Unfolding forgets the named fold and leaves the others, and its audit
// names the keys.
func TestUnfoldingForgetsTheFold(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := foldFixture(t)
	_, artistMerge := mergeFinding(t, ctx, svc, uc, "artist")
	_, albumMerge := mergeFinding(t, ctx, svc, uc, "album")
	if err := svc.Reads.UnfoldEntities(ctx, uc, "artist", artistMerge.Folds); err != nil {
		t.Fatal(err)
	}
	folds := allFolds(t, ctx, svc, uc)
	if len(folds) != 1 || folds[0].Key != albumMerge.Folds[0] {
		t.Fatalf("folds after unfolding the artist = %+v, want the album's alone", folds)
	}
	page, err := svc.Audit.Events(ctx, AuditFilter{Action: "entity.unfold"}, "", 10)
	if err != nil || len(page.Events) != 1 || page.Events[0].TargetKind != "artist" {
		t.Fatalf("audit = %+v (%v), want the unfold", page.Events, err)
	}
	if got, _ := page.Events[0].Detail["keys"].([]any); len(got) != 1 || got[0] != artistMerge.Folds[0] {
		t.Errorf("audited keys = %v, want %q", page.Events[0].Detail["keys"], artistMerge.Folds)
	}
}

// An unfold naming a key no fold holds is not found, names the key, and
// forgets nothing, the keys it does hold included.
func TestUnfoldingAMissingKeyForgetsNothing(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := foldFixture(t)
	_, artistMerge := mergeFinding(t, ctx, svc, uc, "artist")
	err := svc.Reads.UnfoldEntities(ctx, uc, "artist", []string{artistMerge.Folds[0], "nobody folded"})
	if KindOf(err) != KindNotFound || !strings.Contains(err.Error(), "nobody folded") {
		t.Fatalf("unfolding a missing key = %v, want not found naming it", err)
	}
	if folds := allFolds(t, ctx, svc, uc); len(folds) != 1 || folds[0].Key != artistMerge.Folds[0] {
		t.Errorf("folds = %+v, want the held key kept", folds)
	}
	if page, _ := svc.Audit.Events(ctx, AuditFilter{Action: "entity.unfold"}, "", 10); len(page.Events) != 0 {
		t.Errorf("a refused unfold was audited: %+v", page.Events)
	}
}

// Folds are an administrator's: a member is refused both verbs, and a
// malformed request is refused before the catalog sees it.
func TestFoldsAreForAdministrators(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := foldFixture(t)
	_, artistMerge := mergeFinding(t, ctx, svc, uc, "artist")
	member := &UserCtx{ID: uc.ID, CatalogPID: uc.CatalogPID, AllLibraries: true}
	if _, _, err := svc.Reads.ListEntityFolds(ctx, member, "", 0); KindOf(err) != KindForbidden {
		t.Errorf("a member listing folds = %v, want forbidden", err)
	}
	if err := svc.Reads.UnfoldEntities(ctx, member, "artist", artistMerge.Folds); KindOf(err) != KindForbidden {
		t.Errorf("a member unfolding = %v, want forbidden", err)
	}
	many := make([]string, maxUnfoldKeys+1)
	for i := range many {
		many[i] = artistMerge.Folds[0]
	}
	for _, bad := range []struct {
		entityType string
		keys       []string
	}{
		{"playlist", artistMerge.Folds},
		{"artist", nil},
		{"artist", many},
	} {
		if err := svc.Reads.UnfoldEntities(ctx, uc, bad.entityType, bad.keys); KindOf(err) != KindInvalid {
			t.Errorf("unfolding %s with %d keys = %v, want invalid", bad.entityType, len(bad.keys), err)
		}
	}
	if folds := allFolds(t, ctx, svc, uc); len(folds) != 1 {
		t.Errorf("folds = %+v, want the merge's kept", folds)
	}
}

// The listing pages by type, then key, and a cursor it never minted is
// invalid.
func TestFoldsPageByTypeThenKey(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := foldFixture(t)
	mergeFinding(t, ctx, svc, uc, "artist")
	mergeFinding(t, ctx, svc, uc, "album")
	first, next, err := svc.Reads.ListEntityFolds(ctx, uc, "", 1)
	if err != nil || len(first) != 1 || first[0].EntityType != "album" || next == "" {
		t.Fatalf("first page = %+v, next %q (%v), want the album fold and a cursor", first, next, err)
	}
	second, next, err := svc.Reads.ListEntityFolds(ctx, uc, next, 1)
	if err != nil || len(second) != 1 || second[0].EntityType != "artist" || next == "" {
		t.Fatalf("second page = %+v, next %q (%v), want the artist fold and a cursor past it", second, next, err)
	}
	last, next, err := svc.Reads.ListEntityFolds(ctx, uc, next, 1)
	if err != nil || len(last) != 0 || next != "" {
		t.Fatalf("last page = %+v, next %q (%v), want nothing more", last, next, err)
	}
	if _, _, err := svc.Reads.ListEntityFolds(ctx, uc, "not-a-cursor", 1); KindOf(err) != KindInvalid {
		t.Errorf("a foreign cursor = %v, want invalid", err)
	}
}

// A fold reads as its key's name, and carries what tells apart two folds
// that read alike: a genre's facet, an album's folder.
func TestAFoldReadsItsKeyForPeople(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		et   model.MergeEntity
		key  string
		want foldReading
	}{
		{model.MergeArtist, "the beatles", foldReading{spelling: "the beatles"}},
		{model.MergeGenre, "genre:chill", foldReading{spelling: "chill", facet: "genre"}},
		{model.MergeGenre, "mood:chill", foldReading{spelling: "chill", facet: "mood"}},
		{model.MergeSeries, "series:harbor tales", foldReading{spelling: "harbor tales"}},
		{model.MergeSeries, "mbid:0383dadf-2a4e-4d10-a46a-e9e041da8eb3",
			foldReading{spelling: "MusicBrainz 0383dadf-2a4e-4d10-a46a-e9e041da8eb3"}},
		{model.MergeReleaseGroup, "rg:joni\x1fblue", foldReading{spelling: "joni - blue"}},
		{model.MergeReleaseGroup, "rg:\x1fblue", foldReading{spelling: "blue"}},
		{model.MergeReleaseGroup, "mbid:abc", foldReading{spelling: "MusicBrainz abc"}},
		{model.MergeAlbum, "al:rg:joni\x1fblue\x1f\x1f\x1fmusic joni blue again",
			foldReading{spelling: "joni - blue", folder: "music joni blue again"}},
		// A disc count segment, which the catalog leaves empty, reads past.
		{model.MergeAlbum, "al:rg:joni\x1fblue\x1f\x1f2\x1fmusic joni blue",
			foldReading{spelling: "joni - blue", folder: "music joni blue"}},
		{model.MergeAlbum, "al:mbid:abc\x1f\x1f\x1fmusic blue", foldReading{spelling: "MusicBrainz abc", folder: "music blue"}},
		{model.MergeAlbum, "mbid:def", foldReading{spelling: "MusicBrainz def"}},
	} {
		if got := readFoldKey(tc.et, tc.key); got != tc.want {
			t.Errorf("%s %q reads %+v, want %+v", tc.et, tc.key, got, tc.want)
		}
	}
}

// Copies of one release in three folders merge into one and leave two
// folds that spell alike: each carries its folder, so the two rows differ.
func TestFoldsThatSpellAlikeAreToldApart(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := openEnrichFixture(t, func(c *Config) {
		for i, dir := range []string{"Blue", "Blue Again", "Blue Once More"} {
			if _, err := fixtures.Generate(filepath.Join(c.Roots[0].Path, dir), fixtures.Spec{
				Name: fmt.Sprintf("copy%d", i), Codec: fixtures.CodecFLAC, Duration: time.Duration(2+i) * time.Second,
				Tags: map[string]string{"TITLE": fmt.Sprintf("Song %d", i), "ARTIST": "Joni", "ALBUMARTIST": "Joni",
					"ALBUM": "Blue", "TRACKNUMBER": "1"},
			}); err != nil {
				t.Fatal(err)
			}
		}
	})
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	albums, merged := mergeFinding(t, ctx, svc, uc, "album")
	if len(albums.Losers) != 2 || len(merged.Folds) != 2 {
		t.Fatalf("album merge = %+v over %+v, want two losers folded", merged, albums)
	}
	folds := allFolds(t, ctx, svc, uc)
	if len(folds) != 2 {
		t.Fatalf("folds = %+v, want the two losers'", folds)
	}
	got := map[string]bool{}
	for _, f := range folds {
		if f.Spelling != "joni - blue" || f.Library != "lib" || f.EntityName != albums.Survivor.Name {
			t.Errorf("fold %+v, want joni - blue in a folder of lib, under the survivor", f)
		}
		got[f.Folder] = true
	}
	if !got["Blue Again"] || !got["Blue Once More"] {
		t.Errorf("folders = %v, want each loser's own, within its library", got)
	}
}

// A folder no file of the album sits in any longer is placed nowhere:
// the listing says nothing it cannot read off a file.
func TestAFoldWhoseFolderHoldsNoFileIsPlacedNowhere(t *testing.T) {
	t.Parallel()
	var root string
	ctx, svc, uc := openEnrichFixture(t, func(c *Config) {
		root = c.Roots[0].Path
		for i, dir := range []string{"Blue", "Blue Again", "Blue Once More"} {
			if _, err := fixtures.Generate(filepath.Join(root, dir), fixtures.Spec{
				Name: fmt.Sprintf("copy%d", i), Codec: fixtures.CodecFLAC, Duration: time.Duration(2+i) * time.Second,
				Tags: map[string]string{"TITLE": fmt.Sprintf("Song %d", i), "ARTIST": "Joni", "ALBUMARTIST": "Joni",
					"ALBUM": "Blue", "TRACKNUMBER": "1"},
			}); err != nil {
				t.Fatal(err)
			}
		}
	})
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	mergeFinding(t, ctx, svc, uc, "album")
	if err := os.RemoveAll(filepath.Join(root, "Blue Again")); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	placed := map[string]string{}
	for _, f := range allFolds(t, ctx, svc, uc) {
		placed[f.Folder] = f.Library
	}
	if lib, ok := placed["Blue Once More"]; !ok || lib != "lib" {
		t.Errorf("placed = %v, want the folder that still holds its file", placed)
	}
	if lib, ok := placed[""]; !ok || lib != "" || len(placed) != 2 {
		t.Errorf("placed = %v, want the emptied folder with no folder and no library", placed)
	}
}

// Only a file of the album places a folder: the match key folds a path's
// separators and punctuation alike, so a folder and its place in a
// sibling library cannot be told apart by the key, and a key two places
// fold to is placed nowhere.
func TestAFolderIsPlacedOnlyByAFileInIt(t *testing.T) {
	t.Parallel()
	libs := []*model.Library{
		{PID: "L1", Root: []byte(filepath.FromSlash("/x/music"))},
		{PID: "L2", Root: []byte(filepath.FromSlash("/x/music-hd"))},
	}
	names := map[model.PID]string{"L1": "Music", "L2": "Music HD"}
	item := func(album, lib model.PID, path string) *model.ItemView {
		return &model.ItemView{AlbumPID: album, LibraryPID: lib, Path: []byte(filepath.FromSlash(path))}
	}
	places := folderPlaces(libs, names, []*model.ItemView{
		item("A", "L1", "/x/music/HD/Kilo/01.flac"),
		item("B", "L2", "/x/music-hd/Kilo/CD1/01.flac"),
		item("C", "L1", "/x/music/HD/Blue/01.flac"),
		item("C", "L2", "/x/music-hd/Blue/01.flac"),
		item("D", "L1", "/x/music/01.flac"),
		item("E", "L1", "/elsewhere/01.flac"),
	})
	for _, tc := range []struct {
		album  model.PID
		folder string
		want   placement
		placed bool
	}{
		{"A", identity.MatchKey(filepath.FromSlash("/x/music/HD/Kilo")), placement{library: "Music", folder: "HD/Kilo"}, true},
		{"B", identity.MatchKey(filepath.FromSlash("/x/music-hd/Kilo")), placement{library: "Music HD", folder: "Kilo"}, true},
		{"C", identity.MatchKey(filepath.FromSlash("/x/music/HD/Blue")), placement{}, false},
		{"D", identity.MatchKey(filepath.FromSlash("/x/music")), placement{library: "Music"}, true},
		{"E", identity.MatchKey(filepath.FromSlash("/elsewhere")), placement{}, false},
	} {
		got, ok := places.at(tc.album, tc.folder)
		if ok != tc.placed || got != tc.want {
			t.Errorf("album %s folder %q placed %+v (%v), want %+v (%v)", tc.album, tc.folder, got, ok, tc.want, tc.placed)
		}
	}
}

// A page reads a type only while it has room: one that fills inside a
// type reads that type alone, and one that fills at a type's end stops
// there, its cursor naming the next type even when that holds nothing.
func TestAFoldsPageReadsOnlyTheTypesItNeeds(t *testing.T) {
	t.Parallel()
	held := map[model.MergeEntity][]model.EntityFold{
		model.MergeAlbum:  {{EntityType: model.MergeAlbum, Key: "al:a"}, {EntityType: model.MergeAlbum, Key: "al:b"}},
		model.MergeGenre:  {{EntityType: model.MergeGenre, Key: "genre:x"}},
		model.MergeSeries: {{EntityType: model.MergeSeries, Key: "series:y"}},
	}
	var reads []model.MergeEntity
	read := func(_ context.Context, et model.MergeEntity) ([]model.EntityFold, error) {
		reads = append(reads, et)
		return held[et], nil
	}
	page := func(cursor string, limit int) ([]string, string) {
		t.Helper()
		reads = nil
		folds, next, err := foldsPage(context.Background(), read, nil, cursor, limit)
		if err != nil {
			t.Fatal(err)
		}
		keys := make([]string, 0, len(folds))
		for _, f := range folds {
			keys = append(keys, f.Key)
		}
		return keys, next
	}
	keys, next := page("", 1)
	if !slices.Equal(keys, []string{"al:a"}) || next == "" || !slices.Equal(reads, []model.MergeEntity{model.MergeAlbum}) {
		t.Fatalf("page 1 = %q, next %q, read %q; want al:a from the albums alone", keys, next, reads)
	}
	keys, next = page(next, 1)
	if !slices.Equal(keys, []string{"al:b"}) || next == "" || !slices.Equal(reads, []model.MergeEntity{model.MergeAlbum}) {
		t.Fatalf("page 2 = %q, next %q, read %q; want al:b, stopping at the albums' end", keys, next, reads)
	}
	keys, next = page(next, 2)
	want := []model.MergeEntity{model.MergeArtist, model.MergeGenre, model.MergeReleaseGroup, model.MergeSeries}
	if !slices.Equal(keys, []string{"genre:x", "series:y"}) || next != "" || !slices.Equal(reads, want) {
		t.Fatalf("page 3 = %q, next %q, read %q; want the rest from the types after the albums", keys, next, reads)
	}

	delete(held, model.MergeGenre)
	delete(held, model.MergeSeries)
	keys, next = page("", 2)
	if len(keys) != 2 || next == "" {
		t.Fatalf("a page full at the albums' end = %q, next %q, want a cursor past it", keys, next)
	}
	if keys, next = page(next, 2); len(keys) != 0 || next != "" {
		t.Fatalf("the page past the last fold = %q, next %q, want it empty and last", keys, next)
	}
}

// An unfold moves nothing: the files the merge filed under the survivor
// stay there through a rescan, one that re-reads unchanged files
// included, since the catalog resolves a file's names again only when the
// file is new or has changed. A retagged file files under its own name.
func TestAnUnfoldedNameSplitsOutOnlyWhenItsFileChanges(t *testing.T) {
	t.Parallel()
	var root string
	ctx, svc, uc := openEnrichFixture(t, func(c *Config) {
		root = c.Roots[0].Path
		for i, artist := range []string{"Beatles", "The Beatles"} {
			if _, err := fixtures.Generate(filepath.Join(root, fmt.Sprint(i)), fixtures.Spec{
				Name: "song", Codec: fixtures.CodecFLAC, Duration: time.Duration(2+i) * time.Second,
				Tags: map[string]string{"TITLE": "Song " + artist, "ARTIST": artist, "ALBUMARTIST": artist,
					"ALBUM": "Album " + artist, "TRACKNUMBER": "1"},
			}); err != nil {
				t.Fatal(err)
			}
		}
	})
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	group, merged := mergeFinding(t, ctx, svc, uc, "artist")
	if err := svc.Reads.UnfoldEntities(ctx, uc, "artist", merged.Folds); err != nil {
		t.Fatal(err)
	}
	loser := group.Losers[0].Name
	artistOf := func(title string) model.PID {
		t.Helper()
		items, err := svc.lib.Query(ctx, query.New(query.EntityItems).Where("title", query.OpIs, title).Build(), "")
		if err != nil || len(items) != 1 {
			t.Fatalf("items titled %q = %d (%v)", title, len(items), err)
		}
		return items[0].ArtistPID
	}
	survivor := model.PID(group.Survivor.PID)
	for _, req := range []waxbin.ScanRequest{{}, {Force: true}} {
		if _, err := svc.lib.Scan(ctx, req); err != nil {
			t.Fatal(err)
		}
		if got := artistOf("Song " + loser); got != survivor {
			t.Fatalf("after a scan (force %v) %q files under %s, want the survivor %s", req.Force, loser, got, survivor)
		}
	}

	// The same audio under one more tag: a retag.
	i := 0
	if loser == "The Beatles" {
		i = 1
	}
	if _, err := fixtures.Generate(filepath.Join(root, fmt.Sprint(i)), fixtures.Spec{
		Name: "song", Codec: fixtures.CodecFLAC, Duration: time.Duration(2+i) * time.Second,
		Tags: map[string]string{"TITLE": "Song " + loser, "ARTIST": loser, "ALBUMARTIST": loser,
			"ALBUM": "Album " + loser, "TRACKNUMBER": "1", "COMMENT": "retagged"},
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	if got := artistOf("Song " + loser); got == survivor || got == "" {
		t.Fatalf("after its retag %q files under %s, want an artist of its own", loser, got)
	}
}
