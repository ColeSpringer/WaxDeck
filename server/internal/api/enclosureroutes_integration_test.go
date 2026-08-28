package api

import (
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

// chainFeed is a podcast host whose enclosure sits behind a redirect
// chain, the way measurement prefixes front real audio, and which
// counts what each leg is asked for.
//
// Two edges rather than one, because the interesting failure is a
// remembered chain end that stops answering while the chain itself
// still resolves: that is a signed CDN URL expiring, and it is what the
// invalidate-and-walk rule exists for.
//
// Not `feedServer`, whose `enclosurePrefix` builds the same hop chain:
// nothing there counts what each leg was asked for, and its chain ends
// at a fixed file, so there is no terminus to move. Both are the
// subject here.
type chainFeed struct {
	ts   *httptest.Server
	dir  string
	mu   sync.Mutex
	hits map[string]int
	// edge names which of the two endpoints the chain currently ends
	// at; the other one answers 404.
	edge int
}

const chainHops = 5

func newChainFeed(t *testing.T) *chainFeed {
	t.Helper()
	cf := &chainFeed{dir: t.TempDir(), hits: map[string]int{}, edge: 1}
	// Real bytes, so the relay has something to serve and a player
	// would have something to decode.
	body := strings.Repeat("waxdeck-episode-bytes.", 512)
	if err := os.WriteFile(filepath.Join(cf.dir, "episode.mp3"), []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}

	mux := http.NewServeMux()
	// /hop/<n> walks down to /edge/<current>/episode.mp3.
	mux.HandleFunc("/hop/", func(w http.ResponseWriter, r *http.Request) {
		n := 0
		if _, err := fmt.Sscanf(strings.TrimPrefix(r.URL.Path, "/hop/"), "%d", &n); err != nil || n < 1 {
			http.NotFound(w, r)
			return
		}
		if n > 1 {
			http.Redirect(w, r, fmt.Sprintf("/hop/%d", n-1), http.StatusFound)
			return
		}
		cf.mu.Lock()
		edge := cf.edge
		cf.mu.Unlock()
		http.Redirect(w, r, fmt.Sprintf("/edge/%d/episode.mp3", edge), http.StatusFound)
	})
	mux.HandleFunc("/edge/", func(w http.ResponseWriter, r *http.Request) {
		cf.mu.Lock()
		live := fmt.Sprintf("/edge/%d/episode.mp3", cf.edge)
		cf.mu.Unlock()
		if r.URL.Path != live {
			// The stale edge: a signed URL past its expiry.
			http.NotFound(w, r)
			return
		}
		http.ServeFile(w, r, filepath.Join(cf.dir, "episode.mp3"))
	})
	mux.Handle("/", http.FileServer(http.Dir(cf.dir)))

	cf.ts = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		cf.mu.Lock()
		cf.hits[r.URL.Path]++
		cf.mu.Unlock()
		mux.ServeHTTP(w, r)
	}))
	t.Cleanup(cf.ts.Close)
	cf.writeFeed(t)
	return cf
}

func (cf *chainFeed) writeFeed(t *testing.T) {
	t.Helper()
	doc := `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" xmlns:podcast="https://podcastindex.org/namespace/1.0">
<channel>
<title>Chained Cast</title>
<itunes:author>Chain Author</itunes:author>
<description>A show fronted by measurement prefixes.</description>
<podcast:guid>chained-cast-guid</podcast:guid>
<item>
	<title>Episode 1</title>
	<guid isPermaLink="false">chain-guid-1</guid>
	<pubDate>` + time.Date(2026, 6, 1, 8, 0, 0, 0, time.UTC).Format(time.RFC1123Z) + `</pubDate>
	<itunes:duration>30</itunes:duration>
	<enclosure url="` + cf.ts.URL + fmt.Sprintf("/hop/%d", chainHops) + `" type="audio/mpeg" length="1000"/>
</item>
</channel>
</rss>`
	if err := os.WriteFile(filepath.Join(cf.dir, "feed.xml"), []byte(doc), 0o644); err != nil {
		t.Fatal(err)
	}
}

