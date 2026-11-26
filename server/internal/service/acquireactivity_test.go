package service

import (
	"context"
	"errors"
	"io"
	"slices"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxbin/source"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/syncsource"
)

// eventfulSource lists three videos and fetches each as a few bytes,
// telling the fetch's caller what it does as it goes; fetching runs once
// per fetch, and a fetch of the held video waits there for release.
type eventfulSource struct {
	stagingSource
	// events is what the fetch of the video id reports before its bytes.
	events map[string][]syncsource.FetchEvent
	// hold, when set, is the video whose fetch reports its events and
	// then waits for release, or, with no release, for its end.
	hold     string
	release  chan struct{}
	fetching chan string
	// deaf holds the fetch until release even once its context is done,
	// answering the context's error then.
	deaf bool
}

func (s *eventfulSource) FetchWith(ctx context.Context, req source.FetchRequest, w io.Writer, opts syncsource.FetchOptions) (*source.FetchResult, error) {
	id := req.URL[strings.LastIndexByte(req.URL, '=')+1:]
	for _, e := range s.events[id] {
		if opts.OnEvent != nil {
			opts.OnEvent(e)
		}
	}
	if s.fetching != nil {
		s.fetching <- id
	}
	if id == s.hold && s.deaf {
		<-s.release
		if err := ctx.Err(); err != nil {
			return nil, err
		}
	} else if id == s.hold {
		select {
		case <-s.release:
		case <-ctx.Done():
			return nil, ctx.Err()
		}
	}
	return s.stagingSource.Fetch(ctx, req, w)
}

// taskProgressMarks counts the task-progress markers the account got for
// a task.
func taskProgressMarks(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, taskID string) int {
	t.Helper()
	n := 0
	for _, e := range eventsAfter(t, ctx, svc, uc, 0) {
		if e.Kind == eventTaskProgress && e.ItemPID == taskID {
			n++
		}
	}
	return n
}

// While an acquisition downloads, the task says what it is doing: its
// phase, the item in hand of how many, that item's bytes and when it last
// moved, and its progress moves within the item. Once it ends it says
// nothing more.
func TestARunningAcquisitionSaysWhatItIsDoing(t *testing.T) {
	t.Parallel()
	src := &eventfulSource{
		events: map[string][]syncsource.FetchEvent{"two": {
			{Phase: syncsource.PhaseDownloading},
			{Phase: syncsource.PhaseDownloading, Bytes: 4_200_000, Total: 9_800_000},
		}},
		hold: "two", release: make(chan struct{}), fetching: make(chan string, 3),
	}
	ctx, svc, uc := acquireFixture(t, src)
	task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/playlist?list=PLthree", false, "music", "", "", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	ran := make(chan bool)
	go func() { ran <- svc.Tools.DrainSourceToolTasks(ctx) }()
	for id := range src.fetching {
		if id == "two" {
			break
		}
	}
	dto, err := svc.Tools.GetToolTaskFor(ctx, uc, task.ID)
	if err != nil {
		t.Fatal(err)
	}
	a := dto.Activity
	if a == nil {
		close(src.release)
		<-ran
		t.Fatalf("a downloading task reads %+v with no activity", dto)
	}
	if a.Phase != "downloading" || a.ItemsDone != 1 || a.ItemsTotal != 3 || a.ItemTitle != "two" ||
		a.BytesDone != 4_200_000 || a.BytesTotal != 9_800_000 {
		t.Errorf("activity = %+v, want downloading the second of three, 4.2 of 9.8 MB", *a)
	}
	if since := time.Since(time.Unix(0, a.AtNS)); since < 0 || since > time.Minute {
		t.Errorf("activity at %v ago, want just now", since)
	}
	// One item of three is 30 of the run's 90; the second's bytes add to it.
	if want := (1 + 4.2/9.8) / 3 * 90; dto.ProgressPct < want-0.01 || dto.ProgressPct > want+0.01 {
		t.Errorf("progress = %.2f, want %.2f: the items done and the item in hand's share", dto.ProgressPct, want)
	}
	close(src.release)
	if !<-ran {
		t.Fatal("the worker found no task to run")
	}
	dto, err = svc.Tools.GetToolTaskFor(ctx, uc, task.ID)
	if err != nil {
		t.Fatal(err)
	}
	if dto.State != taskStateDone || dto.Activity != nil {
		t.Errorf("the finished task reads %s with activity %+v, want done with none", dto.State, dto.Activity)
	}
}

