package service

import (
	"errors"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/auth"
	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
)

// offersOf counts the offers the bridge was made of name.
func (f *fakeFlowRoots) offersOf(name string) int {
	f.mu.Lock()
	defer f.mu.Unlock()
	n := 0
	for _, r := range f.synced {
		if r.Name == name {
			n++
		}
	}
	return n
}

// A root offered between the engine's answer after an outage and that
// answer's re-sync (a library's own sync, a folder back from an outage)
// was refused by the engine that answered: the re-sync leaves that
// refusal standing, so the root is not offered twice for one answer. A
// refusal from before an outage is let go at the answer that ends it,
// since the engine may be one restarted where it can see the root.
func TestAnAnswersResyncLeavesARefusalItsOwnEngineGave(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newCatalogFixture(t)
	libDir := svc.RootTable()[0].Path
	bridge := &hookedFlowRoots{}
	bridge.refuse(errors.New("opening root: no such file or directory"))
	svc.FollowEngine(ctx, bridge)
	waitFor(t, func() bool { return svc.flowRefusedAt("lib", libDir) }, "the boot's offer of lib refused")
	bridge.down()

	// The answer's re-sync waits on the lock this offer holds.
	svc.flowSyncMu.Lock()
	bridge.up(ctx)
	if warning := svc.teachFlowRoot(ctx, bridge, "lib", libDir); warning == "" {
		svc.flowSyncMu.Unlock()
		t.Fatal("the engine that answered took lib, want it refused")
	}
	// The re-sync's pass takes this owed unmount off first, which marks it.
	if err := svc.db.SettingSet(ctx, flowUnmountKey+"marker", "/gone", time.Now().UnixNano()); err != nil {
		svc.flowSyncMu.Unlock()
		t.Fatal(err)
	}
	bridge.refuse(nil)
	svc.flowSyncMu.Unlock()
	waitFor(t, func() bool { return slices.Contains(bridge.removedNames(), "marker") }, "the answer's re-sync to run")
	// It holds the lock for its whole pass.
	svc.flowSyncMu.Lock()
	svc.flowSyncMu.Unlock()
	if n := bridge.offersOf("lib"); n != 2 {
		t.Fatalf("lib offered %d times, want twice: at the boot, and once after the answer", n)
	}

	bridge.down()
	bridge.up(ctx)
	waitFor(t, func() bool { return slices.Contains(bridge.RootNames(), "lib") },
		"lib, refused before this outage, offered again at its answer")
}

// Through the real bridge, nothing is remembered as refused or warned of
// while the engine is away: a folder mounted later that comes back during
// an outage, and a library created during it, are held for the engine,
// and its answer offers each once and takes it.
func TestNothingIsRefusedWhileTheEngineIsAway(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	var logged lockedBuffer
	ctx, svc, uc, _ := openServiceAt(t, dataDir, func(c *Config) {
		c.Logger = slog.New(slog.NewTextHandler(&logged, nil))
	})
	configured := filepath.Join(dataDir, "configured")
	configPath := filepath.Join(t.TempDir(), "waxflow.json")
	if err := os.WriteFile(configPath, []byte(fmt.Sprintf(`{"roots":[{"name":"configured","path":%q}]}`, configured)), 0o644); err != nil {
		t.Fatal(err)
	}
	sidecar, srv := newFakeSidecar(t, configPath, "")
	sidecar.away.Store(false)
	bridge, err := flow.New(ctx, flow.Config{
		BaseURL:    srv.URL,
		APIKey:     "key",
		Roots:      []flow.Root{{Name: "configured", Path: configured}},
		ConfigPath: configPath,
		Tokens:     auth.NewMediaTokens([]byte("test-secret-test-secret-test-sec"), 0),
		Resolver:   svc,
	})
	if err != nil {
		t.Fatal(err)
	}
	svc.FollowEngine(ctx, bridge)
	if err := bridge.Connect(ctx); err != nil {
		t.Fatal(err)
	}
	later := filepath.Join(t.TempDir(), "later")
	if info, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "later", Path: later, AllowAbsent: true}); err != nil || info.StreamingWarning == "" {
		t.Fatalf("an absent folder: %+v %v, want the sidecar's refusal", info, err)
	}
	waitFor(t, func() bool {
		running, err := svc.catalogJobRunning(ctx)
		return err == nil && !running
	}, "the create's scan to end")
	if !svc.flowRefusedAt("later", later) {
		t.Fatal("the missing folder's refusal was not remembered")
	}

	sidecar.away.Store(true)
	if bridge.Connect(ctx) == nil {
		t.Fatal("an engine that is away answered")
	}
	const warned = "the streaming sidecar did not take a library's root"
	warns := strings.Count(logged.String(), warned)
	if err := os.Mkdir(later, 0o755); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Rescan(ctx, false); err != nil {
		t.Fatal(err)
	}
	waitFor(t, func() bool { return !svc.flowRefusedAt("later", later) }, "the old refusal forgotten once the folder is back")
	talks := t.TempDir()
	if info, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "talks", Path: talks}); err != nil ||
		!strings.Contains(info.StreamingWarning, "when the streaming engine answers again") {
		t.Fatalf("a library created while the engine is away: %+v %v, want it to wait for the engine", info, err)
	}
	waitFor(t, func() bool {
		running, err := svc.catalogJobRunning(ctx)
		return err == nil && !running
	}, "the second create's scan to end")
	svc.flowSyncMu.Lock()
	refused := len(svc.flowRefused)
	svc.flowSyncMu.Unlock()
	if refused != 0 {
		t.Errorf("%d roots remembered as refused while the engine was away, want none", refused)
	}
	if n := strings.Count(logged.String(), warned); n != warns {
		t.Errorf("%d refusals warned of while the engine was away, want none", n-warns)
	}
	if got := sidecarConfigNames(t, configPath); !slices.Equal(got, []string{"configured"}) {
		t.Errorf("the config lists %v while the engine is away, want no unchecked root", got)
	}

	reloads := func() int {
		sidecar.mu.Lock()
		defer sidecar.mu.Unlock()
		return len(sidecar.reloads)
	}
	before := reloads()
	sidecar.away.Store(false)
	if err := bridge.Connect(ctx); err != nil {
		t.Fatal(err)
	}
	waitFor(t, func() bool {
		names := bridge.RootNames()
		return slices.Contains(names, "later") && slices.Contains(names, "talks")
	}, "both offered and taken at the engine's answer")
	svc.flowSyncMu.Lock()
	svc.flowSyncMu.Unlock()
	if n := reloads() - before; n != 2 {
		t.Errorf("the answer reloaded %d times, want one offer of each", n)
	}
}
