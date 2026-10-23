package service

import (
	"context"
	"encoding/json"
	"log/slog"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// takenOut adds a library and takes it out of the catalog directly, as a
// removal's job does before it ends; the follower leaves that job to the
// settle the test drives, as it does one the console started.
func takenOut(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, name string) (LibraryInfo, string, *model.RemoveRootReport) {
	t.Helper()
	dir := t.TempDir()
	lib, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: name, Path: dir})
	if err != nil {
		t.Fatal(err)
	}
	_, bare, _ := parseAPIPID(lib.PID)
	waitFor(t, func() bool {
		running, err := svc.catalogJobRunning(ctx)
		return err == nil && !running
	}, "the create's scan to end")
	svc.removals.begin(bare, removal{name: name, path: dir, userID: uc.ID})
	rep, err := svc.lib.RemoveRoot(ctx, bare, waxbin.RemoveRootOptions{})
	if err != nil {
		t.Fatal(err)
	}
	return lib, dir, rep
}

// endedRemoval is a removal job's end as the settle reads it, its origin
// holding what the console recorded at the start.
func endedRemoval(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, lib LibraryInfo, dir string, state model.JobState, rep *model.RemoveRootReport) *model.Job {
	t.Helper()
	_, bare, _ := parseAPIPID(lib.PID)
	j := &model.Job{
		PID: model.NewPID(), Kind: "remove-root", State: state, TargetType: "library", TargetPID: bare,
		StartedAt: time.Now().UnixNano(), FinishedAt: time.Now().UnixNano(),
	}
	if rep != nil {
		raw, err := json.Marshal(rep)
		if err != nil {
			t.Fatal(err)
		}
		j.Result = string(raw)
	}
	if state == model.JobFailed {
		j.Error = "the removal stopped"
	}
	detail, err := json.Marshal(removalFacts{Name: lib.Name, Path: dir})
	if err != nil {
		t.Fatal(err)
	}
	if err := svc.db.InsertJobOrigin(ctx, wdb.JobOrigin{
		PID: string(j.PID), UserID: uc.ID, Detail: string(detail), CreatedAtNS: 1,
	}); err != nil {
		t.Fatal(err)
	}
	return j
}

// inboxSays reports whether the account's inbox holds a row about the job
// with this title.
func inboxSays(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, j *model.Job, title string) bool {
	t.Helper()
	page, err := svc.Notifications(ctx, uc, "", 50)
	if err != nil {
		t.Fatal(err)
	}
	return slices.ContainsFunc(page.Notifications, func(n InboxNotification) bool {
		return n.TargetPID == apiPID(PrefixJob, j.PID) && n.Title == title
	})
}

// A removal whose job ended crashed or canceled after the catalog let the
// library go is followed up all the same, and its starter is told it was
// removed: the cleanup goes by what the catalog holds, not by the job's
// last state. Counts are recorded when the job kept a report.
func TestARemovalThatEndedBadlyAfterTheLibraryWentIsFollowedUp(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := openServiceAt(t, t.TempDir(), nil)
	flow := &fakeFlowRoots{names: []string{"configured"}}
	svc.SetFlowRoots(flow)
	books, booksDir, _ := takenOut(t, ctx, svc, uc, "books")
	member := memberCtx(t, ctx, svc, "member", books.PID)
	crashed := endedRemoval(t, ctx, svc, uc, books, booksDir, model.JobCrashed, nil)
	svc.settleJobOrigin(ctx, crashed)

	audit := removalAudit(t, ctx, svc, books.PID)
	if audit == nil || audit.ActorID != uc.ID || audit.TargetName != "books" || audit.Detail["path"] != booksDir {
		t.Fatalf("audit = %+v, want books' removal under its starter", audit)
	}
	if _, counted := audit.Detail["filesDetached"]; counted {
		t.Errorf("audit detail = %v, want no counts from a job that kept no report", audit.Detail)
	}
	if stored, err := svc.db.LibraryRootsList(ctx); err != nil || slices.ContainsFunc(stored, func(r wdb.LibraryRoot) bool { return r.Name == "books" }) {
		t.Errorf("stored names = %+v (%v), want books' gone", stored, err)
	}
	if u, err := svc.db.UserByID(ctx, member.ID); err != nil {
		t.Fatal(err)
	} else if uc2, err := svc.UserCtx(ctx, u); err != nil || uc2.AllLibraries || len(uc2.Libraries) != 0 {
		t.Errorf("a member granted only books now sees all=%v %v (%v), want nothing", uc2.AllLibraries, uc2.Libraries, err)
	}
	flow.mu.Lock()
	removed := slices.Clone(flow.removed)
	flow.mu.Unlock()
	if !slices.Equal(removed, []string{"books"}) {
		t.Errorf("the bridge removed %v, want books", removed)
	}
	if !inboxSays(t, ctx, svc, uc, crashed, "Library removed") {
		t.Error("the starter was not told the library was removed")
	}

	tapes, tapesDir, rep := takenOut(t, ctx, svc, uc, "tapes")
	canceled := endedRemoval(t, ctx, svc, uc, tapes, tapesDir, model.JobCanceled, rep)
	svc.settleJobOrigin(ctx, canceled)
	if audit := removalAudit(t, ctx, svc, tapes.PID); audit == nil || audit.Detail["filesDetached"] != float64(rep.FilesDetached) {
		t.Errorf("audit = %+v, want tapes' removal with the report's counts", audit)
	}
}

