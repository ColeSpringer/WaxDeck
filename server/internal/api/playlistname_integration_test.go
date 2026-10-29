package api

import (
	"net/url"
	"strings"
	"testing"
)

// Every door that names a playlist keeps the contract's 200-character
// bound: counted in characters, on the name as trimmed, and refused as
// invalid-request past it.
func TestPlaylistNamesKeepTheirBound(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	// Two bytes a character, so a count of bytes would refuse it.
	atBound := "  " + strings.Repeat(string(rune(0xe9)), 200) + "  "
	tooLong := strings.Repeat("n", 201)
	nsp := map[string]any{"all": []any{map[string]any{"contains": map[string]any{"title": "a"}}}}

	made := decodeStatus[Playlist](t, h.postJSON(t, "/api/v1/playlists", map[string]any{
		"name": atBound, "kind": "static",
	}), 201, "a name at the bound")
	if made.Name != strings.TrimSpace(atBound) {
		t.Fatalf("stored name = %q, want it trimmed", made.Name)
	}

	for _, c := range []struct {
		door, method, path string
		body               any
	}{
		{"create", "POST", "/api/v1/playlists", map[string]any{"name": tooLong, "kind": "static"}},
		{"rename", "PATCH", "/api/v1/playlists/" + made.Pid, map[string]any{"name": tooLong}},
		{"m3u import", "POST", "/api/v1/playlists/m3u", map[string]any{"name": tooLong, "content": "#EXTM3U\n"}},
		{"nsp import, named", "POST", "/api/v1/playlists/nsp?name=" + url.QueryEscape(tooLong), nsp},
		{"nsp import, by its document", "POST", "/api/v1/playlists/nsp",
			map[string]any{"name": tooLong, "all": nsp["all"]}},
		{"export import", "POST", "/api/v1/playlists/import",
			map[string]any{"source": "text", "name": tooLong, "payload": "Fixture Artist - Alpha Song"}},
		{"export import, by the export's own name", "POST", "/api/v1/playlists/import", map[string]any{
			"source":  "csv",
			"payload": "Playlist Name,Track Name,Artist Name\n" + tooLong + ",Alpha Song,Fixture Artist\n",
		}},
	} {
		e := decodeStatus[Error](t, reqAs(t, h, c.method, c.path, h.token, c.body), 400, c.door)
		if e.Code != "invalid-request" || !strings.Contains(e.Message, "200") {
			t.Errorf("%s = %+v, want invalid-request naming the bound", c.door, e)
		}
	}
	if got := decode[Playlist](t, get(t, h.ts, "/api/v1/playlists/"+made.Pid, h.token)); got.Name != made.Name {
		t.Fatalf("the refused rename changed the name to %q", got.Name)
	}
}
