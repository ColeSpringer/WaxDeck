package api

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"slices"
	"strconv"
	"strings"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/adapter/gpodder"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// podcastGrants is a server grown the way one does: the administrator
// subscribes to a show and fetches one of its two episodes, which is when
// the catalog creates its podcast library, and accounts are then granted
// libraries by pid.
type podcastGrants struct {
	h                    *harness
	show                 string
	fetched, unfetched   string
	musicLib, podcastLib string
}

func newPodcastGrants(t *testing.T) podcastGrants {
	t.Helper()
	return newPodcastGrantsWith(t, nil)
}

// newPodcastGrantsWith is newPodcastGrants on a service configuration the
// test adjusts first.
func newPodcastGrantsWith(t *testing.T, mutate func(*service.Config)) podcastGrants {
	t.Helper()
	h := newPodcastHarnessWith(t, mutate)
	feed := newFeedServer(t, 2)
	sub := decodeStatus[Subscription](t, h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()}), 201, "subscribe")
	eps := decode[EpisodePage](t, get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)).Items
	if len(eps) != 2 {
		t.Fatalf("episodes = %d, want 2", len(eps))
	}
	wantStatus(t, h.postJSON(t, "/api/v1/episodes/"+eps[0].Pid+"/fetch", nil), 202, "fetching one episode")
	drainFetches(t, h)
	g := podcastGrants{h: h, show: sub.Show.Pid, fetched: eps[0].Pid, unfetched: eps[1].Pid}
	for _, lib := range decode[Libraries](t, get(t, h.ts, "/api/v1/libraries", h.token)).Libraries {
		switch deref(lib.Media) {
		case "podcast":
			g.podcastLib = lib.Pid
		default:
			g.musicLib = lib.Pid
		}
	}
	if g.podcastLib == "" || g.musicLib == "" {
		t.Fatalf("libraries = music %q, podcast %q; want both listed for granting", g.musicLib, g.podcastLib)
	}
	return g
}

// feedURL answers the fixture show's feed URL.
func (g podcastGrants) feedURL(t *testing.T) string {
	t.Helper()
	return deref(decode[PodcastDetail](t, get(t, g.h.ts, "/api/v1/podcasts/"+g.show, g.h.token)).Show.FeedUrl)
}

// account creates an account granted exactly libs and answers its token.
func (g podcastGrants) account(t *testing.T, name string, libs ...string) (id, token string) {
	t.Helper()
	acct := decodeStatus[UserAccount](t, g.h.postJSON(t, "/api/v1/users", map[string]any{
		"username": name, "password": testPassword,
		"libraryAccess": map[string]any{"mode": "granted", "libraryPids": libs},
	}), 201, "creating "+name)
	return acct.Id, loginAs(t, g.h.ts, name, testPassword).Token
}

func (g podcastGrants) status(t *testing.T, method, path, token string, body any) (int, string) {
	t.Helper()
	resp := reqAs(t, g.h, method, path, token, body)
	raw, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	return resp.StatusCode, string(raw)
}

// listed answers which of the fixture's two episodes a listing names. A
// sync snapshot is read to its end: shows come first, items after.
func (g podcastGrants) listed(t *testing.T, path, token string) []string {
	t.Helper()
	code, body := g.status(t, http.MethodGet, path, token, nil)
	if code != 200 {
		t.Fatalf("%s = %d: %s", path, code, body)
	}
	for last := body; strings.HasPrefix(path, "/api/v1/sync/catalog"); {
		var page CatalogSyncPage
		if err := json.Unmarshal([]byte(last), &page); err != nil {
			t.Fatal(err)
		}
		if page.NextCursor == nil {
			break
		}
		_, last = g.status(t, http.MethodGet, path+"&cursor="+url.QueryEscape(*page.NextCursor), token, nil)
		body += last
	}
	var out []string
	for _, pid := range []string{g.fetched, g.unfetched} {
		if strings.Contains(body, `"`+pid+`"`) {
			out = append(out, pid)
		}
	}
	return out
}

