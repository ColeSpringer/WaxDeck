package service

import (
	"context"
	"errors"
	"log/slog"
	"maps"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"testing"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/config"
	"github.com/colespringer/waxbin/model"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

func (f *fakeFlowRoots) removedNames() []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	return slices.Clone(f.removed)
}

// owedUnmounts lists the removed libraries' roots the bridge has still to
// let go of.
func owedUnmounts(t *testing.T, ctx context.Context, svc *Library) []string {
	t.Helper()
	owed, err := svc.db.SettingsWithPrefix(ctx, flowUnmountKey)
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	for key := range owed {
		names = append(names, strings.TrimPrefix(key, flowUnmountKey))
	}
	slices.Sort(names)
	return names
}

// whileDown works on the catalog as the CLI does with the server stopped.
func whileDown(t *testing.T, dataDir string, fn func(context.Context, *waxbin.Library)) {
	t.Helper()
	ctx := context.Background()
	cli, err := waxbin.Open(ctx, waxbin.Options{DBPath: filepath.Join(dataDir, "waxbin.db"), Logger: slog.New(slog.DiscardHandler)})
	if err != nil {
		t.Fatal(err)
	}
	fn(ctx, cli)
	if err := cli.Close(); err != nil {
		t.Fatal(err)
	}
}

// grantsOf is what the account and the invite are granted.
func grantsOf(t *testing.T, ctx context.Context, svc *Library, userID, inviteID string) ([]string, []string) {
	t.Helper()
	acct, err := svc.Account(ctx, userID)
	if err != nil {
		t.Fatal(err)
	}
	invites, err := svc.Invites(ctx)
	if err != nil {
		t.Fatal(err)
	}
	for _, iv := range invites {
		if iv.ID == inviteID {
			return acct.LibraryPIDs, iv.LibraryPIDs
		}
	}
	t.Fatalf("no invite %s", inviteID)
	return nil, nil
}

// A removal settled at the next start, before the bridge is wired, takes
// the library's mount off the bridge once it is wired; a later start owes
// it nothing.
func TestARemovalSettledAtStartUnmountsOnceTheBridgeIsWired(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	var logged lockedBuffer
	ctx, svc, uc, stop := openServiceAt(t, dataDir, func(c *Config) {
		c.Logger = slog.New(slog.NewTextHandler(&logged, nil))
	})
	lib, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "books", Path: t.TempDir()})
	if err != nil {
		t.Fatal(err)
	}
	memberCtx(t, ctx, svc, "member", lib.PID)
	if _, err := svc.db.Writer().ExecContext(ctx, `CREATE TRIGGER refuse_prune BEFORE DELETE ON library_grants
		BEGIN SELECT RAISE(ABORT, 'refused'); END`); err != nil {
		t.Fatal(err)
	}
	waitFor(t, func() bool {
		_, err = svc.RemoveLibrary(ctx, uc, lib.PID)
		return err == nil
	}, "the removal to start once the create's scan ends")
	waitFor(t, func() bool { return strings.Contains(logged.String(), "following up a library's removal") },
		"the follow-up to fail")
	if _, err := svc.db.Writer().ExecContext(ctx, `DROP TRIGGER refuse_prune`); err != nil {
		t.Fatal(err)
	}
	stop()

	ctx, svc, _, stop = openServiceAt(t, dataDir, nil)
	waitFor(t, func() bool { return removalAudit(t, ctx, svc, lib.PID) != nil }, "the follow-up at the next start")
	flow := &fakeFlowRoots{names: []string{"configured", "books"}}
	svc.SetFlowRoots(flow)
	waitFor(t, func() bool { return slices.Equal(flow.removedNames(), []string{"books"}) },
		"the bridge to let go of books once wired")
	stop()

	_, svc, _, _ = openServiceAt(t, dataDir, nil)
	again := &fakeFlowRoots{}
	svc.SetFlowRoots(again)
	waitFor(t, func() bool { return again.taught("configured", filepath.Join(dataDir, "configured")) },
		"the next start's bridge synced")
	if removed := again.removedNames(); len(removed) != 0 {
		t.Errorf("the next start's bridge was asked to let go of %v, want nothing owed", removed)
	}
}

