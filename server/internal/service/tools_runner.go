package service

import (
	"cmp"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// The task runner: the drain loop, retries and holds, one task's run and
// the engine gate, with the scratch directory and the failure test a run
// uses.

// longToolTasks are the task types one run of which can take hours, a
// health fix and a catalog repair: they get a worker of their own, which
// runs them one at a time, since an acquisition or a sync queued behind
// one would wait as long.
var longToolTasks = []string{taskTypeHealthFix, taskTypeCatalogRepair}

// DrainToolTasks retires exhausted tasks and works one leased task other
// than a long one; false means the queue is idle so the caller can sleep.
func (l *Tools) DrainToolTasks(ctx context.Context) bool {
	return l.drainToolTasks(ctx, wdb.TaskTypes{Except: longToolTasks})
}

// DrainLongToolTasks is DrainToolTasks for the long tasks.
func (l *Tools) DrainLongToolTasks(ctx context.Context) bool {
	return l.drainToolTasks(ctx, wdb.TaskTypes{Only: longToolTasks})
}

func (l *Tools) drainToolTasks(ctx context.Context, types wdb.TaskTypes) bool {
	return l.drainToolTasksAt(ctx, types, time.Now().UnixNano())
}

// drainToolTasksAt is drainToolTasks as of now, which a test sets past
// the leases it holds.
func (l *Tools) drainToolTasksAt(ctx context.Context, types wdb.TaskTypes, now int64) bool {
	// A task run against a suspended catalog spends an attempt on nothing.
	if l.library.Maintenance() {
		return false
	}
	l.retireExhaustedToolTasks(ctx, now)
	row, err := l.db.LeaseToolTask(ctx, now, toolTaskLease.Nanoseconds(), toolTaskMaxAttempts, types)
	if err != nil {
		if !errors.Is(err, wdb.ErrNotFound) {
			l.log.Warn("leasing tool task", "err", err)
		}
		return false
	}
	// Only the first lease is a state change (queued -> running); a re-lease
	// after a transient failure leaves the task running, so re-notifying would
	// make every curation client refetch on each retry for no change. Terminal
	// transitions notify separately (completion below, exhaustion above).
	if row.Attempts <= 1 {
		l.notifyToolTask(ctx, row.ID)
	}
	runCtx, cancel := context.WithTimeout(ctx, toolRunTimeoutFor(row.Type))
	err = l.runToolTask(runCtx, &row)
	cancel()
	if err != nil {
		var wait *toolRetry
		switch {
		case errors.Is(err, errToolParked):
			// The run parked its task, which says why; nothing to record.
		case errors.As(err, &wait):
			l.deferToolTask(ctx, &row, wait)
		case permanentToolErr(err):
			l.failToolTask(ctx, &row, err)
		case ctx.Err() != nil:
			// The server is stopping, which is no failure of the task's:
			// the lease runs out and the task runs again once it is back.
		case row.Attempts >= toolTaskMaxAttempts && !row.Resumable:
			// A task whose run must be finished ends only by its run's own
			// endings, never by a count of attempts: its lease runs out
			// and it runs again, as the lease and the retire pass allow.
			l.failToolTask(ctx, &row, err)
		default:
			// Transient (a timeout, an engine request cut off): the row
			// stays leased and untouched; the lease expires and the
			// attempts machinery re-runs it, or FailExhaustedToolTasks
			// retires it.
			l.log.Warn("tool task attempt failed", "task", row.ID, "type", row.Type,
				"attempt", row.Attempts, "err", err)
		}
	}
	return true
}

// toolRetry is a failure a run waits out rather than fails on: what it
// put in the library stays as it is, and the task comes back after the
// delay, the attempt not counted. reason names the wait for a client.
type toolRetry struct {
	after  time.Duration
	err    error
	reason string
}

// errToolParked is a run that parked its task rather than run again.
var errToolParked = errors.New("the task is parked")

// ToolTaskFinished reports whether a task state is terminal: done,
// failed, or parked, which counts as failed. A finished task is never
// run again, and only a finished one may be deleted, swept or pruned.
func ToolTaskFinished(state string) bool {
	return state == taskStateDone || state == taskStateFailed || state == taskStateParked
}

func (r *toolRetry) Error() string { return r.err.Error() }
func (r *toolRetry) Unwrap() error { return r.err }

// toolBackoff is how long a run waits after its nth wait in a row: a
// quarter minute, doubling, at most half an hour.
func toolBackoff(n int) time.Duration {
	d := 15 * time.Second
	for i := 1; i < n && d < 30*time.Minute; i++ {
		d *= 2
	}
	return min(d, 30*time.Minute)
}

// deferToolTask hands a waiting task back until its delay is out, counted
// from when the run ended, saying why it waits, and tells its watchers.
func (l *Tools) deferToolTask(ctx context.Context, t *wdb.ToolTask, wait *toolRetry) {
	ctx = context.WithoutCancel(ctx)
	l.log.Info("tool task waits", "task", t.ID, "type", t.Type, "for", wait.after, "err", wait.err)
	until := time.Now().Add(wait.after).UnixNano()
	if err := l.db.DeferToolTask(ctx, t.ID, until, toolFailure(wait.err).Msg, cmp.Or(wait.reason, "other")); err != nil {
		l.log.Warn("deferring tool task", "task", t.ID, "err", err)
	}
	l.notifyToolTaskProgress(ctx, t.ID)
}

// holdToolTask marks a task as one a run in this process holds, which the
// retire pass leaves, and renews its lease until the returned release:
// the lease covers the whole run, every step and every wait in it.
func (l *Tools) holdToolTask(taskID string) func() {
	l.toolRunsMu.Lock()
	if l.toolRuns == nil {
		l.toolRuns = map[string]int{}
	}
	l.toolRuns[taskID]++
	l.toolRunsMu.Unlock()
	every := l.toolLeaseEvery
	if every <= 0 {
		every = toolLeaseRenew
	}
	stop, done := make(chan struct{}), make(chan struct{})
	started := l.workers != nil && l.procCtx != nil && l.workers.GoOnce(l.procCtx, "tool-lease", func(ctx context.Context) error {
		defer close(done)
		tick := time.NewTicker(every)
		defer tick.Stop()
		for {
			select {
			case <-ctx.Done():
				return nil
			case <-stop:
				return nil
			case <-tick.C:
				until := time.Now().Add(toolTaskLease).UnixNano()
				if err := l.db.RenewToolTaskLease(ctx, taskID, until); err != nil {
					l.log.Warn("renewing tool task lease", "task", taskID, "err", err)
				}
			}
		}
	})
	return func() {
		close(stop)
		if started {
			<-done
		}
		l.toolRunsMu.Lock()
		if l.toolRuns[taskID]--; l.toolRuns[taskID] <= 0 {
			delete(l.toolRuns, taskID)
		}
		l.toolRunsMu.Unlock()
	}
}

// heldToolTasks are the tasks a run in this process holds.
func (l *Tools) heldToolTasks() []string {
	l.toolRunsMu.Lock()
	defer l.toolRunsMu.Unlock()
	out := make([]string, 0, len(l.toolRuns))
	for id := range l.toolRuns {
		out = append(out, id)
	}
	return out
}

// retireExhaustedToolTasks fails every task whose attempts ran out with
// its last lease, as of now, but for those a run holds and those whose
// run must be finished, which the lease keeps taking.
func (l *Tools) retireExhaustedToolTasks(ctx context.Context, now int64) {
	ids, err := l.db.FailExhaustedToolTasks(ctx, now, toolTaskMaxAttempts, l.heldToolTasks())
	if err != nil {
		l.log.Warn("retiring exhausted tool tasks", "err", err)
		return
	}
	for _, id := range ids {
		t, err := l.db.ToolTaskByID(ctx, id)
		if err == nil {
			l.settleRetired(ctx, &t)
		}
		l.Migrate.settleMigrationExport(ctx, id)
		l.scrubTaskSecrets(ctx, id)
		l.notifyToolTask(ctx, id)
		if err == nil {
			l.notifyFileToolEnd(ctx, &t)
			l.taskEnded(ctx, &t)
		}
	}
}

// runToolTask executes one leased task to completion.
func (l *Tools) runToolTask(ctx context.Context, t *wdb.ToolTask) error {
	defer l.holdToolTask(t.ID)()
	// What a wait said is old news once the task runs again.
	t.Error = ""
	var p toolTaskParams
	if err := json.Unmarshal([]byte(t.Params), &p); err != nil {
		return fmt.Errorf("%w: bad task params: %v", errToolPermanent, err)
	}
	var results []string
	var err error
	switch {
	case t.Type == taskTypeBookMerge:
		results, err = l.runBookMerge(ctx, t, p)
	case t.Type == taskTypeBookSplit:
		results, err = l.runBookSplit(ctx, t, p)
	case t.Type == taskTypeCueSplit:
		results, err = l.runCueSplit(ctx, t, p)
	case t.Type == taskTypeAcquire:
		results, err = l.Ingest.runAcquire(ctx, t, p)
	case t.Type == taskTypePlaylistSync:
		results, err = l.Playlists.runPlaylistSync(ctx, t, p)
	case t.Type == taskTypeGenreNormalize:
		err = l.Reads.runGenreNormalize(ctx, t)
	case t.Type == taskTypeHealthFix:
		err = l.Health.runHealthFixTask(ctx, t, p)
	case t.Type == taskTypeCatalogRepair:
		err = l.library.runCatalogRepair(ctx, t)
	case strings.HasPrefix(t.Type, taskTypeMigratePrefix):
		err = l.Migrate.runMigrationTask(ctx, t)
	default:
		err = fmt.Errorf("%w: unknown task type %q", errToolPermanent, t.Type)
	}
	if err != nil {
		return err
	}
	// Recorded whatever happens to the attempt now: the work is done.
	ctx = context.WithoutCancel(ctx)
	l.recordToolTaskDone(ctx, t, results)
	// Before the scrub, which drops an export id once the upload it
	// names is gone: settling is what makes that true.
	l.Migrate.settleMigrationExport(ctx, t.ID)
	l.scrubTaskSecrets(ctx, t.ID)
	l.notifyToolTask(ctx, t.ID)
	l.taskEnded(ctx, t)
	return nil
}

// errEngineAway is the streaming engine gone since the task was queued.
var errEngineAway = errors.New("streaming engine unavailable")

// engineAwayErr reports a failure that is the streaming engine being
// away, which passes once it answers again.
func engineAwayErr(err error) bool {
	return errors.Is(err, errEngineAway) || errors.Is(err, flow.ErrEngineDown)
}

// errNoEngine is a tool's engine work on a server that now runs without
// one: no engine is coming back to wait on.
var errNoEngine = &Error{Kind: KindFeature, Err: errToolPermanent,
	Msg: "this needs the streaming engine, which this server runs without"}

// engineUp gates a tool's engine work. An engine configured but away
// comes back, which the run waits out without spending an attempt
// (engineAwayErr); a server started without one fails the work at once.
// Only the engine work waits on it: a book tool whose outputs are already
// staged finishes without it.
func (l *Tools) engineUp() error {
	if l.flowJobs == nil {
		return errNoEngine
	}
	if !l.flowJobs.JobsSupported() {
		return errEngineAway
	}
	return nil
}

// workspace creates the task's scratch directory under staging.
func (l *Tools) workspace(taskID string) (string, error) {
	dir := filepath.Join(l.Ingest.stagingDir, "tools", taskID)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", &Error{Kind: KindInternal, Err: err}
	}
	return dir, nil
}

// taskAccount resolves the account a task acts for, named who in the
// failure. One that is gone or can no longer sign in fails the task for
// good; a failed read says nothing about the account and comes back as
// it is, so the task runs again.
func (l *Tools) taskAccount(ctx context.Context, userID, who string) (*UserCtx, error) {
	uc, err := l.Grants.UserCtxByID(ctx, userID)
	if KindOf(err) == KindNotFound {
		return nil, fmt.Errorf("%w: %s is gone or disabled", errToolPermanent, who)
	}
	return uc, err
}

// permanentToolErr reports whether a failure is worth retrying: engine
// refusals (4xx), catalog validation errors, and job-level failures are
// permanent; transport trouble and timeouts are not.
func permanentToolErr(err error) bool {
	if errors.Is(err, errToolPermanent) {
		return true
	}
	if flow.PermanentJobErr(err) {
		return true
	}
	switch KindOf(err) {
	case KindInvalid, KindConflict, KindNotFound, KindFormat:
		return true
	}
	return false
}
