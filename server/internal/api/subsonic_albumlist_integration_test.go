package api

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// albumListSpec is one tagged track of the album-list fixture.
func albumListSpec(name, title, artist, album, date, genre string) fixtures.Spec {
	tags := map[string]string{"TITLE": title, "ARTIST": artist, "ALBUM": album, "GENRE": genre}
	if date != "" {
		tags["DATE"] = date
	}
	return fixtures.Spec{Name: name, Codec: fixtures.CodecFLAC, Duration: time.Second, Tags: tags}
}

// albumListHarness is the demo album plus four tagged ones, each scanned
// in on its own so the order they were added in is known, and is neither
// the order of their names nor of their years: Mid Record (2010), Old
// Record (1999), New Record (2024), then Zenith Record (1985).
func albumListHarness(t *testing.T) (*harness, string) {
	t.Helper()
	dir := t.TempDir()
	h := newHarness(t, service.Root{Name: "albums", Path: dir})
	for _, album := range [][]fixtures.Spec{
		{albumListSpec("mid1", "Mid One", "Mid Band", "Mid Record", "2010", "Pop")},
		{
			albumListSpec("old1", "Old One", "Old Band", "Old Record", "1999", "Rock"),
			albumListSpec("old2", "Old Two", "Old Band", "Old Record", "1999", "Jazz"),
			albumListSpec("old3", "Old Three", "Old Band", "Old Record", "1999", "Rock"),
		},
		{
			albumListSpec("new1", "New One", "New Band", "New Record", "2024", "Pop"),
			albumListSpec("new2", "New Two", "New Band", "New Record", "2024", "Pop"),
		},
		{albumListSpec("late1", "Late One", "Late Band", "Zenith Record", "1985", "Soul")},
	} {
		if _, err := fixtures.Generate(dir, album...); err != nil {
			t.Fatal(err)
		}
		h.rescanAndWait(t)
	}
	return h, newSubsonicSecret(t, h)
}

// postListenAt records one finished listen of pid at a chosen time.
func postListenAt(t *testing.T, h *harness, sessionID, pid string, at time.Time) {
	t.Helper()
	raw, _ := json.Marshal(map[string]any{"sessions": []map[string]any{{
		"sessionId": sessionID, "pid": pid, "startedAt": at.UTC().Format(time.RFC3339),
		"msPlayed": 1000, "finished": true,
	}}})
	req, _ := http.NewRequest("POST", h.ts.URL+"/api/v1/listens", bytes.NewReader(raw))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+h.token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 200 {
		t.Fatalf("listen status = %d", resp.StatusCode)
	}
}

// albumListNames lists one getAlbumList2 request's album names, and the
// albums by name.
func albumListNames(t *testing.T, h *harness, secret, extra string) ([]string, map[string]map[string]any) {
	t.Helper()
	env := mustOK(t, h, secret, "test", "getAlbumList2", extra)
	var names []string
	byName := map[string]map[string]any{}
	for _, a := range jlist(jmap(env["albumList2"])["album"]) {
		name, _ := jmap(a)["name"].(string)
		names = append(names, name)
		byName[name] = jmap(a)
	}
	return names, byName
}

func songsByTitle(env map[string]any, key string) map[string]map[string]any {
	out := map[string]map[string]any{}
	for _, s := range jlist(jmap(env[key])["song"]) {
		title, _ := jmap(s)["title"].(string)
		out[title] = jmap(s)
	}
	return out
}

// The seeded state the list and mark assertions read. Mid One is played
// three times, Old Record's three tracks four times between them (Old Two
// twice), and New One once, last: so Old Record has the most plays and
// Mid Record the most played track. Old Record is starred, Mid Record
// rated 80, and New Two starred.
type albumListState struct {
	albums map[string]map[string]any
	songs  map[string]string // title to pid
}

