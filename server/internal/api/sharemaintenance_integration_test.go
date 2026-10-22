package api

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin/proxy"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// handOffClient dials the catalog's admin socket the way the CLI does,
// wherever the service put it: beside the catalog, or under the runtime
// or temp dir when that path is too long for a socket.
func handOffClient(t *testing.T, dataDir string) *proxy.Client {
	t.Helper()
	abs, err := filepath.Abs(dataDir)
	if err != nil {
		t.Fatal(err)
	}
	sum := sha256.Sum256([]byte(abs))
	dir := "waxdeck-" + hex.EncodeToString(sum[:8])
	candidates := []string{filepath.Join(dataDir, service.SocketFileName)}
	for _, base := range []string{os.Getenv("XDG_RUNTIME_DIR"), os.TempDir()} {
		if base != "" {
			candidates = append(candidates, filepath.Join(base, dir, service.SocketFileName))
		}
	}
	for deadline := time.Now().Add(5 * time.Second); ; {
		for _, path := range candidates {
			if c, err := proxy.Dial(path); err == nil {
				t.Cleanup(func() { c.Close() })
				return c
			}
		}
		if time.Now().After(deadline) {
			t.Fatalf("no catalog socket at any of %v", candidates)
		}
		time.Sleep(10 * time.Millisecond)
	}
}

// While the catalog is handed off, a link's routes say it is away, which
// a player retries, rather than that the link does not exist, which it
// does not; a link that is really gone stays gone, and the rest play
// again once the hand-off ends.
func TestAShareSaysWhenTheCatalogIsAway(t *testing.T) {
	t.Parallel()
	var dataDir string
	h := newPodcastHarnessWith(t, func(cfg *service.Config) { dataDir = cfg.DataDir })
	_, ep := firstEpisode(t, h, newFeedServer(t, 1).feedURL(), nil)
	track := h.items(t, "?mediaType=music").Items[0]
	episode := shareOf(t, h, ep.Pid, nil)
	file := shareOf(t, h, track.Pid, map[string]any{"allowDownload": true})
	gone := shareOf(t, h, track.Pid, nil)
	wantStatus(t, h.deleteReq(t, "/api/v1/shares/"+gone.Pid), 204, "revoking one link")

	ctx := context.Background()
	c := handOffClient(t, dataDir)
	if err := c.MaintenanceBegin(ctx); err != nil {
		t.Fatal(err)
	}
	handedOff := true
	t.Cleanup(func() {
		if handedOff {
			c.MaintenanceEnd(ctx)
		}
	})

	for _, route := range []string{
		episode.Url + "/stream?i=0",
		file.Url + "/stream?i=0",
		file.Url + "/download?i=0",
		file.Url + "/art",
	} {
		resp, body := anon(t, h, http.MethodGet, route, "")
		if resp.StatusCode != http.StatusServiceUnavailable || !strings.Contains(string(body), `"catalog-maintenance"`) {
			t.Errorf("%s in a hand-off = %d: %s", route, resp.StatusCode, body)
		}
	}
	resp, page := anon(t, h, http.MethodGet, file.Url, "")
	if resp.StatusCode != http.StatusServiceUnavailable || !strings.Contains(string(page), "Try this link again") {
		t.Errorf("the page in a hand-off = %d: %s", resp.StatusCode, page)
	}
	for _, route := range []string{gone.Url, gone.Url + "/stream?i=0"} {
		if resp, _ := anon(t, h, http.MethodGet, route, ""); resp.StatusCode != http.StatusNotFound {
			t.Errorf("revoked %s in a hand-off = %d, want 404", route, resp.StatusCode)
		}
	}

	if err := c.MaintenanceEnd(ctx); err != nil {
		t.Fatal(err)
	}
	handedOff = false
	for _, route := range []string{episode.Url + "/stream?i=0", file.Url + "/stream?i=0"} {
		if resp, _ := anon(t, h, http.MethodGet, route, ""); resp.StatusCode != http.StatusOK {
			t.Errorf("%s after the hand-off = %d, want 200", route, resp.StatusCode)
		}
	}
}
