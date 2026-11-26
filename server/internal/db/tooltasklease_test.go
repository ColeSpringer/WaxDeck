package db

import (
	"context"
	"errors"
	"testing"
	"time"
)

// task is a queued tool task row for these tests.
func task(id, lock string) ToolTask {
	return ToolTask{
		ID: id, Type: "book-merge", State: "queued", ItemPID: "bk-1", LockKey: lock,
		Params: "{}", ResultPIDs: "[]", CreatedAtNS: time.Now().UnixNano(),
	}
}

// A task holding a lock key keeps a second one with that key out while it
// is queued or running, and answers which task holds it; once it ends,
// the key is free again.
func TestALockedTaskKeepsASecondOutWhileItIsLive(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	if held, err := d.InsertLockedToolTask(ctx, task("tk-1", "book:1")); err != nil || held != "" {
		t.Fatalf("first insert = %q, %v; want it queued", held, err)
	}
	if held, err := d.InsertLockedToolTask(ctx, task("tk-2", "book:1")); err != nil || held != "tk-1" {
		t.Fatalf("second insert = %q, %v; want it refused, naming tk-1", held, err)
	}
	if _, err := d.ToolTaskByID(ctx, "tk-2"); err != ErrNotFound {
		t.Fatalf("refused task = %v, want it never stored", err)
	}
	if held, err := d.InsertLockedToolTask(ctx, task("tk-3", "book:2")); err != nil || held != "" {
		t.Fatalf("another book's task = %q, %v; want it queued", held, err)
	}
	done, err := d.ToolTaskByID(ctx, "tk-1")
	if err != nil {
		t.Fatal(err)
	}
	done.State = "done"
	if err := d.UpdateToolTask(ctx, done); err != nil {
		t.Fatal(err)
	}
	if held, err := d.InsertLockedToolTask(ctx, task("tk-4", "book:1")); err != nil || held != "" {
		t.Fatalf("a task after the first ended = %q, %v; want it queued", held, err)
	}
}

// A canceled task keeps its lock until it releases it, or is deleted.
func TestACanceledTaskHoldsItsLockUntilReleased(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	for _, id := range []string{"tk-1", "tk-2"} {
		if held, err := d.InsertLockedToolTask(ctx, task(id, "book:"+id)); err != nil || held != "" {
			t.Fatalf("insert %s = %q, %v", id, held, err)
		}
		if ok, err := d.SettleToolTaskCanceled(ctx, id, time.Now().UnixNano(), "[]", ""); err != nil || !ok {
			t.Fatalf("cancel %s = %v, %v", id, ok, err)
		}
	}
	if held, err := d.ToolTaskHolding(ctx, "book:tk-1"); err != nil || held != "tk-1" {
		t.Fatalf("holding = %q, %v; want the canceled task", held, err)
	}
	if err := d.ReleaseToolTaskLock(ctx, "tk-1"); err != nil {
		t.Fatal(err)
	}
	if held, err := d.InsertLockedToolTask(ctx, task("tk-3", "book:tk-1")); err != nil || held != "" {
		t.Fatalf("after the release = %q, %v; want it queued", held, err)
	}
	if _, err := d.DeleteToolTask(ctx, "tk-2", ""); err != nil {
		t.Fatal(err)
	}
	if held, err := d.InsertLockedToolTask(ctx, task("tk-4", "book:tk-2")); err != nil || held != "" {
		t.Fatalf("after the delete = %q, %v; want it queued", held, err)
	}
}

// A task marked resumable outlives its attempts: the retire pass leaves
// it, and the lease takes it again past the attempts cap.
func TestAResumableTaskIsLeasedPastItsAttempts(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	if err := d.InsertToolTask(ctx, task("tk-1", "")); err != nil {
		t.Fatal(err)
	}
	lease := int64(time.Minute)
	now := time.Now().UnixNano()
	for n := 1; n <= 3; n++ {
		now += 2 * lease
		if _, err := d.LeaseToolTask(ctx, now, lease, 3, TaskTypes{}); err != nil {
			t.Fatalf("lease %d: %v", n, err)
		}
	}
	if err := d.MarkToolTaskResumable(ctx, "tk-1"); err != nil {
		t.Fatal(err)
	}
	now += 2 * lease
	if ids, err := d.FailExhaustedToolTasks(ctx, now, 3, nil); err != nil || len(ids) != 0 {
		t.Fatalf("retired = %v, %v; want the resumable task left", ids, err)
	}
	row, err := d.LeaseToolTask(ctx, now, lease, 3, TaskTypes{})
	if err != nil || row.ID != "tk-1" || row.Attempts != 4 || !row.Resumable {
		t.Fatalf("lease past the cap = %+v, %v; want tk-1 leased a fourth time", row, err)
	}
}

