package service

import (
	"sync"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"

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
		jobs, err := svc.Jobs(ctx, uc, 2)
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
		svc.jobs.mu.Lock()
		defer svc.jobs.mu.Unlock()
		_, ok := svc.jobs.running[pid]
		return ok
	}
	waitFor(t, followed, "the feed's row should reach the follower")
	// As if the feed had never passed the job on.
	svc.jobs.mu.Lock()
	delete(svc.jobs.running, pid)
	delete(svc.jobs.changed, pid)
	svc.jobs.mu.Unlock()

	svc.adoptJob(ctx, pid, uc.ID, "")
	waitFor(t, followed, "recording the starter should hand the job to the follower")
	gate()
	waitForInbox(t, ctx, svc, uc, "job-finished")
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
	if err := svc.RunHealthSweep(ctx); err != nil {
		t.Fatal(err)
	}
	lost := model.NewPID()
	if err := svc.db.InsertJobOrigin(ctx, wdb.JobOrigin{PID: string(lost), UserID: uc.ID, Rule: ruleMissingLyrics, CreatedAtNS: 1}); err != nil {
		t.Fatal(err)
	}
	if !ruleFixing(t, ctx, svc, ruleMissingLyrics) {
		t.Fatal("the rule does not read as fixing while its job's origin stands")
	}
	markers := healthMarkers(t, ctx, svc, uc)
	svc.followJob(lost)
	waitFor(t, func() bool { return !ruleFixing(t, ctx, svc, ruleMissingLyrics) },
		"the rule should stop reading as fixing once its job is gone")
	waitFor(t, func() bool { return healthMarkers(t, ctx, svc, uc) > markers },
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
		svc.jobs.mu.Lock()
		defer svc.jobs.mu.Unlock()
		_, ok := svc.jobs.running[pid]
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
	svc.jobs.mu.Lock()
	delete(svc.jobs.running, pid)
	delete(svc.jobs.changed, pid)
	svc.jobs.mu.Unlock()

	waitFor(t, followed, "the feed should read the dropped rows from the log")
}
