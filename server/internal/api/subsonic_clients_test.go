package api

import (
	"context"
	"crypto/md5"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"

	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
	"github.com/colespringer/waxdeck/server/internal/service"
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

// clientPostOK performs the call the way Feishin actually ships it:
// every parameter, credentials included, form-encoded in a POST body
// with nothing on the URL. GET coverage says nothing about this path.
func clientPostOK(t *testing.T, h *harness, secret, client, view string, form url.Values) map[string]any {
	t.Helper()
	salt := fmt.Sprintf("s%d", time.Now().UnixNano())
	sum := md5.Sum([]byte(secret + salt))
	form.Set("u", "admin")
	form.Set("t", hex.EncodeToString(sum[:]))
	form.Set("s", salt)
	form.Set("v", "1.16.1")
	form.Set("c", client)
	form.Set("f", "json")
	resp, err := http.Post(h.ts.URL+"/rest/"+view,
		"application/x-www-form-urlencoded", strings.NewReader(form.Encode()))
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 {
		t.Fatalf("POST %s (%s) status = %d: %s", view, client, resp.StatusCode, body)
	}
	var wrapper map[string]map[string]any
	if err := json.Unmarshal(body, &wrapper); err != nil {
		t.Fatalf("POST %s (%s): %v (%s)", view, client, err, body)
	}
	env, ok := wrapper["subsonic-response"]
	if !ok || env["status"] != "ok" {
		t.Fatalf("POST %s (%s) = %v", view, client, env)
	}
	return env
}

// jmap and jlist navigate the decoded JSON; a missing list reads as
// empty.
func jmap(v any) map[string]any {
	m, _ := v.(map[string]any)
	return m
}

func jlist(v any) []any {
	l, _ := v.([]any)
	return l
}

// addLaterAlbum scans in one more album after the demo one, so "most
// recently added" and "alphabetically first" name different albums.
func addLaterAlbum(t *testing.T, h *harness) {
	t.Helper()
	if _, err := fixtures.Generate(h.library,
		albumListSpec("zebra1", "Zebra One", "Zebra Band", "Zebra Arrivals", "2025", "Pop"),
	); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
}

func TestSubsonicClientDSub(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	addLaterAlbum(t, h)
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

	// The home screen lists and secondary tabs. "Recently added" leads
	// with the album scanned last, not the alphabetical first.
	env = mustOK(t, h, secret, c, "getAlbumList.view", "&type=newest&size=20")
	if albums := jlist(jmap(env["albumList"])["album"]); len(albums) != 2 || jmap(albums[0])["title"] != "Zebra Arrivals" {
		t.Fatalf("getAlbumList newest = %v, want Zebra Arrivals first", albums)
	}
	env = mustOK(t, h, secret, c, "getRandomSongs.view", "&size=20")
	if len(jlist(jmap(env["randomSongs"])["song"])) == 0 {
		t.Fatal("getRandomSongs answered no songs")
	}
	mustOK(t, h, secret, c, "getStarred.view", "")
	mustOK(t, h, secret, c, "getPlaylists.view", "")
	mustOK(t, h, secret, c, "getPodcasts.view", "")
	mustOK(t, h, secret, c, "getBookmarks.view", "")
	mustOK(t, h, secret, c, "getNowPlaying.view", "")

	// Play: now-playing update, stream, timed submission.
	mustOK(t, h, secret, c, "scrobble.view", "&id="+songID+"&submission=false")
	streamAndAssertBytes(t, h, "/rest/stream.view?apiKey="+secret+"&id="+songID)
	mustOK(t, h, secret, c, "scrobble.view",
		fmt.Sprintf("&id=%s&time=%d&submission=true", songID, time.Now().Add(-time.Minute).UnixMilli()))
}

// TestSubsonicClientDSubEditsAPlaylist replays DSub's playlist editor: it
// re-reads the list after every edit and removes rows by the index it
// rendered, singly or several at once, taking exactly the rows swiped.
func TestSubsonicClientDSubEditsAPlaylist(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	secret := newSubsonicSecret(t, h)
	const c = "DSub"
	page := h.items(t, "")
	var songs strings.Builder
	var want []string
	for _, it := range page.Items[:4] {
		songs.WriteString("&songId=" + url.QueryEscape(it.Pid))
		want = append(want, it.Pid)
	}
	env := mustOK(t, h, secret, c, "createPlaylist.view", "&name=Road+Mix"+songs.String())
	id := fmt.Sprintf("%v", jmap(env["playlist"])["id"])
	read := func() []string {
		t.Helper()
		var ids []string
		for _, e := range jlist(jmap(mustOK(t, h, secret, c, "getPlaylist.view", "&id="+url.QueryEscape(id))["playlist"])["entry"]) {
			ids = append(ids, fmt.Sprintf("%v", jmap(e)["id"]))
		}
		return ids
	}
	check := func(step string, got, want []string) {
		t.Helper()
		if strings.Join(got, ",") != strings.Join(want, ",") {
			t.Fatalf("%s: entries = %v, want %v", step, got, want)
		}
	}
	check("created", read(), want)
	mustOK(t, h, secret, c, "updatePlaylist.view", "&playlistId="+url.QueryEscape(id)+"&songIndexToRemove=0")
	check("removed the first", read(), want[1:])
	mustOK(t, h, secret, c, "updatePlaylist.view", "&playlistId="+url.QueryEscape(id)+"&songIndexToRemove=1")
	check("removed the second of three", read(), []string{want[1], want[3]})
	mustOK(t, h, secret, c, "updatePlaylist.view",
		"&playlistId="+url.QueryEscape(id)+"&songIndexToRemove=0&songIndexToRemove=1")
	check("removed both left", read(), nil)
	mustOK(t, h, secret, c, "deletePlaylist.view", "&id="+url.QueryEscape(id))
}

func TestSubsonicClientFeishin(t *testing.T) {
	t.Parallel()
	// The tracks index serves the whole library, so the harness carries
	// the two shapes that broke it in the browser harness: an ADTS AAC,
	// whose stored container is the composite label "aac (adts)", and a
	// garbage file with no probeable container at all.
	exotic := t.TempDir()
	if _, err := fixtures.Generate(exotic,
		fixtures.Spec{Codec: fixtures.CodecAAC, Container: fixtures.ContainerADTS},
		fixtures.Spec{Codec: fixtures.CodecFLAC, Corrupt: fixtures.CorruptGarbage},
	); err != nil {
		t.Fatalf("generating exotic fixtures: %v", err)
	}
	h := newHarness(t, service.Root{Name: "exotic", Path: exotic})
	secret := newSubsonicSecret(t, h)
	const c = "Feishin"

	// Feishin connects, then syncs by tags with paged album lists.
	//
	// getUser is the very first call, and it is the whole sign-in: the
	// credentials form submits, this answers, and the app either enters
	// or stays on the login screen. The trace used to start at ping,
	// which is why a server that could serve every other call here
	// still could not be logged into - the browser harness found it.
	env := mustOK(t, h, secret, c, "getUser.view", "&username=admin")
	if u := jmap(env["user"]); u["username"] != "admin" || u["streamRole"] != true {
		t.Fatalf("getUser = %v", env["user"])
	}
	mustOK(t, h, secret, c, "ping.view", "")
	mustOK(t, h, secret, c, "getMusicFolders.view", "")
	env = mustOK(t, h, secret, c, "getArtists.view", "")
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

	// The tracks index, POSTed the way Feishin ships every request. It
	// is the one surface that serializes the whole library, exotic
	// shapes included, and its renderer dereferences contentType on
	// every row without checking - so the field is load-bearing on every
	// song, however unprobeable the file. The browser harness found the
	// miss as a listing stuck at a skeleton, retrying a 200 forever.
	// First the count probe: one song at a rising offset until empty.
	env = clientPostOK(t, h, secret, c, "search3.view", url.Values{
		"query": {""}, "songCount": {"1"}, "songOffset": {"0"},
		"albumCount": {"0"}, "artistCount": {"0"},
	})
	if n := len(jlist(jmap(env["searchResult3"])["song"])); n != 1 {
		t.Fatalf("count probe at offset 0 = %d songs, want 1", n)
	}
	env = clientPostOK(t, h, secret, c, "search3.view", url.Values{
		"query": {""}, "songCount": {"1"}, "songOffset": {"5000"},
		"albumCount": {"0"}, "artistCount": {"0"},
	})
	if n := len(jlist(jmap(env["searchResult3"])["song"])); n != 0 {
		t.Fatalf("count probe past the end = %d songs, want 0", n)
	}
	env = clientPostOK(t, h, secret, c, "search3.view", url.Values{
		"query": {""}, "songCount": {"100"}, "songOffset": {"0"},
		"albumCount": {"0"}, "artistCount": {"0"},
	})
	songs := jlist(jmap(env["searchResult3"])["song"])
	if len(songs) < 5 {
		t.Fatalf("tracks index = %d songs, want the whole library", len(songs))
	}
	sawADTS := false
	for _, s := range songs {
		sm := jmap(s)
		ct, _ := sm["contentType"].(string)
		if ct == "" {
			t.Fatalf("song %v carries no contentType", sm["title"])
		}
		suffix, _ := sm["suffix"].(string)
		if strings.ContainsAny(suffix, " ()") {
			t.Fatalf("suffix %q is a probe label, not an extension", suffix)
		}
		if suffix == "aac" && ct == "audio/aac" {
			sawADTS = true
		}
	}
	if !sawADTS {
		t.Fatal("the ADTS fixture did not serialize as suffix aac + audio/aac")
	}

	// Search-as-you-type and play.
	env = mustOK(t, h, secret, c, "search3.view", "&query=Alpha&artistCount=20&albumCount=20&songCount=20")
	if len(jlist(jmap(env["searchResult3"])["song"])) == 0 {
		t.Fatal("search3 found nothing")
	}
	streamAndAssertBytes(t, h, "/rest/stream.view?apiKey="+secret+"&id="+songID)
}

// TestSubsonicClientFeishinHomeRows replays Feishin's home screen: one
// album list per row, POSTed the way it ships every request, then the
// album page and the tracks index it opens. Each row leads with the album
// the seeded history says it should, which an alphabetical answer to
// every type (what the surface once gave) cannot do.
func TestSubsonicClientFeishinHomeRows(t *testing.T) {
	t.Parallel()
	h, secret := albumListHarness(t)
	st := seedAlbumListState(t, h, secret)
	const c = "Feishin"

	row := func(form url.Values) []any {
		t.Helper()
		form.Set("offset", "0")
		form.Set("size", "15")
		return jlist(jmap(clientPostOK(t, h, secret, c, "getAlbumList2", form)["albumList2"])["album"])
	}
	for _, tc := range []struct {
		name  string
		form  url.Values
		first string
	}{
		{"Recently played", url.Values{"type": {"recent"}}, "New Record"},
		// Added last, released longest ago: the two rows must disagree.
		{"Recently added", url.Values{"type": {"newest"}}, "Zenith Record"},
		{"Recently released", url.Values{"type": {"byYear"}, "fromYear": {fmt.Sprint(time.Now().Year())}, "toYear": {"0"}}, "New Record"},
		// The most plays in all, not the most played track (Mid One).
		{"Most played", url.Values{"type": {"frequent"}}, "Old Record"},
	} {
		albums := row(tc.form)
		if len(albums) == 0 || jmap(albums[0])["name"] != tc.first {
			t.Errorf("%s = %v, want %s first", tc.name, albums, tc.first)
		}
	}
	if albums := row(url.Values{"type": {"random"}}); len(albums) != 5 {
		t.Errorf("Explore (random) = %d albums, want all 5", len(albums))
	}

	// The album page draws the heart and the stars from the album itself.
	env := clientPostOK(t, h, secret, c, "getAlbum", url.Values{"id": {st.id("Old Record")}})
	if a := jmap(env["album"]); a["starred"] == nil {
		t.Errorf("getAlbum Old Record = %v, want its star", a)
	}
	env = clientPostOK(t, h, secret, c, "getAlbum", url.Values{"id": {st.id("Mid Record")}})
	if a := jmap(env["album"]); a["userRating"] != float64(4) {
		t.Errorf("getAlbum Mid Record = %v, want rating 4", a)
	}
	env = clientPostOK(t, h, secret, c, "getArtists", url.Values{})
	if len(jlist(jmap(env["artists"])["index"])) == 0 {
		t.Error("getArtists answered no index")
	}
	env = clientPostOK(t, h, secret, c, "search3", url.Values{
		"query": {""}, "songCount": {"100"}, "songOffset": {"0"}, "albumCount": {"0"}, "artistCount": {"0"},
	})
	starredSongs := 0
	for _, s := range jlist(jmap(env["searchResult3"])["song"]) {
		if m := jmap(s); m["starred"] != nil {
			starredSongs++
			if m["id"] != st.songs["New Two"] {
				t.Errorf("tracks index stars %v, want New Two alone", m["title"])
			}
		}
	}
	if starredSongs != 1 {
		t.Errorf("tracks index carries %d starred songs, want New Two", starredSongs)
	}
}

func TestSubsonicClientSymfonium(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	addLaterAlbum(t, h)
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
	env = mustOK(t, h, secret, c, "getAlbumList2", "&type=newest&size=500")
	if albums := jlist(jmap(env["albumList2"])["album"]); len(albums) != 2 || jmap(albums[0])["name"] != "Zebra Arrivals" {
		t.Fatalf("getAlbumList2 newest = %v, want Zebra Arrivals first", albums)
	}
	// The sync walks newest at rising offsets until a page comes back
	// empty, and takes what it has read as the whole library.
	crawled := map[string]bool{}
	for offset := 0; ; offset++ {
		env = mustOK(t, h, secret, c, "getAlbumList2", fmt.Sprintf("&type=newest&size=1&offset=%d", offset))
		albums := jlist(jmap(env["albumList2"])["album"])
		if len(albums) == 0 {
			break
		}
		crawled[fmt.Sprint(jmap(albums[0])["id"])] = true
		if offset > 10 {
			t.Fatal("the newest crawl never came back empty")
		}
	}
	env = mustOK(t, h, secret, c, "getAlbumList2", "&type=alphabeticalByName&size=500")
	for _, a := range jlist(jmap(env["albumList2"])["album"]) {
		if !crawled[fmt.Sprint(jmap(a)["id"])] {
			t.Errorf("the newest crawl never reached %v", jmap(a)["name"])
		}
	}
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

// Symfonium keeps an audiobook's resume point as a Subsonic bookmark and,
// on a server advertising transcodeOffset, starts the stream there with
// timeOffset. A book in parts reaches it only as one bookmark entry, so
// the stream it starts is the rest of the book: the part the bookmark
// falls in, from the bookmark, then every part after it.
func TestSubsonicClientSymfoniumResumesABookInParts(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	h.engineMP3.Store(true)
	secret := newSubsonicSecret(t, h)
	const c = "Symfonium"
	book, _ := subsonicBook(t, h) // parts of 4, 5 and 6 s

	env := mustOK(t, h, secret, c, "getOpenSubsonicExtensions", "")
	offsets := false
	for _, e := range jlist(env["openSubsonicExtensions"]) {
		offsets = offsets || jmap(e)["name"] == "transcodeOffset"
	}
	if !offsets {
		t.Fatal("transcodeOffset is not advertised, so Symfonium would not send an offset")
	}
	mustOK(t, h, secret, c, "createBookmark", "&id="+book+"&position=6500")
	env = mustOK(t, h, secret, c, "getBookmarks", "")
	var id string
	var position float64
	for _, bm := range jlist(jmap(env["bookmarks"])["bookmark"]) {
		if e := jmap(jmap(bm)["entry"]); e["id"] == book {
			id, position = book, jmap(bm)["position"].(float64)
		}
	}
	if id == "" || position != 6500 {
		t.Fatalf("getBookmarks = %v, want the book at 6500", env["bookmarks"])
	}

	loc := streamRedirect(t, h, fmt.Sprintf("/rest/stream?apiKey=%s&id=%s&timeOffset=%g", secret, id, position/1000))
	resp, err := http.Get(h.ts.URL + loc)
	if err != nil {
		t.Fatal(err)
	}
	body, err := io.ReadAll(resp.Body)
	resp.Body.Close()
	if err != nil || resp.StatusCode != 200 || resp.Header.Get("Content-Type") != "audio/mpeg" {
		t.Fatalf("the resumed stream = %d %q (%v), want 200 audio/mpeg", resp.StatusCode, resp.Header.Get("Content-Type"), err)
	}
	if got, want := partsAsked(h), []string{"02 - Part Two.m4b@2", "03 - Part Three.m4b"}; !slices.Equal(got, want) {
		t.Fatalf("the engine encoded %v, want %v", got, want)
	}
	// The stand-in encodes each part whole, cut or not: parts two and three.
	if secs := mp3Seconds(t, body); secs < 11 || secs > 11.2 {
		t.Fatalf("the resumed stream plays %.3f s, want parts two and three's 11", secs)
	}
}

// Symfonium resumes a podcast episode where it left off by starting the
// stream there with timeOffset, on a server advertising transcodeOffset.
// An episode the server has not fetched has only the feed's own file to
// relay, which no offset can cut: the stream is refused rather than handed
// over from its top while the client's clock reads the resume point (and
// saves that clock back as the position). From its start it plays through
// the relay as ever.
func TestSubsonicClientSymfoniumResumesAnUnfetchedEpisode(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	feed := newFeedServer(t, 1)
	decodeStatus[Subscription](t, h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()}), 201, "subscribe")
	secret := newSubsonicSecret(t, h)
	const c = "Symfonium"

	env := mustOK(t, h, secret, c, "getOpenSubsonicExtensions", "")
	offsets := false
	for _, e := range jlist(env["openSubsonicExtensions"]) {
		offsets = offsets || jmap(e)["name"] == "transcodeOffset"
	}
	if !offsets {
		t.Fatal("transcodeOffset is not advertised, so Symfonium would not send an offset")
	}
	env = mustOK(t, h, secret, c, "getPodcasts", "&includeEpisodes=true")
	var streamID string
	for _, ch := range jlist(jmap(env["podcasts"])["channel"]) {
		for _, ep := range jlist(jmap(ch)["episode"]) {
			if jmap(ep)["status"] == "skipped" {
				streamID, _ = jmap(ep)["streamId"].(string)
			}
		}
	}
	if streamID == "" {
		t.Fatalf("no unfetched episode with a streamId in %v", env["podcasts"])
	}

	noFollow := &http.Client{CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	resp, err := noFollow.Get(h.ts.URL + "/rest/stream?apiKey=" + secret + "&f=json&c=" + c + "&id=" + streamID + "&timeOffset=60")
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK || !strings.Contains(string(body), `"status":"failed"`) {
		t.Fatalf("a resume 60 s into an unfetched episode = %d to %q (%s), want a refusal, not its top",
			resp.StatusCode, resp.Header.Get("Location"), body)
	}
	if loc := streamRedirect(t, h, "/rest/stream?apiKey="+secret+"&id="+streamID); !strings.HasPrefix(loc, "/media/enclosure?") {
		t.Fatalf("the episode from its start = %s, want the passthrough relay", loc)
	}
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
		// raw is the protocol's own "do not transcode", so it beats a
		// cap sent beside it rather than being overridden by one.
		"&format=raw&maxBitRate=128",
		"&format=RAW&maxBitRate=128",
	} {
		t.Run(strings.TrimPrefix(hint, "&"), func(t *testing.T) {
			streamAndAssertBytes(t, h, "/rest/stream.view?apiKey="+secret+"&id="+songID+hint)
		})
	}
}

