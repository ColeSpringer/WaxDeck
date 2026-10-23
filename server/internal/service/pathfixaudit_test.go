package service

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// pathFixEnds are the audit rows of path fixes' ends, newest first.
func pathFixEnds(t *testing.T, ctx context.Context, svc *Library) []map[string]any {
	t.Helper()
	page, err := svc.AuditEvents(ctx, wdb.AuditFilter{Action: "health.fix"}, "", 50)
	if err != nil {
		t.Fatal(err)
	}
	var out []map[string]any
	for _, e := range page.Events {
		if _, ok := e.Detail["moved"]; ok {
			out = append(out, e.Detail)
		}
	}
	return out
}

// stopAfterRun makes a path fix's attempt stop as the server does, once
// the organize run it waits on has ended, and answers that run's pid.
func stopAfterRun(t *testing.T, ctx context.Context, svc *Library, stop context.CancelFunc) *model.PID {
	t.Helper()
	var run model.PID
	svc.awaitJobHook = func(runCtx context.Context, job model.PID, _ time.Duration, _ func(context.Context)) (*model.Job, error) {
		run = job
		waitForEnd(t, ctx, svc, job)
		stop()
		return nil, runCtx.Err()
	}
	return &run
}

// A path fix's attempt that a stop cuts short is no end of the fix: it
// writes no audit row, and the attempt that finishes the fix writes the
// one row, naming the run the cut attempt made and counting what it
// moved, as does the fix's own summary.
func TestAPathFixCutByAStopIsAuditedOnceWhenItEnds(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _, pid := managedTrackFixture(t)
	start, err := svc.StartHealthFix(ctx, uc, rulePathMismatch, []string{pid})
	if err != nil {
		t.Fatal(err)
	}
	runCtx, stop := context.WithCancel(ctx)
	run := stopAfterRun(t, ctx, svc, stop)
	if err := attempt(t, runCtx, svc, 1); !errors.Is(err, context.Canceled) {
		t.Fatalf("the first attempt = %v, want it stopped", err)
	}
	svc.awaitJobHook = nil
	if ends := pathFixEnds(t, ctx, svc); len(ends) != 0 {
		t.Fatalf("audit rows after the stopped attempt = %v, want none", ends)
	}
	if err := attempt(t, ctx, svc, 2); err != nil {
		t.Fatalf("the rerun = %v, want it done", err)
	}
	cut := apiPID(PrefixJob, *run)
	sum := fixSummary(t, ctx, svc, uc, start.TaskID)
	if sum.Moved == nil || *sum.Moved != 1 || sum.Attempted != 1 || fmt.Sprint(sum.JobPIDs) != fmt.Sprint([]string{cut}) {
		t.Fatalf("summary %+v, want the track moved by the stopped attempt's run", sum)
	}
	ends := pathFixEnds(t, ctx, svc)
	if len(ends) != 1 || ends[0]["moved"] != float64(1) || fmt.Sprint(ends[0]["jobPids"]) != fmt.Sprint([]any{cut}) ||
		ends[0]["task"] != start.TaskID {
		t.Fatalf("audit rows = %v, want one naming the run and the move", ends)
	}
}

// A path fix whose attempts run out is audited once, as it ends, with
// what every attempt of it did: the run a stopped attempt made and the
// move that run landed.
func TestAPathFixWhoseAttemptsRanOutIsAuditedOnceWithItsTotals(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _, pid := managedTrackFixture(t)
	start, err := svc.StartHealthFix(ctx, uc, rulePathMismatch, []string{pid})
	if err != nil {
		t.Fatal(err)
	}
	runCtx, stop := context.WithCancel(ctx)
	run := stopAfterRun(t, ctx, svc, stop)
	if err := attempt(t, runCtx, svc, 1); !errors.Is(err, context.Canceled) {
		t.Fatalf("the first attempt = %v, want it stopped", err)
	}
	svc.awaitJobHook = nil
	spendAttempts(t, ctx, svc, start.TaskID, toolTaskMaxAttempts)
	svc.retireExhaustedToolTasks(ctx, time.Now().Add(time.Hour).UnixNano())
	if task := toolTask(t, ctx, svc, start.TaskID); task.State != taskStateFailed {
		t.Fatalf("task = %s, want it ended for its attempts", task.State)
	}
	ends := pathFixEnds(t, ctx, svc)
	if len(ends) != 1 || ends[0]["moved"] != float64(1) ||
		fmt.Sprint(ends[0]["jobPids"]) != fmt.Sprint([]any{apiPID(PrefixJob, *run)}) {
		t.Fatalf("audit rows = %v, want one naming the run and the move it landed", ends)
	}
}

