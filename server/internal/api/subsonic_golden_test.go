package api

import (
	"bytes"
	"crypto/md5"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"testing"

	"github.com/colespringer/waxdeck/fixtures"
)

// The golden suite pins the Subsonic adapter's exact wire output, XML
// and JSON, over a deterministic fixture setup. Volatile content is
// normalized before comparison: ULIDs become ULID_n in first-seen
// order per document, RFC 3339 timestamps become TS, and the
// serverVersion attribute becomes VERSION. Regenerate the files with
// UPDATE_GOLDEN=1 go test -run TestSubsonicGolden ./internal/api/.
var (
	goldenULID    = regexp.MustCompile(`[0-9A-HJKMNP-TV-Z]{26}`)
	goldenTS      = regexp.MustCompile(`\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})`)
	goldenVerXML  = regexp.MustCompile(`serverVersion="[^"]*"`)
	goldenVerJSON = regexp.MustCompile(`"serverVersion":"[^"]*"`)
	goldenLMXML   = regexp.MustCompile(`lastModified="\d+"`)
	goldenLMJSON  = regexp.MustCompile(`"lastModified":\d+`)
)

func normalizeSubsonic(body []byte) []byte {
	s := goldenTS.ReplaceAllString(string(body), "TS")
	s = goldenVerXML.ReplaceAllString(s, `serverVersion="VERSION"`)
	s = goldenVerJSON.ReplaceAllString(s, `"serverVersion":"VERSION"`)
	s = goldenLMXML.ReplaceAllString(s, `lastModified="LM"`)
	s = goldenLMJSON.ReplaceAllString(s, `"lastModified":"LM"`)
	seen := map[string]string{}
	n := 0
	s = goldenULID.ReplaceAllStringFunc(s, func(m string) string {
		if p, ok := seen[m]; ok {
			return p
		}
		n++
		p := fmt.Sprintf("ULID_%d", n)
		seen[m] = p
		return p
	})
	return []byte(s)
}

// subsonicGoldenBody fetches one /rest view's raw response in the
// requested format ("xml" is the protocol default, "json" rides f=).
func subsonicGoldenBody(t *testing.T, h *harness, view, secret, extra, format string) []byte {
	t.Helper()
	salt := "goldsalt"
	sum := md5.Sum([]byte(secret + salt))
	q := "?u=admin&t=" + hex.EncodeToString(sum[:]) + "&s=" + salt + "&v=1.16.1&c=golden" + extra
	if format == "json" {
		q += "&f=json"
	}
	resp, err := http.Get(h.ts.URL + "/rest/" + view + q)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != 200 {
		t.Fatalf("%s (%s) status = %d: %s", view, format, resp.StatusCode, body)
	}
	return body
}

