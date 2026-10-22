package api

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// playlistStation serves a station's stream at /stream and, at every
// other path, the playlist answers names: its type and body, HOST in the
// body standing for the station's own address. It counts the requests
// for each path.
type playlistStation struct {
	ts   *httptest.Server
	mu   sync.Mutex
	hits map[string]int
}

func newPlaylistStation(t *testing.T, payload []byte, answers map[string][2]string) *playlistStation {
	t.Helper()
	p := &playlistStation{hits: map[string]int{}}
	p.ts = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		p.mu.Lock()
		p.hits[r.URL.Path]++
		p.mu.Unlock()
		if r.URL.Path == "/stream" {
			w.Header().Set("Content-Type", "audio/mpeg")
			w.Header().Set("icy-name", "Followed FM")
			w.Write(payload)
			return
		}
		answer, ok := answers[r.URL.Path]
		if !ok {
			http.NotFound(w, r)
			return
		}
		if answer[0] == "" {
			w.Header()["Content-Type"] = nil
		} else {
			w.Header().Set("Content-Type", answer[0])
		}
		w.Header().Set("icy-name", "Playlist FM")
		io.WriteString(w, strings.ReplaceAll(answer[1], "HOST", r.Host))
	}))
	t.Cleanup(p.ts.Close)
	return p
}

func (p *playlistStation) asked(path string) int {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.hits[path]
}

// A station whose address answers a PLS or M3U playlist plays the stream
// the playlist names: typed, plain text or untyped, with CRLF lines, a
// byte-order mark or a relative entry. The answer is the stream's, its
// ICY headers included, and the station keeps the address it was given.
func TestAPlaylistStationPlaysItsStream(t *testing.T) {
	t.Parallel()
	h := newHarnessWith(t, func(cfg *service.Config) { cfg.AllowPrivateRadioHosts = true })
	payload := bytes.Repeat([]byte("followed-stream."), 256)
	station := newPlaylistStation(t, payload, map[string][2]string{
		"/dir/pls":   {"audio/x-scpls", "[playlist]\r\nNumberOfEntries=1\r\nFile1=../stream\r\nTitle1=Relative\r\n"},
		"/m3u":       {"audio/x-mpegurl", "#EXTM3U\n#EXTINF:-1,Absolute\nhttp://HOST/stream\n"},
		"/m3u.txt":   {"text/plain; charset=utf-8", "\ufeff#EXTM3U\r\nhttp://HOST/stream\r\n"},
		"/pls.bare":  {"", "[playlist]\nFile1=http://HOST/stream\n"},
		"/list.bare": {"application/octet-stream", "http://HOST/stream\n"},
		"/skips.m3u": {"audio/mpegurl", "#EXTM3U\nrtsp://HOST/rtsp\nmms://HOST/mms\nhttp://HOST/stream\n"},
	})
	for _, path := range []string{"/dir/pls", "/m3u", "/m3u.txt", "/pls.bare", "/list.bare", "/skips.m3u"} {
		st := decodeStatus[RadioStation](t, h.postJSON(t, "/api/v1/radio/stations", map[string]any{
			"name": "Playlist FM " + path, "streamUrl": station.ts.URL + path,
		}), 201, "creating a station")
		pi := decode[RadioPlayInfo](t, get(t, h.ts, "/api/v1/radio/stations/"+st.Pid+"/play-info", h.token))
		resp := get(t, h.ts, pi.Url, "")
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		if resp.StatusCode != 200 || !bytes.Equal(body, payload) || resp.Header.Get("Content-Type") != "audio/mpeg" {
			t.Errorf("%s: %d as %q with %d bytes, want the followed stream", path, resp.StatusCode, resp.Header.Get("Content-Type"), len(body))
		}
		if got := resp.Header.Get("Icy-Name"); got != "Followed FM" {
			t.Errorf("%s: Icy-Name = %q, want the stream's", path, got)
		}
		if again := decode[RadioStation](t, get(t, h.ts, "/api/v1/radio/stations/"+st.Pid, h.token)); again.StreamUrl != station.ts.URL+path {
			t.Errorf("%s: the station now holds %q", path, again.StreamUrl)
		}
	}
	for _, path := range []string{"/rtsp", "/mms"} {
		if n := station.asked(path); n != 0 {
			t.Errorf("%s was asked for %d times", path, n)
		}
	}
}

