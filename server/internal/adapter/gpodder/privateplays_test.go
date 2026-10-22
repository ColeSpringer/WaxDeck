package gpodder

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// linkedFeeds serves two shows whatever the query: /members hands each
// listener episode links carrying the token its own address did, the way
// a paid host does, and /open names an episode whose link carries a query
// that is no credential.
func linkedFeeds(t *testing.T) string {
	t.Helper()
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var guid, item string
		switch r.URL.Path {
		case "/members":
			guid = "6b2e1f90-4c1d-5e7a-8f3b-1d9c2a7e5b40"
			item = fmt.Sprintf(`<item><title>Members One</title><guid>members-1</guid><itunes:duration>600</itunes:duration>`+
				`<enclosure url="http://%s/one.mp3?token=%s" type="audio/mpeg" length="1"/></item>`, r.Host, url.QueryEscape(r.URL.Query().Get("token")))
		case "/open":
			guid = "7c3f2a01-5d2e-5f8b-9a4c-2e0d3b8f6c51"
			item = fmt.Sprintf(`<item><title>Open One</title><guid>open-1</guid><itunes:duration>600</itunes:duration>`+
				`<enclosure url="http://%s/two.mp3?src=rss" type="audio/mpeg" length="1"/></item>`, r.Host)
		default:
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "application/rss+xml")
		fmt.Fprintf(w, `<?xml version="1.0"?><rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" xmlns:podcast="https://podcastindex.org/namespace/1.0"><channel><title>%s</title>
<podcast:guid>%s</podcast:guid>
%s
</channel></rss>`, r.URL.Path, guid, item)
	}))
	t.Cleanup(ts.Close)
	return ts.URL
}

// playEpisode moves the one episode of a show uc follows.
func (e *env) playEpisode(uc *service.UserCtx, show string) {
	e.t.Helper()
	eps, _, err := e.svc.Episodes(e.ctx, uc, show, "", 1)
	if err != nil || len(eps) != 1 {
		e.t.Fatalf("episodes = %+v (%v)", eps, err)
	}
	if _, err := e.svc.Checkpoint(e.ctx, uc, eps[0].PID, 30_000, nil); err != nil {
		e.t.Fatal(err)
	}
}

// A private show's play reaches a device named by its episode's guid and
// by the episode's link without its query or user info when the catalog
// holds another follower's address, and so that follower's links with
// its token. The follower whose address the catalog holds, and an open
// show, have their plays name the link as it is, with no guid.
func TestAPrivateShowsPlayCarriesNoOtherAccountsToken(t *testing.T) {
	e := newEnv(t)
	host := linkedFeeds(t)
	members := e.subscribeFirstParty(host + "/members?token=alice")
	bob := e.listener("bob")
	if _, _, err := e.svc.Subscribe(e.ctx, bob, service.SubscribeRequest{URL: host + "/members?token=bob"}); err != nil {
		t.Fatal(err)
	}
	open := e.subscribeFirstParty(host + "/open")
	for _, show := range []string{members, open} {
		e.playEpisode(e.uc, show)
	}
	e.playEpisode(bob, members)
	bobs, _, err := e.svc.GpodderActionsSince(e.ctx, bob, "", 0, "", "")
	if err != nil {
		t.Fatal(err)
	}
	for _, a := range bobs {
		if a.DeviceID == service.GpodderOwnDevice && (a.EpisodeURL != host+"/one.mp3?token=bob" || a.GUID != "") {
			t.Errorf("the play of the follower whose address the catalog holds names %q with guid %q, want its own link as it is", a.EpisodeURL, a.GUID)
		}
	}

	resp, raw := e.call("GET", "/api/2/episodes/alice.json?since=0", "", true)
	mustStatus(t, resp, raw, 200)
	if strings.Contains(string(raw), "token=bob") {
		t.Errorf("the episodes download carries another account's token: %s", raw)
	}
	var page struct {
		Actions []map[string]any `json:"actions"`
	}
	if err := json.Unmarshal(raw, &page); err != nil {
		t.Fatal(err)
	}
	want := map[string]map[string]any{
		host + "/members?token=alice": {"episode": host + "/one.mp3", "guid": "members-1"},
		host + "/open":                {"episode": host + "/two.mp3?src=rss", "guid": nil},
	}
	for _, a := range page.Actions {
		if a["device"] != service.GpodderOwnDevice {
			continue
		}
		podcast, _ := a["podcast"].(string)
		w, ok := want[podcast]
		if !ok {
			t.Errorf("a play names %q, a show the account does not follow by that address", podcast)
			continue
		}
		delete(want, podcast)
		if a["episode"] != w["episode"] || a["guid"] != w["guid"] {
			t.Errorf("the play of %s names episode %v with guid %v, want %v with %v", podcast, a["episode"], a["guid"], w["episode"], w["guid"])
		}
	}
	for podcast := range want {
		t.Errorf("no play of %s in %s", podcast, raw)
	}
}

// A private show this account alone follows was fetched by its own
// address, so its plays name the episode by the link the account's apps
// hold: gPodder desktop finds the episode by that link, AntennaPod weighs
// the play against its own unsent one of the same podcast and episode, and
// the aggregated download answers one action for the episode.
func TestALoneFollowersPrivatePlayKeepsItsOwnLink(t *testing.T) {
	e := newEnv(t)
	host := linkedFeeds(t)
	feed, link := host+"/members?token=alice", host+"/one.mp3?token=alice"
	show := e.subscribeFirstParty(feed)
	phone := newAntennaPod(t, e, "phone-1")
	phone.login()
	phone.register()
	var ack uploadAckJSON
	phone.mustJSON("POST", "/api/2/episodes/alice.json", fmt.Sprintf(
		`[{"podcast":%q,"episode":%q,"guid":"members-1","device":"phone-1","action":"play","timestamp":%q,"started":0,"position":100,"total":600}]`,
		feed, link, time.Now().Add(-time.Hour).UTC().Format("2006-01-02T15:04:05")), &ack)
	e.playEpisode(e.uc, show)

	laptop := newGpodderDesktop(t, e, "laptop")
	laptop.connect()
	plays := actionsFor(laptop.downloadActions(0), link)
	keys := map[string]bool{}
	for _, p := range plays {
		keys[p.Device] = p.Podcast == feed && p.GUID == ""
	}
	if len(keys) != 2 || !keys[service.GpodderOwnDevice] || !keys["phone-1"] {
		t.Errorf("the plays under the account's own link %s = %+v, want the web play and the phone's, both of %s", link, plays, feed)
	}

	resp, raw := e.call("GET", "/api/2/episodes/alice.json?since=0&aggregated=true", "", true)
	mustStatus(t, resp, raw, 200)
	var page struct {
		Actions []map[string]any `json:"actions"`
	}
	if err := json.Unmarshal(raw, &page); err != nil {
		t.Fatal(err)
	}
	n := 0
	for _, a := range page.Actions {
		if a["podcast"] == feed {
			n++
		}
	}
	if n != 1 {
		t.Errorf("the aggregated download answers %d actions for the episode, want one: %s", n, raw)
	}
}
