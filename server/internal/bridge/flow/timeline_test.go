package flow

import (
	"context"
	"encoding/json"
	"errors"
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
	res, err := b.TimelineFor(context.Background(), "us-alice", members, TimelineOptions{})
	if err != nil {
		t.Fatal(err)
	}
	if res.JobPID != "" {
		t.Fatal("unexpected job")
	}
	if !strings.HasPrefix(res.URL, "/media/hls/master.m3u8?tl=digest123&rk=aac~off~0&mt=") {
		t.Fatalf("url %q", res.URL)
	}
	if res.Format != "aac" {
		t.Fatalf("format %q, want the ladder's first", res.Format)
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
		[]TimelineMember{{PID: "tr-v", Src: Source{Path: path, Virtual: true}}}, TimelineOptions{}); err == nil {
		t.Fatal("virtual member accepted")
	}
}

// TestTimelineForHonoursRequestedFormats pins that a caller's decodable
// formats decide the rendering, that two renderings of one queue stay
// live at once, and that a preference the engine cannot produce falls
// back to the ladder rather than to silence.
func TestTimelineForHonoursRequestedFormats(t *testing.T) {
	b, path := newTimelineBridge(t)
	members := []TimelineMember{{PID: "tr-one", Src: Source{Path: path, DurationMS: 60000}}}
	mint := func(formats ...string) *TimelineResult {
		t.Helper()
		res, err := b.TimelineFor(context.Background(), "us-alice", members,
			TimelineOptions{Formats: formats})
		if err != nil {
			t.Fatal(err)
		}
		return res
	}

	// The sidecar offers aac and flac. A browser that cannot decode aac
	// asks for flac and gets it, on its own URL.
	flac := mint("flac")
	if flac.Format != "flac" || !strings.Contains(flac.URL, "rk=flac~off~0") {
		t.Fatalf("flac mint: format %q url %q", flac.Format, flac.URL)
	}

	// Preferences are tried in order, and one the engine cannot produce
	// is skipped rather than refused.
	if got := mint("opus", "flac"); got.Format != "flac" {
		t.Fatalf("second preference: %q", got.Format)
	}
	if got := mint("opus"); got.Format != "aac" {
		t.Fatalf("unproducible preference did not fall back to the ladder: %q", got.Format)
	}

	// The cast mint of the same queue arrives with the same digest and
	// must not take the browser's URL away from it: both renderings
	// stay live and each serves what it was minted for.
	aac := mint()
	if aac.Format != "aac" || aac.URL == flac.URL {
		t.Fatalf("cast mint: format %q url %q", aac.Format, aac.URL)
	}
	b.tl.mu.Lock()
	stashed := len(b.tl.stash)
	b.tl.mu.Unlock()
	if stashed != 2 {
		t.Fatalf("stashed %d renderings, want both", stashed)
	}
	for _, res := range []*TimelineResult{flac, aac} {
		rec := httptest.NewRecorder()
		b.ServeHLS(rec, httptest.NewRequest(http.MethodGet, res.URL, nil))
		if rec.Code != http.StatusOK {
			t.Fatalf("%s master: status %d: %s", res.Format, rec.Code, rec.Body.String())
		}
	}
}

