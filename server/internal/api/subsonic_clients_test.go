package api

import (
	"crypto/md5"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"testing"
	"time"
)

// The real-client conformance suite. Each test replays the request
// sequence one third-party client actually issues on its startup,
// browse, and play path, with that client's auth style, format, and
// endpoint order, chaining ids from each response into the next call
// the way the client does. The traces are derived from the DSub and
// Feishin sources and Symfonium's documented server requirements; a
// missing endpoint on any of these paths is a startup failure in the
// real client, so it fails here.

// clientCall performs one /rest call the way the emulated client
// would (token auth, per-request salt, f=json, the client's c= name)
// and returns the decoded envelope.
func clientCall(t *testing.T, h *harness, secret, client, view, extra string) map[string]any {
	t.Helper()
	salt := fmt.Sprintf("s%d", time.Now().UnixNano())
	sum := md5.Sum([]byte(secret + salt))
	q := "?u=admin&t=" + hex.EncodeToString(sum[:]) + "&s=" + salt + "&v=1.16.1&c=" + client + "&f=json" + extra
	resp, err := http.Get(h.ts.URL + "/rest/" + view + q)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 {
		t.Fatalf("%s (%s) status = %d: %s", view, client, resp.StatusCode, body)
	}
	var wrapper map[string]map[string]any
	if err := json.Unmarshal(body, &wrapper); err != nil {
		t.Fatalf("%s (%s): %v (%s)", view, client, err, body)
	}
	env, ok := wrapper["subsonic-response"]
	if !ok {
		t.Fatalf("%s (%s): no subsonic-response in %s", view, client, body)
	}
	return env
}

// mustOK asserts a success envelope and returns it.
func mustOK(t *testing.T, h *harness, secret, client, view, extra string) map[string]any {
	t.Helper()
	env := clientCall(t, h, secret, client, view, extra)
	if env["status"] != "ok" {
		t.Fatalf("%s (%s) = %v", view, client, env)
	}
	return env
}

// jmap and jlist navigate the decoded JSON; a missing list reads as
// empty (the renderer emits null for empty slices).
func jmap(v any) map[string]any {
	m, _ := v.(map[string]any)
	return m
}

func jlist(v any) []any {
	l, _ := v.([]any)
	return l
}

func TestSubsonicClientDSub(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	secret := newSubsonicSecret(t, h)
	const c = "DSub"

	// DSub connects, lists folders, and browses by directory out of
	// the box (tag browsing is an opt-in setting).
	mustOK(t, h, secret, c, "ping.view", "")
	env := mustOK(t, h, secret, c, "getMusicFolders.view", "")
	folders := jlist(jmap(env["musicFolders"])["musicFolder"])
	if len(folders) == 0 {
		t.Fatal("no music folders")
	}
	folderID := fmt.Sprintf("%v", jmap(folders[0])["id"])

	env = mustOK(t, h, secret, c, "getIndexes.view", "&musicFolderId="+folderID)
	var artistID string
	for _, sec := range jlist(jmap(env["indexes"])["index"]) {
		for _, a := range jlist(jmap(sec)["artist"]) {
			if jmap(a)["name"] == "Fixture Artist" {
				artistID, _ = jmap(a)["id"].(string)
			}
		}
	}
	if artistID == "" {
		t.Fatalf("Fixture Artist not in getIndexes: %v", env["indexes"])
	}

	env = mustOK(t, h, secret, c, "getMusicDirectory.view", "&id="+url.QueryEscape(artistID))
	var albumID string
	for _, ch := range jlist(jmap(env["directory"])["child"]) {
		m := jmap(ch)
		if m["isDir"] != true {
			t.Fatalf("artist directory child is not a directory: %v", m)
		}
		if m["title"] == "Fixture Album" {
			albumID, _ = m["id"].(string)
		}
	}
	if albumID == "" {
		t.Fatalf("Fixture Album not in artist directory: %v", env["directory"])
	}

	env = mustOK(t, h, secret, c, "getMusicDirectory.view", "&id="+url.QueryEscape(albumID))
	var songID string
	songs := jlist(jmap(env["directory"])["child"])
	if len(songs) != 4 {
		t.Fatalf("album directory children = %d, want 4", len(songs))
	}
	for _, ch := range jlist(jmap(env["directory"])["child"]) {
		m := jmap(ch)
		if m["isDir"] != false {
			t.Fatalf("album directory child is a directory: %v", m)
		}
		if m["title"] == "Alpha Song" {
			songID, _ = m["id"].(string)
		}
	}
	if !strings.HasPrefix(songID, "tr-") {
		t.Fatalf("songID = %q", songID)
	}

	// The home screen lists and secondary tabs.
	env = mustOK(t, h, secret, c, "getAlbumList.view", "&type=newest&size=20")
	if len(jlist(jmap(env["albumList"])["album"])) == 0 {
		t.Fatal("getAlbumList answered no albums")
	}
	env = mustOK(t, h, secret, c, "getRandomSongs.view", "&size=20")
	if len(jlist(jmap(env["randomSongs"])["song"])) == 0 {
		t.Fatal("getRandomSongs answered no songs")
	}
	mustOK(t, h, secret, c, "getStarred.view", "")
	mustOK(t, h, secret, c, "getPlaylists.view", "")
	mustOK(t, h, secret, c, "getPodcasts.view", "")
	mustOK(t, h, secret, c, "getBookmarks.view", "")

	// Play: now-playing update, stream, timed submission.
	mustOK(t, h, secret, c, "scrobble.view", "&id="+songID+"&submission=false")
	streamAndAssertBytes(t, h, "/rest/stream.view?apiKey="+secret+"&id="+songID)
	mustOK(t, h, secret, c, "scrobble.view",
		fmt.Sprintf("&id=%s&time=%d&submission=true", songID, time.Now().Add(-time.Minute).UnixMilli()))
}

