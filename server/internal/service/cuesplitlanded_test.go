package service

import (
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
)

// A CUE split waiting on a piece that did not land, whose landed piece is
// moved (as organize or a health fix moves it) or deleted by its owner in
// the wait, imports no piece twice: the rerun asks the engine for nothing
// more, imports only the piece still missing, and retires the rip.
func TestACueSplitNeverImportsALandedPieceAgain(t *testing.T) {
	t.Parallel()
	for _, what := range []string{"moved", "deleted"} {
		t.Run(what, func(t *testing.T) {
			t.Parallel()
			ctx, svc, uc, one, _, engine := cueSplitFixture(t)
			task, err := svc.StartCueSplit(ctx, uc, one, false)
			if err != nil {
				t.Fatal(err)
			}
			var blocker string
			svc.toolStepHook = func(step string) error {
				if step != "importing" {
					return nil
				}
				blocker = taskParams(t, ctx, svc, task.ID).PieceDests[1]
				if err := os.MkdirAll(filepath.Dir(blocker), 0o755); err != nil {
					t.Error(err)
				}
				if err := os.WriteFile(blocker, []byte("not a piece"), 0o644); err != nil {
					t.Error(err)
				}
				return nil
			}
			var wait *toolRetry
			if err := attempt(t, ctx, svc, 1); !errors.As(err, &wait) {
				t.Fatalf("first attempt = %v, want it waiting on the piece that failed", err)
			}
			svc.toolStepHook = nil
			if err := os.Remove(blocker); err != nil {
				t.Fatal(err)
			}
			landed := tracksTitled(t, ctx, svc, "Rip One", false)
			if len(landed) != 1 {
				t.Fatalf("real Rip One tracks = %v, want the piece that landed", landed)
			}
			switch what {
			case "moved":
				dest := taskParams(t, ctx, svc, task.ID).PieceDests[0]
				moved := filepath.Join(filepath.Dir(filepath.Dir(dest)), "Moved", filepath.Base(dest))
				if err := os.MkdirAll(filepath.Dir(moved), 0o755); err != nil {
					t.Fatal(err)
				}
				if err := os.Rename(dest, moved); err != nil {
					t.Fatal(err)
				}
				if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
					t.Fatal(err)
				}
			default:
				it, err := svc.lib.Get(ctx, landed[0])
				if err != nil {
					t.Fatal(err)
				}
				trashAs(t, ctx, svc, "user", it.FilePID)
			}
			if err := attempt(t, ctx, svc, 2); err != nil {
				t.Fatalf("the rerun = %v, want it finished", err)
			}
			if engine.made() != 1 {
				t.Errorf("engine jobs = %d, want the one cut", engine.made())
			}
			want := landed
			if what == "deleted" {
				want = nil
			}
			if got := tracksTitled(t, ctx, svc, "Rip One", false); !slices.Equal(got, want) {
				t.Errorf("real Rip One tracks = %v, want %v: the piece that landed, and no second import of it", got, want)
			}
			if got := tracksTitled(t, ctx, svc, "Rip Two", false); len(got) != 1 {
				t.Errorf("real Rip Two tracks = %v, want the piece that waited, imported", got)
			}
			if trash := activeTrash(t, ctx, svc); !slices.Contains(trash, taskTypeCueSplit) {
				t.Errorf("trash = %q, want the rip retired", trash)
			}
		})
	}
}

// A split whose every missing piece the import refuses for good, a place
// another file holds, ends at once rather than wait out what cannot
// pass: a second split of a rip whose first kept it finds every place
// taken by the first's tracks, and stops naming them, the rip kept.
func TestACueSplitWhosePiecesCannotLandEndsAtOnce(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, one, _, _ := cueSplitFixture(t)
	first, err := svc.StartCueSplit(ctx, uc, one, true)
	if err != nil {
		t.Fatal(err)
	}
	if err := attempt(t, ctx, svc, 1); err != nil {
		t.Fatalf("the first split = %v, want it finished", err)
	}
	if got := toolTask(t, ctx, svc, first.ID); got.State != taskStateDone {
		t.Fatalf("the first split = %s (error %q), want it done", got.State, got.Error)
	}
	second, err := svc.StartCueSplit(ctx, uc, one, false)
	if err != nil {
		t.Fatal(err)
	}
	if !drainAt(ctx, svc, 2) {
		t.Fatal("the worker found no task")
	}
	if got := toolTask(t, ctx, svc, second.ID); got.State != taskStateFailed ||
		!strings.Contains(got.Error, "destination already exists") || !strings.Contains(got.Error, "01 - Rip One") {
		t.Fatalf("the second split = %s (error %q, waiting %q), want it ended at once, naming the places taken",
			got.State, got.Error, got.WaitReason)
	}
	for _, title := range []string{"Rip One", "Rip Two"} {
		if got := tracksTitled(t, ctx, svc, title, false); len(got) != 1 {
			t.Errorf("real %s tracks = %v, want the first split's alone", title, got)
		}
		if got := tracksTitled(t, ctx, svc, title, true); len(got) != 1 {
			t.Errorf("carved %s tracks = %v, want the rip kept", title, got)
		}
	}
	if trash := activeTrash(t, ctx, svc); len(trash) != 0 {
		t.Errorf("trash = %q, want the rip kept", trash)
	}
}

// A CUE split whose pieces the import holds back because the library they
// go to is flagged read-only waits the flag out, as any refusal that
// clears on its own, with two managed libraries as with one: the import
// then quarantines each piece rather than refuse the plan.
func TestACueSplitWaitsOutAReadOnlyTargetAmongManagedLibraries(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, one, _, _ := cueSplitFixtureWith(t, func(c *Config) {
		c.Roots = append(c.Roots, Root{Name: "books", Path: t.TempDir(), Managed: true, Media: "audiobook"})
	})
	task, err := svc.StartCueSplit(ctx, uc, one, false)
	if err != nil {
		t.Fatal(err)
	}
	libs, err := svc.lib.Libraries(ctx)
	if err != nil {
		t.Fatal(err)
	}
	var tracksLib model.PID
	for _, lib := range libs {
		if lib.MediaType() != model.MediaAudiobook {
			tracksLib = lib.PID
		}
	}
	setReadOnly := func(on bool) {
		if _, err := svc.lib.SetLibraryReadOnly(ctx, tracksLib, on); err != nil {
			t.Fatal(err)
		}
		svc.refreshLibraryState(ctx)
	}
	// Flagged once the pieces are cut, before the import plans them.
	svc.toolStepHook = func(step string) error {
		if step == "staged" {
			setReadOnly(true)
		}
		return nil
	}
	err = attempt(t, ctx, svc, 1)
	svc.toolStepHook = nil
	var wait *toolRetry
	if !errors.As(err, &wait) || wait.reason != "read-only" {
		t.Fatalf("first attempt = %v, want it waiting on the read-only library", err)
	}
	setReadOnly(false)
	if err := attempt(t, ctx, svc, 2); err != nil {
		t.Fatalf("the rerun once the flag went = %v, want it finished", err)
	}
	if got := toolTask(t, ctx, svc, task.ID); got.State != taskStateDone {
		t.Fatalf("task = %s (error %q), want it done", got.State, got.Error)
	}
}
