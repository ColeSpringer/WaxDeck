package flow

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/auth"
)

// switchedEngine is a fake sidecar a test takes away and brings back.
// Away, it drops every connection unanswered, which is what a request
// meets when the engine process is gone; refusing, it answers every
// request as WaxFlow answers a key it does not hold.
type switchedEngine struct {
	srv      *httptest.Server
	away     atomic.Bool
	refuse   atomic.Bool
	requests atomic.Int32
	streams  atomic.Int32
}

func newSwitchedEngine(t *testing.T) *switchedEngine {
	t.Helper()
	e := &switchedEngine{}
	e.srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		e.requests.Add(1)
		if e.away.Load() {
			conn, _, err := w.(http.Hijacker).Hijack()
			if err == nil {
				conn.Close()
			}
			return
		}
		if e.refuse.Load() {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusUnauthorized)
			io.WriteString(w, `{"error":"missing or invalid API key","code":"unauthorized","schemaVersion":1}`)
			return
		}
		switch r.URL.Path {
		case "/caps":
			fmt.Fprint(w, capsJSON())
		case "/stream":
			e.streams.Add(1)
			io.WriteString(w, "engine bytes")
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(e.srv.Close)
	return e
}

// lockedBuffer collects log output written from several goroutines.
type lockedBuffer struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (b *lockedBuffer) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.Write(p)
}

func (b *lockedBuffer) count(s string) int {
	b.mu.Lock()
	defer b.mu.Unlock()
	return strings.Count(b.buf.String(), s)
}

func newEngineBridge(t *testing.T, base string, src Source, log *slog.Logger) *Bridge {
	t.Helper()
	b, err := New(context.Background(), Config{
		BaseURL:  base,
		APIKey:   "key",
		Roots:    []Root{{Name: "lib", Path: filepath.Dir(src.Path)}},
		Tokens:   auth.NewMediaTokens([]byte("test-secret-test-secret-test-sec"), 0),
		Resolver: staticResolver{src},
		Logger:   log,
	})
	if err != nil {
		t.Fatal(err)
	}
	b.SetTranscodeGate(&fakeGate{})
	return b
}

func flacSource(t *testing.T) Source {
	t.Helper()
	path := filepath.Join(t.TempDir(), "song.flac")
	if err := os.WriteFile(path, []byte("flacbytes"), 0o644); err != nil {
		t.Fatal(err)
	}
	return Source{Path: path, Size: 9, MTimeNS: 42, Codec: "flac", Container: "flac", DurationMS: 5000}
}

// connectedBridge is a bridge whose engine has answered once.
func connectedBridge(t *testing.T, e *switchedEngine, src Source) *Bridge {
	t.Helper()
	b := newEngineBridge(t, e.srv.URL, src, nil)
	if err := b.Connect(context.Background()); err != nil {
		t.Fatal(err)
	}
	return b
}

// awaitSignal waits for one signal on ch, failing the test when none
// lands in a generous window.
func awaitSignal(t *testing.T, ch <-chan struct{}, what string) {
	t.Helper()
	select {
	case <-ch:
	case <-time.After(10 * time.Second):
		t.Fatalf("timed out waiting for %s", what)
	}
}

// New asks nothing of the engine, so a server starts whether or not it
// answers, and the bridge reads as no engine until it does.
func TestNewAnswersAtOnceWithoutTheSidecar(t *testing.T) {
	e := newSwitchedEngine(t)
	b := newEngineBridge(t, e.srv.URL, flacSource(t), nil)
	if n := e.requests.Load(); n != 0 {
		t.Fatalf("New made %d requests of the engine, want none", n)
	}
	if b.Up() || b.Caps() != nil {
		t.Fatal("a bridge that has heard nothing reads as up")
	}
	if b.JobsSupported() || b.TimelinesSupported() || b.TimelineMemberWindowsSupported() ||
		b.RootsReloadSupported() || b.SilenceDetectorVersion() != "" {
		t.Fatal("a bridge that has heard nothing claims a capability")
	}
	if st := b.Status(); st != (Status{}) {
		t.Fatalf("status = %+v, want the zero status", st)
	}

	var none *Bridge
	if none.Up() || none.Caps() != nil || none.Status() != (Status{}) {
		t.Fatal("a server without a bridge reads as having an engine")
	}

	dead := httptest.NewServer(http.NotFoundHandler())
	deadURL := dead.URL
	dead.Close()
	b = newEngineBridge(t, deadURL, flacSource(t), nil)
	if err := b.Connect(context.Background()); err == nil {
		t.Fatal("Connect to a closed port answered nil")
	}
	if b.Up() {
		t.Fatal("a refused connect left the bridge up")
	}
}

