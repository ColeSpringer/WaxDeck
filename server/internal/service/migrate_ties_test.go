package service

import (
	"bytes"
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
	"github.com/colespringer/waxdeck/fixtures"
)

// copiesOfOneRecording adds one album track ripped twice (two folders,
// the same tags, different audio, so two items the ladder proves are one
// recording) and one title recorded twice on two albums, which share
// nothing but their names.
func copiesOfOneRecording(t *testing.T, libDir string) {
	t.Helper()
	track := func(name, title, artist, album string) fixtures.Spec {
		return fixtures.Spec{
			Name: name, Codec: fixtures.CodecFLAC, Duration: 3 * time.Second,
			Tags: map[string]string{"TITLE": title, "ARTIST": artist, "ALBUM": album, "TRACKNUMBER": "3"},
		}
	}
	for dir, spec := range map[string]fixtures.Spec{
		"rip one": track("copied-one", "Copied Song", "Copy Artist", "Copy Album"),
		"rip two": track("copied-two", "Copied Song", "Copy Artist", "Copy Album"),
		"studio":  track("twice-studio", "Twice Song", "Twice Artist", "Studio Album"),
		"live":    track("twice-live", "Twice Song", "Twice Artist", "Live Album"),
	} {
		if _, err := fixtures.Generate(filepath.Join(libDir, dir), spec); err != nil {
			t.Fatal(err)
		}
	}
}

// itemsTitled answers every item carrying the title, lowest pid first.
func (f *migrateFixture) itemsTitled(t *testing.T, ctx context.Context, title string) []*model.ItemView {
	t.Helper()
	items, err := f.svc.lib.Query(ctx, query.New(query.EntityItems).Where("title", query.OpIs, title).Build(), "")
	if err != nil {
		t.Fatalf("querying %q: %v", title, err)
	}
	slices.SortFunc(items, func(a, b *model.ItemView) int { return strings.Compare(string(a.PID), string(b.PID)) })
	return items
}

// spotifyPlays is an extended history file of one finished play per
// (title, artist, album) triple, a day apart.
func spotifyPlays(t *testing.T, plays ...[3]string) []byte {
	t.Helper()
	rows := make([]string, 0, len(plays))
	for i, p := range plays {
		rows = append(rows, fmt.Sprintf(`{"ts":"2026-02-%02dT10:00:00Z","ms_played":3000,`+
			`"master_metadata_track_name":%q,"master_metadata_album_artist_name":%q,`+
			`"master_metadata_album_album_name":%q}`, i+1, p[0], p[1], p[2]))
	}
	return spotifyHistoryZip(t, "["+strings.Join(rows, ",")+"]")
}

// runSpotify stages an export and imports its history.
func (f *migrateFixture) runSpotify(t *testing.T, ctx context.Context, archive []byte) migrationSummary {
	t.Helper()
	staged, err := f.svc.Migrate.StageMigrationExport(ctx, f.uc, bytes.NewReader(archive), 0)
	if err != nil {
		t.Fatal(err)
	}
	return f.runMigration(t, ctx, MigrationRequest{Source: "spotify", ExportID: staged.PID, History: true})
}