// TestSubsonicStreamHonoursMaxBitRate is the other half: a real cap is
// parsed, clamped and handed to the bridge, so a client on a phone
// network gets an encode at the number it asked for rather than the
// lossless file. It pins the flac song, because a lossy source already
// inside the cap is meant to stream unchanged and would prove nothing.
func TestSubsonicStreamHonoursMaxBitRate(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	secret := newSubsonicSecret(t, h)
	const c = "test"

	env := mustOK(t, h, secret, c, "search3.view", "&query=Alpha")
	songID, _ := jmap(jlist(jmap(env["searchResult3"])["song"])[0])["id"].(string)
	if !strings.HasPrefix(songID, "tr-") {
		t.Fatalf("songID = %q", songID)
	}

	for _, tc := range []struct {
		hint       string
		want       string // the br= the redirect must carry
		wantFormat string // and the format it lands in
	}{
		// A client that names no format gets MP3, which every client
		// decodes.
		{hint: "&maxBitRate=128", want: "128", wantFormat: "mp3"},
		// Below the floor no codec speaks; above the ceiling a cap
		// cannot beat direct play. Neither may reach the mint unclamped.
		{hint: "&maxBitRate=8", want: "32", wantFormat: "mp3"},
		{hint: "&maxBitRate=9999", want: "320", wantFormat: "mp3"},
		// The request DSub and Symfonium actually send. What a client
		// pins beside a cap is what it can decode, so the encode lands
		// there rather than on the ladder's own pick.
		{hint: "&maxBitRate=192&format=mp3", want: "192", wantFormat: "mp3"},
		// A format this engine cannot produce falls back to the ladder
		// rather than advertising bytes the stream will never serve.
		{hint: "&maxBitRate=192&format=wma", want: "192"},
	} {
		t.Run(strings.TrimPrefix(tc.hint, "&"), func(t *testing.T) {
			loc := streamRedirect(t, h, "/rest/stream.view?apiKey="+secret+"&id="+songID+tc.hint)
			q, err := url.ParseQuery(strings.TrimPrefix(loc, "/media/stream?"))
			if err != nil {
				t.Fatalf("parsing %s: %v", loc, err)
			}
			if q.Get("br") != tc.want || q.Get("fmt") == "" {
				t.Fatalf("capped redirect = %s, want br=%s and a format", loc, tc.want)
			}
			if tc.wantFormat != "" && q.Get("fmt") != tc.wantFormat {
				t.Fatalf("capped redirect = %s, want the client's own %s", loc, tc.wantFormat)
			}
			resp, err := http.Get(h.ts.URL + loc)
			if err != nil {
				t.Fatal(err)
			}
			audio, _ := io.ReadAll(resp.Body)
			resp.Body.Close()
			if resp.StatusCode != 200 || len(audio) == 0 {
				t.Fatalf("capped stream status = %d bytes = %d", resp.StatusCode, len(audio))
			}
		})
	}
}

