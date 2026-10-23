package service

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"

	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// fakeBookEngine is a streaming engine whose merge and split jobs are
// done as soon as they are made, each output synthesized audio, and which
// counts the jobs it was asked for.
type fakeBookEngine struct {
	dir  string
	mu   sync.Mutex
	jobs map[string][]fixtures.Spec
}

func newFakeBookEngine(t *testing.T) *fakeBookEngine {
	return &fakeBookEngine{dir: t.TempDir(), jobs: map[string][]fixtures.Spec{}}
}

func (e *fakeBookEngine) JobsSupported() bool            { return true }
func (e *fakeBookEngine) SilenceDetectorVersion() string { return "" }
func (e *fakeBookEngine) AnalyzeSilence(context.Context, string) (flow.SilenceAnalysis, error) {
	return flow.SilenceAnalysis{}, nil
}

// made is how many jobs the engine was asked for.
func (e *fakeBookEngine) made() int {
	e.mu.Lock()
	defer e.mu.Unlock()
	return len(e.jobs)
}

// job records a job of outputs in format, each of a length no other
// audio in a test shares, and answers its id.
func (e *fakeBookEngine) job(kind, format string, outputs int, chapters []fixtures.Chapter) string {
	e.mu.Lock()
	defer e.mu.Unlock()
	id := fmt.Sprintf("%s-%d", kind, len(e.jobs)+1)
	codec, container := fixtures.CodecAAC, fixtures.ContainerMP4
	switch format {
	case "flac":
		codec, container = fixtures.CodecFLAC, fixtures.ContainerDefault
	case "mp3":
		codec, container = fixtures.CodecMP3, fixtures.ContainerDefault
	}
	specs := make([]fixtures.Spec, outputs)
	for i := range specs {
		specs[i] = fixtures.Spec{
			Name: fmt.Sprintf("%s-%d", id, i), Codec: codec, Container: container,
			Duration: time.Duration(i+1)*1300*time.Millisecond + time.Duration(len(e.jobs)+1)*70*time.Millisecond,
			Chapters: chapters,
		}
	}
	e.jobs[id] = specs
	return id
}

func (e *fakeBookEngine) CreateMergeJob(_ context.Context, srcs, _ []string, _ string) (string, error) {
	chapters := make([]fixtures.Chapter, len(srcs))
	for i := range srcs {
		chapters[i] = fixtures.Chapter{Start: time.Duration(i) * 600 * time.Millisecond,
			End: time.Duration(i+1) * 600 * time.Millisecond, Title: fmt.Sprintf("Chapter %d", i+1)}
	}
	return e.job("merge", "aac", 1, chapters), nil
}

func (e *fakeBookEngine) CreateSplitJob(_ context.Context, _ string, cuts []int64, cue string, format string) (string, error) {
	pieces := len(cuts) + 1
	if cue != "" {
		sheet, err := os.ReadFile(cue)
		if err != nil {
			return "", err
		}
		pieces = strings.Count(string(sheet), "TRACK ")
	}
	return e.job("split", format, pieces, nil), nil
}

func (e *fakeBookEngine) JobStatus(_ context.Context, id string) (string, float64, int, string, error) {
	e.mu.Lock()
	defer e.mu.Unlock()
	return "done", 100, len(e.jobs[id]), "", nil
}

func (e *fakeBookEngine) DownloadJobResult(_ context.Context, id string, index int, dst string, mode os.FileMode) error {
	e.mu.Lock()
	spec := e.jobs[id][index]
	e.mu.Unlock()
	paths, err := fixtures.Generate(e.dir, spec)
	if err != nil {
		return err
	}
	data, err := os.ReadFile(paths[0])
	if err != nil {
		return err
	}
	return os.WriteFile(dst, data, mode)
}

// errStopped is how a test ends a book tool's run where a crash or a
// restart would.
var errStopped = errors.New("the server stopped here")

// stopAt ends a run after step, first doing also when it is set.
func stopAt(step string, also func()) func(string) error {
	return func(s string) error {
		if s != step {
			return nil
		}
		if also != nil {
			also()
		}
		return errStopped
	}
}

