package api

import (
	"bytes"
	"log/slog"
	"net/http"
	"strings"
	"sync"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// logLines is a log sink a test reads while the server writes to it.
type logLines struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (l *logLines) Write(p []byte) (int, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.buf.Write(p)
}

func (l *logLines) String() string {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.buf.String()
}

// A refused answer's label is logged for the operator cut to its start:
// the host chooses it, and any listener can make the relay log it.
func TestARefusedLabelIsLoggedCutShort(t *testing.T) {
	t.Parallel()
	var logged logLines
	h := newPodcastHarnessWith(t, func(cfg *service.Config) {
		cfg.Logger = slog.New(slog.NewTextHandler(&logged, nil))
	})
	feed := typedEnclosureHost(t, "audio/mpeg", "text/html; filler="+strings.Repeat("y", 4000), "<html></html>")
	sub := decodeStatus[Subscription](t, h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed}), 201, "subscribe")
	ep := decode[EpisodePage](t, get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)).Items[0]
	info := decode[PlayInfo](t, get(t, h.ts, "/api/v1/items/"+ep.Pid+"/play-info", h.token))
	resp := get(t, h.ts, info.Url, "")
	resp.Body.Close()
	if resp.StatusCode != http.StatusBadGateway {
		t.Fatalf("relay = %d, want the refusal", resp.StatusCode)
	}
	var line string
	for _, l := range strings.Split(logged.String(), "\n") {
		if strings.Contains(l, "something other than audio") {
			line = l
		}
	}
	if !strings.Contains(line, "text/html; filler=yyy") || strings.Contains(line, strings.Repeat("y", 100)) {
		t.Errorf("refusal line = %q (%d bytes), want the label cut to its start", line, len(line))
	}
}
