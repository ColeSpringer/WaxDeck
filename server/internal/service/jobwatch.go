package service

// Which of the catalog's jobs run now, and the follower that announces
// them. The newest-jobs window loses a job that a burst of others (an
// upload's imports) came after, so the change feed's job rows are kept and
// read back by pid.

import (
	"cmp"
	"context"
	"encoding/json"
	"errors"
	"sort"
	"sync"
	"time"

	"github.com/colespringer/waxbin/analyze"
	"github.com/colespringer/waxbin/enrich"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/organize"
	"github.com/colespringer/waxbin/scan"
	"github.com/colespringer/waxbin/waxerr"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// jobFollowInterval is how often the follower reads the running jobs,
// whose heartbeats never reach the feed.
const jobFollowInterval = 2 * time.Second

// jobProgressKinds are the jobs whose progress is announced; the rest (a
// delete, a restore, an upload's imports) announce only their end.
var jobProgressKinds = map[string]bool{
	"scan": true, "enrich": true, "organize": true, "analyze": true, "empty-trash": true,
}

// jobWatch holds the jobs the feed saw change since they were last read,
// the kind of each last read running, and what reads found until the
// follower takes it. mu guards the maps only, so the feed never waits on
// a read of the catalog; refresh keeps one read at a time, so reads land
// in the order they were made.
type jobWatch struct {
	refresh sync.Mutex
	mu      sync.Mutex
	changed map[model.PID]struct{}
	running map[model.PID]string
	read    map[model.PID]model.Job
}

func (w *jobWatch) saw(pid model.PID) {
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.changed == nil {
		w.changed = map[model.PID]struct{}{}
	}
	w.changed[pid] = struct{}{}
}

// followJob hands a job to the follower, which reads it at once.
func (l *Library) followJob(pid model.PID) {
	l.jobs.saw(pid)
	select {
	case l.jobWake <- struct{}{}:
	default:
	}
}

// pending reports whether a read is owed: a job ran at the last read, or a
// read found something the follower has not taken.
func (w *jobWatch) pending() bool {
	w.mu.Lock()
	defer w.mu.Unlock()
	return len(w.running) > 0 || len(w.read) > 0
}

// takeRead hands the follower what reads found since it last asked.
func (w *jobWatch) takeRead() []model.Job {
	w.mu.Lock()
	defer w.mu.Unlock()
	out := make([]model.Job, 0, len(w.read))
	for _, j := range w.read {
		out = append(out, j)
	}
	clear(w.read)
	return out
}

// refreshFollowed reads again the jobs the feed saw change and the ones
// last read running, so a finish the feed dropped still lands, and keeps
// each read for the follower.
func (l *Library) refreshFollowed(ctx context.Context) error {
	w := &l.jobs
	w.refresh.Lock()
	defer w.refresh.Unlock()
	w.mu.Lock()
	if w.running == nil {
		w.running = map[model.PID]string{}
	}
	if w.read == nil {
		w.read = map[model.PID]model.Job{}
	}
	pids := make([]model.PID, 0, len(w.changed)+len(w.running))
	for pid := range w.changed {
		pids = append(pids, pid)
	}
	for pid := range w.running {
		if _, ok := w.changed[pid]; !ok {
			pids = append(pids, pid)
		}
	}
	clear(w.changed)
	w.mu.Unlock()

	reads := make(map[model.PID]*model.Job, len(pids))
	for i, pid := range pids {
		j, err := l.lib.Job(ctx, pid)
		switch {
		case waxerr.CodeOf(err) == waxerr.CodeNotFound:
			reads[pid] = nil
		case err != nil:
			// What was not read is owed to the next refresh.
			for _, left := range pids[i:] {
				w.saw(left)
			}
			l.applyReads(reads)
			return classify(err)
		default:
			reads[pid] = j
		}
	}
	l.applyReads(reads)
	return nil
}

// applyReads records what a refresh found; a job gone from the catalog,
// as a restore replaces its jobs, lets go of its origin, or a fix it held
// would read as running until the next start.
func (l *Library) applyReads(reads map[model.PID]*model.Job) {
	w := &l.jobs
	var gone []model.PID
	w.mu.Lock()
	for pid, j := range reads {
		switch {
		case j == nil:
			delete(w.running, pid)
			gone = append(gone, pid)
		case j.State == model.JobRunning:
			w.running[pid] = j.Kind
			w.read[pid] = *j
		default:
			delete(w.running, pid)
			w.read[pid] = *j
		}
	}
	w.mu.Unlock()
	for _, pid := range gone {
		l.releaseLostOrigin(context.WithoutCancel(l.procCtx), pid)
	}
}

// followedJob names a running job of kind ("" for any) the feed saw.
func (l *Library) followedJob(ctx context.Context, kind string) (model.PID, bool, error) {
	if err := l.refreshFollowed(ctx); err != nil {
		return "", false, err
	}
	w := &l.jobs
	w.mu.Lock()
	defer w.mu.Unlock()
	for pid, k := range w.running {
		if kind == "" || k == kind {
			return pid, true, nil
		}
	}
	return "", false, nil
}

// followedRunning lists the running jobs the feed saw.
func (l *Library) followedRunning(ctx context.Context) ([]model.PID, error) {
	if err := l.refreshFollowed(ctx); err != nil {
		return nil, err
	}
	w := &l.jobs
	w.mu.Lock()
	defer w.mu.Unlock()
	out := make([]model.PID, 0, len(w.running))
	for pid := range w.running {
		out = append(out, pid)
	}
	return out, nil
}

// runningJob names a running job of kind ("" for any): one the feed
// followed, or among the newest window jobs one too new for the feed to
// have passed on yet.
func (l *Library) runningJob(ctx context.Context, kind string, window int) (model.PID, bool, error) {
	if pid, ok, err := l.followedJob(ctx, kind); err != nil || ok {
		return pid, ok, err
	}
	jobs, err := l.lib.Jobs(ctx, window)
	if err != nil {
		return "", false, classify(err)
	}
	for _, j := range jobs {
		if j.State == model.JobRunning && (kind == "" || j.Kind == kind) {
			return j.PID, true, nil
		}
	}
	return "", false, nil
}

// jobSeen is what the follower last announced of a job, and when.
type jobSeen struct {
	state   model.JobState
	bucket  int
	message string
	at      time.Time
}

// jobMessageEvery spaces the announcements of a job whose message alone
// moved: the catalog rewrites a scan's every fifty files and an
// enrichment's every target, and a scan's is its only sign of life.
const jobMessageEvery = 15 * time.Second

// jobSeenCap bounds the follower's memory of announced jobs; past it the
// ended ones are forgotten.
const jobSeenCap = 1024

// progressBucket is a fraction in five percent steps.
func progressBucket(p float64) int { return int(p * 20) }

// jobNews reports whether a read of j at now is worth announcing after
// prev (nil when never announced). A job this process never saw that
// ended before it opened is old news: the feed replays rows written
// since its last saved place.
func jobNews(prev *jobSeen, j model.Job, now time.Time, openedAtNS int64) bool {
	if prev != nil && prev.state != model.JobRunning {
		return false
	}
	if prev == nil && j.State != model.JobRunning && j.FinishedAt < openedAtNS {
		return false
	}
	if !jobProgressKinds[j.Kind] {
		return j.State != model.JobRunning
	}
	if prev == nil || prev.state != j.State || prev.bucket != progressBucket(j.Progress) {
		return true
	}
	return prev.message != j.Message && now.Sub(prev.at) >= jobMessageEvery
}

// runJobFollower announces the catalog's jobs to administrators as they
// move and settles each one that ends. A job row on the feed wakes it;
// while a job runs it also reads on a ticker.
func (l *Library) runJobFollower(ctx context.Context) error {
	l.settleOrigins(ctx)
	tick := time.NewTicker(cmp.Or(l.jobFollowEvery, jobFollowInterval))
	defer tick.Stop()
	seen := map[model.PID]jobSeen{}
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-l.jobWake:
		case <-tick.C:
			if !l.jobs.pending() {
				continue
			}
		}
		if err := l.refreshFollowed(ctx); err != nil {
			l.log.Warn("following catalog jobs", "err", err)
			continue
		}
		l.announceJobs(ctx, seen, l.jobs.takeRead())
		if len(seen) > jobSeenCap {
			for pid, s := range seen {
				if s.state != model.JobRunning {
					delete(seen, pid)
				}
			}
		}
	}
}