// attempt leases the task as the worker would once every earlier lease
// has run out, the nth time, and runs it.
func attempt(t *testing.T, ctx context.Context, svc *Library, n int) error {
	t.Helper()
	now := time.Now().Add(time.Duration(n) * 2 * toolTaskLease).UnixNano()
	row, err := svc.db.LeaseToolTask(ctx, now, toolTaskLease.Nanoseconds(), toolTaskMaxAttempts, wdb.TaskTypes{})
	if err != nil {
		t.Fatalf("leasing attempt %d: %v", n, err)
	}
	return svc.runToolTask(ctx, &row)
}

// bookToolFixture is a library holding the two-part "Tool Book" by Tess
// Tool, in a folder named for it or, with discs set, in disc folders of
// that folder, and an engine whose jobs finish at once. It answers the
// book, the book's folder and the engine.
func bookToolFixture(t *testing.T, discs bool) (context.Context, *Library, *UserCtx, model.PID, string, *fakeBookEngine) {
	t.Helper()
	var root string
	ctx, svc, uc := openEnrichFixture(t, func(c *Config) { root = c.Roots[0].Path })
	dir := filepath.Join(root, "Tess Tool", "Tool Book")
	for part := 1; part <= 2; part++ {
		in := dir
		if discs {
			in = filepath.Join(dir, fmt.Sprintf("CD%d", part))
		}
		toolBook(t, in, part)
	}
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	book, parts := theToolBook(t, svc)
	if parts != 2 {
		t.Fatalf("parts = %d, want the two as one book", parts)
	}
	engine := newFakeBookEngine(t)
	svc.SetFlowJobs(engine)
	return ctx, svc, uc, book, dir, engine
}

// chapteredBookFixture is a library holding the single-file chaptered
// fixture book in a folder named for it, and an engine whose jobs finish
// at once. It answers the book, the book's folder and the engine.
func chapteredBookFixture(t *testing.T) (context.Context, *Library, *UserCtx, model.PID, string, *fakeBookEngine) {
	t.Helper()
	var root string
	ctx, svc, uc := openEnrichFixture(t, func(c *Config) { root = c.Roots[0].Path })
	dir := filepath.Join(root, "Ada Author", "The Chaptered Fixture")
	if _, err := fixtures.GenerateChapteredBook(dir); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	book, _ := theToolBook(t, svc)
	engine := newFakeBookEngine(t)
	svc.SetFlowJobs(engine)
	return ctx, svc, uc, book, dir, engine
}

// partFiles are a book's files, in reading order.
func partFiles(t *testing.T, ctx context.Context, svc *Library, book model.PID) []model.PID {
	t.Helper()
	bd, err := svc.lib.Book(ctx, book)
	if err != nil {
		t.Fatal(err)
	}
	out := make([]model.PID, len(bd.Files))
	for i, f := range bd.Files {
		out[i] = f.FilePID
	}
	return out
}

// trashAs moves files to the trash under a tool's reason, as the tool's
// own trash would.
func trashAs(t *testing.T, ctx context.Context, svc *Library, reason string, files ...model.PID) {
	t.Helper()
	plan, err := svc.lib.PlanDeleteFiles(ctx, files, model.DeleteTrash, waxbin.DeleteReason(reason))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := svc.lib.ApplyDelete(ctx, plan); err != nil {
		t.Fatal(err)
	}
}

// hiddenLeft are the tool's hidden copies a folder still holds.
func hiddenLeft(t *testing.T, dir string) []string {
	t.Helper()
	var out []string
	filepath.WalkDir(dir, func(path string, d os.DirEntry, err error) error {
		if err == nil && strings.HasPrefix(d.Name(), ".waxdeck-tool-") {
			out = append(out, path)
		}
		return nil
	})
	return out
}

// namesIn lists a folder's entries by name.
func namesIn(t *testing.T, dir string) []string {
	t.Helper()
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	out := make([]string, 0, len(entries))
	for _, e := range entries {
		out = append(out, e.Name())
	}
	return out
}

// toolTask reads a task back.
func toolTask(t *testing.T, ctx context.Context, svc *Library, id string) ToolTaskDTO {
	t.Helper()
	row, err := svc.db.ToolTaskByID(ctx, id)
	if err != nil {
		t.Fatal(err)
	}
	return toolTaskDTO(row)
}