// The podcast library is one more library to grant: an account granted
// it hears every episode, fetched or not, on every surface, and an
// account granted other libraries only hears none, even of a show it
// subscribed to while it could.
func TestEpisodesFollowThePodcastGrant(t *testing.T) {
	t.Parallel()
	g := newPodcastGrants(t)
	_, listener := g.account(t, "listener", g.musicLib, g.podcastLib)
	formerID, former := g.account(t, "former", g.musicLib, g.podcastLib)
	feedURL := g.feedURL(t)
	for _, token := range []string{listener, former} {
		if code, body := g.status(t, http.MethodPost, "/api/v1/podcasts", token, map[string]any{"url": feedURL}); code != 201 {
			t.Fatalf("subscribing while granted = %d: %s", code, body)
		}
	}
	resp := g.h.patchJSON(t, "/api/v1/users/"+formerID, map[string]any{
		"libraryAccess": map[string]any{"mode": "granted", "libraryPids": []string{g.musicLib}},
	})
	resp.Body.Close()
	both := []string{g.fetched, g.unfetched}

	listings := []string{
		"/api/v1/podcasts/" + g.show + "/episodes",
		"/api/v1/podcasts/episodes?filter=latest",
		"/api/v1/library/items?mediaType=podcast&limit=50",
		"/api/v1/library/browse?list=recently-added&mediaType=podcast&limit=50",
		"/api/v1/library/search?q=" + url.QueryEscape("Episode"),
		"/api/v1/sync/catalog?limit=500",
	}
	for _, path := range listings {
		if got := g.listed(t, path, listener); !slices.Equal(got, both) {
			t.Errorf("%s as the granted listener names %v, want both episodes", path, got)
		}
	}
	for _, path := range listings[1:] {
		if got := g.listed(t, path, former); len(got) != 0 {
			t.Errorf("%s without the podcast grant names %v, want none", path, got)
		}
	}
	if code, _ := g.status(t, http.MethodGet, listings[0], former, nil); code != 404 {
		t.Errorf("the show's episodes without the podcast grant = %d, want 404", code)
	}
	for token, want := range map[string]int{listener: 2, former: 0} {
		page := decode[FacetPage](t, reqAs(t, g.h, http.MethodGet, "/api/v1/library/facets?dimension=kind", token, nil))
		got := 0
		for _, b := range page.Buckets {
			if b.Key == "episode" {
				got = b.Count
			}
		}
		if got != want {
			t.Errorf("the kind facet counts %d episodes, want %d", got, want)
		}
	}

	for _, pid := range both {
		for _, path := range []string{"/api/v1/items/" + pid, "/api/v1/episodes/" + pid, "/api/v1/items/" + pid + "/play-info"} {
			if code, body := g.status(t, http.MethodGet, path, listener, nil); code != 200 {
				t.Errorf("%s as the granted listener = %d: %s", path, code, body)
			}
			if code, _ := g.status(t, http.MethodGet, path, former, nil); code != 404 {
				t.Errorf("%s without the podcast grant = %d, want 404", path, code)
			}
		}
		info := decode[PlayInfo](t, reqAs(t, g.h, http.MethodGet, "/api/v1/items/"+pid+"/play-info", listener, nil))
		if relayed := get(t, g.h.ts, info.Url, ""); relayed.StatusCode != 200 {
			t.Errorf("the granted listener's stream of %s = %d", pid, relayed.StatusCode)
		} else {
			relayed.Body.Close()
		}

		code, body := g.status(t, http.MethodPost, "/api/v1/shares", listener, map[string]any{"pid": pid})
		if code != 201 {
			t.Errorf("sharing %s as the granted listener = %d: %s", pid, code, body)
			continue
		}
		if code, _ := g.status(t, http.MethodPost, "/api/v1/shares", former, map[string]any{"pid": pid}); code != 404 {
			t.Errorf("sharing %s without the podcast grant = %d, want 404", pid, code)
		}
		var share Share
		if err := json.Unmarshal([]byte(body), &share); err != nil {
			t.Fatal(err)
		}
		page, err := http.Get(g.h.ts.URL + share.Url)
		if err != nil {
			t.Fatal(err)
		}
		html, _ := io.ReadAll(page.Body)
		page.Body.Close()
		if page.StatusCode != 200 || !strings.Contains(string(html), "<audio") {
			t.Errorf("the public page of %s = %d: %.200s", pid, page.StatusCode, html)
		}
		stream, err := http.Get(g.h.ts.URL + share.Url + "/stream?i=0")
		if err != nil {
			t.Fatal(err)
		}
		stream.Body.Close()
		if stream.StatusCode != 200 {
			t.Errorf("the public stream of %s = %d", pid, stream.StatusCode)
		}
	}
}

