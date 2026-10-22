package api

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// badHosts answers each path the way a host that is no podcast feed does.
func badHosts(t *testing.T) *httptest.Server {
	t.Helper()
	mux := http.NewServeMux()
	mux.HandleFunc("/page", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html")
		io.WriteString(w, "<!doctype html><html><head><title>Example</title></head><body>a page</body></html>")
	})
	mux.HandleFunc("/huge.xml", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/rss+xml")
		io.WriteString(w, `<?xml version="1.0"?><rss version="2.0"><channel><title>Huge</title><!--`)
		io.WriteString(w, strings.Repeat("x", 21<<20))
		io.WriteString(w, `--></channel></rss>`)
	})
	mux.HandleFunc("/members.xml", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("WWW-Authenticate", `Basic realm="members"`)
		http.Error(w, "unauthorized", http.StatusUnauthorized)
	})
	mux.HandleFunc("/down.xml", func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "upstream on fire", http.StatusServiceUnavailable)
	})
	ts := httptest.NewServer(mux)
	t.Cleanup(ts.Close)
	return ts
}

// wantFeedRefusal reads one refusal and checks it says why in the
// server's sentence, with the reason, and nothing of what the host or the
// catalog said.
func wantFeedRefusal(t *testing.T, resp *http.Response, status int, code, reason, sentence, url string) {
	t.Helper()
	raw, err := io.ReadAll(resp.Body)
	resp.Body.Close()
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != status {
		t.Fatalf("status = %d (%s), want %d", resp.StatusCode, raw, status)
	}
	for _, leak := range []string{"podcast.", "provider", "netsafe", "HTTP 4", "HTTP 5", url} {
		if strings.Contains(string(raw), leak) {
			t.Errorf("the body says %q: %s", leak, raw)
		}
	}
	var body Error
	if err := json.Unmarshal(raw, &body); err != nil {
		t.Fatalf("body %s: %v", raw, err)
	}
	if body.Code != code || body.Message != sentence {
		t.Errorf("body = %s, want code %s and %q", raw, code, sentence)
	}
	if body.Params == nil || (*body.Params)["reason"] != reason {
		t.Errorf("params = %v, want reason %s", body.Params, reason)
	}
}

// A feed the server will not take is refused in the user's words: the
// address is the caller's to change, so a 400 that says which way it is
// wrong; a host that failed is a 502 that says how.
func TestASubscribeRefusalSaysWhy(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	hosts := badHosts(t)
	for _, c := range []struct {
		path     string
		status   int
		code     string
		reason   string
		sentence string
	}{
		{"/page", 400, "invalid-request", "not-a-feed", "That address did not return a podcast feed."},
		{"/huge.xml", 400, "invalid-request", "too-large", "That feed is larger than this server accepts (16 MiB)."},
		{"/members.xml", 502, "feed-unreachable", "host-refused", "The feed's host refused the request; it may need a login."},
		{"/gone.xml", 502, "feed-unreachable", "host-missing", "No feed was found at that address."},
		{"/down.xml", 502, "feed-unreachable", "host-error", "The feed's host answered with an error."},
	} {
		t.Run(c.reason, func(t *testing.T) {
			url := hosts.URL + c.path
			resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": url})
			wantFeedRefusal(t, resp, c.status, c.code, c.reason, c.sentence, url)
		})
	}
}

// A server that keeps its fetches off the local network says so.
func TestASubscribeToAPrivateAddressIsRefused(t *testing.T) {
	t.Parallel()
	h := newPodcastHarnessWith(t, func(cfg *service.Config) { cfg.AllowPrivateFeedHosts = false })
	feed := newFeedServer(t, 1)
	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
	wantFeedRefusal(t, resp, 400, "invalid-request", "blocked-address",
		"This server does not fetch feeds from private or local network addresses.", feed.feedURL())
}

// Each entry of an import says why it did not land, in the same words a
// subscribe would, and the import as a whole still succeeds.
func TestAnOpmlImportSaysWhyEachFeedFailed(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	hosts := badHosts(t)
	feed := newFeedServer(t, 1)
	doc := fmt.Sprintf(`<?xml version="1.0"?><opml version="2.0"><body>
		<outline text="Good" xmlUrl=%q/>
		<outline text="Page" xmlUrl=%q/>
		<outline text="Members" xmlUrl=%q/>
	</body></opml>`, feed.feedURL(), hosts.URL+"/page", hosts.URL+"/members.xml")
	resp := h.postJSON(t, "/api/v1/podcasts/opml", map[string]any{"opml": doc})
	if resp.StatusCode != 200 {
		t.Fatalf("import status = %d", resp.StatusCode)
	}
	got := decode[OpmlImportResult](t, resp)
	byURL := map[string]OpmlImportEntry{}
	for _, e := range got.Results {
		byURL[e.FeedUrl] = e
	}
	if good := byURL[feed.feedURL()]; good.Pid == nil || good.Error != nil || good.Reason != nil {
		t.Errorf("the good feed = %+v, want subscribed", good)
	}
	for url, want := range map[string][2]string{
		hosts.URL + "/page":        {"not-a-feed", "That address did not return a podcast feed."},
		hosts.URL + "/members.xml": {"host-refused", "The feed's host refused the request; it may need a login."},
	} {
		e := byURL[url]
		if e.Error == nil || *e.Error != want[1] || e.Reason == nil || string(*e.Reason) != want[0] {
			t.Errorf("%s = %+v, want %q (%s)", url, e, want[1], want[0])
		}
	}
}

