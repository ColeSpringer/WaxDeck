package service

import (
	"context"
	"database/sql"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/port"
	"github.com/colespringer/waxdeck/fixtures"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// newStaleCatalog scans a one-track library, then rewrites the catalog's
// baseline fingerprint so the next open refuses it. That is the same condition
// a build whose baseline moved produces, without needing the older binary to
// produce it: the guard compares PRAGMA user_version against this build's
// fingerprint and nothing else. Returns the data dir and the library root.
func newStaleCatalog(t *testing.T) (dataDir, libDir string) {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	log := slog.New(slog.NewTextHandler(io.Discard, nil))

	libDir = t.TempDir()
	if _, err := fixtures.Generate(libDir, fixtures.Spec{
		Name:     "amber",
		Codec:    fixtures.CodecFLAC,
		Duration: 2 * time.Second,
		Tags:     map[string]string{"TITLE": "Amber Waves", "ARTIST": "Test Ensemble"},
	}); err != nil {
		t.Fatalf("generating fixtures: %v", err)
	}

	dataDir = t.TempDir()
	store, err := wdb.Open(ctx, filepath.Join(dataDir, "waxdeck.db"))
	if err != nil {
		t.Fatal(err)
	}
	group := supervise.NewGroup(log)
	svc, err := Open(ctx, Config{
		DataDir: dataDir,
		Roots:   []Root{{Name: "lib", Path: libDir}},
		Logger:  log,
	}, store, group)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatalf("scanning fixture library: %v", err)
	}
	cancel()
	svc.Close()
	group.Wait()
	store.Close()

	db, err := sql.Open("sqlite", "file:"+filepath.Join(dataDir, "waxbin.db"))
	if err != nil {
		t.Fatal(err)
	}
	// Any value the build's fingerprint is not. 1 is safe: the fingerprint is
	// four bytes of a SHA-256 and would have to collide to matter.
	if _, err := db.ExecContext(context.Background(), "PRAGMA user_version = 1"); err != nil {
		t.Fatalf("stamping a stale baseline: %v", err)
	}
	if err := db.Close(); err != nil {
		t.Fatal(err)
	}
	return dataDir, libDir
}

// openCatalog re-opens the service over an existing data dir. Callers own the
// returned service; err is theirs to assert on.
func openCatalog(t *testing.T, dataDir, libDir string, reset bool) (*Library, func(), error) {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	store, err := wdb.Open(ctx, filepath.Join(dataDir, "waxdeck.db"))
	if err != nil {
		cancel()
		t.Fatal(err)
	}
	group := supervise.NewGroup(log)
	svc, err := Open(ctx, Config{
		DataDir:           dataDir,
		Roots:             []Root{{Name: "lib", Path: libDir}},
		Logger:            log,
		ResetStaleCatalog: reset,
	}, store, group)
	stop := func() {
		cancel()
		if svc != nil {
			svc.Close()
		}
		group.Wait()
		store.Close()
	}
	return svc, stop, err
}

// A catalog from a different baseline is refused rather than opened, and the
// refusal names a recovery a WaxDeck operator can actually perform. The catalog
// message names `waxbin db reset`, a CLI they do not have.
func TestStaleBaselineCatalogIsRefusedWithAWaxDeckRecovery(t *testing.T) {
	t.Parallel()
	dataDir, libDir := newStaleCatalog(t)

	svc, stop, err := openCatalog(t, dataDir, libDir, false)
	defer stop()
	if err == nil {
		t.Fatal("opening a stale-baseline catalog succeeded, want a refusal")
	}
	if svc != nil {
		t.Fatal("a refused open returned a service")
	}
	msg := err.Error()
	if !strings.Contains(msg, "-reset-catalog") {
		t.Errorf("refusal does not name the WaxDeck recovery: %s", msg)
	}
	if !strings.Contains(msg, "WAXDECK_RESET_CATALOG") {
		t.Errorf("refusal does not name the env form of the recovery: %s", msg)
	}

	// The catalog is left where it was: refusing must not discard anything.
	if _, err := os.Stat(filepath.Join(dataDir, "waxbin.db")); err != nil {
		t.Errorf("catalog is gone after a refusal: %v", err)
	}
}

// With the flag set, startup moves the stale catalog aside and comes up on a
// fresh one. The previous catalog is renamed, not deleted.
func TestResetCatalogMovesTheStaleCatalogAsideAndStarts(t *testing.T) {
	t.Parallel()
	dataDir, libDir := newStaleCatalog(t)

	svc, stop, err := openCatalog(t, dataDir, libDir, true)
	defer stop()
	if err != nil {
		t.Fatalf("opening with -reset-catalog: %v", err)
	}
	if svc == nil {
		t.Fatal("no service after a successful reset")
	}

	entries, err := os.ReadDir(dataDir)
	if err != nil {
		t.Fatal(err)
	}
	var saved string
	for _, e := range entries {
		if strings.HasPrefix(e.Name(), "waxbin.db.stale-") && strings.HasSuffix(e.Name(), ".bak") {
			saved = e.Name()
		}
	}
	if saved == "" {
		t.Fatalf("no .stale-<ts>.bak beside the fresh catalog; dir holds %v", entries)
	}

	// Renamed, not deleted: the discarded catalog still holds what it held,
	// so a mis-fire is recoverable.
	census, err := port.ReadCensus(context.Background(), filepath.Join(dataDir, saved))
	if err != nil {
		t.Fatalf("censusing the saved catalog: %v", err)
	}
	if !census.Partial && census.Items != 1 {
		t.Errorf("saved catalog holds %d items, want the 1 that was scanned", census.Items)
	}
}

