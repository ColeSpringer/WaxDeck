package api

import (
	"context"
	"io"
	"net/http"
	"strings"
	"sync/atomic"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// countingSources counts each lookup the download route makes.
type countingSources struct {
	downloadSources
	lookups atomic.Int32
}

func (c *countingSources) StreamDownloadSource(ctx context.Context, pid, f string) (flow.Source, service.DownloadFile, error) {
	c.lookups.Add(1)
	return c.downloadSources.StreamDownloadSource(ctx, pid, f)
}

func (c *countingSources) DownloadSource(ctx context.Context, pid, f string) (service.DownloadFile, error) {
	c.lookups.Add(1)
	return c.downloadSources.DownloadSource(ctx, pid, f)
}

// A fetch of the download route looks its file up once: a stream token's
// play of the original while the engine is away, and every seek in it,
// checks that the token is for the original's bytes against the same
// lookup it serves them from.
func TestTheDownloadRouteLooksItsFileUpOnce(t *testing.T) {
	t.Parallel()
	h := newHarnessDirect(t)
	pid := h.items(t, "?limit=1").Items[0].Pid
	pi := decode[PlayInfo](t, get(t, h.ts, "/api/v1/items/"+pid+"/play-info", h.token))
	if !strings.HasPrefix(pi.Url, "/media/download?") {
		t.Fatalf("engine-less play-info = %s, want the download route", pi.Url)
	}
	info := decode[DownloadInfo](t, get(t, h.ts, "/api/v1/items/"+pid+"/download-info", h.token))
	counted := &countingSources{downloadSources: h.srv.sources}
	h.srv.sources = counted
	for _, tc := range []struct{ name, url, rng string }{
		{"a stream token's play", pi.Url, ""},
		{"a stream token's seek", pi.Url, "bytes=4-"},
		{"a download token's fetch", info.Files[0].Url, ""},
	} {
		counted.lookups.Store(0)
		req, err := http.NewRequest("GET", h.ts.URL+tc.url, nil)
		if err != nil {
			t.Fatal(err)
		}
		if tc.rng != "" {
			req.Header.Set("Range", tc.rng)
		}
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		io.Copy(io.Discard, resp.Body)
		resp.Body.Close()
		if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusPartialContent {
			t.Fatalf("%s = %d", tc.name, resp.StatusCode)
		}
		if n := counted.lookups.Load(); n != 1 {
			t.Errorf("%s looked its file up %d times, want once", tc.name, n)
		}
	}
}