func TestSubsonicClientFeishin(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	secret := newSubsonicSecret(t, h)
	const c = "Feishin"

	// Feishin connects, then syncs by tags with paged album lists.
	mustOK(t, h, secret, c, "ping.view", "")
	mustOK(t, h, secret, c, "getMusicFolders.view", "")
	env := mustOK(t, h, secret, c, "getArtists.view", "")
	var artistID string
	for _, sec := range jlist(jmap(env["artists"])["index"]) {
		for _, a := range jlist(jmap(sec)["artist"]) {
			if jmap(a)["name"] == "Fixture Artist" {
				artistID, _ = jmap(a)["id"].(string)
			}
		}
	}
	if artistID == "" {
		t.Fatal("Fixture Artist not in getArtists")
	}
	env = mustOK(t, h, secret, c, "getAlbumList2.view", "&type=alphabeticalByName&size=500&offset=0")
	albums := jlist(jmap(env["albumList2"])["album"])
	if len(albums) == 0 {
		t.Fatal("getAlbumList2 answered no albums")
	}
	env = mustOK(t, h, secret, c, "getAlbumList2.view", "&type=alphabeticalByName&size=500&offset=500")
	if n := len(jlist(jmap(env["albumList2"])["album"])); n != 0 {
		t.Fatalf("page past the end = %d albums, want 0", n)
	}
	mustOK(t, h, secret, c, "getGenres.view", "")
	mustOK(t, h, secret, c, "getPlaylists.view", "")
	mustOK(t, h, secret, c, "getScanStatus.view", "")

	// The artist page fires info, top songs, and the album chain.
	mustOK(t, h, secret, c, "getArtistInfo2.view", "&id="+url.QueryEscape(artistID))
	mustOK(t, h, secret, c, "getTopSongs.view", "&artist="+url.QueryEscape("Fixture Artist"))
	env = mustOK(t, h, secret, c, "getArtist.view", "&id="+url.QueryEscape(artistID))
	albumID, _ := jmap(jlist(jmap(env["artist"])["album"])[0])["id"].(string)
	env = mustOK(t, h, secret, c, "getAlbum.view", "&id="+url.QueryEscape(albumID))
	var songID string
	for _, s := range jlist(jmap(env["album"])["song"]) {
		if jmap(s)["title"] == "Alpha Song" {
			songID, _ = jmap(s)["id"].(string)
		}
	}
	if songID == "" {
		t.Fatal("Alpha Song not in getAlbum")
	}

	// Favorites and ratings round-trip.
	mustOK(t, h, secret, c, "star.view", "&id="+songID)
	env = mustOK(t, h, secret, c, "getStarred2.view", "")
	found := false
	for _, s := range jlist(jmap(env["starred2"])["song"]) {
		if jmap(s)["id"] == songID {
			found = true
		}
	}
	if !found {
		t.Fatal("starred song not in getStarred2")
	}
	mustOK(t, h, secret, c, "unstar.view", "&id="+songID)
	mustOK(t, h, secret, c, "setRating.view", "&id="+songID+"&rating=4")

	// Search-as-you-type and play.
	env = mustOK(t, h, secret, c, "search3.view", "&query=Alpha&artistCount=20&albumCount=20&songCount=20")
	if len(jlist(jmap(env["searchResult3"])["song"])) == 0 {
		t.Fatal("search3 found nothing")
	}
	streamAndAssertBytes(t, h, "/rest/stream.view?apiKey="+secret+"&id="+songID)
}