// activeTrash is what the trash holds now, by reason.
func activeTrash(t *testing.T, ctx context.Context, svc *Library) []string {
	t.Helper()
	entries, err := svc.lib.Trash(ctx, false, 0)
	if err != nil {
		t.Fatal(err)
	}
	out := make([]string, 0, len(entries))
	for _, e := range entries {
		out = append(out, e.Reason)
	}
	return out
}

// wantMerged fails unless the task finished the merge of book: one file,
// named for the book, in the folder its parts were in, holding the
// carried position, its parts in the trash under the merge's reason, no
// hidden copy left, and one audit of it.
func wantMerged(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, taskID, dir string) {
	t.Helper()
	task := toolTask(t, ctx, svc, taskID)
	if task.State != taskStateDone || len(task.ResultPIDs) != 1 {
		t.Fatalf("task = %s (error %q), results %v; want it done with the merged book", task.State, task.Error, task.ResultPIDs)
	}
	_, merged, _ := parseAPIPID(task.ResultPIDs[0])
	bd, err := svc.lib.Book(ctx, merged)
	if err != nil || len(bd.Files) != 1 {
		t.Fatalf("merged book = %+v, %v; want one file", bd, err)
	}
	file, err := svc.lib.File(ctx, bd.Files[0].FilePID)
	if want := filepath.Join(dir, "Tool Book.m4b"); err != nil || string(file.Path) != want {
		t.Fatalf("merged file = %+v, %v; want %s", file, err, want)
	}
	if names := namesIn(t, dir); !slices.Equal(names, []string{"Tool Book.m4b"}) {
		t.Errorf("the book's folder holds %q, want the merged file alone", names)
	}
	if trash := activeTrash(t, ctx, svc); !slices.Equal(trash, []string{taskTypeBookMerge, taskTypeBookMerge}) {
		t.Errorf("trash = %q, want the two parts under the merge's reason", trash)
	}
	st, err := svc.lib.Playback().State(ctx, model.PID(uc.CatalogPID), merged)
	if err != nil || st.PositionMS != 4200 {
		t.Errorf("merged position = %+v, %v; want 4200 carried", st, err)
	}
	audits := auditDetails(t, ctx, svc, "book.merge")
	if len(audits) != 1 || audits[0]["result"] != task.ResultPIDs[0] || audits[0]["trashed"] != float64(2) {
		t.Errorf("book.merge audits = %v, want the merge recorded once", audits)
	}
}

// A merge stopped after any of its steps, as a crash or a restart stops
// it, finishes when the task runs again: the engine is not asked again,
// nor needed, once the merged file is staged, the parts go to the trash
// once, and the book ends merged where its parts were, with no hidden
// copy or workspace left.
func TestABookMergeStoppedAfterAnyStepFinishesOnTheRerun(t *testing.T) {
	t.Parallel()
	for _, step := range []string{"staged", "trashing", "trashed", "placed", "cataloged"} {
		t.Run(step, func(t *testing.T) {
			t.Parallel()
			ctx, svc, uc, book, dir, engine := bookToolFixture(t, false)
			if _, err := svc.Checkpoint(ctx, uc, apiPID(PrefixBook, book), 4200, nil); err != nil {
				t.Fatal(err)
			}
			task, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
			if err != nil {
				t.Fatal(err)
			}
			var also func()
			if step == "trashing" {
				// Cut after the first part went, as a crash would.
				parts := partFiles(t, ctx, svc, book)
				also = func() { trashAs(t, ctx, svc, taskTypeBookMerge, parts[0]) }
			}
			svc.toolStepHook = stopAt(step, also)
			if err := attempt(t, ctx, svc, 1); !errors.Is(err, errStopped) {
				t.Fatalf("first attempt = %v, want it stopped after %s", err, step)
			}
			// What a crash leaves of the engine's workspace.
			ws := filepath.Join(svc.stagingDir, "tools", task.ID)
			if err := os.MkdirAll(ws, 0o755); err != nil {
				t.Fatal(err)
			}
			svc.toolStepHook = nil
			// The engine's work is done, so the rerun needs no engine.
			svc.SetFlowJobs(stubFlowJobs{})
			if err := attempt(t, ctx, svc, 2); err != nil {
				t.Fatalf("the rerun = %v, want it finished", err)
			}
			wantMerged(t, ctx, svc, uc, task.ID, dir)
			if onDisk(ws) {
				t.Errorf("the stopped attempt's workspace is still there")
			}
			if engine.made() != 1 {
				t.Errorf("engine jobs = %d, want the one the first attempt made", engine.made())
			}
		})
	}
}