// Run keeps asking until the engine answers, says so once each way, and
// runs the hooks on every crossing.
func TestTheBridgeConnectsWhenTheSidecarAppears(t *testing.T) {
	e := newSwitchedEngine(t)
	e.away.Store(true)
	logs := &lockedBuffer{}
	b := newEngineBridge(t, e.srv.URL, flacSource(t), slog.New(slog.NewTextHandler(logs, nil)))
	b.retryMin, b.retryMax, b.probeEvery = time.Millisecond, 4*time.Millisecond, 2*time.Millisecond

	ups := make(chan struct{}, 8)
	downs := make(chan struct{}, 8)
	var upCount, downCount atomic.Int32
	b.OnUp(func(context.Context, Status) {
		upCount.Add(1)
		ups <- struct{}{}
	})
	b.OnDown(func() {
		downCount.Add(1)
		downs <- struct{}{}
	})
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- b.Run(ctx) }()
	stopped := false
	stop := func() {
		if !stopped {
			stopped = true
			cancel()
			if err := <-done; err != nil {
				t.Errorf("Run = %v, want nil once its context ends", err)
			}
		}
	}
	defer stop()

	awaitSignal(t, downs, "the first ask failing")
	if b.Up() {
		t.Fatal("up before the engine answered")
	}
	e.away.Store(false)
	awaitSignal(t, ups, "the engine answering")
	if !b.Up() || !b.Status().Connected || !b.Status().VoiceBoost {
		t.Fatalf("after the engine answered: up %v, status %+v", b.Up(), b.Status())
	}
	e.away.Store(true)
	awaitSignal(t, downs, "the engine going away")
	if b.Up() {
		t.Fatal("still up after the engine went away")
	}
	e.away.Store(false)
	awaitSignal(t, ups, "the engine coming back")
	stop()

	if n := upCount.Load(); n != 2 {
		t.Errorf("OnUp ran %d times, want once per crossing (2)", n)
	}
	if n := downCount.Load(); n != 2 {
		t.Errorf("OnDown ran %d times, want once per crossing (2)", n)
	}
	if n := logs.count("level=WARN msg=\"streaming engine unreachable; serving originals directly until it answers\""); n != 1 {
		t.Errorf("unreachable warned %d times, want once for the one loss:\n%s", n, logs.buf.String())
	}
	if n := logs.count("level=INFO msg=\"streaming engine not answering yet"); n != 1 {
		t.Errorf("the startup failure said %d times, want once:\n%s", n, logs.buf.String())
	}
	if n := logs.count("waxflow bridge up"); n != 2 {
		t.Errorf("bridge up logged %d times, want once per return (2)", n)
	}
}

// A stream that cannot reach the engine takes the bridge down at once
// and asks Run for a probe, rather than waiting out the probe interval.
func TestAProxyErrorMarksTheBridgeDown(t *testing.T) {
	e := newSwitchedEngine(t)
	b := connectedBridge(t, e, flacSource(t))
	streamURL := tokenURL(t, b, "tr-X")
	e.away.Store(true)

	rec := httptest.NewRecorder()
	b.ServeStream(rec, httptest.NewRequest("GET", streamURL, nil))
	if rec.Code != http.StatusBadGateway {
		t.Fatalf("status = %d, want 502 for the request that found the engine gone", rec.Code)
	}
	if b.Up() {
		t.Fatal("the bridge is still up after the proxy failed to reach the engine")
	}
	select {
	case <-b.kick:
	default:
		t.Fatal("no probe was asked for")
	}
}

