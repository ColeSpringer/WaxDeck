package service

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"sync/atomic"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/auth"
	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
)

// A change in what /health reports reaches every account as one pid-less
// marker; the word at startup and a repeat are no news.
func TestTheEngineStateMarksEveryAccountOnAChange(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	count := func() int { return markers(t, ctx, svc, uc.ID, eventServer, "") }

	svc.SetEngineState(ctx, EngineState{Configured: true})
	if n := count(); n != 0 {
		t.Fatalf("markers after the startup word = %d, want 0", n)
	}
	up := EngineState{Configured: true, Connected: true, Timelines: true, VoiceBoost: true, FileTools: true}
	svc.SetEngineState(ctx, up)
	if n := count(); n != 1 {
		t.Fatalf("markers after the engine answered = %d, want 1", n)
	}
	svc.SetEngineState(ctx, up)
	if n := count(); n != 1 {
		t.Fatalf("markers after the same state again = %d, want 1", n)
	}
	svc.SetEngineState(ctx, EngineState{Configured: true})
	if n := count(); n != 2 {
		t.Fatalf("markers after the engine went away = %d, want 2", n)
	}
	if st := svc.EngineState(); st != (EngineState{Configured: true}) {
		t.Fatalf("state = %+v, want configured and away", st)
	}
}

// The marker reaches clients the way they read events: through the
// server sync delta, not only as a stored row.
func TestTheServerMarkerRidesTheSyncDelta(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	svc.SetEngineState(ctx, EngineState{Configured: true})
	since, err := svc.MintServerCursor(ctx)
	if err != nil {
		t.Fatal(err)
	}
	svc.SetEngineState(ctx, EngineState{Configured: true, Connected: true})
	delta, err := svc.SyncServerDelta(ctx, uc, since, 100)
	if err != nil {
		t.Fatal(err)
	}
	if !slices.ContainsFunc(delta.Events, func(e ServerSyncEvent) bool { return e.Kind == eventServer && e.PID == "" }) {
		t.Fatalf("events = %+v, want a pid-less server marker", delta.Events)
	}
}

// A library created while the engine is away is taken by the bridge at
// once (it writes the root for the sidecar and reloads it when the engine
// answers), not held against it: the create says streaming waits for the
// engine, and nothing is remembered as refused.
func TestALibraryCreatedWhileTheEngineIsAwayIsTakenAndWaitsForIt(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	bridge := &fakeFlowRoots{names: []string{"lib"}}
	svc.SetEngineState(ctx, EngineState{Configured: true})
	svc.SetFlowRoots(bridge)

	dir := t.TempDir()
	info, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "books", Path: dir})
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(info.StreamingWarning, "when the streaming engine answers again") {
		t.Fatalf("streaming warning = %q, want it to wait for the engine", info.StreamingWarning)
	}
	if !bridge.taught("books", dir) {
		t.Fatal("the root did not reach the bridge while the engine was away")
	}
	svc.flowSyncMu.Lock()
	refused := svc.flowRefused["books"].path
	svc.flowSyncMu.Unlock()
	if refused != "" {
		t.Fatal("a root taken while the engine was away was remembered as refused")
	}
}

// A root the bridge refuses while the engine is away (a path this server
// cannot see) is refused in the bridge's words to the administrator who
// made the library, not hidden behind "waits for the engine".
func TestALibraryTheBridgeRefusesWhileTheEngineIsAwaySaysWhy(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	bridge := &fakeFlowRoots{names: []string{"lib"}, syncErr: errors.New("not a directory this server can see")}
	svc.SetEngineState(ctx, EngineState{Configured: true})
	svc.SetFlowRoots(bridge)

	info, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "books", Path: t.TempDir()})
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(info.StreamingWarning, "not a directory this server can see") {
		t.Fatalf("streaming warning = %q, want the bridge's reason", info.StreamingWarning)
	}
}

// Book merging names an engine that is away rather than one that is
// missing, which the administrator reads to wait rather than to set one
// up.
func TestBookMergingSaysTheEngineIsAway(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	admin := *uc
	admin.Admin = true

	_, err := svc.StartBookMerge(ctx, &admin, "bk-none", nil, true)
	if err == nil || err.Error() != "book merging needs the streaming engine" {
		t.Fatalf("without an engine: %v", err)
	}
	svc.SetEngineState(ctx, EngineState{Configured: true})
	_, err = svc.StartBookMerge(ctx, &admin, "bk-none", nil, true)
	if KindOf(err) != KindFeature || err.Error() != "book merging needs the streaming engine, which is not reachable right now" {
		t.Fatalf("with the engine away: %v", err)
	}
}

