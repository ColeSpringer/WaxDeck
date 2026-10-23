package service

import (
	"context"
	"os"
	"path/filepath"
	"slices"
	"sync"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/organize"

	"github.com/colespringer/waxdeck/fixtures"
)

// readingEngine is a fakeBookEngine that reads the rip and the sheet of
// each split job, as the streaming engine does, and records where.
type readingEngine struct {
	*fakeBookEngine
	mu         sync.Mutex
	srcs, cues []string
}

func (e *readingEngine) CreateSplitJob(ctx context.Context, src string, cuts []int64, cue, format string) (string, error) {
	e.mu.Lock()
	e.srcs, e.cues = append(e.srcs, src), append(e.cues, cue)
	e.mu.Unlock()
	if _, err := os.Stat(src); err != nil {
		return "", err
	}
	return e.fakeBookEngine.CreateSplitJob(ctx, src, cuts, cue, format)
}

// moveRip moves a rip's folder, sheet and all, as someone moving it by
// hand does, and rescans, so the catalog follows the rip there.
func moveRip(t *testing.T, ctx context.Context, svc *Library, from, to string) {
	t.Helper()
	if err := os.Rename(from, to); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
}

// Organize never moves a cue rip: the file plays several tracks, and the
// pass holds it where it is.
func TestOrganizeLeavesACueRipWhereItIs(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _, ripDir, _ := cueSplitFixture(t)
	plan, err := svc.PreviewOrganize(ctx, uc, "", nil)
	if err != nil {
		t.Fatal(err)
	}
	if !slices.ContainsFunc(plan.Holds, func(h OrganizeHoldDTO) bool { return h.Code == string(organize.HoldVirtual) }) {
		t.Fatalf("holds = %+v, want the rip held", plan.Holds)
	}
	if _, err := svc.ApplyOrganize(ctx, uc, "", nil); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(ripDir, "Rip Album.flac")); err != nil {
		t.Fatalf("the rip moved: %v", err)
	}
}

// A CUE split whose rip moved, sheet and all, after it was queued cuts the
// rip where it is now, and finishes.
func TestACueSplitCutsItsRipWhereItIsNow(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, one, ripDir, engine := cueSplitFixture(t)
	reading := &readingEngine{fakeBookEngine: engine}
	svc.SetFlowJobs(reading)
	task, err := svc.StartCueSplit(ctx, uc, one, false)
	if err != nil {
		t.Fatal(err)
	}
	moved := filepath.Join(filepath.Dir(ripDir), "Moved Album")
	moveRip(t, ctx, svc, ripDir, moved)
	if err := attempt(t, ctx, svc, 1); err != nil {
		t.Fatalf("the run = %v, want it finished", err)
	}
	if done := toolTask(t, ctx, svc, task.ID); done.State != taskStateDone || len(done.ResultPIDs) != 2 {
		t.Fatalf("task = %s (error %q), results %v; want it done with two tracks", done.State, done.Error, done.ResultPIDs)
	}
	want := filepath.Join(moved, "Rip Album.flac")
	if len(reading.srcs) != 1 || reading.srcs[0] != want || reading.cues[0] != filepath.Join(moved, "Rip Album.cue") {
		t.Fatalf("the engine read %v and %v, want the rip and its sheet in %s", reading.srcs, reading.cues, moved)
	}
}

