package service

import (
	"context"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/proxy"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// A data dir the socket fits in keeps it beside the catalog.
func TestIPCSocketSitsBesideTheCatalog(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	socket, sockDir, made := ipcSocket(dir)
	if socket != filepath.Join(dir, SocketFileName) || sockDir != "" || made {
		t.Errorf("socket = %q in %q (made %v), want it beside the catalog", socket, sockDir, made)
	}
}

// socketBases points the runtime and temp dirs at fresh ones of the test's,
// shallow ones: a test's own temp dir is named after the test and can be
// too deep for a socket under it.
func socketBases(t *testing.T) (runtimeDir, tempDir string) {
	t.Helper()
	shallow := func() string {
		d, err := os.MkdirTemp("", "sock")
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { os.RemoveAll(d) })
		return d
	}
	runtimeDir, tempDir = shallow(), shallow()
	t.Setenv("XDG_RUNTIME_DIR", runtimeDir)
	t.Setenv("TMPDIR", tempDir)
	return runtimeDir, tempDir
}

// A data dir too deep for a unix socket's path puts the socket in a private
// directory of its own under the runtime dir, short enough to bind and to
// dial. A restart after a crash that skipped Close finds the same directory
// rather than leaving another behind.
func TestIPCSocketLeavesADataDirTooDeepForIt(t *testing.T) {
	runtimeDir, _ := socketBases(t)
	dataDir := filepath.Join(t.TempDir(), strings.Repeat("d", maxSocketPath))
	socket, sockDir, made := ipcSocket(dataDir)
	if !made || filepath.Dir(sockDir) != runtimeDir {
		t.Fatalf("socket = %q in %q (made %v), want a new one under %s", socket, sockDir, made, runtimeDir)
	}
	if len(socket) > maxSocketPath || filepath.Dir(socket) != sockDir {
		t.Errorf("socket = %q (%d bytes) in %q", socket, len(socket), sockDir)
	}
	fi, err := os.Stat(sockDir)
	if err != nil {
		t.Fatal(err)
	}
	if runtime.GOOS != "windows" && fi.Mode().Perm() != 0o700 {
		t.Errorf("the socket's directory is %v, want it private", fi.Mode().Perm())
	}

	again, againDir, madeAgain := ipcSocket(dataDir)
	if again != socket || againDir != sockDir || madeAgain {
		t.Errorf("the next start got %q in %q (made %v), want %q again", again, againDir, madeAgain, socket)
	}
	entries, err := os.ReadDir(runtimeDir)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 1 {
		t.Errorf("the runtime dir holds %d entries after two starts, want 1", len(entries))
	}
}

// A directory under the socket's name that is not private to this user
// is someone else's to swap the socket in, so it is passed over.
func TestIPCSocketPassesOverADirectoryItDoesNotOwnOutright(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Windows gives each account its own temp dir")
	}
	_, tempDir := socketBases(t)
	dataDir := filepath.Join(t.TempDir(), strings.Repeat("d", maxSocketPath))
	socket, sockDir, _ := ipcSocket(dataDir)
	if err := os.Chmod(sockDir, 0o755); err != nil {
		t.Fatal(err)
	}
	other, otherDir, made := ipcSocket(dataDir)
	if otherDir == sockDir || other == socket {
		t.Fatalf("socket = %q, in the directory opened to others", other)
	}
	if !made || filepath.Dir(otherDir) != tempDir {
		t.Errorf("socket = %q in %q (made %v), want a new one under %s", other, otherDir, made, tempDir)
	}
	if fi, err := os.Stat(sockDir); err != nil || fi.Mode().Perm() != 0o755 {
		t.Errorf("the passed-over directory was touched: %v, %v", fi, err)
	}
}

// The CLI finds the socket through the catalog's lockfile, so a server whose
// data dir is too deep for one still answers the CLI, wherever the lockfile
// says, and leaves nothing behind when it stops.
func TestTheCLIReachesAServerWhoseDataDirIsTooDeepForItsSocket(t *testing.T) {
	t.Parallel()
	ctx, cancel := context.WithCancel(context.Background())
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	dataDir := filepath.Join(t.TempDir(), strings.Repeat("d", maxSocketPath))
	if err := os.MkdirAll(dataDir, 0o755); err != nil {
		t.Fatal(err)
	}
	store, err := wdb.Open(ctx, filepath.Join(dataDir, "waxdeck.db"))
	if err != nil {
		t.Fatal(err)
	}
	group := supervise.NewGroup(log)
	svc, err := Open(ctx, Config{
		DataDir: dataDir,
		Roots:   []Root{{Name: "lib", Path: t.TempDir()}},
		Logger:  log,
	}, store, group)
	if err != nil {
		t.Fatal(err)
	}
	stopped := false
	stop := func() {
		if stopped {
			return
		}
		stopped = true
		cancel()
		group.Wait()
		svc.Close()
		store.Close()
	}
	t.Cleanup(stop)

	owner, err := waxbin.ReadLockOwner(filepath.Join(dataDir, "waxbin.db"))
	if err != nil {
		t.Fatal(err)
	}
	socket := owner.IPCSocket
	if len(socket) > maxSocketPath {
		t.Fatalf("the lockfile advertises a %d-byte socket: %s", len(socket), socket)
	}
	// The serve worker starts on the group, so give it a moment to listen.
	for deadline := time.Now().Add(10 * time.Second); ; {
		c, err := proxy.Dial(socket)
		if err == nil {
			err = c.Ping(ctx)
			c.Close()
		}
		if err == nil {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("the CLI cannot reach %s: %v", socket, err)
		}
		time.Sleep(20 * time.Millisecond)
	}
	stop()
	if _, err := os.Stat(filepath.Dir(socket)); !os.IsNotExist(err) {
		t.Errorf("the socket's directory outlived the server: %v", err)
	}
}
