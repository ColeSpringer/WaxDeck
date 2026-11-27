package service

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/enrich"
	"github.com/colespringer/waxbin/model"
	catalogerr "github.com/colespringer/waxbin/waxerr"
	waxtap "github.com/colespringer/waxtap/v3"

	"github.com/colespringer/waxdeck/fixtures"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/syncsource"
)

// taskMarks counts the task markers the account got for a task.
func taskMarks(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, taskID string) int {
	t.Helper()
	n := 0
	for _, e := range eventsAfter(t, ctx, svc, uc, 0) {
		if e.Kind == eventTask && e.ItemPID == taskID {
			n++
		}
	}
	return n
}

// cancelTask cancels a task as its owner would, failing on a refusal; a
// hook a run calls may use it.
func cancelTask(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, id string) ToolTaskDTO {
	t.Helper()
	dto, err := svc.Tools.CancelToolTaskFor(ctx, uc, id)
	if err != nil {
		t.Errorf("canceling %s: %v", id, err)
	}
	return dto
}

// loggingTo has a fixture's service log to logs.
func loggingTo(logs *syncBuffer) func(*Config) {
	return func(c *Config) { c.Logger = slog.New(slog.NewTextHandler(logs, nil)) }
}

// awaitFetch waits for the source to start fetching id, failing the test
// when it does not within ten seconds.
func awaitFetch(t *testing.T, src *eventfulSource, id string) {
	t.Helper()
	deadline := time.After(10 * time.Second)
	for {
		select {
		case got := <-src.fetching:
			if got == id {
				return
			}
		case <-deadline:
			t.Fatalf("the source never fetched %q", id)
		}
	}
}

// idle reports whether the worker finds nothing to run, an hour on.
func idle(ctx context.Context, svc *Library) bool {
	return !svc.Tools.drainToolTasksAt(ctx, wdb.TaskTypes{}, time.Now().Add(time.Hour).UnixNano())
}

// A queued task asked to cancel ends canceled at once, tells its watchers,
// and is never run.
func TestCancelingAQueuedTaskEndsItAtOnce(t *testing.T) {
	t.Parallel()
	src := &stagingSource{}
	ctx, svc, uc := acquireFixture(t, src)
	task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/playlist?list=PLthree", false, "music", "", "", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	marks := taskMarks(t, ctx, svc, uc, task.ID)
	dto := cancelTask(t, ctx, svc, uc, task.ID)
	if dto.State != taskStateCanceled || dto.FinishedAtNS == 0 || dto.CancelRequested {
		t.Fatalf("the cancel answered %s, finished at %d, cancel requested %v; want it canceled now",
			dto.State, dto.FinishedAtNS, dto.CancelRequested)
	}
	if got := taskMarks(t, ctx, svc, uc, task.ID); got != marks+1 {
		t.Errorf("task markers went from %d to %d, want one for the end", marks, got)
	}
	if !idle(ctx, svc) {
		t.Fatal("the worker ran a canceled task")
	}
	if row := storedTask(t, ctx, svc, task.ID); row.State != taskStateCanceled || row.Attempts != 0 {
		t.Fatalf("task = %s after %d attempts, want it canceled, never leased", row.State, row.Attempts)
	}
	if n := len(src.fetchCounts()); n != 0 {
		t.Errorf("a canceled acquisition fetched %d items", n)
	}
}

// A running acquisition asked to cancel says so while it winds down, then
// ends canceled, not run again: what staged keeps its review entry, which
// the task lists, and the download in hand leaves nothing in staging.
func TestCancelingARunningAcquisitionKeepsWhatStaged(t *testing.T) {
	t.Parallel()
	src := &eventfulSource{
		events: map[string][]syncsource.FetchEvent{"two": {{Phase: syncsource.PhaseDownloading, Bytes: 10, Total: 100}}},
		hold:   "two", release: make(chan struct{}), fetching: make(chan string, 3), deaf: true,
	}
	ctx, svc, uc := acquireFixture(t, src)
	task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/playlist?list=PLthree", false, "music", "", "", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	ran := make(chan struct{})
	go func() {
		defer close(ran)
		svc.Tools.DrainSourceToolTasks(ctx)
	}()
	awaitFetch(t, src, "two")
	// The fetch in hand answers only once released, so the run is still
	// winding down when the request is answered.
	dto := cancelTask(t, ctx, svc, uc, task.ID)
	close(src.release)
	if dto.State != taskStateRunning || !dto.CancelRequested {
		t.Errorf("a running task asked to cancel reads %s, cancel requested %v; want running, cancel requested", dto.State, dto.CancelRequested)
	}
	select {
	case <-ran:
	case <-time.After(10 * time.Second):
		t.Fatal("the canceled run did not stop")
	}
	row := storedTask(t, ctx, svc, task.ID)
	if row.State != taskStateCanceled || row.FinishedAtNS == 0 || row.Error != "" {
		t.Fatalf("task = %s (error %q), want it canceled", row.State, row.Error)
	}
	if !idle(ctx, svc) {
		t.Fatal("the worker ran the canceled task again")
	}
	p := taskParamsOf(&row)
	var results []string
	if err := json.Unmarshal([]byte(row.ResultPIDs), &results); err != nil {
		t.Fatal(err)
	}
	if len(p.Fetched) != 1 || len(results) != 1 {
		t.Fatalf("fetched %+v with results %v, want the first item staged and its entry listed", p.Fetched, results)
	}
	up, err := svc.db.UploadByID(ctx, p.Fetched[0].Upload)
	if err != nil || up.ReviewEntryID != results[0] {
		t.Fatalf("the staged upload = %+v (%v), want it in the listed entry %s", up, err, results[0])
	}
	entries, err := os.ReadDir(svc.Ingest.stagingDir)
	if err != nil {
		t.Fatal(err)
	}
	var dirs []string
	for _, e := range entries {
		if strings.HasPrefix(e.Name(), "up-") {
			dirs = append(dirs, e.Name())
		}
	}
	if !slices.Equal(dirs, []string{up.ID}) {
		t.Errorf("staging holds %v, want only the staged upload %s", dirs, up.ID)
	}
	if got := src.fetchCounts(); len(got) != 1 {
		t.Errorf("fetches = %v, want only the first item's", got)
	}
	if dto := queuedTasks(t, ctx, svc, uc)[0]; dto.Activity != nil || dto.CancelRequested {
		t.Errorf("the canceled task reads activity %+v, cancel requested %v", dto.Activity, dto.CancelRequested)
	}
}

