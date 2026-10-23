package service

import (
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

// A create whose folder does not answer, as on a mount that stopped
// answering, fails on its own once the wait runs out and holds up no
// other create meanwhile; tried again, it waits on the look still out
// rather than starting another.
func TestACreateAtAFolderThatDoesNotAnswerFailsAlone(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	ctx, svc, uc, _ := openServiceAt(t, dataDir, nil)
	hung := filepath.Join(dataDir, "hung")
	var looks atomic.Int32
	answer := make(chan struct{})
	// Registered after the service's own cleanup, so it runs first and the
	// stand-in returns before the service waits out its workers.
	t.Cleanup(func() { close(answer) })
	svc.creates.wait = 200 * time.Millisecond
	svc.creates.look = func(path string) folderAnswer {
		if path == hung {
			looks.Add(1)
			<-answer
		}
		return lookAt(path)
	}
	create := func(name, path string) <-chan error {
		done := make(chan error, 1)
		go func() {
			_, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: name, Path: path, Managed: true})
			done <- err
		}()
		return done
	}
	answered := func(done <-chan error, what string) error {
		t.Helper()
		select {
		case err := <-done:
			return err
		case <-time.After(10 * time.Second):
			t.Fatalf("%s never answered", what)
			return nil
		}
	}

	stuck := create("hung", hung)
	waitFor(t, func() bool { return looks.Load() == 1 }, "the hung folder looked at")
	if err := answered(create("other", t.TempDir()), "a create at another folder"); err != nil {
		t.Fatalf("a create at another folder while one hangs = %v", err)
	}
	err := answered(stuck, "the create at the folder that does not answer")
	if KindOf(err) != KindInvalid || !strings.Contains(err.Error(), "did not answer") {
		t.Errorf("the create at the folder that does not answer = %v, want it refused for that", err)
	}
	if err := answered(create("hung", hung), "the create tried again"); KindOf(err) != KindInvalid {
		t.Errorf("the create tried again = %v, want it refused the same way", err)
	}
	if n := looks.Load(); n != 1 {
		t.Errorf("the folder was looked at %d times, want once while the first look is out", n)
	}
}