// A transcript its host refuses says so, and keeps saying so from the
// cache, without asking the host again, rather than turning into a host
// that did not answer.
func TestATranscriptItsHostRefusesSaysWhy(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	feed := newFeedServer(t, 1)
	files := http.FileServer(http.Dir(feed.dir))
	var asked atomic.Int32
	feed.ts.Config.Handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, ".vtt") {
			asked.Add(1)
			http.Error(w, "forbidden", http.StatusForbidden)
			return
		}
		files.ServeHTTP(w, r)
	})
	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
	if resp.StatusCode != 201 {
		t.Fatalf("subscribe status = %d", resp.StatusCode)
	}
	sub := decode[Subscription](t, resp)
	page := decode[EpisodePage](t, get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token))
	if len(page.Items) != 1 {
		t.Fatalf("episodes = %d, want 1", len(page.Items))
	}
	path := "/api/v1/episodes/" + page.Items[0].Pid + "/transcript"
	for _, when := range []string{"fetched", "cached"} {
		t.Run(when, func(t *testing.T) {
			wantFeedRefusal(t, get(t, h.ts, path, h.token), 502, "feed-unreachable", "host-refused",
				"The transcript's host refused the request; it may need a login.", feed.ts.URL)
		})
	}
	if got := asked.Load(); got != 1 {
		t.Errorf("the transcript host was asked %d times, want once: the second answer is the cache's", got)
	}
}

// A refresh of a feed whose host has started refusing says that, too.
func TestARefreshItsHostRefusesSaysWhy(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	feed := newFeedServer(t, 1)
	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
	if resp.StatusCode != 201 {
		t.Fatalf("subscribe status = %d", resp.StatusCode)
	}
	sub := decode[Subscription](t, resp)
	feed.ts.Config.Handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "forbidden", http.StatusForbidden)
	})
	resp = h.postJSON(t, "/api/v1/podcasts/"+sub.Show.Pid+"/refresh", nil)
	wantFeedRefusal(t, resp, 502, "feed-unreachable", "host-refused",
		"The feed's host refused the request; it may need a login.", feed.feedURL())
}

// Capturing a transcript its host refuses says why, as reading it does,
// and asking again meanwhile answers from the remembered failure without
// asking the host.
func TestATranscriptCaptureItsHostRefusesSaysWhy(t *testing.T) {
	t.Parallel()
	capture := func(t *testing.T, transcript http.HandlerFunc) (*harness, *feedServer, string) {
		t.Helper()
		h := newPodcastHarness(t)
		feed := newFeedServer(t, 1)
		files := http.FileServer(http.Dir(feed.dir))
		feed.ts.Config.Handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if strings.HasSuffix(r.URL.Path, ".vtt") {
				transcript(w, r)
				return
			}
			files.ServeHTTP(w, r)
		})
		resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
		if resp.StatusCode != 201 {
			t.Fatalf("subscribe status = %d", resp.StatusCode)
		}
		sub := decode[Subscription](t, resp)
		page := decode[EpisodePage](t, get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token))
		if len(page.Items) != 1 {
			t.Fatalf("episodes = %d, want 1", len(page.Items))
		}
		return h, feed, "/api/v1/episodes/" + page.Items[0].Pid + "/transcript"
	}
	var asked atomic.Int64
	h, feed, path := capture(t, func(w http.ResponseWriter, _ *http.Request) {
		asked.Add(1)
		http.Error(w, "forbidden", http.StatusForbidden)
	})
	wantFeedRefusal(t, h.postJSON(t, path, nil), 502, "feed-unreachable", "host-refused",
		"The transcript's host refused the request; it may need a login.", feed.ts.URL)
	wantFeedRefusal(t, h.postJSON(t, path, nil), 502, "feed-unreachable", "host-refused",
		"The transcript's host refused the request; it may need a login.", feed.ts.URL)
	if n := asked.Load(); n != 1 {
		t.Errorf("the host was asked %d times for two captures, want once", n)
	}

	// One that answers with no text in it is not a transcript.
	h, feed, path = capture(t, func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/vtt")
		io.WriteString(w, "WEBVTT\n")
	})
	wantFeedRefusal(t, h.postJSON(t, path, nil), 502, "feed-unreachable", "not-a-feed",
		"The transcript's address did not return a transcript.", feed.ts.URL)
}

// A document that is not OPML is refused in the server's words, not the
// XML decoder's.
func TestAnImportOfSomethingElseSaysSoPlainly(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	resp := h.postJSON(t, "/api/v1/podcasts/opml", map[string]any{"opml": "<opml><body><outline"})
	if resp.StatusCode != 400 {
		t.Fatalf("status = %d, want 400", resp.StatusCode)
	}
	if body := decode[Error](t, resp); body.Code != "invalid-request" || body.Message != "not an OPML document" {
		t.Fatalf("body = %+v, want the plain refusal", body)
	}
}