// A mount the sidecar kept at the removal is owed: the bridge is asked
// again at its next sync, and once it lets go, never again.
func TestAMountTheSidecarKeptIsTakenOffAtTheNextSync(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	ctx, svc, uc, _ := openServiceAt(t, dataDir, nil)
	flow := &fakeFlowRoots{names: []string{"configured"}, removeErr: errors.New("the reload was refused")}
	svc.SetFlowRoots(flow)
	lib, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "books", Path: t.TempDir()})
	if err != nil {
		t.Fatal(err)
	}
	waitFor(t, func() bool {
		_, err = svc.RemoveLibrary(ctx, uc, lib.PID)
		return err == nil
	}, "the removal to start once the create's scan ends")
	waitFor(t, func() bool { return removalAudit(t, ctx, svc, lib.PID) != nil }, "the removal audited")
	if w, _ := removalAudit(t, ctx, svc, lib.PID).Detail["streamingWarning"].(string); !strings.Contains(w, "the reload was refused") {
		t.Errorf("streaming warning = %q, want the sidecar's refusal", w)
	}

	// What the bridge is asked from here on, by the next sync and any the
	// removal's own table change started.
	configured := filepath.Join(dataDir, "configured")
	resync := func() []string {
		flow.mu.Lock()
		flow.removeErr, flow.names, flow.synced, flow.removed = nil, nil, nil, nil
		flow.mu.Unlock()
		svc.SetFlowRoots(flow)
		waitFor(t, func() bool { return flow.taught("configured", configured) }, "the bridge synced")
		return flow.removedNames()
	}
	if removed := resync(); !slices.Equal(removed, []string{"books"}) {
		t.Errorf("the bridge was asked to let go of %v, want books again at its next sync", removed)
	}
	if removed := resync(); len(removed) != 0 {
		t.Errorf("the bridge was asked to let go of %v, want nothing more once it had", removed)
	}
}

// A server with no streaming engine has no sidecar config to edit: a
// removal there owes the bridge nothing, what was owed before it said so
// is let go, and a bridge wired at a later start is asked nothing.
func TestAServerWithNoEngineOwesTheBridgeNothing(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	ctx, svc, uc, stop := openServiceAt(t, dataDir, nil)
	remove := func(name string) {
		lib, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: name, Path: t.TempDir()})
		if err != nil {
			t.Fatal(err)
		}
		waitFor(t, func() bool {
			_, err = svc.RemoveLibrary(ctx, uc, lib.PID)
			return err == nil
		}, "the removal to start once the create's scan ends")
		waitFor(t, func() bool { return removalAudit(t, ctx, svc, lib.PID) != nil }, "the removal audited")
	}
	remove("books")
	if owed := owedUnmounts(t, ctx, svc); !slices.Equal(owed, []string{"books"}) {
		t.Fatalf("owed before the server said it has no engine = %v, want books", owed)
	}
	svc.SetFlowRoots(nil)
	waitFor(t, func() bool { return len(owedUnmounts(t, ctx, svc)) == 0 }, "the owed unmount let go")
	remove("tapes")
	if owed := owedUnmounts(t, ctx, svc); len(owed) != 0 {
		t.Errorf("owed on a server with no engine = %v, want nothing", owed)
	}
	stop()

	_, svc, _, _ = openServiceAt(t, dataDir, nil)
	flow := &fakeFlowRoots{}
	svc.SetFlowRoots(flow)
	waitFor(t, func() bool { return flow.taught("configured", filepath.Join(dataDir, "configured")) }, "the bridge synced")
	if removed := flow.removedNames(); len(removed) != 0 {
		t.Errorf("a bridge wired later was asked to let go of %v, want nothing", removed)
	}
}