// streamRedirect issues a /rest/stream call and returns the location it
// redirects to, asserting that the adapter assembled that URL itself:
// none of the caller's own query may appear on it.
func streamRedirect(t *testing.T, h *harness, path string) string {
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
	for _, forwarded := range []string{"maxBitRate", "bitRate", "format=raw", "timeOffset"} {
		if strings.Contains(loc, forwarded) {
			t.Fatalf("stream redirect forwarded the client's %s: %s", forwarded, loc)
		}
	}
	// A t on the redirect is the adapter's own cut, there only for a
	// client that asked for an offset; a token-auth client's t is its
	// password hash.
	u, err := url.Parse(loc)
	if err != nil {
		t.Fatalf("parsing %s: %v", loc, err)
	}
	if u.Query().Has("t") && !strings.Contains(path, "timeOffset=") {
		t.Fatalf("stream redirect carries a t the client never asked for: %s", loc)
	}
	return loc
}

// subsonicSongID finds the song a search3 for query answers first.
func subsonicSongID(t *testing.T, h *harness, secret, query string) string {
	t.Helper()
	env := mustOK(t, h, secret, "test", "search3.view", "&query="+url.QueryEscape(query))
	songID, _ := jmap(jlist(jmap(env["searchResult3"])["song"])[0])["id"].(string)
	if !strings.HasPrefix(songID, "tr-") {
		t.Fatalf("songID = %q", songID)
	}
	return songID
}

