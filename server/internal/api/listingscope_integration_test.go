package api

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/colespringer/waxdeck/fixtures"
)

// An account that hides explicit content, following a show whose flagged
// episodes sort first, gets full listing pages: the advisory flags keep
// those episodes out of the page rather than cutting them from it
// afterwards, which left the head of the listing empty but for a cursor.
func TestListingPagesStayFullForAnAccountThatHidesExplicitContent(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	eps := make([]countsEpisode, 0, 10)
	for i := range 5 {
		eps = append(eps, countsEpisode{title: fmt.Sprintf("AAA flagged %d", i), explicit: true})
	}
	for i := range 5 {
		eps = append(eps, countsEpisode{title: fmt.Sprintf("AAB clean %d", i)})
	}
	feed := newCountsFeed(t, eps)
	kid := restrictedListener(t, h, "kid")
	resp := reqAs(t, h, http.MethodPost, "/api/v1/podcasts", kid, map[string]any{"url": feed.feedURL()})
	if resp.StatusCode != http.StatusCreated && resp.StatusCode != http.StatusOK {
		t.Fatalf("follow status = %d", resp.StatusCode)
	}
	resp.Body.Close()

	for _, path := range []string{
		"/api/v1/library/items?limit=3",
		"/api/v1/library/items?mediaType=podcast&limit=3",
		"/api/v1/library/browse?list=alphabetical&limit=3",
	} {
		page := decodeStatus[ItemPage](t, get(t, h.ts, path, kid), http.StatusOK, path)
		if len(page.Items) != 3 {
			t.Errorf("%s answered %d items (next %v), want three", path, len(page.Items), page.NextCursor)
		}
		for _, it := range page.Items {
			if strings.HasPrefix(it.Title, "AAA") {
				t.Errorf("%s offered %q, which the account hides", path, it.Title)
			}
		}
	}
}

// One account following a show whose episode titles sort first leaves
// every other account's listings full: the episodes it may not see are
// kept out of the page rather than cut from it afterwards, which left
// first pages empty but for a cursor.
func TestListingPagesStayFullWhenAnotherAccountFollowsAShow(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	feedDir := t.TempDir()
	host := httptest.NewServer(http.FileServer(http.Dir(feedDir)))
	t.Cleanup(host.Close)
	if _, err := fixtures.GeneratePresetFeeds(feedDir, host.URL); err != nil {
		t.Fatal(err)
	}
	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{
		"url": host.URL + "/" + fixtures.EarlyFeedDir + "/feed.xml",
	})
	wantStatus(t, resp, http.StatusCreated, "the admin follows the early feed")

	// The follower's own first item is one of those episodes, which is
	// what puts them ahead of everything else.
	first := h.items(t, "?limit=1")
	if len(first.Items) != 1 || first.Items[0].Title != "AAA Before Everything" {
		t.Fatalf("the follower's first item = %+v, want the early feed's first episode", first.Items)
	}

	var music string
	for _, lib := range decode[Libraries](t, get(t, h.ts, "/api/v1/libraries", h.token)).Libraries {
		if lib.Path != nil && *lib.Path == h.library {
			music = lib.Pid
		}
	}
	if music == "" {
		t.Fatal("no library at the music root")
	}
	resp = h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "music-only", "password": testPassword,
		"libraryAccess": map[string]any{"mode": "granted", "libraryPids": []string{music}},
	})
	wantStatus(t, resp, http.StatusCreated, "create the library-restricted account")
	_, nonFollower := listenerAccount(t, h, "non-follower", true)

	for name, token := range map[string]string{
		"an account that follows nothing": nonFollower,
		"a library-restricted account":    loginAs(t, h.ts, "music-only", testPassword).Token,
	} {
		for _, path := range []string{
			"/api/v1/library/items?limit=1",
			"/api/v1/library/browse?list=recently-added&limit=1",
		} {
			page := decodeStatus[ItemPage](t, get(t, h.ts, path, token), http.StatusOK, name+" "+path)
			if len(page.Items) != 1 {
				t.Errorf("%s: %s answered %d items (next %v), want one", name, path, len(page.Items), page.NextCursor)
				continue
			}
			if page.Items[0].MediaType == MediaTypePodcast {
				t.Errorf("%s: %s offered %q, an episode it does not follow", name, path, page.Items[0].Title)
			}
		}
	}
}