// A split stopped while it stages its pieces asks the engine again and
// finishes; one stopped after its original went to the trash finishes
// without it.
func TestABookSplitStoppedAfterAnyStepFinishesOnTheRerun(t *testing.T) {
	t.Parallel()
	for _, c := range []struct {
		step string
		jobs int
	}{{"staging", 2}, {"trashed", 1}, {"placed", 1}} {
		t.Run(c.step, func(t *testing.T) {
			t.Parallel()
			ctx, svc, uc, book, dir, engine := chapteredBookFixture(t)
			task, err := svc.StartBookSplit(ctx, uc, apiPID(PrefixBook, book), false)
			if err != nil {
				t.Fatal(err)
			}
			svc.toolStepHook = stopAt(c.step, nil)
			if err := attempt(t, ctx, svc, 1); !errors.Is(err, errStopped) {
				t.Fatalf("first attempt = %v, want it stopped after %s", err, c.step)
			}
			svc.toolStepHook = nil
			if err := attempt(t, ctx, svc, 2); err != nil {
				t.Fatalf("the rerun = %v, want it finished", err)
			}
			done := toolTask(t, ctx, svc, task.ID)
			if done.State != taskStateDone || len(done.ResultPIDs) != 1 {
				t.Fatalf("task = %s (error %q), want it done", done.State, done.Error)
			}
			want := []string{"01 - Opening.m4b", "02 - Middle.m4b", "03 - Ending.m4b"}
			if names := namesIn(t, dir); !slices.Equal(names, want) {
				t.Errorf("the book's folder holds %q, want the pieces alone", names)
			}
			_, split, _ := parseAPIPID(done.ResultPIDs[0])
			if got := partFiles(t, ctx, svc, split); len(got) != 3 {
				t.Errorf("the split book has %d parts, want 3", len(got))
			}
			if trash := activeTrash(t, ctx, svc); !slices.Equal(trash, []string{taskTypeBookSplit}) {
				t.Errorf("trash = %q, want the original under the split's reason", trash)
			}
			if engine.made() != c.jobs {
				t.Errorf("engine jobs = %d, want %d", engine.made(), c.jobs)
			}
		})
	}
}

// A shutdown that reaches a merge as its parts go to the trash does not
// cut the trash half way: every part goes, and the rerun finishes.
func TestAShutdownMidTrashFinishesTheTrash(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, book, dir, _ := bookToolFixture(t, true)
	if _, err := svc.Checkpoint(ctx, uc, apiPID(PrefixBook, book), 4200, nil); err != nil {
		t.Fatal(err)
	}
	task, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	run, stop := context.WithCancel(ctx)
	defer stop()
	svc.toolStepHook = func(step string) error {
		if step == "trashing" {
			stop()
		}
		return nil
	}
	now := time.Now().Add(2 * toolTaskLease).UnixNano()
	row, err := svc.db.LeaseToolTask(ctx, now, toolTaskLease.Nanoseconds(), toolTaskMaxAttempts, wdb.TaskTypes{})
	if err != nil {
		t.Fatal(err)
	}
	if err := svc.runToolTask(run, &row); !errors.Is(err, context.Canceled) {
		t.Fatalf("the stopped attempt = %v, want it ended by the shutdown", err)
	}
	if trash := activeTrash(t, ctx, svc); len(trash) != 2 {
		t.Fatalf("trash = %q, want both parts moved", trash)
	}
	svc.toolStepHook = nil
	if err := attempt(t, ctx, svc, 2); err != nil {
		t.Fatalf("the rerun = %v, want it finished", err)
	}
	wantMerged(t, ctx, svc, uc, task.ID, dir)
}

