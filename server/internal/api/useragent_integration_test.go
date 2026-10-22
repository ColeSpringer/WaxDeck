package api

import (
	"io"
	"net/http"
	"strings"
	"sync"
	"testing"
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
