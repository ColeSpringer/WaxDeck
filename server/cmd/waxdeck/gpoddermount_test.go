package main

import (
	"context"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// Mounting the gpodder surface serves it and runs the retries of the feeds
// its devices parked, whatever else the server runs.
func TestTheGpodderSurfaceRetriesItsParkedFeeds(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	group := supervise.NewGroup(slog.New(slog.DiscardHandler))
	t.Cleanup(func() {
		cancel()
		group.Wait()
	})
	mux := http.NewServeMux()
	served := make(chan string, 1)
	surface := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { served <- r.URL.Path })
	retried := make(chan struct{}, 1)
	mountGpodder(ctx, mux, group, surface, func(context.Context) {
		select {
		case retried <- struct{}{}:
		default:
		}
	}, time.Millisecond)
	select {
	case <-retried:
	case <-time.After(5 * time.Second):
		t.Fatal("the parked feeds were never retried")
	}
	for _, path := range []string{"/api/2/devices/alice.json", "/subscriptions/alice.json"} {
		mux.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, path, nil))
		select {
		case got := <-served:
			if got != path {
				t.Errorf("the surface served %s for %s", got, path)
			}
		default:
			t.Errorf("%s did not reach the gpodder surface", path)
		}
	}
}
