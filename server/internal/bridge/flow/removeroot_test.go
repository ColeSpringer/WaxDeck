package flow

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync/atomic"
	"testing"
)

// writeTwoRootConfig lays down a sidecar config serving lib and books,
// beside the keys WaxDeck does not own.
func writeTwoRootConfig(t *testing.T) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "waxflow.json")
	body := `{
  "apiKeys": ["secret-one"],
  "roots": [{"name": "lib", "path": "/library"}, {"name": "books", "path": "/books"}, {"name": "tail", "path": "/tail"}],
  "signingSecret": "kid1:00ff"
}`
	if err := os.WriteFile(path, []byte(body), 0o640); err != nil {
		t.Fatal(err)
	}
	return path
}

var twoRoots = []Root{{Name: "lib", Path: "/library"}, {Name: "books", Path: "/books"}, {Name: "tail", Path: "/tail"}}

// A removed library's root leaves the file before the sidecar reconciles,
// leaves the bridge's table so nothing mints a stream under it, and every
// other key and root stays in its place.
func TestRemoveRootRewritesTheConfigAndReloads(t *testing.T) {
	t.Parallel()
	path := writeTwoRootConfig(t)
	var atReload []string
	b := newRootBridge(t, reloadCapsJSON(), path, twoRoots, func(w http.ResponseWriter, r *http.Request) {
		atReload = configRootNames(t, path)
		fmt.Fprint(w, `{"schemaVersion":1,"added":[],"removed":["books"],"changed":[],"roots":["lib","tail"]}`)
	})
	if err := b.RemoveRoot(context.Background(), "books"); err != nil {
		t.Fatalf("RemoveRoot: %v", err)
	}
	if !slices.Equal(atReload, []string{"lib", "tail"}) {
		t.Errorf("roots the sidecar read = %v, want lib and tail in place", atReload)
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(raw), "secret-one") || !strings.Contains(string(raw), "kid1:00ff") {
		t.Errorf("the rewrite lost a key WaxDeck does not own:\n%s", raw)
	}
	if slices.Contains(b.RootNames(), "books") {
		t.Errorf("the bridge still maps books: %v", b.RootNames())
	}
	if _, err := b.srcRef("/books/a.flac"); err == nil {
		t.Error("a file under the removed root still maps to a stream reference")
	}
	if info, err := os.Stat(path); err == nil && info.Mode().Perm() != 0o640 {
		t.Errorf("mode = %v, want the operator's 0640 kept", info.Mode().Perm())
	}
}

// A sidecar that refuses the reload serves the root until it reloads or
// restarts, and the answer says why. The removal stands in the bridge and
// the file: a root put back in the file is what stops the sidecar
// starting once its folder is gone.
func TestARemovalTheSidecarRefusesStandsAndSaysWhy(t *testing.T) {
	t.Parallel()
	path := writeTwoRootConfig(t)
	b := newRootBridge(t, reloadCapsJSON(), path, twoRoots, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusServiceUnavailable)
		fmt.Fprint(w, `{"error":"a job is holding the root set","code":"overloaded","schemaVersion":1}`)
	})
	err := b.RemoveRoot(context.Background(), "books")
	if err == nil || !strings.Contains(err.Error(), "a job is holding the root set") {
		t.Fatalf("RemoveRoot = %v, want the sidecar's reason", err)
	}
	if names := configRootNames(t, path); !slices.Equal(names, []string{"lib", "tail"}) {
		t.Errorf("the file lists %v after the refusal, want books gone and the rest in place", names)
	}
	if _, err := b.srcRef("/books/a.flac"); err == nil {
		t.Error("a file under the removed root still maps to a stream reference")
	}
}

// A name neither the file nor the bridge holds asks nothing of the
// sidecar.
func TestRemoveRootOfAnUnknownNameAsksNothing(t *testing.T) {
	t.Parallel()
	path := writeTwoRootConfig(t)
	before, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var reloads atomic.Int32
	b := newRootBridge(t, reloadCapsJSON(), path, twoRoots, func(w http.ResponseWriter, r *http.Request) {
		reloads.Add(1)
		fmt.Fprint(w, `{"schemaVersion":1,"added":[],"removed":[],"changed":[],"roots":[]}`)
	})
	if err := b.RemoveRoot(context.Background(), "never"); err != nil {
		t.Fatalf("RemoveRoot of an unknown name = %v", err)
	}
	after, _ := os.ReadFile(path)
	if reloads.Load() != 0 || string(after) != string(before) {
		t.Errorf("%d reloads, config changed %v; want neither", reloads.Load(), string(after) != string(before))
	}
}

