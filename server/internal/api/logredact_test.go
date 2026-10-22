package api

import (
	"errors"
	"log/slog"
	"strings"
	"sync"
	"testing"
)

type lineBuffer struct {
	mu  sync.Mutex
	buf strings.Builder
}

func (b *lineBuffer) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.Write(p)
}

func (b *lineBuffer) String() string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.String()
}

// The API's lines keep a web address's host and nothing after it, as the
// service's do: an error it logs can repeat a feed's tokenized address.
func TestTheAPIsLogKeepsHostsOnly(t *testing.T) {
	t.Parallel()
	var logged lineBuffer
	srv := NewServer("test", Options{Logger: slog.New(slog.NewTextHandler(&logged, nil))})
	srv.log.Warn("a request failed during catalog maintenance", "path", "/api/v1/podcasts",
		"err", errors.New(`Get "https://host.example/feed?auth=SECRET": dial tcp: refused`))
	if out := logged.String(); strings.Contains(out, "SECRET") || !strings.Contains(out, "https://host.example") {
		t.Fatalf("log = %q, want the host and no query", out)
	}
}
