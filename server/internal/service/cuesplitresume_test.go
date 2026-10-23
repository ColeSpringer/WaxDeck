package service

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"

	"github.com/colespringer/waxdeck/fixtures"
)

// cueSplitFixture is a managed library holding a two-track rip and its
// sheet, and an engine whose jobs finish at once. It answers the first
// carved track's pid, the rip's folder and the engine.
func cueSplitFixture(t *testing.T) (context.Context, *Library, *UserCtx, string, string, *fakeBookEngine) {
	t.Helper()
	return cueSplitFixtureWith(t, nil)
}

// cueSplitFixtureWith is cueSplitFixture with its configuration adjusted
// by mutate first.
func cueSplitFixtureWith(t *testing.T, mutate func(*Config)) (context.Context, *Library, *UserCtx, string, string, *fakeBookEngine) {
	t.Helper()
	var root string
	ctx, svc, uc := openEnrichFixture(t, func(c *Config) {
		c.Roots[0].Managed = true
		root = c.Roots[0].Path
		if mutate != nil {
			mutate(c)
		}
	})
	ripDir := filepath.Join(root, "Rip Artist", "Rip Album")
	if _, err := fixtures.Generate(ripDir, fixtures.Spec{
		Name: "Rip Album", Codec: fixtures.CodecFLAC, Duration: 6 * time.Second, SampleRate: 44100,
		Tags: map[string]string{"ALBUM": "Rip Album", "ARTIST": "Rip Artist", "ALBUMARTIST": "Rip Artist"},
	}); err != nil {
		t.Fatal(err)
	}
	sheet := "PERFORMER \"Rip Artist\"\nTITLE \"Rip Album\"\nFILE \"Rip Album.flac\" WAVE\n" +
		"  TRACK 01 AUDIO\n    TITLE \"Rip One\"\n    INDEX 01 00:00:00\n" +
		"  TRACK 02 AUDIO\n    TITLE \"Rip Two\"\n    INDEX 01 00:03:00\n"
	if err := os.WriteFile(filepath.Join(ripDir, "Rip Album.cue"), []byte(sheet), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	one := tracksTitled(t, ctx, svc, "Rip One", true)
	if len(one) != 1 {
		t.Fatalf("carved tracks titled Rip One = %v, want one", one)
	}
	engine := newFakeBookEngine(t)
	svc.SetFlowJobs(engine)
	return ctx, svc, uc, apiPID(PrefixTrack, one[0]), ripDir, engine
}

// tracksTitled are the library's tracks titled title, carved ones when
// virtual, real ones otherwise; the trash's are left out.
func tracksTitled(t *testing.T, ctx context.Context, svc *Library, title string, virtual bool) []model.PID {
	t.Helper()
	items, err := svc.lib.Query(ctx, query.New(query.EntityItems).Where("title", query.OpIs, title).Build(), "")
	if err != nil {
		t.Fatal(err)
	}
	var out []model.PID
	for _, it := range items {
		if it.Kind == model.KindTrack && it.Virtual == virtual && it.State == model.StatePresent {
			out = append(out, it.PID)
		}
	}
	return out
}

// A CUE split stopped after any of its steps, as a crash or a restart
// stops it, finishes when the task runs again with one real track per
// carved one: no piece is imported twice, the rip goes to the trash once,
// and the engine is not asked again once the pieces are cut.
func TestACueSplitStoppedAfterAnyStepFinishesWithoutDuplicates(t *testing.T) {
	t.Parallel()
	for _, step := range []string{"staged", "importing", "import", "imported", "trashing", "trashed", "audited"} {
		t.Run(step, func(t *testing.T) {
			t.Parallel()
			ctx, svc, uc, one, ripDir, engine := cueSplitFixture(t)
			task, err := svc.StartCueSplit(ctx, uc, one, false)
			if err != nil {
				t.Fatal(err)
			}
			svc.toolStepHook = stopAt(step, nil)
			if err := attempt(t, ctx, svc, 1); !errors.Is(err, errStopped) {
				t.Fatalf("first attempt = %v, want it stopped after %s", err, step)
			}
			svc.toolStepHook = nil
			if err := attempt(t, ctx, svc, 2); err != nil {
				t.Fatalf("the rerun = %v, want it finished", err)
			}
			done := toolTask(t, ctx, svc, task.ID)
			if done.State != taskStateDone || len(done.ResultPIDs) != 2 {
				t.Fatalf("task = %s (error %q), results %v; want it done with two tracks", done.State, done.Error, done.ResultPIDs)
			}
			for _, title := range []string{"Rip One", "Rip Two"} {
				if got := tracksTitled(t, ctx, svc, title, false); len(got) != 1 {
					t.Errorf("real tracks titled %s = %v, want one", title, got)
				}
				if got := tracksTitled(t, ctx, svc, title, true); len(got) != 0 {
					t.Errorf("carved tracks titled %s = %v, want them gone with the rip", title, got)
				}
			}
			if trash := activeTrash(t, ctx, svc); !slices.Equal(trash, []string{taskTypeCueSplit}) {
				t.Errorf("trash = %q, want the rip once under cue-split", trash)
			}
			if _, err := os.Stat(filepath.Join(ripDir, "Rip Album.cue")); !os.IsNotExist(err) {
				t.Errorf("the sheet is still there: %v", err)
			}
			if audits := auditDetails(t, ctx, svc, "item.split-cue"); len(audits) != 1 {
				t.Errorf("item.split-cue audits = %v, want one", audits)
			}
			if engine.made() != 1 {
				t.Errorf("engine jobs = %d, want the one", engine.made())
			}
		})
	}
}

// A second CUE split of a rip one is still at work on is refused when it
// is queued, from any track of the rip.
func TestASecondCueSplitOfARipIsRefusedWhileTheFirstIsLive(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, one, _, _ := cueSplitFixture(t)
	first, err := svc.StartCueSplit(ctx, uc, one, false)
	if err != nil {
		t.Fatal(err)
	}
	two := tracksTitled(t, ctx, svc, "Rip Two", true)
	_, err = svc.StartCueSplit(ctx, uc, apiPID(PrefixTrack, two[0]), false)
	if p := RefusalParams(err); KindOf(err) != KindConflict || p["reason"] != refusalTaskRunning || p["task"] != first.ID {
		t.Fatalf("a second split of the rip = %v (params %v), want it refused naming %s", err, p, first.ID)
	}
}

// A busy catalog at the CUE split's import is waited out, the cut pieces
// kept, and the next attempt imports them once.
func TestABusyCatalogAtTheCueImportIsWaitedOut(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, one, _, engine := cueSplitFixture(t)
	task, err := svc.StartCueSplit(ctx, uc, one, false)
	if err != nil {
		t.Fatal(err)
	}
	svc.mutateHook = busyOnce("import")
	err = attempt(t, ctx, svc, 1)
	var wait *toolRetry
	if !errors.As(err, &wait) {
		t.Fatalf("first attempt = %v, want it waiting on the busy catalog", err)
	}
	if err := attempt(t, ctx, svc, 2); err != nil {
		t.Fatalf("the rerun = %v, want it finished", err)
	}
	if done := toolTask(t, ctx, svc, task.ID); done.State != taskStateDone {
		t.Fatalf("task = %s (error %q), want it done", done.State, done.Error)
	}
	for _, title := range []string{"Rip One", "Rip Two"} {
		if got := tracksTitled(t, ctx, svc, title, false); len(got) != 1 {
			t.Errorf("real tracks titled %s = %v, want one", title, got)
		}
	}
	if engine.made() != 1 {
		t.Errorf("engine jobs = %d, want the one", engine.made())
	}
}

// A CUE split some of whose pieces did not become tracks keeps the rip,
// keeps the pieces that did, and says which did not; once the cause is
// gone, a rerun imports the rest and only then retires the rip.
func TestACueSplitWithAPieceThatFailedKeepsTheRip(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, one, _, _ := cueSplitFixture(t)
	task, err := svc.StartCueSplit(ctx, uc, one, false)
	if err != nil {
		t.Fatal(err)
	}
	var blocker string
	svc.toolStepHook = func(step string) error {
		if step != "importing" {
			return nil
		}
		// Another's file takes the second piece's place before the import.
		blocker = taskParams(t, ctx, svc, task.ID).PieceDests[1]
		if err := os.MkdirAll(filepath.Dir(blocker), 0o755); err != nil {
			t.Error(err)
		}
		if err := os.WriteFile(blocker, []byte("not a piece"), 0o644); err != nil {
			t.Error(err)
		}
		return nil
	}
	err = attempt(t, ctx, svc, 1)
	var wait *toolRetry
	if !errors.As(err, &wait) || !strings.Contains(err.Error(), "1 of 2 pieces did not become tracks") || !strings.Contains(err.Error(), "02 - Rip Two") {
		t.Fatalf("first attempt = %v, want it waiting, naming the piece that failed", err)
	}
	if got := tracksTitled(t, ctx, svc, "Rip One", false); len(got) != 1 {
		t.Errorf("real tracks titled Rip One = %v, want the piece that landed kept", got)
	}
	if got := tracksTitled(t, ctx, svc, "Rip Two", true); len(got) != 1 {
		t.Errorf("carved tracks titled Rip Two = %v, want the rip still carving it", got)
	}
	if trash := activeTrash(t, ctx, svc); len(trash) != 0 {
		t.Fatalf("trash = %q, want the rip kept", trash)
	}
	svc.toolStepHook = nil
	if err := os.Remove(blocker); err != nil {
		t.Fatal(err)
	}
	if err := attempt(t, ctx, svc, 2); err != nil {
		t.Fatalf("the rerun = %v, want it finished", err)
	}
	for _, title := range []string{"Rip One", "Rip Two"} {
		if got := tracksTitled(t, ctx, svc, title, false); len(got) != 1 {
			t.Errorf("real tracks titled %s = %v, want one", title, got)
		}
	}
	if trash := activeTrash(t, ctx, svc); !slices.Equal(trash, []string{taskTypeCueSplit}) {
		t.Errorf("trash = %q, want the rip once every piece is a track", trash)
	}
}

// A read-only flag at the rip's trash is waited out, as the book tools
// wait it out.
func TestACueSplitWaitsOutAReadOnlyRip(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, one, _, _ := cueSplitFixture(t)
	task, err := svc.StartCueSplit(ctx, uc, one, false)
	if err != nil {
		t.Fatal(err)
	}
	svc.toolStepHook = stopAt("trashing", nil)
	if err := attempt(t, ctx, svc, 1); !errors.Is(err, errStopped) {
		t.Fatalf("first attempt = %v, want it stopped at the rip's trash", err)
	}
	svc.toolStepHook = nil
	flagReadOnly(t, ctx, svc, true)
	err = attempt(t, ctx, svc, 2)
	var wait *toolRetry
	if !errors.As(err, &wait) {
		t.Fatalf("the rerun on a read-only library = %v, want it waiting", err)
	}
	flagReadOnly(t, ctx, svc, false)
	if err := attempt(t, ctx, svc, 3); err != nil {
		t.Fatalf("the rerun once the flag went = %v, want it finished", err)
	}
	if done := toolTask(t, ctx, svc, task.ID); done.State != taskStateDone {
		t.Fatalf("task = %s (error %q), want it done", done.State, done.Error)
	}
}

// A rip somebody deleted after its pieces became tracks leaves the split
// nothing to carry or retire: it finishes rather than wait on the rip.
func TestACueSplitWhoseRipWasDeletedSinceFinishes(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, one, _, _ := cueSplitFixture(t)
	task, err := svc.StartCueSplit(ctx, uc, one, false)
	if err != nil {
		t.Fatal(err)
	}
	svc.toolStepHook = stopAt("imported", nil)
	if err := attempt(t, ctx, svc, 1); !errors.Is(err, errStopped) {
		t.Fatalf("first attempt = %v, want it stopped once imported", err)
	}
	svc.toolStepHook = nil
	carved := append(tracksTitled(t, ctx, svc, "Rip One", true), tracksTitled(t, ctx, svc, "Rip Two", true)...)
	pids := make([]string, len(carved))
	for i, pid := range carved {
		pids[i] = apiPID(PrefixTrack, pid)
	}
	if _, err := svc.DeleteItems(ctx, uc, pids, "trash", false); err != nil {
		t.Fatal(err)
	}
	if err := attempt(t, ctx, svc, 2); err != nil {
		t.Fatalf("the rerun = %v, want it finished", err)
	}
	if done := toolTask(t, ctx, svc, task.ID); done.State != taskStateDone || len(done.ResultPIDs) != 2 {
		t.Fatalf("task = %s (error %q), results %v; want it done with its two tracks", done.State, done.Error, done.ResultPIDs)
	}
}

// A CUE split parked after its rip went to the trash says so, and where
// the tracks it made are, for whoever clears it; nothing more comes of
// its workspace.
func TestACueSplitParkedAfterItsRipTrashSaysWhereEverythingIs(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, one, _, _ := cueSplitFixture(t)
	task, err := svc.StartCueSplit(ctx, uc, one, false)
	if err != nil {
		t.Fatal(err)
	}
	svc.toolStepHook = stopAt("trashed", nil)
	if err := attempt(t, ctx, svc, 1); !errors.Is(err, errStopped) {
		t.Fatalf("first attempt = %v, want it stopped once the rip is in the trash", err)
	}
	svc.toolStepHook = nil
	setParams(t, ctx, svc, task.ID, func(p *toolTaskParams) { p.RunsStarted, p.RunsEnded = 4, 1 })
	if !drainAt(ctx, svc, 2) {
		t.Fatal("the worker found no task")
	}
	parked := toolTask(t, ctx, svc, task.ID)
	folder := filepath.Base(filepath.Dir(taskParams(t, ctx, svc, task.ID).PieceDests[0]))
	if parked.State != taskStateParked || !strings.Contains(parked.Error, "the rip went to the trash") ||
		strings.Contains(parked.Error, "the rip stays") || !strings.Contains(parked.Error, folder) {
		t.Fatalf("task = %s (error %q), want it parked, the rip said to be in the trash and the tracks in %s", parked.State, parked.Error, folder)
	}
	if _, err := os.Stat(filepath.Join(svc.stagingDir, "tools", task.ID)); !os.IsNotExist(err) {
		t.Errorf("the parked split's workspace = %v, want it gone", err)
	}
}