func seedAlbumListState(t *testing.T, h *harness, secret string) albumListState {
	t.Helper()
	_, albums := albumListNames(t, h, secret, "&type=alphabeticalByName&size=50")
	st := albumListState{albums: albums, songs: map[string]string{}}
	for _, name := range []string{"Old Record", "Mid Record", "New Record", "Zenith Record"} {
		id, _ := albums[name]["id"].(string)
		if !strings.HasPrefix(id, "al-") {
			t.Fatalf("%s id = %q, want a catalog album", name, id)
		}
		env := mustOK(t, h, secret, "test", "getAlbum", "&id="+url.QueryEscape(id))
		for title, s := range songsByTitle(env, "album") {
			st.songs[title], _ = s["id"].(string)
		}
	}
	now := time.Now()
	for i, play := range []struct {
		title string
		ago   time.Duration
	}{
		{"Mid One", 5 * time.Hour}, {"Mid One", 4 * time.Hour}, {"Mid One", 3 * time.Hour},
		{"Old Two", 170 * time.Minute}, {"Old Two", 165 * time.Minute},
		{"Old One", 160 * time.Minute}, {"Old Three", 140 * time.Minute},
		{"New One", 10 * time.Minute},
	} {
		postListenAt(t, h, fmt.Sprintf("seed-%d", i), st.songs[play.title], now.Add(-play.ago))
	}
	wantStatus(t, h.putJSON(t, "/api/v1/albums/"+st.id("Old Record")+"/star", map[string]any{"starred": true}), 200, "star Old Record")
	wantStatus(t, h.putJSON(t, "/api/v1/albums/"+st.id("Mid Record")+"/rating", map[string]any{"rating": 80}), 200, "rate Mid Record")
	wantStatus(t, h.putJSON(t, "/api/v1/items/"+st.songs["New Two"]+"/star", map[string]any{"starred": true}), 200, "star New Two")
	return st
}

// recentStamp reports whether v is an RFC 3339 time within a day of now,
// which a time read in the wrong unit is not.
func recentStamp(v any) bool {
	s, ok := v.(string)
	if !ok {
		return false
	}
	at, err := time.Parse(time.RFC3339, s)
	return err == nil && time.Since(at) < 24*time.Hour && time.Until(at) < time.Hour
}

func (st albumListState) id(name string) string {
	id, _ := st.albums[name]["id"].(string)
	return id
}

func TestSubsonicAlbumListTypes(t *testing.T) {
	t.Parallel()
	h, secret := albumListHarness(t)
	seedAlbumListState(t, h, secret)

	alphabetical, _ := albumListNames(t, h, secret, "&type=alphabeticalByName&size=50")
	if got := strings.Join(alphabetical, ", "); got != "Fixture Album, Mid Record, New Record, Old Record, Zenith Record" {
		t.Fatalf("alphabeticalByName = [%s]", got)
	}
	for _, tc := range []struct{ query, want string }{
		{"&type=recent&size=10", "New Record, Old Record, Mid Record"},
		// Summed plays: Old Record's 4 over Mid Record's 3, though Mid One
		// is the most played track.
		{"&type=frequent&size=10", "Old Record, Mid Record, New Record"},
		{"&type=starred&size=10", "Old Record"},
		{"&type=highest&size=10", "Mid Record"},
		// The order they were added in, never their release years.
		{"&type=newest&size=10", "Zenith Record, New Record, Old Record, Mid Record, Fixture Album"},
		{"&type=newest&size=2&offset=2", "Old Record, Mid Record"},
		{"&type=byYear&fromYear=2000&toYear=2024", "Mid Record, New Record"},
		{"&type=byYear&fromYear=2026&toYear=0&size=10", "New Record, Mid Record, Old Record, Zenith Record, Fixture Album"},
		{"&type=byGenre&genre=Jazz", "Old Record"},
		{"&type=alphabeticalByArtist&size=50", "Fixture Album, Zenith Record, Mid Record, New Record, Old Record"},
		{"&type=recent&size=1&offset=1", "Old Record"},
		{"&type=newest&offset=999999", ""},
	} {
		got, _ := albumListNames(t, h, secret, tc.query)
		if strings.Join(got, ", ") != tc.want {
			t.Errorf("getAlbumList2%s = [%s], want [%s]", tc.query, strings.Join(got, ", "), tc.want)
		}
	}
	// The folder-mode twin answers the same lists.
	env := mustOK(t, h, secret, "test", "getAlbumList", "&type=frequent&size=10")
	var folderMode []string
	for _, a := range jlist(jmap(env["albumList"])["album"]) {
		title, _ := jmap(a)["title"].(string)
		folderMode = append(folderMode, title)
	}
	if strings.Join(folderMode, ", ") != "Old Record, Mid Record, New Record" {
		t.Errorf("getAlbumList frequent = [%s]", strings.Join(folderMode, ", "))
	}

	for _, extra := range []string{"", "&type=mostPopular", "&type=byYear&fromYear=2000", "&type=byGenre"} {
		env := clientCall(t, h, secret, "test", "getAlbumList2", extra)
		if env["status"] != "failed" || jmap(env["error"])["code"] != float64(10) {
			t.Errorf("getAlbumList2%s = %v, want error 10", extra, env)
		}
	}

	// Another account has played and marked nothing.
	other := otherSubsonicAccount(t, h, "albums-other")
	for _, typ := range []string{"recent", "frequent", "starred", "highest"} {
		env := clientCallAs(t, h, other, "getAlbumList2", "&type="+typ)
		if n := len(jlist(jmap(env["albumList2"])["album"])); env["status"] != "ok" || n != 0 {
			t.Errorf("another account's %s = %v, want an empty list", typ, env)
		}
	}
}