// A request that finds the engine gone is a loss the moment it does: the
// outage is said, and the probe it asks for tells the hooks of it before
// those of the return the answer makes, carrying what the engine offers
// in that answer. Without the crossing a blip the probe overturns would
// leave the service's record and a root refused in the window wrong, with
// nothing to correct them.
func TestALostEngineCrossesAndTheNextAnswerCrossesBack(t *testing.T) {
	e := newSwitchedEngine(t)
	logs := &lockedBuffer{}
	b := newEngineBridge(t, e.srv.URL, flacSource(t), slog.New(slog.NewTextHandler(logs, nil)))
	var told []string
	var ups []Status
	b.OnDown(func() { told = append(told, "down") })
	b.OnUp(func(_ context.Context, st Status) {
		told = append(told, "up")
		ups = append(ups, st)
	})
	connect(t, b)

	b.lost(errors.New("connection reset by peer"))
	if b.Up() {
		t.Fatal("after a loss the bridge is still up")
	}
	select {
	case <-b.kick:
	default:
		t.Fatal("a loss asked for no probe")
	}
	b.lost(errors.New("again"))
	if n := logs.count("level=WARN msg=\"streaming engine unreachable"); n != 1 {
		t.Fatalf("the loss warned %d times, want once", n)
	}

	connect(t, b)
	if want := []string{"up", "down", "up"}; !slices.Equal(told, want) {
		t.Fatalf("hooks told %v, want %v: the outage once, then the return", told, want)
	}
	if st := ups[1]; !st.Connected || !st.VoiceBoost {
		t.Fatalf("the return said %+v, want what the answer offers", st)
	}
}

// An engine that refuses this server's API key is a setting only an
// administrator can fix, so the log says so at ERROR, naming both
// settings, once per crossing, and never as an engine that is not
// answering: not even when it was not answering a moment before, which
// is every boot under compose.
func TestARefusedKeyIsSaidAsOne(t *testing.T) {
	e := newSwitchedEngine(t)
	e.away.Store(true)
	logs := &lockedBuffer{}
	b := newEngineBridge(t, e.srv.URL, flacSource(t), slog.New(slog.NewTextHandler(logs, nil)))
	ctx := context.Background()
	const refused = `level=ERROR msg="the streaming engine refused this server's API key: --flow-api-key (WAXDECK_FLOW_API_KEY) must be one the engine accepts (WAXFLOW_API_KEYS)`

	if b.Connect(ctx) == nil {
		t.Fatal("an engine that is not there answered")
	}
	e.away.Store(false)
	e.refuse.Store(true)
	for range 2 {
		if b.Connect(ctx) == nil {
			t.Fatal("an engine refusing the key answered")
		}
	}
	if b.Up() {
		t.Fatal("up on an engine that refused the key")
	}
	if n := logs.count(refused); n != 1 {
		t.Fatalf("the refusal was said %d times, want once:\n%s", n, logs.buf.String())
	}

	e.refuse.Store(false)
	connect(t, b)
	e.refuse.Store(true)
	if b.Connect(ctx) == nil {
		t.Fatal("an engine refusing the key answered")
	}
	if n := logs.count(refused); n != 2 {
		t.Fatalf("the refusal was said %d times, want once per crossing (2):\n%s", n, logs.buf.String())
	}
	if n := logs.count("streaming engine unreachable"); n != 0 {
		t.Fatalf("a refused key was called unreachable:\n%s", logs.buf.String())
	}
	if n := logs.count("streaming engine not answering yet"); n != 1 {
		t.Fatalf("not answering said %d times, want once, for the boot:\n%s", n, logs.buf.String())
	}
}

// A listener who gave up on a stream before the engine answered is not
// an outage: nothing is crossed and no probe is asked for.
func TestALeavingListenerIsNoOutage(t *testing.T) {
	asked := make(chan struct{}, 1)
	engine := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/caps" {
			fmt.Fprint(w, capsJSON())
			return
		}
		asked <- struct{}{}
		<-r.Context().Done()
	}))
	t.Cleanup(engine.Close)
	b := newEngineBridge(t, engine.URL, flacSource(t), nil)
	connect(t, b)
	ctx, cancel := context.WithCancel(context.Background())
	req := httptest.NewRequest("GET", tokenURL(t, b, "tr-X"), nil).WithContext(ctx)
	done := make(chan struct{})
	go func() {
		defer close(done)
		b.ServeStream(httptest.NewRecorder(), req)
	}()
	<-asked
	cancel()
	<-done
	if !b.Up() {
		t.Fatal("a listener leaving took the engine down")
	}
	select {
	case <-b.kick:
		t.Fatal("a listener leaving asked for a probe")
	default:
	}
}

