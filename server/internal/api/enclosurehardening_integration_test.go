package api

import (
	"io"
	"net/http"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/auth"
)

// relayAs fetches a relay URL with a method and an optional range, and
// answers the response with its body read whole.
func relayAs(t *testing.T, h *harness, method, url, rangeHeader string) (*http.Response, []byte) {
	t.Helper()
	req, err := http.NewRequest(method, h.ts.URL+url, nil)
	if err != nil {
		t.Fatal(err)
	}
	if rangeHeader != "" {
		req.Header.Set("Range", rangeHeader)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	body, err := io.ReadAll(resp.Body)
	resp.Body.Close()
	if err != nil {
		t.Fatal(err)
	}
	return resp, body
}

// typedEpisode subscribes to a typed host's feed and answers its one
// episode's pid and its relay URL from play-info.
func typedEpisode(t *testing.T, h *harness, feedURL string) (pid, relay string) {
	t.Helper()
	sub := decodeStatus[Subscription](t, h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feedURL}), 201, "subscribe")
	ep := decode[EpisodePage](t, get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)).Items[0]
	info := decode[PlayInfo](t, get(t, h.ts, "/api/v1/items/"+ep.Pid+"/play-info", h.token))
	return ep.Pid, info.Url
}

// Every answer the relay gives carries the media hardening, whatever its
// status: the bytes and the refusals alike come from this origin. A
// range to a host serving a page is refused whole, none of it relayed.
func TestEveryRelayedAnswerIsHardened(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	const audio = "ID3fake-mpeg-audio-bytes-for-the-relay"
	const page = "<!doctype html><html><script>alert(1)</script></html>"
	_, audioRelay := typedEpisode(t, h, typedEnclosureHost(t, "audio/mpeg", "audio/mpeg", audio))
	_, pageRelay := typedEpisode(t, h, typedEnclosureHost(t, "audio/mpeg", "text/html; charset=utf-8", page))
	for _, c := range []struct {
		name, relay, method, rng string
		status                   int
	}{
		{"a range of audio", audioRelay, http.MethodGet, "bytes=3-6", http.StatusPartialContent},
		{"a HEAD of audio", audioRelay, http.MethodHead, "", http.StatusOK},
		{"a ranged HEAD of audio", audioRelay, http.MethodHead, "bytes=0-1", http.StatusPartialContent},
		{"a range past the end", audioRelay, http.MethodGet, "bytes=9999-", http.StatusRequestedRangeNotSatisfiable},
		{"a range of a page", pageRelay, http.MethodGet, "bytes=0-20", http.StatusBadGateway},
		{"a HEAD of a page", pageRelay, http.MethodHead, "", http.StatusBadGateway},
	} {
		resp, body := relayAs(t, h, c.method, c.relay, c.rng)
		if resp.StatusCode != c.status {
			t.Errorf("%s = %d, want %d", c.name, resp.StatusCode, c.status)
		}
		if got := resp.Header.Get("X-Content-Type-Options"); got != "nosniff" {
			t.Errorf("%s: X-Content-Type-Options = %q, want nosniff", c.name, got)
		}
		if got := resp.Header.Get("Content-Security-Policy"); got != "default-src 'none'; sandbox" {
			t.Errorf("%s: Content-Security-Policy = %q", c.name, got)
		}
		if strings.Contains(string(body), "<script>") || strings.Contains(string(body), "html>") {
			t.Errorf("%s relayed the page: %s", c.name, body)
		}
		if c.status == http.StatusPartialContent && c.method == http.MethodGet && string(body) != audio[3:7] {
			t.Errorf("%s = %q, want %q", c.name, body, audio[3:7])
		}
	}
}

// A request for several ranges goes up as one for the whole episode,
// which a server may always answer: the listener gets audio rather than
// a host's multipart answer, which the gate could not vouch for.
func TestAMultiRangeRequestIsRelayedWhole(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	const audio = "ID3fake-mpeg-audio-bytes-for-the-relay"
	_, relay := typedEpisode(t, h, typedEnclosureHost(t, "audio/mpeg", "audio/mpeg", audio))
	resp, body := relayAs(t, h, http.MethodGet, relay, "bytes=0-4,10-14")
	if resp.StatusCode != http.StatusOK || string(body) != audio {
		t.Errorf("a multi-range relay = %d: %q", resp.StatusCode, body)
	}
	if got := resp.Header.Get("Content-Type"); got != "audio/mpeg" {
		t.Errorf("Content-Type = %q, want audio/mpeg", got)
	}
}