// A path fix stopped part way goes on from its last finished chunk: the
// rerun does not plan what the stopped attempt finished, counts the item
// its cut chunk's run moved as moved, and the fix's totals cover both
// attempts, every run named.
func TestAPathFixRerunGoesOnFromItsLastChunk(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, stray := fillerLibrary(t)
	fillers, err := svc.lib.Query(ctx, query.New(query.EntityItems).Where("title", query.OpIs, "Filler 0").Build(), "")
	if err != nil || len(fillers) != 1 {
		t.Fatalf("fillers = %v (%v)", fillers, err)
	}
	scope := []string{stray, apiPID(PrefixTrack, fillers[0].PID)}
	start, err := svc.StartHealthFix(ctx, uc, rulePathMismatch, scope)
	if err != nil {
		t.Fatal(err)
	}
	// The nth attempt, leased once every earlier lease has run out.
	run := func(ctx context.Context, n int) (healthFixSummary, error) {
		t.Helper()
		at := time.Now().Add(time.Duration(n) * 2 * toolTaskLease).UnixNano()
		row, err := svc.db.LeaseToolTask(ctx, at, toolTaskLease.Nanoseconds(), toolTaskMaxAttempts,
			wdb.TaskTypes{Only: taskTypeHealthFix})
		if err != nil {
			t.Fatal(err)
		}
		var p toolTaskParams
		if err := json.Unmarshal([]byte(row.Params), &p); err != nil {
			t.Fatal(err)
		}
		return svc.fixPathScope(ctx, &row, &p, p.ItemPIDs, newToolProgress(svc, &row), 1)
	}

	// The second chunk's run moves its item, and the stop comes then.
	runCtx, stop := context.WithCancel(ctx)
	var runs []model.PID
	svc.awaitJobHook = func(runCtx context.Context, job model.PID, silence time.Duration, tick func(context.Context)) (*model.Job, error) {
		runs = append(runs, job)
		if len(runs) == 1 {
			return waitJob(runCtx, func(ctx context.Context) (*model.Job, error) { return svc.lib.Job(ctx, job) },
				time.Now, silence, tick)
		}
		waitForEnd(t, ctx, svc, job)
		stop()
		return nil, runCtx.Err()
	}
	if _, err := run(runCtx, 1); !errors.Is(err, context.Canceled) {
		t.Fatalf("the first attempt = %v, want it stopped", err)
	}
	if p := taskParams(t, ctx, svc, start.TaskID).PathFix; p == nil || p.Done != 1 || len(p.Moving) != 1 ||
		len(p.Sum.JobPIDs) != 2 {
		t.Fatalf("progress = %+v, want the first chunk done and the second's item and both runs kept", p)
	}

	svc.awaitJobHook = nil
	sum, err := run(ctx, 2)
	if err != nil {
		t.Fatal(err)
	}
	want := fmt.Sprint([]string{apiPID(PrefixJob, runs[0]), apiPID(PrefixJob, runs[1])})
	if sum.Attempted != 2 || sum.Moved == nil || *sum.Moved != 2 || len(sum.Skipped) != 0 || fmt.Sprint(sum.JobPIDs) != want {
		t.Fatalf("summary %+v, want both items moved, each counted once, by the two runs %s", sum, want)
	}
}
