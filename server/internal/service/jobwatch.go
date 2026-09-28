package service

// Which of the catalog's jobs run now. The newest-jobs window loses a job
// that a burst of others (an upload's imports) came after, so the change
// feed's job rows are kept and read back by pid.

import (
	"context"
	"sync"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/waxerr"
)

// jobWatch holds the jobs the feed saw change since they were last read,
// and the kind of each last read running.
type jobWatch struct {
	mu      sync.Mutex
	changed map[model.PID]struct{}
	running map[model.PID]string
}

func (w *jobWatch) saw(pid model.PID) {
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.changed == nil {
		w.changed = map[model.PID]struct{}{}
	}
	w.changed[pid] = struct{}{}
}

// followedJob names a running job of kind ("" for any) the feed saw. The
// running ones are read again too, so a finish the feed dropped still
// lands.
func (l *Library) followedJob(ctx context.Context, kind string) (model.PID, bool, error) {
	w := &l.jobs
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.running == nil {
		w.running = map[model.PID]string{}
	}
	if w.changed == nil {
		w.changed = map[model.PID]struct{}{}
	}
	for pid := range w.running {
		w.changed[pid] = struct{}{}
	}
	for pid := range w.changed {
		j, err := l.lib.Job(ctx, pid)
		switch {
		case waxerr.CodeOf(err) == waxerr.CodeNotFound:
			delete(w.running, pid)
		case err != nil:
			return "", false, classify(err)
		case j.State == model.JobRunning:
			w.running[pid] = j.Kind
		default:
			delete(w.running, pid)
		}
		delete(w.changed, pid)
	}
	for pid, k := range w.running {
		if kind == "" || k == kind {
			return pid, true, nil
		}
	}
	return "", false, nil
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
