package api

import (
	"net/http"
	"strings"
	"testing"
)

func cacheControl(resp *http.Response) string {
	return strings.Join(resp.Header.Values("Cache-Control"), ", ")
}

// A cache in front of the server must not keep a share's answers, or a
// revoked link would go on serving from it: the page, the audio from a
// file, from the engine and relayed from a feed, the download, and the
// refusals a dead link gets. The artwork alone is stored, and revalidated
// at every use so that it stops with the link.
func TestEveryShareAnswerIsKeptOutOfSharedCaches(t *testing.T) {
	t.Parallel()
	for _, c := range []struct {
		name    string
		harness func(*testing.T) *harness
	}{
		{"audio from the file", newHarnessDirect},
		{"audio through the engine", newPodcastHarness},
	} {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			h := c.harness(t)
			track := h.items(t, "?mediaType=music").Items[0]
			wantStatus(t, metadataPutBytes(t, h.ts, "/api/v1/items/"+track.Pid+"/artwork", h.token, tinyPNG(t)), 200, "set a cover")
			share := shareOf(t, h, track.Pid, map[string]any{"allowDownload": true})
			kept := func(path, rangeHeader string, status int) {
				t.Helper()
				resp, _ := anon(t, h, http.MethodGet, path, rangeHeader)
				if resp.StatusCode != status {
					t.Errorf("%s %s = %d, want %d", path, rangeHeader, resp.StatusCode, status)
				}
				if got := cacheControl(resp); !strings.Contains(got, "no-store") {
					t.Errorf("%s %s (%d) sent Cache-Control %q, want no-store", path, rangeHeader, resp.StatusCode, got)
				}
			}
			kept(share.Url, "", http.StatusOK)
			kept(share.Url+"/stream?i=0", "", http.StatusOK)
			kept(share.Url+"/stream?i=0", "bytes=10-19", http.StatusPartialContent)
			kept(share.Url+"/stream?i=7", "", http.StatusNotFound)
			kept(share.Url+"/download?i=0", "", http.StatusOK)
			resp, _ := anon(t, h, http.MethodGet, share.Url+"/art", "")
			if got := cacheControl(resp); resp.StatusCode != http.StatusOK || got != "public, no-cache" {
				t.Errorf("artwork = %d with Cache-Control %q, want 200 stored and revalidated", resp.StatusCode, got)
			}

			wantStatus(t, h.deleteReq(t, "/api/v1/shares/"+share.Pid), 204, "revoking the link")
			kept(share.Url, "", http.StatusNotFound)
			kept(share.Url+"/stream?i=0", "", http.StatusNotFound)
			kept(share.Url+"/download?i=0", "", http.StatusNotFound)
			kept(share.Url+"/art", "", http.StatusNotFound)
		})
	}

	t.Run("audio relayed from a feed", func(t *testing.T) {
		t.Parallel()
		h := newPodcastHarness(t)
		_, ep := firstEpisode(t, h, newFeedServer(t, 1).feedURL(), nil)
		share := shareOf(t, h, ep.Pid, nil)
		for _, rng := range []string{"", "bytes=10-19"} {
			resp, _ := anon(t, h, http.MethodGet, share.Url+"/stream?i=0", rng)
			if got := cacheControl(resp); !strings.Contains(got, "no-store") {
				t.Errorf("the relay (%q) sent Cache-Control %q, want no-store", rng, got)
			}
		}
	})
}