// A merge whose attempts all stopped once its output was staged is never
// retired with the book in the trash: the retire pass leaves it, and the
// lease takes it past its attempts until it finishes.
func TestABookMergeOutOfAttemptsAfterItsTrashIsResumedNotRetired(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, book, dir, _ := bookToolFixture(t, false)
	if _, err := svc.Checkpoint(ctx, uc, apiPID(PrefixBook, book), 4200, nil); err != nil {
		t.Fatal(err)
	}
	task, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	for n, step := range []string{"trashed", "placed", "cataloged"} {
		svc.toolStepHook = stopAt(step, nil)
		if err := attempt(t, ctx, svc, n+1); !errors.Is(err, errStopped) {
			t.Fatalf("attempt %d = %v, want it stopped after %s", n+1, err, step)
		}
	}
	svc.toolStepHook = nil
	svc.retireExhaustedToolTasks(ctx, time.Now().Add(10*toolTaskLease).UnixNano())
	if got := toolTask(t, ctx, svc, task.ID); got.State != "running" {
		t.Fatalf("task after the retire pass = %s (error %q), want it left running", got.State, got.Error)
	}
	if err := attempt(t, ctx, svc, 4); err != nil {
		t.Fatalf("the fourth attempt = %v, want it finished", err)
	}
	wantMerged(t, ctx, svc, uc, task.ID, dir)
}

// A split whose attempts all stopped before its pieces were all staged
// is retired with its hidden copies gone and the book as it was.
func TestABookSplitRetiredBeforeItsPiecesWereStagedLeavesNothing(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, book, dir, _ := chapteredBookFixture(t)
	task, err := svc.StartBookSplit(ctx, uc, apiPID(PrefixBook, book), false)
	if err != nil {
		t.Fatal(err)
	}
	for n, step := range []string{"staging", "producing", "producing"} {
		svc.toolStepHook = stopAt(step, nil)
		if err := attempt(t, ctx, svc, n+1); !errors.Is(err, errStopped) {
			t.Fatalf("attempt %d = %v, want it stopped at %s", n+1, err, step)
		}
	}
	svc.toolStepHook = nil
	svc.retireExhaustedToolTasks(ctx, time.Now().Add(10*toolTaskLease).UnixNano())
	if done := toolTask(t, ctx, svc, task.ID); done.State != taskStateFailed {
		t.Fatalf("task = %s, want it retired", done.State)
	}
	if left := hiddenLeft(t, dir); len(left) != 0 {
		t.Errorf("hidden copies left: %q", left)
	}
	if names := namesIn(t, dir); !slices.Equal(names, []string{"The Chaptered Fixture.m4b"}) {
		t.Errorf("the book's folder holds %q, want the original alone", names)
	}
	if trash := activeTrash(t, ctx, svc); len(trash) != 0 {
		t.Errorf("trash = %q, want nothing moved", trash)
	}
	// Retired is failed, and tells whoever started it as a failure does.
	if row := waitForInbox(t, ctx, svc, uc, "tool-task-failed"); row.TargetPID != task.ID {
		t.Errorf("inbox row = %+v, want the retired split", row)
	}
}

// The merge's trash takes the parts it merged and nothing else: a book
// that gained a part since the merge was queued fails the merge with
// nothing moved and nothing written.
func TestAMergeOfABookThatChangedSinceItWasQueuedMovesNothing(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, book, dir, _ := bookToolFixture(t, false)
	task, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	toolBook(t, dir, 3)
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	if got := partFiles(t, ctx, svc, book); len(got) != 3 {
		t.Fatalf("parts = %d, want the third joined", len(got))
	}
	if err := attempt(t, ctx, svc, 1); !errors.Is(err, errToolPermanent) || !strings.Contains(err.Error(), "changed since the merge was queued") {
		t.Fatalf("merge = %v, want a permanent refusal of the changed book", err)
	}
	if trash := activeTrash(t, ctx, svc); len(trash) != 0 {
		t.Errorf("trash = %q, want nothing moved", trash)
	}
	if names := namesIn(t, dir); len(names) != 3 || slices.Contains(names, "Tool Book.m4b") {
		t.Errorf("the book's folder holds %q, want its three parts alone", names)
	}
	_ = task
}