// A library removed while the server was down leaves nothing behind at
// the next start: its stored name and the grants naming it go, its mount
// is taken off once the bridge is wired, and one line says so. Nobody is
// recorded as having removed it.
func TestALibraryRemovedWhileTheServerWasDownIsCleanedAtStart(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	ctx, svc, uc, stop := openServiceAt(t, dataDir, nil)
	lib, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "books", Path: t.TempDir()})
	if err != nil {
		t.Fatal(err)
	}
	member := memberCtx(t, ctx, svc, "member", lib.PID)
	invite, err := svc.CreateInvite(ctx, uc, InviteCreate{AccessMode: "granted", LibraryPIDs: []string{lib.PID}})
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

	var logged lockedBuffer
	ctx, svc, _, _ = openServiceAt(t, dataDir, func(c *Config) {
		c.Logger = slog.New(slog.NewTextHandler(&logged, nil))
	})
	if stored, err := svc.db.LibraryRootsList(ctx); err != nil || slices.ContainsFunc(stored, func(r wdb.LibraryRoot) bool { return r.Name == "books" }) {
		t.Errorf("stored names = %+v (%v), want books' gone", stored, err)
	}
	if acct, iv := grantsOf(t, ctx, svc, member.ID, invite.ID); len(acct) != 0 || len(iv) != 0 {
		t.Errorf("grants: the member's %v, the invite's %v, want none", acct, iv)
	}
	if lines := strings.Count(logged.String(), "cleaned up after a library the catalog no longer holds"); lines != 1 ||
		!strings.Contains(logged.String(), "library=books") {
		t.Errorf("cleanup lines = %d in %q, want one naming books", lines, logged.String())
	}
	if audit := removalAudit(t, ctx, svc, lib.PID); audit != nil {
		t.Errorf("audit = %+v, want none for a removal this server did not start", audit)
	}
	flow := &fakeFlowRoots{names: []string{"configured", "books"}}
	svc.SetFlowRoots(flow)
	waitFor(t, func() bool { return slices.Equal(flow.removedNames(), []string{"books"}) },
		"the bridge to let go of books once wired")
}

// A folder added again while the server was down is the newer library's:
// it keeps the folder's name and its mount, and only the removed one's
// grants go.
func TestAStartCleanupLeavesANewerLibraryAtTheFolder(t *testing.T) {
	t.Parallel()
	dataDir, dir := t.TempDir(), t.TempDir()
	ctx, svc, uc, stop := openServiceAt(t, dataDir, nil)
	lib, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "books", Path: dir})
	if err != nil {
		t.Fatal(err)
	}
	member := memberCtx(t, ctx, svc, "member", lib.PID)
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
		if _, err := cli.AddRoot(ctx, config.Root{Path: dir, Mode: model.ModeInPlace}); err != nil {
			t.Fatal(err)
		}
	})

	var logged lockedBuffer
	ctx, svc, _, _ = openServiceAt(t, dataDir, func(c *Config) {
		c.Logger = slog.New(slog.NewTextHandler(&logged, nil))
	})
	newer := libraryAt(t, ctx, svc, dir)
	if newer.PID == lib.PID || newer.Name != "books" {
		t.Errorf("the folder lists %+v, want a newer library named books", newer)
	}
	if acct, err := svc.Account(ctx, member.ID); err != nil || len(acct.LibraryPIDs) != 0 {
		t.Errorf("the member's grants = %v (%v), want the removed library's gone", acct.LibraryPIDs, err)
	}
	if lines := strings.Count(logged.String(), "cleaned up after a library the catalog no longer holds"); lines != 1 {
		t.Errorf("cleanup lines = %d in %q, want one for the removed library", lines, logged.String())
	}
	flow := &fakeFlowRoots{names: []string{"books"}}
	svc.SetFlowRoots(flow)
	waitFor(t, func() bool { return flow.taught("configured", filepath.Join(dataDir, "configured")) }, "the bridge synced")
	if removed := flow.removedNames(); len(removed) != 0 {
		t.Errorf("the bridge was asked to let go of %v, want the newer library's mount kept", removed)
	}
}