// A refused answer is not remembered as where the episode lives, by the
// warm that walks the chain ahead of the listener or by the relay: the
// next listener asks the feed's own URL again.
func TestARefusedRouteIsNotRemembered(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	feed := typedEnclosureHost(t, "audio/mpeg", "text/html; charset=utf-8", "<!doctype html><p>parked</p>")
	pid, relay := typedEpisode(t, h, feed)
	enclosure := strings.TrimSuffix(feed, "/feed.xml") + "/episode"
	waitForWarm(t, h)
	if got, ok := h.srv.enclosures.lookup(pid, enclosure); ok {
		t.Errorf("the warm remembered a route the relay refuses: %s", got)
	}
	if resp, _ := relayAs(t, h, http.MethodGet, relay, ""); resp.StatusCode != http.StatusBadGateway {
		t.Fatalf("relay = %d, want 502", resp.StatusCode)
	}
	if got, ok := h.srv.enclosures.lookup(pid, enclosure); ok {
		t.Errorf("the refused route is remembered: %s", got)
	}
}

// A remembered chain end that starts answering a page is a remembered
// URL gone wrong like any other: the relay drops it and walks the chain
// once, and the listener gets the episode where the chain ends now.
func TestARememberedEndThatTurnsIntoAPageIsWalkedPast(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	cf := newChainFeed(t)
	var paged atomic.Bool
	chain := cf.ts.Config.Handler
	cf.ts.Config.Handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if paged.Load() && r.URL.Path == "/edge/1/episode.mp3" {
			w.Header().Set("Content-Type", "text/html; charset=utf-8")
			io.WriteString(w, "<!doctype html><p>this link has expired</p>")
			return
		}
		chain.ServeHTTP(w, r)
	})
	pid := chainEpisode(t, h, cf)
	info := decode[PlayInfo](t, get(t, h.ts, "/api/v1/items/"+pid+"/play-info", h.token))
	if got := warmedRoute(t, h, pid, cf.enclosureURL()); !strings.HasSuffix(got, "/edge/1/episode.mp3") {
		t.Fatalf("the warm remembered %q, want the first edge", got)
	}
	paged.Store(true)
	cf.rotateEdge()

	resp, body := relayAs(t, h, http.MethodGet, info.Url, "")
	if resp.StatusCode != http.StatusOK || !strings.HasPrefix(string(body), "waxdeck-episode-bytes.") {
		t.Fatalf("relay after the end turned into a page = %d: %.80s", resp.StatusCode, body)
	}
	if got := warmedRoute(t, h, pid, cf.enclosureURL()); !strings.HasSuffix(got, "/edge/2/episode.mp3") {
		t.Errorf("the route now ends at %q, want the second edge", got)
	}
}

// A YouTube show's episode never relays, whichever way a client asks:
// play-info refuses it as not fetched, and the relay refuses a token
// minted for it.
func TestAYouTubeEpisodeNeverRelays(t *testing.T) {
	t.Parallel()
	h := newWatchPageHarness(t)
	_, video := firstEpisode(t, h, "https://www.youtube.com/@watchpages", map[string]any{"sourceType": "youtube"})
	if video.HasEnclosure != nil && *video.HasEnclosure {
		t.Error("the video's row says it has audio to relay")
	}
	resp := get(t, h.ts, "/api/v1/items/"+video.Pid+"/play-info", h.token)
	body, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != http.StatusConflict || !strings.Contains(string(body), `"conflict"`) {
		t.Errorf("play-info = %d: %s", resp.StatusCode, body)
	}
	token, _ := h.media.MintFor(auth.MediaClaims{User: adminUserID(t, h), Purpose: auth.PurposeEnclosure, PID: video.Pid}, time.Minute)
	if resp, body := relayAs(t, h, http.MethodGet, enclosureURL(video.Pid, token), ""); resp.StatusCode != http.StatusNotFound {
		t.Errorf("the relay with a minted token = %d: %s", resp.StatusCode, body)
	}
}
