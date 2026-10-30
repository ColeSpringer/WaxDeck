package api

import (
	"bytes"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// A podcast host that refuses clients that do not say who they are
// (Buzzsprout answers a bare Go client 403) still serves this server:
// the catalog's own feed client, the transcript display fetch and the
// enclosure relay all name it.
func TestOutboundRequestsNameTheServer(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	feed := newFeedServer(t, 1)
	files := http.FileServer(http.Dir(feed.dir))
	var mu sync.Mutex
	refused := map[string]string{}
	feed.ts.Config.Handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		agent := r.Header.Get("User-Agent")
		if !strings.HasPrefix(agent, "WaxDeck/") {
			mu.Lock()
			refused[r.URL.Path] = agent
			mu.Unlock()
			http.Error(w, "say who you are", http.StatusForbidden)
			return
		}
		files.ServeHTTP(w, r)
	})

	sub := decodeStatus[Subscription](t, h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()}), 201, "subscribe")
	ep := decode[EpisodePage](t, get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)).Items[0]

	tx := get(t, h.ts, "/api/v1/episodes/"+ep.Pid+"/transcript", h.token)
	body, _ := io.ReadAll(tx.Body)
	tx.Body.Close()
	if tx.StatusCode != 200 || !strings.Contains(string(body), "General fixture") {
		t.Errorf("transcript display = %d: %s", tx.StatusCode, body)
	}

	info := decode[PlayInfo](t, get(t, h.ts, "/api/v1/items/"+ep.Pid+"/play-info", h.token))
	relayed := get(t, h.ts, info.Url, "")
	audio, _ := io.ReadAll(relayed.Body)
	relayed.Body.Close()
	if relayed.StatusCode != 200 || len(audio) == 0 {
		t.Errorf("enclosure relay = %d with %d bytes", relayed.StatusCode, len(audio))
	}

	mu.Lock()
	defer mu.Unlock()
	for path, agent := range refused {
		t.Errorf("%s was asked for as %q", path, agent)
	}
}

// A station host that refuses clients that do not say who they are still
// streams through the proxy: the station's own address, and the stream a
// playlist at it names, are each asked for as this server.
func TestRadioStreamProxyNamesTheServer(t *testing.T) {
	t.Parallel()
	h := newHarnessWith(t, func(cfg *service.Config) { cfg.AllowPrivateRadioHosts = true })
	payload := bytes.Repeat([]byte("named-stream."), 256)
	var mu sync.Mutex
	refused := map[string]string{}
	station := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if agent := r.Header.Get("User-Agent"); !strings.HasPrefix(agent, "WaxDeck/") {
			mu.Lock()
			refused[r.URL.Path] = agent
			mu.Unlock()
			http.Error(w, "say who you are", http.StatusForbidden)
			return
		}
		switch r.URL.Path {
		case "/stream":
			w.Header().Set("Content-Type", "audio/mpeg")
			w.Write(payload)
		case "/list.m3u":
			w.Header().Set("Content-Type", "audio/x-mpegurl")
			fmt.Fprintf(w, "#EXTM3U\nhttp://%s/stream\n", r.Host)
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(station.Close)

	for _, path := range []string{"/stream", "/list.m3u"} {
		st := decodeStatus[RadioStation](t, h.postJSON(t, "/api/v1/radio/stations", map[string]any{
			"name": "Named FM " + path, "streamUrl": station.URL + path,
		}), 201, "creating a station")
		pi := decode[RadioPlayInfo](t, get(t, h.ts, "/api/v1/radio/stations/"+st.Pid+"/play-info", h.token))
		resp := get(t, h.ts, pi.Url, "")
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		if resp.StatusCode != 200 || !bytes.Equal(body, payload) {
			t.Errorf("%s: the proxied stream = %d with %d bytes, want 200 with the station's %d", path, resp.StatusCode, len(body), len(payload))
		}
	}

	mu.Lock()
	defer mu.Unlock()
	for path, agent := range refused {
		t.Errorf("%s was asked for as %q", path, agent)
	}
}
