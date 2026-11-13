package service

import (
	"context"
	"encoding/json"
	"path/filepath"
	"reflect"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/analyze"
	"github.com/colespringer/waxbin/inbox"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/organize"
	"github.com/colespringer/waxbin/scan"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// An administrator hears of a watched job's start, each five percent and
// its end at once, and of a new message at most every fifteen seconds; of
// a delete or an upload's import, only the end; and of any end once.
func TestJobNewsAnnouncesWhatAnAdministratorWatches(t *testing.T) {
	t.Parallel()
	now := time.Unix(1_000_000, 0)
	opened := now.Add(-time.Hour).UnixNano()
	running := func(p float64, msg string, ago time.Duration) *jobSeen {
		return &jobSeen{state: model.JobRunning, bucket: progressBucket(p), message: msg, at: now.Add(-ago)}
	}
	done := &jobSeen{state: model.JobDone, at: now.Add(-time.Minute)}
	for _, tc := range []struct {
		name string
		prev *jobSeen
		job  model.Job
		want bool
	}{
		{"a scan seen first", nil, model.Job{Kind: "scan", State: model.JobRunning}, true},
		{"a scan that has not moved", running(0.41, "walking", time.Minute), model.Job{Kind: "scan", State: model.JobRunning, Progress: 0.44, Message: "walking"}, false},
		{"a scan past another five percent, at once", running(0.44, "walking", time.Second), model.Job{Kind: "scan", State: model.JobRunning, Progress: 0.45, Message: "walking"}, true},
		{"a scan saying something new, soon after the last", running(0.44, "scanned 50 files", 3*time.Second), model.Job{Kind: "scan", State: model.JobRunning, Progress: 0.44, Message: "scanned 100 files"}, false},
		{"a scan saying something new, past the spacing", running(0.44, "scanned 50 files", jobMessageEvery), model.Job{Kind: "scan", State: model.JobRunning, Progress: 0.44, Message: "scanned 900 files"}, true},
		{"a scan that ended, at once", running(0.9, "", time.Second), model.Job{Kind: "scan", State: model.JobDone, Progress: 1}, true},
		{"an end read again", done, model.Job{Kind: "scan", State: model.JobDone, Progress: 1}, false},
		{"a delete running", nil, model.Job{Kind: "delete", State: model.JobRunning, Progress: 0.5}, false},
		{"a delete that ended", nil, model.Job{Kind: "delete", State: model.JobFailed, FinishedAt: opened + 1}, true},
		{"an import that ended, read again", done, model.Job{Kind: "import", State: model.JobDone}, false},
		{"emptying the trash, seen first", nil, model.Job{Kind: "empty-trash", State: model.JobRunning}, true},
		{"a scan that ended before this process opened, replayed", nil, model.Job{Kind: "scan", State: model.JobDone, FinishedAt: opened - 1}, false},
		{"a scan that ended since this process opened, seen first", nil, model.Job{Kind: "scan", State: model.JobDone, FinishedAt: opened + 1}, true},
		{"a delete that ended before this process opened, replayed", nil, model.Job{Kind: "delete", State: model.JobDone, FinishedAt: opened - 1}, false},
	} {
		if got := jobNews(tc.prev, tc.job, now, opened); got != tc.want {
			t.Errorf("%s: news = %v, want %v", tc.name, got, tc.want)
		}
	}
}

// A job still running is listed, first, however many newer jobs pushed
// it out of the window.
func TestARunningJobPastTheWindowIsListedFirst(t *testing.T) {
	t.Parallel()
	a := &lyricist{name: "a", asked: make(chan struct{}, 1), gate: make(chan struct{})}
	ctx, svc, uc, _ := openLyricsFixture(t, a)
	pid, err := svc.lib.StartEnrich(ctx, waxbin.EnrichOptions{})
	if err != nil {
		t.Fatal(err)
	}
	defer waitForJob(t, ctx, svc, pid)
	defer close(a.gate)
	<-a.asked
	for range 3 {
		if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
			t.Fatal(err)
		}
	}

	deadline := time.Now().Add(5 * time.Second)
	for {
		jobs, err := svc.Jobs.List(ctx, uc, 2)
		if err != nil {
			t.Fatal(err)
		}
		if len(jobs) == 3 && jobs[0].PID == apiPID(PrefixJob, pid) && jobs[0].State == "running" &&
			jobs[1].Kind == "scan" && jobs[2].Kind == "scan" {
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("jobs = %+v, want the running pass and then the two newest scans", jobs)
		}
		time.Sleep(20 * time.Millisecond)
	}
}