// mappingFlowRoots is a bridge that keeps the folder each root name maps
// to, and what it was told, in order; while refuse is set its sidecar
// takes no root.
type mappingFlowRoots struct {
	mu     sync.Mutex
	mapped map[string]string
	told   []string
	refuse bool
}

func (f *mappingFlowRoots) RootNames() []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	return slices.Sorted(maps.Keys(f.mapped))
}

func (f *mappingFlowRoots) SyncRoot(_ context.Context, name, path string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.refuse {
		return errors.New("the sidecar cannot open " + path)
	}
	f.mapped[name] = path
	f.told = append(f.told, "sync "+name+" "+path)
	return nil
}

func (f *mappingFlowRoots) RemoveRoot(_ context.Context, name string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	delete(f.mapped, name)
	f.told = append(f.told, "remove "+name)
	return nil
}

func (f *mappingFlowRoots) state() (map[string]string, []string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return maps.Clone(f.mapped), slices.Clone(f.told)
}

// A library removed while the server was stopped, whose name a newer
// library in another folder goes by now, gives the name's mount up: the
// bridge lets go of the old folder and is taught the newer one, so the
// sidecar maps the new folder only. The newer library is one the CLI
// added or one the configuration names.
func TestANameTakenInAnotherFolderIsMountedThere(t *testing.T) {
	t.Parallel()
	for _, configured := range []bool{false, true} {
		t.Run(map[bool]string{false: "added with the CLI", true: "configured"}[configured], func(t *testing.T) {
			t.Parallel()
			dataDir := t.TempDir()
			oldDir, newDir := filepath.Join(t.TempDir(), "music"), filepath.Join(t.TempDir(), "music")
			for _, dir := range []string{oldDir, newDir} {
				if err := os.Mkdir(dir, 0o755); err != nil {
					t.Fatal(err)
				}
			}
			ctx, svc, uc, stop := openServiceAt(t, dataDir, nil)
			lib, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "music", Path: oldDir})
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
				if configured {
					return
				}
				if _, err := cli.AddRoot(ctx, config.Root{Path: newDir, Mode: model.ModeInPlace}); err != nil {
					t.Fatal(err)
				}
			})

			ctx, svc, _, _ = openServiceAt(t, dataDir, func(c *Config) {
				if configured {
					c.Roots = append(c.Roots, Root{Name: "music", Path: newDir})
				}
			})
			if newer := libraryAt(t, ctx, svc, newDir); newer.Name != "music" {
				t.Fatalf("the newer library = %+v, want it named music", newer)
			}
			flow := &mappingFlowRoots{mapped: map[string]string{"configured": filepath.Join(dataDir, "configured"), "music": oldDir}}
			svc.SetFlowRoots(flow)
			waitFor(t, func() bool {
				mapped, _ := flow.state()
				return mapped["music"] == newDir
			}, "the bridge to map music to the newer library's folder")
			if _, told := flow.state(); !slices.Equal(told, []string{"remove music", "sync music " + newDir}) {
				t.Errorf("the bridge was told %q, want the old mount taken off, then the new one taught", told)
			}
		})
	}
}

