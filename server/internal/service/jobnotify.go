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
	}
	return "Library job"
}

// jobBody says what a finished job did, from its summary.
func jobBody(j Job) string {
	subject := jobSubject(j.Kind)
	switch {
	case j.Scan != nil:
		r := j.Scan
		return fmt.Sprintf("%s: %d added, %d updated, %d missing, %d errored",
			subject, r.Created, r.Updated, r.Missing, r.Errored)
	case j.Analyze != nil:
		r := j.Analyze
		return fmt.Sprintf("%s: %d analyzed, %d measured, %d errored",
			subject, r.Analyzed, r.LoudnessMeasured, r.Errored+r.MeasureFailed)
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
	}
	return subject + " finished"
}

// notifyJobEnd files an ended job in its starter's inbox.
func (l *Library) notifyJobEnd(ctx context.Context, userID string, j Job) {
	if model.JobState(j.State) == model.JobDone {
		l.EmitNotificationFor(ctx, "job-finished", jobTitle(j.Kind, false), jobBody(j), j.PID, []string{userID})
		return
	}
	l.EmitNotificationFor(ctx, "job-failed", jobTitle(j.Kind, true),
		jobSubject(j.Kind)+": "+jobFailure(j), j.PID, []string{userID})
}

// jobFailure says why a job did not finish. A server that stopped under
// it is said plainly: the catalog records that as "reclaimed: owner not
// live" or a context's "context canceled".
func jobFailure(j Job) string {
	if model.JobState(j.State) == model.JobCrashed || strings.Contains(j.Error, context.Canceled.Error()) {
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
	return fmt.Sprintf("Trash: %d files purged, %s reclaimed, %d errored",
		t.Purged, sizeWords(t.ReclaimedBytes), t.Errored)
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