// A removal stopped before the catalog let the library go leaves all of it
// - its name, its grants, its mount - and its starter is told it failed.
func TestARemovalStoppedBeforeTheLibraryWentLeavesItAll(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := openServiceAt(t, t.TempDir(), nil)
	flow := &fakeFlowRoots{names: []string{"configured"}}
	svc.SetFlowRoots(flow)
	dir := t.TempDir()
	spare, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "spare", Path: dir})
	if err != nil {
		t.Fatal(err)
	}
	member := memberCtx(t, ctx, svc, "member", spare.PID)
	failed := endedRemoval(t, ctx, svc, uc, spare, dir, model.JobFailed, nil)
	svc.settleJobOrigin(ctx, failed)

	if audit := removalAudit(t, ctx, svc, spare.PID); audit != nil {
		t.Errorf("audit = %+v, want none for a library still there", audit)
	}
	if stored, err := svc.db.LibraryRootsList(ctx); err != nil || !slices.ContainsFunc(stored, func(r wdb.LibraryRoot) bool { return r.Name == "spare" }) {
		t.Errorf("stored names = %+v (%v), want spare's kept", stored, err)
	}
	if acct, err := svc.Account(ctx, member.ID); err != nil || !slices.Equal(acct.LibraryPIDs, []string{spare.PID}) {
		t.Errorf("the member's grants = %v (%v), want spare kept", acct.LibraryPIDs, err)
	}
	flow.mu.Lock()
	removed := slices.Clone(flow.removed)
	flow.mu.Unlock()
	if len(removed) != 0 {
		t.Errorf("the bridge removed %v, want nothing", removed)
	}
	if !inboxSays(t, ctx, svc, uc, failed, "Removing the library failed") {
		t.Error("the starter was not told the removal failed")
	}
}

// A folder added again while its old library's removal was still ending
// keeps the new library's name and mount: only what was the removed
// library's goes.
func TestALibraryAddedAgainAtTheFolderKeepsItsName(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := openServiceAt(t, t.TempDir(), nil)
	flow := &fakeFlowRoots{names: []string{"configured"}}
	svc.SetFlowRoots(flow)
	books, dir, rep := takenOut(t, ctx, svc, uc, "books")
	again, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "audio", Path: dir})
	if err != nil {
		t.Fatal(err)
	}
	done := endedRemoval(t, ctx, svc, uc, books, dir, model.JobDone, rep)
	svc.settleJobOrigin(ctx, done)

	if lib := libraryAt(t, ctx, svc, dir); lib.PID != again.PID || lib.Name != "audio" {
		t.Errorf("the folder lists %+v, want the new library audio", lib)
	}
	if stored, err := svc.db.LibraryRootsList(ctx); err != nil || !slices.ContainsFunc(stored, func(r wdb.LibraryRoot) bool { return r.Name == "audio" }) {
		t.Errorf("stored names = %+v (%v), want audio's kept", stored, err)
	}
	flow.mu.Lock()
	removed := slices.Clone(flow.removed)
	flow.mu.Unlock()
	if !slices.Equal(removed, []string{"books"}) {
		t.Errorf("the bridge removed %v, want books alone", removed)
	}
	if audit := removalAudit(t, ctx, svc, books.PID); audit == nil {
		t.Error("the removal was not audited")
	}
}

// A follow-up that fails keeps its origin and is done at the next start,
// audited once.
func TestARemovalWhoseFollowUpFailsIsDoneAtTheNextStart(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	var logged lockedBuffer
	ctx, svc, uc, stop := openServiceAt(t, dataDir, func(c *Config) {
		c.Logger = slog.New(slog.NewTextHandler(&logged, nil))
	})
	lib, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "books", Path: t.TempDir()})
	if err != nil {
		t.Fatal(err)
	}
	memberCtx(t, ctx, svc, "member", lib.PID)
	if _, err := svc.db.Writer().ExecContext(ctx, `CREATE TRIGGER refuse_prune BEFORE DELETE ON library_grants
		BEGIN SELECT RAISE(ABORT, 'refused'); END`); err != nil {
		t.Fatal(err)
	}
	var job Job
	waitFor(t, func() bool {
		job, err = svc.RemoveLibrary(ctx, uc, lib.PID)
		return err == nil
	}, "the removal to start once the create's scan ends")
	_, jobPID, _ := parseAPIPID(job.PID)
	waitFor(t, func() bool { return strings.Contains(logged.String(), "following up a library's removal") },
		"the follow-up to fail")
	if has, err := svc.db.HasJobOrigin(ctx, string(jobPID)); err != nil || !has {
		t.Fatalf("origin kept = %v (%v), want it kept for the next start", has, err)
	}
	if audit := removalAudit(t, ctx, svc, lib.PID); audit != nil {
		t.Fatalf("audit = %+v, want none before the follow-up lands", audit)
	}
	if _, err := svc.db.Writer().ExecContext(ctx, `DROP TRIGGER refuse_prune`); err != nil {
		t.Fatal(err)
	}
	stop()

	ctx, svc, _, _ = openServiceAt(t, dataDir, nil)
	waitFor(t, func() bool { return removalAudit(t, ctx, svc, lib.PID) != nil }, "the follow-up at the next start")
	page, err := svc.AuditEvents(ctx, wdb.AuditFilter{Action: "library.remove", TargetPID: lib.PID}, "", 10)
	if err != nil || len(page.Events) != 1 {
		t.Errorf("removal audits = %d (%v), want one", len(page.Events), err)
	}
	if stored, err := svc.db.LibraryRootsList(ctx); err != nil || slices.ContainsFunc(stored, func(r wdb.LibraryRoot) bool { return r.Name == "books" }) {
		t.Errorf("stored names = %+v (%v), want books' gone", stored, err)
	}
	waitFor(t, func() bool {
		has, err := svc.db.HasJobOrigin(ctx, string(jobPID))
		return err == nil && !has
	}, "the origin dropped once settled")
}