// Splitting a book or a CUE rip words a missing engine and one that is
// away as merging does.
func TestSplittingSaysTheEngineIsAway(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	admin := *uc
	admin.Admin = true
	splits := []struct {
		what  string
		start func() error
	}{
		{"book splitting", func() error {
			_, err := svc.StartBookSplit(ctx, &admin, "bk-none", true)
			return err
		}},
		{"cue splitting", func() error {
			_, err := svc.StartCueSplit(ctx, &admin, "tr-none", true)
			return err
		}},
	}
	for _, s := range splits {
		if err := s.start(); KindOf(err) != KindFeature || err.Error() != s.what+" needs the streaming engine" {
			t.Errorf("%s without an engine: %v", s.what, err)
		}
	}
	svc.SetEngineState(ctx, EngineState{Configured: true})
	for _, s := range splits {
		if err := s.start(); KindOf(err) != KindFeature || err.Error() != s.what+" needs the streaming engine, which is not reachable right now" {
			t.Errorf("%s with the engine away: %v", s.what, err)
		}
	}
}

// hookedFlowRoots is the bridge as FollowEngine sees it: its crossings,
// which a test fires, over the root surface of fakeFlowRoots.
type hookedFlowRoots struct {
	fakeFlowRoots
	ups   []func(context.Context, flow.Status)
	downs []func()
	helds []func([]string)
}

func (f *hookedFlowRoots) OnUp(fn func(context.Context, flow.Status)) { f.ups = append(f.ups, fn) }
func (f *hookedFlowRoots) OnDown(fn func())                           { f.downs = append(f.downs, fn) }
func (f *hookedFlowRoots) OnHeld(fn func([]string))                   { f.helds = append(f.helds, fn) }

// held is an answer that crosses nothing finding the named roots held.
func (f *hookedFlowRoots) held(names ...string) {
	for _, fn := range f.helds {
		fn(names)
	}
}

func (f *hookedFlowRoots) up(ctx context.Context) {
	for _, fn := range f.ups {
		fn(ctx, flow.Status{Connected: true, Timelines: true, VoiceBoost: true, FileTools: true})
	}
}

func (f *hookedFlowRoots) down() {
	for _, fn := range f.downs {
		fn()
	}
}

// refuse has the bridge refuse every root from now on, or take them again.
func (f *hookedFlowRoots) refuse(err error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.syncErr = err
}

// The service follows the engine through its crossings. Its root surface
// is wired at boot, so every root operation works before the engine first
// answers, as during any outage: the bridge takes the root and reloads it
// when the engine answers. Every answer records what the engine offers
// and offers it again any root it refused before.
func TestTheServiceFollowsTheEngineAcrossABlip(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	bridge := &hookedFlowRoots{fakeFlowRoots: fakeFlowRoots{names: []string{"lib"}}}
	svc.FollowEngine(ctx, bridge)
	if svc.flowRootSync() == nil {
		t.Fatal("the root surface waits for the engine's first answer")
	}

	addWaiting := func(name string) string {
		t.Helper()
		dir := t.TempDir()
		info, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: name, Path: dir})
		if err != nil {
			t.Fatal(err)
		}
		if !strings.Contains(info.StreamingWarning, "when the streaming engine answers again") {
			t.Fatalf("%s: streaming warning = %q, want it to wait for the engine", name, info.StreamingWarning)
		}
		if !bridge.taught(name, dir) {
			t.Fatalf("%s: the root did not reach the bridge before the engine answered", name)
		}
		return dir
	}
	addWaiting("books")

	bridge.up(ctx)
	if !svc.EngineState().Connected {
		t.Fatal("the service missed the engine's answer")
	}
	bridge.down()
	if svc.EngineState().Connected {
		t.Fatal("the service missed the loss")
	}
	addWaiting("talks")

	// A root the engine refused while it answered is offered again at its
	// next answer: an engine back from an outage may see it now.
	bridge.up(ctx)
	bridge.refuse(errors.New("opening root: no such file or directory"))
	refused := t.TempDir()
	if info, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "comedy", Path: refused}); err != nil || info.StreamingWarning == "" {
		t.Fatalf("a refused root: %+v %v, want a warning", info, err)
	}
	bridge.refuse(nil)
	bridge.down()
	bridge.up(ctx)
	if st := svc.EngineState(); !st.Connected || !st.VoiceBoost {
		t.Fatalf("state after the return = %+v, want connected with what it offers", st)
	}
	waitFor(t, func() bool { return slices.Contains(bridge.RootNames(), "comedy") }, "the refused root offered again at the return")
}

