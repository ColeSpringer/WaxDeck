package api

import (
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

// otherHostFeed is a feed behind basic auth whose audio lives elsewhere:
// one episode's enclosure names a second host outright, the other's sits
// at the feed's origin and redirects to that host. The second host, on
// another port of the same address, is one Go would forward the
// credentials to.
type otherHostFeed struct {
	origin, other *httptest.Server
	mu            sync.Mutex
	asked         []string // what the second host was asked: "<path> <range> <authorization>"
	walks         int      // credentialed asks of the origin's redirect
}

func newOtherHostFeed(t *testing.T, user, pass string) *otherHostFeed {
	t.Helper()
	f := &otherHostFeed{}
	body := strings.Repeat("waxdeck-other-host-episode.", 256)
	f.other = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		f.mu.Lock()
		f.asked = append(f.asked, r.URL.Path+" "+r.Header.Get("Range")+" "+r.Header.Get("Authorization"))
		f.mu.Unlock()
		w.Header().Set("Content-Type", "audio/mpeg")
		http.ServeContent(w, r, "", time.Time{}, strings.NewReader(body))
	}))
	t.Cleanup(f.other.Close)
	f.origin = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if u, p, ok := r.BasicAuth(); !ok || u != user || p != pass {
			w.Header().Set("WWW-Authenticate", `Basic realm="private"`)
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		if r.URL.Path == "/redirect.mp3" {
			f.mu.Lock()
			f.walks++
			f.mu.Unlock()
			http.Redirect(w, r, f.other.URL+"/redirected.mp3", http.StatusFound)
			return
		}
		w.Header().Set("Content-Type", "application/rss+xml")
		item := func(n int, enclosure string) string {
			return fmt.Sprintf(`<item><title>Episode %d</title><guid isPermaLink="false">other-host-%d</guid>
<pubDate>%s</pubDate><enclosure url="%s" type="audio/mpeg" length="1000"/></item>`,
				n, n, time.Date(2026, 6, n, 8, 0, 0, 0, time.UTC).Format(time.RFC1123Z), enclosure)
		}
		fmt.Fprint(w, `<?xml version="1.0" encoding="UTF-8"?><rss version="2.0"><channel><title>Other Host Cast</title>`+
			item(1, f.other.URL+"/direct.mp3")+item(2, f.origin.URL+"/redirect.mp3")+`</channel></rss>`)
	}))
	t.Cleanup(f.origin.Close)
	return f
}

func (f *otherHostFeed) askedOf(path string) []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	var out []string
	for _, a := range f.asked {
		if strings.HasPrefix(a, path+" ") {
			out = append(out, a)
		}
	}
	return out
}

// A show's credentials go to its feed's own origin and nowhere else: an
// enclosure on another host is asked for without them, by the warm-up
// fetch and by the relay alike, and a redirect from the feed's origin to
// another host drops them on the way, while the origin itself still gets
// them.
func TestEnclosureCredentialsStayAtTheFeedsOrigin(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	f := newOtherHostFeed(t, "member", "s3cret")
	sub := decodeStatus[Subscription](t, h.postJSON(t, "/api/v1/podcasts", map[string]any{
		"url": f.origin.URL + "/feed.xml", "username": "member", "password": "s3cret",
	}), 201, "subscribe")
	episodes := map[string]EpisodeSummary{}
	for _, ep := range decode[EpisodePage](t, get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)).Items {
		episodes[ep.Title] = ep
	}
	for title, path := range map[string]string{"Episode 1": "/direct.mp3", "Episode 2": "/redirected.mp3"} {
		t.Run(title, func(t *testing.T) {
			info := decode[PlayInfo](t, get(t, h.ts, "/api/v1/items/"+episodes[title].Pid+"/play-info", h.token))
			waitFor2(t, func() bool { return len(f.askedOf(path)) > 0 })
			relayed := get(t, h.ts, info.Url, "")
			body, _ := io.ReadAll(relayed.Body)
			relayed.Body.Close()
			if relayed.StatusCode != http.StatusOK || len(body) == 0 {
				t.Fatalf("relay = %d with %d bytes", relayed.StatusCode, len(body))
			}
			asked := f.askedOf(path)
			warmed, streamed := false, false
			for _, a := range asked {
				if strings.HasSuffix(a, " ") {
					warmed = warmed || strings.Contains(a, "bytes=0-0")
					streamed = streamed || !strings.Contains(a, "bytes=")
					continue
				}
				t.Errorf("the other host was sent the show's credentials: %q", a)
			}
			if !warmed || !streamed {
				t.Errorf("the other host was asked %q, want the warm-up's one byte and the relay's whole episode", asked)
			}
		})
	}
	f.mu.Lock()
	walks := f.walks
	f.mu.Unlock()
	if walks < 2 {
		t.Errorf("the feed's origin was asked for its redirect with the credentials %d times, want the warm-up and the relay", walks)
	}
}