// What a station answers is never followed past one playlist, never into
// an HLS manifest's segments, never to an address that is not the web's,
// and never past the bytes a playlist may hold: each is refused in its own
// words.
func TestAPlaylistStationIsRefusedWhatItCannotPlay(t *testing.T) {
	t.Parallel()
	h := newHarnessWith(t, func(cfg *service.Config) { cfg.AllowPrivateRadioHosts = true })
	station := newPlaylistStation(t, []byte("unused"), map[string][2]string{
		"/hls":        {"application/vnd.apple.mpegurl", "#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXTINF:10,\nseg1.ts\n"},
		"/hls.bare":   {"", "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=64000\nhttp://HOST/low.m3u8\n"},
		"/outer":      {"audio/x-mpegurl", "http://HOST/inner\n"},
		"/inner":      {"audio/x-scpls", "[playlist]\nFile1=http://HOST/stream\n"},
		"/outer.bare": {"audio/x-mpegurl", "http://HOST/inner.bare\n"},
		"/inner.bare": {"", "#EXTM3U\nhttp://HOST/stream\n"},
		"/nonweb":     {"audio/x-scpls", "[playlist]\nFile1=rtsp://HOST/s\nFile2=mms://HOST/s\nFile3=file:///etc/passwd\n"},
		"/big":        {"audio/x-mpegurl", "#EXTM3U\n" + strings.Repeat("# padding padding padding padding padding\n", 2000) + "http://HOST/stream\n"},
		"/wraps.m3u":  {"audio/x-mpegurl", "http://HOST/inner.m3u8\n"},
		"/inner.m3u8": {"application/vnd.apple.mpegurl", "#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXTINF:10,\nseg.ts\n"},
		"/wraps.pls":  {"audio/x-scpls", "[playlist]\nFile1=http://HOST/inner.hls\n"},
		"/inner.hls":  {"", "#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-STREAM-INF:BANDWIDTH=64000\nlow.m3u8\n"},
	})
	for path, says := range map[string]string{
		"/hls":        string(refusedHLS),
		"/hls.bare":   string(refusedHLS),
		"/outer":      string(refusedNested),
		"/outer.bare": string(refusedNested),
		"/nonweb":     string(refusedNoStream),
		"/big":        string(refusedLarge),
		"/wraps.m3u":  string(refusedHLS),
		"/wraps.pls":  string(refusedHLS),
	} {
		st := decodeStatus[RadioStation](t, h.postJSON(t, "/api/v1/radio/stations", map[string]any{
			"name": "Refused FM " + path, "streamUrl": station.ts.URL + path,
		}), 201, "creating a station")
		pi := decode[RadioPlayInfo](t, get(t, h.ts, "/api/v1/radio/stations/"+st.Pid+"/play-info", h.token))
		resp := get(t, h.ts, pi.Url, "")
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		var e Error
		if resp.StatusCode != http.StatusBadGateway || json.Unmarshal(body, &e) != nil ||
			e.Code != "service-unreachable" || e.Message != says {
			t.Errorf("%s: %d %s, want the refusal %q", path, resp.StatusCode, body, says)
		}
	}
	for _, path := range []string{"/stream", "/seg1.ts", "/low.m3u8", "/seg.ts"} {
		if n := station.asked(path); n != 0 {
			t.Errorf("%s was asked for %d times", path, n)
		}
	}
}

// A playlist's entry is asked for through the radio client, so the dial
// guard judges the address the playlist names: a loopback entry is refused
// before anything dials it.
func TestAPlaylistNamingAPrivateHostIsNeverDialed(t *testing.T) {
	t.Parallel()
	h := newHarnessWith(t, nil)
	station := newPlaylistStation(t, []byte("private"), map[string][2]string{
		"/list": {"audio/x-mpegurl", "#EXTM3U\nhttp://HOST/stream\n"},
	})
	ctx, stop := context.WithCancel(context.Background())
	defer stop()
	req, err := stationRequest(ctx, station.ts.URL+"/list", "test")
	if err != nil {
		t.Fatal(err)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	stream, err := stationStream(ctx, h.svc.RadioHTTP(), "test", resp, stop, time.Minute)
	var why stationRefusal
	if err == nil || errors.As(err, &why) {
		if stream != nil {
			stream.Body.Close()
		}
		t.Fatalf("following a playlist to a loopback host = %v, want the dial refused", err)
	}
	if n := station.asked("/stream"); n != 0 {
		t.Errorf("the loopback stream was asked for %d times", n)
	}
}

// A playlist, or an answer that says nothing of itself, that does not
// arrive in time is refused rather than held: the radio client has no
// deadline of its own.
func TestASlowPlaylistIsRefused(t *testing.T) {
	t.Parallel()
	for _, typ := range []string{"audio/x-mpegurl", ""} {
		ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if typ == "" {
				w.Header()["Content-Type"] = nil
			} else {
				w.Header().Set("Content-Type", typ)
			}
			fmt.Fprint(w, "#EXTM3U\n")
			w.(http.Flusher).Flush()
			<-r.Context().Done()
		}))
		// The test's own deadline, so a relay that waited for ever fails here
		// rather than at the suite's timeout.
		ctx, stop := context.WithTimeout(context.Background(), 10*time.Second)
		req, err := stationRequest(ctx, ts.URL+"/list", "test")
		if err != nil {
			t.Fatal(err)
		}
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		start := time.Now()
		_, err = stationStream(ctx, http.DefaultClient, "test", resp, stop, 200*time.Millisecond)
		if !errors.Is(err, refusedSlow) || time.Since(start) > 30*time.Second {
			t.Errorf("a playlist typed %q that never ends = %v after %v, want refused as slow", typ, err, time.Since(start))
		}
		resp.Body.Close()
		stop()
		ts.Close()
	}
}