// redirectQuery answers the parameters a stream redirect carries.
func redirectQuery(t *testing.T, loc string) url.Values {
	t.Helper()
	u, err := url.Parse(loc)
	if err != nil {
		t.Fatalf("parsing %s: %v", loc, err)
	}
	return u.Query()
}

// A client's start offset is the stream's cut: the redirect carries the
// adapter's own t in whole seconds, never the token-auth t of the same
// name, and the engine starts there. Anything but a positive number is no
// offset at all.
func TestSubsonicTimeOffsetCutsTheStream(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	secret := newSubsonicSecret(t, h)
	songID := subsonicSongID(t, h, secret, "Alpha") // a 2 s flac

	salt := "cutsalt"
	sum := md5.Sum([]byte(secret + salt))
	tokenAuth := "u=admin&t=" + hex.EncodeToString(sum[:]) + "&s=" + salt + "&v=1.16.1&c=test"
	loc := streamRedirect(t, h, "/rest/stream.view?"+tokenAuth+"&id="+songID+"&maxBitRate=128&timeOffset=1.5")
	if q := redirectQuery(t, loc); q.Get("t") != "1" || q.Get("br") != "128" {
		t.Fatalf("redirect = %s, want a 128 kbps stream cut at 1", loc)
	}
	if code := fetchStatus(t, h, loc); code != 200 {
		t.Fatalf("cut stream = %d", code)
	}
	if h.flowReq.cut != "1" || h.flowReq.bitrate != "128" {
		t.Fatalf("the engine saw cut %q at %q, want 1 at 128", h.flowReq.cut, h.flowReq.bitrate)
	}

	for _, offset := range []string{"", "0", "-3", "NaN", "Inf", "abc"} {
		loc := streamRedirect(t, h, "/rest/stream.view?apiKey="+secret+"&id="+songID+"&maxBitRate=128&timeOffset="+offset)
		if redirectQuery(t, loc).Has("t") {
			t.Errorf("timeOffset=%q cut the stream: %s", offset, loc)
		}
	}
	// raw is the file as it is, which an offset cannot be.
	loc = streamRedirect(t, h, "/rest/stream.view?apiKey="+secret+"&id="+songID+"&format=raw&timeOffset=1")
	if q := redirectQuery(t, loc); q.Has("t") || q.Has("fmt") {
		t.Errorf("a raw request was cut: %s", loc)
	}
}