// A task waiting out a source's half-hour retry-after is canceled within
// the one request, not when its wait runs out.
func TestCancelingAWaitingTaskEndsItWithinTheRequest(t *testing.T) {
	t.Parallel()
	src := &probeSource{fetchErr: catalogerr.Wrap(catalogerr.CodeIO, "fetch",
		&waxtap.RateLimitError{RetryAfter: 30 * time.Minute, StatusCode: 429})}
	ctx, svc, uc := acquireFixture(t, src)
	task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/watch?v=one", false, "music", "", "", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	drainOnce(t, ctx, svc)
	if row := storedTask(t, ctx, svc, task.ID); row.WaitReason != "rate-limited" || time.Until(time.Unix(0, row.LeaseUntilNS)) < 25*time.Minute {
		t.Fatalf("task = %s waiting on %q until %v, want a half-hour wait", row.State, row.WaitReason, time.Unix(0, row.LeaseUntilNS))
	}
	if dto := cancelTask(t, ctx, svc, uc, task.ID); dto.State != taskStateCanceled || dto.WaitReason != "" {
		t.Fatalf("the cancel answered %s waiting on %q, want it canceled now", dto.State, dto.WaitReason)
	}
	if !idle(ctx, svc) {
		t.Fatal("the worker ran the canceled task once its wait was out")
	}
	if row := storedTask(t, ctx, svc, task.ID); row.State != taskStateCanceled || row.Error != "" || row.ErrorCode != "" {
		t.Fatalf("task = %s (error %q, code %q), want it canceled with no wait's words", row.State, row.Error, row.ErrorCode)
	}
}

// A cancel that lands after the lease and before the run holds its task
// ends it canceled: the run stops before it fetches anything, and the end
// is told once.
func TestACancelBetweenTheLeaseAndTheHoldStopsTheRun(t *testing.T) {
	t.Parallel()
	src := &stagingSource{}
	ctx, svc, uc := acquireFixture(t, src)
	task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/playlist?list=PLthree", false, "music", "", "", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	var marks int
	svc.Tools.drainHook = func(point, id string) {
		if point == "leased" && id == task.ID {
			cancelTask(t, ctx, svc, uc, id)
			marks = taskMarks(t, ctx, svc, uc, id)
		}
	}
	drainOnce(t, ctx, svc)
	if row := storedTask(t, ctx, svc, task.ID); row.State != taskStateCanceled {
		t.Fatalf("task = %s (error %q), want it canceled", row.State, row.Error)
	}
	if n := len(src.fetchCounts()); n != 0 {
		t.Errorf("the run fetched %d items after its cancel", n)
	}
	if got := taskMarks(t, ctx, svc, uc, task.ID); got != marks {
		t.Errorf("task markers went from %d to %d once the run stopped, want the end told once", marks, got)
	}
	if !idle(ctx, svc) {
		t.Fatal("the worker ran the canceled task again")
	}
}

// A cancel that lands as the run ends leaves the task done when it
// finished first, and canceled otherwise, however the run ended: never
// run again, never put back to waiting or failed.
func TestACancelAsTheRunEndsEndsItOnce(t *testing.T) {
	t.Parallel()
	t.Run("finished first", func(t *testing.T) {
		t.Parallel()
		ctx, svc, uc := acquireFixture(t, &stagingSource{})
		task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/playlist?list=PLthree", false, "music", "", "", nil, nil)
		if err != nil {
			t.Fatal(err)
		}
		svc.Tools.drainHook = func(point, id string) {
			if point != "ran" {
				return
			}
			if dto := cancelTask(t, ctx, svc, uc, id); dto.State != taskStateDone || dto.CancelRequested {
				t.Errorf("a cancel of a done task answered %s, cancel requested %v; want it as it is", dto.State, dto.CancelRequested)
			}
		}
		drainOnce(t, ctx, svc)
		if row := storedTask(t, ctx, svc, task.ID); row.State != taskStateDone || row.CancelRequested {
			t.Fatalf("task = %s, cancel requested %v; want it done, the cancel ignored", row.State, row.CancelRequested)
		}
		if !idle(ctx, svc) {
			t.Fatal("the worker ran the done task again")
		}
	})
	for name, fetchErr := range map[string]error{
		"waiting": &waxtap.RateLimitError{RetryAfter: 90 * time.Second, StatusCode: 429},
		"failing": waxtap.ErrVideoUnavailable,
	} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			logs := &syncBuffer{}
			ctx, svc, uc := acquireFixture(t, &probeSource{fetchErr: catalogerr.Wrap(catalogerr.CodeIO, "fetch", fetchErr)}, loggingTo(logs))
			task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/watch?v=one", false, "music", "", "", nil, nil)
			if err != nil {
				t.Fatal(err)
			}
			svc.Tools.drainHook = func(point, id string) {
				if point == "ran" {
					if dto := cancelTask(t, ctx, svc, uc, id); dto.State != taskStateCanceled {
						t.Errorf("a cancel as the run ended answered %s, want canceled", dto.State)
					}
				}
			}
			drainOnce(t, ctx, svc)
			row := storedTask(t, ctx, svc, task.ID)
			if row.State != taskStateCanceled || row.WaitReason != "" || row.Error != "" || row.ErrorCode != "" {
				t.Fatalf("task = %s waiting on %q (error %q, code %q), want it canceled as the cancel left it",
					row.State, row.WaitReason, row.Error, row.ErrorCode)
			}
			if strings.Contains(logs.String(), "a tool task failed") {
				t.Errorf("a task canceled as its run ended was logged as failed:\n%s", logs)
			}
			if !idle(ctx, svc) {
				t.Fatal("the worker ran the canceled task again")
			}
		})
	}
	// No interleaving forced: a smoke run for the race detector.
	t.Run("racing smoke", func(t *testing.T) {
		t.Parallel()
		ctx, svc, uc := acquireFixture(t, &stagingSource{})
		for range 3 {
			task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/playlist?list=PLthree", false, "music", "", "", nil, nil)
			if err != nil {
				t.Fatal(err)
			}
			var wg sync.WaitGroup
			wg.Go(func() {
				svc.Tools.DrainSourceToolTasks(ctx)
			})
			if _, err := svc.Tools.CancelToolTaskFor(ctx, uc, task.ID); err != nil {
				t.Errorf("canceling: %v", err)
			}
			wg.Wait()
			for svc.Tools.DrainSourceToolTasks(ctx) {
			}
			if row := storedTask(t, ctx, svc, task.ID); row.State != taskStateDone && row.State != taskStateCanceled {
				t.Fatalf("task = %s (error %q), want it done or canceled", row.State, row.Error)
			}
		}
	})
}

