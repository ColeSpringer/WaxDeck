package service

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// addAdmin makes a second administrator.
func addAdmin(t *testing.T, ctx context.Context, svc *Library, name string) *UserCtx {
	t.Helper()
	acct, err := svc.CreateAccount(ctx, AccountCreate{
		Username: name, Password: "correct-horse", Roles: []string{"admin"},
	})
	if err != nil {
		t.Fatal(err)
	}
	uc, err := svc.UserCtx(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	return uc
}

// inboxOf is every row in one account's inbox with an event among events.
func inboxOf(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, events ...string) []InboxNotification {
	t.Helper()
	page, err := svc.Notifications(ctx, uc, "", 100)
	if err != nil {
		t.Fatal(err)
	}
	var out []InboxNotification
	for _, n := range page.Notifications {
		for _, e := range events {
			if n.Event == e {
				out = append(out, n)
			}
		}
	}
	return out
}

// waitForInbox waits for an account's inbox to hold a row for event.
func waitForInbox(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, event string) InboxNotification {
	t.Helper()
	deadline := time.Now().Add(10 * time.Second)
	for {
		if rows := inboxOf(t, ctx, svc, uc, event); len(rows) > 0 {
			return rows[0]
		}
		if time.Now().After(deadline) {
			t.Fatalf("no %s row reached the inbox", event)
		}
		time.Sleep(10 * time.Millisecond)
	}
}

// A scan an administrator starts tells them when it ends, and nobody else.
func TestAScanTellsTheAdministratorWhoStartedIt(t *testing.T) {
	t.Parallel()
	ctx, svc, a := openEnrichFixture(t, func(*Config) {})
	b := addAdmin(t, ctx, svc, "second")

	job, err := svc.RescanFor(ctx, a, false)
	if err != nil {
		t.Fatal(err)
	}
	row := waitForInbox(t, ctx, svc, a, "job-finished")
	if row.TargetPID != job.PID || row.Title != "Scan finished" || !strings.Contains(row.Body, "0 added") {
		t.Fatalf("row = %+v, want the scan's end naming %s", row, job.PID)
	}
	if rows := inboxOf(t, ctx, svc, b, "job-finished", "job-failed"); len(rows) > 0 {
		t.Fatalf("the other administrator heard of it: %+v", rows)
	}
}

// A scan nobody started, the scheduler's or a new library's, tells
// nobody: it leaves no one to tell.
func TestAScanNobodyStartedTellsNobody(t *testing.T) {
	t.Parallel()
	ctx, svc, a := openEnrichFixture(t, func(*Config) {})
	job, err := svc.Rescan(ctx, false)
	if err != nil {
		t.Fatal(err)
	}
	if origins, err := svc.db.JobOrigins(ctx); err != nil || len(origins) > 0 {
		t.Fatalf("origins = %+v (%v), want none", origins, err)
	}
	_, pid, _ := parseAPIPID(job.PID)
	waitForJob(t, ctx, svc, pid)

	mine, err := svc.RescanFor(ctx, a, false)
	if err != nil {
		t.Fatal(err)
	}
	waitForInbox(t, ctx, svc, a, "job-finished")
	rows := inboxOf(t, ctx, svc, a, "job-finished", "job-failed")
	if len(rows) != 1 || rows[0].TargetPID != mine.PID {
		t.Fatalf("rows = %+v, want only the scan the administrator started", rows)
	}
}

// A job that ends before its starter is recorded still reaches them: the
// follower found nobody to tell, so the starter does.
func TestAJobThatEndsBeforeItsStarterIsRecordedStillTellsThem(t *testing.T) {
	t.Parallel()
	ctx, svc, a := openEnrichFixture(t, func(*Config) {})
	res, err := svc.lib.Scan(ctx, waxbin.ScanRequest{})
	if err != nil {
		t.Fatal(err)
	}
	svc.adoptJob(ctx, res.JobPID, a.ID, "")
	waitForInbox(t, ctx, svc, a, "job-finished")
	rows := inboxOf(t, ctx, svc, a, "job-finished")
	if len(rows) != 1 || rows[0].TargetPID != apiPID(PrefixJob, res.JobPID) {
		t.Fatalf("rows = %+v, want the finished scan's", rows)
	}
	waitFor(t, func() bool {
		origins, err := svc.db.JobOrigins(ctx)
		return err == nil && len(origins) == 0
	}, "the settled origin should be gone")
}

// A job that failed says why, and one cut off by the server stopping
// says that instead of the catalog's words for it.
func TestAFailedJobSaysWhy(t *testing.T) {
	t.Parallel()
	ctx, svc, a := openEnrichFixture(t, func(*Config) {})
	want := map[model.PID]string{}
	for _, tc := range []struct {
		state  model.JobState
		reason string
		body   string
	}{
		{model.JobFailed, "the disk went away", "Analysis: the disk went away"},
		{model.JobFailed, "analyze: canceled: context canceled", "Analysis: the server stopped before it finished"},
		{model.JobCrashed, "reclaimed: owner not live", "Analysis: the server stopped before it finished"},
	} {
		pid := model.NewPID()
		if err := svc.db.InsertJobOrigin(ctx, wdb.JobOrigin{PID: string(pid), UserID: a.ID, CreatedAtNS: 1}); err != nil {
			t.Fatal(err)
		}
		svc.settleJobOrigin(ctx, &model.Job{PID: pid, Kind: "analyze", State: tc.state, Error: tc.reason})
		want[pid] = tc.body
	}
	rows := inboxOf(t, ctx, svc, a, "job-finished", "job-failed")
	if len(rows) != len(want) {
		t.Fatalf("rows = %+v, want one per failure", rows)
	}
	for _, r := range rows {
		_, pid, _ := parseAPIPID(r.TargetPID)
		if r.Event != "job-failed" || r.Title != "Analysis failed" || r.Body != want[pid] {
			t.Errorf("row = %+v, want the failure worded %q", r, want[pid])
		}
	}
	if origins, err := svc.db.JobOrigins(ctx); err != nil || len(origins) > 0 {
		t.Fatalf("origins = %+v (%v), want every one settled", origins, err)
	}
}

// A sweep an administrator asks for runs once: it shows as sweeping
// until it lands, and the request goes with it.
func TestHealthSweepRequestClears(t *testing.T) {
	t.Parallel()
	ctx, svc, a := openEnrichFixture(t, func(*Config) {})
	if err := svc.RunHealthSweep(ctx); err != nil {
		t.Fatal(err)
	}
	if svc.HealthSweepDue(ctx) {
		t.Fatal("a sweep is due right after one ran")
	}
	if err := svc.QueueHealthSweep(ctx, a); err != nil {
		t.Fatal(err)
	}
	if sum, err := svc.HealthSummaryFor(ctx); err != nil || !sum.Sweeping || !svc.HealthSweepDue(ctx) {
		t.Fatalf("after the request: sweeping %v, due %v (%v); want both", sum.Sweeping, svc.HealthSweepDue(ctx), err)
	}
	if err := svc.RunHealthSweep(ctx); err != nil {
		t.Fatal(err)
	}
	if sum, err := svc.HealthSummaryFor(ctx); err != nil || sum.Sweeping || svc.HealthSweepDue(ctx) {
		t.Fatalf("after the sweep: sweeping %v, due %v (%v); want neither", sum.Sweeping, svc.HealthSweepDue(ctx), err)
	}
}

// Work that runs inside its own request, emptying the trash or applying
// an organize plan, files its end the same way a background job does.
func TestSynchronousWorkTellsTheAdministratorToo(t *testing.T) {
	t.Parallel()
	ctx, svc, a := openEnrichFixture(t, func(c *Config) { c.Roots[0].Managed = true })
	if _, err := svc.EmptyTrash(ctx, a); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.ApplyOrganize(ctx, a, "waxbin-native", nil); err != nil {
		t.Fatal(err)
	}
	titles := map[string]string{}
	for _, r := range inboxOf(t, ctx, svc, a, "job-finished") {
		titles[r.Title] = r.Body
	}
	if !strings.HasPrefix(titles["Trash emptied"], "Trash: 0 files purged") ||
		!strings.HasPrefix(titles["Organize finished"], "Organize: 0 moved") {
		t.Fatalf("rows = %v, want the trash and the organize run", titles)
	}
}

// markers counts the kind's markers on an account's stream, those naming
// pid when one is given.
func markers(t *testing.T, ctx context.Context, svc *Library, userID, kind, pid string) int {
	t.Helper()
	evs, _, err := svc.db.EventsSince(ctx, userID, 0, 1000)
	if err != nil {
		t.Fatal(err)
	}
	n := 0
	for _, e := range evs {
		if e.Kind == kind && (pid == "" || e.ItemPID == pid) {
			n++
		}
	}
	return n
}

// A sweep that fails answers its request, so it neither runs again every
// minute nor reads as sweeping for good, and the summary says it failed.
// A run of failures is told once, and the next sweep that lands clears it.
func TestAFailedSweepAnswersItsRequestAndSaysSo(t *testing.T) {
	t.Parallel()
	ctx, svc, a := openEnrichFixture(t, func(*Config) {})
	if err := svc.RunHealthSweep(ctx); err != nil {
		t.Fatal(err)
	}
	if err := svc.QueueHealthSweep(ctx, a); err != nil {
		t.Fatal(err)
	}
	seen := markers(t, ctx, svc, a.ID, eventHealth, "")
	req := svc.sweepRequest(ctx)
	svc.sweeping.Store(true)
	svc.sweepEnded(ctx, req, errors.New("the disk went away"))
	sum, err := svc.HealthSummaryFor(ctx)
	if err != nil || sum.Sweeping || !sum.SweepFailed || svc.HealthSweepDue(ctx) {
		t.Fatalf("after a failed sweep: sweeping %v, failed %v, due %v (%v); want failed alone",
			sum.Sweeping, sum.SweepFailed, svc.HealthSweepDue(ctx), err)
	}
	if n := markers(t, ctx, svc, a.ID, eventHealth, ""); n != seen+1 {
		t.Fatalf("markers = %d, want the failure told once (%d)", n, seen+1)
	}
	svc.sweepEnded(ctx, "", errors.New("the disk is still gone"))
	if n := markers(t, ctx, svc, a.ID, eventHealth, ""); n != seen+1 {
		t.Fatalf("markers = %d after a second failure, want no more (%d)", n, seen+1)
	}
	// A request that fails in the same run still ends, and clients
	// reading it as sweeping have to hear so.
	if err := svc.QueueHealthSweep(ctx, a); err != nil {
		t.Fatal(err)
	}
	seen = markers(t, ctx, svc, a.ID, eventHealth, "")
	svc.sweeping.Store(true)
	svc.sweepEnded(ctx, svc.sweepRequest(ctx), errors.New("the disk is gone for good"))
	if n := markers(t, ctx, svc, a.ID, eventHealth, ""); n != seen+1 {
		t.Fatalf("markers = %d after a requested sweep failed again, want its end told (%d)", n, seen+1)
	}
	seen = markers(t, ctx, svc, a.ID, eventHealth, "")
	if err := svc.RunHealthSweep(ctx); err != nil {
		t.Fatal(err)
	}
	if sum, err := svc.HealthSummaryFor(ctx); err != nil || sum.SweepFailed {
		t.Fatalf("after a sweep that landed: failed %v (%v), want cleared", sum.SweepFailed, err)
	}
	if n := markers(t, ctx, svc, a.ID, eventHealth, ""); n != seen+1 {
		t.Fatalf("markers = %d, want the landing told (%d)", n, seen+1)
	}
}