func (cf *chainFeed) feedURL() string { return cf.ts.URL + "/feed.xml" }

// enclosureURL is what the feed names, which is half of a route's key.
func (cf *chainFeed) enclosureURL() string {
	return cf.ts.URL + fmt.Sprintf("/hop/%d", chainHops)
}

func (cf *chainFeed) hitsOn(path string) int {
	cf.mu.Lock()
	defer cf.mu.Unlock()
	return cf.hits[path]
}

func (cf *chainFeed) rotateEdge() {
	cf.mu.Lock()
	cf.edge = 2
	cf.mu.Unlock()
}

// warmedRoute waits for the background resolve to have recorded where
// the chain ends.
//
// The recorded route, not the entry hop's hit count: the counting
// wrapper increments on the way in, so a walk that has reached the
// chain has not necessarily finished it, and a range issued in that
// window walks the chain a second time. Under load that is a CI-only
// flake reported as a cache failure.
func warmedRoute(t *testing.T, h *harness, pid, from string) string {
	t.Helper()
	var resolved string
	waitFor2(t, func() bool {
		got, ok := h.srv.enclosures.lookup(pid, from)
		resolved = got
		return ok
	})
	return resolved
}

// chainEpisode subscribes to cf and returns the episode's pid.
func chainEpisode(t *testing.T, h *harness, cf *chainFeed) string {
	t.Helper()
	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": cf.feedURL()})
	if resp.StatusCode != 201 {
		t.Fatalf("subscribe status = %d", resp.StatusCode)
	}
	sub := decode[Subscription](t, resp)
	resp = get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)
	page := decode[EpisodePage](t, resp)
	if len(page.Items) != 1 {
		t.Fatalf("episodes = %d, want 1", len(page.Items))
	}
	return page.Items[0].Pid
}

// The first-play cost this exists to remove: a not-yet-fetched episode
// used to walk its whole prefix chain before the first byte moved, and
// again on every seek, because a media element re-ranges constantly.
//
// Two halves, in one test because they are one measurement: play-info
// warms the chain in the background, and every relayed range after that
// goes straight to the far end.
func TestEnclosureChainIsWalkedOnce(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	cf := newChainFeed(t)
	pid := chainEpisode(t, h, cf)

	entry := fmt.Sprintf("/hop/%d", chainHops)
	resp := get(t, h.ts, "/api/v1/items/"+pid+"/play-info", h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("play-info status = %d", resp.StatusCode)
	}
	info := decode[PlayInfo](t, resp)

	// The warm is a supervised worker, so the walk lands shortly after
	// play-info answers rather than with it.
	warmedRoute(t, h, pid, cf.enclosureURL())
	if got := cf.hitsOn(entry); got != 1 {
		t.Fatalf("play-info left the chain walked %d times, want 1", got)
	}

	// Three ranges, the shape of a listener starting and then scrubbing
	// twice. None of them may touch the chain again.
	for i, rng := range []string{"", "bytes=0-99", "bytes=200-299"} {
		req, err := http.NewRequest(http.MethodGet, h.ts.URL+info.Url, nil)
		if err != nil {
			t.Fatal(err)
		}
		if rng != "" {
			req.Header.Set("Range", rng)
		}
		relayed, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		body, err := io.ReadAll(relayed.Body)
		relayed.Body.Close()
		if err != nil {
			t.Fatal(err)
		}
		if relayed.StatusCode != http.StatusOK && relayed.StatusCode != http.StatusPartialContent {
			t.Fatalf("range %d status = %d", i, relayed.StatusCode)
		}
		if len(body) == 0 {
			t.Fatalf("range %d served no bytes", i)
		}
	}
	if got := cf.hitsOn(entry); got != 1 {
		t.Fatalf("chain walked %d times across three ranges, want 1", got)
	}
	if got := cf.hitsOn("/edge/1/episode.mp3"); got != 4 {
		t.Fatalf("the far end was asked %d times, want 4 (one warm, three ranges)", got)
	}
}