// A CUE split whose rip moved after the cut retires the rip from where it
// is now with its sheet, and removes no file at the sheet's old place,
// which is another's by then.
func TestACueSplitRetiresItsRipWhereItIsNow(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, one, ripDir, _ := cueSplitFixture(t)
	task, err := svc.StartCueSplit(ctx, uc, one, false)
	if err != nil {
		t.Fatal(err)
	}
	svc.toolStepHook = stopAt("staged", nil)
	if err := attempt(t, ctx, svc, 1); err == nil {
		t.Fatal("the first attempt ran on past the cut")
	}
	svc.toolStepHook = nil
	moved := filepath.Join(filepath.Dir(ripDir), "Moved Album")
	moveRip(t, ctx, svc, ripDir, moved)
	// Another rip's sheet takes the old place.
	if err := os.MkdirAll(ripDir, 0o755); err != nil {
		t.Fatal(err)
	}
	stranger := filepath.Join(ripDir, "Rip Album.cue")
	if err := os.WriteFile(stranger, []byte("another rip's sheet"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := attempt(t, ctx, svc, 2); err != nil {
		t.Fatalf("the rerun = %v, want it finished", err)
	}
	if done := toolTask(t, ctx, svc, task.ID); done.State != taskStateDone || len(done.ResultPIDs) != 2 {
		t.Fatalf("task = %s (error %q), results %v; want it done with two tracks", done.State, done.Error, done.ResultPIDs)
	}
	if _, err := os.Stat(stranger); err != nil {
		t.Fatalf("the sheet now at the old place was removed: %v", err)
	}
	for _, name := range []string{"Rip Album.flac", "Rip Album.cue"} {
		if _, err := os.Stat(filepath.Join(moved, name)); !os.IsNotExist(err) {
			t.Errorf("%s is still beside where the rip was (%v)", name, err)
		}
	}
	if trash := activeTrash(t, ctx, svc); !slices.Equal(trash, []string{taskTypeCueSplit}) {
		t.Errorf("trash = %q, want the rip once under cue-split", trash)
	}
}

// A CUE split whose rip's audio alone moved, after its import, into a
// folder holding another rip and its sheet takes no sheet but the rip's
// own for its own: the other rip keeps its sheet, and with it its carved
// tracks.
func TestACueSplitTakesNoSheetButItsRipsOwn(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, one, ripDir, _ := cueSplitFixture(t)
	task, err := svc.StartCueSplit(ctx, uc, one, false)
	if err != nil {
		t.Fatal(err)
	}
	svc.toolStepHook = stopAt("imported", nil)
	if err := attempt(t, ctx, svc, 1); err == nil {
		t.Fatal("the first attempt ran on past the import")
	}
	svc.toolStepHook = nil
	other := filepath.Join(filepath.Dir(ripDir), "Other Album")
	if _, err := fixtures.Generate(other, fixtures.Spec{
		Name: "Other Album", Codec: fixtures.CodecFLAC, Duration: 6 * time.Second, SampleRate: 44100,
		Tags: map[string]string{"ALBUM": "Other Album", "ARTIST": "Other Artist", "ALBUMARTIST": "Other Artist"},
	}); err != nil {
		t.Fatal(err)
	}
	sheet := filepath.Join(other, "Other Album.cue")
	if err := os.WriteFile(sheet, []byte("PERFORMER \"Other Artist\"\nTITLE \"Other Album\"\nFILE \"Other Album.flac\" WAVE\n"+
		"  TRACK 01 AUDIO\n    TITLE \"Other One\"\n    INDEX 01 00:00:00\n"+
		"  TRACK 02 AUDIO\n    TITLE \"Other Two\"\n    INDEX 01 00:03:00\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	moveRip(t, ctx, svc, filepath.Join(ripDir, "Rip Album.flac"), filepath.Join(other, "Rip Album.flac"))
	if got := tracksTitled(t, ctx, svc, "Other One", true); len(got) != 1 {
		t.Fatalf("the other rip's carved tracks titled Other One = %v, want one", got)
	}
	if err := attempt(t, ctx, svc, 2); err != nil {
		t.Fatalf("the rerun = %v, want it finished", err)
	}
	if done := toolTask(t, ctx, svc, task.ID); done.State != taskStateDone {
		t.Fatalf("task = %s (error %q), want it done", done.State, done.Error)
	}
	if cue := taskParams(t, ctx, svc, task.ID).CuePath; cue == sheet {
		t.Fatalf("the split took %s, another rip's sheet, for its own", cue)
	}
	if _, err := os.Stat(sheet); err != nil {
		t.Fatalf("the other rip's sheet was removed: %v", err)
	}
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	if got := tracksTitled(t, ctx, svc, "Other One", true); len(got) != 1 {
		t.Fatalf("the other rip's carved tracks after a rescan = %v, want its track still there", got)
	}
}

// A rip a second encoding of shares its sheet with: splitting the one
// leaves the sheet, which the trash keeps while the other still uses it,
// and the other encoding's carved tracks with it.
func TestACueSplitLeavesASheetAnotherEncodingUses(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, one, ripDir, _ := cueSplitFixture(t)
	if _, err := fixtures.Generate(ripDir, fixtures.Spec{
		Name: "Rip Album", Codec: fixtures.CodecMP3, Duration: 6 * time.Second, SampleRate: 44100,
		Tags: map[string]string{"ALBUM": "Rip Album", "ARTIST": "Rip Artist", "ALBUMARTIST": "Rip Artist"},
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	carved := len(tracksTitled(t, ctx, svc, "Rip One", true))
	task, err := svc.StartCueSplit(ctx, uc, one, false)
	if err != nil {
		t.Fatal(err)
	}
	if err := attempt(t, ctx, svc, 1); err != nil {
		t.Fatalf("the split = %v, want it finished", err)
	}
	if done := toolTask(t, ctx, svc, task.ID); done.State != taskStateDone {
		t.Fatalf("task = %s (error %q), want it done", done.State, done.Error)
	}
	if _, err := os.Stat(filepath.Join(ripDir, "Rip Album.mp3")); err != nil {
		t.Fatalf("the other encoding went: %v", err)
	}
	if _, err := os.Stat(filepath.Join(ripDir, "Rip Album.cue")); err != nil {
		t.Fatalf("the sheet the other encoding is carved by was removed: %v", err)
	}
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	if got := tracksTitled(t, ctx, svc, "Rip One", true); len(got) == 0 {
		t.Fatalf("carved tracks titled Rip One after a rescan = %v, want the other encoding's (there were %d)", got, carved)
	}
}

// A CUE split is refused when it is queued unless the rip has the sheet of
// its own name beside it, the one the catalog carves it by: another sheet
// alone in the folder is not taken for it, and nothing is queued.
func TestACueSplitOfARipWithoutItsOwnSheetIsRefused(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, one, ripDir, _ := cueSplitFixture(t)
	// The sheet takes another name; the catalog still carves the rip until
	// its next scan.
	if err := os.Rename(filepath.Join(ripDir, "Rip Album.cue"), filepath.Join(ripDir, "Other Album.cue")); err != nil {
		t.Fatal(err)
	}
	_, err := svc.StartCueSplit(ctx, uc, one, false)
	if p := RefusalParams(err); KindOf(err) != KindConflict || p["reason"] != refusalNoSheet {
		t.Fatalf("a split of a rip without its own sheet = %v (params %v), want conflict, reason %s", err, p, refusalNoSheet)
	}
	if tasks, _, err := svc.ListToolTasksFor(ctx, uc, "", 10); err != nil || len(tasks) != 0 {
		t.Fatalf("tasks = %+v (%v), want none queued", tasks, err)
	}
}
