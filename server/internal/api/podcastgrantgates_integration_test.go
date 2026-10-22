package api

import (
	"encoding/json"
	"net/http"
	"net/url"
	"strings"
	"testing"
)

// The doors that read a show or an episode's documents hold the podcast
// grant as the listings do: an account granted other libraries only,
// though it followed the show while it could, is not sent the show by
// the sync snapshot, and is answered not-found by the show's detail and
// by both transcript doors, the capture of one already indexed included.
func TestTheShowAndTranscriptDoorsHoldThePodcastGrant(t *testing.T) {
	t.Parallel()
	g := newPodcastGrants(t)
	formerID, former := g.account(t, "former", g.musicLib, g.podcastLib)
	wantStatus(t, reqAs(t, g.h, http.MethodPost, "/api/v1/podcasts", former, map[string]any{"url": g.feedURL(t)}), 201, "subscribing while granted")
	transcript := "/api/v1/episodes/" + g.unfetched + "/transcript"
	snapshot := func() string {
		t.Helper()
		code, body := g.status(t, http.MethodGet, "/api/v1/sync/catalog?limit=500", former, nil)
		if code != 200 {
			t.Fatalf("the snapshot = %d: %s", code, body)
		}
		for last := body; ; {
			var page CatalogSyncPage
			if err := json.Unmarshal([]byte(last), &page); err != nil {
				t.Fatal(err)
			}
			if page.NextCursor == nil {
				return body
			}
			_, last = g.status(t, http.MethodGet, "/api/v1/sync/catalog?limit=500&cursor="+url.QueryEscape(*page.NextCursor), former, nil)
			body += last
		}
	}
	if !strings.Contains(snapshot(), `"`+g.show+`"`) {
		t.Fatal("the granted follower's snapshot does not send the show")
	}
	if code, body := g.status(t, http.MethodGet, transcript, former, nil); code != 200 {
		t.Fatalf("the transcript while granted = %d: %s", code, body)
	}
	// Indexed now, so a capture asked again has nothing to fetch and is
	// answered by its own door alone.
	if code, body := g.status(t, http.MethodPost, transcript, former, nil); code != http.StatusNoContent {
		t.Fatalf("the capture while granted = %d: %s", code, body)
	}
	resp := g.h.patchJSON(t, "/api/v1/users/"+formerID, map[string]any{
		"libraryAccess": map[string]any{"mode": "granted", "libraryPids": []string{g.musicLib}},
	})
	resp.Body.Close()

	if body := snapshot(); strings.Contains(body, `"`+g.show+`"`) {
		t.Errorf("the snapshot without the podcast grant sends the show: %.300s", body)
	}
	for _, door := range []struct{ method, path string }{
		{http.MethodGet, "/api/v1/podcasts/" + g.show},
		{http.MethodGet, transcript},
		{http.MethodPost, transcript},
	} {
		if code, body := g.status(t, door.method, door.path, former, nil); code != http.StatusNotFound {
			t.Errorf("%s %s without the podcast grant = %d: %s, want 404", door.method, door.path, code, body)
		}
	}
}
