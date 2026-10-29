package service

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxdeck/fixtures"
)

// sharedRecordingMBID is the recording id a retag gives every copy of one
// song, wherever it sits.
const sharedRecordingMBID = "00000000-0000-4000-8000-0000000000dd"

// albumWithCompilationCopy is a library holding "Main Album" by Main
// Artist, two songs, and a Various Artists compilation scanned before it
// that holds a second copy of the album's first song, so that copy has the
// lower pid: the one a tie between the two answers with. Both copies carry
// one recording id.
func albumWithCompilationCopy(t *testing.T) (context.Context, *migrateFixture, string) {
	t.Helper()
	var libDir string
	song := func(name, title, album, albumArtist, track string) fixtures.Spec {
		return fixtures.Spec{
			Name: name, Codec: fixtures.CodecFLAC, Duration: 3 * time.Second,
			Tags: map[string]string{
				"TITLE": title, "ARTIST": "Main Artist", "ALBUM": album,
				"ALBUMARTIST": albumArtist, "TRACKNUMBER": track,
			},
		}
	}
	ctx, f := newMigrateFixtureWith(t, func(t *testing.T, dir string) {
		libDir = dir
		comp := song("comp-first", "First Song", "Compilation", "Various Artists", "7")
		comp.Tags["COMPILATION"] = "1"
		if _, err := fixtures.Generate(filepath.Join(dir, "compilation"), comp); err != nil {
			t.Fatal(err)
		}
	})
	time.Sleep(2 * time.Millisecond)
	if _, err := fixtures.Generate(filepath.Join(libDir, "main"),
		song("main-first", "First Song", "Main Album", "Main Artist", "1"),
		song("main-second", "Second Song", "Main Album", "Main Artist", "2"),
	); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	copies := f.itemsTitled(t, ctx, "First Song")
	if len(copies) != 2 || copies[0].Album != "Compilation" || copies[1].Album != "Main Album" {
		t.Fatalf("copies = %d, want the compilation's first by pid, then the album's", len(copies))
	}
	for _, it := range copies {
		if err := f.svc.lib.EditFields(ctx, it.PID, map[string]string{"mbid": sharedRecordingMBID}, waxbin.EditOptions{}); err != nil {
			t.Fatal(err)
		}
	}
	return ctx, f, libDir
}

// starredGroups is a Subsonic server whose stars are one album and one
// artist with that album as their only one, holding the songs given.
func starredGroups(t *testing.T, albumName string, songs ...string) *httptest.Server {
	t.Helper()
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch strings.TrimSuffix(strings.TrimPrefix(r.URL.Path, "/rest/"), ".view") {
		case "getStarred2":
			writeSubsonic(w, fmt.Sprintf(`"starred2":{"song":[],`+
				`"album":[{"id":"al-src","name":%q,"artist":"Main Artist"}],`+
				`"artist":[{"id":"ar-src","name":"Main Artist"}]}`, albumName), true)
		case "getArtist":
			writeSubsonic(w, `"artist":{"id":"ar-src","name":"Main Artist","album":[{"id":"al-src"}]}`, true)
		case "getAlbum":
			writeSubsonic(w, `"album":{"id":"al-src","song":[`+strings.Join(songs, ",")+`]}`, true)
		case "getBookmarks":
			writeSubsonic(w, `"bookmarks":{"bookmark":[]}`, true)
		default:
			writeSubsonic(w, `"error":{"code":0,"message":"unknown method"}`, false)
		}
	}))
	t.Cleanup(ts.Close)
	return ts
}

// starredTitles reads back the starred albums' and artists' titles.
func (f *migrateFixture) starredTitles(t *testing.T, ctx context.Context) (albums, artists []string) {
	t.Helper()
	ents := f.starredEntities(t, ctx)
	for _, a := range ents.Albums {
		albums = append(albums, a.Title)
	}
	for _, a := range ents.Artists {
		artists = append(artists, a.Title)
	}
	return albums, artists
}