// fakeSidecar is a streaming sidecar a real bridge talks to: away until
// told otherwise, it refuses to reload with a root it cannot open (the
// one named, or one whose folder is not there), and it records the root
// names its config file held at each reload, as the real one reconciles
// against that file.
type fakeSidecar struct {
	away       atomic.Bool
	cannotOpen string
	mu         sync.Mutex
	reloads    [][]string
}

// offers counts the reloads whose config named root.
func (e *fakeSidecar) offers(root string) int {
	e.mu.Lock()
	defer e.mu.Unlock()
	n := 0
	for _, names := range e.reloads {
		if slices.Contains(names, root) {
			n++
		}
	}
	return n
}

// sidecarConfigNames reads the root names the config file lists.
func sidecarConfigNames(t *testing.T, path string) []string {
	t.Helper()
	names := []string{}
	for _, r := range sidecarConfigRoots(t, path) {
		names = append(names, r.Name)
	}
	return names
}

// sidecarConfigRoots reads the roots the config file lists.
func sidecarConfigRoots(t *testing.T, path string) []Root {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Errorf("reading the sidecar config: %v", err)
		return nil
	}
	var cfg struct {
		Roots []struct {
			Name string `json:"name"`
			Path string `json:"path"`
		} `json:"roots"`
	}
	if err := json.Unmarshal(raw, &cfg); err != nil {
		t.Errorf("the sidecar config is not JSON: %v", err)
		return nil
	}
	roots := []Root{}
	for _, r := range cfg.Roots {
		roots = append(roots, Root{Name: r.Name, Path: r.Path})
	}
	return roots
}

// bridgeOverFakeSidecar is the real bridge, followed by svc from boot,
// over a sidecar whose config file lists none of the catalog's roots (one
// it refused before, say, which a refusal keeps out of the file), the
// engine not answering yet. Its log reaches logs.
func bridgeOverFakeSidecar(t *testing.T, ctx context.Context, svc *Library, cannotOpen string, logs *lockedBuffer) (*flow.Bridge, *fakeSidecar, string) {
	t.Helper()
	configPath := filepath.Join(t.TempDir(), "waxflow.json")
	if err := os.WriteFile(configPath, []byte(`{"roots":[]}`), 0o644); err != nil {
		t.Fatal(err)
	}
	e, srv := newFakeSidecar(t, configPath, cannotOpen)
	bridge, err := flow.New(ctx, flow.Config{
		BaseURL:    srv.URL,
		APIKey:     "key",
		ConfigPath: configPath,
		Tokens:     auth.NewMediaTokens([]byte("test-secret-test-secret-test-sec"), 0),
		Resolver:   svc,
		Logger:     slog.New(slog.NewTextHandler(logs, nil)),
	})
	if err != nil {
		t.Fatal(err)
	}
	svc.FollowEngine(ctx, bridge)
	if bridge.Connect(ctx) == nil {
		t.Fatal("an engine that is away answered")
	}
	// The boot's sync offers the catalog's root while the engine is away;
	// the bridge holds it.
	waitFor(t, func() bool { return strings.Contains(logs.String(), "held=[lib]") }, "the boot's offer held")
	return bridge, e, configPath
}