// The reset fires only on a stale baseline. A catalog this build can open is
// opened, never moved aside -- otherwise leaving the flag set in a compose file
// would discard the catalog on every restart.
func TestResetCatalogLeavesAHealthyCatalogAlone(t *testing.T) {
	t.Parallel()
	dataDir, libDir := newStaleCatalog(t)

	// Reset once to get a healthy catalog, then restart with the flag still on.
	_, stop, err := openCatalog(t, dataDir, libDir, true)
	if err != nil {
		t.Fatalf("first open: %v", err)
	}
	stop()

	before, err := filepath.Glob(filepath.Join(dataDir, "waxbin.db.stale-*"))
	if err != nil {
		t.Fatal(err)
	}

	svc, stop2, err := openCatalog(t, dataDir, libDir, true)
	defer stop2()
	if err != nil {
		t.Fatalf("restarting on a healthy catalog: %v", err)
	}
	if svc == nil {
		t.Fatal("no service after restart")
	}
	after, err := filepath.Glob(filepath.Join(dataDir, "waxbin.db.stale-*"))
	if err != nil {
		t.Fatal(err)
	}
	if len(after) != len(before) {
		t.Errorf("restart moved a healthy catalog aside: %d backups before, %d after", len(before), len(after))
	}
}

// staleBaseline is the predicate that decides whether discarding the catalog is
// the cure, so it has to answer false for everything that is not a baseline
// mismatch -- a missing file and a file that is not a catalog included.
func TestStaleBaselineOnlyAnswersForABaselineMismatch(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	dir := t.TempDir()

	missing := filepath.Join(dir, "absent.db")
	if staleBaseline(ctx, missing) {
		t.Error("a missing catalog reads as a stale baseline")
	}

	notACatalog := filepath.Join(dir, "junk.db")
	if err := os.WriteFile(notACatalog, []byte("not a database"), 0o600); err != nil {
		t.Fatal(err)
	}
	if staleBaseline(ctx, notACatalog) {
		t.Error("a non-catalog file reads as a stale baseline")
	}

	dataDir, _ := newStaleCatalog(t)
	if !staleBaseline(ctx, filepath.Join(dataDir, "waxbin.db")) {
		t.Error("a genuinely stale catalog does not read as one")
	}
}

// The set moves together: a -wal holding commits the main file lacks must not
// be left behind, or the backup that makes a mis-fire recoverable is missing
// the newest writes.
func TestMoveCatalogAsideMovesTheSidecarsWithIt(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	db := filepath.Join(dir, "waxbin.db")
	for _, suffix := range []string{"", "-wal", "-shm"} {
		if err := os.WriteFile(db+suffix, []byte(suffix), 0o600); err != nil {
			t.Fatal(err)
		}
	}

	dest, err := moveCatalogAside(db)
	if err != nil {
		t.Fatalf("moveCatalogAside: %v", err)
	}
	for _, suffix := range []string{"", "-wal", "-shm"} {
		if _, err := os.Stat(db + suffix); !os.IsNotExist(err) {
			t.Errorf("%s was left behind", db+suffix)
		}
		b, err := os.ReadFile(dest + suffix)
		if err != nil {
			t.Errorf("reading moved %s: %v", dest+suffix, err)
			continue
		}
		if string(b) != suffix {
			t.Errorf("moved %s holds %q, want %q", dest+suffix, b, suffix)
		}
	}

	// Nothing to move is not an error, and names no destination.
	if got, err := moveCatalogAside(filepath.Join(dir, "absent.db")); err != nil || got != "" {
		t.Errorf("moveCatalogAside on a missing catalog = (%q, %v), want (\"\", nil)", got, err)
	}
}

// A second reset inside the same second must not overwrite the backup the first
// one just made: the timestamp is second-granular and os.Rename is silent.
func TestMoveCatalogAsideTakesTheFirstFreeName(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	db := filepath.Join(dir, "waxbin.db")

	if err := os.WriteFile(db, []byte("first"), 0o600); err != nil {
		t.Fatal(err)
	}
	first, err := moveCatalogAside(db)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(db, []byte("second"), 0o600); err != nil {
		t.Fatal(err)
	}
	second, err := moveCatalogAside(db)
	if err != nil {
		t.Fatal(err)
	}
	if first == second {
		t.Fatalf("both resets used %s", first)
	}
	b, err := os.ReadFile(first)
	if err != nil {
		t.Fatal(err)
	}
	if string(b) != "first" {
		t.Errorf("the first backup now holds %q, want %q", b, "first")
	}
}

func TestRootsNotConfiguredNamesOnlyTheRootsStartupWillNotRestore(t *testing.T) {
	t.Parallel()
	got := rootsNotConfigured(
		[]string{"/music", "/added-at-runtime", "/podcasts"},
		[]Root{{Name: "music", Path: "/music"}, {Name: "pod", Path: "/podcasts"}},
	)
	if len(got) != 1 || got[0] != "/added-at-runtime" {
		t.Fatalf("rootsNotConfigured = %v, want [/added-at-runtime]", got)
	}
	if got := rootsNotConfigured(nil, []Root{{Path: "/music"}}); len(got) != 0 {
		t.Fatalf("rootsNotConfigured with no catalog roots = %v, want empty", got)
	}
}