// announceJobs tells administrators which jobs moved, reading who they
// are once, and settles each that ended.
func (l *Library) announceJobs(ctx context.Context, seen map[model.PID]jobSeen, jobs []model.Job) {
	now := time.Now()
	var news []model.Job
	for _, j := range jobs {
		var prev *jobSeen
		if s, ok := seen[j.PID]; ok {
			prev = &s
		}
		if !jobNews(prev, j, now, l.openedAtNS) {
			continue
		}
		seen[j.PID] = jobSeen{state: j.State, bucket: progressBucket(j.Progress), message: j.Message, at: now}
		news = append(news, j)
	}
	if len(news) == 0 {
		return
	}
	admins, err := l.db.EnabledAdminIDs(ctx)
	if err != nil {
		l.log.Warn("listing administrators for job news", "err", err)
	}
	for _, j := range news {
		for _, id := range admins {
			l.emitUserEvent(ctx, id, eventJob, apiPID(PrefixJob, j.PID))
		}
		if j.State == model.JobRunning {
			continue
		}
		// Most jobs have no one to tell: an upload's imports, deletes,
		// the scheduler's own runs. Only a pass's pictures matter then.
		if j.Kind == "enrich" || l.jobHasOrigin(ctx, j.PID) {
			l.settleLater(func(ctx context.Context) { l.onJobFinished(ctx, &j) })
		}
	}
}

