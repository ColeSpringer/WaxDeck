package service

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"sync"
	"testing"
)

// Every request the server makes on its own behalf names the server: the
// station directory, a station's logo and its page, and the cover a
// synced playlist borrows.
func TestOutboundRequestsCarryTheAgent(t *testing.T) {
	t.Parallel()
	var mu sync.Mutex
	seen := map[string]string{}
	record := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		seen[r.URL.Path] = r.UserAgent()
		mu.Unlock()
		if r.URL.Path == "/station" {
			w.Header().Set("Content-Type", "text/html")
			io.WriteString(w, "<html></html>")
			return
		}
		w.Header().Set("Content-Type", "image/png")
		w.Write([]byte("\x89PNG\r\n\x1a\n"))
	})
	plain := httptest.NewServer(record)
	t.Cleanup(plain.Close)
	secure := httptest.NewTLSServer(record)
	t.Cleanup(secure.Close)
	l := bareLibrary(&core{log: slog.New(slog.DiscardHandler)})
	l.version = "9.9.9"
	l.Radio.allowPrivateRadioHosts = true
	l.Podcasts.transcriptHTTPOnce.Do(func() { l.Podcasts.transcriptHTTP = secure.Client() })

	ctx := context.Background()
	l.Radio.fetchRadioDirectory(ctx, plain.URL, "jazz", 5)
	l.Radio.fetchRadioLogo(ctx, plain.URL+"/logo.png")
	page, err := url.Parse(plain.URL + "/station")
	if err != nil {
		t.Fatal(err)
	}
	l.Radio.declaredIcons(ctx, page)
	l.Playlists.fetchSyncedCoverImage(ctx, secure.URL+"/cover.png")

	want := l.UserAgent()
	for path, what := range map[string]string{
		"/json/stations/search": "the station directory",
		"/logo.png":             "a station logo",
		"/station":              "a station's page",
		"/cover.png":            "a synced playlist's cover",
	} {
		if got := seen[path]; got != want {
			t.Errorf("%s sent %q, want %q", what, got, want)
		}
	}
}