// While the engine is away no mint names it.
func TestPlayInfoMintsNothingWhileDown(t *testing.T) {
	e := newSwitchedEngine(t)
	src := flacSource(t)
	b := newEngineBridge(t, e.srv.URL, src, nil)
	if _, err := b.PlayInfoForSource(context.Background(), "us-1", "tr-X", src, PlayOptions{}); !errors.Is(err, ErrEngineDown) {
		t.Fatalf("PlayInfoForSource = %v, want ErrEngineDown", err)
	}
	if _, err := b.PlayInfoFor(context.Background(), "us-1", "tr-X", PlayOptions{}); !errors.Is(err, ErrEngineDown) {
		t.Fatalf("PlayInfoFor = %v, want ErrEngineDown", err)
	}
	if _, err := b.JoinedPlayInfo(context.Background(), "us-1", "bk-X", PlayOptions{}); !errors.Is(err, ErrEngineDown) {
		t.Fatalf("JoinedPlayInfo = %v, want ErrEngineDown", err)
	}
	if _, err := b.TimelineFor(context.Background(), "us-1", nil, TimelineOptions{}); !errors.Is(err, ErrEngineDown) {
		t.Fatalf("TimelineFor = %v, want ErrEngineDown", err)
	}
	if n := e.requests.Load(); n != 0 {
		t.Fatalf("the engine was asked %d times while down", n)
	}
}

// An original minted while the engine was up keeps playing through an
// outage: the stream route hands it to the download route under the
// same token and validator.
func TestServeStreamRedirectsAnOriginalWhileDown(t *testing.T) {
	e := newSwitchedEngine(t)
	src := flacSource(t)
	b := connectedBridge(t, e, src)

	for _, tc := range []struct {
		name string
		url  string
		keep url.Values
	}{
		{name: "an original", url: tokenURL(t, b, "tr-X")},
		{name: "a book part", url: mintURL(t, b, "bk-X", PlayOptions{FilePID: "fi-2"}), keep: url.Values{"f": {"fi-2"}}},
		{name: "a copy of the source", url: shapedURL(t, b, "tr-X", url.Values{"fmt": {"flac"}}), keep: url.Values{"fmt": {"flac"}}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			b.lost(errors.New("gone"))
			streams := e.streams.Load()
			minted, err := url.Parse(tc.url)
			if err != nil {
				t.Fatal(err)
			}
			rec := httptest.NewRecorder()
			b.ServeStream(rec, httptest.NewRequest("GET", tc.url, nil))
			if rec.Code != http.StatusFound {
				t.Fatalf("status = %d (%s), want 302", rec.Code, rec.Body.String())
			}
			loc, err := url.Parse(rec.Header().Get("Location"))
			if err != nil {
				t.Fatal(err)
			}
			q := loc.Query()
			if loc.Path != "/media/download" || q.Get("pid") != minted.Query().Get("pid") {
				t.Fatalf("Location = %s, want the download route for the same pid", loc)
			}
			if q.Get("mt") != minted.Query().Get("mt") {
				t.Fatal("the redirect does not carry the minted token")
			}
			if q.Get("id") != "9-42" {
				t.Fatalf("id = %q, want the file's validator 9-42", q.Get("id"))
			}
			for k := range tc.keep {
				if q.Get(k) != tc.keep.Get(k) {
					t.Fatalf("%s = %q, want %q kept for the token's shape", k, q.Get(k), tc.keep.Get(k))
				}
			}
			if e.streams.Load() != streams {
				t.Fatal("the engine was asked for the stream while down")
			}
		})
	}
}

// mintURL mints a stream URL with options while the bridge is up.
func mintURL(t *testing.T, b *Bridge, pid string, opts PlayOptions) string {
	t.Helper()
	info, err := b.PlayInfoFor(context.Background(), "us-1", pid, opts)
	if err != nil {
		t.Fatal(err)
	}
	return info.URL
}