// A sidecar that does not reload roots serves what it opened until it
// restarts, from a file that no longer names the root: dropping one never
// stops it starting, and a root nothing maps harms nothing meanwhile, so
// there is nothing left for an administrator to do.
func TestRemoveRootWithoutReloadSupport(t *testing.T) {
	t.Parallel()
	path := writeTwoRootConfig(t)
	b := newRootBridge(t, capsJSON(), path, twoRoots, nil)
	if err := b.RemoveRoot(context.Background(), "books"); err != nil {
		t.Fatalf("RemoveRoot = %v, want it done", err)
	}
	if slices.Contains(b.RootNames(), "books") {
		t.Errorf("the bridge still maps books: %v", b.RootNames())
	}
	if names := configRootNames(t, path); !slices.Equal(names, []string{"lib", "tail"}) {
		t.Errorf("the file lists %v, want books gone and the rest in place", names)
	}
	if err := b.RemoveRoot(context.Background(), "books"); err != nil {
		t.Errorf("removing it again = %v, want nothing left to say", err)
	}
}

// A config file that cannot be read still lets the bridge forget the
// root, so nothing mints a stream under it and its name is free.
func TestRemoveRootForgetsTheRootWhateverTheFile(t *testing.T) {
	t.Parallel()
	path := writeTwoRootConfig(t)
	b := newRootBridge(t, reloadCapsJSON(), path, twoRoots, func(w http.ResponseWriter, r *http.Request) {
		t.Error("a reload was asked for over a config that cannot be read")
	})
	if err := os.WriteFile(path, []byte("not json"), 0o640); err != nil {
		t.Fatal(err)
	}
	if err := b.RemoveRoot(context.Background(), "books"); err == nil {
		t.Fatal("RemoveRoot = nil over a config that cannot be read, want why")
	}
	if slices.Contains(b.RootNames(), "books") {
		t.Errorf("the bridge still maps books: %v", b.RootNames())
	}
}

// While the engine is away the root still leaves the bridge and the file
// the engine loads its roots from when it is back, and that is success:
// it is said in the log, not answered as a failure.
func TestRemoveRootWhileTheEngineIsAway(t *testing.T) {
	t.Parallel()
	path := writeTwoRootConfig(t)
	var logged bytes.Buffer
	b := &Bridge{
		configPath: path,
		roots:      append([]Root(nil), twoRoots...),
		log:        slog.New(slog.NewTextHandler(&logged, nil)),
	}
	if err := b.RemoveRoot(context.Background(), "books"); err != nil {
		t.Fatalf("RemoveRoot while the engine is away = %v, want it done", err)
	}
	if slices.Contains(b.RootNames(), "books") {
		t.Errorf("the bridge still maps books: %v", b.RootNames())
	}
	if names := configRootNames(t, path); !slices.Equal(names, []string{"lib", "tail"}) {
		t.Errorf("the file lists %v, want books gone and the rest in place", names)
	}
	if !strings.Contains(logged.String(), "while it is away") || !strings.Contains(logged.String(), "removed=[books]") {
		t.Errorf("the log says %q, want the removal while away said with the root", logged.String())
	}
}

// With no config file named, the sidecar's roots are its operator's
// configuration, which WaxDeck cannot reach; the bridge forgets the root,
// and a root nothing maps harms nothing.
func TestRemoveRootWithoutAConfigFile(t *testing.T) {
	t.Parallel()
	b := newRootBridge(t, reloadCapsJSON(), "", twoRoots, nil)
	if err := b.RemoveRoot(context.Background(), "books"); err != nil {
		t.Fatalf("RemoveRoot = %v, want it done", err)
	}
	if slices.Contains(b.RootNames(), "books") {
		t.Errorf("the bridge still maps books: %v", b.RootNames())
	}
}