// A canceled task is a finished one: it can be deleted, and Clear
// finished takes it.
func TestACanceledTaskIsClearedAsAFinishedOne(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := acquireFixture(t, &stagingSource{})
	var ids []string
	for range 2 {
		task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/playlist?list=PLthree", false, "music", "", "", nil, nil)
		if err != nil {
			t.Fatal(err)
		}
		cancelTask(t, ctx, svc, uc, task.ID)
		ids = append(ids, task.ID)
	}
	if err := svc.Tools.DeleteToolTaskFor(ctx, uc, ids[0]); err != nil {
		t.Fatalf("deleting a canceled task: %v", err)
	}
	deleted, kept, err := svc.Tools.ClearFinishedToolTasksFor(ctx, uc, ToolTasksMine)
	if err != nil || deleted != 1 || kept != 0 {
		t.Fatalf("clear = %d deleted, %d kept (%v), want the other canceled task", deleted, kept, err)
	}
	if left := queuedTasks(t, ctx, svc, uc); len(left) != 0 {
		t.Fatalf("tasks left = %+v", left)
	}
}

// A task that had finished answers a cancel as it is, with no error.
func TestACancelOfAFinishedTaskAnswersItAsItIs(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := acquireFixture(t, &stagingSource{})
	for _, state := range []string{taskStateDone, taskStateFailed, taskStateParked, taskStateCanceled} {
		row := newToolTask(uc, taskTypeAcquire, "", toolTaskParams{}, "")
		row.State, row.Error, row.FinishedAtNS = state, "what it said", time.Now().UnixNano()
		if err := svc.db.InsertToolTask(ctx, row); err != nil {
			t.Fatal(err)
		}
		dto, err := svc.Tools.CancelToolTaskFor(ctx, uc, row.ID)
		if err != nil || dto.State != state || dto.CancelRequested {
			t.Errorf("a cancel of a %s task = %s, cancel requested %v (%v); want it as it is", state, dto.State, dto.CancelRequested, err)
		}
		if got := storedTask(t, ctx, svc, row.ID); got.State != state || got.Error != "what it said" || got.CancelRequested {
			t.Errorf("the %s task reads %s (error %q, cancel requested %v) after the cancel", state, got.State, got.Error, got.CancelRequested)
		}
	}
}

// Only the task's owner or an administrator may cancel it; anyone else is
// told there is no such task, and it runs on.
func TestAStrangerCannotCancelATask(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := acquireFixture(t, &stagingSource{})
	task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/playlist?list=PLthree", false, "music", "", "", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	_, stranger := memberAs(t, ctx, svc, AccountCreate{Username: "stranger"})
	if _, err := svc.Tools.CancelToolTaskFor(ctx, stranger, task.ID); KindOf(err) != KindNotFound {
		t.Fatalf("a stranger's cancel = %v, want not-found", err)
	}
	if row := storedTask(t, ctx, svc, task.ID); row.State != taskStateQueued || row.CancelRequested {
		t.Fatalf("task = %s, cancel requested %v after a stranger's cancel", row.State, row.CancelRequested)
	}
}

// droppingEngine is a book engine whose jobs keep running until a run
// drops them, which it records.
type droppingEngine struct {
	*fakeBookEngine
	mu      sync.Mutex
	dropped []string
}

func (e *droppingEngine) DeleteJob(_ context.Context, id string) error {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.dropped = append(e.dropped, id)
	return nil
}

func (e *droppingEngine) droppedJobs() []string {
	e.mu.Lock()
	defer e.mu.Unlock()
	return slices.Clone(e.dropped)
}

// A book merge canceled while the engine renders it has the engine drop
// its job, leaves nothing of itself in the library or in staging, tells
// nobody it failed, and frees the book for another merge.
func TestACanceledBookMergeDropsItsEngineJob(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, book, dir, base := bookToolFixture(t, false)
	base.running = 1 << 20
	engine := &droppingEngine{fakeBookEngine: base}
	svc.Tools.SetFlowJobs(engine)
	task, err := svc.Tools.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	var once sync.Once
	svc.Tools.activityHook = func(id string, a ToolTaskActivity) {
		if id == task.ID && a.Phase == activityProcessing {
			once.Do(func() {
				marks := taskMarks(t, ctx, svc, uc, id)
				if dto := cancelTask(t, ctx, svc, uc, id); dto.State != taskStateRunning || !dto.CancelRequested {
					t.Errorf("the rendering merge asked to cancel reads %s, cancel requested %v", dto.State, dto.CancelRequested)
				}
				if got := taskMarks(t, ctx, svc, uc, id); got != marks+1 {
					t.Errorf("task markers went from %d to %d at the request, want one", marks, got)
				}
			})
		}
	}
	done := make(chan struct{})
	go func() {
		defer close(done)
		svc.Tools.DrainToolTasks(ctx)
	}()
	select {
	case <-done:
	case <-time.After(20 * time.Second):
		t.Fatal("the canceled merge did not stop")
	}
	if row := storedTask(t, ctx, svc, task.ID); row.State != taskStateCanceled {
		t.Fatalf("task = %s (error %q), want it canceled", row.State, row.Error)
	}
	if got := engine.droppedJobs(); len(got) != 1 {
		t.Errorf("the engine dropped jobs %v, want the merge's one", got)
	}
	if left := hiddenLeft(t, dir); len(left) != 0 {
		t.Errorf("the canceled merge left %v in the book's folder", left)
	}
	if _, err := os.Stat(filepath.Join(svc.Ingest.stagingDir, "tools", task.ID)); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("the canceled merge's workspace = %v, want it gone", err)
	}
	if _, parts := theToolBook(t, svc); parts != 2 {
		t.Errorf("the book has %d parts after the canceled merge, want its two", parts)
	}
	if rows := inboxOf(t, ctx, svc, uc, "tool-task-failed"); len(rows) != 0 {
		t.Errorf("a canceled merge filed %+v", rows)
	}
	if _, err := svc.Tools.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false); err != nil {
		t.Errorf("a merge after the canceled one = %v, want it queued", err)
	}
}