// The retire pass leaves a task a run in this process holds, whatever
// its lease says.
func TestTheRetirePassLeavesATaskARunHolds(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	if err := d.InsertToolTask(ctx, task("tk-1", "")); err != nil {
		t.Fatal(err)
	}
	lease := int64(time.Minute)
	now := time.Now().UnixNano()
	for range 3 {
		now += 2 * lease
		if _, err := d.LeaseToolTask(ctx, now, lease, 3, TaskTypes{}); err != nil {
			t.Fatal(err)
		}
	}
	now += 2 * lease
	if ids, err := d.FailExhaustedToolTasks(ctx, now, 3, []string{"tk-1"}); err != nil || len(ids) != 0 {
		t.Fatalf("retired = %v, %v; want the held task left", ids, err)
	}
	if ids, err := d.FailExhaustedToolTasks(ctx, now, 3, nil); err != nil || len(ids) != 1 {
		t.Fatalf("retired = %v, %v; want the task retired once no run holds it", ids, err)
	}
}

// A deferred task waits out its delay without spending the attempt that
// deferred it, and says why it waits; the next lease ends the wait but
// keeps what the wait said, for a run that never comes back.
func TestADeferredTaskWaitsWithoutSpendingAnAttempt(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	if err := d.InsertToolTask(ctx, task("tk-1", "")); err != nil {
		t.Fatal(err)
	}
	lease := int64(time.Minute)
	now := time.Now().UnixNano()
	if _, err := d.LeaseToolTask(ctx, now, lease, 3, TaskTypes{}); err != nil {
		t.Fatal(err)
	}
	until := now + int64(10*time.Minute)
	if err := d.DeferToolTask(ctx, "tk-1", ToolTaskWait{UntilNS: until, Error: "the catalog is busy",
		ErrorCode: "catalog-busy", Reason: "catalog-busy"}); err != nil {
		t.Fatal(err)
	}
	waiting, err := d.ToolTaskByID(ctx, "tk-1")
	if err != nil || waiting.State != "running" || waiting.Error != "the catalog is busy" || waiting.ErrorCode != "catalog-busy" ||
		waiting.WaitReason != "catalog-busy" || waiting.LeaseUntilNS != until || waiting.Attempts != 0 {
		t.Fatalf("deferred task = %+v, %v; want it running, saying why and until when, the attempt given back", waiting, err)
	}
	if _, err := d.LeaseToolTask(ctx, until-1, lease, 3, TaskTypes{}); err != ErrNotFound {
		t.Fatalf("lease before the delay ran out = %v, want none", err)
	}
	row, err := d.LeaseToolTask(ctx, until+1, lease, 3, TaskTypes{})
	if err != nil || row.Attempts != 1 || row.WaitReason != "" || row.Error != "the catalog is busy" {
		t.Fatalf("lease after the delay = %+v, %v; want attempt 1 again, the wait over and its words kept", row, err)
	}
}

// A wait that spends its attempt still ends with the attempts, and the
// retire pass keeps the last failure and its code rather than a sentence
// of its own.
func TestTheRetirePassKeepsTheLastFailure(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	if err := d.InsertToolTask(ctx, task("tk-1", "")); err != nil {
		t.Fatal(err)
	}
	if err := d.InsertToolTask(ctx, task("tk-2", "")); err != nil {
		t.Fatal(err)
	}
	lease := int64(time.Minute)
	now := time.Now().UnixNano()
	for n := 1; n <= 3; n++ {
		now += 2 * lease
		for range 2 {
			if _, err := d.LeaseToolTask(ctx, now, lease, 3, TaskTypes{}); err != nil {
				t.Fatalf("lease %d: %v", n, err)
			}
		}
		if n < 3 {
			if err := d.DeferToolTask(ctx, "tk-1", ToolTaskWait{UntilNS: now + lease, Error: "the disk hiccuped",
				ErrorCode: "internal", ErrorParams: `{"step":"art"}`, Reason: "other", SpendAttempt: true}); err != nil {
				t.Fatal(err)
			}
		}
	}
	if row, _ := d.ToolTaskByID(ctx, "tk-1"); row.Attempts != 3 {
		t.Fatalf("attempts = %d, want each wait to have spent its attempt", row.Attempts)
	}
	now += 2 * lease
	if ids, err := d.FailExhaustedToolTasks(ctx, now, 3, nil); err != nil || len(ids) != 2 {
		t.Fatalf("retired = %v, %v; want both", ids, err)
	}
	said, _ := d.ToolTaskByID(ctx, "tk-1")
	if said.State != "failed" || said.Error != "the disk hiccuped" || said.ErrorCode != "internal" || said.ErrorParams != `{"step":"art"}` {
		t.Fatalf("retired task = %+v, want its last failure kept", said)
	}
	if silent, _ := d.ToolTaskByID(ctx, "tk-2"); silent.Error != "gave up after repeated attempts" || silent.ErrorCode != "internal" {
		t.Fatalf("retired task with nothing said = %+v, want the retire pass's own words, coded internal", silent)
	}
}

