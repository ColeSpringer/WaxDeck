package api

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

// The subscription tile's three numbers come from counting queries for
// a caller who may see everything and from a walk for one who may not.
// These are the parity assertion between the two.
//
// The population is the part worth proving: the two agree only because
// an items query counts an episode nobody has fetched, so the fixtures
// leave every episode undownloaded and assert it.

// countsFeed serves a feed whose items can be flagged explicit or left
// undated, which the shared feedServer's cannot.
type countsFeed struct {
	ts  *httptest.Server
	dir string
}

// countsFeeds numbers the feeds so each carries its own podcast:guid.
// One shared guid would collapse every feed onto a single show.
var countsFeeds atomic.Int64

// countsEpisode is one item of a countsFeed.
type countsEpisode struct {
	title    string
	explicit bool
	// undated omits pubDate, which sorts the episode last.
	undated bool
}

func newCountsFeed(t *testing.T, eps []countsEpisode) *countsFeed {
	t.Helper()
	cf := &countsFeed{dir: t.TempDir()}
	mux := http.NewServeMux()
	mux.Handle("/", http.FileServer(http.Dir(cf.dir)))
	cf.ts = httptest.NewServer(mux)
	t.Cleanup(cf.ts.Close)

	guid := strconv.FormatInt(countsFeeds.Add(1), 10)
	var items strings.Builder
	base := time.Date(2026, 6, 1, 8, 0, 0, 0, time.UTC)
	for i, ep := range eps {
		date := ""
		if !ep.undated {
			date = "<pubDate>" + base.AddDate(0, 0, i).Format(time.RFC1123Z) + "</pubDate>"
		}
		explicit := ""
		if ep.explicit {
			explicit = "<itunes:explicit>true</itunes:explicit>"
		}
		// A URL this server never serves: these are only ever counted.
		fmt.Fprintf(&items, `<item>
			<title>%s</title>
			<guid isPermaLink="false">counts-guid-%d</guid>
			%s
			%s
			<itunes:duration>30</itunes:duration>
			<enclosure url="%s/never-fetched-%d.mp3" type="audio/mpeg" length="1000"/>
		</item>`, ep.title, i, date, explicit, cf.ts.URL, i)
	}
	doc := `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" xmlns:podcast="https://podcastindex.org/namespace/1.0">
<channel>
<title>Counting Cast ` + guid + `</title>
<itunes:author>Counting Author</itunes:author>
<description>A show that exists to be counted.</description>
<podcast:guid>counting-cast-` + guid + `</podcast:guid>
` + items.String() + `
</channel>
</rss>`
	if err := os.WriteFile(filepath.Join(cf.dir, "feed.xml"), []byte(doc), 0o644); err != nil {
		t.Fatal(err)
	}
	return cf
}

func (cf *countsFeed) feedURL() string { return cf.ts.URL + "/feed.xml" }

// restrictedListener creates an account that may follow shows but may
// not see explicit ones, and returns its token.
func restrictedListener(t *testing.T, h *harness, username string) string {
	t.Helper()
	resp := h.postJSON(t, "/api/v1/users", map[string]any{
		"username": username, "password": testPassword,
		"permissions": map[string]any{
			"download": true, "delete": false, "explicitContent": false,
			"sharedOutputs": true, "managePodcasts": true,
		},
	})
	wantStatus(t, resp, 201, "create restricted listener")
	return loginAs(t, h.ts, username, testPassword).Token
}

// subscriptionRow reads one caller's subscription row for a show.
func subscriptionRow(t *testing.T, h *harness, token, show string) Subscription {
	t.Helper()
	resp := reqAs(t, h, "GET", "/api/v1/podcasts", token, nil)
	for _, sub := range decode[SubscriptionPage](t, resp).Items {
		if sub.Show.Pid == show {
			return sub
		}
	}
	t.Fatalf("no subscription for %s", show)
	return Subscription{}
}

