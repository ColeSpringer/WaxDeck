package api

import (
	"io"
	"net/http"
	"strings"
	"testing"
)

// A podcast library's episodes come from their feeds and the matching
// engine never scores them, so the library takes no matching behavior;
// the music library beside it still does.
func TestThePodcastLibraryTakesNoMatchingBehavior(t *testing.T) {
	t.Parallel()
	g := newPodcastGrants(t)
	put := func(lib string) (int, string) {
		t.Helper()
		resp := reqAs(t, g.h, http.MethodPut, "/api/v1/libraries/"+lib+"/matching", g.h.token,
			map[string]any{"mode": "off", "singlesAutoApply": true})
		defer resp.Body.Close()
		body, err := io.ReadAll(resp.Body)
		if err != nil {
			t.Fatal(err)
		}
		return resp.StatusCode, string(body)
	}

	if code, body := put(g.podcastLib); code != http.StatusBadRequest || !strings.Contains(body, `"invalid-request"`) ||
		!strings.Contains(body, "feeds") {
		t.Errorf("setting the podcast library's matching = %d: %s, want a refusal that says why", code, body)
	}
	if got := decode[LibraryMatching](t, get(t, g.h.ts, "/api/v1/libraries/"+g.podcastLib+"/matching", g.h.token)); got.Mode != "auto" || got.SinglesAutoApply {
		t.Errorf("the podcast library's matching after the refusal = %+v, want the untouched default", got)
	}
	if code, body := put(g.musicLib); code != http.StatusOK {
		t.Errorf("setting the music library's matching = %d: %s", code, body)
	}
}