func TestSubsonicMarksOnEveryShape(t *testing.T) {
	t.Parallel()
	h, secret := albumListHarness(t)
	st := seedAlbumListState(t, h, secret)

	// While the first account's marks stand, another account reads none of
	// them on any shape.
	other := otherSubsonicAccount(t, h, "marks-other")
	noMarks := func(where string, m map[string]any) {
		t.Helper()
		for _, key := range []string{"starred", "userRating", "playCount", "played"} {
			if m[key] != nil {
				t.Errorf("another account's %s carries %s = %v", where, key, m[key])
			}
		}
	}
	env := clientCallAs(t, h, other, "getAlbumList2", "&type=alphabeticalByName&size=50")
	for _, a := range jlist(jmap(env["albumList2"])["album"]) {
		noMarks(fmt.Sprint(jmap(a)["name"]), jmap(a))
	}
	for _, name := range []string{"Old Record", "Mid Record"} {
		env = clientCallAs(t, h, other, "getAlbum", "&id="+url.QueryEscape(st.id(name)))
		noMarks(name, jmap(env["album"]))
		for _, s := range jlist(jmap(env["album"])["song"]) {
			noMarks(fmt.Sprint(jmap(s)["title"]), jmap(s))
		}
	}
	env = clientCallAs(t, h, other, "getSong", "&id="+st.songs["New Two"])
	noMarks("New Two", jmap(env["song"]))
	env = clientCallAs(t, h, other, "getStarred2", "")
	if s2 := jmap(env["starred2"]); len(jlist(s2["album"])) != 0 || len(jlist(s2["song"])) != 0 {
		t.Errorf("another account's getStarred2 = %v, want empty", s2)
	}

	_, albums := albumListNames(t, h, secret, "&type=alphabeticalByName&size=50")
	if a := albums["Old Record"]; !recentStamp(a["starred"]) || a["userRating"] != nil || a["playCount"] != float64(4) {
		t.Errorf("Old Record = %v, want starred today, unrated, four plays", a)
	}
	if a := albums["Mid Record"]; a["userRating"] != float64(4) || a["starred"] != nil || a["playCount"] != float64(3) || !recentStamp(a["played"]) {
		t.Errorf("Mid Record = %v, want rating 4, three plays and a last play today", a)
	}
	for _, name := range []string{"Zenith Record", "Fixture Album"} {
		if a := albums[name]; a["starred"] != nil || a["userRating"] != nil || a["playCount"] != nil {
			t.Errorf("%s = %v, want no marks", name, a)
		}
	}

	env = mustOK(t, h, secret, "test", "getAlbum", "&id="+url.QueryEscape(st.id("Mid Record")))
	if a := jmap(env["album"]); a["userRating"] != float64(4) {
		t.Errorf("getAlbum Mid Record = %v, want rating 4", a)
	}
	if s := songsByTitle(env, "album")["Mid One"]; s["playCount"] != float64(3) || !recentStamp(s["played"]) || s["starred"] != nil {
		t.Errorf("Mid One = %v, want three plays today and no star", s)
	}
	env = mustOK(t, h, secret, "test", "getSong", "&id="+st.songs["New Two"])
	if s := jmap(env["song"]); !recentStamp(s["starred"]) || s["playCount"] != nil {
		t.Errorf("getSong New Two = %v, want starred today and unplayed", s)
	}
	env = mustOK(t, h, secret, "test", "getArtist", "&id="+url.QueryEscape(fmt.Sprint(st.albums["Old Record"]["artistId"])))
	if a := jlist(jmap(env["artist"])["album"]); len(a) != 1 || jmap(a[0])["starred"] == nil {
		t.Errorf("getArtist Old Band albums = %v, want Old Record starred", a)
	}
	env = mustOK(t, h, secret, "test", "getStarred2", "")
	s2 := jmap(env["starred2"])
	if a := jlist(s2["album"]); len(a) != 1 || jmap(a[0])["name"] != "Old Record" || jmap(a[0])["starred"] == nil {
		t.Errorf("getStarred2 albums = %v, want Old Record with its star time", a)
	}
	if s := jlist(s2["song"]); len(s) != 1 || jmap(s[0])["id"] != st.songs["New Two"] || jmap(s[0])["starred"] == nil {
		t.Errorf("getStarred2 songs = %v, want New Two with its star time", s)
	}
	env = mustOK(t, h, secret, "test", "search3", "&query=Record&songCount=50")
	for _, a := range jlist(jmap(env["searchResult3"])["album"]) {
		m := jmap(a)
		starred := m["starred"] != nil
		if starred != (m["name"] == "Old Record") || (m["userRating"] != nil) != (m["name"] == "Mid Record") {
			t.Errorf("search3 album %v carries the wrong marks", m)
		}
	}

	// Clearing them over the protocol clears them everywhere.
	mustOK(t, h, secret, "test", "setRating", "&id="+url.QueryEscape(st.id("Mid Record"))+"&rating=0")
	mustOK(t, h, secret, "test", "unstar", "&albumId="+url.QueryEscape(st.id("Old Record")))
	mustOK(t, h, secret, "test", "unstar", "&id="+st.songs["New Two"])
	_, albums = albumListNames(t, h, secret, "&type=alphabeticalByName&size=50")
	for name, a := range albums {
		if a["starred"] != nil || a["userRating"] != nil {
			t.Errorf("%s after clearing = %v", name, a)
		}
	}
	if got, _ := albumListNames(t, h, secret, "&type=highest"); len(got) != 0 {
		t.Errorf("highest after clearing the only rating = %v", got)
	}
}