// A group star lands on the entity a member names, and a tie's copy
// decides the entity: the first song answers with its compilation copy.
// The album's other song resolves uniquely, so it decides, and neither the
// compilation nor Various Artists is starred.
func TestMigrateSubsonicEntityStarsPassOverATieForAUniqueMember(t *testing.T) {
	t.Parallel()
	ctx, f, _ := albumWithCompilationCopy(t)
	ts := starredGroups(t, "Main Album (Collector's Edition)",
		`{"id":"s-first","title":"First Song","artist":"Main Artist","album":"Main Album (Collector's Edition)",`+
			`"duration":3,"musicBrainzId":"`+sharedRecordingMBID+`"}`,
		`{"id":"s-second","title":"Second Song","artist":"Main Artist","album":"Main Album (Collector's Edition)","duration":3}`)

	sum := f.runMigration(t, ctx, MigrationRequest{
		Source: "navidrome", ServerURL: ts.URL, Username: "demo", Password: "demo-pass", Stars: true,
	})
	if sum.AlbumStars != 1 || sum.ArtistStars != 1 {
		t.Fatalf("summary = %+v, want one album and one artist starred", sum)
	}
	albums, artists := f.starredTitles(t, ctx)
	if len(albums) != 1 || albums[0] != "Main Album" {
		t.Errorf("starred albums = %q, want Main Album", albums)
	}
	if len(artists) != 1 || artists[0] != "Main Artist" {
		t.Errorf("starred artists = %q, want Main Artist", artists)
	}
}

// With no member resolving uniquely, a tie whose copies all name one album
// decides over one that splits two, wherever it falls in the group, and
// however the copies spell their recording id: the catalog keeps it as
// tagged and matches it in any case.
func TestMigrateSubsonicEntityStarsPreferATieOnOneAlbum(t *testing.T) {
	t.Parallel()
	for name, spell := range map[string]func(string) string{
		"spelled as the source sends it": func(id string) string { return id },
		"spelled in upper case":          strings.ToUpper,
	} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			preferATieOnOneAlbum(t, spell)
		})
	}
}

