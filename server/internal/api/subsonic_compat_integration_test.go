package api

import (
	"context"
	"crypto/md5"
	"encoding/hex"
	"encoding/json"
	"io"
	"net/http"
	"net/url"
	"strings"
	"testing"
	"time"
)

// rawSubsonic fetches one /rest URL as it is and answers the status, the
// content type and the body.
func rawSubsonic(t *testing.T, h *harness, path string) (int, string, string) {
	t.Helper()
	resp, err := http.Get(h.ts.URL + path)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	return resp.StatusCode, resp.Header.Get("Content-Type"), string(body)
}

func envelopeCode(t *testing.T, body string) int {
	t.Helper()
	var wrapper map[string]struct {
		Error *struct {
			Code int `json:"code"`
		} `json:"error"`
	}
	if err := json.Unmarshal([]byte(body), &wrapper); err != nil {
		t.Fatalf("%v (%s)", err, body)
	}
	if e := wrapper["subsonic-response"].Error; e != nil {
		return e.Code
	}
	return -1
}

// A cover that is not there is the protocol's error under HTTP 404, so an
// image element fires its error handler instead of drawing a broken
// picture; a client reading the body still finds code 70.
func TestSubsonicMissingCoverIs404(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	secret := newSubsonicSecret(t, h)
	song := subsonicSongID(t, h, secret, "Alpha")
	_, albums := albumListNames(t, h, secret, "&type=alphabeticalByName")
	album, _ := albums["Fixture Album"]["id"].(string)

	for _, id := range []string{song, album, "al-01JZX5N8QW3F4V9T2B7KD3M9R6", "nonsense"} {
		status, ct, body := rawSubsonic(t, h, "/rest/getCoverArt?apiKey="+secret+"&f=json&id="+url.QueryEscape(id))
		if status != http.StatusNotFound || ct != "application/json" || envelopeCode(t, body) != 70 {
			t.Errorf("cover %s (json) = %d %q %s, want 404 with error 70", id, status, ct, body)
		}
		status, ct, body = rawSubsonic(t, h, "/rest/getCoverArt?apiKey="+secret+"&id="+url.QueryEscape(id))
		if status != http.StatusNotFound || ct != "application/xml" || !strings.Contains(body, `<error code="70"`) {
			t.Errorf("cover %s (xml) = %d %q %s, want 404 with error 70", id, status, ct, body)
		}
	}
	if status, _, body := rawSubsonic(t, h, "/rest/getCoverArt?apiKey="+secret+"&f=json"); status != 200 || envelopeCode(t, body) != 10 {
		t.Errorf("a cover with no id = %d %s, want error 10", status, body)
	}
}

// The authentication errors the protocol names: a password where only
// tokens work is 42, two mechanisms at once 43, and tokenInfo answers
// whose key it is.
func TestSubsonicAuthenticationErrors(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	secret := newSubsonicSecret(t, h)
	sum := md5.Sum([]byte(secret + "s1"))
	token := "&t=" + hex.EncodeToString(sum[:]) + "&s=s1"
	for path, want := range map[string]int{
		"/rest/ping?u=admin&p=" + secret:           42,
		"/rest/ping?u=admin&p=" + secret + token:   43,
		"/rest/ping?apiKey=" + secret + "&u=admin": 43,
		"/rest/ping?apiKey=" + secret + token:      43,
		"/rest/ping?apiKey=wrong":                  44,
		"/rest/ping?u=admin&t=00&s=s1":             40,
		"/rest/ping?u=admin":                       10,
		"/rest/ping?u=admin" + token + "&v=1.16.1": -1,
	} {
		_, _, body := rawSubsonic(t, h, path+"&f=json")
		if got := envelopeCode(t, body); got != want {
			t.Errorf("%s = %d (%s), want %d", path, got, body, want)
		}
	}
	env := clientCallAs(t, h, subsonicAccount{username: "admin", secret: secret}, "tokenInfo", "")
	if env["status"] != "ok" || jmap(env["tokenInfo"])["username"] != "admin" {
		t.Errorf("tokenInfo = %v, want the key's account", env)
	}
}

// getUser claims no role whose verbs this surface lacks: there is no
// share or podcast management here, so a client must not draw those
// controls.
func TestSubsonicUserClaimsOnlyHonouredRoles(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	secret := newSubsonicSecret(t, h)
	u := jmap(mustOK(t, h, secret, "test", "getUser", "&username=admin")["user"])
	if u["shareRole"] != false || u["podcastRole"] != false || u["streamRole"] != true || u["adminRole"] != true {
		t.Errorf("getUser = %v, want no share or podcast role", u)
	}
}