// A job its starter records is followed from then on, whatever the feed
// passed along: the feed drops rows when it falls behind, and a started
// job it dropped would show no progress and tell nobody of its end.
func TestAStartersJobIsFollowedWhateverTheFeedDropped(t *testing.T) {
	t.Parallel()
	a := &lyricist{name: "a", asked: make(chan struct{}, 1), gate: make(chan struct{})}
	ctx, svc, uc, _ := openLyricsFixture(t, a)
	pid, err := svc.lib.StartEnrich(ctx, waxbin.EnrichOptions{})
	if err != nil {
		t.Fatal(err)
	}
	gate := sync.OnceFunc(func() { close(a.gate) })
	defer waitForJob(t, ctx, svc, pid)
	defer gate()
	<-a.asked
	followed := func() bool {
		svc.Jobs.jobs.mu.Lock()
		defer svc.Jobs.jobs.mu.Unlock()
		_, ok := svc.Jobs.jobs.running[pid]
		return ok
	}
	waitFor(t, followed, "the feed's row should reach the follower")
	// As if the feed had never passed the job on.
	svc.Jobs.jobs.mu.Lock()
	delete(svc.Jobs.jobs.running, pid)
	delete(svc.Jobs.jobs.changed, pid)
	svc.Jobs.jobs.mu.Unlock()

	svc.Jobs.adoptJob(ctx, pid, uc.ID, "")
	waitFor(t, followed, "recording the starter should hand the job to the follower")
	gate()
	waitForInbox(t, ctx, svc, uc, "job-finished")
}

// A job whose starter could not be recorded is followed all the same:
// nobody is told of its end, but its progress, and a kind change's rows,
// still need the follower.
func TestAJobWhoseStarterCouldNotBeRecordedIsStillFollowed(t *testing.T) {
	t.Parallel()
	a := &lyricist{name: "a", asked: make(chan struct{}, 1), gate: make(chan struct{})}
	ctx, svc, uc, _ := openLyricsFixture(t, a)
	pid, err := svc.lib.StartEnrich(ctx, waxbin.EnrichOptions{})
	if err != nil {
		t.Fatal(err)
	}
	gate := sync.OnceFunc(func() { close(a.gate) })
	defer waitForJob(t, ctx, svc, pid)
	defer gate()
	<-a.asked
	followed := func() bool {
		svc.Jobs.jobs.mu.Lock()
		defer svc.Jobs.jobs.mu.Unlock()
		_, ok := svc.Jobs.jobs.running[pid]
		return ok
	}
	waitFor(t, followed, "the feed's row should reach the follower")
	// As if the feed had never passed the job on.
	svc.Jobs.jobs.mu.Lock()
	delete(svc.Jobs.jobs.running, pid)
	delete(svc.Jobs.jobs.changed, pid)
	svc.Jobs.jobs.mu.Unlock()

	refuseJobOriginWrites(t, ctx, svc)
	svc.Jobs.adoptJob(ctx, pid, uc.ID, "")
	waitFor(t, followed, "a starter that could not be recorded should still hand the job to the follower")
}

// nextStart leaves the job ends taken in hand as the start after a stop
// does: let go, for that start's settle to take.
func nextStart(t *testing.T, ctx context.Context, svc *Library) {
	t.Helper()
	if err := svc.db.ReleaseJobOriginClaims(ctx); err != nil {
		t.Fatal(err)
	}
}

// waitFor polls cond until it holds, failing with what it waited for.
func waitFor(t *testing.T, cond func() bool, what string) {
	t.Helper()
	deadline := time.Now().Add(10 * time.Second)
	for !cond() {
		if time.Now().After(deadline) {
			t.Fatal(what)
		}
		time.Sleep(10 * time.Millisecond)
	}
}

// A followed job the catalog no longer has, as after a restore, lets go
// of its origin: a fix it held would otherwise read as running, and
// refuse every other fix of its rule, until the next start.
func TestAJobTheCatalogLostLetsGoOfItsOrigin(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := openLyricsFixture(t, &lyricist{name: "a"})
	if err := svc.Health.RunHealthSweep(ctx); err != nil {
		t.Fatal(err)
	}
	lost := model.NewPID()
	if err := svc.db.InsertJobOrigin(ctx, wdb.JobOrigin{PID: string(lost), UserID: uc.ID, Rule: ruleMissingLyrics, CreatedAtNS: 1}); err != nil {
		t.Fatal(err)
	}
	if !ruleFixing(t, ctx, svc, ruleMissingLyrics) {
		t.Fatal("the rule does not read as fixing while its job's origin stands")
	}
	seen := markers(t, ctx, svc, uc.ID, eventHealth, "")
	svc.Jobs.followJob(lost)
	waitFor(t, func() bool { return !ruleFixing(t, ctx, svc, ruleMissingLyrics) },
		"the rule should stop reading as fixing once its job is gone")
	waitFor(t, func() bool { return markers(t, ctx, svc, uc.ID, eventHealth, "") > seen },
		"every account should hear the rule is no longer being fixed")
}

