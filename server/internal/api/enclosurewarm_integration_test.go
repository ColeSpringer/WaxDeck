package api

import (
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"
)

// waitForWarm waits out the background resolves play-info starts. A warm
// is a supervised worker, so it is over when its place in the
// single-flight table is given back.
func waitForWarm(t *testing.T, h *harness) {
	t.Helper()
	waitFor2(t, func() bool {
		h.srv.enclosures.mu.Lock()
		defer h.srv.enclosures.mu.Unlock()
		return len(h.srv.enclosures.warming) == 0
	})
}

// A play of an episode whose host answers a page costs the host two
// requests on one connection: the warm that walks the chain ahead of the
// listener, and the listener's own walk, which has no remembered end to
// try first because the warm remembers nothing the relay would refuse.
func TestAHostAnsweringAPageIsAskedTwicePerPlayOnOneConnection(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	var asked, connections atomic.Int64
	var ts *httptest.Server
	mux := http.NewServeMux()
	mux.HandleFunc("/feed.xml", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel>
<title>Parked Cast</title>
<description>One episode.</description>
<item>
	<title>Parked Episode</title>
	<guid isPermaLink="false">parked-1</guid>
	<pubDate>%s</pubDate>
	<enclosure url="%s/episode" type="audio/mpeg" length="1000"/>
</item>
</channel></rss>`, time.Date(2026, 6, 1, 8, 0, 0, 0, time.UTC).Format(time.RFC1123Z), ts.URL)
	})
	mux.HandleFunc("/episode", func(w http.ResponseWriter, r *http.Request) {
		asked.Add(1)
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		fmt.Fprint(w, "<!doctype html><p>this domain is parked</p>")
	})
	ts = httptest.NewUnstartedServer(mux)
	ts.Config.ConnState = func(_ net.Conn, state http.ConnState) {
		if state == http.StateNew {
			connections.Add(1)
		}
	}
	ts.Start()
	t.Cleanup(ts.Close)

	_, ep := firstEpisode(t, h, ts.URL+"/feed.xml", nil)
	before := connections.Load()
	relay := decode[PlayInfo](t, get(t, h.ts, "/api/v1/items/"+ep.Pid+"/play-info", h.token)).Url
	waitForWarm(t, h)
	if resp, _ := relayAs(t, h, http.MethodGet, relay, ""); resp.StatusCode != http.StatusBadGateway {
		t.Fatalf("relay = %d, want the refusal", resp.StatusCode)
	}
	if got := asked.Load(); got != 2 {
		t.Errorf("the host was asked for the episode %d times, want 2", got)
	}
	if got := connections.Load() - before; got != 1 {
		t.Errorf("the host took %d connections for the play, want the warm's reused by the walk", got)
	}
	if route, ok := h.srv.enclosures.lookup(ep.Pid, ts.URL+"/episode"); ok {
		t.Errorf("a route the relay refuses was remembered: %s", route)
	}
}