// A download reporting a thousand times tells the task's watchers a
// bounded number of times: on each change of phase, and at most once
// every two seconds within one.
func TestManyEventsMarkTheTaskABoundedNumberOfTimes(t *testing.T) {
	t.Parallel()
	var burst []syncsource.FetchEvent
	for i := range 1000 {
		burst = append(burst, syncsource.FetchEvent{Phase: syncsource.PhaseDownloading, Bytes: int64(i) * 1000, Total: 1_000_000})
	}
	src := &eventfulSource{events: map[string][]syncsource.FetchEvent{"one": burst, "two": burst, "three": burst}}
	ctx, svc, uc := acquireFixture(t, src)
	task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/playlist?list=PLthree", false, "music", "", "", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	start := time.Now()
	drainOnce(t, ctx, svc)
	elapsed := time.Since(start)
	if row := storedTask(t, ctx, svc, task.ID); row.State != taskStateDone {
		t.Fatalf("task = %s (error %q), want done", row.State, row.Error)
	}
	// Listing, then per item a download and an import, and each item's
	// recorded progress, and one per two seconds the run took.
	bound := 1 + 3*2 + 3 + int(elapsed/(2*time.Second)) + 1
	n := taskProgressMarks(t, ctx, svc, uc, task.ID)
	t.Logf("%d markers over %v, bound %d", n, elapsed, bound)
	if n == 0 || n > bound {
		t.Errorf("%d task-progress markers for 3000 events over %v, want between 1 and %d", n, elapsed, bound)
	}
}

// A download that reports once and then shows nothing for the stall
// window is stopped, and the task waits as stalled to try again, no
// attempt spent and no activity shown.
func TestAStalledDownloadWaitsToTryAgain(t *testing.T) {
	t.Parallel()
	src := &eventfulSource{
		events: map[string][]syncsource.FetchEvent{"two": {{Phase: syncsource.PhaseDownloading, Bytes: 1000, Total: 9000}}},
		hold:   "two", release: make(chan struct{}),
	}
	ctx, svc, uc := acquireFixture(t, src)
	svc.Ingest.acquireStallWindow = 200 * time.Millisecond
	task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/playlist?list=PLthree", false, "music", "", "", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	done := make(chan struct{})
	go func() {
		defer close(done)
		svc.Tools.DrainSourceToolTasks(ctx)
	}()
	select {
	case <-done:
	case <-time.After(30 * time.Second):
		close(src.release)
		<-done
		t.Fatal("a stalled download was not stopped")
	}
	row := storedTask(t, ctx, svc, task.ID)
	if row.State != taskStateRunning || row.WaitReason != "stalled" || row.Attempts != 0 || !strings.Contains(row.Error, "stopped moving") {
		t.Fatalf("task = %s waiting on %q after %d attempts (error %q), want it waiting as stalled, no attempt spent",
			row.State, row.WaitReason, row.Attempts, row.Error)
	}
	dto := queuedTasks(t, ctx, svc, uc)[0]
	if dto.WaitReason != "stalled" || dto.Activity != nil {
		t.Errorf("the task reads waiting on %q with activity %+v, want stalled and none", dto.WaitReason, dto.Activity)
	}
}

// A playlist sync skips an item that fails on its own, but a stalled one
// stops the batch: the link, not the video, stopped moving.
func TestAStallStopsASyncsBatch(t *testing.T) {
	t.Parallel()
	src := &eventfulSource{
		events: map[string][]syncsource.FetchEvent{"one": {{Phase: syncsource.PhaseDownloading}}},
		hold:   "one", release: make(chan struct{}),
	}
	ctx, svc, uc := acquireFixture(t, src)
	svc.Ingest.acquireStallWindow = 200 * time.Millisecond
	task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/playlist?list=PLthree", false, "music", "", "", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	row := storedTask(t, ctx, svc, task.ID)
	items := []acquireItem{
		{Title: "one", URL: "https://tube.example/watch?v=one", GUID: "one"},
		{Title: "two", URL: "https://tube.example/watch?v=two", GUID: "two"},
	}
	release := svc.Tools.holdToolTask(row.ID, nil)
	_, staged, skipped, ferr, _ := svc.Ingest.fetchAcquireBatch(ctx, &row, toolTaskParams{MediaType: "music"}, src, items, "", uc, 95, true)
	release()
	if !errors.Is(ferr, errFetchStalled) || staged != 0 || skipped != 0 {
		t.Errorf("batch staged %d, skipped %d, err %v; want it stopped at the stall", staged, skipped, ferr)
	}
	if got := src.fetchCounts()["https://tube.example/watch?v=two"]; got != 0 {
		t.Errorf("the item after the stall was fetched %d times, want none", got)
	}
}

