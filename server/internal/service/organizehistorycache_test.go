package service

import (
	"context"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
)

// The catalog lists the organize journal only whole, so the pages of an
// unchanged journal share one listing: paging through three runs reads it
// once, and so does the settle of a run that left no report. A new run
// and the scheduled prune are on the next page at once.
func TestHistoryPagesShareOneListingOfAnUnchangedJournal(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _, _ := managedTrackFixture(t)
	apply, err := svc.ApplyOrganize(ctx, uc, "", nil)
	if err != nil || apply.Moved != 1 {
		t.Fatalf("apply = %+v (%v)", apply, err)
	}
	back, err := svc.UndoOrganize(ctx, uc, apply.JobPID)
	if err != nil || back.Moved != 1 {
		t.Fatalf("undo = %+v (%v)", back, err)
	}
	again, err := svc.UndoOrganize(ctx, uc, back.JobPID)
	if err != nil || again.Moved != 1 {
		t.Fatalf("undo of the undo = %+v (%v)", again, err)
	}
	var reads atomic.Int32
	svc.historyReadHook = func() { reads.Add(1) }

	cursor := ""
	var listed []string
	for range 3 {
		page, next, err := svc.OrganizeHistory(ctx, uc, cursor, 1)
		if err != nil || len(page) != 1 {
			t.Fatalf("page after %q = %+v (%v), want one run", cursor, page, err)
		}
		listed = append(listed, page[0].JobPID)
		cursor = next
	}
	if want := []string{again.JobPID, back.JobPID, apply.JobPID}; listed[0] != want[0] || listed[1] != want[1] ||
		listed[2] != want[2] || cursor != "" {
		t.Fatalf("pages = %v ending at %q, want %v newest first and no next page", listed, cursor, want)
	}
	_, bare, _ := parseAPIPID(apply.JobPID)
	if n := svc.journalCommitted(ctx, bare); n != 1 {
		t.Fatalf("the apply's committed moves = %d, want 1", n)
	}
	if n := reads.Load(); n != 1 {
		t.Fatalf("the journal was listed %d times for three pages and a settle, want once", n)
	}

	fourth, err := svc.UndoOrganize(ctx, uc, again.JobPID)
	if err != nil || fourth.Moved != 1 {
		t.Fatalf("a fourth run = %+v (%v)", fourth, err)
	}
	page, _, err := svc.OrganizeHistory(ctx, uc, "", 1)
	if err != nil || len(page) != 1 || page[0].JobPID != fourth.JobPID {
		t.Fatalf("first page after a new run = %+v (%v), want the new run", page, err)
	}

	svc.journalPruneHook = func(ctx context.Context, _ time.Duration) (int, error) {
		return svc.lib.PruneOrganizeJournal(ctx, 0)
	}
	if err := svc.RunPrune(ctx); err != nil {
		t.Fatal(err)
	}
	if page, _, err := svc.OrganizeHistory(ctx, uc, "", 10); err != nil || len(page) != 0 {
		t.Fatalf("history after the prune = %+v (%v), want every run gone with its journal", page, err)
	}
}

// The memory of each listed run's profile is held only while it is read
// or written, never across the catalog's read of a run's job, so one
// listing does not wait on another's reads.
func TestRunProfilesAreNotLockedAcrossTheJobRead(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _, _ := managedTrackFixture(t)
	apply, err := svc.ApplyOrganize(ctx, uc, "", nil)
	if err != nil {
		t.Fatal(err)
	}
	_, bare, _ := parseAPIPID(apply.JobPID)
	held := false
	read := func(ctx context.Context, pid model.PID) (*model.Job, error) {
		if !svc.runProfilesMu.TryLock() {
			held = true
		} else {
			svc.runProfilesMu.Unlock()
		}
		return svc.lib.Job(ctx, pid)
	}
	profiles := svc.runProfilesWith(ctx, []model.OrganizeBatch{{JobPID: bare, Kind: "organize"}}, read)
	if held {
		t.Fatal("the profiles' lock was held across the catalog's job read")
	}
	if profiles[bare] == "" {
		t.Fatalf("profiles = %v, want the run's", profiles)
	}
}

// A journal another process pruned while it held the catalog, which
// records no change, is listed afresh once the catalog is reopened.
func TestHistoryIsListedAfreshOnceTheCatalogIsReopened(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _, _ := managedTrackFixture(t)
	if _, err := svc.ApplyOrganize(ctx, uc, "", nil); err != nil {
		t.Fatal(err)
	}
	if page, _, err := svc.OrganizeHistory(ctx, uc, "", 10); err != nil || len(page) != 1 {
		t.Fatalf("history = %+v (%v), want the run", page, err)
	}
	if n, err := svc.lib.PruneOrganizeJournal(ctx, 0); err != nil || n == 0 {
		t.Fatalf("pruned %d (%v), want the run's journal gone", n, err)
	}
	head, err := svc.lib.LatestChangeSeq(ctx)
	if err != nil {
		t.Fatal(err)
	}
	svc.onReopen(ctx, waxbin.ReopenEvent{Seq: head})
	if page, _, err := svc.OrganizeHistory(ctx, uc, "", 10); err != nil || len(page) != 0 {
		t.Fatalf("history after the reopen = %+v (%v), want the pruned run gone", page, err)
	}
}