// A book with a copy elsewhere is not merged away: the merge would trash
// its parts and leave the copy as the book. Keeping the originals merges
// it.
func TestAMergeOfABookWithACopyKeepsTheOriginals(t *testing.T) {
	t.Parallel()
	var root, other string
	ctx, svc, uc := openEnrichFixture(t, func(c *Config) {
		root = c.Roots[0].Path
		other = t.TempDir()
		c.Roots = append(c.Roots, Root{Name: "other", Path: other})
	})
	dir := filepath.Join(root, "Tess Tool", "Tool Book")
	toolBook(t, dir, 1)
	toolBook(t, dir, 2)
	copyDir := filepath.Join(other, "Tess Tool", "Tool Book")
	if err := os.MkdirAll(copyDir, 0o755); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"part 1.m4b", "part 2.m4b"} {
		data, err := os.ReadFile(filepath.Join(dir, name))
		if err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(copyDir, name), data, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	book, _ := theToolBook(t, svc)
	refs, err := svc.lib.ItemFiles(ctx, book)
	if err != nil {
		t.Fatal(err)
	}
	if !slices.ContainsFunc(refs, func(r model.ItemFileRef) bool { return r.Role == "alternate" }) {
		t.Skipf("the catalog made no copy of the book (%+v)", refs)
	}
	svc.SetFlowJobs(newFakeBookEngine(t))
	if _, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false); KindOf(err) != KindConflict ||
		!strings.Contains(err.Error(), "copy") {
		t.Fatalf("merge of a book with a copy = %v (kind %q), want a conflict naming the copy", err, KindOf(err))
	}
	if _, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, true); err != nil {
		t.Fatalf("merge keeping the originals = %v, want it queued", err)
	}
}

// A merge whose trash some part refuses as it runs puts back the parts
// that went and writes nothing, and the run is audited with what moved.
func TestAMergeWhoseTrashIsCutShortPutsThePartsBack(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritablePaths(t)
	ctx, svc, uc, book, dir, _ := bookToolFixture(t, true)
	task, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	svc.deleteApplyHook = func(context.Context) { lockFolder(t, filepath.Join(dir, "CD2")) }
	err = attempt(t, ctx, svc, 1)
	if !errors.Is(err, errToolPermanent) {
		t.Fatalf("merge = %v, want it failed for good", err)
	}
	for _, want := range []string{"1 of 2 files", "CD2/part 2.m4b", "permission denied", "put back", "nothing was written"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("failure %q does not say %q", err, want)
		}
	}
	if got := partFiles(t, ctx, svc, book); len(got) != 2 {
		t.Errorf("the book has %d parts after the failed merge, want both back", len(got))
	}
	if trash := activeTrash(t, ctx, svc); len(trash) != 0 {
		t.Errorf("trash = %q, want what went put back", trash)
	}
	if left := hiddenLeft(t, dir); len(left) != 0 {
		t.Errorf("hidden copies left: %q", left)
	}
	audits := auditDetails(t, ctx, svc, "book.merge")
	if len(audits) != 1 || audits[0]["result"] != "failed" || audits[0]["trashed"] != float64(1) || audits[0]["restored"] != float64(1) {
		t.Errorf("book.merge audits = %v, want the failed run recorded with what moved", audits)
	}
	_ = task
}