// activityLog is every activity runs here record, in order.
type activityLog struct {
	mu   sync.Mutex
	seen []ToolTaskActivity
}

func recordActivity(svc *Library) *activityLog {
	log := &activityLog{}
	svc.Tools.activityHook = func(_ string, a ToolTaskActivity) {
		log.mu.Lock()
		defer log.mu.Unlock()
		log.seen = append(log.seen, a)
	}
	return log
}

// phases are the phases recorded, a run of one phase once.
func (l *activityLog) phases() []string {
	l.mu.Lock()
	defer l.mu.Unlock()
	var out []string
	for _, a := range l.seen {
		if len(out) == 0 || out[len(out)-1] != a.Phase {
			out = append(out, a.Phase)
		}
	}
	return out
}

func (l *activityLog) all() []ToolTaskActivity {
	l.mu.Lock()
	defer l.mu.Unlock()
	return slices.Clone(l.seen)
}

// Once every item of a batch staged, its closing import counts them all.
func TestTheClosingImportCountsEveryItemDone(t *testing.T) {
	t.Parallel()
	src := &stagingSource{}
	ctx, svc, uc := acquireFixture(t, src)
	task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/playlist?list=PLthree", false, "music", "", "", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	row := storedTask(t, ctx, svc, task.ID)
	items := []acquireItem{
		{Title: "one", URL: "https://tube.example/watch?v=one", GUID: "one"},
		{Title: "two", URL: "https://tube.example/watch?v=two", GUID: "two"},
		{Title: "three", URL: "https://tube.example/watch?v=three", GUID: "three"},
	}
	release := svc.Tools.holdToolTask(row.ID, nil)
	defer release()
	if _, staged, _, ferr, eerr := svc.Ingest.fetchAcquireBatch(ctx, &row, toolTaskParams{MediaType: "music"}, src, items, "", uc, 90, false); staged != 3 || ferr != nil || eerr != nil {
		t.Fatalf("batch staged %d (%v, %v), want all three", staged, ferr, eerr)
	}
	if a, _ := svc.Tools.activityOf(row.ID); a.Phase != activityImporting || a.ItemsDone != 3 || a.ItemsTotal != 3 {
		t.Errorf("the closing import reads %+v, want importing three of three", a)
	}
}

// A change of phase tells the task's watchers at once, and activity
// within one phase at most every two seconds.
func TestAChangeOfPhaseMarksAtOnce(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := acquireFixture(t, &stagingSource{})
	task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/playlist?list=PLthree", false, "music", "", "", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	release := svc.Tools.holdToolTask(task.ID, nil)
	defer release()
	before := taskProgressMarks(t, ctx, svc, uc, task.ID)
	svc.Tools.noteActivity(ctx, task.ID, func(a *ToolTaskActivity) { a.Phase = activityListing })
	svc.Tools.noteActivity(ctx, task.ID, func(a *ToolTaskActivity) { a.Phase = activityDownloading })
	svc.Tools.noteActivity(ctx, task.ID, func(a *ToolTaskActivity) { a.BytesDone = 10 })
	if got := taskProgressMarks(t, ctx, svc, uc, task.ID) - before; got != 2 {
		t.Errorf("%d markers, want one per change of phase and none for the bytes inside two seconds", got)
	}
}

// busyWriterSource holds the store's writer while it reports a change of
// phase, and records how long the report took to come back.
type busyWriterSource struct {
	eventfulSource
	svc  *Library
	took atomic.Int64
}

