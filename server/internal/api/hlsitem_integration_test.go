package api

import (
	"encoding/base64"
	"encoding/json"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"testing"
)

// fakeItemDescriptor is the v a one-source master carries, built from the
// sign parameters as the real daemon builds it.
func fakeItemDescriptor(params map[string]string) string {
	d := map[string]any{"ver": 1, "src": params["src"], "id": "1-1", "format": params["format"]}
	for _, k := range []string{"gain", "dynamics"} {
		if params[k] != "" {
			d[k] = params[k]
		}
	}
	for _, k := range []string{"bitrate", "from", "to"} {
		if n, err := strconv.ParseInt(params[k], 10, 64); err == nil {
			d[k] = n
		}
	}
	raw, _ := json.Marshal(d)
	return base64.RawURLEncoding.EncodeToString(raw)
}

// fetchHLS answers a /media/hls URL's status and body.
func fetchHLS(t *testing.T, h *harness, u string) (int, string) {
	t.Helper()
	resp, err := http.Get(h.ts.URL + u)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	return resp.StatusCode, string(body)
}

// hlsChild answers the proxied URL of the first child a playlist names
// whose URI starts with prefix.
func hlsChild(t *testing.T, body, prefix string) string {
	t.Helper()
	for _, line := range strings.Split(body, "\n") {
		if strings.HasPrefix(line, prefix) {
			return "/media/hls/" + line
		}
	}
	t.Fatalf("no %s child in %q", prefix, body)
	return ""
}

// A caller that plays HLS is served a capped stream as the item's own
// HLS presentation, which it seeks itself: seekable, never cut, and
// playable through this origin playlist by playlist.
func TestPlayInfoServesAnHLSPresentationToACallerThatPlaysIt(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	pid := h.items(t, "?limit=1").Items[0].Pid // Alpha Song, a 2 s flac

	pi := decode[PlayInfo](t, get(t, h.ts, "/api/v1/items/"+pid+"/play-info?maxBitrateKbps=96&positionMs=1500&hls=true", h.token))
	u, err := url.Parse(pi.Url)
	if err != nil {
		t.Fatal(err)
	}
	if u.Path != "/media/hls/master.m3u8" || u.Query().Has("t") {
		t.Fatalf("url %s, want an uncut HLS presentation", pi.Url)
	}
	if !pi.Seekable || pi.StartOffsetMs != nil || pi.MimeType != "application/vnd.apple.mpegurl" {
		t.Fatalf("play-info %+v, want a seekable HLS presentation with no cut", pi)
	}
	if pi.AppliedBitrateKbps == nil || *pi.AppliedBitrateKbps != 96 {
		t.Fatalf("applied = %v, want the cap", pi.AppliedBitrateKbps)
	}
	code, master := fetchHLS(t, h, pi.Url)
	if code != 200 || !strings.Contains(master, "&mt=") {
		t.Fatalf("master = %d %q, want its children under the token", code, master)
	}
	code, media := fetchHLS(t, h, hlsChild(t, master, "media.m3u8"))
	if code != 200 {
		t.Fatalf("media playlist = %d", code)
	}
	// The engine's descriptor names the file; no URL handed out does.
	for _, body := range []string{master, media} {
		if strings.Contains(body, "v=") || strings.Contains(body, "sig=") || !strings.Contains(body, "?c=") {
			t.Fatalf("playlist %q, want every child sealed", body)
		}
	}
	if code, body := fetchHLS(t, h, hlsChild(t, media, "seg/0.m4s")); code != 200 || body != "fmp4" {
		t.Fatalf("segment = %d %q", code, body)
	}

	// The original plays as the file, which the client seeks itself.
	pi = decode[PlayInfo](t, get(t, h.ts, "/api/v1/items/"+pid+"/play-info?positionMs=1500&hls=true", h.token))
	if !strings.HasPrefix(pi.Url, "/media/stream?") || !pi.Seekable {
		t.Fatalf("an original = %s seekable %v, want the file", pi.Url, pi.Seekable)
	}
}

// Each playlist and segment fetch re-checks the listener, as a stream
// fetch does: an ended session stops the presentation, and so does the
// loss of the item.
func TestHLSPresentationStopsWithItsListenersAccess(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	pid := h.items(t, "?limit=1").Items[0].Pid
	lib := decodeStatus[Library](t, h.postJSON(t, "/api/v1/libraries", map[string]any{
		"name": "elsewhere", "path": t.TempDir(),
	}), 201, "a library the item is not in")
	allowed := map[string]any{"download": true, "delete": false, "explicitContent": true,
		"sharedOutputs": true, "managePodcasts": true}
	for i, c := range []struct {
		name string
		end  func(id string)
		want int
	}{
		{"session revoked", func(id string) {
			wantStatus(t, h.deleteReq(t, "/api/v1/users/"+id+"/sessions"), 204, "revoke")
		}, http.StatusUnauthorized},
		{"grant narrowed", func(id string) {
			wantStatus(t, h.patchJSON(t, "/api/v1/users/"+id, map[string]any{
				"libraryAccess": map[string]any{"mode": "granted", "libraryPids": []string{lib.Pid}},
			}), 200, "narrow")
		}, http.StatusNotFound},
	} {
		t.Run(c.name, func(t *testing.T) {
			id, token, _ := mediaListener(t, h, "hlslistener"+string(rune('a'+i)), allowed)
			pi := decode[PlayInfo](t, get(t, h.ts, "/api/v1/items/"+pid+"/play-info?maxBitrateKbps=96&hls=true", token))
			code, master := fetchHLS(t, h, pi.Url)
			if code != 200 {
				t.Fatalf("master before the change = %d", code)
			}
			child := hlsChild(t, master, "media.m3u8")
			c.end(id)
			for name, u := range map[string]string{"master": pi.Url, "child": child} {
				if code, _ := fetchHLS(t, h, u); code != c.want {
					t.Errorf("%s after %s = %d, want %d", name, c.name, code, c.want)
				}
			}
		})
	}
}