// withoutRoots answers the bytes as they were when the file lists none of
// the names, and refuses a file that is not a JSON object.
func TestWithoutRoots(t *testing.T) {
	t.Parallel()
	raw := []byte(`{"roots":[{"name":"lib","path":"/library"}],"cacheMaxBytes":5}`)
	out, listed, err := withoutRoots(raw, "waxflow.json", []string{"books"})
	if err != nil || listed || string(out) != string(raw) {
		t.Errorf("dropping an unlisted root = %s, %v, %v; want the bytes unchanged", out, listed, err)
	}
	out, listed, err = withoutRoots(raw, "waxflow.json", []string{"books", "lib"})
	if err != nil || !listed {
		t.Fatalf("dropping lib = %v, %v", listed, err)
	}
	var cfg map[string]any
	if err := json.Unmarshal(out, &cfg); err != nil {
		t.Fatal(err)
	}
	if roots, _ := cfg["roots"].([]any); len(roots) != 0 || cfg["cacheMaxBytes"] != float64(5) {
		t.Errorf("after dropping lib = %s, want no roots and the cache key kept", out)
	}
	if _, _, err := withoutRoots([]byte(`[1]`), "waxflow.json", []string{"lib"}); err == nil {
		t.Error("a config that is not an object was taken")
	}
}

// lateRoots is twoRoots without books: what a start maps when the catalog
// let books go while the server was stopped (the CLI's removal), though
// the sidecar's file still names it.
var lateRoots = []Root{{Name: "lib", Path: "/library"}, {Name: "tail", Path: "/tail"}}

// A root the sidecar's file names and the bridge does not map leaves the
// file while the engine is away, and the engine's answer reloads the file
// without it, once: a folder deleted later never stops the sidecar
// starting.
func TestARemovalWhileAwayTakesARootOnlyTheFileNames(t *testing.T) {
	t.Parallel()
	path := writeTwoRootConfig(t)
	e := newRootEngine(t, path)
	b := awayRootBridge(t, e, path, lateRoots, nil)
	if err := b.RemoveRoot(context.Background(), "books"); err != nil {
		t.Fatalf("RemoveRoot while away = %v, want it taken", err)
	}
	if names := configRootNames(t, path); !slices.Equal(names, []string{"lib", "tail"}) {
		t.Fatalf("the file lists %v, want books gone and the rest in place", names)
	}
	e.away.Store(false)
	connect(t, b)
	connect(t, b)
	if reloads := e.reloadsSoFar(); len(reloads) != 1 || !slices.Equal(reloads[0], []string{"lib", "tail"}) {
		t.Fatalf("reloads after two answers = %v, want one, without books", reloads)
	}
}

// A sidecar that serves no reloads starts from its file next time, so a
// root only the file names leaves it all the same.
func TestARemovalWithoutReloadsTakesARootOnlyTheFileNames(t *testing.T) {
	t.Parallel()
	path := writeTwoRootConfig(t)
	b := newRootBridge(t, capsJSON(), path, lateRoots, nil)
	if err := b.RemoveRoot(context.Background(), "books"); err != nil {
		t.Fatalf("RemoveRoot = %v, want it done", err)
	}
	if names := configRootNames(t, path); !slices.Equal(names, []string{"lib", "tail"}) {
		t.Fatalf("the file lists %v, want books gone and the rest in place", names)
	}
}

// A removal the file cannot take while the engine is away still unmaps
// the root, so nothing mints a stream under it again, and says why; made
// again once the file can be written, it reaches the file, and the
// engine's answer reloads it.
func TestARemovalWhileAwayThatCannotWriteTheFileStillUnmapsTheRoot(t *testing.T) {
	t.Parallel()
	path := writeTwoRootConfig(t)
	good, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	e := newRootEngine(t, path)
	b := awayRootBridge(t, e, path, twoRoots, nil)
	if err := os.WriteFile(path, []byte("not json"), 0o640); err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	if err := b.RemoveRoot(ctx, "books"); err == nil {
		t.Fatal("RemoveRoot = nil over a file that cannot be read, want why")
	}
	if slices.Contains(b.RootNames(), "books") {
		t.Errorf("the bridge still maps books: %v", b.RootNames())
	}
	if err := os.WriteFile(path, good, 0o640); err != nil {
		t.Fatal(err)
	}
	if err := b.RemoveRoot(ctx, "books"); err != nil {
		t.Fatalf("RemoveRoot again = %v, want it taken", err)
	}
	if names := configRootNames(t, path); !slices.Equal(names, []string{"lib", "tail"}) {
		t.Fatalf("the file lists %v, want books gone and the rest in place", names)
	}
	e.away.Store(false)
	connect(t, b)
	if reloads := e.reloadsSoFar(); len(reloads) != 1 || !slices.Equal(reloads[0], []string{"lib", "tail"}) {
		t.Fatalf("reloads = %v, want one, without books", reloads)
	}
}