// An offset into an original is an encode from that point, so it takes a
// transcode slot like any other: refused while the server is full, where
// the original played whole is not.
func TestSubsonicTimeOffsetOnAnOriginalGoesThroughTheGate(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	secret := newSubsonicSecret(t, h)
	songID := subsonicSongID(t, h, secret, "Alpha")

	wantStatus(t, h.putJSON(t, "/api/v1/admin/transcoding", map[string]any{
		"maxConcurrent": 1, "maxConcurrentPerUser": 0, "defaultMaxBitrateKbps": 0,
	}), 200, "one transcode server-wide")
	release, err := h.svc.TranscodeGate().Acquire(context.Background(), "someone-else", flow.TranscodeStream)
	if err != nil {
		t.Fatal(err)
	}
	defer release()

	cut := streamRedirect(t, h, "/rest/stream.view?apiKey="+secret+"&id="+songID+"&timeOffset=1")
	if q := redirectQuery(t, cut); q.Get("t") != "1" || q.Get("fmt") != "flac" || q.Get("enc") != "1" {
		t.Fatalf("redirect = %s, want a lossless encode cut at 1", cut)
	}
	if code := fetchStatus(t, h, cut); code != http.StatusTooManyRequests {
		t.Fatalf("a cut while the server is full = %d, want 429", code)
	}
	whole := streamRedirect(t, h, "/rest/stream.view?apiKey="+secret+"&id="+songID)
	if code := fetchStatus(t, h, whole); code != 200 {
		t.Fatalf("the original played whole = %d, want 200", code)
	}

	release()
	if code := fetchStatus(t, h, cut); code != 200 || h.flowReq.format != "flac" || h.flowReq.cut != "1" {
		t.Fatalf("the cut once a slot is free = %d, engine saw %s from %q; want flac from 1",
			code, h.flowReq.format, h.flowReq.cut)
	}
}