// A removal followed up once a newer library in another folder goes by
// its name takes the old mount off all the same, and the newer library is
// taught in its place: with the bridge not wired yet, or wired but never
// holding the name, its sidecar having refused the old folder.
func TestARemovalWhoseNameWasTakenElsewhereMovesTheMount(t *testing.T) {
	t.Parallel()
	for _, wired := range []bool{false, true} {
		t.Run(map[bool]string{false: "the bridge not wired yet", true: "the bridge wired"}[wired], func(t *testing.T) {
			t.Parallel()
			dataDir := t.TempDir()
			ctx, svc, uc, _ := openServiceAt(t, dataDir, nil)
			flow := &mappingFlowRoots{mapped: map[string]string{"configured": filepath.Join(dataDir, "configured")}, refuse: wired}
			if wired {
				svc.SetFlowRoots(flow)
			}
			music, oldDir, rep := takenOut(t, ctx, svc, uc, "music")
			flow.mu.Lock()
			flow.refuse = false
			flow.mu.Unlock()
			svc.refreshLibraryState(ctx)
			newDir := t.TempDir()
			if _, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "music", Path: newDir}); err != nil {
				t.Fatal(err)
			}
			svc.settleJobOrigin(ctx, endedRemoval(t, ctx, svc, uc, music, oldDir, model.JobDone, rep))
			if audit := removalAudit(t, ctx, svc, music.PID); audit == nil {
				t.Fatal("the removal was not followed up")
			}
			if !wired {
				flow.mu.Lock()
				flow.mapped["music"] = oldDir
				flow.mu.Unlock()
				svc.SetFlowRoots(flow)
			}
			waitFor(t, func() bool {
				mapped, told := flow.state()
				return mapped["music"] == newDir && len(told) >= 2 && slices.Equal(told[len(told)-2:], []string{"remove music", "sync music " + newDir})
			}, "the old mount taken off, then the newer library taught")
		})
	}
}

// settingsNaming lists the settings keys that name the library.
func settingsNaming(t *testing.T, ctx context.Context, svc *Library, apiLibraryPID string) []string {
	t.Helper()
	_, bare, _ := parseAPIPID(apiLibraryPID)
	all, err := svc.db.SettingsWithPrefix(ctx, "")
	if err != nil {
		t.Fatal(err)
	}
	var keys []string
	for key := range all {
		if strings.Contains(key, string(bare)) {
			keys = append(keys, key)
		}
	}
	slices.Sort(keys)
	return keys
}

// A removed library's matching settings go with it, whether the console
// removed it or the CLI did while the server was stopped.
func TestARemovedLibrarysMatchingSettingsGo(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	ctx, svc, uc, stop := openServiceAt(t, dataDir, nil)
	var libs []LibraryInfo
	for _, name := range []string{"online", "offline"} {
		lib, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: name, Path: t.TempDir()})
		if err != nil {
			t.Fatal(err)
		}
		if err := svc.SetLibraryMatching(ctx, uc, lib.PID, LibraryMatching{Mode: matchingReview, SinglesAutoApply: true}); err != nil {
			t.Fatal(err)
		}
		libs = append(libs, lib)
	}
	online, offline := libs[0], libs[1]
	if keys := settingsNaming(t, ctx, svc, offline.PID); len(keys) != 2 {
		t.Fatalf("settings naming the library = %v, want its mode and its singles switch", keys)
	}
	waitFor(t, func() bool {
		_, err := svc.RemoveLibrary(ctx, uc, online.PID)
		return err == nil
	}, "the removal to start once the creates' scans end")
	waitFor(t, func() bool { return removalAudit(t, ctx, svc, online.PID) != nil }, "the removal followed up")
	if keys := settingsNaming(t, ctx, svc, online.PID); len(keys) != 0 {
		t.Errorf("settings naming the removed library = %v, want none", keys)
	}
	waitFor(t, func() bool {
		running, err := svc.catalogJobRunning(ctx)
		return err == nil && !running
	}, "the catalog's jobs to end")
	stop()
	_, bare, _ := parseAPIPID(offline.PID)
	whileDown(t, dataDir, func(ctx context.Context, cli *waxbin.Library) {
		if _, err := cli.RemoveRoot(ctx, bare, waxbin.RemoveRootOptions{}); err != nil {
			t.Fatal(err)
		}
	})

	ctx, svc, _, _ = openServiceAt(t, dataDir, nil)
	if keys := settingsNaming(t, ctx, svc, offline.PID); len(keys) != 0 {
		t.Errorf("settings naming the library removed while the server was stopped = %v, want none", keys)
	}
}
