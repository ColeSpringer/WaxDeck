package api

import (
	"fmt"
	"html"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"unicode/utf8"
)

// A feed can carry a title as long as the feed itself; the REST and
// Subsonic answers that name the show or its episode give the first
// thousand characters.
func TestFeedTitlesAreClippedInTheAnswers(t *testing.T) {
	t.Parallel()
	showTitle, episodeTitle := "Show "+strings.Repeat("é", 5000), "Episode "+strings.Repeat("ü", 5000)
	host := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/rss+xml")
		fmt.Fprintf(w, `<?xml version="1.0"?><rss version="2.0"><channel><title>%s</title>
<item><title>%s</title><guid>clip-1</guid><enclosure url="http://%s/one.mp3" type="audio/mpeg" length="10"/></item>
</channel></rss>`, html.EscapeString(showTitle), html.EscapeString(episodeTitle), r.Host)
	}))
	t.Cleanup(host.Close)
	h := newPodcastHarness(t)
	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": host.URL + "/feed.xml"})
	if resp.StatusCode != http.StatusCreated {
		t.Fatalf("subscribe status = %d", resp.StatusCode)
	}
	show := decode[Subscription](t, resp).Show.Pid
	clipped := func(what string, got any, full string) {
		t.Helper()
		s, _ := got.(string)
		if n := utf8.RuneCountInString(s); n != 1000 || !strings.HasPrefix(full, s) {
			t.Errorf("%s gives %d characters of the title, want its first 1000", what, n)
		}
	}
	clipped("the show detail", decode[PodcastDetail](t, get(t, h.ts, "/api/v1/podcasts/"+show, h.token)).Show.Title, showTitle)
	eps := decode[EpisodePage](t, get(t, h.ts, "/api/v1/podcasts/"+show+"/episodes", h.token)).Items
	if len(eps) != 1 {
		t.Fatalf("episodes = %d, want 1", len(eps))
	}
	clipped("the episode row", eps[0].Title, episodeTitle)

	env := mustOK(t, h, newSubsonicSecret(t, h), "test", "getPodcasts", "&includeEpisodes=true")
	channels := jlist(jmap(env["podcasts"])["channel"])
	if len(channels) != 1 {
		t.Fatalf("getPodcasts = %v, want one channel", channels)
	}
	clipped("getPodcasts' channel", jmap(channels[0])["title"], showTitle)
	episodes := jlist(jmap(channels[0])["episode"])
	if len(episodes) != 1 {
		t.Fatalf("getPodcasts' channel = %v, want one episode", channels[0])
	}
	clipped("getPodcasts' episode", jmap(episodes[0])["title"], episodeTitle)
	clipped("getPodcasts' episode album", jmap(episodes[0])["album"], showTitle)
}