// A remembered chain end is a shortcut, not an address. When it stops
// answering - a signed CDN URL past its expiry - the relay drops it and
// walks the chain once, and the listener never sees the difference.
func TestEnclosureRouteFallsBackWhenTheEndMoves(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	cf := newChainFeed(t)
	pid := chainEpisode(t, h, cf)

	entry := fmt.Sprintf("/hop/%d", chainHops)
	resp := get(t, h.ts, "/api/v1/items/"+pid+"/play-info", h.token)
	info := decode[PlayInfo](t, resp)
	if got := warmedRoute(t, h, pid, cf.enclosureURL()); !strings.HasSuffix(got, "/edge/1/episode.mp3") {
		t.Fatalf("the warm remembered %q, want the first edge", got)
	}

	// The edge the warm remembered goes away and the chain now ends
	// somewhere else.
	cf.rotateEdge()

	relayed := get(t, h.ts, info.Url, "")
	body, err := io.ReadAll(relayed.Body)
	relayed.Body.Close()
	if err != nil {
		t.Fatal(err)
	}
	if relayed.StatusCode != http.StatusOK {
		t.Fatalf("relay after the edge moved = %d, want 200", relayed.StatusCode)
	}
	if len(body) == 0 {
		t.Fatal("the relay served no bytes after the edge moved")
	}
	if got := cf.hitsOn(entry); got != 2 {
		t.Fatalf("chain walked %d times, want 2 (the warm, then the fallback)", got)
	}

	// And the new end is what is remembered now: the next range walks
	// nothing. The relay records before it writes a byte, so the route
	// is already there.
	if got, ok := h.srv.enclosures.lookup(pid, cf.enclosureURL()); !ok ||
		!strings.HasSuffix(got, "/edge/2/episode.mp3") {
		t.Fatalf("the fallback remembered %q (%v), want the new edge", got, ok)
	}
	again := get(t, h.ts, info.Url, "")
	io.Copy(io.Discard, again.Body)
	again.Body.Close()
	if got := cf.hitsOn(entry); got != 2 {
		t.Fatalf("chain walked %d times after the fallback, want still 2", got)
	}
	if got := cf.hitsOn("/edge/2/episode.mp3"); got != 2 {
		t.Fatalf("the new end was asked %d times, want 2", got)
	}
}

// crossOriginFeed is a paid feed whose audio lives on a CDN of its own:
// the feed document and the enclosure entry sit behind basic auth, and
// the enclosure redirects to a second, open host.
//
// The shape that makes the route cache a liability rather than a win.
// A remembered CDN URL cannot carry the show's credentials - it is a
// different origin, and nothing here proves it is still the party the
// feed named - so the shortcut would earn a 401 and cost a full walk on
// top of itself, every range, forever.
type crossOriginFeed struct {
	origin          *httptest.Server
	cdn             *httptest.Server
	mu              sync.Mutex
	hits            map[string]int
	cdnCredentialed bool
}

func newCrossOriginFeed(t *testing.T, user, pass string) *crossOriginFeed {
	t.Helper()
	cf := &crossOriginFeed{hits: map[string]int{}}
	body := strings.Repeat("waxdeck-paid-episode.", 512)

	// Reached by a different name than the origin's, which is what makes
	// the hop a real one: Go forwards Authorization across a redirect
	// that stays on the same hostname, ports included, so two
	// 127.0.0.1 servers would be one host to it.
	cf.cdn = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		cf.mu.Lock()
		cf.hits["cdn"]++
		if r.Header.Get("Authorization") != "" {
			cf.cdnCredentialed = true
		}
		cf.mu.Unlock()
		http.ServeContent(w, r, "episode.mp3", time.Time{}, strings.NewReader(body))
	}))
	t.Cleanup(cf.cdn.Close)

	cf.origin = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		cf.mu.Lock()
		cf.hits[r.URL.Path]++
		cf.mu.Unlock()
		gotUser, gotPass, ok := r.BasicAuth()
		if !ok || gotUser != user || gotPass != pass {
			w.Header().Set("WWW-Authenticate", `Basic realm="private"`)
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		if r.URL.Path == "/enclosure.mp3" {
			http.Redirect(w, r, cf.cdnURL()+"/episode.mp3", http.StatusFound)
			return
		}
		w.Header().Set("Content-Type", "application/rss+xml")
		fmt.Fprint(w, `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" xmlns:podcast="https://podcastindex.org/namespace/1.0">
<channel>
<title>Paid Cast</title>
<description>A show behind a login.</description>
<podcast:guid>paid-cast-guid</podcast:guid>
<item>
	<title>Episode 1</title>
	<guid isPermaLink="false">paid-guid-1</guid>
	<pubDate>`+time.Date(2026, 6, 1, 8, 0, 0, 0, time.UTC).Format(time.RFC1123Z)+`</pubDate>
	<itunes:duration>30</itunes:duration>
	<enclosure url="`+cf.origin.URL+`/enclosure.mp3" type="audio/mpeg" length="1000"/>
</item>
</channel>
</rss>`)
	}))
	t.Cleanup(cf.origin.Close)
	return cf
}

