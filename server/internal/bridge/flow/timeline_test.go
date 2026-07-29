package flow

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/auth"
	"github.com/colespringer/waxdeck/server/internal/db"
)

// fakeTimelineSidecar answers the surfaces TimelineFor and ServeHLS
// touch: caps, the timeline mint, signing, and the HLS tree.
func fakeTimelineSidecar(t *testing.T) *httptest.Server {
	t.Helper()
	srv := httptest.NewServer(timelineSidecarMux(t))
	t.Cleanup(srv.Close)
	return srv
}

// timelineSidecarMux is the sidecar's routing table on its own, for a
// test that wraps it rather than serving it directly.
func timelineSidecarMux(t *testing.T) *http.ServeMux {
	t.Helper()
	mux := http.NewServeMux()
	mux.HandleFunc("/caps", func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]any{
			"schemaVersion": 1,
			"delivery": map[string]any{
				"progressive": true, "hls": true, "timelines": true,
				"hlsFormats": []string{"aac", "flac"}, "jobs": true,
			},
			"outputs": []map[string]any{{"name": "aac", "live": true}, {"name": "mp3", "live": true}, {"name": "wav", "live": true}},
		})
	})
	mux.HandleFunc("/hls/timeline", func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			Srcs             []struct{ Src string } `json:"srcs"`
			CrossfadeSeconds float64                `json:"crossfadeSeconds"`
		}
		json.NewDecoder(r.Body).Decode(&req)
		w.WriteHeader(http.StatusCreated)
		json.NewEncoder(w).Encode(map[string]any{
			"schemaVersion": 1, "tl": "digest123", "members": len(req.Srcs),
			"durationSeconds": 150.0, "envelopeRate": 44100,
			"boundaries": []map[string]int64{
				{"offsetSamples": 0, "durationSamples": 2646000},
				{"offsetSamples": 2646000, "durationSamples": 3969000},
			},
		})
	})
	mux.HandleFunc("/sign", func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			Path   string            `json:"path"`
			Params map[string]string `json:"params"`
		}
		json.NewDecoder(r.Body).Decode(&req)
		if req.Params["tl"] != "" && req.Params["gain"] == "" {
			// The real daemon refuses tag-driven gain on timelines; the
			// fake enforces the same so the suite keeps it honest.
			http.Error(w, `{"error":"tag gain on timeline","code":"invalid-request"}`, http.StatusBadRequest)
			return
		}
		q := url.Values{}
		for k, v := range req.Params {
			q.Set(k, v)
		}
		q.Set("sig", "upstreamsig")
		json.NewEncoder(w).Encode(map[string]any{
			"schemaVersion": 1,
			"url":           req.Path + "?" + q.Encode(),
			"exp":           time.Now().Add(time.Hour).Unix(),
		})
	})
	mux.HandleFunc("/hls/master.m3u8", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Query().Get("sig") == "" {
			http.Error(w, "unsigned", http.StatusUnauthorized)
			return
		}
		w.Header().Set("Content-Type", "application/vnd.apple.mpegurl")
		w.Write([]byte("#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=160000,CODECS=\"mp4a.40.2\"\nmedia.m3u8?v=abc&sig=child1\n"))
	})
	mux.HandleFunc("/hls/media.m3u8", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/vnd.apple.mpegurl")
		w.Write([]byte("#EXTM3U\n#EXT-X-MAP:URI=\"init.mp4?v=abc&sig=init1\"\n#EXTINF:4.0,\nseg/0.m4s?v=abc&sig=seg0\n#EXT-X-ENDLIST\n"))
	})
	mux.HandleFunc("/hls/seg/0.m4s", func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("X-API-Key") != "" {
			// The proxy must never attach its key to HLS fetches; the
			// upstream signature is the authorization.
			http.Error(w, "unexpected api key", http.StatusBadRequest)
			return
		}
		w.Header().Set("Content-Type", "video/iso.segment")
		// Hop-by-hop noise the relay must strip.
		w.Header().Set("Keep-Alive", "timeout=5")
		w.Header().Set("Proxy-Connection", "keep-alive")
		w.Write([]byte("segmentbytes"))
	})
	return mux
}

