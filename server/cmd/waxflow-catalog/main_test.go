package main

import (
	"bytes"
	"context"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxflow/cli"
	"github.com/colespringer/waxflow/source"
)

// noRoots is the root resolver a test's catalog delegates to.
type noRoots struct{}

func (noRoots) Resolve(context.Context, string) (*source.File, error) { return nil, os.ErrNotExist }

// syncLog collects what the resolver says while it waits.
type syncLog struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (l *syncLog) Write(p []byte) (int, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.buf.Write(p)
}

func (l *syncLog) count(s string) int {
	l.mu.Lock()
	defer l.mu.Unlock()
	return strings.Count(l.buf.String(), s)
}

// shortWait shortens the catalog wait for one test.
func shortWait(t *testing.T, every, limit time.Duration) {
	t.Helper()
	saved := catalogWait
	catalogWait.every, catalogWait.limit = every, limit
	t.Cleanup(func() { catalogWait = saved })
}

// createCatalog lays down a WaxBin catalog at path, as WaxDeck's first
// start does.
func createCatalog(path string) error {
	lib, err := waxbin.Open(context.Background(), waxbin.Options{DBPath: path})
	if err != nil {
		return err
	}
	return lib.Close()
}

func daemonOpts(path string, log io.Writer) cli.ResolverOptions {
	return cli.ResolverOptions{
		CatalogDB: path, MaxBytes: 1 << 20, Next: noRoots{}, Daemon: true,
		Logger: slog.New(slog.NewTextHandler(log, nil)),
	}
}

// The sidecar started before WaxDeck waits for the catalog WaxDeck
// creates, saying so once, instead of exiting into a restart loop. The
// file appearing mid-creation is waited out too.
func TestOpenResolverWaitsForTheCatalog(t *testing.T) {
	shortWait(t, 5*time.Millisecond, time.Minute)
	path := filepath.Join(t.TempDir(), "waxbin.db")
	created := make(chan error, 1)
	time.AfterFunc(300*time.Millisecond, func() { created <- createCatalog(path) })
	logs := &syncLog{}
	res, closer, err := openResolver(context.Background(), daemonOpts(path, logs))
	if cerr := <-created; cerr != nil {
		t.Fatalf("creating the catalog: %v", cerr)
	}
	if err != nil {
		t.Fatalf("openResolver = %v, want the catalog once it appeared", err)
	}
	t.Cleanup(func() { closer.Close() })
	if _, ok := res.(*catalog); !ok {
		t.Fatalf("resolver = %T, want the catalog resolver", res)
	}
	if n := logs.count("waiting for the catalog"); n != 1 {
		t.Fatalf("said it waits %d times, want once", n)
	}
}

// The wait ends with the process.
func TestOpenResolverStopsWaitingWithItsContext(t *testing.T) {
	shortWait(t, 5*time.Millisecond, time.Minute)
	ctx, cancel := context.WithCancel(context.Background())
	time.AfterFunc(50*time.Millisecond, cancel)
	_, _, err := openResolver(ctx, daemonOpts(filepath.Join(t.TempDir(), "waxbin.db"), io.Discard))
	if err == nil {
		t.Fatal("openResolver answered nil after its context ended")
	}
}

// A catalog that never comes fails the start once the wait is spent,
// naming where it looked.
func TestOpenResolverGivesUpAfterItsWait(t *testing.T) {
	shortWait(t, 5*time.Millisecond, 30*time.Millisecond)
	path := filepath.Join(t.TempDir(), "waxbin.db")
	_, _, err := openResolver(context.Background(), daemonOpts(path, io.Discard))
	if err == nil || !strings.Contains(err.Error(), path) {
		t.Fatalf("openResolver = %v, want a refusal naming %s", err, path)
	}
}

// A one-shot command never waits: a missing catalog is its answer.
func TestOpenResolverWaitsOnlyAsADaemon(t *testing.T) {
	shortWait(t, time.Hour, time.Hour)
	opts := daemonOpts(filepath.Join(t.TempDir(), "waxbin.db"), io.Discard)
	opts.Daemon = false
	if _, _, err := openResolver(context.Background(), opts); err == nil {
		t.Fatal("a one-shot command opened a catalog that does not exist")
	}
}

// A catalog the sidecar cannot read is no catalog WaxDeck has yet to
// create: it fails at once, in the open's own words, rather than after
// the whole wait as "no catalog".
func TestOpenResolverDoesNotWaitOnAnUnreadableCatalog(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("root reads any directory")
	}
	shortWait(t, time.Hour, time.Hour)
	locked := filepath.Join(t.TempDir(), "locked")
	if err := os.Mkdir(locked, 0o000); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.Chmod(locked, 0o755) })
	path := filepath.Join(locked, "waxbin.db")

	done := make(chan error, 1)
	go func() {
		_, _, err := openResolver(context.Background(), daemonOpts(path, io.Discard))
		done <- err
	}()
	select {
	case err := <-done:
		if err == nil || strings.Contains(err.Error(), "no catalog at") {
			t.Fatalf("openResolver = %v, want the open's own refusal", err)
		}
	case <-time.After(30 * time.Second):
		t.Fatal("the resolver waited on a catalog it cannot read")
	}
}