// The feed reads again from the log what the lossy subscription dropped,
// as the catalog's contract asks: a job whose rows were lost is followed
// once the log is read, however quiet the catalog is meanwhile.
func TestTheFeedRereadsWhatTheSubscriptionDropped(t *testing.T) {
	t.Parallel()
	a := &lyricist{name: "a", asked: make(chan struct{}, 1), gate: make(chan struct{})}
	ctx, svc, _, _ := openLyricsFixture(t, a)
	pid, err := svc.lib.StartEnrich(ctx, waxbin.EnrichOptions{})
	if err != nil {
		t.Fatal(err)
	}
	gate := sync.OnceFunc(func() { close(a.gate) })
	defer waitForJob(t, ctx, svc, pid)
	defer gate()
	<-a.asked
	followed := func() bool {
		svc.Jobs.jobs.mu.Lock()
		defer svc.Jobs.jobs.mu.Unlock()
		_, ok := svc.Jobs.jobs.running[pid]
		return ok
	}
	waitFor(t, followed, "the feed's row should reach the follower")
	var created int64
	rows, err := svc.lib.Changes(ctx, 0)
	if err != nil {
		t.Fatal(err)
	}
	for _, ch := range rows {
		if ch.EntityType == "job" && ch.EntityPID == pid {
			created = ch.Seq
			break
		}
	}
	if created == 0 {
		t.Fatal("no change row for the pass")
	}
	// As if the subscription had dropped the pass's rows and every one
	// after: the feed's place is before them, and the follower never
	// heard of the pass.
	svc.feed.mu.Lock()
	svc.feed.tail = created - 1
	svc.feed.mu.Unlock()
	svc.Jobs.jobs.mu.Lock()
	delete(svc.Jobs.jobs.running, pid)
	delete(svc.Jobs.jobs.changed, pid)
	svc.Jobs.jobs.mu.Unlock()

	waitFor(t, followed, "the feed should read the dropped rows from the log")
}

// announced waits until a whole scan's end has reached userID, by which
// point the follower has read every job that ended before it.
func announced(t *testing.T, ctx context.Context, svc *Library, userID string) {
	t.Helper()
	res, err := svc.lib.Scan(ctx, waxbin.ScanRequest{})
	if err != nil {
		t.Fatal(err)
	}
	waitFor(t, func() bool { return markers(t, ctx, svc, userID, eventJob, apiPID(PrefixJob, res.JobPID)) > 0 },
		"a whole scan announced to every administrator")
}

// A run on one item is its starter's business while it runs; its end
// reaches every administrator, whose job list may show it running. The
// listing names its target.
func TestATargetedJobsEndReachesEveryAdministrator(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, track := openLyricsFixture(t, &lyricist{name: "a"})
	other := addAdmin(t, ctx, svc, "other").ID
	started, err := svc.lib.StartEnrich(ctx, waxbin.EnrichOptions{ItemPID: track})
	if err != nil {
		t.Fatal(err)
	}
	svc.Jobs.adoptJob(ctx, started, uc.ID, "")
	waitForJob(t, ctx, svc, started)
	unowned, err := svc.lib.StartEnrich(ctx, waxbin.EnrichOptions{ItemPID: track})
	if err != nil {
		t.Fatal(err)
	}
	waitForJob(t, ctx, svc, unowned)
	waitFor(t, func() bool { return markers(t, ctx, svc, uc.ID, eventJob, apiPID(PrefixJob, started)) > 0 }, "the starter hearing of their run")
	announced(t, ctx, svc, other)
	announced(t, ctx, svc, uc.ID)
	if n := markers(t, ctx, svc, other, eventJob, apiPID(PrefixJob, started)); n != 1 {
		t.Errorf("another administrator heard of the run %d times, want its end once", n)
	}
	if a, b := markers(t, ctx, svc, uc.ID, eventJob, apiPID(PrefixJob, unowned)), markers(t, ctx, svc, other, eventJob, apiPID(PrefixJob, unowned)); a != 1 || b != 1 {
		t.Errorf("a run nobody started was announced %d and %d times, want its end once each", a, b)
	}
	job, err := svc.Jobs.Status(ctx, apiPID(PrefixJob, started))
	if err != nil || job.Target == nil || job.Target.Type != "item" || job.Target.PID != apiPID(PrefixTrack, track) || job.Target.Name != "Amber Waves" {
		t.Errorf("target = %+v (%v), want the track by name", job.Target, err)
	}
}