// A required parameter left out is error 10, whatever the view.
func TestSubsonicMissingParametersAreError10(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	secret := newSubsonicSecret(t, h)
	for _, view := range []string{
		"getSong", "getMusicDirectory", "getArtist", "getAlbum", "getPlaylist", "deletePlaylist",
		"getArtistInfo", "getArtistInfo2", "getTopSongs", "getSimilarSongs", "stream", "download",
		"updateInternetRadioStation", "deleteInternetRadioStation", "scrobble", "star", "setRating",
		"deleteBookmark", "createBookmark", "getSongsByGenre", "getAlbumList2", "getAlbumList",
	} {
		env := clientCall(t, h, secret, "test", view, "")
		if env["status"] != "failed" || jmap(env["error"])["code"] != float64(10) {
			t.Errorf("%s with no parameters = %v, want error 10", view, env)
		}
	}
}

// The format is any case; jsonp wraps the document in the callback
// named; and an empty list is [] in JSON, never null.
func TestSubsonicFormats(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	secret := newSubsonicSecret(t, h)
	for _, f := range []string{"JSON", "Json"} {
		status, ct, body := rawSubsonic(t, h, "/rest/ping?apiKey="+secret+"&f="+f)
		if status != 200 || ct != "application/json" || !strings.Contains(body, `"status":"ok"`) {
			t.Errorf("f=%s = %d %q %s", f, status, ct, body)
		}
	}
	status, ct, body := rawSubsonic(t, h, "/rest/getStarred2?apiKey="+secret+"&f=jsonp&callback=sub.cb")
	if status != 200 || ct != "application/javascript" || !strings.HasPrefix(body, "sub.cb({") || !strings.HasSuffix(body, "});") {
		t.Errorf("jsonp = %d %q %s", status, ct, body)
	}
	// A callback that is not a name is refused as plain JSON, its text
	// never echoed into the response.
	for _, callback := range []string{"&callback=" + url.QueryEscape("alert(1)//"), "&callback=", ""} {
		status, ct, body := rawSubsonic(t, h, "/rest/ping?apiKey="+secret+"&f=jsonp"+callback)
		if status != 200 || ct != "application/json" || envelopeCode(t, body) != 10 || strings.Contains(body, "alert") {
			t.Errorf("jsonp%s = %d %q %s, want error 10 as JSON", callback, status, ct, body)
		}
	}
	_, _, body = rawSubsonic(t, h, "/rest/getStarred2?apiKey="+secret+"&f=json")
	if strings.Contains(body, "null") || !strings.Contains(body, `"song":[]`) || !strings.Contains(body, `"album":[]`) {
		t.Errorf("empty getStarred2 = %s, want [] for each list", body)
	}
	_, _, body = rawSubsonic(t, h, "/rest/search3?apiKey="+secret+"&f=json&query=nothing-matches-this")
	if strings.Contains(body, "null") {
		t.Errorf("empty search3 = %s, want no null", body)
	}
}

// A genre counts the albums holding a track of it, and an artist's top
// songs are the caller's own most played of its tracks.
func TestSubsonicGenreAlbumsAndTopSongs(t *testing.T) {
	t.Parallel()
	h, secret := albumListHarness(t)
	seedAlbumListState(t, h, secret)

	counts := map[string][2]float64{}
	for _, g := range jlist(jmap(mustOK(t, h, secret, "test", "getGenres", "")["genres"])["genre"]) {
		m := jmap(g)
		counts[m["value"].(string)] = [2]float64{m["songCount"].(float64), m["albumCount"].(float64)}
	}
	for genre, want := range map[string][2]float64{"Pop": {3, 2}, "Rock": {2, 1}, "Jazz": {1, 1}, "Soul": {1, 1}} {
		if counts[genre] != want {
			t.Errorf("%s = %v songs/albums, want %v", genre, counts[genre], want)
		}
	}

	top := func(artist, extra string) string {
		var out []string
		for _, s := range jlist(jmap(mustOK(t, h, secret, "test", "getTopSongs", "&artist="+url.QueryEscape(artist)+extra)["topSongs"])["song"]) {
			out = append(out, jmap(s)["title"].(string))
		}
		return strings.Join(out, ", ")
	}
	// Old Two twice, then Old Three and Old One once each, the later play
	// first.
	if got := top("Old Band", ""); got != "Old Two, Old Three, Old One" {
		t.Errorf("Old Band top songs = [%s], want [Old Two, Old Three, Old One]", got)
	}
	if got := top("Old Band", "&count=1"); got != "Old Two" {
		t.Errorf("Old Band top song = [%s], want [Old Two]", got)
	}
	if got := top("new band", ""); got != "New One" {
		t.Errorf("New Band top songs = [%s], want the played New One alone", got)
	}
	if got := top("Zenith Band", ""); got != "" {
		t.Errorf("an artist with no plays = [%s], want none", got)
	}
	other := otherSubsonicAccount(t, h, "top-other")
	if s := jlist(jmap(clientCallAs(t, h, other, "getTopSongs", "&artist=Mid+Band")["topSongs"])["song"]); len(s) != 0 {
		t.Errorf("another account's top songs = %v, want its own (none)", s)
	}
}

