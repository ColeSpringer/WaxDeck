package api

import (
	"fmt"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// foldersHarness is the demo library ("lib") beside a second music root
// ("vinyl") holding its own album and one more track of the demo album,
// which therefore belongs to both folders.
func foldersHarness(t *testing.T) (*harness, string) {
	t.Helper()
	dir := t.TempDir()
	if _, err := fixtures.Generate(dir,
		albumListSpec("groove1", "Groove One", "Groove Band", "Vinyl Days", "1977", "Funk"),
		fixtures.Spec{Name: "echo", Codec: fixtures.CodecFLAC, Duration: time.Second, Tags: map[string]string{
			"TITLE": "Echo Song", "ARTIST": "Fixture Artist", "ALBUM": "Fixture Album",
		}},
	); err != nil {
		t.Fatal(err)
	}
	h := newHarness(t, service.Root{Name: "vinyl", Path: dir})
	return h, newSubsonicSecret(t, h)
}

// folderIDs maps each folder name getMusicFolders lists to its id.
func folderIDs(t *testing.T, env map[string]any) map[string]string {
	t.Helper()
	out := map[string]string{}
	for _, f := range jlist(jmap(env["musicFolders"])["musicFolder"]) {
		out[fmt.Sprint(jmap(f)["name"])] = fmt.Sprint(jmap(f)["id"])
	}
	return out
}

func artistNames(env map[string]any) []string {
	var out []string
	for _, sec := range jlist(jmap(env["artists"])["index"]) {
		for _, a := range jlist(jmap(sec)["artist"]) {
			out = append(out, fmt.Sprint(jmap(a)["name"]))
		}
	}
	return out
}

func TestSubsonicMusicFoldersScopeBrowsing(t *testing.T) {
	t.Parallel()
	h, secret := foldersHarness(t)

	ids := folderIDs(t, mustOK(t, h, secret, "test", "getMusicFolders", ""))
	if len(ids) != 2 || ids["lib"] == "" || ids["vinyl"] == "" || ids["lib"] == ids["vinyl"] {
		t.Fatalf("folders = %v, want lib and vinyl", ids)
	}
	lib, vinyl := "&musicFolderId="+ids["lib"], "&musicFolderId="+ids["vinyl"]

	if got := artistNames(mustOK(t, h, secret, "test", "getArtists", vinyl)); !slices.Equal(got, []string{"Fixture Artist", "Groove Band"}) {
		t.Errorf("vinyl artists = %v", got)
	}
	if got := artistNames(mustOK(t, h, secret, "test", "getArtists", lib)); !slices.Equal(got, []string{"Fixture Artist"}) {
		t.Errorf("lib artists = %v", got)
	}
	env := mustOK(t, h, secret, "test", "getIndexes", lib)
	if n := len(jlist(jmap(env["indexes"])["index"])); n != 1 {
		t.Errorf("lib indexes = %v, want Fixture Artist's section alone", env["indexes"])
	}

	// An album belongs to every folder holding one of its tracks, with
	// that folder's tracks.
	_, albums := albumListNames(t, h, secret, "&type=alphabeticalByName"+vinyl)
	if len(albums) != 2 || albums["Fixture Album"]["songCount"] != float64(1) || albums["Vinyl Days"] == nil {
		t.Errorf("vinyl albums = %v, want Vinyl Days and the demo album's one track there", albums)
	}
	env = mustOK(t, h, secret, "test", "getAlbumList", "&type=alphabeticalByName"+lib)
	if a := jlist(jmap(env["albumList"])["album"]); len(a) != 1 || jmap(a[0])["title"] != "Fixture Album" {
		t.Errorf("lib folder-mode albums = %v", a)
	}

	env = mustOK(t, h, secret, "test", "search3", "&query=&songCount=50"+lib)
	if n := len(jlist(jmap(env["searchResult3"])["song"])); n != 4 {
		t.Errorf("lib songs = %d, want the demo album's 4", n)
	}
	env = mustOK(t, h, secret, "test", "getRandomSongs", "&size=50"+vinyl)
	if n := len(jlist(jmap(env["randomSongs"])["song"])); n != 2 {
		t.Errorf("vinyl random songs = %d, want 2", n)
	}
	for folder, want := range map[string]int{lib: 0, vinyl: 1} {
		env = mustOK(t, h, secret, "test", "getSongsByGenre", "&genre=Funk"+folder)
		if n := len(jlist(jmap(env["songsByGenre"])["song"])); n != want {
			t.Errorf("Funk songs under %s = %d, want %d", folder, n, want)
		}
	}

	// Starred lists keep to the folder too.
	groove := jmap(jlist(jmap(mustOK(t, h, secret, "test", "search3", "&query=Groove")["searchResult3"])["song"])[0])["id"]
	alpha := subsonicSongID(t, h, secret, "Alpha")
	mustOK(t, h, secret, "test", "star", fmt.Sprintf("&id=%v&id=%s", groove, alpha))
	for view, key := range map[string]string{"getStarred2": "starred2", "getStarred": "starred"} {
		env = mustOK(t, h, secret, "test", view, lib)
		if s := jlist(jmap(env[key])["song"]); len(s) != 1 || jmap(s[0])["id"] != alpha {
			t.Errorf("%s under lib = %v, want Alpha Song alone", view, s)
		}
	}

	for _, bad := range []string{"&musicFolderId=99999", "&musicFolderId=abc"} {
		env := clientCall(t, h, secret, "test", "getArtists", bad)
		if env["status"] != "failed" || jmap(env["error"])["code"] != float64(70) {
			t.Errorf("getArtists%s = %v, want error 70", bad, env)
		}
	}

	// A library added later takes a new id and moves none.
	wantStatus(t, h.postJSON(t, "/api/v1/libraries", map[string]any{"name": "tapes", "path": t.TempDir(), "media": "music"}), 201, "add tapes")
	again := folderIDs(t, mustOK(t, h, secret, "test", "getMusicFolders", ""))
	if again["lib"] != ids["lib"] || again["vinyl"] != ids["vinyl"] || again["tapes"] == "" || again["tapes"] == ids["lib"] || again["tapes"] == ids["vinyl"] {
		t.Errorf("folders after an add = %v, before %v", again, ids)
	}

	// A library made to hold audiobooks is no folder while it does, and its
	// id is 70; made music again, it is back under the id it had.
	var vinylPID string
	for _, l := range decode[Libraries](t, get(t, h.ts, "/api/v1/libraries", h.token)).Libraries {
		if l.Name == "vinyl" {
			vinylPID = l.Pid
		}
	}
	wantStatus(t, h.putJSON(t, "/api/v1/libraries/"+vinylPID+"/media", map[string]any{"media": "audiobook"}), 200, "vinyl to audiobook")
	if retyped := folderIDs(t, mustOK(t, h, secret, "test", "getMusicFolders", "")); retyped["vinyl"] != "" || retyped["lib"] != ids["lib"] {
		t.Errorf("folders while vinyl holds audiobooks = %v", retyped)
	}
	if env := clientCall(t, h, secret, "test", "getArtists", vinyl); env["status"] != "failed" || jmap(env["error"])["code"] != float64(70) {
		t.Errorf("the retyped folder = %v, want error 70", env)
	}
	wantStatus(t, h.putJSON(t, "/api/v1/libraries/"+vinylPID+"/media", map[string]any{"media": "music"}), 200, "vinyl back to music")
	if back := folderIDs(t, mustOK(t, h, secret, "test", "getMusicFolders", "")); back["vinyl"] != ids["vinyl"] {
		t.Errorf("folders after vinyl is music again = %v, want vinyl under %s", back, ids["vinyl"])
	}
}

// A musicFolderId that names nothing narrows nothing, so a starred
// episode still lists; a real folder lists its own tracks alone.
func TestSubsonicStarredUnderABlankFolder(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	feed := newFeedServer(t, 1)
	decodeStatus[Subscription](t, h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()}), 201, "subscribe")
	secret := newSubsonicSecret(t, h)
	var episode string
	for _, ch := range jlist(jmap(mustOK(t, h, secret, "test", "getPodcasts", "&includeEpisodes=true")["podcasts"])["channel"]) {
		for _, ep := range jlist(jmap(ch)["episode"]) {
			episode = fmt.Sprint(jmap(ep)["id"])
		}
	}
	alpha := subsonicSongID(t, h, secret, "Alpha")
	mustOK(t, h, secret, "test", "star", "&id="+alpha+"&id="+episode)
	ids := folderIDs(t, mustOK(t, h, secret, "test", "getMusicFolders", ""))
	starred := func(extra string) []string {
		t.Helper()
		var out []string
		for _, s := range jlist(jmap(mustOK(t, h, secret, "test", "getStarred2", extra)["starred2"])["song"]) {
			out = append(out, fmt.Sprint(jmap(s)["id"]))
		}
		slices.Sort(out)
		return out
	}
	if got, want := starred("&musicFolderId=%20"), starred(""); !slices.Equal(got, want) || len(got) != 2 {
		t.Errorf("starred under a blank folder = %v, want %v, the episode included", got, want)
	}
	if got := starred("&musicFolderId=" + ids["lib"]); !slices.Equal(got, []string{alpha}) {
		t.Errorf("starred under lib = %v, want Alpha Song alone", got)
	}
}

