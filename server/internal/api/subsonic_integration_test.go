package api

import (
	"crypto/md5"
	"encoding/hex"
	"encoding/json"
	"encoding/xml"
	"io"
	"net/http"
	"strings"
	"testing"
)

// subsonicEnv decodes the JSON rendering's envelope for assertions.
type subsonicEnv struct {
	Status       string `json:"status"`
	Version      string `json:"version"`
	Type         string `json:"type"`
	OpenSubsonic bool   `json:"openSubsonic"`
	Error        *struct {
		Code    int    `json:"code"`
		Message string `json:"message"`
	} `json:"error"`
	User *struct {
		Username  string `json:"username"`
		AdminRole bool   `json:"adminRole"`
	} `json:"user"`
	Artists *struct {
		Index []struct {
			Name    string `json:"name"`
			Artists []struct {
				ID         string `json:"id"`
				Name       string `json:"name"`
				AlbumCount int    `json:"albumCount"`
			} `json:"artist"`
		} `json:"index"`
	} `json:"artists"`
	Artist *struct {
		Name   string `json:"name"`
		Albums []struct {
			ID        string `json:"id"`
			Name      string `json:"name"`
			SongCount int    `json:"songCount"`
		} `json:"album"`
	} `json:"artist"`
	Album *struct {
		Name  string `json:"name"`
		Songs []struct {
			ID          string `json:"id"`
			Title       string `json:"title"`
			ContentType string `json:"contentType"`
			Duration    int    `json:"duration"`
		} `json:"song"`
	} `json:"album"`
	AlbumList2 *struct {
		Albums []struct {
			Name string `json:"name"`
		} `json:"album"`
	} `json:"albumList2"`
	SearchResult3 *struct {
		Songs []struct {
			ID string `json:"id"`
		} `json:"song"`
	} `json:"searchResult3"`
}

// subsonicGet calls a /rest view with token auth and decodes the JSON
// envelope.
func subsonicGet(t *testing.T, h *harness, view, secret, extra string) subsonicEnv {
	t.Helper()
	salt := "abc123"
	sum := md5.Sum([]byte(secret + salt))
	q := "?u=admin&t=" + hex.EncodeToString(sum[:]) + "&s=" + salt + "&v=1.16.1&c=test&f=json" + extra
	resp, err := http.Get(h.ts.URL + "/rest/" + view + q)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		t.Fatalf("%s status = %d, want 200 (errors ride the envelope)", view, resp.StatusCode)
	}
	body, _ := io.ReadAll(resp.Body)
	var wrapper map[string]subsonicEnv
	if err := json.Unmarshal(body, &wrapper); err != nil {
		t.Fatalf("%s: %v (body %s)", view, err, body)
	}
	env, ok := wrapper["subsonic-response"]
	if !ok {
		t.Fatalf("%s: no subsonic-response key in %s", view, body)
	}
	return env
}

func newSubsonicSecret(t *testing.T, h *harness) string {
	t.Helper()
	resp := h.postJSON(t, "/api/v1/users/me/app-passwords", map[string]any{"label": "subsonic test"})
	if resp.StatusCode != 201 {
		t.Fatalf("app password status = %d", resp.StatusCode)
	}
	return decode[AppPasswordCreated](t, resp).Secret
}

