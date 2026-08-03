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

// The subscription tile's three numbers are counting queries narrowed
// to what the caller may see. These pin what "may see" means: two
// accounts reading one show agree wherever nothing is flagged and
// diverge exactly where something is.
//
// The population is the part worth proving: the counts include an
// episode nobody has fetched, so the fixtures leave every episode
// undownloaded and assert it.

// countsFeed serves a feed whose channel or items can be flagged
// explicit and whose items can be left undated, which the shared
// feedServer's cannot.
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

// countsChannel carries the channel-level flags a countsFeed declares.
type countsChannel struct {
	// explicit marks the show itself explicit, independent of its items.
	explicit bool
	// firstPublished dates the first item, each later one a day after.
	// The zero value uses the shared default, which makes two feeds tie
	// item for item.
	firstPublished time.Time
}

func newCountsFeed(t *testing.T, eps []countsEpisode) *countsFeed {
	t.Helper()
	return newCountsFeedAs(t, countsChannel{}, eps)
}

func newCountsFeedAs(t *testing.T, ch countsChannel, eps []countsEpisode) *countsFeed {
	t.Helper()
	cf := &countsFeed{dir: t.TempDir()}
	mux := http.NewServeMux()
	mux.Handle("/", http.FileServer(http.Dir(cf.dir)))
	cf.ts = httptest.NewServer(mux)
	t.Cleanup(cf.ts.Close)

	guid := strconv.FormatInt(countsFeeds.Add(1), 10)
	var items strings.Builder
	base := ch.firstPublished
	if base.IsZero() {
		base = time.Date(2026, 6, 1, 8, 0, 0, 0, time.UTC)
	}
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
	channelExplicit := ""
	if ch.explicit {
		channelExplicit = "<itunes:explicit>true</itunes:explicit>"
	}
	doc := `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" xmlns:podcast="https://podcastindex.org/namespace/1.0">
<channel>
<title>Counting Cast ` + guid + `</title>
<itunes:author>Counting Author</itunes:author>
<description>A show that exists to be counted.</description>
<podcast:guid>counting-cast-` + guid + `</podcast:guid>
` + channelExplicit + `
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
	_, token := listenerAccount(t, h, username, false)
	return token
}

// listenerAccount creates a podcast-following account with explicit
// content granted or withheld, and returns its id and token. The id is
// what a later PATCH needs to change its mind.
func listenerAccount(t *testing.T, h *harness, username string, explicit bool) (string, string) {
	t.Helper()
	resp := h.postJSON(t, "/api/v1/users", map[string]any{
		"username": username, "password": testPassword,
		"permissions": map[string]any{
			"download": true, "delete": false, "explicitContent": explicit,
			"sharedOutputs": true, "managePodcasts": true,
		},
	})
	if resp.StatusCode != 201 {
		resp.Body.Close()
		t.Fatalf("create listener status = %d, want 201", resp.StatusCode)
	}
	return decode[UserAccount](t, resp).Id, loginAs(t, h.ts, username, testPassword).Token
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

// The parity case: one show, nothing flagged, read by an account that
// may see explicit content and one that may not. Nothing is flagged, so
// the two must agree on all three numbers.
func TestShowCountsAgreeWhenNothingIsFlagged(t *testing.T) {
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

	// If a query counted only present items, both would read 0.
	resp = get(t, h.ts, "/api/v1/podcasts/"+show+"/episodes", h.token)
	for _, ep := range decode[EpisodePage](t, resp).Items {
		if ep.Downloaded {
			t.Fatalf("episode %s is downloaded; the fixture must stay undownloaded", ep.Pid)
		}
	}

	open := subscriptionRow(t, h, h.token, show)
	restricted := subscriptionRow(t, h, listener, show)
	if open.Show.EpisodeCount == nil || restricted.Show.EpisodeCount == nil {
		t.Fatalf("episodeCount = %v (open) / %v (restricted), want both", open.Show.EpisodeCount, restricted.Show.EpisodeCount)
	}
	if *open.Show.EpisodeCount != 12 || *restricted.Show.EpisodeCount != *open.Show.EpisodeCount {
		t.Errorf("episodeCount = %d open, %d restricted, want 12 both",
			*open.Show.EpisodeCount, *restricted.Show.EpisodeCount)
	}
	if open.UnplayedCount == nil || restricted.UnplayedCount == nil {
		t.Fatalf("unplayedCount = %v / %v, want both", open.UnplayedCount, restricted.UnplayedCount)
	}
	if *open.UnplayedCount != 12 || *restricted.UnplayedCount != *open.UnplayedCount {
		t.Errorf("unplayedCount = %d open, %d restricted, want 12 both",
			*open.UnplayedCount, *restricted.UnplayedCount)
	}
	if open.Show.LastPublishedAt == nil || restricted.Show.LastPublishedAt == nil {
		t.Fatalf("lastPublishedAt = %v / %v, want both", open.Show.LastPublishedAt, restricted.Show.LastPublishedAt)
	}
	if !open.Show.LastPublishedAt.Equal(*restricted.Show.LastPublishedAt) {
		t.Errorf("lastPublishedAt = %v open, %v restricted",
			*open.Show.LastPublishedAt, *restricted.Show.LastPublishedAt)
	}

	// `played` is per-user: a count with the wrong pid answers somebody
	// else's backlog.
	resp = get(t, h.ts, "/api/v1/podcasts/"+show+"/episodes", h.token)
	all := decode[EpisodePage](t, resp).Items
	putPlayState(t, h, all[0].Pid, all[0].DurationMs)
	putPlayState(t, h, all[1].Pid, all[1].DurationMs)

	if got := subscriptionRow(t, h, h.token, show).UnplayedCount; got == nil || *got != 10 {
		t.Errorf("open unplayedCount = %v after two plays, want 10", got)
	}
	if got := subscriptionRow(t, h, listener, show).UnplayedCount; got == nil || *got != 12 {
		t.Errorf("restricted unplayedCount = %v; the other account's plays are not this one's", got)
	}
}

// The gate pushed down into the query: a restricted caller's three
// numbers describe the episodes that caller can actually open, and the
// show detail header agrees with the listing drawn beneath it.
func TestRestrictedShowCountsHideExplicitEpisodes(t *testing.T) {
	h := newPodcastHarness(t)
	feed := newCountsFeed(t, []countsEpisode{
		{title: "Clean One"},
		{title: "Explicit One", explicit: true},
		{title: "Clean Two"},
		// Newest overall, and unreadable: the restricted caller's
		// lastPublishedAt must fall back to Clean Two.
		{title: "Explicit Two", explicit: true},
	})

	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
	show := decode[Subscription](t, resp).Show.Pid
	listener := restrictedListener(t, h, "shielded")
	resp = reqAs(t, h, "POST", "/api/v1/podcasts", listener, map[string]any{"url": feed.feedURL()})
	resp.Body.Close()

	if got := subscriptionRow(t, h, h.token, show).Show.EpisodeCount; got == nil || *got != 4 {
		t.Errorf("open episodeCount = %v, want all 4", got)
	}
	restricted := subscriptionRow(t, h, listener, show)
	if got := restricted.Show.EpisodeCount; got == nil || *got != 2 {
		t.Errorf("restricted episodeCount = %v, want the 2 clean episodes", got)
	}
	if got := restricted.UnplayedCount; got == nil || *got != 2 {
		t.Errorf("restricted unplayedCount = %v, want 2", got)
	}

	// The flagged episodes are shut on the view's own flag, without a
	// read behind it.
	resp = get(t, h.ts, "/api/v1/podcasts/"+show+"/episodes", h.token)
	for _, ep := range decode[EpisodePage](t, resp).Items {
		if ep.Explicit == nil || !*ep.Explicit {
			continue
		}
		resp = reqAs(t, h, "GET", "/api/v1/items/"+ep.Pid, listener, nil)
		wantStatus(t, resp, 404, "restricted item read of a flagged episode")
	}

	// The detail header counts the same way the detail's own episode
	// list filters, so the two never contradict each other.
	resp = reqAs(t, h, "GET", "/api/v1/podcasts/"+show, listener, nil)
	if resp.StatusCode != 200 {
		resp.Body.Close()
		t.Fatalf("restricted show detail status = %d, want 200", resp.StatusCode)
	}
	detail := decode[PodcastDetail](t, resp)
	if got := detail.Show.EpisodeCount; got == nil || *got != 2 {
		t.Errorf("restricted detail episodeCount = %v, want the 2 clean episodes", got)
	}
	resp = reqAs(t, h, "GET", "/api/v1/podcasts/"+show+"/episodes", listener, nil)
	listed := decode[EpisodePage](t, resp).Items
	if len(listed) != 2 {
		t.Fatalf("restricted episode listing = %d rows, want 2", len(listed))
	}
	if detail.Show.LastPublishedAt == nil {
		t.Fatal("restricted detail lastPublishedAt absent, want the newest clean episode")
	}
	// Clean Two is the newest the restricted caller can see; the two
	// explicit ones straddle it in the feed.
	var newestClean time.Time
	for _, ep := range listed {
		if ep.PublishedAt.After(newestClean) {
			newestClean = ep.PublishedAt
		}
	}
	if !detail.Show.LastPublishedAt.Equal(newestClean) {
		t.Errorf("restricted lastPublishedAt = %v, want the newest clean episode %v",
			*detail.Show.LastPublishedAt, newestClean)
	}
	if restricted.Show.LastPublishedAt == nil || !restricted.Show.LastPublishedAt.Equal(newestClean) {
		t.Errorf("restricted tile lastPublishedAt = %v, want %v", restricted.Show.LastPublishedAt, newestClean)
	}
}

// A show flagged explicit at the channel level hides all of it, even
// the episodes that carry no flag of their own: the counts agree with
// the 404 the same caller gets on the show and on any of its episodes.
func TestRestrictedShowCountsZeroExplicitShow(t *testing.T) {
	h := newPodcastHarness(t)
	feed := newCountsFeedAs(t, countsChannel{explicit: true}, []countsEpisode{
		{title: "Unflagged One"},
		{title: "Unflagged Two"},
		{title: "Flagged", explicit: true},
	})

	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
	show := decode[Subscription](t, resp).Show.Pid

	// Subscribing to an explicit show is refused outright, so the only
	// way to hold this row is to have subscribed while allowed and lose
	// the grant afterwards.
	id, listener := listenerAccount(t, h, "revoked", true)
	resp = reqAs(t, h, "POST", "/api/v1/podcasts", listener, map[string]any{"url": feed.feedURL()})
	wantStatus(t, resp, 201, "subscribe while allowed")
	resp = h.patchJSON(t, "/api/v1/users/"+id, map[string]any{
		"permissions": map[string]any{
			"download": true, "delete": false, "explicitContent": false,
			"sharedOutputs": true, "managePodcasts": true,
		},
	})
	wantStatus(t, resp, 200, "revoke explicit content")

	row := subscriptionRow(t, h, listener, show)
	// A zero count is absent on the wire; the show DTO's own rule.
	if row.Show.EpisodeCount != nil {
		t.Errorf("restricted episodeCount = %d, want absent", *row.Show.EpisodeCount)
	}
	if got := row.UnplayedCount; got == nil || *got != 0 {
		t.Errorf("restricted unplayedCount = %v, want a computed 0", got)
	}
	if row.Show.LastPublishedAt != nil {
		t.Errorf("restricted lastPublishedAt = %v, want absent", *row.Show.LastPublishedAt)
	}
	if got := subscriptionRow(t, h, h.token, show).Show.EpisodeCount; got == nil || *got != 3 {
		t.Errorf("open episodeCount = %v, want all 3", got)
	}

	// The numbers and the doors agree: nothing of this show opens. The
	// unflagged episodes are the interesting ones, since only the show's
	// own flag shuts them.
	resp = reqAs(t, h, "GET", "/api/v1/podcasts/"+show, listener, nil)
	wantStatus(t, resp, 404, "restricted show detail on an explicit show")
	resp = get(t, h.ts, "/api/v1/podcasts/"+show+"/episodes", h.token)
	all := decode[EpisodePage](t, resp).Items
	if len(all) != 3 {
		t.Fatalf("open episode listing = %d rows, want 3", len(all))
	}
	for _, ep := range all {
		// Both doors onto the same episode, because the episode endpoint
		// is the one path that reaches an episode without passing its
		// show, and it used to answer what the item read refused.
		resp = reqAs(t, h, "GET", "/api/v1/items/"+ep.Pid, listener, nil)
		wantStatus(t, resp, 404, "restricted item read of an explicit show's episode")
		resp = reqAs(t, h, "GET", "/api/v1/episodes/"+ep.Pid, listener, nil)
		wantStatus(t, resp, 404, "restricted episode read of an explicit show's episode")
	}
}

// The two cases the counts answer by matching nothing.
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

	// The recent-episodes list excludes undated rows outright, so an
	// all-undated show has no newest publication at all.
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