// Following a show is for hearing it, so an account that cannot see the
// podcast library is refused, in words that say what to ask for.
func TestSubscribingNeedsThePodcastLibrary(t *testing.T) {
	t.Parallel()
	g := newPodcastGrants(t)
	feedURL := g.feedURL(t)
	_, musicOnly := g.account(t, "music-only", g.musicLib)
	code, body := g.status(t, http.MethodPost, "/api/v1/podcasts", musicOnly, map[string]any{"url": feedURL})
	if code != http.StatusForbidden || !strings.Contains(body, `"forbidden"`) || !strings.Contains(body, "podcast library") {
		t.Errorf("subscribing without the podcast library = %d: %s", code, body)
	}
	if subs := decode[SubscriptionPage](t, reqAs(t, g.h, http.MethodGet, "/api/v1/podcasts", musicOnly, nil)); len(subs.Items) != 0 {
		t.Errorf("the refused account follows %d shows, want none", len(subs.Items))
	}
	_, listener := g.account(t, "listener", g.musicLib, g.podcastLib)
	if code, body := g.status(t, http.MethodPost, "/api/v1/podcasts", listener, map[string]any{"url": feedURL}); code != 201 {
		t.Errorf("subscribing with the podcast library = %d: %s", code, body)
	}
}

// gpodderReads is what one gpodder delta or episodes download answered.
type gpodderReads struct {
	Add, Remove []string
	Actions     []struct{ Podcast, Episode, Device string }
	Timestamp   int64
}

func readGpodder(t *testing.T, body string) gpodderReads {
	t.Helper()
	var out gpodderReads
	if err := json.Unmarshal([]byte(body), &out); err != nil {
		t.Fatalf("%v: %s", err, body)
	}
	return out
}