// newFakeSidecar serves a fakeSidecar over the config file at configPath,
// away until told otherwise.
func newFakeSidecar(t *testing.T, configPath, cannotOpen string) (*fakeSidecar, *httptest.Server) {
	t.Helper()
	e := &fakeSidecar{cannotOpen: cannotOpen}
	e.away.Store(true)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if e.away.Load() {
			if conn, _, err := w.(http.Hijacker).Hijack(); err == nil {
				conn.Close()
			}
			return
		}
		switch r.URL.Path {
		case "/caps":
			fmt.Fprint(w, `{"schemaVersion":1,"outputs":[{"name":"flac","live":true}],"delivery":{"progressive":true,"rootsReload":true},"dsp":{}}`)
		case "/roots/reload":
			roots := sidecarConfigRoots(t, configPath)
			names := make([]string, 0, len(roots))
			for _, r := range roots {
				names = append(names, r.Name)
			}
			e.mu.Lock()
			e.reloads = append(e.reloads, names)
			e.mu.Unlock()
			for _, r := range roots {
				if _, err := os.Stat(r.Path); r.Name == e.cannotOpen || err != nil {
					w.Header().Set("Content-Type", "application/json")
					w.WriteHeader(http.StatusBadRequest)
					fmt.Fprintf(w, `{"error":"opening root %s: no such file or directory","code":"invalid-request","schemaVersion":1}`, r.Name)
					return
				}
			}
			fmt.Fprint(w, `{"schemaVersion":1,"added":[],"removed":[],"changed":[],"roots":[]}`)
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(srv.Close)
	return e, srv
}

// A root the sidecar cannot open, offered at a start while the engine is
// not answering yet (every compose start), never reaches the config file
// the sidecar boots from, before or after the engine answers: the bridge
// holds it until a reload can check it, the engine's answer offers it
// once, the reload refuses it, and the refusal is remembered as a refused
// offer always is.
func TestARootTheSidecarRefusesNeverReachesTheConfigItBootsFrom(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newCatalogFixture(t)
	logs := &lockedBuffer{}
	bridge, e, configPath := bridgeOverFakeSidecar(t, ctx, svc, "lib", logs)
	if got := sidecarConfigNames(t, configPath); len(got) != 0 {
		t.Fatalf("config before the engine answered = %v, want no roots", got)
	}

	e.away.Store(false)
	if err := bridge.Connect(ctx); err != nil {
		t.Fatal(err)
	}
	libDir := svc.RootTable()[0].Path
	waitFor(t, func() bool {
		svc.flowSyncMu.Lock()
		defer svc.flowSyncMu.Unlock()
		return svc.flowRefused["lib"].path == libDir
	}, "the refusal remembered as a refused offer is")
	if got := sidecarConfigNames(t, configPath); len(got) != 0 {
		t.Fatalf("config after the refusal = %v, want no roots", got)
	}
	if n := e.offers("lib"); n != 1 {
		t.Fatalf("the answer offered the refused root %d times, want once", n)
	}
	if slices.Contains(bridge.RootNames(), "lib") {
		t.Fatal("the bridge maps a root the sidecar refused")
	}
}

// One the sidecar can open goes in at its answer: checked by the reload,
// then in the config file and the bridge's table.
func TestARootHeldWhileTheEngineIsAwayGoesInAtItsAnswer(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newCatalogFixture(t)
	logs := &lockedBuffer{}
	bridge, e, configPath := bridgeOverFakeSidecar(t, ctx, svc, "", logs)
	if got := sidecarConfigNames(t, configPath); len(got) != 0 {
		t.Fatalf("config before the engine answered = %v, want no roots", got)
	}
	e.away.Store(false)
	if err := bridge.Connect(ctx); err != nil {
		t.Fatal(err)
	}
	waitFor(t, func() bool { return slices.Contains(bridge.RootNames(), "lib") }, "the held root taken at the answer")
	if got := sidecarConfigNames(t, configPath); !slices.Equal(got, []string{"lib"}) {
		t.Fatalf("config after the answer = %v, want lib", got)
	}
	if n := e.offers("lib"); n != 1 {
		t.Fatalf("lib offered %d times, want once", n)
	}
}

// A library whose root the engine did not answer for while it stayed up
// (a reload that ran out of time on a slow mount) gets the warning a
// refused one gets while it waits, and is offered again at the next answer
// that finds it held, though nothing crossed.
func TestALibraryWhoseReloadGetsNoAnswerIsOfferedAgainAtTheNextAnswer(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	bridge := &hookedFlowRoots{fakeFlowRoots: fakeFlowRoots{names: []string{"lib"}}}
	svc.FollowEngine(ctx, bridge)
	bridge.up(ctx)
	bridge.refuse(flow.ErrRootHeld)

	dir := t.TempDir()
	info, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "books", Path: dir})
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(info.StreamingWarning, "not available yet") {
		t.Fatalf("streaming warning = %q, want the one a refused library gets", info.StreamingWarning)
	}
	bridge.refuse(nil)
	bridge.held("books")
	waitFor(t, func() bool { return slices.Contains(bridge.RootNames(), "books") }, "the held root offered again at the next answer")
}