// A finished targeted job leaves the list, read by pid instead: a burst
// of them would push the whole passes out of the window.
func TestAFinishedTargetedJobLeavesTheList(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, track := openLyricsFixture(t, &lyricist{name: "a"})
	whole, err := svc.lib.Scan(ctx, waxbin.ScanRequest{})
	if err != nil {
		t.Fatal(err)
	}
	for range 3 {
		pid, err := svc.lib.StartEnrich(ctx, waxbin.EnrichOptions{ItemPID: track})
		if err != nil {
			t.Fatal(err)
		}
		waitForJob(t, ctx, svc, pid)
	}
	jobs, err := svc.Jobs.List(ctx, uc, 2)
	if err != nil {
		t.Fatal(err)
	}
	if len(jobs) == 0 || !slices.ContainsFunc(jobs, func(j Job) bool { return j.PID == apiPID(PrefixJob, whole.JobPID) }) {
		t.Errorf("jobs = %+v, want the whole scan listed", jobs)
	}
	for _, j := range jobs {
		if j.Target != nil && j.State != "running" {
			t.Errorf("a finished targeted job is listed: %+v", j)
		}
	}
}

// The watcher's scan of one library is targeted: nobody started it, so
// only its end is told, to every administrator.
func TestAScanOfOneLibraryAnnouncesItsEnd(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := openLyricsFixture(t, &lyricist{name: "a"})
	lib := svc.Roots.libraryRoots()[0]
	res, err := svc.lib.Scan(ctx, waxbin.ScanRequest{LibraryPID: model.PID(lib.PID)})
	if err != nil {
		t.Fatal(err)
	}
	announced(t, ctx, svc, uc.ID)
	if n := markers(t, ctx, svc, uc.ID, eventJob, apiPID(PrefixJob, res.JobPID)); n != 1 {
		t.Errorf("a one-library scan was announced %d times, want its end once", n)
	}
	job, err := svc.Jobs.Status(ctx, apiPID(PrefixJob, res.JobPID))
	if err != nil || job.Target == nil || job.Target.Type != "library" || job.Target.PID != apiPID(PrefixLibrary, model.PID(lib.PID)) || job.Target.Name != lib.Name {
		t.Errorf("job = %+v (%v), want the library as its target", job.Target, err)
	}
}