// jobHasOrigin reports whether someone waits to hear a job ended.
func (l *Library) jobHasOrigin(ctx context.Context, pid model.PID) bool {
	has, err := l.db.HasJobOrigin(ctx, string(pid))
	if err != nil {
		l.log.Warn("reading a job's origin", "job", string(pid), "err", err)
		return true
	}
	return has
}

// settleLater runs a job's end off the caller: a fix's re-check reads
// every item failing its rule, and neither the follower, which would hold
// every other job's news behind it, nor a request should wait on that.
func (l *Library) settleLater(settle func(context.Context)) {
	l.workers.GoOnce(l.procCtx, "job-settle", func(ctx context.Context) error {
		settle(ctx)
		return nil
	})
}

// emitEveryoneEvent puts a pid-less marker on every account's stream.
func (l *Library) emitEveryoneEvent(ctx context.Context, kind string) {
	ids, err := l.db.EnabledUserIDs(ctx)
	if err != nil {
		l.log.Warn("listing accounts for an event", "kind", kind, "err", err)
		return
	}
	for _, id := range ids {
		l.emitUserEvent(ctx, id, kind, "")
	}
}

// onJobFinished is a job's end: a pass that gathered pictures moves the
// artwork epoch, so generated playlist covers re-composite, and whoever
// started the job hears of it.
func (l *Library) onJobFinished(ctx context.Context, j *model.Job) {
	if j.Kind == "enrich" && j.Result != "" {
		var res enrich.Result
		if json.Unmarshal([]byte(j.Result), &res) == nil && (res.ArtFetched > 0 || res.AuxArtFetched > 0) {
			l.noteArtworkChanged(ctx)
		}
	}
	l.settleJobOrigin(ctx, j)
}

// adoptJob records who started a job, so its end reaches them, and
// follows it from here, since the feed may have dropped its rows. A job
// that ended before the record landed is settled here: the follower found
// no one to tell.
func (l *Library) adoptJob(ctx context.Context, pid model.PID, userID, rule string) {
	ctx = context.WithoutCancel(ctx)
	if err := l.db.InsertJobOrigin(ctx, wdb.JobOrigin{
		PID: string(pid), UserID: userID, Rule: rule, CreatedAtNS: time.Now().UnixNano(),
	}); err != nil {
		l.log.Warn("recording who started a job", "job", string(pid), "err", err)
		return
	}
	l.followJob(pid)
	if j, err := l.lib.Job(ctx, pid); err == nil && j.State != model.JobRunning {
		l.settleLater(func(ctx context.Context) { l.settleJobOrigin(ctx, j) })
	}
}

// settleJobOrigin tells whoever started an ended job about it, once: the
// follower and the starter may both get here, and one claims the origin.
// The origin goes once the end is told, so a stop in between leaves it
// for the next start.
func (l *Library) settleJobOrigin(ctx context.Context, j *model.Job) {
	o, err := l.db.ClaimJobOrigin(context.WithoutCancel(ctx), string(j.PID), time.Now().UnixNano(), l.openedAtNS)
	if err != nil {
		if !errors.Is(err, wdb.ErrNotFound) {
			l.log.Warn("claiming a job's origin", "job", string(j.PID), "err", err)
		}
		return
	}
	if o.Rule != "" {
		l.finishHealthFixJob(ctx, o, jobDTO(j))
		return
	}
	ctx = context.WithoutCancel(ctx)
	l.notifyJobEnd(ctx, o.UserID, jobDTO(j))
	l.dropJobOrigin(ctx, o.PID)
}

