package flow

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
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/auth"
)

// rootEngine is a fake sidecar for root changes. It can be away, refuse
// any reload whose config names a root it cannot open, drop a reload's
// connection unanswered, or hold a reload until released; it records
// each reload with the root names its config file held then, as the real
// one reconciles against that file.
type rootEngine struct {
	srv  *httptest.Server
	away atomic.Bool
	// cannotOpen is a root name the engine refuses to reload with.
	cannotOpen atomic.Pointer[string]
	dropReload atomic.Bool
	// hold, when set, keeps a reload waiting until it is closed, after
	// saying so on entered.
	hold    chan struct{}
	entered chan struct{}
	mu      sync.Mutex
	reloads [][]string
}

func newRootEngine(t *testing.T, configPath string) *rootEngine {
	t.Helper()
	e := &rootEngine{}
	e.srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if e.away.Load() {
			if conn, _, err := w.(http.Hijacker).Hijack(); err == nil {
				conn.Close()
			}
			return
		}
		switch r.URL.Path {
		case "/caps":
			fmt.Fprint(w, reloadCapsJSON())
		case "/roots/reload":
			names := configRootNames(t, configPath)
			e.mu.Lock()
			e.reloads = append(e.reloads, names)
			hold := e.hold
			e.mu.Unlock()
			if e.dropReload.Load() {
				if conn, _, err := w.(http.Hijacker).Hijack(); err == nil {
					conn.Close()
				}
				return
			}
			if hold != nil {
				e.entered <- struct{}{}
				<-hold
			}
			if bad := e.cannotOpen.Load(); bad != nil && slices.Contains(names, *bad) {
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusBadRequest)
				fmt.Fprintf(w, `{"error":"opening root %s: no such file or directory","code":"invalid-request","schemaVersion":1}`, *bad)
				return
			}
			fmt.Fprint(w, `{"schemaVersion":1,"added":[],"removed":[],"changed":[],"roots":[]}`)
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(e.srv.Close)
	return e
}

// holdReloads has every reload from now on wait until release is called,
// saying first on the returned channel that one has arrived.
func (e *rootEngine) holdReloads() (entered <-chan struct{}, release func()) {
	e.mu.Lock()
	defer e.mu.Unlock()
	hold := make(chan struct{})
	e.hold, e.entered = hold, make(chan struct{}, 4)
	return e.entered, func() {
		e.mu.Lock()
		e.hold = nil
		e.mu.Unlock()
		close(hold)
	}
}

// reloadsSoFar copies the reloads the engine has taken.
func (e *rootEngine) reloadsSoFar() [][]string {
	e.mu.Lock()
	defer e.mu.Unlock()
	return slices.Clone(e.reloads)
}

// configRootNames reads the root names a config file lists, in order.
func configRootNames(t *testing.T, path string) []string {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Errorf("reading the config: %v", err)
		return nil
	}
	var cfg struct {
		Roots []struct {
			Name string `json:"name"`
		} `json:"roots"`
	}
	if err := json.Unmarshal(raw, &cfg); err != nil {
		t.Errorf("the config is not JSON: %v\n%s", err, raw)
		return nil
	}
	names := []string{}
	for _, r := range cfg.Roots {
		names = append(names, r.Name)
	}
	return names
}

// awayRootBridge is a bridge over e with the config file at path and the
// given starting roots, whose engine has not answered yet.
func awayRootBridge(t *testing.T, e *rootEngine, path string, roots []Root, log *slog.Logger) *Bridge {
	t.Helper()
	e.away.Store(true)
	b, err := New(context.Background(), Config{
		BaseURL:    e.srv.URL,
		APIKey:     "key",
		Roots:      roots,
		ConfigPath: path,
		Tokens:     auth.NewMediaTokens([]byte("test-secret-test-secret-test-sec"), 0),
		Resolver:   staticResolver{},
		Logger:     log,
	})
	if err != nil {
		t.Fatal(err)
	}
	if b.Connect(context.Background()) == nil {
		t.Fatal("an engine that is away answered")
	}
	return b
}

