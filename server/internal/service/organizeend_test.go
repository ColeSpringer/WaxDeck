package service

import (
	"context"
	"errors"
	"fmt"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/organize"
	"github.com/colespringer/waxbin/query"

	"github.com/colespringer/waxdeck/fixtures"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// fillerLibrary is a managed library of a misplaced track among 300
// misplaced fillers, scanned: enough files that a forced rescan, or a run
// over all of them, is still going a moment after it starts. It answers
// the track's api pid.
func fillerLibrary(t *testing.T) (context.Context, *Library, *UserCtx, string) {
	t.Helper()
	ctx, svc, uc := openEnrichFixture(t, func(c *Config) {
		c.Roots[0].Managed = true
		if _, err := fixtures.Generate(c.Roots[0].Path, fixtures.Spec{
			Name: "stray", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
			Tags: map[string]string{"TITLE": "Stray", "ARTIST": "Nomad", "ALBUM": "Wander", "TRACKNUMBER": "1"},
		}); err != nil {
			t.Fatal(err)
		}
		specs := make([]fixtures.Spec, 300)
		for i := range specs {
			specs[i] = fixtures.Spec{
				Name: fmt.Sprintf("filler-%03d", i), Codec: fixtures.CodecFLAC, Duration: time.Second,
				Tags: map[string]string{"TITLE": fmt.Sprintf("Filler %d", i), "ARTIST": "Padding", "ALBUM": "Slow Scan"},
			}
		}
		if _, err := fixtures.Generate(filepath.Join(c.Roots[0].Path, "filler"), specs...); err != nil {
			t.Fatal(err)
		}
	})
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	stray, err := svc.lib.Query(ctx, query.New(query.EntityItems).Where("title", query.OpIs, "Stray").Build(), "")
	if err != nil || len(stray) != 1 {
		t.Fatalf("stray = %v (%v)", stray, err)
	}
	return ctx, svc, uc, apiPID(PrefixTrack, stray[0].PID)
}

// startForcedRescan starts a rescan that rereads every file, and waits
// until it holds the file-mutation scope.
func startForcedRescan(t *testing.T, ctx context.Context, svc *Library) model.PID {
	t.Helper()
	scan, err := svc.lib.StartScan(ctx, waxbin.ScanRequest{Force: true})
	if err != nil {
		t.Fatal(err)
	}
	for deadline := time.Now().Add(10 * time.Second); ; time.Sleep(5 * time.Millisecond) {
		j, err := svc.lib.Job(ctx, scan)
		if err != nil {
			t.Fatal(err)
		}
		if j.State == model.JobRunning {
			return scan
		}
		if time.Now().After(deadline) {
			t.Fatalf("the rescan is %s, not running", j.State)
		}
	}
}

// waitForEnd waits a job out, however long a loaded machine takes.
func waitForEnd(t *testing.T, ctx context.Context, svc *Library, pid model.PID) {
	t.Helper()
	for deadline := time.Now().Add(2 * time.Minute); ; time.Sleep(20 * time.Millisecond) {
		j, err := svc.lib.Job(ctx, pid)
		if err != nil {
			t.Fatal(err)
		}
		if j.State != model.JobRunning {
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("job %s still running", pid)
		}
	}
}

// startedRun is the running job of kind a request started, once its
// starter is on record.
func startedRun(t *testing.T, ctx context.Context, svc *Library, kind string) model.PID {
	t.Helper()
	for deadline := time.Now().Add(30 * time.Second); ; time.Sleep(time.Millisecond) {
		origins, err := svc.db.JobOrigins(ctx)
		if err != nil {
			t.Fatal(err)
		}
		for _, o := range origins {
			if j, err := svc.lib.Job(ctx, model.PID(o.PID)); err == nil && j.Kind == kind && j.State == model.JobRunning {
				return j.PID
			}
		}
		if time.Now().After(deadline) {
			t.Fatalf("no %s job started", kind)
		}
	}
}

// waitForAudit is the newest audit row of action, once one is written.
func waitForAudit(t *testing.T, ctx context.Context, svc *Library, action string) map[string]any {
	t.Helper()
	for deadline := time.Now().Add(30 * time.Second); ; time.Sleep(20 * time.Millisecond) {
		page, err := svc.AuditEvents(ctx, wdb.AuditFilter{Action: action}, "", 10)
		if err != nil {
			t.Fatal(err)
		}
		if len(page.Events) > 0 {
			if len(page.Events) > 1 {
				t.Fatalf("audit %s = %d rows, want one", action, len(page.Events))
			}
			return page.Events[0].Detail
		}
		if time.Now().After(deadline) {
			t.Fatalf("no %s audit row", action)
		}
	}
}

// waitLong polls cond for as long as a loaded machine can take to settle a
// run of hundreds of files.
func waitLong(t *testing.T, cond func() bool, what string) {
	t.Helper()
	for deadline := time.Now().Add(time.Minute); !cond(); time.Sleep(20 * time.Millisecond) {
		if time.Now().After(deadline) {
			t.Fatal(what)
		}
	}
}

// An apply whose request goes away while its run goes on is still
// audited with what the run moved, and the moved items leave the path
// rule, when the run ends.
func TestAnApplyItsRequestLeftIsStillAuditedAndRechecked(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := fillerLibrary(t)
	if err := svc.RunHealthSweep(ctx); err != nil {
		t.Fatal(err)
	}
	if counts, err := svc.db.HealthRuleCounts(ctx); err != nil || counts[rulePathMismatch] < 100 {
		t.Fatalf("path-mismatch = %d (%v), want the misplaced files", counts[rulePathMismatch], err)
	}
	reqCtx, cancel := context.WithCancel(ctx)
	answered := make(chan error, 1)
	go func() {
		_, err := svc.ApplyOrganize(reqCtx, uc, "", nil)
		answered <- err
	}()
	job := startedRun(t, ctx, svc, "organize")
	cancel()
	if err := <-answered; !errors.Is(err, context.Canceled) {
		t.Fatalf("apply = %v, want its request canceled under the run", err)
	}
	waitForEnd(t, ctx, svc, job)
	ran, err := svc.JobStatus(ctx, apiPID(PrefixJob, job))
	if err != nil || ran.Organize == nil || ran.Organize.Moved == 0 {
		t.Fatalf("run = %+v (%v), want what it moved", ran, err)
	}
	if d := waitForAudit(t, ctx, svc, "organize.apply"); d["jobPid"] != ran.PID ||
		d["moved"] != float64(ran.Organize.Moved) || d["state"] != string(model.JobDone) {
		t.Fatalf("audit = %v, want the run and the %d files it moved", d, ran.Organize.Moved)
	}
	waitLong(t, func() bool {
		counts, err := svc.db.HealthRuleCounts(ctx)
		return err == nil && counts[rulePathMismatch] == 0
	}, "the moved items off the path rule")
	if row := waitForInbox(t, ctx, svc, uc, "job-finished"); row.TargetPID != apiPID(PrefixJob, job) {
		t.Errorf("inbox = %+v, want the run's end", row)
	}
}

// An undo whose request goes away is still audited, and asks for the
// sweep that flags the files it moved back, when it ends.
func TestAnUndoItsRequestLeftIsStillAuditedAndAsksForASweep(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := fillerLibrary(t)
	rep, err := svc.ApplyOrganize(ctx, uc, "", nil)
	if err != nil || rep.Moved < 100 {
		t.Fatalf("apply = %+v (%v), want the misplaced files moved", rep, err)
	}
	if svc.SweepRequested(ctx) {
		t.Fatal("a sweep was asked for before the undo")
	}
	reqCtx, cancel := context.WithCancel(ctx)
	answered := make(chan error, 1)
	go func() {
		_, err := svc.UndoOrganize(reqCtx, uc, rep.JobPID)
		answered <- err
	}()
	job := startedRun(t, ctx, svc, "organize-undo")
	cancel()
	if err := <-answered; !errors.Is(err, context.Canceled) {
		t.Fatalf("undo = %v, want its request canceled under the run", err)
	}
	waitForEnd(t, ctx, svc, job)
	if d := waitForAudit(t, ctx, svc, "organize.undo"); d["jobPid"] != apiPID(PrefixJob, job) ||
		d["undoneJob"] != rep.JobPID || d["moved"] != float64(rep.Moved) {
		t.Fatalf("audit = %v, want the undo, the run it undid and what it moved back", d)
	}
	waitLong(t, func() bool { return svc.SweepRequested(ctx) }, "a sweep asked for")
}

// A path fix that meets another job holding the file-mutation scope says
// the catalog was busy, rather than that the move failed.
func TestAPathFixMeetingABusyCatalogSaysSo(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, stray := fillerLibrary(t)
	scan := startForcedRescan(t, ctx, svc)
	start, err := svc.StartHealthFix(ctx, uc, rulePathMismatch, []string{stray})
	if err != nil {
		t.Fatal(err)
	}
	sum := fixSummary(t, ctx, svc, uc, start.TaskID)
	if j, err := svc.lib.Job(ctx, scan); err != nil || j.State != model.JobRunning {
		t.Skipf("the rescan ended (%v) before the fix met it", err)
	}
	if sum.Moved == nil || *sum.Moved != 0 || sum.Failed != 0 || sum.Skipped[catalogBusyReason] != 1 {
		t.Fatalf("summary %+v, want the item skipped for a busy catalog", sum)
	}
	if row := waitForInbox(t, ctx, svc, uc, "health-fix-finished"); !strings.Contains(row.Body, "catalog busy 1") {
		t.Errorf("body = %q, want the busy catalog named", row.Body)
	}
	waitForEnd(t, ctx, svc, scan)
}

// A run is let go once its heartbeat has not moved for the bound, as the
// waiter's own clock measures it from the last change it saw, however old
// the heartbeat's own stamp reads; one that keeps beating is waited out.
func TestAWaitLetsGoOfARunThatStoppedReporting(t *testing.T) {
	t.Parallel()
	clock := time.Unix(1000, 0)
	reads := 0
	// A stamp from long ago: wall-clock arithmetic would let go at once.
	silent := func(context.Context) (*model.Job, error) {
		reads++
		clock = clock.Add(40 * time.Minute)
		return &model.Job{PID: "J", State: model.JobRunning, StartedAt: 1, HeartbeatAt: 1}, nil
	}
	_, err := waitJob(context.Background(), silent, func() time.Time { return clock }, time.Hour, nil)
	if !errors.Is(err, errJobSilent) || reads != 3 {
		t.Fatalf("silent run = %v after %d reads, want let go on the third", err, reads)
	}

	reads = 0
	beating := func(context.Context) (*model.Job, error) {
		reads++
		clock = clock.Add(50 * time.Minute)
		state := model.JobRunning
		if reads == 5 {
			state = model.JobDone
		}
		return &model.Job{PID: "J", State: state, StartedAt: 1, HeartbeatAt: int64(reads)}, nil
	}
	j, err := waitJob(context.Background(), beating, func() time.Time { return clock }, time.Hour, nil)
	if err != nil || j.State != model.JobDone || reads != 5 {
		t.Fatalf("beating run = %v (%v) after %d reads, want waited out to done", j, err, reads)
	}
}

// A path fix waits on its run with the silence bound, and counts the run's
// moves failed once the run stops reporting.
func TestAPathFixLetsGoOfASilentRun(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _, pid := managedTrackFixture(t)
	var bound time.Duration
	svc.awaitJobHook = func(_ context.Context, job model.PID, silence time.Duration, _ func(context.Context)) (*model.Job, error) {
		bound = silence
		return &model.Job{PID: job, Kind: "organize", State: model.JobRunning}, errJobSilent
	}
	start, err := svc.StartHealthFix(ctx, uc, rulePathMismatch, []string{pid})
	if err != nil {
		t.Fatal(err)
	}
	sum := fixSummary(t, ctx, svc, uc, start.TaskID)
	if bound != pathFixJobSilence || bound < time.Hour {
		t.Fatalf("the fix waited with a bound of %v, want %v and at least an hour", bound, pathFixJobSilence)
	}
	if sum.Moved == nil || *sum.Moved != 0 || sum.Failed != 1 || len(sum.JobPIDs) != 1 {
		t.Fatalf("summary %+v, want the item failed with its run named", sum)
	}
	_, run, _ := parseAPIPID(sum.JobPIDs[0])
	waitForEnd(t, ctx, svc, run)
}

// startedJob is a running job of kind, as the catalog lists it.
func startedJob(t *testing.T, ctx context.Context, svc *Library, kind string) model.PID {
	t.Helper()
	for deadline := time.Now().Add(30 * time.Second); ; time.Sleep(time.Millisecond) {
		jobs, err := svc.lib.Jobs(ctx, 20)
		if err != nil {
			t.Fatal(err)
		}
		for _, j := range jobs {
			if j.Kind == kind && j.State == model.JobRunning {
				return j.PID
			}
		}
		if time.Now().After(deadline) {
			t.Fatalf("no %s job started", kind)
		}
	}
}

// A run whose starter could not be recorded is still settled for them by
// the process, however its request fares: audited and told.
func TestARunWhoseStarterCouldNotBeRecordedIsStillSettled(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := fillerLibrary(t)
	svc.jobOriginInsertHook = func(context.Context, wdb.JobOrigin) error {
		return errors.New("the database is locked")
	}
	reqCtx, cancel := context.WithCancel(ctx)
	answered := make(chan error, 1)
	go func() {
		_, err := svc.ApplyOrganize(reqCtx, uc, "", nil)
		answered <- err
	}()
	job := startedJob(t, ctx, svc, "organize")
	cancel()
	if err := <-answered; !errors.Is(err, context.Canceled) {
		t.Fatalf("apply = %v, want its request canceled under the run", err)
	}
	waitForEnd(t, ctx, svc, job)
	if d := waitForAudit(t, ctx, svc, "organize.apply"); d["jobPid"] != apiPID(PrefixJob, job) || d["moved"] == float64(0) {
		t.Fatalf("audit = %v, want the run and what it moved", d)
	}
	if row := waitForInbox(t, ctx, svc, uc, "job-finished"); row.TargetPID != apiPID(PrefixJob, job) {
		t.Errorf("inbox = %+v, want the run's end", row)
	}
}

// A run whose starter's record failed keeps trying it while the run goes
// on, so once one lands, a stop before the run ends leaves the run to the
// next start, which settles it as any other.
func TestAnUnrecordedRunKeepsTryingItsRecordWhileItRuns(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _, _ := managedTrackFixture(t)
	_, sc, err := svc.organizePlanFor(ctx, "", nil)
	if err != nil {
		t.Fatal(err)
	}
	pid, err := svc.lib.RunOrganize(svc.procCtx, sc.q, sc.opts)
	if err != nil {
		t.Fatal(err)
	}
	waitForEnd(t, ctx, svc, pid)
	var tries atomic.Int32
	svc.jobOriginInsertHook = func(ctx context.Context, o wdb.JobOrigin) error {
		if tries.Add(1) <= 2 {
			return errors.New("the database is locked")
		}
		return svc.db.InsertJobOrigin(ctx, o)
	}
	// The run reads as going on until its record lands, and the process
	// stops then.
	waiting, stop := context.WithCancel(ctx)
	defer stop()
	svc.awaitJobHook = func(ctx context.Context, job model.PID, _ time.Duration, tick func(context.Context)) (*model.Job, error) {
		for deadline := time.Now().Add(10 * time.Second); time.Now().Before(deadline); time.Sleep(10 * time.Millisecond) {
			if tick != nil {
				tick(ctx)
			}
			if has, err := svc.db.HasJobOrigin(ctx, string(job)); err == nil && has {
				stop()
				return nil, ctx.Err()
			}
		}
		return nil, errors.New("the record never landed")
	}
	svc.settleUnrecorded(waiting, wdb.JobOrigin{PID: string(pid), UserID: uc.ID, CreatedAtNS: time.Now().UnixNano()})
	if n := tries.Load(); n != 3 {
		t.Fatalf("the record was tried %d times, want until it landed, on the third", n)
	}
	svc.settleOrigins(ctx)
	if d := waitForAudit(t, ctx, svc, "organize.apply"); d["jobPid"] != apiPID(PrefixJob, pid) {
		t.Fatalf("audit = %v, want the run", d)
	}
	if row := waitForInbox(t, ctx, svc, uc, "job-finished"); row.TargetPID != apiPID(PrefixJob, pid) {
		t.Errorf("inbox = %+v, want the run's end", row)
	}
}

// A run that ended before its starter's record landed, its end already
// read by the follower with no one to tell, is settled once the record
// lands, with no request left to do it.
func TestARunThatEndedBeforeItsStarterWasRecordedIsSettled(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _, _ := managedTrackFixture(t)
	_, sc, err := svc.organizePlanFor(ctx, "", nil)
	if err != nil {
		t.Fatal(err)
	}
	pid, err := svc.lib.RunOrganize(svc.procCtx, sc.q, sc.opts)
	if err != nil {
		t.Fatal(err)
	}
	waitForEnd(t, ctx, svc, pid)
	svc.followJob(pid)
	waitFor(t, func() bool { return !svc.jobs.pending() }, "the follower should read the run's end")
	svc.recordStarter(ctx, uc, pid, nil)
	if d := waitForAudit(t, ctx, svc, "organize.apply"); d["jobPid"] != apiPID(PrefixJob, pid) {
		t.Fatalf("audit = %v, want the run", d)
	}
	if row := waitForInbox(t, ctx, svc, uc, "job-finished"); row.TargetPID != apiPID(PrefixJob, pid) {
		t.Errorf("inbox = %+v, want the run's end", row)
	}
}

// A run killed outright left no report, so its audit takes what its
// journal committed rather than nothing.
func TestARunKilledOutrightIsAuditedWithWhatItsJournalCommitted(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _, _ := managedTrackFixture(t)
	rep, err := svc.ApplyOrganize(ctx, uc, "", nil)
	if err != nil || rep.Moved != 1 {
		t.Fatalf("apply = %+v (%v)", rep, err)
	}
	_, bare, _ := parseAPIPID(rep.JobPID)
	e := svc.finishOrganizeJob(ctx, wdb.JobOrigin{UserID: uc.ID}, &model.Job{PID: bare, Kind: "organize", State: model.JobCrashed})
	if e == nil || e.Action != "organize.apply" || !strings.Contains(e.Detail, `"moved":1`) ||
		!strings.Contains(e.Detail, `"state":"crashed"`) {
		t.Fatalf("audit = %+v, want the crashed run with the move its journal holds", e)
	}
}

// An apply's report names the item behind each held file, by its code and
// where the file is in its library, as the preview does.
func TestAnApplyReportNamesItsHolds(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := openEnrichFixture(t, func(c *Config) {
		c.Roots[0].Managed = true
		for i, name := range []string{"twin-a", "twin-b"} {
			if _, err := fixtures.Generate(c.Roots[0].Path, fixtures.Spec{
				Name: name, Codec: fixtures.CodecFLAC, Duration: time.Duration(3+i) * time.Second,
				Tags: map[string]string{"TITLE": "Twin", "ARTIST": "Pair", "ALBUM": "Doubles", "TRACKNUMBER": "1"},
			}); err != nil {
				t.Fatal(err)
			}
		}
	})
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	plan, err := svc.PreviewOrganize(ctx, uc, "", nil)
	if err != nil || len(plan.Holds) != 1 {
		t.Fatalf("preview holds = %+v (%v), want the second twin", plan.Holds, err)
	}
	rep, err := svc.ApplyOrganize(ctx, uc, "", nil)
	if err != nil || rep.Moved != 1 || rep.Held != 1 || len(rep.Holds) != 1 {
		t.Fatalf("apply = %+v (%v), want one twin moved and one held", rep, err)
	}
	h := rep.Holds[0]
	if h.Code != string(organize.HoldCollision) || !strings.HasPrefix(h.ItemPID, PrefixTrack+"-") ||
		h.ItemPID != plan.Holds[0].ItemPID || filepath.IsAbs(h.From) || h.From != plan.Holds[0].From ||
		h.To != plan.Holds[0].To || h.Reason == "" {
		t.Fatalf("hold = %+v, want the preview's hold %+v", h, plan.Holds[0])
	}
	job, err := svc.JobStatus(ctx, rep.JobPID)
	if err != nil || job.Organize == nil || job.Organize.Held != 1 || job.Organize.Moved != 1 {
		t.Fatalf("job = %+v (%v), want its tally to count the hold", job, err)
	}
}

// The scheduled prune lets go of the organize journal past the task
// retention window, and keeps it when retention is off.
func TestThePruneLetsTheJournalGoPastTheTaskWindow(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newAdminFixture(t)
	var asked []time.Duration
	svc.journalPruneHook = func(_ context.Context, age time.Duration) (int, error) {
		asked = append(asked, age)
		return 0, nil
	}
	st, err := svc.AdminSettingsGet(ctx)
	if err != nil {
		t.Fatal(err)
	}
	st.TaskRetentionDays = 0
	if _, err := svc.AdminSettingsPut(ctx, admin, st); err != nil {
		t.Fatal(err)
	}
	if err := svc.RunPrune(ctx); err != nil {
		t.Fatal(err)
	}
	if len(asked) != 0 {
		t.Fatalf("pruned the journal past %v with retention off", asked)
	}
	st.TaskRetentionDays = 7
	if _, err := svc.AdminSettingsPut(ctx, admin, st); err != nil {
		t.Fatal(err)
	}
	if err := svc.RunPrune(ctx); err != nil {
		t.Fatal(err)
	}
	if len(asked) != 1 || asked[0] != 7*24*time.Hour {
		t.Fatalf("pruned past %v, want once, past seven days", asked)
	}
}

// An undo's progress is news as it runs, as the run it undoes is.
func TestAnUndoAnnouncesItsProgress(t *testing.T) {
	t.Parallel()
	now := time.Now()
	j := model.Job{Kind: "organize-undo", State: model.JobRunning, Progress: 0.1}
	if !jobNews(nil, j, now, 0) {
		t.Fatal("a running undo's first read is no news")
	}
	seen := &jobSeen{state: model.JobRunning, bucket: progressBucket(0.1), at: now}
	j.Progress = 0.6
	if !jobNews(seen, j, now, 0) {
		t.Fatal("an undo's progress is no news")
	}
}
