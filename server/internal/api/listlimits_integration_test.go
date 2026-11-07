package api

import (
	"fmt"
	"strings"
	"testing"
)

// A list's limit keeps the contract's bounds: one outside [1, max] is
// refused with the bound, never answered with an empty page whose cursor
// names the page it came from, or with the whole list.
func TestListLimitsKeepTheirBounds(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	made := decodeStatus[Playlist](t, h.postJSON(t, "/api/v1/playlists", map[string]any{
		"name": "paged", "kind": "static",
	}), 201, "a playlist to page")
	rule := map[string]any{"root": map[string]any{"type": "condition", "field": "mediaType", "op": "is", "value": "music"}}
	for _, c := range []struct {
		method, path string
		max          int
		body         any
	}{
		{"GET", "/api/v1/playlists", 500, nil},
		{"GET", "/api/v1/playlists/" + made.Pid + "/items", 500, nil},
		{"POST", "/api/v1/playlists/preview", 200, rule},
		{"GET", "/api/v1/podcasts", 500, nil},
		{"GET", "/api/v1/podcasts/pc-01JZX5N8QW3F4V9T2B7KD3M9R6/episodes", 500, nil},
		{"GET", "/api/v1/podcasts/directory?query=x", 100, nil},
		{"GET", "/api/v1/radio/directory?query=x", 100, nil},
	} {
		sep := "?"
		if strings.Contains(c.path, "?") {
			sep = "&"
		}
		for _, limit := range []int{0, -1, c.max + 1} {
			path := fmt.Sprintf("%s%slimit=%d", c.path, sep, limit)
			e := decodeStatus[Error](t, reqAs(t, h, c.method, path, h.token, c.body), 400, c.method+" "+path)
			if want := fmt.Sprintf("limit must be between 1 and %d", c.max); e.Code != "invalid-request" || e.Message != want {
				t.Errorf("%s %s = %+v, want invalid-request %q", c.method, path, e, want)
			}
		}
	}
}