func TestSubsonicClientSymfonium(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	secret := newSubsonicSecret(t, h)
	const c = "Symfonium"

	// Symfonium reads the extensions list the moment the envelope
	// declares openSubsonic, and uses apiKey auth when advertised.
	env := mustOK(t, h, secret, c, "ping", "")
	if env["openSubsonic"] != true {
		t.Fatalf("ping does not declare openSubsonic: %v", env)
	}
	env = mustOK(t, h, secret, c, "getOpenSubsonicExtensions", "")
	exts := map[string]bool{}
	for _, e := range jlist(env["openSubsonicExtensions"]) {
		name, _ := jmap(e)["name"].(string)
		exts[name] = true
	}
	if !exts["apiKeyAuthentication"] || !exts["formPost"] {
		t.Fatalf("advertised extensions = %v", exts)
	}

	// Both advertised schemes must actually work: apiKey in the query,
	// and parameters in a POST form body.
	resp, err := http.Get(h.ts.URL + "/rest/ping?apiKey=" + secret + "&f=json")
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if !strings.Contains(string(body), `"status":"ok"`) {
		t.Fatalf("apiKey ping = %s", body)
	}
	resp, err = http.Post(h.ts.URL+"/rest/ping", "application/x-www-form-urlencoded",
		strings.NewReader(url.Values{"apiKey": {secret}, "f": {"json"}}.Encode()))
	if err != nil {
		t.Fatal(err)
	}
	body, _ = io.ReadAll(resp.Body)
	resp.Body.Close()
	if !strings.Contains(string(body), `"status":"ok"`) {
		t.Fatalf("formPost ping = %s", body)
	}

	// Library sync.
	mustOK(t, h, secret, c, "getMusicFolders", "")
	env = mustOK(t, h, secret, c, "getArtists", "")
	var artistID string
	for _, sec := range jlist(jmap(env["artists"])["index"]) {
		for _, a := range jlist(jmap(sec)["artist"]) {
			artistID, _ = jmap(a)["id"].(string)
		}
	}
	mustOK(t, h, secret, c, "getAlbumList2", "&type=newest&size=500")
	mustOK(t, h, secret, c, "getStarred2", "")
	mustOK(t, h, secret, c, "getPlaylists", "")
	mustOK(t, h, secret, c, "getScanStatus", "")
	mustOK(t, h, secret, c, "getGenres", "")
	mustOK(t, h, secret, c, "getPodcasts", "")

	// Browse and play over apiKey auth.
	env = mustOK(t, h, secret, c, "getArtist", "&id="+url.QueryEscape(artistID))
	albumID, _ := jmap(jlist(jmap(env["artist"])["album"])[0])["id"].(string)
	env = mustOK(t, h, secret, c, "getAlbum", "&id="+url.QueryEscape(albumID))
	songID, _ := jmap(jlist(jmap(env["album"])["song"])[0])["id"].(string)
	streamAndAssertBytes(t, h, "/rest/stream?apiKey="+secret+"&id="+songID)
	mustOK(t, h, secret, c, "scrobble",
		fmt.Sprintf("&id=%s&time=%d&submission=true", songID, time.Now().Add(-time.Minute).UnixMilli()))
}

// TestSubsonicStreamIgnoresClientBitrateHints pins the habit several
// clients have of asking for lossless with an explicit zero or an empty
// maxBitRate. The sidecar now refuses both spellings on its own
// parameters, so what matters is that neither ever reaches it: the
// adapter builds WaxFlow's query itself and forwards none of the
// client's. A regression here would surface as a client that plays
// everywhere except when it asks for the best quality.
func TestSubsonicStreamIgnoresClientBitrateHints(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	secret := newSubsonicSecret(t, h)
	const c = "test"

	env := mustOK(t, h, secret, c, "getRandomSongs.view", "&size=1")
	songID, _ := jmap(jlist(jmap(env["randomSongs"])["song"])[0])["id"].(string)
	if !strings.HasPrefix(songID, "tr-") {
		t.Fatalf("songID = %q", songID)
	}

	for _, hint := range []string{
		"&maxBitRate=0", // "no cap": DSub, Symfonium
		"&maxBitRate=",  // the same intent, empty
		"&format=raw",   // "give me the file"
		"&maxBitRate=0&bitRate=0",
	} {
		t.Run(strings.TrimPrefix(hint, "&"), func(t *testing.T) {
			streamAndAssertBytes(t, h, "/rest/stream.view?apiKey="+secret+"&id="+songID+hint)
		})
	}
}