// A cancel's and a retire's state change leave the task's settle pending
// until it is ended, which the listing of unsettled tasks reads.
func TestACanceledOrRetiredTaskIsUnsettledUntilItsSettleEnds(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	for _, id := range []string{"tk-1", "tk-2", "tk-3"} {
		if err := d.InsertToolTask(ctx, task(id, "")); err != nil {
			t.Fatal(err)
		}
	}
	if ok, err := d.SettleToolTaskCanceled(ctx, "tk-1", time.Now().UnixNano(), "[]", ""); err != nil || !ok {
		t.Fatalf("cancel = %v, %v", ok, err)
	}
	lease := int64(time.Minute)
	now := time.Now().UnixNano()
	for range 3 {
		now += 2 * lease
		if _, err := d.LeaseToolTask(ctx, now, lease, 3, TaskTypes{Only: []string{"book-merge"}}); err != nil {
			t.Fatal(err)
		}
	}
	if ids, err := d.FailExhaustedToolTasks(ctx, now+2*lease, 3, nil); err != nil || len(ids) != 1 {
		t.Fatalf("retired = %v, %v; want one", ids, err)
	}
	pending := func() []string {
		t.Helper()
		rows, err := d.PendingToolTaskSettles(ctx)
		if err != nil {
			t.Fatal(err)
		}
		var ids []string
		for _, r := range rows {
			ids = append(ids, r.ID)
		}
		return ids
	}
	got := pending()
	if len(got) != 2 || got[0] != "tk-1" {
		t.Fatalf("unsettled = %v, want the canceled and the retired task", got)
	}
	for _, id := range got {
		if err := d.EndToolTaskSettle(ctx, id); err != nil {
			t.Fatal(err)
		}
	}
	if got := pending(); len(got) != 0 {
		t.Fatalf("unsettled after the settles ended = %v, want none", got)
	}
}

// A run's own terminal write marks its end pending in the same statement,
// done or failed, as a run's end and not a settle's; a plain update
// leaves the marker as it is, and a run's write after a cancel sets none.
func TestARunsTerminalWriteLeavesItsEndPending(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	for _, id := range []string{"tk-1", "tk-2", "tk-3"} {
		if err := d.InsertToolTask(ctx, task(id, "")); err != nil {
			t.Fatal(err)
		}
	}
	for id, state := range map[string]string{"tk-1": "done", "tk-2": "failed"} {
		row, err := d.ToolTaskByID(ctx, id)
		if err != nil {
			t.Fatal(err)
		}
		row.State = state
		if err := d.FinishToolTask(ctx, row); err != nil {
			t.Fatal(err)
		}
		row.Summary = `{"n":1}`
		if err := d.UpdateToolTask(ctx, row); err != nil {
			t.Fatal(err)
		}
	}
	if ok, err := d.SettleToolTaskCanceled(ctx, "tk-3", time.Now().UnixNano(), "[]", ""); err != nil || !ok {
		t.Fatalf("cancel = %v, %v", ok, err)
	}
	late, err := d.ToolTaskByID(ctx, "tk-3")
	if err != nil {
		t.Fatal(err)
	}
	late.State = "failed"
	if err := d.FinishToolTask(ctx, late); !errors.Is(err, ErrNotFound) {
		t.Fatalf("a run's write after the cancel = %v, want ErrNotFound", err)
	}
	rows, err := d.PendingToolTaskSettles(ctx)
	if err != nil {
		t.Fatal(err)
	}
	got := map[string]ToolTask{}
	for _, r := range rows {
		got[r.ID] = r
	}
	for _, id := range []string{"tk-1", "tk-2"} {
		if r := got[id]; !r.SettlePending || !r.RunEndPending {
			t.Errorf("%s = %+v, want its run's end pending", id, r)
		}
	}
	if r := got["tk-3"]; !r.SettlePending || r.RunEndPending {
		t.Errorf("tk-3 = %+v, want the cancel's settle pending, not a run's end", r)
	}
	if err := d.EndToolTaskSettle(ctx, "tk-1"); err != nil {
		t.Fatal(err)
	}
	if r, err := d.ToolTaskByID(ctx, "tk-1"); err != nil || r.SettlePending || r.RunEndPending {
		t.Fatalf("tk-1 after its end = %+v (%v), want nothing pending", r, err)
	}
}