// A book merge that started moving library files can no longer be
// canceled, whether it is running or waiting to try again: the cancel
// answers task-committed and the merge finishes on its own.
func TestABookMergePastItsTrashCannotBeCanceled(t *testing.T) {
	t.Parallel()
	committed := func(t *testing.T, err error) {
		t.Helper()
		if KindOf(err) != KindConflict || RefusalParams(err)["reason"] != "task-committed" {
			t.Fatalf("the cancel = %v, want conflict for task-committed", err)
		}
	}
	t.Run("running", func(t *testing.T) {
		t.Parallel()
		ctx, svc, uc, book, _, _ := bookToolFixture(t, false)
		task, err := svc.Tools.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
		if err != nil {
			t.Fatal(err)
		}
		var refusal error
		asked := false
		svc.Tools.toolStepHook = func(step string) error {
			if step == "trashed" && !asked {
				asked = true
				_, refusal = svc.Tools.CancelToolTaskFor(ctx, uc, task.ID)
			}
			return nil
		}
		drainOnce(t, ctx, svc)
		if !asked {
			t.Fatal("the merge never reached its trash")
		}
		committed(t, refusal)
		if row := storedTask(t, ctx, svc, task.ID); row.State != taskStateDone || row.CancelRequested {
			t.Fatalf("task = %s (error %q), cancel requested %v; want it done", row.State, row.Error, row.CancelRequested)
		}
	})
	t.Run("waiting", func(t *testing.T) {
		t.Parallel()
		ctx, svc, uc, book, _, _ := bookToolFixture(t, false)
		task, err := svc.Tools.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
		if err != nil {
			t.Fatal(err)
		}
		svc.Tools.toolStepHook = stopAt("trashed", nil)
		if err := attempt(t, ctx, svc, 1); !errors.Is(err, errStopped) {
			t.Fatalf("first attempt = %v, want it stopped past the trash", err)
		}
		svc.Tools.toolStepHook = nil
		_, err = svc.Tools.CancelToolTaskFor(ctx, uc, task.ID)
		committed(t, err)
		if row := storedTask(t, ctx, svc, task.ID); row.State != taskStateRunning || row.CancelRequested {
			t.Fatalf("task = %s, cancel requested %v after a refused cancel", row.State, row.CancelRequested)
		}
		if !drainAt(ctx, svc, 2) {
			t.Fatal("the worker found no task")
		}
		if row := storedTask(t, ctx, svc, task.ID); row.State != taskStateDone {
			t.Fatalf("task = %s (error %q), want the merge finished", row.State, row.Error)
		}
	})
}

// failingEngine is a book engine whose jobs fail as the engine refuses
// them.
type failingEngine struct{ *fakeBookEngine }

func (failingEngine) JobStatus(context.Context, string) (string, float64, int, string, error) {
	return "failed", 0, 0, "invalid-request: the engine refused the job", nil
}

// A book merge canceled as its run fails ends canceled and files nothing:
// the failure it met is no news once the merge was canceled.
func TestACanceledBookMergeFilesNoFailure(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, book, _, base := bookToolFixture(t, false)
	svc.Tools.SetFlowJobs(failingEngine{base})
	task, err := svc.Tools.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	svc.Tools.drainHook = func(point, id string) {
		if point == "ran" {
			cancelTask(t, ctx, svc, uc, id)
		}
	}
	drainOnce(t, ctx, svc)
	if row := storedTask(t, ctx, svc, task.ID); row.State != taskStateCanceled || row.Error != "" {
		t.Fatalf("task = %s (error %q), want it canceled", row.State, row.Error)
	}
	if rows := inboxOf(t, ctx, svc, uc, "tool-task-failed"); len(rows) != 0 {
		t.Errorf("a canceled merge filed %+v", rows)
	}
}

// A health fix canceled between its items stops there, keeps the count of
// what it did, and tells nobody it finished.
func TestACanceledFixStopsBetweenItsItems(t *testing.T) {
	t.Parallel()
	var (
		taskID string
		svc    *Library
		uc     *UserCtx
		ctx    context.Context
		asked  int
		mu     sync.Mutex
	)
	lyrics := &enrich.Mock{ProviderName: "lyricist", Caps: enrich.CapLyrics,
		EnrichFunc: func(context.Context, enrich.Request) (*enrich.Candidate, error) {
			mu.Lock()
			asked++
			first := asked == 1
			mu.Unlock()
			if first {
				cancelTask(t, ctx, svc, uc, taskID)
			}
			return &enrich.Candidate{Lyrics: &model.Lyrics{Unsynced: "la la"}}, nil
		}}
	ctx, svc, uc = openEnrichFixture(t, func(c *Config) {
		c.EnrichmentProviders = []enrich.Provider{lyrics}
		for i, title := range []string{"Amber Waves", "Basalt Lines"} {
			if _, err := fixtures.Generate(c.Roots[0].Path, fixtures.Spec{
				Name: fmt.Sprintf("track-%d", i), Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
				Tags: map[string]string{"TITLE": title, "ARTIST": "Test Ensemble", "ALBUM": "Signal Garden"},
			}); err != nil {
				t.Fatal(err)
			}
		}
	})
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	if err := svc.Health.RunHealthSweep(ctx); err != nil {
		t.Fatal(err)
	}
	var scope []string
	for _, title := range []string{"Amber Waves", "Basalt Lines"} {
		_, pid := fixtureTrackPID(t, ctx, svc, uc, title)
		scope = append(scope, apiPID(PrefixTrack, pid))
	}
	start, err := svc.Health.StartHealthFix(ctx, uc, ruleMissingLyrics, scope)
	if err != nil {
		t.Fatal(err)
	}
	taskID = start.TaskID
	for svc.Tools.DrainLongToolTasks(ctx) {
	}
	dto, err := svc.Tools.GetToolTaskFor(ctx, uc, taskID)
	if err != nil {
		t.Fatal(err)
	}
	if dto.State != taskStateCanceled {
		t.Fatalf("task = %s (error %q), want it canceled", dto.State, dto.Error)
	}
	raw, _ := json.Marshal(dto.Summary)
	var sum healthFixSummary
	if err := json.Unmarshal(raw, &sum); err != nil || sum.Attempted != 1 || sum.Rule != ruleMissingLyrics {
		t.Fatalf("summary %s (%v), want the one item it reached counted", raw, err)
	}
	mu.Lock()
	defer mu.Unlock()
	if asked != 1 {
		t.Errorf("the source was asked %d times, want once: the fix stops before the next item", asked)
	}
	if rows := inboxOf(t, ctx, svc, uc, "health-fix-finished"); len(rows) != 0 {
		t.Errorf("a canceled fix filed %+v", rows)
	}
}

