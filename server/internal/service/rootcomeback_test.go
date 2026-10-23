package service

import (
	"context"
	"errors"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
)

// folderFlowRoots is a bridge whose sidecar opens each root it is taught,
// and so refuses one whose folder is not there.
type folderFlowRoots struct {
	fakeFlowRoots
}

func (f *folderFlowRoots) SyncRoot(ctx context.Context, name, path string) error {
	if _, err := os.Stat(path); err != nil {
		return errors.New("opening root " + name + ": no such file or directory")
	}
	return f.fakeFlowRoots.SyncRoot(ctx, name, path)
}

// A library registered before its folder is mounted streams once the
// folder is there, without a restart: the scan that finds it back offers
// it to the sidecar again, which refused it while it was missing.
func TestARootBackFromAbsenceIsTaughtToTheSidecar(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := openServiceAt(t, t.TempDir(), nil)
	flow := &folderFlowRoots{fakeFlowRoots{names: []string{"configured"}}}
	svc.SetFlowRoots(flow)
	later := filepath.Join(t.TempDir(), "later")
	info, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "later", Path: later, AllowAbsent: true})
	if err != nil {
		t.Fatal(err)
	}
	if info.StreamingWarning == "" {
		t.Fatal("the absent folder streamed at once, want the sidecar's refusal")
	}
	waitFor(t, func() bool {
		running, err := svc.catalogJobRunning(ctx)
		return err == nil && !running
	}, "the create's scan to end")
	if err := os.Mkdir(later, 0o755); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Rescan(ctx, false); err != nil {
		t.Fatal(err)
	}
	waitFor(t, func() bool { return flow.taught("later", later) }, "the sidecar taught the folder once it is there")
	svc.flowSyncMu.Lock()
	_, refused := svc.flowRefused["later"]
	svc.flowSyncMu.Unlock()
	if refused {
		t.Error("the refusal of the missing folder is still remembered")
	}
}

// awayFlowRoots is folderFlowRoots behind an engine that can be away.
type awayFlowRoots struct {
	folderFlowRoots
	away atomic.Bool
}

func (f *awayFlowRoots) Up() bool { return !f.away.Load() }

// A folder back while the engine is away is offered nothing and no
// refusal is remembered or warned of; the refusal from when it was
// missing is forgotten, so the engine's return offers it with every root.
func TestARootBackWhileTheEngineIsAwayWaitsForItsReturn(t *testing.T) {
	t.Parallel()
	var logged lockedBuffer
	ctx, svc, uc, _ := openServiceAt(t, t.TempDir(), func(c *Config) {
		c.Logger = slog.New(slog.NewTextHandler(&logged, nil))
	})
	flow := &awayFlowRoots{folderFlowRoots: folderFlowRoots{fakeFlowRoots{names: []string{"configured"}}}}
	svc.SetFlowRoots(flow)
	later := filepath.Join(t.TempDir(), "later")
	if _, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "later", Path: later, AllowAbsent: true}); err != nil {
		t.Fatal(err)
	}
	waitFor(t, func() bool {
		running, err := svc.catalogJobRunning(ctx)
		return err == nil && !running
	}, "the create's scan to end")
	refused := func() bool {
		svc.flowSyncMu.Lock()
		defer svc.flowSyncMu.Unlock()
		_, ok := svc.flowRefused["later"]
		return ok
	}
	if !refused() {
		t.Fatal("the missing folder's refusal was not remembered")
	}
	const warned = "the streaming sidecar did not take a library's root"
	warns := strings.Count(logged.String(), warned)
	flow.away.Store(true)
	flow.mu.Lock()
	offered := len(flow.synced)
	flow.mu.Unlock()

	if err := os.Mkdir(later, 0o755); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Rescan(ctx, false); err != nil {
		t.Fatal(err)
	}
	waitFor(t, func() bool { return !refused() }, "the old refusal forgotten")
	flow.mu.Lock()
	offeredAway := len(flow.synced)
	flow.mu.Unlock()
	if offeredAway != offered {
		t.Errorf("the engine was offered the root %d times while away, want none", offeredAway-offered)
	}
	if n := strings.Count(logged.String(), warned); n != warns {
		t.Errorf("%d refusals warned of while the engine was away, want none", n-warns)
	}

	flow.away.Store(false)
	svc.syncFlowRoots(ctx)
	if !flow.taught("later", later) {
		t.Error("the engine's return did not offer the folder")
	}
}