// A split whose pieces cannot take their names once the original went
// waits, saying where every one of them is, and finishes once the folder
// takes them: it never ends with the book in the trash and its pieces
// hidden.
func TestASplitWhosePiecesCannotTakeTheirNamesWaitsSayingWhereEachIs(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritablePaths(t)
	ctx, svc, uc, book, dir, _ := chapteredBookFixture(t)
	task, err := svc.StartBookSplit(ctx, uc, apiPID(PrefixBook, book), false)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	svc.toolStepHook = func(step string) error {
		if step == "trashed" {
			if err := os.Chmod(dir, 0o555); err != nil {
				t.Error(err)
			}
		}
		return nil
	}
	t.Cleanup(func() { _ = os.Chmod(dir, 0o755) })
	err = attempt(t, ctx, svc, 1)
	var wait *toolRetry
	if !errors.As(err, &wait) {
		t.Fatalf("split = %v, want it waiting", err)
	}
	for i := range 3 {
		if want := fmt.Sprintf(".waxdeck-tool-%s-%d", task.ID, i); !strings.Contains(err.Error(), want) {
			t.Errorf("wait %q does not name %s", err, want)
		}
	}
	if left := hiddenLeft(t, dir); len(left) != 3 {
		t.Errorf("hidden copies = %q, want all three kept", left)
	}
	svc.toolStepHook = nil
	if err := os.Chmod(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := attempt(t, ctx, svc, 2); err != nil {
		t.Fatalf("the rerun = %v, want it finished", err)
	}
	if done := toolTask(t, ctx, svc, task.ID); done.State != taskStateDone {
		t.Fatalf("task = %s (error %q), want it done", done.State, done.Error)
	}
	if left := hiddenLeft(t, dir); len(left) != 0 {
		t.Errorf("hidden copies left: %q", left)
	}
}

// A failure is recorded even when the server is stopping.
func TestAToolFailureIsRecordedAsTheServerStops(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, book, _, _ := bookToolFixture(t, false)
	task, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	row, err := svc.db.ToolTaskByID(ctx, task.ID)
	if err != nil {
		t.Fatal(err)
	}
	stopping, stop := context.WithCancel(ctx)
	stop()
	svc.failToolTask(stopping, &row, fmt.Errorf("%w: the part went missing", errToolPermanent))
	if got := toolTask(t, ctx, svc, task.ID); got.State != taskStateFailed || got.Error != "the part went missing" {
		t.Fatalf("task = %s (error %q), want the failure recorded", got.State, got.Error)
	}
}

// A split whose run cannot go on once it staged its pieces in a folder it
// made for them leaves no such folder behind.
func TestASplitThatCannotGoOnRemovesTheFolderItMade(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritablePaths(t)
	var root string
	ctx, svc, uc := openEnrichFixture(t, func(c *Config) { root = c.Roots[0].Path })
	author := filepath.Join(root, "Ada Author")
	if _, err := fixtures.GenerateChapteredBook(author); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	book, _ := theToolBook(t, svc)
	svc.SetFlowJobs(newFakeBookEngine(t))
	if _, err := svc.StartBookSplit(ctx, uc, apiPID(PrefixBook, book), false); err != nil {
		t.Fatal(err)
	}
	// The library's root stops taking the trash's folder once the pieces
	// are staged.
	svc.toolStepHook = func(step string) error {
		if step == "staged" {
			lockFolder(t, root)
		}
		return nil
	}
	err := attempt(t, ctx, svc, 1)
	if !errors.Is(err, errToolPermanent) || !strings.Contains(err.Error(), "permission denied") ||
		!strings.Contains(err.Error(), "nothing was written") {
		t.Fatalf("split = %v, want it failed for good with nothing written", err)
	}
	if names := namesIn(t, author); !slices.Equal(names, []string{"The Chaptered Fixture.m4b"}) {
		t.Errorf("the author's folder holds %q, want the original alone", names)
	}
}

// A scan that makes no book of a tool's placed files is never answered by
// a book in the trash: the original a run trashed carries the same title.
func TestAToolScanThatMakesNoBookIsNotAnsweredByATrashedOne(t *testing.T) {
	t.Parallel()
	var root string
	ctx, svc, uc := openEnrichFixture(t, func(c *Config) { root = c.Roots[0].Path })
	toolBook(t, filepath.Join(root, "Tool Book", "CD1"), 1)
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	book, _ := theToolBook(t, svc)
	bd, err := svc.lib.Book(ctx, book)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := svc.DeleteItems(ctx, uc, []string{apiPID(PrefixBook, book)}, "trash", false); err != nil {
		t.Fatal(err)
	}
	dir := filepath.Join(root, "Tool Book")
	pid, err := svc.scanToolOutputs(ctx, dir, []string{filepath.Join(dir, "gone.m4b")}, model.NewPID(), bd.Item.Title)
	if !errors.Is(err, errToolPermanent) || !strings.Contains(err.Error(), "the scan made no book of them") {
		t.Fatalf("scan = %q, %v; want it to say the scan made no book of the files", pid, err)
	}
}

// A scan that makes no book of a tool's placed files says so, rather than
// that a later scan will catalog them.
func TestAToolScanThatMakesNoBookSaysSo(t *testing.T) {
	t.Parallel()
	var root string
	ctx, svc, _ := openEnrichFixture(t, func(c *Config) { root = c.Roots[0].Path })
	dir := filepath.Join(root, "Nobody", "Nothing")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	_, err := svc.scanToolOutputs(ctx, dir, []string{filepath.Join(dir, "gone.m4b")}, model.NewPID(), "No Such Book")
	if !errors.Is(err, errToolPermanent) || !strings.Contains(err.Error(), "the scan made no book of them") ||
		strings.Contains(err.Error(), "next scan") {
		t.Fatalf("scan = %v, want it to say the scan made no book of the files", err)
	}
}