// A play of a recording the library holds twice, which nothing in the
// play tells apart, lands on the copy with the lowest pid, and the
// report counts the tie.
func TestMigrateSpotifyTakesATieBetweenCopiesOfOneRecording(t *testing.T) {
	t.Parallel()
	ctx, f := newMigrateFixtureWith(t, copiesOfOneRecording)
	copies := f.itemsTitled(t, ctx, "Copied Song")
	if len(copies) != 2 {
		t.Fatalf("copies = %d items, want the album track held twice", len(copies))
	}

	sum := f.runSpotify(t, ctx, spotifyPlays(t,
		[3]string{"Copied Song", "Copy Artist", "Copy Album"},
		[3]string{"Copied Song", "Copy Artist", "Copy Album"}))
	if sum.Matched != 1 || sum.Unmatched != 0 || sum.Ties != 1 || sum.Listens != 2 {
		t.Fatalf("summary = %+v, want the recording matched once through a tie and both plays written", sum)
	}
	if want := []string{"Copy Artist - Copied Song (2 copies)"}; !slices.Equal(sum.Samples.Ties, want) {
		t.Fatalf("tie samples = %q, want %q", sum.Samples.Ties, want)
	}
	if st := f.playState(t, ctx, apiPID(PrefixTrack, copies[0].PID)); st.PlayCount != 2 {
		t.Errorf("the lowest copy's play count = %d, want both plays", st.PlayCount)
	}
	if st := f.playState(t, ctx, apiPID(PrefixTrack, copies[1].PID)); st.PlayCount != 0 {
		t.Errorf("the other copy's play count = %d, want none", st.PlayCount)
	}
}

// Two recordings that share only an artist and a title are not copies
// of one: nothing proves the tie, so the play still misses, and the
// report counts no tie.
func TestMigrateSpotifyMissesNamesakeRecordings(t *testing.T) {
	t.Parallel()
	ctx, f := newMigrateFixtureWith(t, copiesOfOneRecording)
	if n := len(f.itemsTitled(t, ctx, "Twice Song")); n != 2 {
		t.Fatalf("namesakes = %d items, want two recordings", n)
	}

	sum := f.runSpotify(t, ctx, spotifyPlays(t, [3]string{"Twice Song", "Twice Artist", "Greatest Hits"}))
	if sum.Matched != 0 || sum.Unmatched != 1 || sum.Ties != 0 || sum.Listens != 0 {
		t.Fatalf("summary = %+v, want the play unmatched and no tie", sum)
	}
	if want := []string{"Twice Artist - Twice Song"}; !slices.Equal(sum.Samples.Unmatched, want) || len(sum.Samples.Ties) != 0 {
		t.Fatalf("samples = %+v, want the namesake unmatched", sum.Samples)
	}
}

// starredSongs is a Subsonic server whose only state is the songs given,
// starred.
func starredSongs(t *testing.T, songs ...string) *httptest.Server {
	t.Helper()
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch strings.TrimSuffix(strings.TrimPrefix(r.URL.Path, "/rest/"), ".view") {
		case "getStarred2":
			writeSubsonic(w, `"starred2":{"song":[`+strings.Join(songs, ",")+`],"album":[],"artist":[]}`, true)
		case "getBookmarks":
			writeSubsonic(w, `"bookmarks":{"bookmark":[]}`, true)
		default:
			writeSubsonic(w, `"error":{"code":0,"message":"unknown method"}`, false)
		}
	}))
	t.Cleanup(ts.Close)
	return ts
}

// The Subsonic import resolves through the same resolver, so a starred
// song held twice is starred on one copy and counted as a tie there too.
func TestMigrateSubsonicTakesATieBetweenCopiesOfOneRecording(t *testing.T) {
	t.Parallel()
	ctx, f := newMigrateFixtureWith(t, copiesOfOneRecording)
	copies := f.itemsTitled(t, ctx, "Copied Song")
	ts := starredSongs(t, `{"id":"s-copied","title":"Copied Song","artist":"Copy Artist",`+
		`"album":"Copy Album","duration":3,"starred":"2025-11-05T10:20:30.000Z"}`)

	sum := f.runMigration(t, ctx, MigrationRequest{
		Source: "navidrome", ServerURL: ts.URL, Username: "demo", Password: "demo-pass", Stars: true,
	})
	if sum.Matched != 1 || sum.Ties != 1 || sum.Stars != 1 {
		t.Fatalf("summary = %+v, want the song starred through a tie", sum)
	}
	if want := []string{"Copy Artist - Copied Song (2 copies)"}; !slices.Equal(sum.Samples.Ties, want) {
		t.Fatalf("tie samples = %q, want %q", sum.Samples.Ties, want)
	}
	if !f.playState(t, ctx, apiPID(PrefixTrack, copies[0].PID)).Starred ||
		f.playState(t, ctx, apiPID(PrefixTrack, copies[1].PID)).Starred {
		t.Fatal("the star did not land on the lowest copy alone")
	}
}