// The parity case: one show, no explicit episodes, read by a caller who
// counts and one who walks.
func TestShowCountsMatchTheWalk(t *testing.T) {
	h := newPodcastHarness(t)
	eps := make([]countsEpisode, 0, 12)
	for i := range 12 {
		eps = append(eps, countsEpisode{title: fmt.Sprintf("Episode %d", i+1)})
	}
	feed := newCountsFeed(t, eps)

	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
	show := decode[Subscription](t, resp).Show.Pid
	listener := restrictedListener(t, h, "walker")
	resp = reqAs(t, h, "POST", "/api/v1/podcasts", listener, map[string]any{"url": feed.feedURL()})
	resp.Body.Close()

	// If a query counted only present items, the two would differ by 12.
	resp = get(t, h.ts, "/api/v1/podcasts/"+show+"/episodes", h.token)
	for _, ep := range decode[EpisodePage](t, resp).Items {
		if ep.Downloaded {
			t.Fatalf("episode %s is downloaded; the fixture must stay undownloaded", ep.Pid)
		}
	}

	counted := subscriptionRow(t, h, h.token, show)
	walked := subscriptionRow(t, h, listener, show)
	if counted.Show.EpisodeCount == nil || walked.Show.EpisodeCount == nil {
		t.Fatalf("episodeCount = %v (counted) / %v (walked), want both", counted.Show.EpisodeCount, walked.Show.EpisodeCount)
	}
	if *counted.Show.EpisodeCount != 12 || *walked.Show.EpisodeCount != *counted.Show.EpisodeCount {
		t.Errorf("episodeCount = %d counted, %d walked, want 12 both",
			*counted.Show.EpisodeCount, *walked.Show.EpisodeCount)
	}
	if counted.UnplayedCount == nil || walked.UnplayedCount == nil {
		t.Fatalf("unplayedCount = %v / %v, want both", counted.UnplayedCount, walked.UnplayedCount)
	}
	if *counted.UnplayedCount != 12 || *walked.UnplayedCount != *counted.UnplayedCount {
		t.Errorf("unplayedCount = %d counted, %d walked, want 12 both",
			*counted.UnplayedCount, *walked.UnplayedCount)
	}
	if counted.Show.LastPublishedAt == nil || walked.Show.LastPublishedAt == nil {
		t.Fatalf("lastPublishedAt = %v / %v, want both", counted.Show.LastPublishedAt, walked.Show.LastPublishedAt)
	}
	if !counted.Show.LastPublishedAt.Equal(*walked.Show.LastPublishedAt) {
		t.Errorf("lastPublishedAt = %v counted, %v walked",
			*counted.Show.LastPublishedAt, *walked.Show.LastPublishedAt)
	}

	// `played` is per-user: a count with the wrong pid answers somebody
	// else's backlog.
	resp = get(t, h.ts, "/api/v1/podcasts/"+show+"/episodes", h.token)
	all := decode[EpisodePage](t, resp).Items
	putPlayState(t, h, all[0].Pid, all[0].DurationMs)
	putPlayState(t, h, all[1].Pid, all[1].DurationMs)

	if got := subscriptionRow(t, h, h.token, show).UnplayedCount; got == nil || *got != 10 {
		t.Errorf("counted unplayedCount = %v after two plays, want 10", got)
	}
	if got := subscriptionRow(t, h, listener, show).UnplayedCount; got == nil || *got != 12 {
		t.Errorf("walked unplayedCount = %v; the other account's plays are not this one's", got)
	}
}

// Why the walk survives: no `explicit` query field to push the gate
// down with.
func TestRestrictedShowCountsHideExplicitEpisodes(t *testing.T) {
	h := newPodcastHarness(t)
	feed := newCountsFeed(t, []countsEpisode{
		{title: "Clean One"},
		{title: "Explicit One", explicit: true},
		{title: "Clean Two"},
		{title: "Explicit Two", explicit: true},
	})

	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
	show := decode[Subscription](t, resp).Show.Pid
	listener := restrictedListener(t, h, "shielded")
	resp = reqAs(t, h, "POST", "/api/v1/podcasts", listener, map[string]any{"url": feed.feedURL()})
	resp.Body.Close()

	if got := subscriptionRow(t, h, h.token, show).Show.EpisodeCount; got == nil || *got != 4 {
		t.Errorf("counted episodeCount = %v, want all 4", got)
	}
	walked := subscriptionRow(t, h, listener, show)
	if got := walked.Show.EpisodeCount; got == nil || *got != 2 {
		t.Errorf("walked episodeCount = %v, want the 2 clean episodes", got)
	}
	if got := walked.UnplayedCount; got == nil || *got != 2 {
		t.Errorf("walked unplayedCount = %v, want 2", got)
	}
}

// The two cases the walk answered by falling out of its loop.
func TestShowCountsZeroCases(t *testing.T) {
	h := newPodcastHarness(t)

	empty := newCountsFeed(t, nil)
	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": empty.feedURL()})
	emptyShow := decode[Subscription](t, resp).Show.Pid
	row := subscriptionRow(t, h, h.token, emptyShow)
	// A zero count is absent on the wire; the show DTO's own rule.
	if row.Show.EpisodeCount != nil {
		t.Errorf("empty show episodeCount = %d, want absent", *row.Show.EpisodeCount)
	}
	if got := row.UnplayedCount; got == nil || *got != 0 {
		t.Errorf("empty show unplayedCount = %v, want a computed 0", got)
	}
	if row.Show.LastPublishedAt != nil {
		t.Errorf("empty show lastPublishedAt = %v, want absent", *row.Show.LastPublishedAt)
	}

	// Undated sorts last, so the newest row's time is zero, as the
	// walk's max was.
	undated := newCountsFeed(t, []countsEpisode{
		{title: "No Date One", undated: true},
		{title: "No Date Two", undated: true},
	})
	resp = h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": undated.feedURL()})
	undatedShow := decode[Subscription](t, resp).Show.Pid
	// Two feeds, two shows: one shared guid would fold them together and
	// this case would be an incremental sync onto the empty show.
	if undatedShow == emptyShow {
		t.Fatal("the two fixture feeds collapsed onto one show")
	}
	row = subscriptionRow(t, h, h.token, undatedShow)
	if got := row.Show.EpisodeCount; got == nil || *got != 2 {
		t.Errorf("undated show episodeCount = %v, want 2", got)
	}
	if row.Show.LastPublishedAt != nil {
		t.Errorf("undated show lastPublishedAt = %v, want absent", *row.Show.LastPublishedAt)
	}
}