// A book in parts is one song to a Subsonic client, so a bookmark's offset
// is on the whole book: the stream resolves the part it falls in, as
// play-info does, cuts that part from inside rather than the first part at
// its last second, and plays on through the parts after it.
func TestSubsonicTimeOffsetIntoABookLandsInItsPart(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	h.engineMP3.Store(true)
	if _, err := fixtures.GenerateBook(h.library); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	secret := newSubsonicSecret(t, h)
	books := h.items(t, "?mediaType=audiobook").Items
	if len(books) != 1 {
		t.Fatalf("audiobooks = %d, want the fixture book", len(books))
	}
	book := books[0].Pid

	// Parts of 4, 5 and 6 s: 6.5 s into the book is 2.5 s into part two.
	pi := decode[PlayInfo](t, get(t, h.ts, "/api/v1/items/"+book+"/play-info?positionMs=6500", h.token))
	partTwo := redirectQuery(t, pi.Url).Get("f")
	if partTwo == "" {
		t.Fatalf("play-info named no part: %s", pi.Url)
	}
	loc := streamRedirect(t, h, "/rest/stream.view?apiKey="+secret+"&id="+book+"&timeOffset=6.5")
	if q := redirectQuery(t, loc); q.Get("f") != partTwo || q.Get("t") != "2" || q.Get("join") != "1" {
		t.Fatalf("redirect = %s, want the book from part two (%s), cut at 2", loc, partTwo)
	}
	if code := fetchStatus(t, h, loc); code != 200 {
		t.Fatalf("the stream from part two = %d, want 200", code)
	}
	if got, want := partsAsked(h), []string{"02 - Part Two.m4b@2", "03 - Part Three.m4b"}; !slices.Equal(got, want) {
		t.Fatalf("the engine encoded %v, want %v", got, want)
	}
}