// streamAndAssertBytes follows the stream redirect into the tokenized
// proxy and asserts audio bytes arrive. It also pins that the location
// it redirects to carries none of the caller's query: the adapter
// assembles the sidecar's parameters server-side.
func streamAndAssertBytes(t *testing.T, h *harness, path string) {
	t.Helper()
	client := &http.Client{CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	resp, err := client.Get(h.ts.URL + path)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 302 {
		t.Fatalf("stream status = %d, want 302", resp.StatusCode)
	}
	loc := resp.Header.Get("Location")
	for _, forwarded := range []string{"maxBitRate", "bitRate", "format=raw"} {
		if strings.Contains(loc, forwarded) {
			t.Fatalf("stream redirect forwarded the client's %s: %s", forwarded, loc)
		}
	}
	resp, err = http.Get(h.ts.URL + loc)
	if err != nil {
		t.Fatal(err)
	}
	audio, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != 200 || len(audio) == 0 {
		t.Fatalf("proxied stream status = %d bytes = %d", resp.StatusCode, len(audio))
	}
}

// TestSubsonicEntityIDCutover pins the identifier change on the wire.
// Browse hands out catalog entity pids now, and an id a client cached
// from the previous minted scheme still resolves, so the cutover does
// not strand the stored favorites and playlists already in the wild.
func TestSubsonicEntityIDCutover(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	secret := newSubsonicSecret(t, h)
	const c = "test"

	env := mustOK(t, h, secret, c, "getArtists", "")
	var artistID string
	for _, sec := range jlist(jmap(env["artists"])["index"]) {
		for _, a := range jlist(jmap(sec)["artist"]) {
			if jmap(a)["name"] == "Fixture Artist" {
				artistID, _ = jmap(a)["id"].(string)
			}
		}
	}
	if !strings.HasPrefix(artistID, "ar-") {
		t.Fatalf("artist id = %q, want a catalog entity pid", artistID)
	}
	env = mustOK(t, h, secret, c, "getArtist", "&id="+url.QueryEscape(artistID))
	albumID, _ := jmap(jlist(jmap(env["artist"])["album"])[0])["id"].(string)
	if !strings.HasPrefix(albumID, "al-") {
		t.Fatalf("album id = %q, want a catalog entity pid", albumID)
	}

	// The pre-cutover forms: "A!" + base64(artist) and "L!" +
	// base64(artist US album).
	minted := func(prefix, s string) string {
		return prefix + "!" + base64.RawURLEncoding.EncodeToString([]byte(s))
	}
	legacyArtist := minted("A", "Fixture Artist")
	legacyAlbum := minted("L", "Fixture Artist\x1fFixture Album")

	env = mustOK(t, h, secret, c, "getArtist", "&id="+url.QueryEscape(legacyArtist))
	if jmap(env["artist"])["name"] != "Fixture Artist" {
		t.Fatalf("cached minted artist id did not resolve: %v", env["artist"])
	}
	// Following a cached id hands back the entity form, so a client that
	// stores what it reads migrates itself.
	if got := jmap(env["artist"])["id"]; got != artistID {
		t.Errorf("getArtist by cached id returned %v, want the entity id %s", got, artistID)
	}
	env = mustOK(t, h, secret, c, "getAlbum", "&id="+url.QueryEscape(legacyAlbum))
	if got := jmap(env["album"])["id"]; got != albumID {
		t.Errorf("getAlbum by cached id returned %v, want the entity id %s", got, albumID)
	}

	// Folder-mode browse takes either scheme, and answers the same
	// directory for both.
	for _, id := range []string{legacyAlbum, albumID} {
		env = mustOK(t, h, secret, c, "getMusicDirectory", "&id="+url.QueryEscape(id))
		dir := jmap(env["directory"])
		if dir["id"] != albumID || len(jlist(dir["child"])) != 4 {
			t.Errorf("getMusicDirectory(%q) = %v, want the album with its 4 songs", id, dir)
		}
	}
	// An id in neither scheme is still an unknown directory, not a
	// server error.
	if env := clientCall(t, h, secret, c, "getMusicDirectory", "&id=nonsense"); env["status"] != "failed" {
		t.Errorf("getMusicDirectory with a junk id = %v, want failed", env)
	}
}

func TestSubsonicRandomSongFilters(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	secret := newSubsonicSecret(t, h)
	const c = "test"

	env := mustOK(t, h, secret, c, "getRandomSongs", "&size=10")
	if n := len(jlist(jmap(env["randomSongs"])["song"])); n != 4 {
		t.Fatalf("unfiltered random songs = %d, want the whole fixture album", n)
	}
	// The fixture tracks carry no genre and no year, so any filter
	// must narrow to nothing rather than being silently ignored.
	env = mustOK(t, h, secret, c, "getRandomSongs", "&size=10&genre=Nope")
	if n := len(jlist(jmap(env["randomSongs"])["song"])); n != 0 {
		t.Fatalf("genre-filtered random songs = %d, want 0", n)
	}
	env = mustOK(t, h, secret, c, "getRandomSongs", "&size=10&fromYear=1900")
	if n := len(jlist(jmap(env["randomSongs"])["song"])); n != 0 {
		t.Fatalf("year-filtered random songs = %d, want 0 (fixtures are untagged)", n)
	}
}