// TestTimelineSlotsRideTheLimiter pins the whole life of a listener's
// timeline slot: taken at the mint, shared by every rendering they hold
// live, given back once all of them go quiet, and taken again by the
// fragment fetch that resumes the listen.
func TestTimelineSlotsRideTheLimiter(t *testing.T) {
	b, path := newTimelineBridge(t)
	gate := &fakeGate{}
	b.SetTranscodeGate(gate)
	members := []TimelineMember{{PID: "tr-one", Src: Source{Path: path, DurationMS: 60000}}}

	first, err := b.TimelineFor(context.Background(), "us-alice", members, TimelineOptions{})
	if err != nil {
		t.Fatal(err)
	}
	if gate.acquired != 1 || gate.held != 1 {
		t.Fatalf("acquired %d held %d, want one slot", gate.acquired, gate.held)
	}
	if len(gate.kinds) != 1 || gate.kinds[0] != TranscodeTimeline {
		t.Fatalf("kinds %v, want one timeline", gate.kinds)
	}

	// A second rendering of the same queue - which is what a browser
	// asking for a format the cast mint did not is - rides the slot the
	// listener already holds rather than taking another. Refusing it
	// would stall the music at the seam a queue edit was made in.
	if _, err := b.TimelineFor(context.Background(), "us-alice", members,
		TimelineOptions{Formats: []string{"flac"}}); err != nil {
		t.Fatal(err)
	}
	if gate.acquired != 1 || gate.held != 1 {
		t.Fatalf("acquired %d held %d, want the one slot shared", gate.acquired, gate.held)
	}

	// Quiet: a sweep with every rendering unfetched for longer than the
	// idle window gives the slot back.
	ts := b.timelines()
	ageTimelines(b, 2*timelineIdle)
	b.SweepTimelineSlots()
	if gate.held != 0 {
		t.Fatalf("held %d after the sweep, want the slot back", gate.held)
	}

	// A fetch resuming the listen takes it again. hls.js never
	// re-fetches the master, so this is the fragment path.
	rec := httptest.NewRecorder()
	b.ServeHLS(rec, httptest.NewRequest(http.MethodGet, first.URL, nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("master after the sweep: %d: %s", rec.Code, rec.Body.String())
	}
	if gate.acquired != 2 || gate.held != 1 {
		t.Fatalf("acquired %d held %d, want the slot taken again", gate.acquired, gate.held)
	}

	// A rendering past its expiry is not a listener: the sweep drops the
	// row and the slot with it, however recently it was fetched.
	ts.mu.Lock()
	for key, st := range ts.stash {
		st.expires = time.Now().Add(-time.Minute)
		ts.stash[key] = st
	}
	for user, slot := range ts.slots {
		slot.taken = slot.taken.Add(-2 * timelineIdle)
		ts.slots[user] = slot
	}
	ts.mu.Unlock()
	b.SweepTimelineSlots()
	if gate.held != 0 {
		t.Fatalf("held %d after expiry, want the slot back", gate.held)
	}
	ts.mu.Lock()
	left := len(ts.stash)
	ts.mu.Unlock()
	if left != 0 {
		t.Fatalf("stash holds %d expired rows", left)
	}
}

// TestTimelineMintRefusedByTheLimiter pins that a listener over the cap
// is told before the server renders anything, and that the refusal
// carries the same error a progressive stream's does.
func TestTimelineMintRefusedByTheLimiter(t *testing.T) {
	b, path := newTimelineBridge(t)
	gate := &fakeGate{refuse: true}
	b.SetTranscodeGate(gate)

	_, err := b.TimelineFor(context.Background(), "us-alice",
		[]TimelineMember{{PID: "tr-one", Src: Source{Path: path, DurationMS: 60000}}},
		TimelineOptions{})
	if !errors.Is(err, ErrTranscodeLimited) {
		t.Fatalf("mint error %v, want the limiter refusal", err)
	}
	if gate.acquired != 0 {
		t.Fatalf("acquired %d, want nothing spent on a refused listener", gate.acquired)
	}
}

// TestTimelineFetchRefusedByTheLimiter pins the other half: a listen
// resuming into a full server is refused on the fetch, with the code
// the web engine turns into an explanation rather than a re-mint.
func TestTimelineFetchRefusedByTheLimiter(t *testing.T) {
	b, path := newTimelineBridge(t)
	gate := &fakeGate{}
	b.SetTranscodeGate(gate)
	res, err := b.TimelineFor(context.Background(), "us-alice",
		[]TimelineMember{{PID: "tr-one", Src: Source{Path: path, DurationMS: 60000}}},
		TimelineOptions{})
	if err != nil {
		t.Fatal(err)
	}

	ageTimelines(b, 2*timelineIdle)
	b.SweepTimelineSlots()
	gate.refuse = true

	rec := httptest.NewRecorder()
	b.ServeHLS(rec, httptest.NewRequest(http.MethodGet, res.URL, nil))
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("status %d, want 429", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), "transcode-limited") {
		t.Fatalf("body %q", rec.Body.String())
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
	}, TimelineOptions{})
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
		[]TimelineMember{{PID: "tr-one", Src: Source{Path: path, DurationMS: 60000}}, {PID: "tr-two", Src: Source{Path: path, DurationMS: 90000}}}, TimelineOptions{})
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
	rec = get("/media/hls/master.m3u8?tl=digest123&rk=aac~off~0")
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("tokenless master status %d", rec.Code)
	}
	otherTokens := auth.NewMediaTokens([]byte("other-secret"), 0)
	tok, _ := otherTokens.Mint("us-alice", "tl-digest123/aac~off~0")
	rec = get("/media/hls/master.m3u8?tl=digest123&rk=aac~off~0&mt=" + url.QueryEscape(tok))
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("forged token status %d", rec.Code)
	}
	// A token for a plain item pid does not open the HLS surface.
	itemTok, _ := b.tokens.Mint("us-alice", "tr-one")
	rec = get("/media/hls/master.m3u8?tl=digest123&rk=aac~off~0&mt=" + url.QueryEscape(itemTok))
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
		[]TimelineMember{{PID: "tr-one", Src: Source{Path: path, DurationMS: 60000}}}, TimelineOptions{})
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

	// The id came back with the row, so a pid a client minted before the
	// restart still names something to release. Its listener did not:
	// nothing about who was on a rendering is persisted, and the fetch
	// above is what puts them back on it.
	if !second.ReleaseTimeline("us-alice", strings.TrimPrefix(res.PID, "tl-")) {
		t.Fatalf("pid %q did not survive the restart", res.PID)
	}

	// The other half of persisting: a restored row the sidecar will not
	// serve must fail the way an absent stash does, not by relaying the
	// upstream status. Both refusals count. 403 is the one a signature
	// failure produces, which is what a sidecar whose auto-generated
	// signing secret was recreated answers for every restored row.
	for _, dead := range []int{http.StatusNotFound, http.StatusForbidden} {
		// Each pass re-mints, since the previous one evicted the row.
		res, err := second.TimelineFor(context.Background(), "us-alice",
			[]TimelineMember{{PID: "tr-one", Src: Source{Path: path, DurationMS: 60000}}}, TimelineOptions{})
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

// TestTimelineForCarriesCrossfadeAndGain pins the two listener
// preferences onto the render the signed master actually names. Both
// have to reach the URL: a mint whose boundaries describe a crossfade
// the stream does not apply reports positions nothing can seek by, and a
// leveling preference that stops at the mint levels nothing.
func TestTimelineForCarriesCrossfadeAndGain(t *testing.T) {
	b, path := newTimelineBridge(t)
	quiet, peak := -24.0, -12.0
	members := []TimelineMember{
		{PID: "tr-one", Src: Source{Path: path, DurationMS: 60000, IntegratedLUFS: &quiet, TruePeakDB: &peak}},
		{PID: "tr-two", Src: Source{Path: path, DurationMS: 60000, IntegratedLUFS: &quiet, TruePeakDB: &peak}},
	}

	signedFor := func(opts TimelineOptions, gain string) string {
		t.Helper()
		res, err := b.TimelineFor(context.Background(), "us-alice", members, opts)
		if err != nil {
			t.Fatal(err)
		}
		if res.JobPID != "" {
			t.Fatal("unexpected job")
		}
		b.tl.mu.Lock()
		defer b.tl.mu.Unlock()
		st, ok := b.tl.stash[timelineKey("digest123", renderKey("aac", gain, opts.CrossfadeSeconds))]
		if !ok {
			t.Fatalf("nothing stashed for the minted rendering (%+v)", b.tl.stash)
		}
		return st.signedMaster
	}

	off := signedFor(TimelineOptions{}, "off")
	if !strings.Contains(off, "gain=off") || strings.Contains(off, "crossfadeSeconds") {
		t.Fatalf("plain mint: %s", off)
	}

	// -24 LUFS against the -18 target is a 6 dB lift, and -12 dBTP has
	// room for it.
	on := signedFor(TimelineOptions{CrossfadeSeconds: 4.5, ReplayGain: true}, "6")
	if !strings.Contains(on, "gain=6") {
		t.Fatalf("levelled mint did not carry the derived gain: %s", on)
	}
	if !strings.Contains(on, "crossfadeSeconds=4.5") {
		t.Fatalf("levelled mint did not carry the crossfade: %s", on)
	}

	// Asking to level a queue nothing has measured is not an error and
	// not a guess: it renders as mastered.
	unmeasured := []TimelineMember{{PID: "tr-one", Src: Source{Path: path, DurationMS: 60000}}}
	res, err := b.TimelineFor(context.Background(), "us-alice", unmeasured, TimelineOptions{ReplayGain: true})
	if err != nil {
		t.Fatal(err)
	}
	if res.JobPID != "" {
		t.Fatal("unexpected job")
	}
	b.tl.mu.Lock()
	st := b.tl.stash[timelineKey("digest123", renderKey("aac", "off", 0))]
	b.tl.mu.Unlock()
	if !strings.Contains(st.signedMaster, "gain=off") {
		t.Fatalf("unmeasured queue levelled anyway: %s", st.signedMaster)
	}
}

// ageTimelines backdates every listener's last fetch and every slot's
// acquire time, which is how a test reaches the state a quiet minute
// produces without waiting one.
func ageTimelines(b *Bridge, by time.Duration) {
	ts := b.timelines()
	ts.mu.Lock()
	defer ts.mu.Unlock()
	for key, st := range ts.stash {
		for user, at := range st.listeners {
			st.listeners[user] = at.Add(-by)
		}
		ts.stash[key] = st
	}
	for user, slot := range ts.slots {
		slot.taken = slot.taken.Add(-by)
		ts.slots[user] = slot
	}
}

// TestTimelineSlotsAreHeldPerListener pins that two accounts playing the
// same queue in the same rendering share the row without sharing a
// listen: the key is a content digest, so one listener's mint used to
// take the row over and the other's fetches then counted for nobody -
// the sweep took her slot back a minute into a track she was still
// fetching.
func TestTimelineSlotsAreHeldPerListener(t *testing.T) {
	b, path := newTimelineBridge(t)
	gate := &fakeGate{}
	b.SetTranscodeGate(gate)
	members := []TimelineMember{{PID: "tr-one", Src: Source{Path: path, DurationMS: 60000}}}

	alice, err := b.TimelineFor(context.Background(), "us-alice", members, TimelineOptions{})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := b.TimelineFor(context.Background(), "us-bob", members, TimelineOptions{}); err != nil {
		t.Fatal(err)
	}
	if gate.held != 2 {
		t.Fatalf("held %d, want a slot each", gate.held)
	}

	// Only Alice is still fetching. Bob's went quiet, so his goes back
	// and hers does not.
	ageTimelines(b, 2*timelineIdle)
	rec := httptest.NewRecorder()
	b.ServeHLS(rec, httptest.NewRequest(http.MethodGet, alice.URL, nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("alice's master: %d: %s", rec.Code, rec.Body.String())
	}
	b.SweepTimelineSlots()
	if gate.held != 1 {
		t.Fatalf("held %d, want only the listener still fetching", gate.held)
	}

	// And hers still serves, which is the thing the sweep must not have
	// broken: a released slot is re-acquired on the next fetch, so a
	// wrongly released one shows up as a second acquire rather than an
	// error.
	acquired := gate.acquired
	rec = httptest.NewRecorder()
	b.ServeHLS(rec, httptest.NewRequest(http.MethodGet, alice.URL, nil))
	if rec.Code != http.StatusOK || gate.acquired != acquired {
		t.Fatalf("status %d, acquired %d->%d: alice never lost her slot",
			rec.Code, acquired, gate.acquired)
	}
}

// TestTimelineFailedMintKeepsALiveSlot pins that a mint that fails
// beside one that worked hands back nothing. Both ride the one slot the
// listener holds, so an unconditional give-back left the good rendering
// streaming outside the cap and outside what the console reports.
func TestTimelineFailedMintKeepsALiveSlot(t *testing.T) {
	b, path := newTimelineBridge(t)
	gate := &fakeGate{}
	b.SetTranscodeGate(gate)

	if _, err := b.TimelineFor(context.Background(), "us-alice",
		[]TimelineMember{{PID: "tr-one", Src: Source{Path: path, DurationMS: 60000}}},
		TimelineOptions{}); err != nil {
		t.Fatal(err)
	}
	if gate.held != 1 {
		t.Fatalf("held %d, want the one slot", gate.held)
	}

	// A member outside every root: refused, and refused as a queue the
	// engine cannot render rather than as the server being broken.
	_, err := b.TimelineFor(context.Background(), "us-alice",
		[]TimelineMember{{PID: "tr-two", Src: Source{Path: filepath.Join(t.TempDir(), "elsewhere.flac"), DurationMS: 1000}}},
		TimelineOptions{})
	if !errors.Is(err, ErrTimelineUnrenderable) {
		t.Fatalf("mint error %v, want the unrenderable refusal", err)
	}
	if gate.held != 1 {
		t.Fatalf("held %d after a failed mint, want the live one kept", gate.held)
	}
}

// TestTimelineFetchForADeadRenderingTakesNoSlot pins that a player
// looping on a URL this server no longer holds costs nothing: it used to
// take a fresh slot per retry and get its not-found anyway, so one dead
// client refused other listeners' live mints a minute at a time.
func TestTimelineFetchForADeadRenderingTakesNoSlot(t *testing.T) {
	b, path := newTimelineBridge(t)
	gate := &fakeGate{}
	b.SetTranscodeGate(gate)
	res, err := b.TimelineFor(context.Background(), "us-alice",
		[]TimelineMember{{PID: "tr-one", Src: Source{Path: path, DurationMS: 60000}}},
		TimelineOptions{})
	if err != nil {
		t.Fatal(err)
	}
	ageTimelines(b, 2*timelineIdle)
	ts := b.timelines()
	ts.mu.Lock()
	for key := range ts.stash {
		delete(ts.stash, key)
	}
	ts.mu.Unlock()
	b.SweepTimelineSlots()

	acquired := gate.acquired
	rec := httptest.NewRecorder()
	b.ServeHLS(rec, httptest.NewRequest(http.MethodGet, res.URL, nil))
	if rec.Code != http.StatusNotFound {
		t.Fatalf("status %d, want the not-found that says re-request", rec.Code)
	}
	if gate.acquired != acquired || gate.held != 0 {
		t.Fatalf("acquired %d->%d held %d, want nothing spent on a dead URL",
			acquired, gate.acquired, gate.held)
	}
}

// TestTimelineFormatHonoursTheBitrateCeiling pins that an account with a
// quality ceiling is not handed a lossless rendering of a whole queue by
// the same server that caps its single tracks - including when the
// caller asked for lossless first, which says what it can decode and not
// what it is allowed.
func TestTimelineFormatHonoursTheBitrateCeiling(t *testing.T) {
	b, path := newTimelineBridge(t)
	b.SetTranscodeGate(&fakeGate{ceiling: 192})
	res, err := b.TimelineFor(context.Background(), "us-alice",
		[]TimelineMember{{PID: "tr-one", Src: Source{Path: path, DurationMS: 60000}}},
		TimelineOptions{Formats: []string{"flac", "aac"}})
	if err != nil {
		t.Fatal(err)
	}
	if res.Format != "aac" {
		t.Fatalf("format %q, want the lossy one a ceiling leaves", res.Format)
	}
}

// A client that stops playing releases its rendering, and the slot goes
// back without waiting the idle window out. The rendering itself stays:
// the URL keeps working, and a fetch takes the slot again.
func TestReleaseTimelineGivesTheSlotBack(t *testing.T) {
	b, path := newTimelineBridge(t)
	gate := &fakeGate{}
	b.SetTranscodeGate(gate)
	members := []TimelineMember{{PID: "tr-one", Src: Source{Path: path, DurationMS: 60000}}}

	res, err := b.TimelineFor(context.Background(), "us-alice", members, TimelineOptions{})
	if err != nil {
		t.Fatal(err)
	}
	if res.PID == "" || !strings.HasPrefix(res.PID, "tl-") {
		t.Fatalf("pid = %q, want a tl- id", res.PID)
	}
	if gate.held != 1 {
		t.Fatalf("held %d, want one slot", gate.held)
	}

	id := strings.TrimPrefix(res.PID, "tl-")
	if !b.ReleaseTimeline("us-alice", id) {
		t.Fatal("releasing a live timeline answered false")
	}
	if gate.held != 0 {
		t.Fatalf("held %d after the release, want the slot back at once", gate.held)
	}

	// The rendering is still there for anyone still on it, and resuming
	// takes a slot again the way a swept listen does.
	rec := httptest.NewRecorder()
	b.ServeHLS(rec, httptest.NewRequest(http.MethodGet, res.URL, nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("master after the release: %d: %s", rec.Code, rec.Body.String())
	}
	if gate.acquired != 2 || gate.held != 1 {
		t.Fatalf("acquired %d held %d, want the slot taken again", gate.acquired, gate.held)
	}
}

// The listener with two renderings: releasing one keeps the slot the
// other is still being fetched for, and releasing a rendering they
// stopped fetching an hour ago keeps nothing.
func TestReleaseTimelineWeighsTheOtherRenderings(t *testing.T) {
	b, path := newTimelineBridge(t)
	gate := &fakeGate{}
	b.SetTranscodeGate(gate)
	members := []TimelineMember{{PID: "tr-one", Src: Source{Path: path, DurationMS: 60000}}}

	first, err := b.TimelineFor(context.Background(), "us-alice", members, TimelineOptions{})
	if err != nil {
		t.Fatal(err)
	}
	second, err := b.TimelineFor(context.Background(), "us-alice", members,
		TimelineOptions{Formats: []string{"flac"}})
	if err != nil {
		t.Fatal(err)
	}
	if first.PID == second.PID {
		t.Fatalf("two renderings share one pid: %s", first.PID)
	}
	if gate.acquired != 1 || gate.held != 1 {
		t.Fatalf("acquired %d held %d, want the one shared slot", gate.acquired, gate.held)
	}

	if !b.ReleaseTimeline("us-alice", strings.TrimPrefix(first.PID, "tl-")) {
		t.Fatal("releasing the first rendering answered false")
	}
	if gate.held != 1 {
		t.Fatalf("held %d, want the slot the second rendering is on", gate.held)
	}

	// Back on both, then quiet on both. Releasing one now leaves the
	// other still listing this listener, so presence alone would keep
	// the slot: what decides is that nothing of hers has been fetched
	// inside the idle window.
	if _, err := b.TimelineFor(context.Background(), "us-alice", members, TimelineOptions{}); err != nil {
		t.Fatal(err)
	}
	ageTimelines(b, 2*timelineIdle)
	if !b.ReleaseTimeline("us-alice", strings.TrimPrefix(second.PID, "tl-")) {
		t.Fatal("releasing the second rendering answered false")
	}
	if gate.held != 0 {
		t.Fatalf("held %d, want the slot back", gate.held)
	}
}

// An id that names nothing live is not a release: the handler turns
// this into a 404 rather than pretending a slot went back.
func TestReleaseTimelineRefusesUnknownIds(t *testing.T) {
	b, path := newTimelineBridge(t)
	gate := &fakeGate{}
	b.SetTranscodeGate(gate)
	res, err := b.TimelineFor(context.Background(), "us-alice",
		[]TimelineMember{{PID: "tr-one", Src: Source{Path: path, DurationMS: 60000}}}, TimelineOptions{})
	if err != nil {
		t.Fatal(err)
	}
	if b.ReleaseTimeline("us-alice", "01JZX5N8QW3F4V9T2B7KD3M9R6") {
		t.Fatal("an id nothing minted answered true")
	}

	id := strings.TrimPrefix(res.PID, "tl-")
	ts := b.timelines()
	ts.mu.Lock()
	for key, st := range ts.stash {
		st.expires = time.Now().Add(-time.Minute)
		ts.stash[key] = st
	}
	ts.mu.Unlock()
	if b.ReleaseTimeline("us-alice", id) {
		t.Fatal("an expired rendering answered true")
	}
}

// A release that arrives while the same listener's next mint is still
// assembling its rendering. The stash says nothing about them in that
// window, so a release reading it would hand back the slot the new
// rendering is about to stream on.
func TestReleaseDuringAMintKeepsTheSlot(t *testing.T) {
	b, path := newTimelineBridge(t)
	gate := &fakeGate{}
	b.SetTranscodeGate(gate)
	members := []TimelineMember{{PID: "tr-one", Src: Source{Path: path, DurationMS: 60000}}}

	first, err := b.TimelineFor(context.Background(), "us-alice", members, TimelineOptions{})
	if err != nil {
		t.Fatal(err)
	}
	if gate.held != 1 {
		t.Fatalf("held %d, want the mint's slot", gate.held)
	}

	// The restart: its mint has taken the slot the first one held and
	// has not stashed anything yet. The release for the rendering that
	// stopped lands in exactly that window.
	ts := b.timelines()
	ts.mu.Lock()
	ts.minting["us-alice"]++
	ts.mu.Unlock()
	if !b.ReleaseTimeline("us-alice", strings.TrimPrefix(first.PID, "tl-")) {
		t.Fatal("releasing a live timeline answered false")
	}
	if gate.held != 1 {
		t.Fatalf("held %d, want the slot the mint in flight is on", gate.held)
	}

	// And when that mint gives up, its own failure path is what hands
	// the slot back: nothing is stashed for this listener any more and
	// no mint of theirs is left in flight, which is exactly the pair of
	// questions dropTimelineSlot asks.
	ts.mu.Lock()
	delete(ts.minting, "us-alice")
	ts.mu.Unlock()
	b.dropTimelineSlot("us-alice")
	if gate.held != 0 {
		t.Fatalf("held %d, want the slot back", gate.held)
	}
}

// TestFailedMintWithNothingLiveGivesTheSlotBack pins the other side of
// the in-flight window. A failed mint spares a slot while another mint
// of the same listener's is still assembling, which means it must stop
// counting itself first: a mint that spared its own slot would leave it
// held until the idle sweep, with nothing streaming on it.
func TestFailedMintWithNothingLiveGivesTheSlotBack(t *testing.T) {
	b, _ := newTimelineBridge(t)
	gate := &fakeGate{}
	b.SetTranscodeGate(gate)

	// A member outside every root, so the mint takes a slot and then
	// refuses, with nothing of this listener's live behind it.
	_, err := b.TimelineFor(context.Background(), "us-alice",
		[]TimelineMember{{PID: "tr-one", Src: Source{Path: filepath.Join(t.TempDir(), "elsewhere.flac"), DurationMS: 1000}}},
		TimelineOptions{})
	if !errors.Is(err, ErrTimelineUnrenderable) {
		t.Fatalf("mint error %v, want the unrenderable refusal", err)
	}
	if gate.held != 0 {
		t.Fatalf("held %d after the only mint failed, want the slot back", gate.held)
	}
}

// TestReleaseRefusesARenderingTheCallerIsNotOn pins that a release is
// about the caller's own listening. Answering a pid they were never on
// makes this an oracle for whether somebody else's rendering is live,
// and hands back the caller's slot as a side effect of asking.
func TestReleaseRefusesARenderingTheCallerIsNotOn(t *testing.T) {
	b, path := newTimelineBridge(t)
	gate := &fakeGate{}
	b.SetTranscodeGate(gate)
	members := []TimelineMember{{PID: "tr-one", Src: Source{Path: path, DurationMS: 60000}}}

	alice, err := b.TimelineFor(context.Background(), "us-alice", members, TimelineOptions{})
	if err != nil {
		t.Fatal(err)
	}
	// A different rendering, not just a different queue: the sidecar
	// keys renderings by the digest and the encoder settings, so two
	// listeners asking for the same format are on the same one.
	bob, err := b.TimelineFor(context.Background(), "us-bob", members,
		TimelineOptions{Formats: []string{"flac"}})
	if err != nil {
		t.Fatal(err)
	}
	if bob.PID == alice.PID {
		t.Fatal("both mints landed on one rendering")
	}
	if gate.held != 2 {
		t.Fatalf("held %d, want a slot each", gate.held)
	}

	if b.ReleaseTimeline("us-bob", strings.TrimPrefix(alice.PID, "tl-")) {
		t.Fatal("releasing a rendering the caller is not on answered true")
	}
	if gate.held != 2 {
		t.Fatalf("held %d, want both slots left alone", gate.held)
	}
	// Their own still works, which is what says the refusal was about
	// whose rendering it is rather than about the id.
	if !b.ReleaseTimeline("us-bob", strings.TrimPrefix(bob.PID, "tl-")) {
		t.Fatal("releasing their own rendering answered false")
	}
	if gate.held != 1 {
		t.Fatalf("held %d, want alice's alone", gate.held)
	}
}