// libRoots is the one root writeConfig's file lists.
var libRoots = []Root{{Name: "lib", Path: "/library"}}

// A removal while the engine is away is written to its config at once
// (a removal can never stop it starting) and reloaded by its next answer:
// once, carrying the current set.
func TestARemovalWhileAwayIsWrittenAndReloadedOnceItAnswers(t *testing.T) {
	path := writeConfig(t, t.TempDir())
	e := newRootEngine(t, path)
	b := awayRootBridge(t, e, path, libRoots, nil)

	if err := b.ChangeRoots(context.Background(), nil, []string{"lib"}); err != nil {
		t.Fatalf("a removal while away = %v, want it taken", err)
	}
	if got := configRootNames(t, path); len(got) != 0 {
		t.Fatalf("config after the removal = %v, want lib gone", got)
	}
	if got := b.RootNames(); len(got) != 0 {
		t.Fatalf("bridge roots = %v, want lib gone", got)
	}
	if n := len(e.reloadsSoFar()); n != 0 {
		t.Fatalf("%d reloads asked of an engine that is away", n)
	}

	e.away.Store(false)
	connect(t, b)
	connect(t, b)
	reloads := e.reloadsSoFar()
	if len(reloads) != 1 || len(reloads[0]) != 0 {
		t.Fatalf("reloads after two answers = %v, want one carrying the current set (no roots)", reloads)
	}
}

// An add while the engine is away stays out of its config file, which is
// what it opens at its next start: only a reload checks a root, so the
// add waits, held, until the engine answers and it is offered again
// through the usual write, reload and rollback. A root the engine refuses
// therefore never appears in the file it boots from, before or after it
// answers.
func TestAnAddWhileAwayStaysOutOfTheConfigUntilAReloadChecksIt(t *testing.T) {
	path := writeConfig(t, t.TempDir())
	e := newRootEngine(t, path)
	bad := "books"
	e.cannotOpen.Store(&bad)
	b := awayRootBridge(t, e, path, libRoots, nil)
	ctx := context.Background()

	books := t.TempDir()
	if err := b.SyncRoot(ctx, "books", books); err != nil {
		t.Fatalf("an add while away = %v, want it held", err)
	}
	if got := configRootNames(t, path); !slices.Equal(got, []string{"lib"}) {
		t.Fatalf("config after an add while away = %v, want it untouched", got)
	}
	if got := b.RootNames(); !slices.Equal(got, []string{"lib"}) {
		t.Fatalf("bridge roots = %v, want the held add unmapped", got)
	}

	e.away.Store(false)
	connect(t, b)
	if got := configRootNames(t, path); !slices.Equal(got, []string{"lib"}) {
		t.Fatalf("config once the engine answered = %v, want it untouched", got)
	}
	// The offer the answer's re-sync makes: refused, so rolled back out.
	if err := b.SyncRoot(ctx, "books", books); err == nil {
		t.Fatal("a root the engine cannot open was taken")
	}
	if got := configRootNames(t, path); !slices.Equal(got, []string{"lib"}) {
		t.Fatalf("config after the refusal = %v, want the refused root never left in it", got)
	}
	if got := b.RootNames(); !slices.Equal(got, []string{"lib"}) {
		t.Fatalf("bridge roots after the refusal = %v, want lib alone", got)
	}
	if n := len(e.reloadsSoFar()); n != 1 {
		t.Fatalf("reloads = %d, want the one offer's", n)
	}

	// One it can open goes in through the same offer.
	e.cannotOpen.Store(nil)
	if err := b.SyncRoot(ctx, "books", books); err != nil {
		t.Fatal(err)
	}
	if got := configRootNames(t, path); !slices.Equal(got, []string{"lib", "books"}) {
		t.Fatalf("config after an accepted offer = %v, want lib and books", got)
	}
}