// A run's terminal write never takes over a retire's pending settle, and a
// run's park marks the park's end pending as its own.
func TestARunsWriteKeepsARetiresSettleAndAParkMarksItsEnd(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	for _, id := range []string{"tk-1", "tk-2"} {
		if err := d.InsertToolTask(ctx, task(id, "")); err != nil {
			t.Fatal(err)
		}
	}
	lease := int64(time.Minute)
	now := time.Now().UnixNano()
	for range 3 {
		now += 2 * lease
		if _, err := d.LeaseToolTask(ctx, now, lease, 3, TaskTypes{Only: []string{"book-merge"}}); err != nil {
			t.Fatal(err)
		}
	}
	if ids, err := d.FailExhaustedToolTasks(ctx, now+2*lease, 3, nil); err != nil || len(ids) != 1 || ids[0] != "tk-1" {
		t.Fatalf("retired = %v, %v; want tk-1", ids, err)
	}
	row, err := d.ToolTaskByID(ctx, "tk-1")
	if err != nil {
		t.Fatal(err)
	}
	// A run's failure landing on the row the retire already failed.
	if err := d.FinishToolTask(ctx, row); err != nil {
		t.Fatal(err)
	}
	if r, _ := d.ToolTaskByID(ctx, "tk-1"); !r.SettlePending || r.RunEndPending {
		t.Errorf("tk-1 = %+v, want the retire's settle still pending, not a run's end", r)
	}
	if leased, err := d.LeaseToolTask(ctx, now+4*lease, lease, 3, TaskTypes{Only: []string{"book-merge"}}); err != nil || leased.ID != "tk-2" {
		t.Fatalf("lease = %v, %v; want tk-2", leased.ID, err)
	}
	if ok, err := d.ParkToolTask(ctx, "tk-2", "stopped", now); err != nil || !ok {
		t.Fatal(err)
	}
	if r, _ := d.ToolTaskByID(ctx, "tk-2"); r.State != "parked" || !r.SettlePending || !r.RunEndPending || !r.ParkEndPending {
		t.Errorf("tk-2 = %+v, want it parked, its park's end pending", r)
	}
	if ok, err := d.ParkToolTask(ctx, "tk-2", "again", now); err != nil || ok {
		t.Errorf("a park of a task no longer running = %v, %v; want false", ok, err)
	}
}

// A parked task is stopped for good and finished: it is not leased or
// retired, it holds its lock until it is cleared - deleted, swept with
// the finished tasks, or pruned - and clearing it frees the lock.
func TestAParkedTaskHoldsItsLockUntilItIsCleared(t *testing.T) {
	for _, clear := range []string{"deleted", "swept", "pruned"} {
		t.Run(clear, func(t *testing.T) {
			d := openTest(t)
			ctx := context.Background()
			if held, err := d.InsertLockedToolTask(ctx, task("tk-1", "book:1")); err != nil || held != "" {
				t.Fatalf("insert = %q, %v", held, err)
			}
			lease := int64(time.Minute)
			now := time.Now().UnixNano()
			if _, err := d.LeaseToolTask(ctx, now, lease, 3, TaskTypes{}); err != nil {
				t.Fatal(err)
			}
			if ok, err := d.ParkToolTask(ctx, "tk-1", "stopped", now); err != nil || !ok {
				t.Fatalf("park = %v, %v", ok, err)
			}
			now += 10 * lease
			if _, err := d.LeaseToolTask(ctx, now, lease, 3, TaskTypes{}); err != ErrNotFound {
				t.Fatalf("lease of a parked task = %v, want none", err)
			}
			if ids, err := d.FailExhaustedToolTasks(ctx, now, 0, nil); err != nil || len(ids) != 0 {
				t.Fatalf("retired = %v, %v; want the parked task left", ids, err)
			}
			if row, err := d.ToolTaskByID(ctx, "tk-1"); err != nil || row.FinishedAtNS == 0 {
				t.Fatalf("parked row = %+v, %v; want it finished", row, err)
			}
			if held, err := d.InsertLockedToolTask(ctx, task("tk-2", "book:1")); err != nil || held != "tk-1" {
				t.Fatalf("a second task on the book = %q, %v; want it refused, naming the parked one", held, err)
			}
			var gone int64
			var err error
			switch clear {
			case "deleted":
				var ok bool
				if ok, err = d.DeleteToolTask(ctx, "tk-1", ""); ok {
					gone = 1
				}
			case "swept":
				var finished []ToolTask
				if finished, err = d.FinishedToolTasks(ctx, "", true, 0); err == nil && len(finished) == 1 {
					var n int
					n, err = d.DeleteToolTasksByID(ctx, []string{finished[0].ID})
					gone = int64(n)
				}
			default:
				var old []ToolTask
				if old, err = d.FinishedToolTasks(ctx, "", true, time.Now().Add(time.Hour).UnixNano()); err == nil && len(old) == 1 {
					var n int
					n, err = d.DeleteToolTasksByID(ctx, []string{old[0].ID})
					gone = int64(n)
				}
			}
			if err != nil || gone != 1 {
				t.Fatalf("%s = %d, %v; want the parked task gone", clear, gone, err)
			}
			if held, err := d.InsertLockedToolTask(ctx, task("tk-2", "book:1")); err != nil || held != "" {
				t.Fatalf("a second task once the parked one is %s = %q, %v; want it stored", clear, held, err)
			}
		})
	}
}