// A catalog repair canceled between its steps stops there, keeping what
// the steps it finished counted and saying it was canceled.
func TestACanceledRepairKeepsTheStepsItRan(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	var taskID string
	svc.catalogRepairHook = func(step string) error {
		if step == catalogRepairArt {
			cancelTask(t, ctx, svc, uc, taskID)
		}
		return nil
	}
	task, err := svc.StartCatalogRepair(ctx, uc)
	if err != nil {
		t.Fatal(err)
	}
	taskID = task.ID
	for svc.Tools.DrainLongToolTasks(ctx) {
	}
	row := storedTask(t, ctx, svc, task.ID)
	if row.State != taskStateCanceled {
		t.Fatalf("task = %s (error %q), want it canceled", row.State, row.Error)
	}
	var sum catalogRepairSummary
	if err := json.Unmarshal([]byte(row.Summary), &sum); err != nil {
		t.Fatal(err)
	}
	if len(sum.Runs) != 1 || !slices.Equal(sum.Runs[0].Steps, []string{catalogRepairRollups, catalogRepairSortKeys, catalogRepairOrphans}) ||
		sum.Runs[0].Error != "canceled" || sum.SortKeysRewritten == nil || sum.After != nil {
		t.Fatalf("summary %s, want the three steps before the cancel counted and the run canceled", row.Summary)
	}
}

// A genre normalize canceled before it reads its first page changes
// nothing and ends canceled, saying what it did.
func TestACanceledNormalizeStopsBeforeItsNextPage(t *testing.T) {
	t.Parallel()
	f := newGenreFixture(t)
	task, err := f.svc.Reads.StartGenreNormalize(f.ctx, f.uc, false)
	if err != nil {
		t.Fatal(err)
	}
	var once sync.Once
	f.svc.Tools.activityHook = func(id string, a ToolTaskActivity) {
		if id == task.ID && a.Phase == activityProcessing {
			once.Do(func() { cancelTask(t, f.ctx, f.svc, f.uc, id) })
		}
	}
	f.drainTasks(t)
	row := storedTask(t, f.ctx, f.svc, task.ID)
	if row.State != taskStateCanceled || row.Summary == "" {
		t.Fatalf("task = %s (summary %q), want it canceled with what it did", row.State, row.Summary)
	}
	if got := f.genreOf(t, "Synonym"); got == "Hip Hop" {
		t.Errorf("a normalize canceled before its first page rewrote Synonym to %q", got)
	}
}

// An import canceled as it runs ends canceled, with what it wrote counted,
// and is on the record as canceled under who ordered it.
func TestACanceledImportIsOnTheRecord(t *testing.T) {
	t.Parallel()
	ctx, f := newMigrateFixture(t)
	asked := make(chan struct{}, 1)
	stall := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		select {
		case asked <- struct{}{}:
		default:
		}
		<-r.Context().Done()
	}))
	t.Cleanup(stall.Close)
	dto, err := f.svc.Migrate.StartMigration(ctx, f.uc, MigrationRequest{
		Source: "navidrome", ServerURL: stall.URL, Username: "demo", Password: "demo-pass", DryRun: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	done := make(chan struct{})
	go func() {
		defer close(done)
		f.svc.Tools.DrainToolTasks(ctx)
	}()
	select {
	case <-asked:
	case <-time.After(10 * time.Second):
		t.Fatal("the import never asked its source")
	}
	cancelTask(t, ctx, f.svc, f.uc, dto.ID)
	select {
	case <-done:
	case <-time.After(10 * time.Second):
		t.Fatal("the canceled import did not stop")
	}
	row, err := f.svc.db.ToolTaskByID(ctx, dto.ID)
	if err != nil || row.State != taskStateCanceled || row.Summary == "" {
		t.Fatalf("the task = %+v (%v), want it canceled with its counts", row, err)
	}
	runs := migrationRuns(t, ctx, f)
	if len(runs) != 1 || runs[0].Detail["canceled"] != true || runs[0].Detail["failed"] != nil || runs[0].ActorID != f.uc.ID {
		t.Fatalf("migration.run entries = %+v, want the one canceled run", runs)
	}
}

// A playlist sync canceled mid-batch ends canceled, listing the review
// entries it opened for what staged before the cancel.
func TestCancelingARunningSyncKeepsWhatStaged(t *testing.T) {
	t.Parallel()
	src := &stallingLister{eventfulSource{hold: "two", release: make(chan struct{}), fetching: make(chan string, 3)}}
	logs := &syncBuffer{}
	ctx, svc, uc := acquireFixture(t, src, loggingTo(logs))
	task, err := svc.Playlists.SyncPlaylistSourceNow(ctx, uc, boundPlaylist(t, ctx, svc, uc))
	if err != nil {
		t.Fatal(err)
	}
	ran := make(chan struct{})
	go func() {
		defer close(ran)
		svc.Tools.DrainSourceToolTasks(ctx)
	}()
	awaitFetch(t, &src.eventfulSource, "two")
	cancelTask(t, ctx, svc, uc, task.ID)
	select {
	case <-ran:
	case <-time.After(10 * time.Second):
		close(src.release)
		<-ran
		t.Fatal("the canceled sync did not stop")
	}
	row := storedTask(t, ctx, svc, task.ID)
	var results []string
	if err := json.Unmarshal([]byte(row.ResultPIDs), &results); err != nil {
		t.Fatal(err)
	}
	if row.State != taskStateCanceled || len(results) != 1 || len(taskParamsOf(&row).Entries) != 1 {
		t.Fatalf("sync = %s with results %v (error %q), want it canceled listing the first item's entry", row.State, results, row.Error)
	}
	if out := logs.String(); strings.Contains(out, "playlist sync failure") || strings.Contains(out, "playlist sync attempt failed") {
		t.Errorf("a canceled sync was taken as a failure:\n%s", out)
	}
	if !idle(ctx, svc) {
		t.Fatal("the worker ran the canceled sync again")
	}
}

// A canceled acquisition keeps what an earlier run of it staged and never
// gave a review entry: the cancel opens the entries the next run would
// have, and lists them.
func TestACanceledAcquisitionOpensWhatAnEarlierRunStaged(t *testing.T) {
	t.Parallel()
	src := &stagingSource{}
	src.answerThree(func(context.Context) error { panic("the run died") })
	ctx, svc, uc := acquireFixture(t, src)
	task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/playlist?list=PLthree", false, "music", "", "", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	func() {
		defer func() {
			if recover() == nil {
				t.Fatal("the run did not die")
			}
		}()
		drainOnce(t, ctx, svc)
	}()
	if n := uploadsWithoutEntry(t, ctx, svc); n != 2 {
		t.Fatalf("%d staged downloads without an entry after the run died, want the two it staged", n)
	}
	if dto := cancelTask(t, ctx, svc, uc, task.ID); dto.State != taskStateCanceled || len(dto.ResultPIDs) != 2 {
		t.Fatalf("the cancel answered %s listing %v, want it canceled listing the two entries", dto.State, dto.ResultPIDs)
	}
	if n := uploadsWithoutEntry(t, ctx, svc); n != 0 {
		t.Errorf("%d staged downloads still without an entry after the cancel", n)
	}
}