// A restricted account lists exactly its granted music libraries, under
// the ids everyone else sees, and cannot name another.
func TestSubsonicMusicFoldersAreTheCallers(t *testing.T) {
	t.Parallel()
	h, secret := foldersHarness(t)
	ids := folderIDs(t, mustOK(t, h, secret, "test", "getMusicFolders", ""))

	who := subsonicAccountWithGrants(t, h, "vinyl-only", "vinyl")

	if got := folderIDs(t, clientCallAs(t, h, who, "getMusicFolders", "")); len(got) != 1 || got["vinyl"] != ids["vinyl"] {
		t.Fatalf("restricted folders = %v, want vinyl alone under id %s", got, ids["vinyl"])
	}
	env := clientCallAs(t, h, who, "getArtists", "&musicFolderId="+ids["lib"])
	if env["status"] != "failed" || jmap(env["error"])["code"] != float64(70) {
		t.Errorf("an ungranted folder = %v, want error 70", env)
	}
	env = clientCallAs(t, h, who, "getArtists", "&musicFolderId="+ids["vinyl"])
	if got := artistNames(env); !slices.Equal(got, []string{"Fixture Artist", "Groove Band"}) {
		t.Errorf("restricted vinyl artists = %v", got)
	}
}

// A library declared to hold audiobooks makes every file in it a book,
// so chapters that would read as music anywhere else reach no Subsonic
// music list, and the library is no folder.
func TestSubsonicAudiobookLibraryStaysOutOfMusic(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	chapter := func(name, title string) fixtures.Spec {
		return fixtures.Spec{Name: name, Codec: fixtures.CodecMP3, Duration: time.Second, Tags: map[string]string{
			"TITLE": title, "ARTIST": "Reader Name", "ALBUM": "Librivox Tale", "TRACKNUMBER": strings.TrimPrefix(name, "ch"),
		}}
	}
	if _, err := fixtures.Generate(dir, chapter("ch1", "Chapter One"), chapter("ch2", "Chapter Two")); err != nil {
		t.Fatal(err)
	}
	h := newHarness(t, service.Root{Name: "books", Path: dir, Media: "audiobook"})
	secret := newSubsonicSecret(t, h)
	if books := h.items(t, "?mediaType=audiobook"); len(books.Items) != 1 {
		t.Fatalf("audiobooks = %d, want the declared library's one book", len(books.Items))
	}

	chapters := func(songs []any) []string {
		var out []string
		for _, s := range songs {
			if m := jmap(s); m["album"] == "Librivox Tale" || strings.HasPrefix(fmt.Sprint(m["title"]), "Chapter") {
				out = append(out, fmt.Sprint(m["title"]))
			}
		}
		return out
	}
	env := mustOK(t, h, secret, "test", "getRandomSongs", "&size=500")
	if got := chapters(jlist(jmap(env["randomSongs"])["song"])); len(got) != 0 {
		t.Errorf("getRandomSongs carries book parts %v", got)
	}
	env = mustOK(t, h, secret, "test", "search3", "&query=&songCount=500&albumCount=500")
	if got := chapters(jlist(jmap(env["searchResult3"])["song"])); len(got) != 0 {
		t.Errorf("search3 carries book parts %v", got)
	}
	for _, a := range jlist(jmap(env["searchResult3"])["album"]) {
		if jmap(a)["name"] == "Librivox Tale" {
			t.Errorf("search3 lists the book as an album: %v", a)
		}
	}
	_, albums := albumListNames(t, h, secret, "&type=alphabeticalByName&size=500")
	if _, ok := albums["Librivox Tale"]; ok || len(albums) != 1 {
		t.Errorf("getAlbumList2 = %v, want the demo album alone", albums)
	}
	if ids := folderIDs(t, mustOK(t, h, secret, "test", "getMusicFolders", "")); len(ids) != 1 || ids["lib"] == "" {
		t.Errorf("folders = %v, want lib alone", ids)
	}

	// An account granted the books alone has no music folder at all.
	reader := subsonicAccountWithGrants(t, h, "books-only", "books")
	env = clientCallAs(t, h, reader, "getMusicFolders", "")
	if f, ok := jmap(env["musicFolders"])["musicFolder"].([]any); env["status"] != "ok" || !ok || len(f) != 0 {
		t.Errorf("a books-only account's folders = %v, want an empty list", env)
	}
}