// A capped encode a client names no format for lands in MP3, which every
// client decodes, whether the cap is the client's or the account's.
func TestSubsonicCappedStreamDefaultsToMP3(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	secret := newSubsonicSecret(t, h)
	song := subsonicSongID(t, h, secret, "Alpha") // a 2 s flac
	if q := redirectQuery(t, streamRedirect(t, h, "/rest/stream.view?apiKey="+secret+"&id="+song+"&maxBitRate=128")); q.Get("fmt") != "mp3" || q.Get("br") != "128" {
		t.Errorf("a client cap with no format = %v, want mp3 at 128", q)
	}

	_, token, _ := mediaListener(t, h, "capped", map[string]any{
		"download": true, "delete": false, "explicitContent": true, "sharedOutputs": true, "managePodcasts": true,
		"maxTranscodeKbps": 96,
	})
	resp := reqAs(t, h, "POST", "/api/v1/users/me/app-passwords", token, map[string]any{"label": "client"})
	capped := decode[AppPasswordCreated](t, resp).Secret
	q := redirectQuery(t, streamRedirect(t, h, "/rest/stream.view?apiKey="+capped+"&id="+song+"&timeOffset=1"))
	if q.Get("fmt") != "mp3" || q.Get("br") != "96" || q.Get("t") != "1" {
		t.Errorf("a capped account's cut = %v, want mp3 at the account's 96 from 1", q)
	}
}

// A client asks getIndexes whether anything changed by lastModified: a
// play changes nothing the index lists, so the answer stays put, and an
// edit to what it lists moves it.
func TestSubsonicIndexesLastModifiedMovesWithContentOnly(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	ctx := context.Background()
	secret := newSubsonicSecret(t, h)
	lastModified := func() float64 {
		t.Helper()
		lm, _ := jmap(mustOK(t, h, secret, "test", "getIndexes", "")["indexes"])["lastModified"].(float64)
		return lm
	}
	track := decode[ItemPage](t, get(t, h.ts, "/api/v1/library/items?limit=1", h.token)).Items[0].Pid
	// The answer is the content position only once the change feed has
	// read past the last row that changed content, and the feed's own
	// position until then. A star after the first look puts a row past
	// that one, so a position below the feed's is the content position.
	h.svc.CatalogContentSeq(ctx)
	mustOK(t, h, secret, "test", "star", "&id="+track)
	deadline := time.Now().Add(30 * time.Second)
	for feed := h.svc.CatalogTailSeq(); h.svc.CatalogContentSeq(ctx) >= feed; feed = h.svc.CatalogTailSeq() {
		if time.Now().After(deadline) {
			t.Fatal("the change feed never read past the catalog's last content change")
		}
		time.Sleep(5 * time.Millisecond)
	}
	before := lastModified()
	mustOK(t, h, secret, "test", "scrobble", "&id="+track+"&submission=true")
	if after := lastModified(); after != before {
		t.Errorf("lastModified after a play = %v, want %v as before it", after, before)
	}
	resp := h.patchJSON(t, "/api/v1/items/"+track+"/metadata", map[string]any{"fields": map[string]string{"title": "Retitled"}})
	wantStatus(t, resp, 200, "editing the track")
	for edited := lastModified(); edited <= before; edited = lastModified() {
		if time.Now().After(deadline) {
			t.Fatalf("lastModified after an edit = %v, want past %v", edited, before)
		}
		time.Sleep(5 * time.Millisecond)
	}
}