// AlbumID3's created is required; it is when the album's first file
// arrived, on every shape an album renders as.
func TestSubsonicAlbumCreated(t *testing.T) {
	t.Parallel()
	h, secret := albumListHarness(t)
	_, albums := albumListNames(t, h, secret, "&type=alphabeticalByName&size=50")
	for name, a := range albums {
		if !recentStamp(a["created"]) {
			t.Errorf("getAlbumList2 %s created = %v, want an RFC 3339 time from today", name, a["created"])
		}
	}
	id, _ := albums["Mid Record"]["id"].(string)
	env := mustOK(t, h, secret, "test", "getAlbum", "&id="+url.QueryEscape(id))
	if a := jmap(env["album"]); !recentStamp(a["created"]) {
		t.Errorf("getAlbum = %v, want created today", a)
	}
	for _, s := range jlist(jmap(env["album"])["song"]) {
		if m := jmap(s); !recentStamp(m["created"]) || m["size"] == nil || m["bitRate"] == nil {
			t.Errorf("song %v, want created today, size and bitRate", m)
		}
	}
	env = mustOK(t, h, secret, "test", "getArtist", "&id="+url.QueryEscape(fmt.Sprint(albums["Mid Record"]["artistId"])))
	for _, a := range jlist(jmap(env["artist"])["album"]) {
		if !recentStamp(jmap(a)["created"]) {
			t.Errorf("getArtist album %v, want created today", a)
		}
	}
}

// subsonicAccount is a second account's app password, for asserting that
// one account's state stays its own.
type subsonicAccount struct{ username, secret string }

func otherSubsonicAccount(t *testing.T, h *harness, username string) subsonicAccount {
	t.Helper()
	return subsonicAccountWithGrants(t, h, username)
}

// subsonicAccountWithGrants creates an account granted the libraries
// named (every library when none is), and answers its app password.
func subsonicAccountWithGrants(t *testing.T, h *harness, username string, libraryNames ...string) subsonicAccount {
	t.Helper()
	body := map[string]any{"username": username, "password": username + "-pass"}
	if len(libraryNames) > 0 {
		var pids []string
		for _, l := range decode[Libraries](t, get(t, h.ts, "/api/v1/libraries", h.token)).Libraries {
			if slices.Contains(libraryNames, l.Name) {
				pids = append(pids, l.Pid)
			}
		}
		if len(pids) != len(libraryNames) {
			t.Fatalf("libraries %v: found %v", libraryNames, pids)
		}
		body["libraryAccess"] = map[string]any{"mode": "granted", "libraryPids": pids}
	}
	resp := h.postJSON(t, "/api/v1/users", body)
	if resp.StatusCode != 201 {
		t.Fatalf("create %s status = %d", username, resp.StatusCode)
	}
	resp.Body.Close()
	token := loginAs(t, h.ts, username, username+"-pass").Token
	resp = postJSON(t, h.ts.URL+"/api/v1/users/me/app-passwords", token, `{"label":"subsonic"}`)
	if resp.StatusCode != 201 {
		t.Fatalf("%s app password status = %d", username, resp.StatusCode)
	}
	return subsonicAccount{username: username, secret: decode[AppPasswordCreated](t, resp).Secret}
}

// clientCallAs is clientCall over apiKey auth as another account.
func clientCallAs(t *testing.T, h *harness, who subsonicAccount, view, extra string) map[string]any {
	t.Helper()
	resp, err := http.Get(h.ts.URL + "/rest/" + view + "?apiKey=" + who.secret + "&v=1.16.1&c=test&f=json" + extra)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	var wrapper map[string]map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&wrapper); err != nil {
		t.Fatalf("%s as %s: %v", view, who.username, err)
	}
	return wrapper["subsonic-response"]
}
