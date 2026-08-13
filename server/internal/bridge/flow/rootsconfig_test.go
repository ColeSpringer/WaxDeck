package flow

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/colespringer/waxflow/waxerr"

	"github.com/colespringer/waxdeck/server/internal/auth"
)

// reloadCapsJSON is capsJSON with the root-reload capability advertised.
func reloadCapsJSON() string {
	return `{"schemaVersion":1,
		"outputs":[{"name":"flac","live":true}],
		"delivery":{"progressive":true,"rootsReload":true},
		"dsp":{}}`
}

// newRootBridge builds a bridge against a stub sidecar that answers
// /caps with the given body and /roots/reload with reload.
func newRootBridge(t *testing.T, caps string, configPath string, roots []Root, reload http.HandlerFunc) *Bridge {
	t.Helper()
	fake := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/caps":
			fmt.Fprint(w, caps)
		case "/roots/reload":
			if reload == nil {
				http.Error(w, "no reload handler", http.StatusNotFound)
				return
			}
			reload(w, r)
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(fake.Close)

	b, err := New(context.Background(), Config{
		BaseURL:    fake.URL,
		APIKey:     "key",
		Roots:      roots,
		ConfigPath: configPath,
		Tokens:     auth.NewMediaTokens([]byte("test-secret-test-secret-test-sec"), 0),
		Resolver:   staticResolver{},
	})
	if err != nil {
		t.Fatal(err)
	}
	return b
}

// writeConfig lays down a file-configured sidecar config: roots plus the
// keys WaxDeck does not own and must not lose.
func writeConfig(t *testing.T, dir string) string {
	t.Helper()
	path := filepath.Join(dir, "waxflow.json")
	body := `{
  "apiKeys": ["secret-one", "secret-two"],
  "signingSecret": "kid1:00ff",
  "cacheMaxBytes": 123456,
  "roots": [{"name": "lib", "path": "/library"}],
  "sourceMaxBytes": 999
}`
	if err := os.WriteFile(path, []byte(body), 0o640); err != nil {
		t.Fatal(err)
	}
	return path
}

// TestRootsConfigPreservesForeignKeys is the file-configured deployment
// case: the same file carries apiKeys, signingSecret, and cache settings,
// and WaxDeck owns only the roots array. Losing the rest would take the
// sidecar's auth down on the next reload.
func TestRootsConfigPreservesForeignKeys(t *testing.T) {
	dir := t.TempDir()
	path := writeConfig(t, dir)

	roots := []Root{{Name: "lib", Path: "/library"}, {Name: "books", Path: "/books"}}
	prev, perm, err := readRootsConfig(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := writeRootsConfig(path, prev, perm, roots); err != nil {
		t.Fatalf("writeRootsConfig: %v", err)
	}

	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var got map[string]any
	if err = json.Unmarshal(raw, &got); err != nil {
		t.Fatalf("rewritten config is not JSON: %v\n%s", err, raw)
	}
	keys, _ := got["apiKeys"].([]any)
	if len(keys) != 2 || keys[0] != "secret-one" || keys[1] != "secret-two" {
		t.Errorf("apiKeys = %v, want both preserved", got["apiKeys"])
	}
	if got["signingSecret"] != "kid1:00ff" {
		t.Errorf("signingSecret = %v, want it preserved", got["signingSecret"])
	}
	if got["cacheMaxBytes"] != float64(123456) {
		t.Errorf("cacheMaxBytes = %v, want it preserved", got["cacheMaxBytes"])
	}
	if got["sourceMaxBytes"] != float64(999) {
		t.Errorf("sourceMaxBytes = %v, want it preserved", got["sourceMaxBytes"])
	}
	wrote, _ := json.Marshal(got["roots"])
	want, _ := json.Marshal([]any{
		map[string]any{"name": "lib", "path": "/library"},
		map[string]any{"name": "books", "path": "/books"},
	})
	if string(wrote) != string(want) {
		t.Errorf("roots = %s, want %s", wrote, want)
	}

	// The operator's mode survives: the file can hold secrets, and the
	// sidecar reads it as whatever user it runs as. Asked only off
	// Windows, which has no POSIX bits to report.
	if runtime.GOOS != "windows" {
		info, err := os.Stat(path)
		if err != nil {
			t.Fatal(err)
		}
		if perm := info.Mode().Perm(); perm != 0o640 {
			t.Errorf("mode = %v, want 0640 carried over from the replaced file", perm)
		}
	}
}

// TestRootsConfigRefusesMissingFile pins the deliberate non-creation: a
// config file WaxDeck invents is not the one the sidecar was started
// against, so a reload would reconcile against something else entirely.
func TestRootsConfigRefusesMissingFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "absent.json")
	_, _, err := readRootsConfig(path)
	if err == nil {
		t.Fatal("readRootsConfig on a missing file = nil, want an error")
	}
	if _, statErr := os.Stat(path); statErr == nil {
		t.Error("readRootsConfig created the file; it must not invent one")
	}
}