func (s *busyWriterSource) FetchWith(ctx context.Context, req source.FetchRequest, w io.Writer, opts syncsource.FetchOptions) (*source.FetchResult, error) {
	if strings.HasSuffix(req.URL, "=one") && opts.OnEvent != nil {
		tx, err := s.svc.db.Writer().BeginTx(ctx, nil)
		if err != nil {
			return nil, err
		}
		if _, err := tx.ExecContext(ctx, `UPDATE tool_tasks SET attempts = attempts`); err != nil {
			_ = tx.Rollback()
			return nil, err
		}
		end := time.AfterFunc(time.Second, func() { _ = tx.Rollback() })
		start := time.Now()
		opts.OnEvent(syncsource.FetchEvent{Phase: syncsource.PhaseProcessing})
		s.took.Store(int64(time.Since(start)))
		end.Stop()
		_ = tx.Rollback()
	}
	return s.stagingSource.Fetch(ctx, req, w)
}

// What a download reports comes back to it at once, whatever the store is
// doing: telling the task's watchers waits for the store elsewhere.
func TestADownloadsReportNeverWaitsOnTheStore(t *testing.T) {
	t.Parallel()
	src := &busyWriterSource{}
	ctx, svc, uc := acquireFixture(t, src)
	src.svc = svc
	startTaskMarkers(t, ctx, svc, nil)
	task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/watch?v=one", false, "music", "", "", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	drainOnce(t, ctx, svc)
	if took := time.Duration(src.took.Load()); took <= 0 || took > 500*time.Millisecond {
		t.Errorf("a change of phase took %v to report with the store busy, want it back at once", took)
	}
	deadline := time.Now().Add(10 * time.Second)
	for taskProgressMarks(t, ctx, svc, uc, task.ID) == 0 {
		if time.Now().After(deadline) {
			t.Fatal("the change of phase never told the task's watchers")
		}
		time.Sleep(20 * time.Millisecond)
	}
}

// A fetch that hangs before its download reports anything (the source's
// look-up of the video, say) is stopped as stalled too.
func TestADownloadThatNeverStartsIsStopped(t *testing.T) {
	t.Parallel()
	src := &eventfulSource{hold: "two", release: make(chan struct{})}
	ctx, svc, uc := acquireFixture(t, src)
	svc.Ingest.acquireStallWindow = 200 * time.Millisecond
	task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/playlist?list=PLthree", false, "music", "", "", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	done := make(chan struct{})
	go func() {
		defer close(done)
		svc.Tools.DrainSourceToolTasks(ctx)
	}()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		close(src.release)
		<-done
		t.Fatal("a fetch that never reported was not stopped")
	}
	if row := storedTask(t, ctx, svc, task.ID); row.WaitReason != "stalled" {
		t.Errorf("task = %s waiting on %q (error %q), want it waiting as stalled", row.State, row.WaitReason, row.Error)
	}
}

// stallingLister is a playlist listing three videos whose fetches report
// as eventfulSource's do.
type stallingLister struct{ eventfulSource }

func (s *stallingLister) PlaylistSnapshot(context.Context, string, syncsource.SnapshotOptions) (*syncsource.PlaylistSnapshot, error) {
	snap := &syncsource.PlaylistSnapshot{ID: "PLthree", IdentityKey: "youtube:PLthree", Title: "Three"}
	for i, id := range []string{"one", "two", "three"} {
		snap.Entries = append(snap.Entries, syncsource.PlaylistSnapshotEntry{ID: id, Index: i, URL: "https://tube.example/watch?v=" + id, Title: id})
	}
	return snap, nil
}

// boundPlaylist is a playlist of the account's bound to the listing's link.
func boundPlaylist(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx) string {
	t.Helper()
	pid := playlistAs(t, ctx, svc, uc, "Three", "private", nil)
	_, bare, _ := parseAPIPID(pid)
	now := time.Now().UnixNano()
	if err := svc.db.PutPlaylistSource(ctx, wdb.PlaylistSourceRow{
		PlaylistPID: string(bare), Source: "youtube", Live: true,
		URL: "https://tube.example/playlist?list=PLthree", IdentityKey: "youtube:PLthree",
		SourceID: "PLthree", Title: "Three", Mode: "append", IntervalHours: 1,
		CreatedAtNS: now, UpdatedAtNS: now,
	}); err != nil {
		t.Fatal(err)
	}
	return pid
}

