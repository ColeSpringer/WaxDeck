package service

import (
	"context"
	"errors"
	"slices"
	"strings"
	"sync"
	"sync/atomic"
	"testing"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/enrich"
	"github.com/colespringer/waxbin/model"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// heldLookup is a lyrics provider whose lookup lasts until the run's
// context ends, and then until it is let go: the job stays running, a
// cancel asked for, for as long as a test needs to read it.
type heldLookup struct {
	asked, ended, release chan struct{}
	letGo                 func()
}

func newHeldLookup() *heldLookup {
	p := &heldLookup{asked: make(chan struct{}, 1), ended: make(chan struct{}, 1), release: make(chan struct{})}
	p.letGo = sync.OnceFunc(func() { close(p.release) })
	return p
}

func (p *heldLookup) Name() string                    { return "held" }
func (p *heldLookup) Capabilities() enrich.Capability { return enrich.CapLyrics }
func (p *heldLookup) Enrich(ctx context.Context, _ enrich.Request) (*enrich.Candidate, error) {
	select {
	case p.asked <- struct{}{}:
	default:
	}
	select {
	case <-ctx.Done():
	case <-p.release:
		return nil, context.Canceled
	}
	select {
	case p.ended <- struct{}{}:
	default:
	}
	<-p.release
	return nil, ctx.Err()
}

// heldCancels counts the cancels the service holds.
func heldCancels(svc *Library) int {
	svc.Jobs.jobs.mu.Lock()
	defer svc.Jobs.jobs.mu.Unlock()
	return len(svc.Jobs.jobs.held)
}

// An enrichment pass an administrator started is canceled: it reads as
// running with the cancel asked for while it winds down, a second ask
// answers the same, and it ends canceled, its cancel let go. Asked again
// once ended, it answers unchanged.
func TestACanceledPassWindsDownAndEndsCanceled(t *testing.T) {
	t.Parallel()
	p := newHeldLookup()
	ctx, svc, admin, _ := openLyricsFixture(t, p)
	apiJob, err := svc.Enrichment.RunEnrichment(ctx, admin, false, nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	_, pid, _ := parseAPIPID(apiJob)
	defer waitForJob(t, ctx, svc, pid)
	defer p.letGo()
	<-p.asked

	if job, err := svc.Jobs.Status(ctx, apiJob); err != nil || job.State != "running" || !job.Cancelable || job.CancelRequested {
		t.Fatalf("before the cancel = %+v (%v), want running and cancelable", job, err)
	}
	got, err := svc.Jobs.CancelFor(ctx, admin, apiJob)
	if err != nil {
		t.Fatal(err)
	}
	if got.State != "running" || !got.CancelRequested || got.Cancelable {
		t.Fatalf("the cancel's answer = %+v, want running with the cancel asked for", got)
	}
	<-p.ended
	if again, err := svc.Jobs.CancelFor(ctx, admin, apiJob); err != nil || again.State != "running" || !again.CancelRequested {
		t.Fatalf("a second cancel = %+v (%v), want the same", again, err)
	}
	listed, err := svc.Jobs.List(ctx, admin, 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(listed) == 0 || listed[0].PID != apiJob || !listed[0].CancelRequested || listed[0].Cancelable {
		t.Fatalf("listed = %+v, want the pass first, winding down", listed)
	}

	p.letGo()
	waitForJob(t, ctx, svc, pid)
	end, err := svc.Jobs.Status(ctx, apiJob)
	if err != nil {
		t.Fatal(err)
	}
	if end.State != "canceled" || end.CancelRequested || end.Cancelable {
		t.Fatalf("the ended pass = %+v, want canceled", end)
	}
	waitFor(t, func() bool { return heldCancels(svc) == 0 }, "the ended pass's cancel should be let go")
	if after, err := svc.Jobs.CancelFor(ctx, admin, apiJob); err != nil || after.State != "canceled" {
		t.Fatalf("a cancel of the ended pass = %+v (%v), want it unchanged", after, err)
	}
}

// The scheduler's pass is the server's own, and cancels as an
// administrator's does.
func TestTheScheduledPassIsCancelable(t *testing.T) {
	t.Parallel()
	p := newHeldLookup()
	ctx, svc, admin, _ := openLyricsFixture(t, p)
	if err := svc.Enrichment.RunScheduledEnrichment(ctx); err != nil {
		t.Fatal(err)
	}
	<-p.asked
	pid, running, err := svc.Jobs.runningJob(ctx, "enrich", 5)
	if err != nil || !running {
		t.Fatalf("no running pass (%v)", err)
	}
	defer waitForJob(t, ctx, svc, pid)
	defer p.letGo()
	apiJob := apiPID(PrefixJob, pid)
	if job, err := svc.Jobs.Status(ctx, apiJob); err != nil || !job.Cancelable {
		t.Fatalf("the scheduled pass = %+v (%v), want cancelable", job, err)
	}
	if _, err := svc.Jobs.CancelFor(ctx, admin, apiJob); err != nil {
		t.Fatal(err)
	}
	<-p.ended
	p.letGo()
	waitForJob(t, ctx, svc, pid)
	if job, err := svc.Jobs.Status(ctx, apiJob); err != nil || job.State != "canceled" {
		t.Fatalf("the scheduled pass = %+v (%v), want canceled", job, err)
	}
}

// A job that ends on its own lets go of its cancel: nothing is held past
// a job's end.
func TestAJobEndingOnItsOwnLetsGoOfItsCancel(t *testing.T) {
	t.Parallel()
	ctx, svc, admin, _ := openLyricsFixture(t, &lyricist{name: "a"})
	for range 3 {
		apiJob, err := svc.Enrichment.RunEnrichment(ctx, admin, false, nil, nil)
		if err != nil {
			t.Fatal(err)
		}
		_, pid, _ := parseAPIPID(apiJob)
		waitForJob(t, ctx, svc, pid)
		if job, err := svc.Jobs.Status(ctx, apiJob); err != nil || job.State != "done" || job.Cancelable || job.CancelRequested {
			t.Fatalf("the ended pass = %+v (%v), want done and not cancelable", job, err)
		}
	}
	waitFor(t, func() bool { return heldCancels(svc) == 0 }, "every ended pass's cancel should be let go")
}

// A running job this process holds no cancel for, as one the command line
// submits, is refused with its reason, as is anyone but an administrator; a
// pid naming no job is not found.
func TestACancelTheServerCannotGiveIsRefused(t *testing.T) {
	t.Parallel()
	a := gatedLyricist("a")
	ctx, svc, admin, _ := openLyricsFixture(t, a)
	acct, err := svc.Identity.CreateAccount(ctx, AccountCreate{Username: "listener", Password: "correct-horse"})
	if err != nil {
		t.Fatal(err)
	}
	listener, err := svc.Grants.UserCtxFor(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	pid, err := svc.lib.StartEnrich(ctx, waxbin.EnrichOptions{})
	if err != nil {
		t.Fatal(err)
	}
	defer waitForJob(t, ctx, svc, pid)
	defer a.open()
	<-a.asked
	apiJob := apiPID(PrefixJob, pid)

	if job, err := svc.Jobs.Status(ctx, apiJob); err != nil || job.Cancelable {
		t.Fatalf("a pass the server holds no cancel for = %+v (%v), want not cancelable", job, err)
	}
	_, err = svc.Jobs.CancelFor(ctx, admin, apiJob)
	if KindOf(err) != KindConflict || RefusalParams(err)["reason"] != refusalJobNotHeld {
		t.Fatalf("its cancel = %v (%v), want a conflict naming %s", err, RefusalParams(err), refusalJobNotHeld)
	}
	if _, err := svc.Jobs.CancelFor(ctx, listener, apiJob); KindOf(err) != KindForbidden {
		t.Errorf("a non-administrator's cancel = %v, want forbidden", err)
	}
	if _, err := svc.Jobs.CancelFor(ctx, admin, "jb-01JZX5N8QW3F4V9T2B7KDEXAMPL"); KindOf(err) != KindNotFound {
		t.Errorf("a cancel of no job = %v, want not-found", err)
	}
	if job, err := svc.lib.Job(ctx, pid); err != nil || job.State != model.JobRunning {
		t.Errorf("after the refused cancels the pass = %+v (%v), want it running on", job, err)
	}
}

// Only a scan, an analyze pass and an enrichment pass stop part way; every
// other kind runs to its end, which its refusal says whoever started it,
// as it does for a start restricted to run to its end.
func TestWhichKindsCancel(t *testing.T) {
	t.Parallel()
	for kind, want := range map[string]string{
		"scan": refusalJobNotHeld, "analyze": refusalJobNotHeld, "enrich": refusalJobNotHeld,
		"set-kind": refusalJobRunsToEnd, "remove-root": refusalJobRunsToEnd,
		"organize": refusalJobRunsToEnd, "organize-undo": refusalJobRunsToEnd,
		"import": refusalJobRunsToEnd, "delete": refusalJobRunsToEnd, "restore": refusalJobRunsToEnd,
		"empty-trash": refusalJobRunsToEnd, "purge-trash": refusalJobRunsToEnd, "some-new-kind": refusalJobRunsToEnd,
	} {
		err := uncancelable(kind, false)
		if KindOf(err) != KindConflict || RefusalParams(err)["reason"] != want {
			t.Errorf("%s: refusal = %v (%v), want a conflict naming %s", kind, err, RefusalParams(err), want)
		}
		// A start restricted to run to its end says so, whatever its kind.
		if err := uncancelable(kind, true); KindOf(err) != KindConflict || RefusalParams(err)["reason"] != refusalJobRunsToEnd {
			t.Errorf("%s run to its end: refusal = %v (%v), want a conflict naming %s", kind, err, RefusalParams(err), refusalJobRunsToEnd)
		}
	}
}

// A cancel an administrator asked for is theirs, so its end files nothing
// in their inbox, a scan's as an enrichment's; a pass whose context ends
// without one, as at a shutdown, still tells them the server stopped under
// it. A health fix is the exception: its notice says what its re-check
// found (TestACanceledFixReadsAsCanceled).
func TestARequestedCancelFilesNoNotification(t *testing.T) {
	t.Parallel()
	for _, asked := range []bool{true, false} {
		p := newHeldLookup()
		ctx, svc, admin, _ := openLyricsFixture(t, p)
		apiJob, err := svc.Enrichment.RunEnrichment(ctx, admin, false, nil, nil)
		if err != nil {
			t.Fatal(err)
		}
		_, pid, _ := parseAPIPID(apiJob)
		<-p.asked
		if asked {
			if _, err := svc.Jobs.CancelFor(ctx, admin, apiJob); err != nil {
				t.Fatal(err)
			}
		} else {
			svc.Jobs.jobs.mu.Lock()
			svc.Jobs.jobs.held[pid].cancel()
			svc.Jobs.jobs.mu.Unlock()
		}
		<-p.ended
		p.letGo()
		waitForJob(t, ctx, svc, pid)
		waitFor(t, func() bool {
			origins, err := svc.db.JobOrigins(ctx)
			return err == nil && len(origins) == 0
		}, "the pass's end should be settled")
		rows := inboxOf(t, ctx, svc, admin, "job-finished", "job-failed")
		switch {
		case asked && len(rows) > 0:
			t.Errorf("after a requested cancel the inbox holds %+v, want nothing", rows)
		case !asked && (len(rows) != 1 || rows[0].Event != "job-failed" || rows[0].Body != "Enrichment: the server stopped before it finished"):
			t.Errorf("after a stop nobody asked for the inbox holds %+v, want the server's stop", rows)
		}

		// A scan's end, settled as the follower settles it.
		scan := model.NewPID()
		if err := svc.db.InsertJobOrigin(ctx, wdb.JobOrigin{PID: string(scan), UserID: admin.ID, CreatedAtNS: 1}); err != nil {
			t.Fatal(err)
		}
		if asked {
			if err := svc.db.AskJobOriginCancel(ctx, string(scan)); err != nil {
				t.Fatal(err)
			}
		}
		svc.Jobs.settleJobOrigin(ctx, &model.Job{PID: scan, Kind: "scan", State: model.JobCanceled, Error: "interrupted before it finished"})
		after := inboxOf(t, ctx, svc, admin, "job-finished", "job-failed")
		switch {
		case asked && len(after) > 0:
			t.Errorf("after a scan's requested cancel the inbox holds %+v, want nothing", after)
		case !asked && (len(after) != 2 || !slices.ContainsFunc(after, func(r InboxNotification) bool { return r.Body == "Scan: the server stopped before it finished" })):
			t.Errorf("after a scan's stop nobody asked for the inbox holds %+v, want the server's stop", after)
		}
	}
}

// A health fix whose pass an administrator canceled still files its
// notice, read as canceled, never as a failure: what its re-check found is
// news to the one who canceled it.
func TestACanceledFixReadsAsCanceled(t *testing.T) {
	t.Parallel()
	p := newHeldLookup()
	ctx, svc, uc, _ := openLyricsFixture(t, p)
	if err := svc.Health.RunHealthSweep(ctx); err != nil {
		t.Fatal(err)
	}
	start, err := svc.Health.StartHealthFix(ctx, uc, ruleMissingLyrics, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer p.letGo()
	<-p.asked
	if _, err := svc.Jobs.CancelFor(ctx, uc, start.JobPID); err != nil {
		t.Fatal(err)
	}
	<-p.ended
	p.letGo()
	row := waitForInbox(t, ctx, svc, uc, "health-fix-finished")
	if !strings.HasPrefix(row.Body, "The enrichment pass was canceled. ") || strings.Contains(row.Body, "failed") {
		t.Fatalf("row = %+v, want the pass read as canceled", row)
	}
	if rows := inboxOf(t, ctx, svc, uc, "job-finished", "job-failed"); len(rows) > 0 {
		t.Errorf("the inbox also holds %+v, want the fix's notice alone", rows)
	}
}

// A replaced catalog does not let go of a job's cancel the follower then
// reads still running; one it no longer holds is let go.
func TestACatalogReplaceKeepsTheCancelOfAJobStillRunning(t *testing.T) {
	t.Parallel()
	p := newHeldLookup()
	ctx, svc, admin, _ := openLyricsFixture(t, p)
	apiJob, err := svc.Enrichment.RunEnrichment(ctx, admin, false, nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	_, pid, _ := parseAPIPID(apiJob)
	defer waitForJob(t, ctx, svc, pid)
	defer p.letGo()
	<-p.asked
	var ghost atomic.Bool
	svc.Jobs.jobs.hold(model.NewPID(), func() { ghost.Store(true) })

	svc.Jobs.jobs.forget()
	waitFor(t, ghost.Load, "a held job the catalog does not hold should be let go")
	if job, err := svc.Jobs.Status(ctx, apiJob); err != nil || job.State != "running" || !job.Cancelable {
		t.Fatalf("after the replace the pass = %+v (%v), want it running on, cancelable", job, err)
	}
	if n := heldCancels(svc); n != 1 {
		t.Fatalf("%d cancels held, want the running pass's alone", n)
	}
}

// A start is held by the kind WaxBin gives its job, whatever its caller:
// a kind change started this way is never held, runs to its end, and its
// context is let go once it ends.
func TestOnlyACancelableKindIsHeld(t *testing.T) {
	t.Parallel()
	ctx, svc, _, track := openLyricsFixture(t, &lyricist{name: "a"})
	var got context.Context
	pid, err := svc.Jobs.startCancelable(ctx, wdb.JobOrigin{}, func(ctx context.Context) (model.PID, error) {
		got = ctx
		return svc.lib.StartSetItemKind(ctx, []model.PID{track}, model.KindBook, waxbin.KindOptions{})
	})
	if err != nil {
		t.Fatal(err)
	}
	if n := heldCancels(svc); n != 0 {
		t.Fatalf("a kind change was held (%d held)", n)
	}
	if job, err := svc.Jobs.Status(ctx, apiPID(PrefixJob, pid)); err != nil || job.Cancelable {
		t.Fatalf("the kind change = %+v (%v), want it not cancelable", job, err)
	}
	waitForJob(t, ctx, svc, pid)
	if job, err := svc.lib.Job(ctx, pid); err != nil || job.State != model.JobDone {
		t.Fatalf("the kind change = %+v (%v), want it run to its end", job, err)
	}
	waitFor(t, func() bool { return got.Err() != nil }, "the ended kind change's context should be let go")
}

// An end that lands before its start returns, and that the follower read
// first, is told once, to its starter: the origin is recorded before the
// job is followed or held.
func TestAnEndBeforeItsStartReturnsIsTold(t *testing.T) {
	t.Parallel()
	ctx, svc, admin, _ := openLyricsFixture(t, &lyricist{name: "a"})
	if _, err := svc.Jobs.startCancelable(ctx, wdb.JobOrigin{UserID: admin.ID}, func(ctx context.Context) (model.PID, error) {
		pid, err := svc.lib.StartEnrich(ctx, waxbin.EnrichOptions{})
		if err != nil {
			return pid, err
		}
		waitForJob(t, ctx, svc, pid)
		svc.Jobs.followJob(pid)
		waitFor(t, func() bool { return !svc.Jobs.jobs.pending() }, "the follower should read the end")
		return pid, nil
	}); err != nil {
		t.Fatal(err)
	}
	waitForInbox(t, ctx, svc, admin, "job-finished")
	waitFor(t, func() bool {
		origins, err := svc.db.JobOrigins(ctx)
		return err == nil && len(origins) == 0
	}, "the end should be settled")
	if rows := inboxOf(t, ctx, svc, admin, "job-finished", "job-failed"); len(rows) != 1 {
		t.Fatalf("the inbox holds %+v, want the end told once", rows)
	}
}

// A requested cancel rides its origin row: a settle that keeps the origin
// for a repeat files nothing, and the repeat, after the claims are released
// as at the next start, files nothing either, while a health fix whose
// re-check a stop cut short still reads canceled.
func TestARequestedCancelKeptForARepeatFilesNothing(t *testing.T) {
	t.Parallel()
	p := newHeldLookup()
	ctx, svc, admin, _ := openLyricsFixture(t, p)
	apiJob, err := svc.Enrichment.RunEnrichment(ctx, admin, false, nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	_, pass, _ := parseAPIPID(apiJob)
	defer waitForJob(t, ctx, svc, pass)
	defer p.letGo()
	settled := make(chan struct{}, 1)
	hook := func(j *model.Job, done bool) {
		if done && j.PID == pass {
			select {
			case settled <- struct{}{}:
			default:
			}
		}
	}
	svc.Jobs.jobFinishedHook.Store(&hook)
	// The pass's origin cannot be dropped, so its settle keeps it.
	if _, err := svc.db.Writer().ExecContext(ctx, `CREATE TRIGGER refuse BEFORE DELETE ON job_origins
		WHEN OLD.pid = '`+string(pass)+`' BEGIN SELECT RAISE(ABORT, 'refused'); END`); err != nil {
		t.Fatal(err)
	}
	<-p.asked
	if _, err := svc.Jobs.CancelFor(ctx, admin, apiJob); err != nil {
		t.Fatal(err)
	}
	if o, err := svc.db.JobOriginGet(ctx, string(pass)); err != nil || !o.CancelAsked {
		t.Fatalf("the origin after the cancel = %+v (%v), want the cancel recorded", o, err)
	}
	<-p.ended
	p.letGo()
	waitForJob(t, ctx, svc, pass)
	<-settled
	svc.Jobs.jobFinishedHook.Store(nil)
	if !svc.Jobs.hasOrigin(ctx, pass) {
		t.Fatal("the pass's origin went, want it kept for a repeat")
	}

	// A fix's origin, its cancel asked; a stop cuts its re-check short.
	fix := model.NewPID()
	if err := svc.db.InsertJobOrigin(ctx, wdb.JobOrigin{PID: string(fix), UserID: admin.ID, Rule: ruleMissingLyrics, CreatedAtNS: 1}); err != nil {
		t.Fatal(err)
	}
	if err := svc.db.AskJobOriginCancel(ctx, string(fix)); err != nil {
		t.Fatal(err)
	}
	stopped, stop := context.WithCancel(ctx)
	stop()
	svc.Jobs.settleJobOrigin(stopped, &model.Job{PID: fix, Kind: "enrich", State: model.JobCanceled, Error: "interrupted before it finished"})
	if !svc.Jobs.hasOrigin(ctx, fix) {
		t.Fatal("the fix's origin went, want it kept for a repeat")
	}
	if rows := inboxOf(t, ctx, svc, admin, "job-finished", "job-failed", "health-fix-finished"); len(rows) > 0 {
		t.Fatalf("before the repeat the inbox holds %+v, want nothing", rows)
	}

	// The next start: claims released, every origin settled again.
	if _, err := svc.db.Writer().ExecContext(ctx, `DROP TRIGGER refuse`); err != nil {
		t.Fatal(err)
	}
	if err := svc.db.ReleaseJobOriginClaims(ctx); err != nil {
		t.Fatal(err)
	}
	svc.Jobs.settleJobOrigin(ctx, &model.Job{PID: fix, Kind: "enrich", State: model.JobCanceled, Error: "interrupted before it finished"})
	svc.Jobs.settleOrigins(ctx)
	waitFor(t, func() bool {
		origins, err := svc.db.JobOrigins(ctx)
		return err == nil && len(origins) == 0
	}, "the repeat should settle both ends")
	if rows := inboxOf(t, ctx, svc, admin, "job-finished", "job-failed"); len(rows) > 0 {
		t.Errorf("after the repeat the inbox holds %+v, want nothing for a requested cancel", rows)
	}
	row := waitForInbox(t, ctx, svc, admin, "health-fix-finished")
	if !strings.HasPrefix(row.Body, "The enrichment pass was canceled. ") || strings.Contains(row.Body, "failed") {
		t.Errorf("the fix's row = %+v, want the pass read as canceled", row)
	}
}

// failStartRead makes the read a start makes of its job fail.
func failStartRead(svc *Library) {
	hook := func(model.PID) error { return errors.New("the catalog could not answer") }
	svc.Jobs.startReadHook.Store(&hook)
}

// A pass whose start could not read it is ruled at the cancel, by the kind
// the cancel reads: a kind that stops is canceled through the context its
// start kept, as a held one, and its end files nothing; asked as a kind
// that runs to its end, it is left running.
func TestAStartWhoseReadFailedIsRuledAtTheCancel(t *testing.T) {
	t.Parallel()
	p := newHeldLookup()
	ctx, svc, admin, _ := openLyricsFixture(t, p)
	failStartRead(svc)
	pid, err := svc.Jobs.startCancelable(ctx, wdb.JobOrigin{UserID: admin.ID}, func(ctx context.Context) (model.PID, error) {
		return svc.lib.StartEnrich(ctx, waxbin.EnrichOptions{})
	})
	if err != nil {
		t.Fatal(err)
	}
	defer waitForJob(t, ctx, svc, pid)
	defer p.letGo()
	<-p.asked
	apiJob := apiPID(PrefixJob, pid)

	running, err := svc.lib.Job(ctx, pid)
	if err != nil {
		t.Fatal(err)
	}
	asKindChange := *running
	asKindChange.Kind = "set-kind"
	if out := svc.Jobs.jobOut(&asKindChange); out.Cancelable {
		t.Errorf("read as a kind change = %+v, want not cancelable", out)
	}
	if svc.Jobs.jobs.askCancel(pid, "set-kind") {
		t.Fatal("a cancel reading a kind that runs to its end canceled it")
	}
	if job, err := svc.Jobs.Status(ctx, apiJob); err != nil || job.State != "running" || !job.Cancelable || job.CancelRequested {
		t.Fatalf("the pass = %+v (%v), want running and cancelable", job, err)
	}

	got, err := svc.Jobs.CancelFor(ctx, admin, apiJob)
	if err != nil {
		t.Fatalf("its cancel = %v (%v)", err, RefusalParams(err))
	}
	if got.State != "running" || !got.CancelRequested || got.Cancelable {
		t.Fatalf("the cancel's answer = %+v, want running with the cancel asked for", got)
	}
	<-p.ended
	p.letGo()
	waitForJob(t, ctx, svc, pid)
	if job, err := svc.Jobs.Status(ctx, apiJob); err != nil || job.State != "canceled" {
		t.Fatalf("the pass = %+v (%v), want canceled", job, err)
	}
	waitFor(t, func() bool {
		svc.Jobs.jobs.mu.Lock()
		defer svc.Jobs.jobs.mu.Unlock()
		return len(svc.Jobs.jobs.held) == 0 && len(svc.Jobs.jobs.bound) == 0
	}, "the ended pass's context should be let go")
	waitFor(t, func() bool {
		origins, err := svc.db.JobOrigins(ctx)
		return err == nil && len(origins) == 0
	}, "the pass's end should be settled")
	if rows := inboxOf(t, ctx, svc, admin, "job-finished", "job-failed"); len(rows) > 0 {
		t.Errorf("after a requested cancel the inbox holds %+v, want nothing", rows)
	}
}

// newestJob names the newest job of kind.
func newestJob(t *testing.T, ctx context.Context, svc *Library, kind string) model.PID {
	t.Helper()
	jobs, err := svc.lib.Jobs(ctx, 10)
	if err != nil {
		t.Fatal(err)
	}
	for _, j := range jobs {
		if j.Kind == kind {
			return j.PID
		}
	}
	t.Fatalf("no %s job", kind)
	return ""
}

// The rescan a library's media change starts runs to its end, since half
// done it leaves files in the old medium for good; a forced rescan an
// administrator starts is still canceled. Both starts' reads fail and the
// follower is held off, so each stays as its start left it.
func TestAMediaChangeRescanRunsToItsEnd(t *testing.T) {
	t.Parallel()
	ctx, svc, admin, _ := openLyricsFixture(t, &lyricist{name: "a"})
	libs, err := svc.Roots.Libraries(ctx)
	if err != nil || len(libs) != 1 {
		t.Fatalf("libraries = %+v (%v), want the fixture root", libs, err)
	}
	to := "audiobook"
	if libs[0].Media == to {
		to = "music"
	}
	failStartRead(svc)
	svc.Jobs.jobs.refresh.Lock()
	unlocked := false
	unlock := func() {
		if !unlocked {
			unlocked = true
			svc.Jobs.jobs.refresh.Unlock()
		}
	}
	defer unlock()

	info, err := svc.Roots.SetLibraryMedia(ctx, admin, libs[0].PID, to)
	if err != nil || !info.ScanStarted {
		t.Fatalf("the media change = %+v (%v), want its rescan started", info, err)
	}
	media := newestJob(t, ctx, svc, "scan")
	if cancelable, _ := svc.Jobs.jobs.cancelState(media, "scan"); cancelable {
		t.Error("the media change's rescan reads cancelable")
	}
	if svc.Jobs.jobs.askCancel(media, "scan") {
		t.Error("the media change's rescan was canceled")
	}
	waitForJob(t, ctx, svc, media)
	if job, err := svc.lib.Job(ctx, media); err != nil || job.State != model.JobDone {
		t.Fatalf("the media change's rescan = %+v (%v), want it run to its end", job, err)
	}

	if _, err := svc.RescanFor(ctx, admin, true); err != nil {
		t.Fatal(err)
	}
	forced := newestJob(t, ctx, svc, "scan")
	if forced == media {
		t.Fatal("the forced rescan made no job")
	}
	defer waitForJob(t, ctx, svc, forced)
	if cancelable, _ := svc.Jobs.jobs.cancelState(forced, "scan"); !cancelable {
		t.Error("the forced rescan reads not cancelable")
	}
	if !svc.Jobs.jobs.askCancel(forced, "scan") {
		t.Error("the forced rescan was not canceled")
	}
	unlock()
	waitFor(t, func() bool {
		svc.Jobs.jobs.mu.Lock()
		defer svc.Jobs.jobs.mu.Unlock()
		return len(svc.Jobs.jobs.held) == 0 && len(svc.Jobs.jobs.bound) == 0
	}, "both rescans' contexts should be let go")
}

// A start restricted to run to its end is never held, whatever its kind or
// whether its start read it: it reads not cancelable, its cancel is
// refused as one that runs to its end, and it is left running, its
// context let go once it ends.
func TestAStartThatRunsToItsEndIsNeverCanceled(t *testing.T) {
	t.Parallel()
	for _, readFails := range []bool{false, true} {
		p := newHeldLookup()
		ctx, svc, admin, _ := openLyricsFixture(t, p)
		if readFails {
			failStartRead(svc)
		}
		var got context.Context
		pid, err := svc.Jobs.startRunToEnd(ctx, wdb.JobOrigin{UserID: admin.ID}, func(ctx context.Context) (model.PID, error) {
			got = ctx
			return svc.lib.StartEnrich(ctx, waxbin.EnrichOptions{})
		})
		if err != nil {
			t.Fatal(err)
		}
		<-p.asked
		apiJob := apiPID(PrefixJob, pid)
		if n := heldCancels(svc); n != 0 {
			t.Errorf("read fails %v: the pass was held (%d held)", readFails, n)
		}
		if job, err := svc.Jobs.Status(ctx, apiJob); err != nil || job.State != "running" || job.Cancelable {
			t.Errorf("read fails %v: the pass = %+v (%v), want running and not cancelable", readFails, job, err)
		}
		_, err = svc.Jobs.CancelFor(ctx, admin, apiJob)
		if KindOf(err) != KindConflict || RefusalParams(err)["reason"] != refusalJobRunsToEnd {
			t.Errorf("read fails %v: its cancel = %v (%v), want a conflict naming %s", readFails, err, RefusalParams(err), refusalJobRunsToEnd)
		}
		if job, err := svc.lib.Job(ctx, pid); err != nil || job.State != model.JobRunning || got.Err() != nil {
			t.Errorf("read fails %v: after the refused cancel the pass = %+v (%v), want it running on", readFails, job, err)
		}
		if o, err := svc.db.JobOriginGet(ctx, string(pid)); err == nil && o.CancelAsked {
			t.Errorf("read fails %v: the origin records a cancel", readFails)
		}
		p.letGo()
		waitForJob(t, ctx, svc, pid)
		waitFor(t, func() bool { return got.Err() != nil }, "the ended pass's context should be let go")
	}
}