// A reload that gets no answer is not a refusal: the change it carried
// waits for the engine's next answer. A removal waits written; an add
// waits held, out of the table and the file, and its caller is told so.
func TestAReloadThatGetsNoAnswerKeepsTheChangeForTheNextAnswer(t *testing.T) {
	t.Run("a removal at the reconnect", func(t *testing.T) {
		path := writeConfig(t, t.TempDir())
		e := newRootEngine(t, path)
		b := awayRootBridge(t, e, path, libRoots, nil)
		ctx := context.Background()
		if err := b.ChangeRoots(ctx, nil, []string{"lib"}); err != nil {
			t.Fatal(err)
		}
		e.away.Store(false)
		e.dropReload.Store(true)
		if b.Connect(ctx) == nil || b.Up() {
			t.Fatal("an answer whose reload went unanswered took the engine up")
		}
		e.dropReload.Store(false)
		connect(t, b)
		connect(t, b)
		if n := len(e.reloadsSoFar()); n != 2 {
			t.Fatalf("reloads = %d, want the unanswered one and the next answer's", n)
		}
	})
	t.Run("an add while up", func(t *testing.T) {
		path := writeConfig(t, t.TempDir())
		e := newRootEngine(t, path)
		b := awayRootBridge(t, e, path, libRoots, nil)
		ctx := context.Background()
		e.away.Store(false)
		connect(t, b)
		e.dropReload.Store(true)
		books := t.TempDir()
		if err := b.SyncRoot(ctx, "books", books); !errors.Is(err, ErrRootHeld) {
			t.Fatalf("an add whose reload went unanswered = %v, want it held for the next answer and said so", err)
		}
		if got := configRootNames(t, path); !slices.Equal(got, []string{"lib"}) {
			t.Fatalf("config = %v, want the unchecked add out of it", got)
		}
		if got := b.RootNames(); !slices.Equal(got, []string{"lib"}) {
			t.Fatalf("bridge roots = %v, want the unchecked add unmapped", got)
		}
		if b.Up() {
			t.Fatal("a reload that found the engine gone left it up")
		}
		e.dropReload.Store(false)
		connect(t, b)
		if err := b.SyncRoot(ctx, "books", books); err != nil {
			t.Fatal(err)
		}
		if got := configRootNames(t, path); !slices.Equal(got, []string{"lib", "books"}) {
			t.Fatalf("config after the next answer's offer = %v, want lib and books", got)
		}
	})
}

// A change made while the engine's answer is being taken (after the
// answer's reload, before the engine reads as up) found it away; the
// answer reloads it too, rather than leaving it for the next probe.
func TestAChangeMadeWhileTheAnswerIsTakenIsReloaded(t *testing.T) {
	path := filepath.Join(t.TempDir(), "waxflow.json")
	if err := os.WriteFile(path, []byte(`{"roots":[{"name":"lib","path":"/library"},{"name":"talks","path":"/talks"}]}`), 0o644); err != nil {
		t.Fatal(err)
	}
	e := newRootEngine(t, path)
	b := awayRootBridge(t, e, path, []Root{{Name: "lib", Path: "/library"}, {Name: "talks", Path: "/talks"}}, nil)
	ctx := context.Background()
	if err := b.ChangeRoots(ctx, nil, []string{"lib"}); err != nil {
		t.Fatal(err)
	}

	entered, release := e.holdReloads()
	e.away.Store(false)
	connected := make(chan error, 1)
	go func() { connected <- b.Connect(ctx) }()
	<-entered
	// The answer is reloading; it reads as up only once settle takes the
	// link lock, which this holds until the change below has gone in.
	b.linkMu.Lock()
	changed := make(chan error, 1)
	go func() { changed <- b.ChangeRoots(ctx, nil, []string{"talks"}) }()
	release()
	if err := <-changed; err != nil {
		b.linkMu.Unlock()
		t.Fatal(err)
	}
	b.linkMu.Unlock()
	if err := <-connected; err != nil {
		t.Fatal(err)
	}
	reloads := e.reloadsSoFar()
	if len(reloads) != 2 || len(reloads[1]) != 0 {
		t.Fatalf("reloads = %v, want the answer's and one more carrying the change (no roots)", reloads)
	}
	connect(t, b)
	if n := len(e.reloadsSoFar()); n != 2 {
		t.Fatalf("reloads after the next probe = %d, want nothing left pending", n)
	}
}