// A playlist sync whose download stalls waits as stalled to try again,
// and between listing its source and downloading it says it is working
// out what changed, not still listing.
func TestASyncRunWaitsOutAStalledDownload(t *testing.T) {
	t.Parallel()
	src := &stallingLister{eventfulSource{
		events: map[string][]syncsource.FetchEvent{"one": {{Phase: syncsource.PhaseDownloading}}},
		hold:   "one", release: make(chan struct{}),
	}}
	ctx, svc, uc := acquireFixture(t, src)
	svc.Ingest.acquireStallWindow = 200 * time.Millisecond
	log := recordActivity(svc)
	pid := boundPlaylist(t, ctx, svc, uc)
	task, err := svc.Playlists.SyncPlaylistSourceNow(ctx, uc, pid)
	if err != nil {
		t.Fatal(err)
	}
	drainOnce(t, ctx, svc)
	if row := storedTask(t, ctx, svc, task.ID); row.State != taskStateRunning || row.WaitReason != "stalled" || row.Attempts != 0 {
		t.Fatalf("sync = %s waiting on %q after %d attempts (error %q), want it waiting as stalled, no attempt spent",
			row.State, row.WaitReason, row.Attempts, row.Error)
	}
	if got, want := log.phases(), []string{activityListing, activityProcessing, activityDownloading}; !slices.Equal(got[:min(len(got), 3)], want) {
		t.Errorf("phases %v, want them to start %v", got, want)
	}
}

// Asking a sync that is running to sync now answers that run, saying what
// it is doing.
func TestSyncingNowWhileASyncRunsSaysWhatItDoes(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := acquireFixture(t, &stallingLister{})
	pid := boundPlaylist(t, ctx, svc, uc)
	task, err := svc.Playlists.SyncPlaylistSourceNow(ctx, uc, pid)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := svc.db.Writer().ExecContext(ctx, `UPDATE tool_tasks SET state = 'running' WHERE id = ?`, task.ID); err != nil {
		t.Fatal(err)
	}
	release := svc.Tools.holdToolTask(task.ID, nil)
	defer release()
	svc.Tools.noteActivity(ctx, task.ID, func(a *ToolTaskActivity) { a.Phase = activityListing })
	again, err := svc.Playlists.SyncPlaylistSourceNow(ctx, uc, pid)
	if err != nil {
		t.Fatal(err)
	}
	if again.ID != task.ID || again.Activity == nil || again.Activity.Phase != activityListing {
		t.Errorf("sync now = %s with activity %+v, want the running %s listing", again.ID, again.Activity, task.ID)
	}
}

// windDown makes a task one that runs on after its cancel, as a run
// finishing its current step does.
func windDown(t *testing.T, ctx context.Context, svc *Library, id string) {
	t.Helper()
	if _, err := svc.db.Writer().ExecContext(ctx, `UPDATE tool_tasks SET state = 'running', cancel_requested = 1 WHERE id = ?`, id); err != nil {
		t.Fatal(err)
	}
}

// A sync winding down from its cancel is no sync under way: Sync now and
// the schedule each queue a fresh run.
func TestASyncWindingDownFromACancelLetsAFreshRunQueue(t *testing.T) {
	t.Parallel()
	for _, how := range []string{"now", "scheduled"} {
		t.Run(how, func(t *testing.T) {
			t.Parallel()
			ctx, svc, uc := acquireFixture(t, &stallingLister{})
			pid := boundPlaylist(t, ctx, svc, uc)
			first, err := svc.Playlists.SyncPlaylistSourceNow(ctx, uc, pid)
			if err != nil {
				t.Fatal(err)
			}
			windDown(t, ctx, svc, first.ID)
			if how == "now" {
				again, err := svc.Playlists.SyncPlaylistSourceNow(ctx, uc, pid)
				if err != nil {
					t.Fatal(err)
				}
				if again.ID == first.ID || again.State != taskStateQueued {
					t.Errorf("sync now = %s (%s), want a fresh queued run beside the canceled %s", again.ID, again.State, first.ID)
				}
				return
			}
			svc.Playlists.SyncDuePlaylistSources(ctx)
			var queued int
			if err := svc.db.Reader().QueryRowContext(ctx, `SELECT COUNT(*) FROM tool_tasks WHERE type = ? AND state = 'queued'`, taskTypePlaylistSync).Scan(&queued); err != nil {
				t.Fatal(err)
			}
			if queued != 1 {
				t.Errorf("the schedule queued %d runs beside the canceled one, want one", queued)
			}
		})
	}
}

