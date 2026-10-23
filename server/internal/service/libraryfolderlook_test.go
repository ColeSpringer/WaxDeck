package service

import (
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

// A look at a folder that outlives the managed create that started it
// writes no probe once that create has gone: the folder answers while
// only an unmanaged create at it waits, which takes the same look, and
// that library's folder is left as it was.
func TestALookThatOutlivesItsCreateWritesNoProbe(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	ctx, svc, uc, _ := openServiceAt(t, dataDir, nil)
	folder := filepath.Join(dataDir, "slow")
	if err := os.Mkdir(folder, 0o755); err != nil {
		t.Fatal(err)
	}
	var looks atomic.Int32
	answer := make(chan struct{})
	var answered atomic.Bool
	t.Cleanup(func() {
		if answered.CompareAndSwap(false, true) {
			close(answer)
		}
	})
	svc.creates.wait = 200 * time.Millisecond
	svc.creates.look = func(path string) folderAnswer {
		if path == folder {
			looks.Add(1)
			<-answer
		}
		return lookAt(path)
	}
	n, mtime := folderState(t, folder)

	if _, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "slow", Path: folder, Managed: true}); err == nil ||
		!strings.Contains(err.Error(), "did not answer") {
		t.Fatalf("the managed create = %v, want it refused for the folder not answering", err)
	}
	done := make(chan error, 1)
	go func() {
		_, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "slow", Path: folder})
		done <- err
	}()
	waitFor(t, func() bool {
		svc.creates.mu.Lock()
		defer svc.creates.mu.Unlock()
		return len(svc.creates.claims) == 1
	}, "the unmanaged create to claim the folder")
	answered.Store(true)
	close(answer)
	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("the unmanaged create once the folder answers = %v", err)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("the unmanaged create never answered")
	}
	waitFor(t, func() bool { return svc.rootProbe.idle() }, "the probe pass to end")
	if n2, mtime2 := folderState(t, folder); n2 != n || !mtime2.Equal(mtime) {
		t.Errorf("the folder went from %d entries at %v to %d at %v, want no probe written there", n, mtime, n2, mtime2)
	}
	if got := looks.Load(); got != 1 {
		t.Errorf("the folder was looked at %d times, want one look for both creates", got)
	}
}

// A look that breaks answers its creates as a failure at once, and the
// next create at the folder looks again rather than waiting on it.
func TestALookThatBreaksAnswersAsAFailure(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	ctx, svc, uc, _ := openServiceAt(t, dataDir, nil)
	folder := t.TempDir()
	var broke atomic.Bool
	svc.creates.wait = 5 * time.Second
	svc.creates.look = func(path string) folderAnswer {
		if path == folder && broke.CompareAndSwap(false, true) {
			panic("the look broke")
		}
		return lookAt(path)
	}
	start := time.Now()
	_, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "broken", Path: folder})
	if KindOf(err) != KindInvalid || strings.Contains(err.Error(), "did not answer") || time.Since(start) > 3*time.Second {
		t.Fatalf("the create whose look broke = %v after %v, want it refused at once", err, time.Since(start))
	}
	if _, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "broken", Path: folder}); err != nil {
		t.Errorf("the next create at the folder = %v, want a fresh look to take it", err)
	}
}