func newTimelineBridge(t *testing.T) (*Bridge, string) {
	t.Helper()
	sidecar := fakeTimelineSidecar(t)
	dir := t.TempDir()
	path := filepath.Join(dir, "one.flac")
	if err := os.WriteFile(path, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	tokens := auth.NewMediaTokens([]byte("test-secret"), 0)
	b, err := New(context.Background(), Config{
		BaseURL: sidecar.URL,
		APIKey:  "key",
		Roots:   []Root{{Name: "lib", Path: dir}},
		Tokens:  tokens,
		Logger:  nil,
	})
	if err != nil {
		t.Fatal(err)
	}
	return b, path
}

func TestTimelineForMintsProxiedURL(t *testing.T) {
	b, path := newTimelineBridge(t)
	members := []TimelineMember{
		{PID: "tr-one", Src: Source{Path: path, DurationMS: 60000}},
		{PID: "tr-two", Src: Source{Path: path, DurationMS: 90000}},
	}
	res, err := b.TimelineFor(context.Background(), "us-alice", members, 0)
	if err != nil {
		t.Fatal(err)
	}
	if res.JobPID != "" {
		t.Fatal("unexpected job")
	}
	if !strings.HasPrefix(res.URL, "/media/hls/master.m3u8?tl=digest123&mt=") {
		t.Fatalf("url %q", res.URL)
	}
	if res.DurationMS != 150000 || res.EnvelopeRate != 44100 {
		t.Fatalf("duration %d rate %d", res.DurationMS, res.EnvelopeRate)
	}
	if len(res.Boundaries) != 2 || res.Boundaries[0].PID != "tr-one" || res.Boundaries[1].OffsetSamples != 2646000 {
		t.Fatalf("boundaries %+v", res.Boundaries)
	}
	// The token must outlive the queue.
	if time.Until(res.ExpiresAt) < 25*time.Minute {
		t.Fatalf("expiry too soon: %v", res.ExpiresAt)
	}
	if _, err := b.TimelineFor(context.Background(), "us-alice",
		[]TimelineMember{{PID: "tr-v", Src: Source{Path: path, Virtual: true}}}, 0); err == nil {
		t.Fatal("virtual member accepted")
	}
}

// TestTimelineForVirtualMemberWindows pins that a CUE-carved virtual
// track mints into a gapless timeline as a sample window when the sidecar
// advertises member windows, instead of being refused.
func TestTimelineForVirtualMemberWindows(t *testing.T) {
	var gotSrcs []struct {
		Src  string `json:"src"`
		From int64  `json:"from"`
		To   int64  `json:"to"`
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/caps", func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]any{
			"schemaVersion": 1,
			"delivery": map[string]any{
				"progressive": true, "hls": true, "timelines": true,
				"hlsFormats": []string{"aac", "flac"}, "jobs": true,
				"timelineMemberWindows": true,
			},
			"outputs": []map[string]any{{"name": "aac", "live": true}},
		})
	})
	mux.HandleFunc("/hls/timeline", func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			Srcs []struct {
				Src  string `json:"src"`
				From int64  `json:"from"`
				To   int64  `json:"to"`
			} `json:"srcs"`
		}
		json.NewDecoder(r.Body).Decode(&req)
		gotSrcs = req.Srcs
		w.WriteHeader(http.StatusCreated)
		json.NewEncoder(w).Encode(map[string]any{
			"schemaVersion": 1, "tl": "digestwin", "members": len(req.Srcs),
			"durationSeconds": 60.0, "envelopeRate": 44100,
			"boundaries": []map[string]int64{{"offsetSamples": 0, "durationSamples": 2646000}},
		})
	})
	mux.HandleFunc("/sign", func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			Path   string            `json:"path"`
			Params map[string]string `json:"params"`
		}
		json.NewDecoder(r.Body).Decode(&req)
		q := url.Values{}
		for k, v := range req.Params {
			q.Set(k, v)
		}
		q.Set("sig", "upstreamsig")
		json.NewEncoder(w).Encode(map[string]any{
			"schemaVersion": 1,
			"url":           req.Path + "?" + q.Encode(),
			"exp":           time.Now().Add(time.Hour).Unix(),
		})
	})
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)

	dir := t.TempDir()
	path := filepath.Join(dir, "album.flac")
	if err := os.WriteFile(path, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	b, err := New(context.Background(), Config{
		BaseURL: srv.URL,
		APIKey:  "key",
		Roots:   []Root{{Name: "lib", Path: dir}},
		Tokens:  auth.NewMediaTokens([]byte("test-secret"), 0),
	})
	if err != nil {
		t.Fatal(err)
	}
	if !b.TimelineMemberWindowsSupported() {
		t.Fatal("member windows not reported supported")
	}
	res, err := b.TimelineFor(context.Background(), "us-alice", []TimelineMember{
		{PID: "tr-whole", Src: Source{Path: path, DurationMS: 60000}},
		{PID: "tr-carved", Src: Source{Path: path, DurationMS: 30000, Virtual: true, FromSample: 100, ToSample: 200}},
	}, 0)
	if err != nil {
		t.Fatalf("windowed virtual member refused: %v", err)
	}
	if res.JobPID != "" {
		t.Fatal("unexpected job")
	}
	if len(gotSrcs) != 2 {
		t.Fatalf("mint saw %d srcs, want 2", len(gotSrcs))
	}
	// The whole file carries no window; the carved track carries [100, 200).
	if gotSrcs[0].From != 0 || gotSrcs[0].To != 0 {
		t.Fatalf("whole-file member windowed: %+v", gotSrcs[0])
	}
	if gotSrcs[1].From != 100 || gotSrcs[1].To != 200 {
		t.Fatalf("carved member window = [%d,%d), want [100,200)", gotSrcs[1].From, gotSrcs[1].To)
	}
}