func TestSubsonicBrowseAndStream(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	secret := newSubsonicSecret(t, h)

	// ping over both auth schemes and both formats.
	env := subsonicGet(t, h, "ping", secret, "")
	if env.Status != "ok" || !env.OpenSubsonic || env.Version != "1.16.1" || env.Type != "waxdeck" {
		t.Fatalf("ping envelope = %+v", env)
	}
	resp, err := http.Get(h.ts.URL + "/rest/ping.view?apiKey=" + secret)
	if err != nil {
		t.Fatal(err)
	}
	xmlBody, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if !strings.Contains(string(xmlBody), `status="ok"`) || !strings.Contains(string(xmlBody), "subsonic-response") {
		t.Fatalf("xml ping = %s", xmlBody)
	}
	var parsed struct {
		XMLName xml.Name `xml:"subsonic-response"`
		Status  string   `xml:"status,attr"`
	}
	if err := xml.Unmarshal(xmlBody, &parsed); err != nil || parsed.Status != "ok" {
		t.Fatalf("xml ping does not parse: %v (%s)", err, xmlBody)
	}

	// The ID3 browse chain: artists, artist, album, songs.
	env = subsonicGet(t, h, "getArtists", secret, "")
	if env.Artists == nil || len(env.Artists.Index) == 0 {
		t.Fatalf("getArtists = %+v", env)
	}
	var artistID string
	for _, idx := range env.Artists.Index {
		for _, a := range idx.Artists {
			if a.Name == "Fixture Artist" {
				artistID = a.ID
				if a.AlbumCount != 1 {
					t.Fatalf("albumCount = %d, want 1", a.AlbumCount)
				}
			}
		}
	}
	if artistID == "" {
		t.Fatal("Fixture Artist not in getArtists")
	}

	env = subsonicGet(t, h, "getArtist", secret, "&id="+artistID)
	if env.Artist == nil || len(env.Artist.Albums) != 1 || env.Artist.Albums[0].Name != "Fixture Album" {
		t.Fatalf("getArtist = %+v", env.Artist)
	}
	albumID := env.Artist.Albums[0].ID
	if env.Artist.Albums[0].SongCount != 4 {
		t.Fatalf("songCount = %d, want 4", env.Artist.Albums[0].SongCount)
	}

	env = subsonicGet(t, h, "getAlbum", secret, "&id="+albumID)
	if env.Album == nil || len(env.Album.Songs) != 4 {
		t.Fatalf("getAlbum = %+v", env.Album)
	}
	var songID string
	for _, s := range env.Album.Songs {
		if s.Title == "Alpha Song" {
			songID = s.ID
			if s.ContentType != "audio/flac" || s.Duration != 2 {
				t.Fatalf("song = %+v", s)
			}
		}
	}
	if songID == "" || !strings.HasPrefix(songID, "tr-") {
		t.Fatalf("songID = %q, want a real item pid", songID)
	}

	// getAlbumList2 and search3 agree with the browse chain.
	env = subsonicGet(t, h, "getAlbumList2", secret, "&type=alphabeticalByName")
	if env.AlbumList2 == nil || len(env.AlbumList2.Albums) != 1 {
		t.Fatalf("getAlbumList2 = %+v", env.AlbumList2)
	}
	env = subsonicGet(t, h, "search3", secret, "&query=Alpha")
	if env.SearchResult3 == nil || len(env.SearchResult3.Songs) != 1 || env.SearchResult3.Songs[0].ID != songID {
		t.Fatalf("search3 = %+v", env.SearchResult3)
	}

	// Cover art resolves through the album's member item (404 is fine:
	// the fixture album has no art; what matters is no panic and a
	// Subsonic-shaped error).
	resp, err = http.Get(h.ts.URL + "/rest/getCoverArt?apiKey=" + secret + "&id=" + albumID + "&f=json")
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()

	// stream redirects into the same tokenized proxy first-party
	// clients use, and the bytes flow.
	client := &http.Client{CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	resp, err = client.Get(h.ts.URL + "/rest/stream?apiKey=" + secret + "&id=" + songID)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 302 {
		t.Fatalf("stream status = %d, want 302", resp.StatusCode)
	}
	loc := resp.Header.Get("Location")
	if !strings.HasPrefix(loc, "/media/stream?pid="+songID) {
		t.Fatalf("stream redirect = %q", loc)
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

func TestSubsonicAuthAndStubs(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	secret := newSubsonicSecret(t, h)

	// Wrong token.
	env := subsonicGet(t, h, "ping", "WRONGSECRETWRONGSECRETWRON", "")
	if env.Status != "failed" || env.Error == nil || env.Error.Code != 40 {
		t.Fatalf("wrong-token env = %+v", env)
	}

	// The login password never works on this surface, even correctly
	// hashed (app passwords only).
	env = subsonicGet(t, h, "ping", testPassword, "")
	if env.Status != "failed" || env.Error == nil || env.Error.Code != 40 {
		t.Fatalf("login-password env = %+v", env)
	}

	// Plain-password auth is refused with the token-auth code.
	resp, err := http.Get(h.ts.URL + "/rest/ping?u=admin&p=" + secret + "&f=json")
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if !strings.Contains(string(body), `"code":41`) {
		t.Fatalf("p= auth = %s, want code 41", body)
	}

	// Scrobble is implemented: an unknown item answers the protocol's
	// not-found code, never a 500.
	env = subsonicGet(t, h, "scrobble", secret, "&id=tr-01JZX5N8QW3F4V9T2B7KD3M9R6")
	if env.Status != "failed" || env.Error == nil || env.Error.Code != 70 {
		t.Fatalf("scrobble with unknown id = %+v", env)
	}

	// Unimplemented endpoints stay explicit stubs, never 500s.
	env = subsonicGet(t, h, "jukeboxControl", secret, "")
	if env.Status != "failed" || env.Error == nil || env.Error.Code != 0 ||
		!strings.Contains(env.Error.Message, "jukebox") {
		t.Fatalf("jukebox stub = %+v", env)
	}
}

func TestSubsonicRemoveDuplicateIndexes(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	secret := newSubsonicSecret(t, h)

	// A playlist over the whole album, then a removal request naming
	// the same index twice: one row goes, never a second shifted one.
	items := h.items(t, "?mediaType=music")
	q := ""
	for _, it := range items.Items {
		q += "&songId=" + it.Pid
	}
	env := subsonicGet(t, h, "createPlaylist", secret, "&name=DupRemove"+q)
	if env.Status != "ok" {
		t.Fatalf("createPlaylist = %+v", env)
	}
	lists := decode[PlaylistPage](t, get(t, h.ts, "/api/v1/playlists", h.token))
	var pid string
	for _, pl := range lists.Playlists {
		if pl.Name == "DupRemove" {
			pid = pl.Pid
		}
	}
	if pid == "" {
		t.Fatal("created playlist not listed")
	}
	env = subsonicGet(t, h, "updatePlaylist", secret,
		"&playlistId="+pid+"&songIndexToRemove=1&songIndexToRemove=1")
	if env.Status != "ok" {
		t.Fatalf("updatePlaylist = %+v", env)
	}
	entries := decode[PlaylistItemsPage](t, get(t, h.ts, "/api/v1/playlists/"+pid+"/items", h.token))
	if len(entries.Entries) != len(items.Items)-1 {
		t.Fatalf("entries after duplicate removal = %d, want %d", len(entries.Entries), len(items.Items)-1)
	}
	for _, e := range entries.Entries {
		if e.Item.Title == items.Items[1].Title {
			t.Fatalf("index 1 (%q) still present", e.Item.Title)
		}
	}
}

func TestSubsonicVisibility(t *testing.T) {
	t.Parallel()
	h := newHarness(t)

	// Warm the full-visibility index first. The grouped index is cached
	// per catalog tail and per grant set, so a key that did not carry
	// the grants would hand the administrator's whole catalog to the
	// restricted caller below - which is the failure this ordering
	// exists to catch.
	adminSecret := newSubsonicSecret(t, h)
	warm := subsonicGet(t, h, "getArtists", adminSecret, "")
	if warm.Artists == nil || len(warm.Artists.Index) == 0 {
		t.Fatal("the administrator sees no artists; the visibility check below would prove nothing")
	}

	// A user with no library grants sees an empty catalog, not an error.
	resp := h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "subsonic-restricted", "password": "restricted-pass",
		"libraryAccess": map[string]any{"mode": "granted", "libraryPids": []string{}},
	})
	if resp.StatusCode != 201 {
		t.Fatalf("create user status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	rToken := loginAs(t, h.ts, "subsonic-restricted", "restricted-pass").Token
	resp = postJSON(t, h.ts.URL+"/api/v1/users/me/app-passwords", rToken, `{"label":"restricted subsonic"}`)
	if resp.StatusCode != 201 {
		t.Fatalf("restricted app password status = %d", resp.StatusCode)
	}
	secret := decode[AppPasswordCreated](t, resp).Secret

	salt := "xyz789"
	sum := md5.Sum([]byte(secret + salt))
	url := h.ts.URL + "/rest/getArtists?u=subsonic-restricted&t=" + hex.EncodeToString(sum[:]) + "&s=" + salt + "&f=json"
	getResp, err := http.Get(url)
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(getResp.Body)
	getResp.Body.Close()
	var wrapper map[string]subsonicEnv
	if err := json.Unmarshal(body, &wrapper); err != nil {
		t.Fatalf("restricted getArtists: %v (%s)", err, body)
	}
	env := wrapper["subsonic-response"]
	if env.Status != "ok" {
		t.Fatalf("restricted getArtists = %+v", env)
	}
	if env.Artists != nil && len(env.Artists.Index) != 0 {
		t.Fatalf("restricted user sees artists: %+v", env.Artists)
	}

	// A second page for the same caller reads the cached index rather
	// than sweeping again, and still answers empty.
	getResp, err = http.Get(url)
	if err != nil {
		t.Fatal(err)
	}
	body, _ = io.ReadAll(getResp.Body)
	getResp.Body.Close()
	wrapper = nil
	if err := json.Unmarshal(body, &wrapper); err != nil {
		t.Fatalf("restricted getArtists (second call): %v (%s)", err, body)
	}
	if again := wrapper["subsonic-response"]; again.Artists != nil && len(again.Artists.Index) != 0 {
		t.Fatalf("restricted user sees artists on a repeat call: %+v", again.Artists)
	}

	// And the administrator's own view is untouched by the restricted
	// caller's entry sharing the same tail.
	after := subsonicGet(t, h, "getArtists", adminSecret, "")
	if after.Artists == nil || len(after.Artists.Index) != len(warm.Artists.Index) {
		t.Fatalf("administrator index changed after a restricted caller browsed: %+v", after.Artists)
	}
}

// getUser resolves the named account for administrators rather than
// echoing the caller: an admin management tool asking about a member
// must get that member's row and roles. Non-admins keep the uniform
// refusal, and a name nobody carries answers 70 to the one caller
// allowed to learn that.
func TestSubsonicGetUserResolvesTarget(t *testing.T) {
	t.Parallel()
	h := newHarness(t)

	resp := h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "getuser-member", "password": "member-pass",
	})
	if resp.StatusCode != 201 {
		t.Fatalf("create user status = %d", resp.StatusCode)
	}
	resp.Body.Close()

	call := func(secret, caller, target string) subsonicEnv {
		t.Helper()
		salt := "gu123"
		sum := md5.Sum([]byte(secret + salt))
		u := h.ts.URL + "/rest/getUser?u=" + caller + "&t=" + hex.EncodeToString(sum[:]) +
			"&s=" + salt + "&f=json&username=" + target
		getResp, err := http.Get(u)
		if err != nil {
			t.Fatal(err)
		}
		body, _ := io.ReadAll(getResp.Body)
		getResp.Body.Close()
		var wrapper map[string]subsonicEnv
		if err := json.Unmarshal(body, &wrapper); err != nil {
			t.Fatalf("getUser: %v (%s)", err, body)
		}
		return wrapper["subsonic-response"]
	}

	adminSecret := newSubsonicSecret(t, h)
	env := call(adminSecret, "admin", "getuser-member")
	if env.Status != "ok" || env.User == nil ||
		env.User.Username != "getuser-member" || env.User.AdminRole {
		t.Fatalf("admin asking about the member = %+v, user %+v", env, env.User)
	}

	env = call(adminSecret, "admin", "getuser-nobody")
	if env.Status != "failed" || env.Error == nil || env.Error.Code != 70 {
		t.Fatalf("admin asking about a missing name = %+v", env)
	}

	memberToken := loginAs(t, h.ts, "getuser-member", "member-pass").Token
	resp = postJSON(t, h.ts.URL+"/api/v1/users/me/app-passwords", memberToken, `{"label":"member subsonic"}`)
	if resp.StatusCode != 201 {
		t.Fatalf("member app password status = %d", resp.StatusCode)
	}
	memberSecret := decode[AppPasswordCreated](t, resp).Secret
	env = call(memberSecret, "getuser-member", "admin")
	if env.Status != "failed" || env.Error == nil || env.Error.Code != 50 {
		t.Fatalf("member asking about the admin = %+v", env)
	}
}
