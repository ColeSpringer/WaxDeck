package service

// The inbox rows that tell an administrator their work ended. The bell
// is the only surface: nothing here pops up.

import (
	"cmp"
	"context"
	"fmt"
	"strings"

	"github.com/colespringer/waxbin/model"
)

// jobNames words a job kind, as its finished and failed titles.
var jobNames = map[string][2]string{
	"scan":        {"Scan finished", "Scan failed"},
	"enrich":      {"Enrichment finished", "Enrichment failed"},
	"analyze":     {"Analysis finished", "Analysis failed"},
	"organize":    {"Organize finished", "Organize failed"},
	"empty-trash": {"Trash emptied", "Emptying the trash failed"},
	"set-kind":    {"Kind changed", "Changing the kind failed"},
}

func jobTitle(kind string, failed bool) string {
	names, ok := jobNames[kind]
	if !ok {
		names = [2]string{"Library job finished", "Library job failed"}
	}
	if failed {
		return names[1]
	}
	return names[0]
}

// jobSubject opens a body with what ran, since the inbox row's own title
// is the event's, not the kind's.
func jobSubject(kind string) string {
	switch kind {
	case "scan":
		return "Scan"
	case "enrich":
		return "Enrichment"
	case "analyze":
		return "Analysis"
	case "organize":
		return "Organize"
	case "empty-trash":
		return "Trash"
	case "set-kind":
		return "Kind change"
	}
	return "Library job"
}

// jobSubjectOf is jobSubject naming the job's target when it has one.
func jobSubjectOf(j Job) string {
	if j.Target != nil && j.Target.Name != "" {
		return jobSubject(j.Kind) + " of " + j.Target.Name
	}
	return jobSubject(j.Kind)
}

// jobBody says what a finished job did, from its summary.
func jobBody(j Job) string {
	subject := jobSubjectOf(j)
	switch {
	case j.Scan != nil:
		r := j.Scan
		body := fmt.Sprintf("%s: %d added, %d updated, %d copies, %d missing, %d errored",
			subject, r.Created, r.Updated, r.Copies, r.Missing, r.Errored)
		if r.WalkErrors > 0 {
			body += fmt.Sprintf(", %d unreadable", r.WalkErrors)
		}
		if r.RootUnreachable {
			body += "; " + unreachableFolders(r)
		}
		return body
	case j.Analyze != nil:
		r := j.Analyze
		body := fmt.Sprintf("%s: %d analyzed, %d measured, %d errored",
			subject, r.Analyzed, r.LoudnessMeasured, r.Errored+r.MeasureFailed)
		if r.FingerprintFallbacks > 0 {
			body += fmt.Sprintf(", %d fingerprints without fpcalc", r.FingerprintFallbacks)
		}
		if r.FingerprintPartialReads > 0 {
			body += fmt.Sprintf(", %d read past an error", r.FingerprintPartialReads)
		}
		return body
	case j.Enrich != nil:
		r := j.Enrich
		body := fmt.Sprintf("%s: lyrics for %d tracks, %d covers and %d other pictures fetched",
			subject, r.LyricsMatched, r.ArtFetched, r.AuxArtFetched)
		if r.Deferred > 0 {
			body += fmt.Sprintf(", %d lookups owed", r.Deferred)
		}
		return body
	case j.Organize != nil:
		r := j.Organize
		return fmt.Sprintf("%s: %d moved, %d skipped, %d errored",
			subject, r.Moved, r.Skipped, r.Errored)
	case j.SetKind != nil:
		r := j.SetKind
		body := fmt.Sprintf("%s: %d changed, %d folded into another item",
			subject, len(r.Converted)+len(r.Created), len(r.Absorbed))
		if n := len(r.WriteBackFailures); n > 0 {
			body += fmt.Sprintf(", %d not written", n)
		}
		return body
	}
	return subject + " finished"
}

// unreachableFolders says which library folder a scan could not reach:
// the one library's, or each named run's under a scan of several.
func unreachableFolders(r *ScanTallyDTO) string {
	if len(r.Runs) > 1 {
		var names []string
		for _, run := range r.Runs {
			if run.RootUnreachable && run.Library != "" {
				names = append(names, run.Library)
			}
		}
		switch len(names) {
		case 0:
			return "a library folder is not reachable"
		case 1:
			return "the folder of " + names[0] + " is not reachable"
		}
		return "the folders of " + strings.Join(names, ", ") + " are not reachable"
	}
	return "the library folder is not reachable"
}

// notifyJobEnd files an ended job in its starter's inbox.
func (l *Library) notifyJobEnd(ctx context.Context, userID string, j Job) {
	if model.JobState(j.State) == model.JobDone {
		l.EmitNotificationFor(ctx, "job-finished", jobTitle(j.Kind, false), jobBody(j), j.PID, []string{userID})
		return
	}
	// The recorded failure names the server's paths, which only an
	// administrator reads, and may name a library its starter is not
	// granted.
	u, err := l.db.UserByID(ctx, userID)
	var uc *UserCtx
	if err == nil {
		uc, err = l.UserCtx(ctx, u)
	}
	switch {
	case err != nil:
		j.Error = l.failureWordsFor(&UserCtx{}, j.Error)
	case !uc.Admin:
		j.Error = l.failureWordsFor(uc, j.Error)
	}
	l.EmitNotificationFor(ctx, "job-failed", jobTitle(j.Kind, true),
		jobSubjectOf(j)+": "+jobFailure(j), j.PID, []string{userID})
}

// jobFailure says why a job did not finish. A server that stopped under
// it is said plainly: the catalog records that as a crashed or canceled
// job, or a failure wrapping a context's "context canceled".
func jobFailure(j Job) string {
	if s := model.JobState(j.State); s == model.JobCrashed || s == model.JobCanceled ||
		strings.Contains(j.Error, context.Canceled.Error()) {
		return "the server stopped before it finished"
	}
	return cmp.Or(j.Error, "no reason was recorded")
}

// notifyWorkDone files the end of work an administrator ran inside their
// own request, which leaves no job for the follower to settle.
func (l *Library) notifyWorkDone(ctx context.Context, uc *UserCtx, j Job) {
	l.EmitNotificationFor(ctx, "job-finished", jobTitle(j.Kind, false), jobBody(j), "", []string{uc.ID})
}

// trashBody says what emptying the trash did.
func trashBody(t TrashEmptyDTO) string {
	body := fmt.Sprintf("Trash: %d files purged, %s reclaimed, %d errored",
		t.Purged, sizeWords(t.ReclaimedBytes), t.Errored)
	if t.SkippedReadOnly > 0 {
		body += fmt.Sprintf(", %d kept in read-only libraries", t.SkippedReadOnly)
	}
	return body
}

// sizeWords is a byte count as a person reads it.
func sizeWords(n int64) string {
	const unit = 1000
	if n < unit {
		return fmt.Sprintf("%d B", n)
	}
	div, exp := int64(unit), 0
	for m := n / unit; m >= unit; m /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %cB", float64(n)/float64(div), "kMGTPE"[exp])
}