// A tie is taken only where nothing tells the copies apart. Two items
// enrichment gave one recording id tie on that id, but the album the
// source names picks one of them, and the import keeps that answer over
// the lowest pid.
func TestMigrateKeepsTheCopyTheAlbumNames(t *testing.T) {
	t.Parallel()
	ctx, f := newMigrateFixtureWith(t, copiesOfOneRecording)
	const mbid = "00000000-0000-4000-8000-0000000000cc"
	namesakes := f.itemsTitled(t, ctx, "Twice Song")
	if len(namesakes) != 2 {
		t.Fatalf("namesakes = %d items, want two", len(namesakes))
	}
	for _, it := range namesakes {
		if err := f.svc.lib.EditFields(ctx, it.PID, map[string]string{"mbid": mbid}, waxbin.EditOptions{}); err != nil {
			t.Fatal(err)
		}
	}
	named := namesakes[1]
	ts := starredSongs(t, fmt.Sprintf(`{"id":"s-twice","title":"Twice Song","artist":"Twice Artist",`+
		`"album":%q,"duration":3,"starred":"2025-11-05T10:20:30.000Z","musicBrainzId":%q}`, named.Album, mbid))

	sum := f.runMigration(t, ctx, MigrationRequest{
		Source: "navidrome", ServerURL: ts.URL, Username: "demo", Password: "demo-pass", Stars: true,
	})
	if sum.Matched != 1 || sum.Ties != 0 || sum.Stars != 1 {
		t.Fatalf("summary = %+v, want the song matched to the named album's copy, no tie", sum)
	}
	if !f.playState(t, ctx, apiPID(PrefixTrack, named.PID)).Starred ||
		f.playState(t, ctx, apiPID(PrefixTrack, namesakes[0].PID)).Starred {
		t.Fatalf("the star did not land on the %s copy alone", named.Album)
	}
}

// A symbol in an artist's name does not stop a play matching: Curren$y's
// track, held once, is found from a play that names no album, and the
// report counts no tie.
func TestMigrateSpotifyMatchesASymbolBearingNameHeldOnce(t *testing.T) {
	t.Parallel()
	ctx, f := newMigrateFixtureWith(t, func(t *testing.T, libDir string) {
		t.Helper()
		if _, err := fixtures.Generate(filepath.Join(libDir, "champagne"), fixtures.Spec{
			Name: "junior-mints", Codec: fixtures.CodecFLAC, Duration: 3 * time.Second,
			Tags: map[string]string{"TITLE": "Junior Mints", "ARTIST": "Curren$y", "ALBUM": "The Champagne Files", "TRACKNUMBER": "3"},
		}); err != nil {
			t.Fatal(err)
		}
	})
	held := f.itemsTitled(t, ctx, "Junior Mints")
	if len(held) != 1 {
		t.Fatalf("held = %d items, want the track once", len(held))
	}

	sum := f.runSpotify(t, ctx, spotifyPlays(t, [3]string{"Junior Mints", "Curren$y", ""}))
	if sum.Matched != 1 || sum.Unmatched != 0 || sum.Ties != 0 || sum.Listens != 1 {
		t.Fatalf("summary = %+v, want the play matched once with no tie", sum)
	}
	if len(sum.Samples.Ties) != 0 || len(sum.Samples.Unmatched) != 0 {
		t.Errorf("samples = %+v, want neither a tie nor a miss", sum.Samples)
	}
	if st := f.playState(t, ctx, apiPID(PrefixTrack, held[0].PID)); st.PlayCount != 1 {
		t.Errorf("the track's play count = %d, want the play", st.PlayCount)
	}
}