// The extension is advertised exactly where it works: a server running
// the engine that cuts.
func TestSubsonicAdvertisesTranscodeOffsetWithTheEngine(t *testing.T) {
	t.Parallel()
	for name, c := range map[string]struct {
		h    func(*testing.T) *harness
		want bool
	}{
		"with the engine":    {newHarnessNoExtras, true},
		"without the engine": {newHarnessDirect, false},
	} {
		h := c.h(t)
		secret := newSubsonicSecret(t, h)
		env := mustOK(t, h, secret, "test", "getOpenSubsonicExtensions", "")
		got := false
		for _, e := range jlist(env["openSubsonicExtensions"]) {
			if jmap(e)["name"] == "transcodeOffset" {
				got = true
			}
		}
		if got != c.want {
			t.Errorf("%s: transcodeOffset advertised %v, want %v", name, got, c.want)
		}
	}
}

// newHarnessNoExtras is newHarness as a function value.
func newHarnessNoExtras(t *testing.T) *harness { return newHarness(t) }

// streamAndAssertBytes follows the stream redirect into the tokenized
// proxy and asserts the original bytes arrive: no cap was applied, so
// the URL carries no bitrate of its own either.
func streamAndAssertBytes(t *testing.T, h *harness, path string) {
	t.Helper()
	loc := streamRedirect(t, h, path)
	if strings.Contains(loc, "br=") {
		t.Fatalf("an uncapped hint minted a bitrate: %s", loc)
	}
	resp, err := http.Get(h.ts.URL + loc)
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