// dropJobOrigin forgets an origin whose job's end has been told.
func (l *Library) dropJobOrigin(ctx context.Context, pid string) {
	if _, err := l.db.DeleteJobOrigin(ctx, pid); err != nil && !errors.Is(err, wdb.ErrNotFound) {
		l.log.Warn("dropping a told job's origin", "job", pid, "err", err)
	}
}

// releaseLostOrigin forgets the origin of a job the catalog no longer
// has, telling every account when it held a fix.
func (l *Library) releaseLostOrigin(ctx context.Context, pid model.PID) {
	rule, err := l.db.DeleteJobOrigin(ctx, string(pid))
	switch {
	case errors.Is(err, wdb.ErrNotFound):
	case err != nil:
		l.log.Warn("dropping a lost job's origin", "job", string(pid), "err", err)
	case rule != "":
		l.emitEveryoneEvent(ctx, eventHealth)
	}
}

// settleOrigins settles the origins whose job ended while no follower ran,
// or whose settle a stop cut short, and follows the ones still running.
func (l *Library) settleOrigins(ctx context.Context) {
	origins, err := l.db.JobOrigins(ctx)
	if err != nil {
		l.log.Warn("listing job origins", "err", err)
		return
	}
	for _, o := range origins {
		j, err := l.lib.Job(ctx, model.PID(o.PID))
		switch {
		case waxerr.CodeOf(err) == waxerr.CodeNotFound:
			l.releaseLostOrigin(ctx, model.PID(o.PID))
		case err != nil:
			l.log.Warn("reading a started job", "job", o.PID, "err", err)
		case j.State == model.JobRunning:
			l.followJob(j.PID)
		default:
			l.settleLater(func(ctx context.Context) { l.settleJobOrigin(ctx, j) })
		}
	}
}

// jobDTO maps a catalog job, with what a finished one did.
func jobDTO(j *model.Job) Job {
	out := Job{
		PID:      apiPID(PrefixJob, j.PID),
		Kind:     j.Kind,
		State:    string(j.State),
		Progress: j.Progress,
		Message:  j.Message,
		Error:    j.Error,
	}
	if j.StartedAt > 0 {
		out.StartedAt = time.Unix(0, j.StartedAt).UTC()
	}
	if j.FinishedAt > 0 {
		out.FinishedAt = time.Unix(0, j.FinishedAt).UTC()
	}
	out.readResult(j.Result)
	return out
}

// sortJobsNewestFirst orders jobs by start, newest first.
func sortJobsNewestFirst(jobs []Job) {
	sort.SliceStable(jobs, func(a, b int) bool { return jobs[a].StartedAt.After(jobs[b].StartedAt) })
}

// readResult reads the summary a finished job recorded, by kind; a kind
// that records none, or a summary that does not parse, leaves it unset.
func (j *Job) readResult(raw string) {
	if raw == "" {
		return
	}
	switch j.Kind {
	case "scan":
		var r scan.Result
		if json.Unmarshal([]byte(raw), &r) == nil {
			j.Scan = &ScanTallyDTO{
				FilesSeen: r.FilesSeen, Created: r.ItemsCreated, Updated: r.ItemsUpdated,
				Relinked: r.Relinked, Unchanged: r.Unchanged, Missing: r.Missing,
				Skipped: r.Skipped, Errored: r.Errored,
			}
		}
	case "analyze":
		var r analyze.Result
		if json.Unmarshal([]byte(raw), &r) == nil {
			j.Analyze = &AnalyzeTallyDTO{
				Analyzed: r.Analyzed, LoudnessMeasured: r.LoudnessMeasured,
				MeasureFailed: r.MeasureFailed, Skipped: r.Skipped, Errored: r.Errored,
			}
		}
	case "enrich":
		var r enrich.Result
		if json.Unmarshal([]byte(raw), &r) == nil {
			j.Enrich = lastRunFrom(r, 0)
		}
	case "organize":
		var r organize.RunResult
		if json.Unmarshal([]byte(raw), &r) == nil {
			j.Organize = &OrganizeTallyDTO{
				Profile: r.Profile, Moved: r.Report.Moved, Skipped: r.Report.Skipped,
				Errored: r.Report.Errored, SidecarsMoved: r.Report.SidecarsMoved,
			}
		}
	}
}