// TestReloadRootsWritesThenPosts pins the ordering the sidecar depends
// on: it re-reads the file synchronously inside the request, so the
// rewrite has to have landed before the POST arrives.
func TestReloadRootsWritesThenPosts(t *testing.T) {
	dir := t.TempDir()
	path := writeConfig(t, dir)

	var seenAtPost []Root
	var sawKey string
	b := newRootBridge(t, reloadCapsJSON(), path,
		[]Root{{Name: "lib", Path: "/library"}},
		func(w http.ResponseWriter, r *http.Request) {
			sawKey = r.Header.Get("X-API-Key")
			raw, err := os.ReadFile(path)
			if err != nil {
				t.Errorf("reading config inside the reload: %v", err)
			}
			var cfg struct {
				Roots []Root `json:"roots"`
			}
			if err := json.Unmarshal(raw, &cfg); err != nil {
				t.Errorf("config inside the reload is not JSON: %v", err)
			}
			seenAtPost = cfg.Roots
			fmt.Fprint(w, `{"schemaVersion":1,"added":["books"],"removed":[],"changed":[],"roots":["lib","books"]}`)
		})

	b.AddRoot("books", "/books")
	if err := b.ReloadRoots(context.Background()); err != nil {
		t.Fatalf("ReloadRoots: %v", err)
	}
	if sawKey != "key" {
		t.Errorf("X-API-Key = %q, want the bridge's key", sawKey)
	}
	if len(seenAtPost) != 2 {
		t.Fatalf("roots visible to the sidecar = %v, want both", seenAtPost)
	}
	names := map[string]string{}
	for _, r := range seenAtPost {
		names[r.Name] = r.Path
	}
	if names["books"] != "/books" {
		t.Errorf("the runtime root was not in the file when the reload ran: %v", seenAtPost)
	}
}

// TestSyncRootRollsBackARefusal: a root the sidecar cannot open must not
// survive in the config. It opens its roots at startup too, so a
// leftover would turn the next restart into a boot failure.
func TestSyncRootRollsBackARefusal(t *testing.T) {
	path := writeConfig(t, t.TempDir())
	before, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	b := newRootBridge(t, reloadCapsJSON(), path, []Root{{Name: "lib", Path: "/library"}},
		func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusBadRequest)
			fmt.Fprint(w, `{"error":"opening root books: no such file or directory","code":"invalid-request","schemaVersion":1}`)
		})

	err = b.SyncRoot(context.Background(), "books", "/books")
	if err == nil {
		t.Fatal("SyncRoot = nil on a refused reload, want the sidecar's reason")
	}
	if !strings.Contains(err.Error(), "opening root books") {
		t.Errorf("error = %v, want it to carry the sidecar's message", err)
	}
	after, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(after) != string(before) {
		t.Errorf("config left rewritten after a refusal:\n%s\nwant it restored to:\n%s", after, before)
	}
	for _, n := range b.RootNames() {
		if n == "books" {
			t.Error("the refused root is still in the bridge's table")
		}
	}
}