// cdnURL names the CDN by a hostname the origin does not share.
func (cf *crossOriginFeed) cdnURL() string {
	return strings.Replace(cf.cdn.URL, "127.0.0.1", "localhost", 1)
}

func (cf *crossOriginFeed) hitsOn(key string) int {
	cf.mu.Lock()
	defer cf.mu.Unlock()
	return cf.hits[key]
}

func (cf *crossOriginFeed) sawCredentials() bool {
	cf.mu.Lock()
	defer cf.mu.Unlock()
	return cf.cdnCredentialed
}

// A credentialed feed whose chain leaves its own origin is the one
// population the cache must decline to serve. Remembering the CDN URL
// would mean an unauthenticated shortcut, a 401, and then the walk
// anyway - two upstream requests per range where there used to be one,
// against a host whose operator may well rate-limit repeated auth
// failures.
func TestEnclosureCrossOriginCredentialsAreNotCached(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	cf := newCrossOriginFeed(t, "member", "tokensecret")

	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{
		"url": cf.origin.URL + "/feed.xml", "username": "member", "password": "tokensecret",
	})
	if resp.StatusCode != 201 {
		t.Fatalf("subscribe status = %d", resp.StatusCode)
	}
	sub := decode[Subscription](t, resp)
	resp = get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)
	page := decode[EpisodePage](t, resp)
	if len(page.Items) != 1 {
		t.Fatalf("episodes = %d, want 1", len(page.Items))
	}
	pid := page.Items[0].Pid

	resp = get(t, h.ts, "/api/v1/items/"+pid+"/play-info", h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("play-info status = %d", resp.StatusCode)
	}
	info := decode[PlayInfo](t, resp)
	// The warm walks the chain and declines to record it.
	waitFor2(t, func() bool { return cf.hitsOn("cdn") > 0 })

	enclosure := cf.origin.URL + "/enclosure.mp3"
	if got, ok := h.srv.enclosures.lookup(pid, enclosure); ok {
		t.Fatalf("a credentialed cross-origin chain was remembered as %q", got)
	}

	// Two ranges, each a full walk with the credentials on the first
	// hop, each serving audio. Two walks and two CDN fetches, not four.
	for i := range 2 {
		relayed := get(t, h.ts, info.Url, "")
		body, err := io.ReadAll(relayed.Body)
		relayed.Body.Close()
		if err != nil {
			t.Fatal(err)
		}
		if relayed.StatusCode != http.StatusOK || len(body) == 0 {
			t.Fatalf("range %d = %d with %d bytes", i, relayed.StatusCode, len(body))
		}
	}
	if got := cf.hitsOn("/enclosure.mp3"); got != 3 {
		t.Fatalf("the credentialed hop was asked %d times, want 3 (one warm, two ranges)", got)
	}
	if got := cf.hitsOn("cdn"); got != 3 {
		t.Fatalf("the CDN was asked %d times, want 3", got)
	}
	// And the show's login never left its own origin.
	if cf.sawCredentials() {
		t.Fatal("the feed's credentials reached a host the feed did not name")
	}
}