// A root this server cannot see as a directory is refused while the
// engine is away, in words the administrator can act on now.
func TestAnAddWhileAwayThatCannotBeSeenIsRefused(t *testing.T) {
	path := writeConfig(t, t.TempDir())
	e := newRootEngine(t, path)
	b := awayRootBridge(t, e, path, libRoots, nil)
	missing := filepath.Join(t.TempDir(), "gone")
	if err := b.SyncRoot(context.Background(), "books", missing); err == nil {
		t.Fatal("an unseen path was taken while away")
	}
	e.away.Store(false)
	connect(t, b)
	if n := len(e.reloadsSoFar()); n != 0 {
		t.Fatalf("reloads = %d, want none: nothing was left pending", n)
	}
}

// A removal while the engine answers rewrites the file and reloads at
// once, like an add.
func TestARemovalWhileUpReloadsAtOnce(t *testing.T) {
	path := writeConfig(t, t.TempDir())
	e := newRootEngine(t, path)
	b := awayRootBridge(t, e, path, libRoots, nil)
	e.away.Store(false)
	connect(t, b)
	if err := b.ChangeRoots(context.Background(), nil, []string{"lib"}); err != nil {
		t.Fatal(err)
	}
	reloads := e.reloadsSoFar()
	if len(reloads) != 1 || len(reloads[0]) != 0 {
		t.Fatalf("reloads = %v, want one carrying no roots", reloads)
	}
}

// An add whose reload runs out of time while the engine stays up is held,
// and the caller is told it waits, as a refused add is told; nothing has
// crossed, so the next answer that crosses nothing hands the held names
// to the OnHeld hooks to be offered again (the service's re-sync), rather
// than leaving the root unmapped until the next crossing.
func TestAnAddWhoseReloadTimesOutWhileUpIsOfferedAtTheNextAnswer(t *testing.T) {
	path := writeConfig(t, t.TempDir())
	e := newRootEngine(t, path)
	b := awayRootBridge(t, e, path, libRoots, nil)
	b.reloadTimeout = 50 * time.Millisecond
	ups, downs := countCrossings(b)
	var offered [][]string
	b.OnHeld(func(held []string) { offered = append(offered, held) })
	e.away.Store(false)
	connect(t, b)
	ctx := context.Background()

	_, release := e.holdReloads()
	books := t.TempDir()
	err := b.SyncRoot(ctx, "books", books)
	release()
	if !errors.Is(err, ErrRootHeld) {
		t.Fatalf("an add whose reload ran out of time = %v, want it held and said so", err)
	}
	if !b.Up() {
		t.Fatal("a reload that ran out of time took the engine down")
	}
	if got := configRootNames(t, path); !slices.Equal(got, []string{"lib"}) {
		t.Fatalf("config = %v, want the unchecked add out of it", got)
	}
	wantProbeAsked(t, b, "a reload that ran out of time")

	connect(t, b) // the probe it asked for: answers, and crosses nothing
	if ups.Load() != 1 || downs.Load() != 0 {
		t.Fatalf("crossings: OnUp %d, OnDown %d; want the first answer's alone", ups.Load(), downs.Load())
	}
	if len(offered) != 1 || !slices.Equal(offered[0], []string{"books"}) {
		t.Fatalf("held roots handed on = %v, want books once", offered)
	}
	// Offered again, as the service's re-sync does.
	if err := b.SyncRoot(ctx, "books", books); err != nil {
		t.Fatal(err)
	}
	if got := configRootNames(t, path); !slices.Equal(got, []string{"lib", "books"}) {
		t.Fatalf("config after the offer = %v, want lib and books", got)
	}
	connect(t, b)
	if len(offered) != 1 {
		t.Fatalf("held roots handed on %d times, want nothing once nothing is held", len(offered))
	}
}