// TestSyncRootCarriesTheSidecarsCode: the daemon's error envelope is
// decoded into a waxerr code the caller can classify. The code is
// deliberately not what the status alone gives - the client falls back
// to internal for anything but a 401, so overloaded off a 503 proves the
// envelope was read.
func TestSyncRootCarriesTheSidecarsCode(t *testing.T) {
	path := writeConfig(t, t.TempDir())
	b := newRootBridge(t, reloadCapsJSON(), path, []Root{{Name: "lib", Path: "/library"}},
		func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusServiceUnavailable)
			fmt.Fprint(w, `{"error":"a job is holding the root set","code":"overloaded","schemaVersion":1}`)
		})

	err := b.SyncRoot(context.Background(), "books", "/books")
	if err == nil {
		t.Fatal("SyncRoot = nil on a refused reload, want the sidecar's reason")
	}
	if !errors.Is(err, waxerr.ErrOverloaded) {
		t.Errorf("error = %v, want the sidecar's own code to survive to the caller", err)
	}
	if !strings.Contains(err.Error(), "a job is holding the root set") {
		t.Errorf("error = %v, want it to carry the sidecar's message", err)
	}
}

// TestSyncRootSurvivesAnEarlierRefusal is the cascade the rollback
// exists to stop: one library with a path the sidecar cannot see must
// not block every library created after it.
func TestSyncRootSurvivesAnEarlierRefusal(t *testing.T) {
	path := writeConfig(t, t.TempDir())
	refuse := true
	b := newRootBridge(t, reloadCapsJSON(), path, []Root{{Name: "lib", Path: "/library"}},
		func(w http.ResponseWriter, r *http.Request) {
			if refuse {
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusBadRequest)
				fmt.Fprint(w, `{"error":"opening root bad: no such file or directory","code":"invalid-request","schemaVersion":1}`)
				return
			}
			fmt.Fprint(w, `{"schemaVersion":1,"added":["good"],"removed":[],"changed":[],"roots":["lib","good"]}`)
		})

	if err := b.SyncRoot(context.Background(), "bad", "/nowhere"); err == nil {
		t.Fatal("the first sync should have been refused")
	}
	refuse = false
	if err := b.SyncRoot(context.Background(), "good", "/good"); err != nil {
		t.Fatalf("the next library must not inherit the last one's bad path: %v", err)
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(raw), "nowhere") {
		t.Errorf("the refused root came back in the config:\n%s", raw)
	}
	if !strings.Contains(string(raw), "/good") {
		t.Errorf("the accepted root is missing from the config:\n%s", raw)
	}
}

// TestRootsReloadGatedByCaps pins the probe-time gate: a sidecar whose
// roots are pinned at startup reports rootsReload:false and 404s the
// endpoint, so WaxDeck must not rewrite its config either.
func TestRootsReloadGatedByCaps(t *testing.T) {
	path := writeConfig(t, t.TempDir())
	b := newRootBridge(t, capsJSON(), path, nil, nil)
	if b.RootsReloadSupported() {
		t.Fatal("RootsReloadSupported = true without delivery.rootsReload")
	}
	before, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	err = b.SyncRoot(context.Background(), "books", "/books")
	if err == nil {
		t.Error("SyncRoot = nil against a sidecar that does not serve reloads")
	} else if !strings.Contains(err.Error(), "restarted") {
		t.Errorf("error = %v, want it to name the restart streaming waits on", err)
	}
	after, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	// The config is left alone, and the message above says so. Writing the
	// root unreloaded would put a path nothing validated into a file the
	// sidecar opens at startup, which is a boot failure rather than a
	// degraded stream.
	if string(before) != string(after) {
		t.Error("the config was rewritten for a reload the sidecar cannot serve")
	}
	// The bridge keeps the root here: an operator who restarts the
	// sidecar with it configured gets streaming without restarting
	// WaxDeck as well.
	var kept bool
	for _, n := range b.RootNames() {
		if n == "books" {
			kept = true
		}
	}
	if !kept {
		t.Error("the root was dropped from the bridge; only a sidecar refusal should do that")
	}
}