// The show's login rides every request made at the feed's own origin,
// whichever host sent it there: audio that a measurement prefix on another
// host sends back to the feed's host is asked for with it, and so is audio
// the feed's host reaches through another host by name, where Go drops it
// for the rest of the chain. The warm-up and the relay alike, and the other
// host never sees it.
func TestTheLoginRidesEveryHopAtTheFeedsOrigin(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	var mu sync.Mutex
	var audio, elsewhere []string // the login each ask of the feed's audio carried; what the other host was sent
	var feed, other *httptest.Server
	other = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		elsewhere = append(elsewhere, r.Header.Get("Authorization"))
		mu.Unlock()
		http.Redirect(w, r, feed.URL+"/audio.mp3", http.StatusFound)
	}))
	t.Cleanup(other.Close)
	feed = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		u, p, ok := r.BasicAuth()
		if r.URL.Path == "/audio.mp3" {
			mu.Lock()
			audio = append(audio, u+":"+p)
			mu.Unlock()
		}
		if !ok || u != "member" || p != "s3cret" {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		switch r.URL.Path {
		case "/audio.mp3":
			w.Header().Set("Content-Type", "audio/mpeg")
			fmt.Fprint(w, "ID3audio")
		case "/enclosure.mp3":
			// By another name for the same machine, which Go takes for
			// another host.
			http.Redirect(w, r, strings.Replace(other.URL, "127.0.0.1", "localhost", 1)+"/to-audio", http.StatusFound)
		default:
			item := func(n int, enclosure string) string {
				return fmt.Sprintf(`<item><title>Episode %d</title><guid isPermaLink="false">hop-%d</guid>
<pubDate>%s</pubDate><enclosure url="%s" type="audio/mpeg" length="1000"/></item>`,
					n, n, time.Date(2026, 6, n, 8, 0, 0, 0, time.UTC).Format(time.RFC1123Z), enclosure)
			}
			w.Header().Set("Content-Type", "application/rss+xml")
			fmt.Fprint(w, `<?xml version="1.0" encoding="UTF-8"?><rss version="2.0"><channel><title>Hop Cast</title>`+
				item(1, other.URL+"/to-audio")+item(2, feed.URL+"/enclosure.mp3")+`</channel></rss>`)
		}
	}))
	t.Cleanup(feed.Close)
	sub := decodeStatus[Subscription](t, h.postJSON(t, "/api/v1/podcasts", map[string]any{
		"url": feed.URL + "/feed.xml", "username": "member", "password": "s3cret",
	}), 201, "subscribe")
	asked := func() int {
		mu.Lock()
		defer mu.Unlock()
		return len(audio)
	}
	for _, ep := range decode[EpisodePage](t, get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)).Items {
		before := asked()
		info := decode[PlayInfo](t, get(t, h.ts, "/api/v1/items/"+ep.Pid+"/play-info", h.token))
		waitFor2(t, func() bool { return asked() > before })
		relayed := get(t, h.ts, info.Url, "")
		body, _ := io.ReadAll(relayed.Body)
		relayed.Body.Close()
		if relayed.StatusCode != http.StatusOK || string(body) != "ID3audio" {
			t.Errorf("relay of %s = %d %q, want the audio", ep.Title, relayed.StatusCode, body)
		}
	}
	mu.Lock()
	defer mu.Unlock()
	if len(audio) < 4 {
		t.Errorf("the feed's host was asked for the audio %d times, want each episode's warm-up and relay", len(audio))
	}
	for _, login := range audio {
		if login != "member:s3cret" {
			t.Errorf("the feed's host was asked for the audio with %q, want every ask with the show's login", audio)
			break
		}
	}
	for _, a := range elsewhere {
		if a != "" {
			t.Errorf("the other host was sent the show's credentials: %q", elsewhere)
			break
		}
	}
}