// A scan's runs are named by the root table, never by the path WaxBin
// names them with, and only administrators read them: an account reading
// a job it started gets the total alone.
func TestScanRunsAreNamedByRootNameNotPath(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	lib := svc.Roots.libraryRoots()[0]
	pid, err := svc.lib.StartScan(ctx, waxbin.ScanRequest{LibraryPID: model.PID(lib.PID)})
	if err != nil {
		t.Fatal(err)
	}
	waitForJob(t, ctx, svc, pid)
	// The follower claims an origin it finds at a job's end, so it takes
	// this end in before the starter is recorded.
	jobFollowerSettled(t, svc, pid)
	job, err := svc.Jobs.StatusFor(ctx, admin, apiPID(PrefixJob, pid))
	if err != nil {
		t.Fatal(err)
	}
	if job.Scan == nil || len(job.Scan.Runs) != 1 {
		t.Fatalf("tally = %+v, want one run", job.Scan)
	}
	run := job.Scan.Runs[0]
	if run.LibraryPID != apiPID(PrefixLibrary, model.PID(lib.PID)) || run.Library != lib.Name {
		t.Fatalf("run = %s %q, want %s %q", run.LibraryPID, run.Library, apiPID(PrefixLibrary, model.PID(lib.PID)), lib.Name)
	}
	if strings.Contains(run.Library, string(filepath.Separator)) || run.Library == lib.Path {
		t.Fatalf("run named %q, a path", run.Library)
	}

	acct, err := svc.Identity.CreateAccount(ctx, AccountCreate{Username: "starter", Password: "correct-horse"})
	if err != nil {
		t.Fatal(err)
	}
	starter, err := svc.Grants.UserCtxFor(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	if err := svc.db.InsertJobOrigin(ctx, wdb.JobOrigin{PID: string(pid), UserID: starter.ID, CreatedAtNS: time.Now().UnixNano()}); err != nil {
		t.Fatal(err)
	}
	mine, err := svc.Jobs.StatusFor(ctx, starter, apiPID(PrefixJob, pid))
	if err != nil {
		t.Fatal(err)
	}
	if mine.Scan == nil || mine.Scan.Runs != nil || mine.Scan.AudioFiles != job.Scan.AudioFiles {
		t.Fatalf("starter's tally = %+v, want the total without runs", mine.Scan)
	}
}

// The status's last run is the newest whole pass, not an item's.
func TestTheLastRunIsAWholePass(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, track := openLyricsFixture(t, &lyricist{name: "a"})
	whole, err := svc.lib.StartEnrich(ctx, waxbin.EnrichOptions{})
	if err != nil {
		t.Fatal(err)
	}
	waitForJob(t, ctx, svc, whole)
	item, err := svc.lib.StartEnrich(ctx, waxbin.EnrichOptions{ItemPID: track})
	if err != nil {
		t.Fatal(err)
	}
	waitForJob(t, ctx, svc, item)
	j, err := svc.lib.Job(ctx, whole)
	if err != nil {
		t.Fatal(err)
	}
	st, err := svc.Enrichment.StatusFor(ctx, uc)
	if err != nil || st.LastRun == nil || st.LastRun.FinishedAtNS != j.FinishedAt {
		t.Fatalf("last run = %+v (%v), want the whole pass finished at %d", st.LastRun, err, j.FinishedAt)
	}
}

// A scan records its total over every library with each library's own
// run beside it; the tally carries the whole partition of both, and a run
// keeps its library's pid for naming, never the path WaxBin names it by.
func TestReadResultCarriesTheScanPartition(t *testing.T) {
	t.Parallel()
	total := scan.Result{
		FilesSeen: 12, AudioFiles: 10, ItemsCreated: 2, ItemsUpdated: 1, SidecarsUpdated: 1,
		Copies: 2, Unchanged: 3, Errored: 1, Relinked: 1, Reread: 4, Missing: 1,
		Promoted: 1, Dropped: 2, Skipped: 2, WalkErrors: 1, RootUnreachable: true,
	}
	raw, err := json.Marshal(struct {
		scan.Result
		Runs []scan.Result
	}{
		Result: total,
		Runs: []scan.Result{
			{FilesSeen: 12, AudioFiles: 10, ItemsCreated: 2, ItemsUpdated: 1, SidecarsUpdated: 1,
				Copies: 2, Unchanged: 3, Errored: 1, Relinked: 1, Reread: 4, Missing: 1,
				Promoted: 1, Dropped: 2, Skipped: 2, LibraryPID: "01LIBA", LibraryName: "/music"},
			{WalkErrors: 1, RootUnreachable: true, LibraryPID: "01LIBB", LibraryName: "/unmounted"},
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	j := Job{Kind: "scan"}
	j.readResult(string(raw))
	want := ScanTallyDTO{
		FilesSeen: 12, AudioFiles: 10, Created: 2, Updated: 1, SidecarsUpdated: 1,
		Copies: 2, Unchanged: 3, Errored: 1, Relinked: 1, Reread: 4, Missing: 1,
		Promoted: 1, Dropped: 2, Skipped: 2, WalkErrors: 1, RootUnreachable: true,
	}
	if j.Scan == nil {
		t.Fatal("no tally read")
	}
	got := *j.Scan
	got.Runs = nil
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("total = %+v, want %+v", got, want)
	}
	if n := len(j.Scan.Runs); n != 2 {
		t.Fatalf("runs = %d, want 2", n)
	}
	first, second := j.Scan.Runs[0], j.Scan.Runs[1]
	if first.LibraryPID != "lb-01LIBA" || first.Copies != 2 || first.Reread != 4 || first.RootUnreachable {
		t.Errorf("first run = %+v, want the music library's own counts", first)
	}
	if second.LibraryPID != "lb-01LIBB" || second.WalkErrors != 1 || !second.RootUnreachable {
		t.Errorf("second run = %+v, want the unreachable library", second)
	}
	for _, r := range j.Scan.Runs {
		if r.Library != "" {
			t.Errorf("run %s is named %q before the root table named it", r.LibraryPID, r.Library)
		}
	}
}

// An analyze pass's summary carries how many fingerprints fell back to
// the pure-Go form and how many fpcalc reads were kept past an error.
func TestAnAnalyzeSummaryCarriesItsFingerprintCounts(t *testing.T) {
	t.Parallel()
	raw, err := json.Marshal(analyze.Result{Analyzed: 60, FingerprintFallbacks: 58, FingerprintPartialReads: 2})
	if err != nil {
		t.Fatal(err)
	}
	j := Job{Kind: "analyze"}
	j.readResult(string(raw))
	if a := j.Analyze; a == nil || a.Analyzed != 60 || a.FingerprintFallbacks != 58 || a.FingerprintPartialReads != 2 {
		t.Fatalf("tally = %+v, want the fingerprint counts", j.Analyze)
	}
}

// An organize run's tally keeps what did not move in one count: files in
// place and moves the catalog held back, which it reports apart.
func TestReadResultCountsHeldMovesAsSkipped(t *testing.T) {
	t.Parallel()
	raw, err := json.Marshal(organize.RunResult{Profile: "default",
		Report: organize.Report{Moved: 3, Skipped: 1, Held: 2}})
	if err != nil {
		t.Fatal(err)
	}
	j := Job{Kind: "organize"}
	j.readResult(string(raw))
	if j.Organize == nil || j.Organize.Moved != 3 || j.Organize.Skipped != 3 {
		t.Fatalf("tally = %+v, want 3 moved and 3 left where they were", j.Organize)
	}
}

// A job is read by the audience that hears of it: administrators, and
// the account that started a targeted job while its origin row still
// holds them.
func TestJobStatusForFollowsTheJobsAudience(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	acct, err := svc.Identity.CreateAccount(ctx, AccountCreate{Username: "starter", Password: "correct-horse"})
	if err != nil {
		t.Fatal(err)
	}
	listener, err := svc.Grants.UserCtxFor(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	originFor := func(pid model.PID) {
		t.Helper()
		if err := svc.db.InsertJobOrigin(ctx, wdb.JobOrigin{PID: string(pid), UserID: listener.ID, CreatedAtNS: time.Now().UnixNano()}); err != nil {
			t.Fatal(err)
		}
	}

	// A whole pass is the administrators' alone: the account holding its
	// origin row (an administrator since demoted) never hears of it, and
	// does not read it either.
	pass, err := svc.lib.StartAnalyze(ctx, waxbin.AnalyzeOptions{})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Jobs.StatusFor(ctx, admin, apiPID(PrefixJob, pass)); err != nil {
		t.Errorf("an administrator: %v", err)
	}
	originFor(pass)
	if _, err := svc.Jobs.StatusFor(ctx, listener, apiPID(PrefixJob, pass)); KindOf(err) != KindForbidden {
		t.Errorf("a non-administrator holding a pass's origin = %v, want forbidden", err)
	}

	// A targeted job is its starter's too, while its origin row holds. The
	// follower drops the origin it finds at a job's end, so the kind change
	// is taken in before the starter is recorded.
	_, item, _ := parseAPIPID(fixtureItemPIDs(t, ctx, svc, admin)[0])
	followed := jobEndFollowed(t, svc, "set-kind")
	targeted, err := svc.lib.StartSetItemKind(ctx, []model.PID{item}, model.KindBook, waxbin.KindOptions{})
	if err != nil {
		t.Fatal(err)
	}
	followed("the follower to take the kind change's end in")
	job := apiPID(PrefixJob, targeted)
	if _, err := svc.Jobs.StatusFor(ctx, listener, job); KindOf(err) != KindForbidden {
		t.Errorf("an account that did not start it = %v, want forbidden", err)
	}
	originFor(targeted)
	if _, err := svc.Jobs.StatusFor(ctx, listener, job); err != nil {
		t.Errorf("its starter: %v", err)
	}
	if _, err := svc.db.DeleteJobOrigin(ctx, string(targeted)); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Jobs.StatusFor(ctx, listener, job); KindOf(err) != KindForbidden {
		t.Errorf("its starter once its end was told = %v, want forbidden", err)
	}
	if _, err := svc.Jobs.StatusFor(ctx, listener, "jb-01JZX5N8QW3F4V9T2B7KDEXAMPL"); KindOf(err) != KindNotFound {
		t.Errorf("an unknown job = %v, want not-found", err)
	}
}

// Clearing hides the ended jobs from the caller's list and never one still
// running; a second clear has nothing left to count.
func TestClearingFinishedJobsKeepsARunningJob(t *testing.T) {
	t.Parallel()
	a := gatedLyricist("a")
	defer a.open()
	ctx, svc, uc, _ := openLyricsFixture(t, a)
	for range 3 {
		if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
			t.Fatal(err)
		}
	}
	pid, err := svc.lib.StartEnrich(ctx, waxbin.EnrichOptions{})
	if err != nil {
		t.Fatal(err)
	}
	defer waitForJob(t, ctx, svc, pid)
	defer a.open()
	<-a.asked

	cleared, err := svc.Jobs.ClearFinishedJobs(ctx, uc)
	if err != nil || cleared < 3 {
		t.Fatalf("cleared = (%d, %v), want at least the three scans", cleared, err)
	}
	jobs, err := svc.Jobs.List(ctx, uc, 50)
	if err != nil {
		t.Fatal(err)
	}
	if len(jobs) != 1 || jobs[0].PID != apiPID(PrefixJob, pid) || jobs[0].State != "running" {
		t.Fatalf("jobs after the clear = %+v, want only the running pass", jobs)
	}
	if again, err := svc.Jobs.ClearFinishedJobs(ctx, uc); err != nil || again != 0 {
		t.Errorf("a second clear = (%d, %v), want 0", again, err)
	}
}

// A cleared job never takes a page slot: the scan below is newer than the
// pass by id, yet with a limit of one the page is the pass, which ended
// after the clear.
func TestAClearedJobTakesNoPageSlot(t *testing.T) {
	t.Parallel()
	a := gatedLyricist("a")
	defer a.open()
	ctx, svc, uc, _ := openLyricsFixture(t, a)
	pid, err := svc.lib.StartEnrich(ctx, waxbin.EnrichOptions{})
	if err != nil {
		t.Fatal(err)
	}
	defer waitForJob(t, ctx, svc, pid)
	defer a.open()
	<-a.asked
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	if cleared, err := svc.Jobs.ClearFinishedJobs(ctx, uc); err != nil || cleared < 1 {
		t.Fatalf("cleared = (%d, %v), want at least the scan", cleared, err)
	}
	a.open()
	waitForJob(t, ctx, svc, pid)

	jobs, err := svc.Jobs.List(ctx, uc, 1)
	if err != nil {
		t.Fatal(err)
	}
	if len(jobs) != 1 || jobs[0].PID != apiPID(PrefixJob, pid) {
		t.Fatalf("jobs with a limit of one = %+v, want the pass that ended after the clear", jobs)
	}
}

// A page is filled from as far back as it takes: the pass below ended after
// the clear, behind more cleared scans than one read of the catalog holds
// for a limit of one, and it is still the page.
func TestAJobEndedAfterTheClearListsBehindAWindowOfClearedOnes(t *testing.T) {
	t.Parallel()
	a := gatedLyricist("a")
	defer a.open()
	ctx, svc, uc, _ := openLyricsFixture(t, a)
	pid, err := svc.lib.StartEnrich(ctx, waxbin.EnrichOptions{})
	if err != nil {
		t.Fatal(err)
	}
	defer waitForJob(t, ctx, svc, pid)
	defer a.open()
	<-a.asked
	for range jobsOverfetch + 1 {
		if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
			t.Fatal(err)
		}
	}
	if cleared, err := svc.Jobs.ClearFinishedJobs(ctx, uc); err != nil || cleared < jobsOverfetch+1 {
		t.Fatalf("cleared = (%d, %v), want at least the %d scans", cleared, err, jobsOverfetch+1)
	}
	a.open()
	waitForJob(t, ctx, svc, pid)

	jobs, err := svc.Jobs.List(ctx, uc, 1)
	if err != nil {
		t.Fatal(err)
	}
	if len(jobs) != 1 || jobs[0].PID != apiPID(PrefixJob, pid) {
		t.Fatalf("jobs with a limit of one = %+v, want the pass that ended after the clear", jobs)
	}
}

// A forty-file upload runs an import per file. Finished, those are neither
// listed, however far back the page has to read past them, nor counted by
// the clear, which counts what the list holds.
func TestAnUploadsFinishedImportsAreNeitherListedNorCounted(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := openEnrichFixture(t, func(*Config) {})
	whole, err := svc.lib.Scan(ctx, waxbin.ScanRequest{})
	if err != nil {
		t.Fatal(err)
	}
	libs, err := svc.lib.Libraries(ctx)
	if err != nil || len(libs) == 0 {
		t.Fatalf("libraries = (%v, %v)", libs, err)
	}
	// An import job per file; the files themselves are no part of this.
	plan := &inbox.Plan{Library: libs[0], Source: t.TempDir()}
	for range 40 {
		if _, err := svc.lib.ApplyImport(ctx, plan); err != nil {
			t.Fatal(err)
		}
	}
	raw, err := svc.lib.Jobs(ctx, jobsFetchCap)
	if err != nil {
		t.Fatal(err)
	}
	if imports := slices.IndexFunc(raw, func(j *model.Job) bool { return j.Kind == "import" }); imports < 0 {
		t.Fatalf("the catalog holds no import job: %+v", raw)
	}

	page, err := svc.Jobs.List(ctx, uc, 2)
	if err != nil {
		t.Fatal(err)
	}
	if !slices.ContainsFunc(page, func(j Job) bool { return j.PID == apiPID(PrefixJob, whole.JobPID) }) {
		t.Errorf("a page of two = %+v, want the scan behind the imports", page)
	}
	listed, err := svc.Jobs.List(ctx, uc, 200)
	if err != nil {
		t.Fatal(err)
	}
	var finished int
	for _, j := range listed {
		if j.Kind == "import" {
			t.Errorf("a finished import is listed: %+v", j)
		}
		if j.State != string(model.JobRunning) {
			finished++
		}
	}
	cleared, err := svc.Jobs.ClearFinishedJobs(ctx, uc)
	if err != nil {
		t.Fatal(err)
	}
	if cleared != finished {
		t.Fatalf("cleared %d, want the %d finished jobs the list held", cleared, finished)
	}
}

// What the list leaves out of a finished job, and never of a running one.
func TestListedJobs(t *testing.T) {
	t.Parallel()
	const cleared = 50
	ended := func(kind string, at int64) *model.Job {
		return &model.Job{Kind: kind, State: model.JobDone, StartedAt: at - 1, FinishedAt: at}
	}
	targeted := func(j *model.Job) *model.Job {
		j.TargetType = "item"
		return j
	}
	running := func(j *model.Job) *model.Job {
		j.State = model.JobRunning
		j.FinishedAt = 0
		return j
	}
	for _, tc := range []struct {
		name string
		job  *model.Job
		want bool
	}{
		{"a scan", ended("scan", 60), true},
		{"a cleared scan", ended("scan", 40), false},
		{"an import", ended("import", 60), false},
		{"a delete", ended("delete", 60), false},
		{"a restore", ended("restore", 60), false},
		{"a purge", ended("purge-trash", 60), false},
		{"an import running", running(ended("import", 60)), true},
		{"a delete running", running(ended("delete", 40)), true},
		{"a targeted enrichment", targeted(ended("enrich", 60)), false},
		{"a kind change", targeted(ended("set-kind", 60)), true},
	} {
		if got := listedJob(tc.job, cleared); got != tc.want {
			t.Errorf("%s: listed = %v, want %v", tc.name, got, tc.want)
		}
	}
}

// A job's end is the first time it recorded.
func TestJobEndedAtFallsBackThroughTheRecordedTimes(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		name string
		job  model.Job
		want int64
	}{
		{"finished", model.Job{StartedAt: 1, HeartbeatAt: 2, FinishedAt: 3}, 3},
		{"crashed before finishing", model.Job{StartedAt: 1, HeartbeatAt: 2}, 2},
		{"never beat", model.Job{StartedAt: 1}, 1},
	} {
		if got := jobEndedAt(&tc.job); got != tc.want {
			t.Errorf("%s: end = %d, want %d", tc.name, got, tc.want)
		}
	}
}

// The watermark is the newest end time among the jobs counted, not the
// clock, so a job that ends after the call is not hidden by it.
func TestClearingFinishedJobsStampsTheNewestEnd(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := openEnrichFixture(t, func(*Config) {})
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	raw, err := svc.lib.Jobs(ctx, jobsFetchCap)
	if err != nil {
		t.Fatal(err)
	}
	var newest int64
	for _, j := range raw {
		if j.State != model.JobRunning && j.TargetType == "" {
			newest = max(newest, jobEndedAt(j))
		}
	}
	if _, err := svc.Jobs.ClearFinishedJobs(ctx, uc); err != nil {
		t.Fatal(err)
	}
	if got, err := svc.db.JobsClearedAt(ctx, uc.ID); err != nil || got != newest {
		t.Fatalf("watermark = (%d, %v), want the newest end %d", got, err, newest)
	}
}

// A job's end a stopped process took in hand is told at the next start
// wherever the clock stands by then: one set back behind the claim makes
// the claim look newer than the start.
func TestASettleCutShortIsTakenOverAfterTheClockSteppedBack(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	ctx, svc, uc, stop := openServiceAt(t, dataDir, nil)
	scan, err := svc.lib.Scan(ctx, waxbin.ScanRequest{})
	if err != nil {
		t.Fatal(err)
	}
	// Once the follower has read the scan's end and found no one to tell,
	// nothing here settles the origin recorded after it.
	jobFollowerSettled(t, svc, scan.JobPID)
	if err := svc.db.InsertJobOrigin(ctx, wdb.JobOrigin{PID: string(scan.JobPID), UserID: uc.ID, CreatedAtNS: 1}); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.db.ClaimJobOrigin(ctx, string(scan.JobPID), time.Now().Add(time.Hour).UnixNano()); err != nil {
		t.Fatal(err)
	}
	stop()

	ctx, svc, uc, _ = openServiceAt(t, dataDir, nil)
	if row := waitForInbox(t, ctx, svc, uc, "job-finished"); row.TargetPID != apiPID(PrefixJob, scan.JobPID) {
		t.Fatalf("row = %+v, want the scan's end", row)
	}
	waitFor(t, func() bool {
		has, err := svc.db.HasJobOrigin(ctx, string(scan.JobPID))
		return err == nil && !has
	}, "the settled origin should be gone")
}