// An account whose podcast grant is withdrawn sees no subscriptions and
// changes none, on every door: the list, the OPML export, the Subsonic
// channels and the gpodder lists are empty, every write answers as for a
// show it cannot see, and the rows stay, so restoring the grant restores
// them. A gpodder device polling through the withdrawal is answered the
// since it asked from, so it misses nothing once the grant returns.
func TestAWithdrawnPodcastGrantFailsClosed(t *testing.T) {
	t.Parallel()
	var logged logLines
	g := newPodcastGrantsWith(t, func(cfg *service.Config) {
		cfg.Logger = slog.New(slog.NewTextHandler(&logged, nil))
	})
	formerID, former := g.account(t, "former", g.musicLib, g.podcastLib)
	feedURL := g.feedURL(t)
	if code, body := g.status(t, http.MethodPost, "/api/v1/podcasts", former, map[string]any{"url": feedURL}); code != 201 {
		t.Fatalf("subscribing while granted = %d: %s", code, body)
	}
	if code, body := g.status(t, http.MethodPut, "/api/v1/items/"+g.fetched+"/play-state", former, map[string]any{"positionMs": 2000}); code != 204 {
		t.Fatalf("saving a position while granted = %d: %s", code, body)
	}
	secret := decodeStatus[AppPasswordCreated](t, reqAs(t, g.h, http.MethodPost, "/api/v1/users/me/app-passwords", former,
		map[string]any{"label": "clients"}), 201, "minting an app password").Secret
	gp := httptest.NewServer(gpodder.New(g.h.svc, false, nil))
	t.Cleanup(gp.Close)
	device := func(method, path, body string) string {
		t.Helper()
		req, _ := http.NewRequest(method, gp.URL+path, strings.NewReader(body))
		req.SetBasicAuth("former", secret)
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		raw, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		if resp.StatusCode != 200 {
			t.Fatalf("%s %s = %d: %s", method, path, resp.StatusCode, raw)
		}
		return string(raw)
	}
	device("PUT", "/subscriptions/former/phone.txt", feedURL+"\n")
	subsonic := func(view string) map[string]any {
		t.Helper()
		resp, err := http.Get(g.h.ts.URL + "/rest/" + view + ".view?apiKey=" + secret + "&v=1.16.1&c=test&f=json")
		if err != nil {
			t.Fatal(err)
		}
		defer resp.Body.Close()
		var wrapper map[string]map[string]any
		if err := json.NewDecoder(resp.Body).Decode(&wrapper); err != nil {
			t.Fatal(err)
		}
		return wrapper["subsonic-response"]
	}
	grant := func(libs ...string) {
		t.Helper()
		resp := g.h.patchJSON(t, "/api/v1/users/"+formerID, map[string]any{
			"libraryAccess": map[string]any{"mode": "granted", "libraryPids": libs},
		})
		wantStatus(t, resp, 200, "setting the grant")
	}
	listed := func() int {
		t.Helper()
		return len(decode[SubscriptionPage](t, reqAs(t, g.h, http.MethodGet, "/api/v1/podcasts", former, nil)).Items)
	}
	var episodeURL string
	for _, a := range readGpodder(t, device("GET", "/api/2/episodes/former.json?since=0", "")).Actions {
		if a.Device == "waxdeck" && a.Podcast == feedURL {
			episodeURL = a.Episode
		}
	}
	if episodeURL == "" {
		t.Fatal("the episodes download while granted names no play of the apps'")
	}
	grant(g.musicLib)

	if n := listed(); n != 0 {
		t.Errorf("the subscription list names %d shows, want none", n)
	}
	if code, body := g.status(t, http.MethodGet, "/api/v1/podcasts/opml", former, nil); code != 200 || strings.Contains(body, feedURL) {
		t.Errorf("the OPML export = %d: %s", code, body)
	}
	if env := subsonic("getPodcasts"); env["status"] != "ok" || len(jlist(jmap(env["podcasts"])["channel"])) != 0 {
		t.Errorf("getPodcasts = %v, want ok and no channels", env)
	}
	if env := subsonic("getNewestPodcasts"); env["status"] != "ok" || len(jlist(jmap(env["newestPodcasts"])["episode"])) != 0 {
		t.Errorf("getNewestPodcasts = %v, want ok and no episodes", env)
	}
	for _, path := range []string{"/subscriptions/former.txt", "/subscriptions/former/phone.txt"} {
		if got := device("GET", path, ""); strings.Contains(got, feedURL) {
			t.Errorf("gpodder %s = %q, want no feed", path, got)
		}
	}
	// An upload answers as ever and moves no episode the account cannot
	// see; the log keeps it for the grant's return.
	device("POST", "/api/2/episodes/former.json",
		`[{"podcast":"`+feedURL+`","episode":"`+episodeURL+`","device":"phone","action":"play","position":30}]`)
	if strings.Contains(logged.String(), "gpodder play write-through") {
		t.Errorf("the upload was written through to an episode the account cannot see: %s", logged.String())
	}
	delta := readGpodder(t, device("GET", "/api/2/subscriptions/former/tablet.json?since=0", ""))
	if len(delta.Add)+len(delta.Remove) != 0 || delta.Timestamp != 0 {
		t.Errorf("the gpodder delta from 0 = %+v, want nothing and its since back", delta)
	}
	actions := readGpodder(t, device("GET", "/api/2/episodes/former.json?since=0", ""))
	if len(actions.Actions) != 0 || actions.Timestamp != 0 {
		t.Errorf("the episodes download from 0 = %+v, want nothing and its since back", actions)
	}

	for _, c := range []struct {
		method, path string
		body         any
	}{
		{http.MethodPost, "/api/v1/podcasts/" + g.show + "/refresh", nil},
		{http.MethodPost, "/api/v1/episodes/" + g.unfetched + "/fetch", nil},
		{http.MethodDelete, "/api/v1/episodes/" + g.fetched + "/fetch", nil},
		{http.MethodPut, "/api/v1/podcasts/" + g.show + "/settings", map[string]any{"autoDownload": true}},
		{http.MethodDelete, "/api/v1/podcasts/" + g.show, nil},
	} {
		if code, body := g.status(t, c.method, c.path, former, c.body); code != 404 || !strings.Contains(body, `"not-found"`) {
			t.Errorf("%s %s = %d: %s, want not-found", c.method, c.path, code, body)
		}
	}
	device("POST", "/api/2/subscriptions/former/phone.json", `{"add":[],"remove":["`+feedURL+`"]}`)
	device("PUT", "/subscriptions/former/phone.txt", "")

	grant(g.musicLib, g.podcastLib)
	page := decode[SubscriptionPage](t, reqAs(t, g.h, http.MethodGet, "/api/v1/podcasts", former, nil))
	if len(page.Items) != 1 || page.Items[0].Show.Pid != g.show ||
		(page.Items[0].Settings.AutoDownload != nil && *page.Items[0].Settings.AutoDownload) {
		t.Errorf("subscriptions after the grant came back = %+v, want the show as it was", page.Items)
	}
	since := strconv.FormatInt(delta.Timestamp, 10)
	if got := readGpodder(t, device("GET", "/api/2/subscriptions/former/tablet.json?since="+since, "")); !slices.Equal(got.Add, []string{feedURL}) {
		t.Errorf("the delta from the withdrawn read's timestamp = %+v, want the add it had not read", got)
	}
	devices := map[string]bool{}
	for _, a := range readGpodder(t, device("GET", "/api/2/episodes/former.json?since="+strconv.FormatInt(actions.Timestamp, 10), "")).Actions {
		if a.Podcast == feedURL && a.Episode == episodeURL {
			devices[a.Device] = true
		}
	}
	if !devices["phone"] || !devices["waxdeck"] {
		t.Errorf("the episodes download from the withdrawn read's timestamp names the episode for %v, want the phone's upload and the apps' play", devices)
	}
	if st := decode[PlayState](t, reqAs(t, g.h, http.MethodGet, "/api/v1/items/"+g.fetched+"/play-state", former, nil)); st.PositionMs != 2000 {
		t.Errorf("the position after an upload made during the withdrawal = %d, want the apps' 2000", st.PositionMs)
	}
}