// Audio on another host that wants the show's login is refused there, the
// login going to the feed's own host alone, and the listener is told so
// and that fetching the episode plays it, whether the enclosure names
// that host or the feed's origin redirects to it. A refusal from the
// feed's own host still says the login may be wrong.
func TestALoginWantedOffTheFeedsOriginSaysSo(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	f := newOtherHostFeed(t, "member", "s3cret")
	f.other.Config.Handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if u, p, ok := r.BasicAuth(); !ok || u != "member" || p != "s3cret" {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		w.Header().Set("Content-Type", "audio/mpeg")
		fmt.Fprint(w, "ID3audio")
	})
	var own *httptest.Server
	own = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// The feed still takes the login and its audio no longer does,
		// as after the host changed what the audio asks for.
		if u, p, ok := r.BasicAuth(); !ok || u != "member" || p != "s3cret" || r.URL.Path != "/feed.xml" {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		w.Header().Set("Content-Type", "application/rss+xml")
		fmt.Fprint(w, `<?xml version="1.0" encoding="UTF-8"?><rss version="2.0"><channel><title>Own Host Cast</title>`+
			`<item><title>Episode 1</title><guid isPermaLink="false">own-host-1</guid>`+
			`<enclosure url="`+own.URL+`/audio.mp3" type="audio/mpeg" length="1000"/></item></channel></rss>`)
	}))
	t.Cleanup(own.Close)

	// relayed subscribes to feed with the login and answers what the relay
	// of each of its episodes said, by title.
	relayed := func(feed string) map[string]Error {
		t.Helper()
		sub := decodeStatus[Subscription](t, h.postJSON(t, "/api/v1/podcasts", map[string]any{
			"url": feed, "username": "member", "password": "s3cret",
		}), 201, "subscribe")
		out := map[string]Error{}
		for _, ep := range decode[EpisodePage](t, get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)).Items {
			info := decode[PlayInfo](t, get(t, h.ts, "/api/v1/items/"+ep.Pid+"/play-info", h.token))
			out[ep.Title] = decodeStatus[Error](t, get(t, h.ts, info.Url, ""), http.StatusBadGateway, "relaying "+ep.Title)
		}
		return out
	}
	elsewhere := "the episode's audio host wants the show's login, which this server sends only to the feed's own host; fetch the episode to play it"
	other := relayed(f.origin.URL + "/feed.xml")
	for _, title := range []string{"Episode 1", "Episode 2"} {
		if got := other[title]; got.Code != "feed-unreachable" || got.Message != elsewhere {
			t.Errorf("%s on the other host = %+v, want feed-unreachable saying where the login goes", title, got)
		}
	}
	if got := relayed(own.URL + "/feed.xml")["Episode 1"]; got.Code != "feed-unreachable" ||
		got.Message != "the podcast host refused this episode's credentials; refresh the feed or check the show's login" {
		t.Errorf("audio the feed's own host refuses = %+v, want the login blamed", got)
	}
}