func TestServeHLSRewritesPlaylistsAndProxiesSegments(t *testing.T) {
	b, path := newTimelineBridge(t)
	res, err := b.TimelineFor(context.Background(), "us-alice",
		[]TimelineMember{{PID: "tr-one", Src: Source{Path: path, DurationMS: 60000}}, {PID: "tr-two", Src: Source{Path: path, DurationMS: 90000}}}, 0)
	if err != nil {
		t.Fatal(err)
	}

	get := func(u string) *httptest.ResponseRecorder {
		req := httptest.NewRequest(http.MethodGet, u, nil)
		rec := httptest.NewRecorder()
		b.ServeHLS(rec, req)
		return rec
	}

	// The master fetch verifies the token and rewrites child URIs.
	rec := get(res.URL)
	if rec.Code != http.StatusOK {
		t.Fatalf("master status %d: %s", rec.Code, rec.Body.String())
	}
	body := rec.Body.String()
	if !strings.Contains(body, "media.m3u8?v=abc&sig=child1&mt=") {
		t.Fatalf("child URI not stamped: %s", body)
	}

	// Extract the media playlist URI and fetch it through the proxy.
	var mediaURI string
	for _, line := range strings.Split(body, "\n") {
		if strings.HasPrefix(line, "media.m3u8") {
			mediaURI = "/media/hls/" + line
		}
	}
	rec = get(mediaURI)
	if rec.Code != http.StatusOK {
		t.Fatalf("media status %d: %s", rec.Code, rec.Body.String())
	}
	mediaBody := rec.Body.String()
	if !strings.Contains(mediaBody, "seg/0.m4s?v=abc&sig=seg0&mt=") {
		t.Fatalf("segment URI not stamped: %s", mediaBody)
	}
	if !strings.Contains(mediaBody, `URI="init.mp4?v=abc&sig=init1&mt=`) {
		t.Fatalf("map URI not stamped: %s", mediaBody)
	}

	// Segment fetches pass the upstream signature through, minus the
	// token, and never carry the API key.
	var segURI string
	for _, line := range strings.Split(mediaBody, "\n") {
		if strings.HasPrefix(line, "seg/") {
			segURI = "/media/hls/" + line
		}
	}
	rec = get(segURI)
	if rec.Code != http.StatusOK || rec.Body.String() != "segmentbytes" {
		t.Fatalf("segment status %d body %q", rec.Code, rec.Body.String())
	}
	if rec.Header().Get("Keep-Alive") != "" || rec.Header().Get("Proxy-Connection") != "" {
		t.Fatalf("hop-by-hop headers crossed the relay: %v", rec.Header())
	}

	// A missing or foreign token is refused.
	rec = get("/media/hls/master.m3u8?tl=digest123")
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("tokenless master status %d", rec.Code)
	}
	otherTokens := auth.NewMediaTokens([]byte("other-secret"), 0)
	tok, _ := otherTokens.Mint("us-alice", "tl-digest123")
	rec = get("/media/hls/master.m3u8?tl=digest123&mt=" + url.QueryEscape(tok))
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("forged token status %d", rec.Code)
	}
	// A token for a plain item pid does not open the HLS surface.
	itemTok, _ := b.tokens.Mint("us-alice", "tr-one")
	rec = get("/media/hls/master.m3u8?tl=digest123&mt=" + url.QueryEscape(itemTok))
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("item token accepted on HLS: %d", rec.Code)
	}
}