func TestSubsonicGolden(t *testing.T) {
	h := newHarness(t)

	// A multi-part audiobook joins the demo album so the bookmark
	// surface has spoken-word content to report.
	if _, err := fixtures.GenerateBook(h.library); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	secret := newSubsonicSecret(t, h)

	music := h.items(t, "?mediaType=music")
	if len(music.Items) != 4 {
		t.Fatalf("music items = %d, want 4", len(music.Items))
	}
	alpha := music.Items[0]
	books := h.items(t, "?mediaType=audiobook")
	if len(books.Items) != 1 {
		t.Fatalf("audiobook items = %d, want 1", len(books.Items))
	}
	book := books.Items[0]

	// Deterministic state: one star, one playlist over the whole album
	// in title order, one radio station, one spoken-word resume point.
	resp := h.putJSON(t, "/api/v1/items/"+alpha.Pid+"/star", map[string]any{"starred": true})
	if resp.StatusCode != 200 {
		t.Fatalf("star status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	var pids []string
	for _, it := range music.Items {
		pids = append(pids, it.Pid)
	}
	resp = h.postJSON(t, "/api/v1/playlists", map[string]any{
		"name": "Golden Static", "kind": "static", "itemPids": pids,
	})
	if resp.StatusCode != 201 {
		t.Fatalf("playlist create status = %d", resp.StatusCode)
	}
	pl := decode[Playlist](t, resp)
	resp = h.postJSON(t, "/api/v1/radio/stations", map[string]any{
		"name": "Golden FM", "streamUrl": "http://198.51.100.9/stream", "homepageUrl": "https://golden.example",
	})
	if resp.StatusCode != 201 {
		t.Fatalf("station create status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	// The bookmark surface lists spoken-word items with a saved resume
	// position; a single mid-book checkpoint is the normal state it
	// exists for.
	resp = h.putJSON(t, "/api/v1/items/"+book.Pid+"/play-state", map[string]any{"positionMs": 1234})
	if resp.StatusCode != 200 && resp.StatusCode != 204 {
		t.Fatalf("book checkpoint status = %d", resp.StatusCode)
	}
	resp.Body.Close()

	artistID := "A!" + base64.RawURLEncoding.EncodeToString([]byte("Fixture Artist"))
	albumID := "L!" + base64.RawURLEncoding.EncodeToString([]byte("Fixture Artist\x1fFixture Album"))

	requests := []struct {
		name, view, extra string
	}{
		{"ping", "ping", ""},
		{"getLicense", "getLicense", ""},
		{"getMusicFolders", "getMusicFolders", ""},
		{"getArtists", "getArtists", ""},
		{"getArtist", "getArtist", "&id=" + url.QueryEscape(artistID)},
		{"getAlbum", "getAlbum", "&id=" + url.QueryEscape(albumID)},
		{"getSong", "getSong", "&id=" + alpha.Pid},
		{"getGenres", "getGenres", ""},
		{"search3", "search3", "&query=Alpha"},
		{"getPlaylists", "getPlaylists", ""},
		{"getPlaylist", "getPlaylist", "&id=" + pl.Pid},
		{"getInternetRadioStations", "getInternetRadioStations", ""},
		{"getStarred2", "getStarred2", ""},
		{"getBookmarks", "getBookmarks", ""},
		{"scrobbleUnknown", "scrobble", "&id=tr-01JZX5N8QW3F4V9T2B7KD3M9R6"},
		{"getOpenSubsonicExtensions", "getOpenSubsonicExtensions", ""},
		{"getIndexes", "getIndexes", ""},
		{"getMusicDirectoryArtist", "getMusicDirectory", "&id=" + url.QueryEscape(artistID)},
		{"getMusicDirectoryAlbum", "getMusicDirectory", "&id=" + url.QueryEscape(albumID)},
		{"getAlbumList", "getAlbumList", "&type=alphabeticalByName"},
		{"getStarred", "getStarred", ""},
		{"getScanStatus", "getScanStatus", ""},
		{"getArtistInfo2", "getArtistInfo2", "&id=" + url.QueryEscape(artistID)},
		{"getTopSongs", "getTopSongs", "&artist=" + url.QueryEscape("Fixture Artist")},
		{"getSongsByGenre", "getSongsByGenre", "&genre=Ambient"},
	}

	update := os.Getenv("UPDATE_GOLDEN") != ""
	dir := filepath.Join("testdata", "subsonic")
	if update {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	for _, req := range requests {
		for _, format := range []string{"json", "xml"} {
			body := subsonicGoldenBody(t, h, req.view, secret, req.extra, format)
			norm := normalizeSubsonic(body)
			path := filepath.Join(dir, req.name+"."+format)
			if update {
				if err := os.WriteFile(path, norm, 0o644); err != nil {
					t.Fatal(err)
				}
				continue
			}
			want, err := os.ReadFile(path)
			if err != nil {
				t.Fatalf("missing golden %s (regenerate with UPDATE_GOLDEN=1): %v", path, err)
			}
			if !bytes.Equal(norm, want) {
				t.Errorf("%s (%s) drifted from its golden.\n got: %s\nwant: %s", req.view, format, norm, want)
			}
		}
	}
}