// A cancel and a commit decide one task once: whichever lands first
// stands and the other is refused, in either order.
func TestACancelAndACommitLandOnce(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	for _, id := range []string{"tk-cancel-first", "tk-commit-first"} {
		if err := d.InsertToolTask(ctx, task(id, "")); err != nil {
			t.Fatal(err)
		}
	}
	if asked, err := d.RequestToolTaskCancel(ctx, "tk-cancel-first"); err != nil || !asked {
		t.Fatalf("asking = %v, %v", asked, err)
	}
	if err := d.MarkToolTaskResumable(ctx, "tk-cancel-first"); err != ErrCancelRequested {
		t.Fatalf("commit after the cancel = %v, want it refused", err)
	}
	if row, err := d.ToolTaskByID(ctx, "tk-cancel-first"); err != nil || row.Resumable || !row.CancelRequested {
		t.Fatalf("after the cancel won: %+v, %v", row, err)
	}
	if err := d.MarkToolTaskResumable(ctx, "tk-commit-first"); err != nil {
		t.Fatal(err)
	}
	if asked, err := d.RequestToolTaskCancel(ctx, "tk-commit-first"); err != nil || asked {
		t.Fatalf("cancel after the commit = %v, %v; want it refused", asked, err)
	}
	if row, err := d.ToolTaskByID(ctx, "tk-commit-first"); err != nil || !row.Resumable || row.CancelRequested {
		t.Fatalf("after the commit won: %+v, %v", row, err)
	}
}

// A task asked to cancel is handed to the lease once its lease is out,
// however many attempts it spent, spending none, and the retire pass
// leaves it; a lease still running keeps it.
func TestAnAskedTaskIsLeasedPastItsAttempts(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	if err := d.InsertToolTask(ctx, task("tk-1", "")); err != nil {
		t.Fatal(err)
	}
	lease := int64(time.Minute)
	now := time.Now().UnixNano()
	for range 3 {
		now += 2 * lease
		if _, err := d.LeaseToolTask(ctx, now, lease, 3, TaskTypes{}); err != nil {
			t.Fatal(err)
		}
	}
	if asked, err := d.RequestToolTaskCancel(ctx, "tk-1"); err != nil || !asked {
		t.Fatalf("asking = %v, %v", asked, err)
	}
	if _, err := d.LeaseToolTask(ctx, now, lease, 3, TaskTypes{}); err != ErrNotFound {
		t.Fatalf("lease while the last one runs = %v, want none", err)
	}
	now += 2 * lease
	if ids, err := d.FailExhaustedToolTasks(ctx, now, 3, nil); err != nil || len(ids) != 0 {
		t.Fatalf("retired = %v, %v; want the asked task left", ids, err)
	}
	row, err := d.LeaseToolTask(ctx, now, lease, 3, TaskTypes{})
	if err != nil || row.ID != "tk-1" || row.Attempts != 3 || !row.CancelRequested {
		t.Fatalf("lease = %+v, %v; want tk-1 handed over asked, its attempts as they were", row, err)
	}
}