// TestRootsReloadNeedsConfigPath covers the env-configured sidecar:
// there is no file to rewrite, so support is off even when the sidecar
// itself would serve the endpoint.
func TestRootsReloadNeedsConfigPath(t *testing.T) {
	b := newRootBridge(t, reloadCapsJSON(), "", nil, nil)
	if b.RootsReloadSupported() {
		t.Fatal("RootsReloadSupported = true with no config file configured")
	}
	if err := b.ReloadRoots(context.Background()); err == nil {
		t.Error("ReloadRoots = nil with no config file configured")
	}
}

// TestAddRootResolvesStreamRefs: resolution walks the bridge's own root
// table, so a library it never learned streams from nowhere whatever the
// reload did. Also pins longest-path-first, which a plain append breaks.
func TestAddRootResolvesStreamRefs(t *testing.T) {
	b := newRootBridge(t, reloadCapsJSON(), "", []Root{{Name: "lib", Path: "/srv/media"}}, nil)

	if _, err := b.srcRef("/srv/media/extra/book.m4b"); err != nil {
		t.Fatalf("srcRef under the startup root: %v", err)
	}
	b.AddRoot("books", "/srv/media/extra")

	ref, err := b.srcRef("/srv/media/extra/book.m4b")
	if err != nil {
		t.Fatalf("srcRef after AddRoot: %v", err)
	}
	if ref != "books/book.m4b" {
		t.Errorf("ref = %q, want books/book.m4b (the most specific root)", ref)
	}
	ref, err = b.srcRef("/srv/media/album/track.flac")
	if err != nil {
		t.Fatalf("srcRef under the outer root: %v", err)
	}
	if ref != "lib/album/track.flac" {
		t.Errorf("ref = %q, want lib/album/track.flac", ref)
	}
	names := b.RootNames()
	if len(names) != 2 {
		t.Errorf("RootNames = %v, want both roots", names)
	}
}

// TestRootsConfigMergesByName: `path` here is the sidecar's view of the
// filesystem, so rewriting it from WaxDeck's table would repoint a
// working root, and replacing the array would drop roots the operator
// configured and WaxDeck knows nothing about.
func TestRootsConfigMergesByName(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "waxflow.json")
	body := `{
  "roots": [
    {"name": "lib", "path": "/mnt/media"},
    {"name": "operator-only", "path": "/mnt/extra"}
  ]
}`
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	prev, perm, err := readRootsConfig(path)
	if err != nil {
		t.Fatal(err)
	}
	// WaxDeck knows lib at its own mount point, plus a runtime addition.
	roots := []Root{{Name: "lib", Path: "/library"}, {Name: "books", Path: "/library/books"}}
	if err := writeRootsConfig(path, prev, perm, roots); err != nil {
		t.Fatalf("writeRootsConfig: %v", err)
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var got struct {
		Roots []Root `json:"roots"`
	}
	if err := json.Unmarshal(raw, &got); err != nil {
		t.Fatalf("rewritten config is not JSON: %v\n%s", err, raw)
	}
	paths := map[string]string{}
	for _, r := range got.Roots {
		paths[r.Name] = r.Path
	}
	if paths["lib"] != "/mnt/media" {
		t.Errorf("lib = %q, want the sidecar's own path preserved", paths["lib"])
	}
	if paths["operator-only"] != "/mnt/extra" {
		t.Errorf("operator-only = %q, want a root WaxDeck does not know left alone", paths["operator-only"])
	}
	if paths["books"] != "/library/books" {
		t.Errorf("books = %q, want the new root appended with WaxDeck's path", paths["books"])
	}
	if len(got.Roots) != 3 {
		t.Errorf("roots = %v, want exactly the three", got.Roots)
	}
}
