package api

import (
	"context"
	"net/http"
	"os"
	"strings"
	"testing"
)

// A shared track whose file has gone is a link with nothing to play: the
// page says so in place of a player and a download link that would both
// fail, and the stream and the download refuse.
func TestASharedTrackWhoseFileIsGoneHasNothingToPlay(t *testing.T) {
	t.Parallel()
	for _, c := range []struct {
		name    string
		harness func(*testing.T) *harness
	}{
		{"without the engine", newHarnessDirect},
		{"with the engine", func(t *testing.T) *harness { return newHarness(t) }},
	} {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			h := c.harness(t)
			track := h.items(t, "?mediaType=music").Items[0]
			file, err := h.svc.DownloadSource(context.Background(), track.Pid, "")
			if err != nil {
				t.Fatal(err)
			}
			share := shareOf(t, h, track.Pid, map[string]any{"allowDownload": true})
			if _, page := anon(t, h, http.MethodGet, share.Url, ""); !strings.Contains(string(page), "<audio") ||
				!strings.Contains(string(page), "/download") {
				t.Fatalf("the page of a track that is here lacks its player or download: %.600s", page)
			}

			if err := os.Remove(file.Path); err != nil {
				t.Fatal(err)
			}
			h.rescanAndWait(t)

			resp, page := anon(t, h, http.MethodGet, share.Url, "")
			if resp.StatusCode != http.StatusOK {
				t.Fatalf("the page of a track whose file is gone = %d", resp.StatusCode)
			}
			if strings.Contains(string(page), "<audio") || strings.Contains(string(page), "/download") {
				t.Errorf("the page offers a player or a download for a file that is gone: %.600s", page)
			}
			if !strings.Contains(string(page), "Not available to play yet") {
				t.Errorf("the page does not say the track has nothing to play: %.600s", page)
			}
			if resp, _ := anon(t, h, http.MethodGet, share.Url+"/stream?i=0", ""); resp.StatusCode != http.StatusNotFound {
				t.Errorf("stream = %d, want 404", resp.StatusCode)
			}
			resp, body := anon(t, h, http.MethodGet, share.Url+"/download?i=0", "")
			if resp.StatusCode != http.StatusNotFound || !strings.Contains(string(body), "no file on this server") {
				t.Errorf("download = %d: %s", resp.StatusCode, body)
			}
			if got := sharePlays(t, h, share.Pid); got != 0 {
				t.Errorf("plays = %d, want none", got)
			}
		})
	}
}
