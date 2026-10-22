package api

import (
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// guidFeedHost serves one show under a podcast:guid at any path, the way
// a premium feed answers each listener's own address.
func guidFeedHost(t *testing.T) string {
	t.Helper()
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/rss+xml")
		fmt.Fprintf(w, `<?xml version="1.0"?><rss version="2.0" xmlns:podcast="https://podcastindex.org/namespace/1.0"><channel><title>Own Show</title>
<podcast:guid>5c1f8f8e-7c0b-5a8e-9d7f-2b8f0c3e4a51</podcast:guid>
<item><title>One</title><guid>own-1</guid><enclosure url="http://%s/one.mp3" type="audio/mpeg" length="1"/></item>
</channel></rss>`, r.Host)
	}))
	t.Cleanup(ts.Close)
	return ts.URL
}

// A follower is handed the address it subscribed a show by wherever a
// client reads one: the show and subscription views, the export and
// Subsonic's getPodcasts, whatever the catalog took up from the last
// account to add the show. Someone who does not follow it is shown the
// catalog's.
func TestAFollowerIsHandedItsOwnAddress(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	host := guidFeedHost(t)
	mine, theirs := host+"/mine.xml", host+"/theirs.xml"
	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": mine})
	if resp.StatusCode != http.StatusCreated {
		t.Fatalf("subscribing by %s = %d", mine, resp.StatusCode)
	}
	show := decode[Subscription](t, resp).Show.Pid
	_, bob := listenerAccount(t, h, "bob", false)
	wantStatus(t, reqAs(t, h, http.MethodPost, "/api/v1/podcasts", bob, map[string]any{"url": theirs}),
		http.StatusCreated, "the other follower's subscribe")
	_, carol := listenerAccount(t, h, "carol", false)

	shown := func(token string) string {
		t.Helper()
		detail := decode[PodcastDetail](t, reqAs(t, h, http.MethodGet, "/api/v1/podcasts/"+show, token, nil))
		return deref(detail.Show.FeedUrl)
	}
	if got := shown(h.token); got != mine {
		t.Errorf("the show detail gives its follower %q, want its own %s", got, mine)
	}
	if row := subscriptionRow(t, h, h.token, show); row.Show.FeedUrl == nil || *row.Show.FeedUrl != mine {
		t.Errorf("the subscription list gives its follower %q, want its own %s", deref(row.Show.FeedUrl), mine)
	}
	export := reqAs(t, h, http.MethodGet, "/api/v1/podcasts/opml", h.token, nil)
	opml, _ := io.ReadAll(export.Body)
	export.Body.Close()
	if export.StatusCode != http.StatusOK || !strings.Contains(string(opml), `xmlUrl="`+mine+`"`) || strings.Contains(string(opml), theirs) {
		t.Errorf("the export = %d: %s, want the follower's own %s", export.StatusCode, opml, mine)
	}
	env := mustOK(t, h, newSubsonicSecret(t, h), "test", "getPodcasts", "&includeEpisodes=false")
	channels := jlist(jmap(env["podcasts"])["channel"])
	if len(channels) != 1 || jmap(channels[0])["url"] != mine {
		t.Errorf("getPodcasts = %v, want the one channel at the follower's own %s", channels, mine)
	}
	if got := shown(bob); got != theirs {
		t.Errorf("the show detail gives its other follower %q, want its own %s", got, theirs)
	}
	if got := shown(carol); got != theirs {
		t.Errorf("the show detail gives someone who does not follow it %q, want the catalog's %s", got, theirs)
	}
}
