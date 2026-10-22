package service

import (
	"context"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
)

// A synced playlist's cover is fetched over https at every hop: a
// redirect to plain http is refused before anything is asked of it.
func TestASyncedCoverNeverLeavesHTTPS(t *testing.T) {
	t.Parallel()
	var plainAsked atomic.Int32
	plain := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		plainAsked.Add(1)
		w.Header().Set("Content-Type", "image/png")
		w.Write([]byte("\x89PNG\r\n\x1a\n"))
	}))
	t.Cleanup(plain.Close)
	secure := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/hop" {
			http.Redirect(w, r, "/cover.png", http.StatusFound)
			return
		}
		if r.URL.Path == "/cover.png" {
			w.Header().Set("Content-Type", "image/png")
			w.Write([]byte("\x89PNG\r\n\x1a\n"))
			return
		}
		http.Redirect(w, r, plain.URL+"/cover.png", http.StatusFound)
	}))
	t.Cleanup(secure.Close)
	l := &Library{log: slog.New(slog.DiscardHandler)}
	l.transcriptHTTPOnce.Do(func() { l.transcriptHTTP = secure.Client() })
	ctx := context.Background()

	if raw, _, err := l.fetchSyncedCoverImage(ctx, secure.URL+"/downgrade"); err == nil {
		t.Errorf("a redirect to http gave a cover of %d bytes", len(raw))
	}
	if n := plainAsked.Load(); n != 0 {
		t.Errorf("the plain-http host was asked %d times", n)
	}
	if raw, mime, err := l.fetchSyncedCoverImage(ctx, secure.URL+"/hop"); err != nil || mime != "image/png" || len(raw) == 0 {
		t.Errorf("an https redirect = %d bytes of %q (%v), want the cover", len(raw), mime, err)
	}
}