// An engine tool says what it does: processing while the engine works and
// while it fetches each output (never downloading, the phase of a byte
// stream), then importing as it takes them into the library.
func TestAnEngineToolSaysWhatItIsDoing(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, book, _, engine := chapteredBookFixture(t)
	engine.running = 1
	log := recordActivity(svc)
	task, err := svc.Tools.StartBookSplit(ctx, uc, apiPID(PrefixBook, book), false)
	if err != nil {
		t.Fatal(err)
	}
	if err := attempt(t, ctx, svc, 1); err != nil {
		t.Fatalf("the split = %v", err)
	}
	if row := toolTask(t, ctx, svc, task.ID); row.State != taskStateDone {
		t.Fatalf("split = %s (error %q), want it done", row.State, row.Error)
	}
	if got, want := log.phases(), []string{activityProcessing, activityImporting}; !slices.Equal(got, want) {
		t.Errorf("phases %v, want %v", got, want)
	}
	all := log.all()
	var fetching []int
	for _, a := range all {
		if a.ItemsTotal != 0 {
			if a.ItemsTotal != 3 || a.Phase != activityProcessing {
				t.Errorf("fetching an output reads %+v, want one of three", a)
			}
			fetching = append(fetching, a.ItemsDone)
		}
	}
	if !slices.Equal(fetching, []int{0, 1, 2}) {
		t.Errorf("fetched outputs after %v done, want each of three in turn", fetching)
	}
	if last := all[len(all)-1]; last.Phase != activityImporting || last.ItemsTotal != 0 {
		t.Errorf("the scan-in reads %+v, want it importing past the outputs", last)
	}
}

// A genre sweep counts its items against what it has in all; one whose
// count failed has no total, never one that says it is complete.
func TestAGenreSweepCountsItsItems(t *testing.T) {
	t.Parallel()
	if got := genreSweepTotal(120, 0); got != 0 {
		t.Errorf("total with no count = %d, want it unknown", got)
	}
	if got := genreSweepTotal(120, 100); got != 120 {
		t.Errorf("total past the count = %d, want what was done", got)
	}
	f := newGenreFixture(t)
	log := recordActivity(f.svc)
	if _, err := f.svc.Reads.StartGenreNormalize(f.ctx, f.uc, true); err != nil {
		t.Fatal(err)
	}
	f.drainTasks(t)
	seen := log.all()
	if len(seen) == 0 {
		t.Fatal("the sweep recorded no activity")
	}
	last := seen[len(seen)-1]
	if last.Phase != activityProcessing || last.ItemsTotal == 0 || last.ItemsDone != last.ItemsTotal {
		t.Errorf("the sweep ends reading %+v, want processing every item of its count", last)
	}
}

// An import says which of its items it is on, of how many.
func TestAnImportCountsItsItems(t *testing.T) {
	t.Parallel()
	ctx, f := newMigrateFixture(t)
	ts := newFakeNavidrome(t, "demo", "demo-pass")
	log := recordActivity(f.svc)
	dto, err := f.svc.Migrate.StartMigration(ctx, f.uc, MigrationRequest{
		Source: "navidrome", ServerURL: ts.URL, Username: "demo", Password: "demo-pass",
		Stars: true, Ratings: true, History: true, Progress: true, DryRun: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	row := storedTask(t, ctx, f.svc, dto.ID)
	release := f.svc.Tools.holdToolTask(row.ID, nil)
	err = f.svc.Migrate.runMigrationTask(ctx, &row)
	release()
	if err != nil {
		t.Fatal(err)
	}
	var importing []ToolTaskActivity
	for _, a := range log.all() {
		if a.Phase == activityImporting {
			importing = append(importing, a)
		}
	}
	if len(importing) == 0 {
		t.Fatal("the import recorded no items")
	}
	for _, a := range importing {
		if a.ItemsTotal <= 0 || a.ItemsDone > a.ItemsTotal {
			t.Errorf("importing reads %d of %d, want a place among a known total", a.ItemsDone, a.ItemsTotal)
		}
	}
	if last := importing[len(importing)-1]; last.ItemsDone != last.ItemsTotal {
		t.Errorf("the import ends on %d of %d, want the last", last.ItemsDone, last.ItemsTotal)
	}
}

// One item's bound is a backstop behind the stall watch: a long video over
// a slow link that keeps moving has an hour to download and transcode.
func TestTheItemBoundIsABackstopBehindTheStallWatch(t *testing.T) {
	t.Parallel()
	if acquireItemTimeout < time.Hour {
		t.Errorf("one item is bounded at %v, want at least an hour", acquireItemTimeout)
	}
}
