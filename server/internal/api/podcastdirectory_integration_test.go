package api

import (
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// The directory is a public internet service, so every case here runs
// against a fake exactly as the radio directory's tests do.
func TestPodcastDirectorySearch(t *testing.T) {
	const body = `{"resultCount":3,"results":[
	  {"collectionName":"Song Exploder","artistName":"Hrishikesh Hirway",
	   "feedUrl":"https://feeds.example/song-exploder",
	   "artworkUrl600":"https://art.example/600.jpg",
	   "artworkUrl100":"https://art.example/100.jpg",
	   "primaryGenreName":"Music","trackCount":42},
	  {"collectionName":"No Feed Here","artistName":"Nobody",
	   "primaryGenreName":"Music","trackCount":7},
	  {"artistName":"Nameless","feedUrl":"https://feeds.example/nameless"}
	]}`

	var gotQuery url.Values
	directory := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotQuery = r.URL.Query()
		w.Header().Set("Content-Type", "application/json")
		io.WriteString(w, body)
	}))
	t.Cleanup(directory.Close)

	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.PodcastDirectoryBase = directory.URL
	})

	resp := get(t, h.ts, "/api/v1/podcasts/directory?query=song+exploder", h.token)
	if resp.StatusCode != 200 {
		b, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		t.Fatalf("directory status = %d (%s)", resp.StatusCode, b)
	}
	res := decode[PodcastDirectoryResults](t, resp)

	// The rows with no feed URL and no name are both dropped: neither
	// can be subscribed to, so neither is a result.
	if len(res.Entries) != 1 {
		t.Fatalf("entries = %d, want 1 (rows without a name or feed URL are dropped)", len(res.Entries))
	}
	e := res.Entries[0]
	if e.Name != "Song Exploder" || e.FeedUrl != "https://feeds.example/song-exploder" {
		t.Fatalf("entry = %+v", e)
	}
	if e.Author == nil || *e.Author != "Hrishikesh Hirway" {
		t.Fatalf("entry author = %+v", e.Author)
	}
	// The larger artwork wins when the directory lists both.
	if e.ArtworkUrl == nil || *e.ArtworkUrl != "https://art.example/600.jpg" {
		t.Fatalf("entry artwork = %+v, want the 600px variant", e.ArtworkUrl)
	}
	if e.Genre == nil || *e.Genre != "Music" {
		t.Fatalf("entry genre = %+v", e.Genre)
	}
	if e.EpisodeCount == nil || *e.EpisodeCount != 42 {
		t.Fatalf("entry episode count = %+v", e.EpisodeCount)
	}
	if gotQuery.Get("entity") != "podcast" || gotQuery.Get("term") != "song exploder" {
		t.Fatalf("upstream query = %v, want a podcast-entity term search", gotQuery)
	}

	// A feed URL is what makes a match subscribable, so the whole point
	// of the endpoint is that posting one back subscribes.
	if resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{
		"url": e.FeedUrl,
	}); resp.StatusCode != 502 && resp.StatusCode != 201 && resp.StatusCode != 200 {
		// feeds.example does not resolve, so an unreachable feed is the
		// expected answer; what matters is that it is the feed layer
		// answering and not a rejected request shape.
		b, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		t.Fatalf("subscribing to a directory feed URL = %d (%s)", resp.StatusCode, b)
	}
}

// A throttle is the directory refusing this server's rate, which is a
// busy directory rather than a broken WaxDeck. Untranslated it would
// reach the client as a 500.
func TestPodcastDirectoryThrottleIsDirectoryUnavailable(t *testing.T) {
	directory := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusTooManyRequests)
	}))
	t.Cleanup(directory.Close)

	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.PodcastDirectoryBase = directory.URL
	})

	resp := get(t, h.ts, "/api/v1/podcasts/directory?query=throttled", h.token)
	if resp.StatusCode != 502 {
		b, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		t.Fatalf("throttled directory status = %d, want 502 (%s)", resp.StatusCode, b)
	}
	if e := decode[Error](t, resp); e.Code != "directory-unavailable" {
		t.Fatalf("throttled directory code = %q, want directory-unavailable", e.Code)
	}
}

func TestPodcastDirectoryUnreachableIsTyped(t *testing.T) {
	directory := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {}))
	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.PodcastDirectoryBase = directory.URL
	})
	directory.Close()

	resp := get(t, h.ts, "/api/v1/podcasts/directory?query=unreachable", h.token)
	if resp.StatusCode != 502 {
		t.Fatalf("unreachable directory status = %d, want 502", resp.StatusCode)
	}
	if e := decode[Error](t, resp); e.Code != "directory-unavailable" {
		t.Fatalf("unreachable directory code = %q, want directory-unavailable", e.Code)
	}
}