func preferATieOnOneAlbum(t *testing.T, spell func(string) string) {
	ctx, f, libDir := albumWithCompilationCopy(t)
	// A second copy of the album's other song, on the album itself.
	if _, err := fixtures.Generate(filepath.Join(libDir, "main"), fixtures.Spec{
		Name: "main-second-again", Codec: fixtures.CodecFLAC, Duration: 3 * time.Second,
		Tags: map[string]string{
			"TITLE": "Second Song", "ARTIST": "Main Artist", "ALBUM": "Main Album",
			"ALBUMARTIST": "Main Artist", "TRACKNUMBER": "9",
		},
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	const secondMBID = "00000000-0000-4000-8000-0000000000ee"
	copies := f.itemsTitled(t, ctx, "Second Song")
	if len(copies) != 2 || copies[0].AlbumPID != copies[1].AlbumPID {
		t.Fatalf("second song copies = %d, want two on one album", len(copies))
	}
	for _, it := range copies {
		if err := f.svc.lib.EditFields(ctx, it.PID, map[string]string{"mbid": spell(secondMBID)}, waxbin.EditOptions{}); err != nil {
			t.Fatal(err)
		}
	}
	if stored := f.itemsTitled(t, ctx, "Second Song")[0].MBID; stored != spell(secondMBID) {
		t.Fatalf("the catalog keeps the id as %q, want %q as tagged", stored, spell(secondMBID))
	}
	ts := starredGroups(t, "Main Album (Collector's Edition)",
		`{"id":"s-first","title":"First Song","artist":"Main Artist","album":"Main Album (Collector's Edition)",`+
			`"duration":3,"musicBrainzId":"`+sharedRecordingMBID+`"}`,
		`{"id":"s-second","title":"Second Song","artist":"Main Artist","album":"Main Album (Collector's Edition)",`+
			`"duration":3,"musicBrainzId":"`+secondMBID+`"}`)

	sum := f.runMigration(t, ctx, MigrationRequest{
		Source: "navidrome", ServerURL: ts.URL, Username: "demo", Password: "demo-pass", Stars: true,
	})
	if sum.AlbumStars != 1 || sum.ArtistStars != 1 {
		t.Fatalf("summary = %+v, want one album and one artist starred", sum)
	}
	albums, artists := f.starredTitles(t, ctx)
	if len(albums) != 1 || albums[0] != "Main Album" {
		t.Errorf("starred albums = %q, want Main Album", albums)
	}
	if len(artists) != 1 || artists[0] != "Main Artist" {
		t.Errorf("starred artists = %q, want Main Artist", artists)
	}
}

// A group whose every member ties still stars, through the first tie: no
// member says otherwise.
func TestMigrateSubsonicEntityStarsFallBackOnATie(t *testing.T) {
	t.Parallel()
	ctx, f, _ := albumWithCompilationCopy(t)
	copies := f.itemsTitled(t, ctx, "First Song")
	ts := starredGroups(t, "Main Album (Collector's Edition)",
		`{"id":"s-first","title":"First Song","artist":"Main Artist","album":"Main Album (Collector's Edition)",`+
			`"duration":3,"musicBrainzId":"`+sharedRecordingMBID+`"}`)

	sum := f.runMigration(t, ctx, MigrationRequest{
		Source: "navidrome", ServerURL: ts.URL, Username: "demo", Password: "demo-pass", Stars: true,
	})
	if sum.AlbumStars != 1 || sum.ArtistStars != 1 || sum.UnmatchedEntities != 0 {
		t.Fatalf("summary = %+v, want both groups starred through the tie", sum)
	}
	albums, _ := f.starredTitles(t, ctx)
	if len(albums) != 1 || albums[0] != copies[0].Album {
		t.Errorf("starred albums = %q, want the lowest copy's %q", albums, copies[0].Album)
	}
}

// A Jellyfin favourite reaches its members through the songs walked for
// state first. One that only ties there is no answer while the group holds
// more: the server is asked for the rest, and a unique member decides.
func TestMigrateJellyfinEntityStarsAskForTheGroupPastATie(t *testing.T) {
	t.Parallel()
	ctx, f, _ := albumWithCompilationCopy(t)
	const album = "Main Album (Collector's Edition)"
	song := func(id, title, mbid, userData string) string {
		return fmt.Sprintf(`{"Id":%q,"Name":%q,"Album":%q,"AlbumArtist":"Main Artist",`+
			`"Artists":["Main Artist"],"RunTimeTicks":30000000,"ProviderIds":{"MusicBrainzTrack":%q},"UserData":%s}`,
			id, title, album, mbid, userData)
	}
	played := song("jf-first", "First Song", sharedRecordingMBID, `{"PlayCount":1}`)
	unplayed := song("jf-second", "Second Song", "", `{}`)
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/Users/AuthenticateByName" {
			fmt.Fprint(w, `{"AccessToken":"jf-token","User":{"Id":"jf-user"}}`)
			return
		}
		q := r.URL.Query()
		var rows []string
		switch {
		case r.URL.Path != "/Items" || q.Get("StartIndex") != "0":
		case q.Get("Filters") == "IsFavorite":
			rows = []string{
				fmt.Sprintf(`{"Id":"jf-al","Type":"MusicAlbum","Name":%q,"AlbumArtist":"Main Artist"}`, album),
				`{"Id":"jf-ar","Type":"MusicArtist","Name":"Main Artist"}`,
			}
		case q.Get("ParentId") == "jf-al" || q.Get("ArtistIds") == "jf-ar":
			rows = []string{played, unplayed}
		case q.Get("IncludeItemTypes") == "Audio":
			rows = []string{played, unplayed}
		}
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprintf(w, `{"Items":[%s],"TotalRecordCount":%d}`, strings.Join(rows, ","), len(rows))
	}))
	t.Cleanup(ts.Close)

	sum := f.runMigration(t, ctx, MigrationRequest{
		Source: "jellyfin", ServerURL: ts.URL, Username: "demo", Password: "demo-pass", Stars: true,
	})
	if sum.AlbumStars != 1 || sum.ArtistStars != 1 {
		t.Fatalf("summary = %+v, want one album and one artist starred", sum)
	}
	albums, artists := f.starredTitles(t, ctx)
	if len(albums) != 1 || albums[0] != "Main Album" {
		t.Errorf("starred albums = %q, want Main Album", albums)
	}
	if len(artists) != 1 || artists[0] != "Main Artist" {
		t.Errorf("starred artists = %q, want Main Artist", artists)
	}
}
