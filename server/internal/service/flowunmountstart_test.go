package service

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"testing"

	"github.com/colespringer/waxbin"

	"github.com/colespringer/waxdeck/server/internal/auth"
	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
)

// A library the CLI removed while the server was stopped leaves the
// sidecar's config file at the next start through the real bridge, before
// the engine first answers (every compose start): the start maps only the
// catalog's roots, so the bridge never held the removed one, yet the file
// the sidecar boots from must stop naming a folder that may be gone. The
// engine's first answer reloads the file without it, once.
func TestALibraryRemovedWhileDownLeavesTheSidecarConfigBeforeTheEngineAnswers(t *testing.T) {
	t.Parallel()
	dataDir, booksDir := t.TempDir(), t.TempDir()
	ctx, svc, uc, stop := openServiceAt(t, dataDir, nil)
	lib, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "books", Path: booksDir})
	if err != nil {
		t.Fatal(err)
	}
	waitFor(t, func() bool {
		running, err := svc.catalogJobRunning(ctx)
		return err == nil && !running
	}, "the create's scan to end")
	stop()
	_, bare, _ := parseAPIPID(lib.PID)
	whileDown(t, dataDir, func(ctx context.Context, cli *waxbin.Library) {
		if _, err := cli.RemoveRoot(ctx, bare, waxbin.RemoveRootOptions{}); err != nil {
			t.Fatal(err)
		}
	})

	ctx, svc, _, _ = openServiceAt(t, dataDir, nil)
	configured := filepath.Join(dataDir, "configured")
	configPath := filepath.Join(t.TempDir(), "waxflow.json")
	config := fmt.Sprintf(`{"roots":[{"name":"configured","path":%q},{"name":"books","path":%q}]}`, configured, booksDir)
	if err := os.WriteFile(configPath, []byte(config), 0o644); err != nil {
		t.Fatal(err)
	}
	sidecar, srv := newFakeSidecar(t, configPath, "")
	// The bridge's starting roots, as main seeds them.
	var table []flow.Root
	for _, r := range svc.RootTable() {
		table = append(table, flow.Root{Name: r.Name, Path: r.Path})
	}
	bridge, err := flow.New(ctx, flow.Config{
		BaseURL:    srv.URL,
		APIKey:     "key",
		Roots:      flow.SeedRoots([]flow.Root{{Name: "configured", Path: configured}}, table, configPath),
		ConfigPath: configPath,
		Tokens:     auth.NewMediaTokens([]byte("test-secret-test-secret-test-sec"), 0),
		Resolver:   svc,
	})
	if err != nil {
		t.Fatal(err)
	}
	if names := bridge.RootNames(); slices.Contains(names, "books") {
		t.Fatalf("the start maps %v, want the removed library left out", names)
	}
	svc.FollowEngine(ctx, bridge)
	waitFor(t, func() bool { return len(owedUnmounts(t, ctx, svc)) == 0 }, "the owed unmount taken by the wired bridge")
	if names := sidecarConfigNames(t, configPath); !slices.Equal(names, []string{"configured"}) {
		t.Fatalf("the config lists %v before the engine answered, want the removed library gone", names)
	}

	sidecar.away.Store(false)
	if err := bridge.Connect(ctx); err != nil {
		t.Fatal(err)
	}
	sidecar.mu.Lock()
	reloads := slices.Clone(sidecar.reloads)
	sidecar.mu.Unlock()
	if len(reloads) != 1 || !slices.Equal(reloads[0], []string{"configured"}) {
		t.Fatalf("reloads at the engine's first answer = %v, want one, without books", reloads)
	}
}