// An unmount and a re-add of one name, made in that order while the
// engine is away (a library that took a removed one's name, in another
// folder, the way a start finds them), land in that order: the old folder
// leaves the file at once, the answer reloads that, and the new folder
// goes in at the answer's offer. The file then names the new folder only,
// which the bridge maps: the sidecar and the bridge agree on the name.
func TestAnUnmountThenAReAddOfOneNameWhileAwayLandInOrder(t *testing.T) {
	t.Parallel()
	path := writeTwoRootConfig(t)
	e := newRootEngine(t, path)
	b := awayRootBridge(t, e, path, lateRoots, nil)
	ctx := context.Background()
	newBooks := t.TempDir()
	if err := b.RemoveRoot(ctx, "books"); err != nil {
		t.Fatal(err)
	}
	if err := b.SyncRoot(ctx, "books", newBooks); err != nil {
		t.Fatalf("the re-add while away = %v, want it held", err)
	}
	if names := configRootNames(t, path); !slices.Equal(names, []string{"lib", "tail"}) {
		t.Fatalf("the file lists %v while away, want the old books gone and the new one held", names)
	}
	e.away.Store(false)
	connect(t, b)
	// The offer the answer's re-sync makes of every root the bridge does
	// not map, the held add among them.
	if err := b.SyncRoot(ctx, "books", newBooks); err != nil {
		t.Fatal(err)
	}
	reloads := e.reloadsSoFar()
	if len(reloads) != 2 || !slices.Equal(reloads[0], []string{"lib", "tail"}) || !slices.Contains(reloads[1], "books") {
		t.Fatalf("reloads = %v, want the removal's, then the add's", reloads)
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var cfg struct {
		Roots []Root `json:"roots"`
	}
	if err := json.Unmarshal(raw, &cfg); err != nil {
		t.Fatal(err)
	}
	var books []string
	for _, r := range cfg.Roots {
		if r.Name == "books" {
			books = append(books, r.Path)
		}
	}
	if !slices.Equal(books, []string{newBooks}) {
		t.Errorf("the file has books at %v, want the new folder only", books)
	}
	if ref, err := b.srcRef(filepath.Join(newBooks, "a.flac")); err != nil || ref != "books/a.flac" {
		t.Errorf("the new folder maps to %q, %v; want books/a.flac", ref, err)
	}
}

// A name taken off and taught again under another folder leaves the file
// listing the new folder only: a newer library that took a removed one's
// name is served from its own folder, not the removed one's.
func TestARootTakenOffAndTaughtElsewhereMapsTheNewFolder(t *testing.T) {
	t.Parallel()
	path := writeTwoRootConfig(t)
	b := newRootBridge(t, reloadCapsJSON(), path, twoRoots, func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, `{"schemaVersion":1,"added":[],"removed":[],"changed":[],"roots":[]}`)
	})
	if err := b.RemoveRoot(context.Background(), "books"); err != nil {
		t.Fatalf("RemoveRoot: %v", err)
	}
	if err := b.SyncRoot(context.Background(), "books", "/newbooks"); err != nil {
		t.Fatalf("SyncRoot: %v", err)
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var cfg struct {
		Roots []Root `json:"roots"`
	}
	if err := json.Unmarshal(raw, &cfg); err != nil {
		t.Fatal(err)
	}
	var books []string
	for _, r := range cfg.Roots {
		if r.Name == "books" || r.Path == "/books" {
			books = append(books, r.Name+"="+r.Path)
		}
	}
	if !slices.Equal(books, []string{"books=/newbooks"}) {
		t.Errorf("the file lists %v for books, want the new folder only", books)
	}
}