// decodeEngineDown checks the refusal a request meets while the engine
// is away.
func decodeEngineDown(t *testing.T, rec *httptest.ResponseRecorder) {
	t.Helper()
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d (%s), want 503", rec.Code, rec.Body.String())
	}
	if got := rec.Header().Get("Retry-After"); got != "15" {
		t.Fatalf("Retry-After = %q, want 15", got)
	}
	var body struct {
		Code   string            `json:"code"`
		Params map[string]string `json:"params"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("body %q: %v", rec.Body.String(), err)
	}
	if body.Code != "feature-unavailable" || body.Params["feature"] != "streaming-engine" {
		t.Fatalf("body = %s, want feature-unavailable naming the streaming engine", rec.Body.String())
	}
}

// What only the engine can make is refused while it is away, in words a
// client can act on, and nothing reaches the engine.
func TestServeStreamRefusesAnEngineShapeWhileDown(t *testing.T) {
	e := newSwitchedEngine(t)
	src := flacSource(t)
	b := connectedBridge(t, e, src)
	virtual := src
	virtual.Virtual, virtual.FromSample, virtual.ToSample = true, 44100, 88200
	vb := connectedBridge(t, e, virtual)
	cut := tokenURL(t, b, "tr-X") + "&t=12"

	for _, tc := range []struct {
		name string
		b    *Bridge
		url  string
	}{
		{"voice boost", b, shapedURL(t, b, "tr-X", url.Values{"vb": {"1"}})},
		{"a format", b, shapedURL(t, b, "tr-X", url.Values{"fmt": {"mp3"}})},
		{"a bitrate", b, shapedURL(t, b, "tr-X", url.Values{"fmt": {"opus"}, "enc": {"1"}, "br": {"128"}})},
		{"a window", vb, tokenURL(t, vb, "tr-V")},
		{"a joined book", b, shapedURL(t, b, "bk-X", url.Values{"f": {"fi-1"}, "join": {"1"}, "fmt": {"mp3"}, "br": {"64"}})},
	} {
		t.Run(tc.name, func(t *testing.T) {
			tc.b.lost(errors.New("gone"))
			before := e.requests.Load()
			rec := httptest.NewRecorder()
			tc.b.ServeStream(rec, httptest.NewRequest("GET", tc.url, nil))
			decodeEngineDown(t, rec)
			if e.requests.Load() != before {
				t.Fatal("the engine was asked while down")
			}
		})
	}

	// A cut is the engine's to make; on an original it is the same 400
	// the route answers with the engine up.
	b.lost(errors.New("gone"))
	rec := httptest.NewRecorder()
	b.ServeStream(rec, httptest.NewRequest("GET", cut, nil))
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("t on an original while away = %d, want 400", rec.Code)
	}

	// A bad token is still a bad token, whatever the engine is doing.
	b.lost(errors.New("gone"))
	rec = httptest.NewRecorder()
	b.ServeStream(rec, httptest.NewRequest("GET", "/media/stream?pid=tr-X&mt=forged", nil))
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("forged token while down = %d, want 401", rec.Code)
	}
}

// The HLS surface and the analysis pull answer the same refusal.
func TestTheEngineSurfacesRefuseWhileDown(t *testing.T) {
	e := newSwitchedEngine(t)
	b := connectedBridge(t, e, flacSource(t))
	key := timelineKey("tl-digest", renderKey("aac", "off", 0, 0))
	token, _ := b.tokens.MintFor(auth.MediaClaims{User: "us-1", Purpose: auth.PurposeHLS, PID: TimelinePIDPrefix + key}, 0)
	master := "/media/hls/master.m3u8?tl=tl-digest&rk=" + url.QueryEscape(renderKey("aac", "off", 0, 0)) + "&mt=" + url.QueryEscape(token)

	// Up, the stash holds nothing for it: the refusal below is the
	// engine's state, not the rendering's.
	rec := httptest.NewRecorder()
	b.ServeHLS(rec, httptest.NewRequest("GET", master, nil))
	if rec.Code != http.StatusNotFound {
		t.Fatalf("up: status = %d, want 404 for a rendering never minted", rec.Code)
	}

	b.lost(errors.New("gone"))
	rec = httptest.NewRecorder()
	b.ServeHLS(rec, httptest.NewRequest("GET", master, nil))
	decodeEngineDown(t, rec)

	rec = httptest.NewRecorder()
	b.ServeAnalysisAudio(rec, httptest.NewRequest("GET", "/media/analysis/tr-X", nil), "tr-X")
	decodeEngineDown(t, rec)
}

// connect brings a test's bridge up against its fake engine, as Run does
// on the engine's first answer.
func connect(t *testing.T, b *Bridge) {
	t.Helper()
	if err := b.Connect(context.Background()); err != nil {
		t.Fatal(err)
	}
}

// slowWriter is a listener whose writes block a while: a player that
// paused, its buffer full, the socket backed up.
type slowWriter struct {
	*httptest.ResponseRecorder
	hold time.Duration
}

func (w slowWriter) Write(p []byte) (int, error) {
	time.Sleep(w.hold)
	return w.ResponseRecorder.Write(p)
}

// countCrossings counts a bridge's crossings each way.
func countCrossings(b *Bridge) (ups, downs *atomic.Int32) {
	ups, downs = new(atomic.Int32), new(atomic.Int32)
	b.OnUp(func(context.Context, Status) { ups.Add(1) })
	b.OnDown(func() { downs.Add(1) })
	return ups, downs
}

// wantProbeAsked checks that a request asked Run for a probe now.
func wantProbeAsked(t *testing.T, b *Bridge, what string) {
	t.Helper()
	select {
	case <-b.kick:
	default:
		t.Fatalf("%s asked for no probe", what)
	}
}

// An engine that stops sending partway through a stream cuts that stream
// once one read has waited past the stall limit, and asks for a probe at
// once. Only the probe says whether the engine is gone: a slow source
// under a healthy engine (a disk spinning up, a network mount) is one
// stream's trouble, so no crossing, no marker and no roots offered again.
func TestAStallMidStreamCutsOnlyItAndAsksForAProbe(t *testing.T) {
	stalled := make(chan struct{})
	engine := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/caps" {
			fmt.Fprint(w, capsJSON())
			return
		}
		io.WriteString(w, "the first bytes")
		w.(http.Flusher).Flush()
		select {
		case <-stalled:
		case <-r.Context().Done():
		}
	}))
	t.Cleanup(engine.Close)
	t.Cleanup(func() { close(stalled) })
	logs := &lockedBuffer{}
	b := newEngineBridge(t, engine.URL, flacSource(t), slog.New(slog.NewTextHandler(logs, nil)))
	b.stallLimit = 50 * time.Millisecond
	ups, downs := countCrossings(b)
	connect(t, b)

	rec := httptest.NewRecorder()
	b.ServeStream(rec, httptest.NewRequest("GET", tokenURL(t, b, "tr-X"), nil))
	if got := rec.Body.String(); got != "the first bytes" {
		t.Fatalf("body = %q, want what the engine sent before it stalled", got)
	}
	if !b.Up() {
		t.Fatal("one stalled stream took the engine down")
	}
	wantProbeAsked(t, b, "a stall")
	connect(t, b) // the probe it asked for, which the engine answers
	if downs.Load() != 0 || ups.Load() != 1 {
		t.Fatalf("a stall crossed the engine: OnDown ran %d times, OnUp %d; want 0 and the first answer's 1", downs.Load(), ups.Load())
	}
	if n := logs.count("streaming engine unreachable"); n != 0 {
		t.Fatalf("a stall was logged as an outage:\n%s", logs.buf.String())
	}
}

// A stream whose headers never come answers 502 at the stall limit, the
// refusal that sends a player to mint again, and asks for a probe, which
// decides the engine's state rather than the stall.
func TestAStreamWhoseHeadersNeverComeIsAGatewayErrorAndAProbe(t *testing.T) {
	hung := make(chan struct{})
	engine := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/caps" {
			fmt.Fprint(w, capsJSON())
			return
		}
		select {
		case <-hung:
		case <-r.Context().Done():
		}
	}))
	t.Cleanup(engine.Close)
	t.Cleanup(func() { close(hung) })
	b := newEngineBridge(t, engine.URL, flacSource(t), nil)
	b.stallLimit = 50 * time.Millisecond
	ups, downs := countCrossings(b)
	connect(t, b)

	rec := httptest.NewRecorder()
	b.ServeStream(rec, httptest.NewRequest("GET", tokenURL(t, b, "tr-X"), nil))
	if rec.Code != http.StatusBadGateway {
		t.Fatalf("status = %d, want 502 for a stream whose headers never came", rec.Code)
	}
	if !b.Up() {
		t.Fatal("one stream's missing headers took the engine down")
	}
	wantProbeAsked(t, b, "a stream whose headers never came")
	connect(t, b)
	if downs.Load() != 0 || ups.Load() != 1 {
		t.Fatalf("the stall crossed the engine: OnDown ran %d times, OnUp %d", downs.Load(), ups.Load())
	}
}

// A listener who stops reading is never cut: the copy waits on its write,
// so no read of the engine is waiting while it does.
func TestAPausedListenerIsNotCut(t *testing.T) {
	engine := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/caps" {
			fmt.Fprint(w, capsJSON())
			return
		}
		for range 3 {
			io.WriteString(w, "chunk;")
			w.(http.Flusher).Flush()
		}
	}))
	t.Cleanup(engine.Close)
	b := newEngineBridge(t, engine.URL, flacSource(t), nil)
	b.stallLimit = 50 * time.Millisecond
	connect(t, b)

	w := slowWriter{ResponseRecorder: httptest.NewRecorder(), hold: 200 * time.Millisecond}
	b.ServeStream(w, httptest.NewRequest("GET", tokenURL(t, b, "tr-X"), nil))
	if got := w.Body.String(); got != "chunk;chunk;chunk;" {
		t.Fatalf("body = %q, want the whole stream through a slow listener", got)
	}
	if !b.Up() {
		t.Fatal("a slow listener took the engine down")
	}
}