// TestTimelineStashSurvivesRestart mints through one bridge and serves
// the same URL through a second one built over the same store, which is
// what a restart is: the media-token key is loaded from the data
// directory and survives too, so a restored row's token still verifies.
func TestTimelineStashSurvivesRestart(t *testing.T) {
	var deadStatus atomic.Int32
	sidecar := restartableTimelineSidecar(t, &deadStatus)
	dir := t.TempDir()
	path := filepath.Join(dir, "one.flac")
	if err := os.WriteFile(path, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	store, err := db.Open(context.Background(), filepath.Join(dir, "waxdeck.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { store.Close() })

	newBridge := func() *Bridge {
		b, err := New(context.Background(), Config{
			BaseURL:   sidecar.URL,
			APIKey:    "key",
			Roots:     []Root{{Name: "lib", Path: dir}},
			Tokens:    auth.NewMediaTokens([]byte("test-secret"), 0),
			Timelines: store,
		})
		if err != nil {
			t.Fatal(err)
		}
		return b
	}

	first := newBridge()
	res, err := first.TimelineFor(context.Background(), "us-alice",
		[]TimelineMember{{PID: "tr-one", Src: Source{Path: path, DurationMS: 60000}}}, 0)
	if err != nil {
		t.Fatal(err)
	}

	// The restart. Nothing is carried over in memory; the stash comes
	// back off disk.
	second := newBridge()
	second.tl.mu.Lock()
	restored := len(second.tl.stash)
	second.tl.mu.Unlock()
	if restored != 1 {
		t.Fatalf("restored %d stash rows, want 1", restored)
	}

	get := func(b *Bridge, u string) *httptest.ResponseRecorder {
		rec := httptest.NewRecorder()
		b.ServeHLS(rec, httptest.NewRequest(http.MethodGet, u, nil))
		return rec
	}
	rec := get(second, res.URL)
	if rec.Code != http.StatusOK {
		t.Fatalf("master through the restarted bridge: status %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "media.m3u8?v=abc&sig=child1&mt=") {
		t.Fatalf("child URI not stamped: %s", rec.Body.String())
	}

	// The other half of persisting: a restored row the sidecar will not
	// serve must fail the way an absent stash does, not by relaying the
	// upstream status. Both refusals count. 403 is the one a signature
	// failure produces, which is what a sidecar whose auto-generated
	// signing secret was recreated answers for every restored row.
	for _, dead := range []int{http.StatusNotFound, http.StatusForbidden} {
		// Each pass re-mints, since the previous one evicted the row.
		res, err := second.TimelineFor(context.Background(), "us-alice",
			[]TimelineMember{{PID: "tr-one", Src: Source{Path: path, DurationMS: 60000}}}, 0)
		if err != nil {
			t.Fatal(err)
		}
		deadStatus.Store(int32(dead))
		rec = get(second, res.URL)
		if rec.Code != http.StatusNotFound {
			t.Fatalf("upstream %d: answered %d, want 404", dead, rec.Code)
		}
		if !strings.Contains(rec.Body.String(), `"not-found"`) || !strings.Contains(rec.Body.String(), "re-request it") {
			t.Fatalf("upstream %d: body %q, want the re-request refusal", dead, rec.Body.String())
		}
		rows, err := store.LoadTimelineStash(context.Background(), time.Now().UnixNano())
		if err != nil {
			t.Fatal(err)
		}
		if len(rows) != 0 {
			t.Fatalf("upstream %d: dead row still stored: %+v", dead, rows)
		}

		// And the eviction holds in memory, so the next fetch takes the
		// absent-stash path without asking the sidecar again.
		deadStatus.Store(0)
		if rec = get(second, res.URL); rec.Code != http.StatusNotFound {
			t.Fatalf("upstream %d: evicted digest answered %d, want 404", dead, rec.Code)
		}
	}
}

// restartableTimelineSidecar is the fake sidecar with a switch that
// makes the master fetch fail the way a restarted one does. The status
// is settable because there is more than one such answer: 404 for a
// digest the sidecar no longer holds, 403 for a signature its
// regenerated signing secret no longer verifies.
func restartableTimelineSidecar(t *testing.T, deadStatus *atomic.Int32) *httptest.Server {
	t.Helper()
	inner := timelineSidecarMux(t)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if status := int(deadStatus.Load()); status != 0 && r.URL.Path == "/hls/master.m3u8" {
			http.Error(w, `{"error":"the timeline is gone","code":"not-found"}`, status)
			return
		}
		inner.ServeHTTP(w, r)
	}))
	t.Cleanup(srv.Close)
	return srv
}

func TestRewritePlaylist(t *testing.T) {
	in := "#EXTM3U\n" +
		"#EXT-X-MAP:URI=\"init.mp4?v=1\"\n" +
		"#EXTINF:4.0,\n" +
		"seg/0.m4s?v=1\n" +
		"bare.m4s\n"
	out := string(rewritePlaylist([]byte(in), "TOK"))
	for _, want := range []string{
		`URI="init.mp4?v=1&mt=TOK"`,
		"seg/0.m4s?v=1&mt=TOK",
		"bare.m4s?mt=TOK",
	} {
		if !strings.Contains(out, want) {
			t.Fatalf("missing %q in %s", want, out)
		}
	}
}
