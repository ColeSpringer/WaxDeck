package service

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"sync"
	"testing"
)

// Every podcast request names this server's build, the catalog's
// (subscribing, syncing, downloading an episode) and WaxDeck's own
// (capturing a transcript, which reads as the transcript read does).
func TestEveryPodcastRequestNamesTheServer(t *testing.T) {
	t.Parallel()
	var mu sync.Mutex
	seen := map[string][]string{}
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		seen[r.URL.Path] = append(seen[r.URL.Path], r.UserAgent())
		mu.Unlock()
		switch {
		case strings.HasSuffix(r.URL.Path, ".mp3"):
			w.Header().Set("Content-Type", "audio/mpeg")
			w.Write([]byte("ID3\x04\x00\x00\x00\x00\x00\x00"))
		case strings.HasSuffix(r.URL.Path, ".vtt"):
			w.Header().Set("Content-Type", "text/vtt")
			fmt.Fprint(w, "WEBVTT\n\n00:00.000 --> 00:01.000\nHello there.\n")
		default:
			w.Header().Set("Content-Type", "application/rss+xml")
			fmt.Fprintf(w, `<?xml version="1.0"?><rss version="2.0" xmlns:podcast="https://podcastindex.org/namespace/1.0"><channel><title>Agent Show</title>
<item><title>One</title><guid>agent-1</guid><enclosure url="http://%[1]s/one.mp3" type="audio/mpeg" length="10"/>
<podcast:transcript url="http://%[1]s/one.vtt" type="text/vtt"/></item>
</channel></rss>`, r.Host)
		}
	}))
	t.Cleanup(ts.Close)
	dir := t.TempDir()
	ctx, svc, uc, _ := openServiceAt(t, dir, func(cfg *Config) {
		cfg.PodcastDir = filepath.Join(dir, "podcasts")
		cfg.PodcastRootName = "podcasts"
		cfg.AllowPrivateFeedHosts = true
		cfg.Version = "9.9.9"
	})
	sub, _, err := svc.Subscribe(ctx, uc, SubscribeRequest{URL: ts.URL + "/feed.xml"})
	if err != nil {
		t.Fatal(err)
	}
	eps, _, err := svc.Episodes(ctx, uc, sub.Show.PID, "", 10)
	if err != nil || len(eps) != 1 {
		t.Fatalf("episodes = %+v (%v), want one", eps, err)
	}
	if err := svc.CaptureEpisodeTranscript(ctx, uc, eps[0].PID); err != nil {
		t.Fatalf("capturing the transcript: %v", err)
	}
	_, bare, _ := parseAPIPID(sub.Show.PID)
	if _, err := svc.syncShow(ctx, bare, syncOwn); err != nil {
		t.Fatalf("syncing: %v", err)
	}
	if err := svc.QueueEpisodeFetch(ctx, uc, eps[0].PID); err != nil {
		t.Fatal(err)
	}
	svc.DrainFetchQueue(ctx)

	want := svc.UserAgent()
	mu.Lock()
	defer mu.Unlock()
	for path, what := range map[string]string{
		"/feed.xml": "a subscribe and a sync",
		"/one.vtt":  "a transcript capture",
		"/one.mp3":  "an episode download",
	} {
		if len(seen[path]) == 0 {
			t.Errorf("%s asked for nothing", what)
		}
		for _, got := range seen[path] {
			if got != want {
				t.Errorf("%s sent %q, want %q", what, got, want)
			}
		}
	}
}

// The podcast directory is asked as this build too.
func TestThePodcastDirectoryIsAskedAsTheServer(t *testing.T) {
	t.Parallel()
	agents := make(chan string, 1)
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		select {
		case agents <- r.UserAgent():
		default:
		}
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprint(w, `{"resultCount":0,"results":[]}`)
	}))
	t.Cleanup(ts.Close)
	l := &Library{version: "9.9.9", podcastDirectoryBase: ts.URL, log: slog.New(slog.DiscardHandler)}
	l.SearchPodcastDirectory(context.Background(), "jazz", 5)
	select {
	case got := <-agents:
		if want := l.UserAgent(); got != want {
			t.Errorf("the directory was asked as %q, want %q", got, want)
		}
	default:
		t.Fatal("the directory was not asked")
	}
}