// cancelWhileStaging cancels a split of the chaptered fixture's book once
// its first piece is staged, while the run holds it: the run's other
// copies finish, and the commit it reaches next meets the cancel.
func cancelWhileStaging(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, book model.PID) string {
	t.Helper()
	task, err := svc.Tools.StartBookSplit(ctx, uc, apiPID(PrefixBook, book), false)
	if err != nil {
		t.Fatal(err)
	}
	asked := false
	svc.Tools.toolStepHook = func(step string) error {
		if step == "staging" && !asked {
			asked = true
			if dto := cancelTask(t, ctx, svc, uc, task.ID); !dto.CancelRequested {
				t.Errorf("the staging split asked to cancel reads %s, cancel requested %v", dto.State, dto.CancelRequested)
			}
		}
		return nil
	}
	t.Cleanup(func() { svc.Tools.toolStepHook = nil })
	return task.ID
}

// A split canceled while it stages its pieces ends canceled once they are
// staged: its commit is refused, the cancel takes the pieces back, and the
// task is not left to be finished.
func TestACancelWhileStagingWinsOverTheCommit(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, book, dir, _ := chapteredBookFixture(t)
	id := cancelWhileStaging(t, ctx, svc, uc, book)
	drainOnce(t, ctx, svc)
	row := storedTask(t, ctx, svc, id)
	if row.State != taskStateCanceled || row.Resumable || row.Error != "" {
		t.Fatalf("task = %s, resumable %v (error %q), want it canceled, never committed", row.State, row.Resumable, row.Error)
	}
	if left := hiddenLeft(t, dir); len(left) != 0 {
		t.Errorf("the canceled split left %v in the book's folder", left)
	}
	if names := namesIn(t, dir); !slices.Equal(names, []string{"The Chaptered Fixture.m4b"}) {
		t.Errorf("the book's folder holds %q, want the original alone", names)
	}
	if !idle(ctx, svc) {
		t.Fatal("the worker ran the canceled split again")
	}
}

