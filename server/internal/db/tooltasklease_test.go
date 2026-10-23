package db

import (
	"context"
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
// deferred it, and says why it waits.
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
	if err := d.DeferToolTask(ctx, "tk-1", until, "the catalog is busy", "catalog-busy"); err != nil {
		t.Fatal(err)
	}
	waiting, err := d.ToolTaskByID(ctx, "tk-1")
	if err != nil || waiting.State != "running" || waiting.Error != "the catalog is busy" ||
		waiting.WaitReason != "catalog-busy" || waiting.LeaseUntilNS != until {
		t.Fatalf("deferred task = %+v, %v; want it running, saying why and until when", waiting, err)
	}
	if _, err := d.LeaseToolTask(ctx, until-1, lease, 3, TaskTypes{}); err != ErrNotFound {
		t.Fatalf("lease before the delay ran out = %v, want none", err)
	}
	row, err := d.LeaseToolTask(ctx, until+1, lease, 3, TaskTypes{})
	if err != nil || row.Attempts != 1 || row.Error != "" || row.WaitReason != "" {
		t.Fatalf("lease after the delay = %+v, %v; want attempt 1 again, the wait's words cleared", row, err)
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
			if err := d.ParkToolTask(ctx, "tk-1", "stopped", now); err != nil {
				t.Fatal(err)
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