// A canceled split whose folder will not let its staged pieces go ends
// canceled saying which files stay and where; clearing the task removes
// them once the folder allows it.
func TestACanceledSplitNamesTheFilesItCouldNotRemove(t *testing.T) {
	skipWithoutUnwritablePaths(t)
	t.Parallel()
	ctx, svc, uc, book, dir, _ := chapteredBookFixture(t)
	id := cancelWhileStaging(t, ctx, svc, uc, book)
	svc.Tools.drainHook = func(point, taskID string) {
		if point == "ran" && taskID == id {
			if err := os.Chmod(dir, 0o555); err != nil {
				t.Error(err)
			}
		}
	}
	t.Cleanup(func() { _ = os.Chmod(dir, 0o755) })
	drainOnce(t, ctx, svc)
	row := storedTask(t, ctx, svc, id)
	left := hiddenLeft(t, dir)
	if row.State != taskStateCanceled || len(left) < 2 {
		t.Fatalf("task = %s (error %q) with %v left, want it canceled and its pieces stuck", row.State, row.Error, left)
	}
	for _, path := range left {
		if !strings.Contains(row.Error, filepath.Base(path)) {
			t.Errorf("the error %q does not name %s", row.Error, filepath.Base(path))
		}
	}
	if !strings.Contains(row.Error, "The Chaptered Fixture") || !strings.Contains(row.Error, "clearing the task") {
		t.Errorf("the error %q does not say where they are and what clearing does", row.Error)
	}
	if rows := inboxOf(t, ctx, svc, uc, "tool-task-failed"); len(rows) != 0 {
		t.Errorf("a canceled split filed %+v", rows)
	}
	if err := os.Chmod(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := svc.Tools.DeleteToolTaskFor(ctx, uc, id); err != nil {
		t.Fatalf("clearing the canceled split: %v", err)
	}
	if left := hiddenLeft(t, dir); len(left) != 0 {
		t.Errorf("clearing left %v in the book's folder", left)
	}
}

// A task asked to cancel whose settle never landed (the server stopped
// between the two) is settled by the next lease of it, its attempts spent
// or not, and never run: the retire pass leaves it to the lease.
func TestAnAskedTaskNoRunHoldsIsSettledByTheNextLease(t *testing.T) {
	t.Parallel()
	src := &stagingSource{}
	ctx, svc, uc := acquireFixture(t, src)
	task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/playlist?list=PLthree", false, "music", "", "", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Now().UnixNano()
	for range toolTaskMaxAttempts {
		now += 2 * toolTaskLease.Nanoseconds()
		if _, err := svc.db.LeaseToolTask(ctx, now, toolTaskLease.Nanoseconds(), toolTaskMaxAttempts, wdb.TaskTypes{}); err != nil {
			t.Fatal(err)
		}
	}
	if asked, err := svc.db.RequestToolTaskCancel(ctx, task.ID); err != nil || !asked {
		t.Fatalf("asking = %v, %v", asked, err)
	}
	var points []string
	svc.Tools.drainHook = func(point, id string) { points = append(points, point) }
	if !svc.Tools.drainToolTasksAt(ctx, wdb.TaskTypes{}, now+2*toolTaskLease.Nanoseconds()) {
		t.Fatal("the worker found no task")
	}
	row := storedTask(t, ctx, svc, task.ID)
	if row.State != taskStateCanceled || row.Attempts != toolTaskMaxAttempts {
		t.Fatalf("task = %s after %d attempts (error %q), want it canceled, no attempt spent", row.State, row.Attempts, row.Error)
	}
	if len(points) != 0 || len(src.fetchCounts()) != 0 {
		t.Errorf("the settle passed %v and fetched %v, want the task never run", points, src.fetchCounts())
	}
}

// A path fix canceled while an organize run moves its chunk counts that
// chunk's moves, as its audit does, and says how many it moved.
func TestACanceledPathFixCountsTheChunkInHand(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _, pid := managedTrackFixture(t)
	start, err := svc.Health.StartHealthFix(ctx, uc, rulePathMismatch, []string{pid})
	if err != nil {
		t.Fatal(err)
	}
	var run model.PID
	svc.Health.awaitJobHook = func(runCtx context.Context, job model.PID, _ time.Duration, _ func(context.Context)) (*model.Job, error) {
		run = job
		waitForEnd(t, ctx, svc, job)
		cancelTask(t, ctx, svc, uc, start.TaskID)
		return nil, runCtx.Err()
	}
	for svc.Tools.DrainLongToolTasks(ctx) {
	}
	row := storedTask(t, ctx, svc, start.TaskID)
	if row.State != taskStateCanceled {
		t.Fatalf("task = %s (error %q), want it canceled", row.State, row.Error)
	}
	var sum healthFixSummary
	if err := json.Unmarshal([]byte(row.Summary), &sum); err != nil {
		t.Fatal(err)
	}
	if sum.Moved == nil || *sum.Moved != 1 || sum.Filled != 1 || sum.Attempted != 1 ||
		fmt.Sprint(sum.JobPIDs) != fmt.Sprint([]string{apiPID(PrefixJob, run)}) {
		t.Fatalf("summary %+v, want the track its run moved counted as moved", sum)
	}
}

// An import canceled while it waits to try again is on the record with
// what its earlier attempt wrote.
func TestAnImportCanceledWhileItWaitsCountsWhatItWrote(t *testing.T) {
	t.Parallel()
	ctx, f := newMigrateFixture(t)
	nav := newFakeNavidrome(t, "demo", "demo-pass")
	proxy := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.TrimSuffix(strings.TrimPrefix(r.URL.Path, "/rest/"), ".view") == "getAlbum" {
			// The starred album's members, read after the song stars
			// landed: a passing failure.
			http.Error(w, "busy", http.StatusBadGateway)
			return
		}
		resp, err := http.Get(nav.URL + r.URL.RequestURI())
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadGateway)
			return
		}
		defer resp.Body.Close()
		w.Header().Set("Content-Type", resp.Header.Get("Content-Type"))
		w.WriteHeader(resp.StatusCode)
		_, _ = io.Copy(w, resp.Body)
	}))
	t.Cleanup(proxy.Close)
	dto, err := f.svc.Migrate.StartMigration(ctx, f.uc, MigrationRequest{
		Source: "navidrome", ServerURL: proxy.URL, Username: "demo", Password: "demo-pass", Stars: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	if !f.svc.Tools.DrainToolTasks(ctx) {
		t.Fatal("the worker found no task")
	}
	if row, err := f.svc.db.ToolTaskByID(ctx, dto.ID); err != nil || row.State != taskStateRunning || row.WaitReason == "" {
		t.Fatalf("the task = %+v (%v), want it waiting to try again", row, err)
	}
	if got := cancelTask(t, ctx, f.svc, f.uc, dto.ID); got.State != taskStateCanceled {
		t.Fatalf("the cancel answered %s, want canceled", got.State)
	}
	runs := migrationRuns(t, ctx, f)
	if len(runs) != 1 || runs[0].Detail["canceled"] != true || runs[0].Detail["matched"] == float64(0) || runs[0].Detail["stars"] != float64(1) {
		t.Fatalf("migration.run entries = %+v, want the canceled run counting the star it wrote", runs)
	}
}

// An acquisition that fails once it opened review entries lists them, in
// its results and its summary, as a done or canceled one does: retired
// after its waits ran out, or failed on a verdict.
func TestAFailedAcquisitionListsTheEntriesItOpened(t *testing.T) {
	t.Parallel()
	listed := func(t *testing.T, ctx context.Context, svc *Library, id string) {
		t.Helper()
		row := storedTask(t, ctx, svc, id)
		var results []string
		if err := json.Unmarshal([]byte(row.ResultPIDs), &results); err != nil {
			t.Fatal(err)
		}
		if row.State != taskStateFailed || len(results) != 2 || !slices.Equal(results, taskParamsOf(&row).Entries) ||
			!slices.Equal(summaryEntries(t, toolTaskDTO(row).Summary), []string{"one", "two"}) {
			t.Fatalf("task = %s with results %v, summary %s (error %q), want it failed listing its two entries",
				row.State, results, row.Summary, row.Error)
		}
	}
	t.Run("retired", func(t *testing.T) {
		t.Parallel()
		src := &stagingSource{}
		src.stall.Store(true)
		ctx, svc, uc := acquireFixture(t, src)
		svc.Ingest.acquireItemBound = 300 * time.Millisecond
		task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/playlist?list=PLthree", false, "music", "", "", nil, nil)
		if err != nil {
			t.Fatal(err)
		}
		drainOnce(t, ctx, svc)
		spendAttempts(t, ctx, svc, task.ID, toolTaskMaxAttempts)
		svc.Tools.retireExhaustedToolTasks(ctx, time.Now().Add(time.Hour).UnixNano())
		listed(t, ctx, svc, task.ID)
	})
	t.Run("failed", func(t *testing.T) {
		t.Parallel()
		src := &stagingSource{}
		src.answerThree(func(context.Context) error {
			return catalogerr.Wrap(catalogerr.CodeIO, "fetch", waxtap.ErrVideoUnavailable)
		})
		ctx, svc, uc := acquireFixture(t, src)
		task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/playlist?list=PLthree", false, "music", "", "", nil, nil)
		if err != nil {
			t.Fatal(err)
		}
		drainOnce(t, ctx, svc)
		listed(t, ctx, svc, task.ID)
	})
}

// A download a sync staged and the person removed before its entry opened
// leaves the sync's record of it naming an upload that is gone; the next
// sync forgets that record, as it does a download the retention prune
// reclaimed, and downloads the entry again, which lands in review.
func TestASyncDownloadRemovedMidRunIsDownloadedByTheNextSync(t *testing.T) {
	t.Parallel()
	src := &stallingLister{}
	ctx, svc, uc := acquireFixture(t, src)
	mapRow := func() wdb.PlaylistSourceMapRow {
		rows, err := svc.db.PlaylistSourceMapFor(ctx, "youtube", []string{"one"})
		if err != nil {
			t.Fatal(err)
		}
		return rows["one"]
	}
	removed := ""
	src.answerThree(func(context.Context) error {
		removed = mapRow().UploadID
		return svc.Ingest.DeleteUpload(ctx, uc, removed)
	})
	pl := boundPlaylist(t, ctx, svc, uc)
	first, err := svc.Playlists.SyncPlaylistSourceNow(ctx, uc, pl)
	if err != nil {
		t.Fatal(err)
	}
	drainOnce(t, ctx, svc)
	if row := storedTask(t, ctx, svc, first.ID); row.State != taskStateDone || len(taskParamsOf(&row).Entries) != 2 {
		t.Fatalf("first sync = %s with entries %v (error %q), want it done with the other two", row.State, taskParamsOf(&row).Entries, row.Error)
	}
	if m := mapRow(); removed == "" || m.UploadID != removed || m.ItemPID != "" {
		t.Fatalf("the removed download's record = %+v, want it naming the removed upload %q", m, removed)
	}
	if sum := toolTaskDTO(storedTask(t, ctx, svc, first.ID)).Summary; sum["queued"] != float64(2) {
		t.Errorf("first sync's summary %v, want the two downloads still staged counted as queued", sum)
	}
	src.answerThree(nil)
	second, err := svc.Playlists.SyncPlaylistSourceNow(ctx, uc, pl)
	if err != nil {
		t.Fatal(err)
	}
	drainOnce(t, ctx, svc)
	row := storedTask(t, ctx, svc, second.ID)
	m := mapRow()
	up, uerr := svc.db.UploadByID(ctx, m.UploadID)
	if row.State != taskStateDone || m.UploadID == removed || uerr != nil || up.ReviewEntryID == "" ||
		!slices.Equal(taskParamsOf(&row).Entries, []string{up.ReviewEntryID}) {
		t.Fatalf("second sync = %s with entries %v (error %q); record %+v, upload %+v (%v); want the entry downloaded again and in review",
			row.State, taskParamsOf(&row).Entries, row.Error, m, up, uerr)
	}
	if n := src.fetchCounts()["https://tube.example/watch?v=one"]; n != 2 {
		t.Errorf("the removed entry was fetched %d times, want once by each sync", n)
	}
}

// A download the person removed mid-run is not counted as staged when the
// batch fails after it.
func TestARemovedDownloadIsNotCountedAsStaged(t *testing.T) {
	t.Parallel()
	src := &stagingSource{}
	ctx, svc, uc := acquireFixture(t, src)
	src.answerThree(func(context.Context) error {
		var id string
		if err := svc.db.Reader().QueryRowContext(ctx, `SELECT id FROM uploads WHERE file_name = 'one.mp3'`).Scan(&id); err != nil {
			return err
		}
		if err := svc.Ingest.DeleteUpload(ctx, uc, id); err != nil {
			return err
		}
		return catalogerr.Wrap(catalogerr.CodeIO, "fetch", waxtap.ErrVideoUnavailable)
	})
	task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/playlist?list=PLthree", false, "music", "", "", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	drainOnce(t, ctx, svc)
	if row := storedTask(t, ctx, svc, task.ID); row.State != taskStateFailed || !strings.HasPrefix(row.Error, "1 of 3 items staged before") {
		t.Fatalf("task = %s (error %q), want it failed counting the one download still staged", row.State, row.Error)
	}
	if got := cutShort([]fetchedItem{{Key: "a", Upload: "up-a"}, {Key: "b", Upload: "up-b", Dropped: true}, {Key: "c", Upload: "up-c", Dropped: true}},
		[]acquireItem{{GUID: "a"}, {GUID: "b"}, {GUID: "d"}}, errors.New("stopped")); got.staged != 1 || got.total != 3 {
		t.Errorf("cut short = %d of %d, want 1 of 3: neither removed download counted", got.staged, got.total)
	}
}

// An acquisition whose every download the person removed before its entry
// opened ends done with nothing filed: the download was made, and what
// became of it was the person's doing.
func TestAnAcquisitionWhoseDownloadsWereAllRemovedEndsDone(t *testing.T) {
	t.Parallel()
	src := &stagingSource{}
	ctx, svc, uc := acquireFixture(t, src)
	task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/watch?v=one", false, "music", "", "", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	removed := false
	svc.Tools.activityHook = func(id string, a ToolTaskActivity) {
		if id != task.ID || a.Phase != activityImporting || removed {
			return
		}
		row := storedTask(t, ctx, svc, id)
		fetched := taskParamsOf(&row).Fetched
		if len(fetched) != 1 {
			// The fetch's own importing, before the download is recorded.
			return
		}
		removed = true
		if err := svc.Ingest.DeleteUpload(context.WithoutCancel(ctx), uc, fetched[0].Upload); err != nil {
			t.Error(err)
		}
	}
	t.Cleanup(func() { svc.Tools.activityHook = nil })
	drainOnce(t, ctx, svc)
	if row := storedTask(t, ctx, svc, task.ID); !removed || row.State != taskStateDone || len(taskParamsOf(&row).Entries) != 0 {
		t.Fatalf("task = %s with entries %v (error %q), removed %v; want it done with none", row.State, taskParamsOf(&row).Entries, row.Error, removed)
	}
	if rows := inboxOf(t, ctx, svc, uc, "tool-task-failed"); len(rows) != 0 {
		t.Errorf("an acquisition whose download was removed filed %+v", rows)
	}
}

// A path fix canceled mid-chunk counts every item of the chunk in hand as
// attempted, as the same chunk finished does, held ones included.
func TestACanceledPathFixAttemptsItsWholeChunk(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, scope := untaggedBesideStrayFixture(t)
	start, err := svc.Health.StartHealthFix(ctx, uc, rulePathMismatch, scope)
	if err != nil {
		t.Fatal(err)
	}
	svc.Health.awaitJobHook = func(runCtx context.Context, job model.PID, _ time.Duration, _ func(context.Context)) (*model.Job, error) {
		waitForEnd(t, ctx, svc, job)
		cancelTask(t, ctx, svc, uc, start.TaskID)
		return nil, runCtx.Err()
	}
	for svc.Tools.DrainLongToolTasks(ctx) {
	}
	row := storedTask(t, ctx, svc, start.TaskID)
	var sum healthFixSummary
	if err := json.Unmarshal([]byte(row.Summary), &sum); row.State != taskStateCanceled || err != nil {
		t.Fatalf("task = %s with summary %q (%v), want it canceled", row.State, row.Summary, err)
	}
	if sum.Attempted != len(scope) {
		t.Errorf("summary %+v, want all %d items of the chunk attempted", sum, len(scope))
	}
}
