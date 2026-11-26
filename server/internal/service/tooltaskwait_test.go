package service

import (
	"errors"
	"testing"
	"time"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// A failure the server cannot classify, in any kind of task, waits in view
// as "other" with the failure said, the attempt spent; the attempts still
// end a task that keeps failing, keeping its last failure and its code.
func TestAnUnclassifiedFailureWaitsAsOther(t *testing.T) {
	t.Parallel()
	t.Run("catalog repair", func(t *testing.T) {
		t.Parallel()
		ctx, svc, uc := newCatalogFixture(t)
		svc.catalogRepairHook = func(step string) error {
			if step == catalogRepairArt {
				return errors.New("the disk went away for a moment")
			}
			return nil
		}
		task, err := svc.StartCatalogRepair(ctx, uc)
		if err != nil {
			t.Fatal(err)
		}
		now := time.Now()
		for attempt := 1; attempt <= toolTaskMaxAttempts; attempt++ {
			if !svc.Tools.drainToolTasksAt(ctx, longDrain, now.UnixNano()) {
				t.Fatalf("attempt %d found no task to run", attempt)
			}
			row := storedTask(t, ctx, svc, task.ID)
			if attempt < toolTaskMaxAttempts {
				if row.State != taskStateRunning || row.WaitReason != "other" || row.Attempts != attempt ||
					row.Error != "reclaiming unused images: the disk went away for a moment" || row.LeaseUntilNS <= time.Now().UnixNano() {
					t.Fatalf("attempt %d: task = %s waiting on %q after %d attempts (error %q)", attempt,
						row.State, row.WaitReason, row.Attempts, row.Error)
				}
			} else if row.State != taskStateFailed || row.ErrorCode != "internal" ||
				row.Error != "reclaiming unused images: the disk went away for a moment" {
				t.Fatalf("last attempt: task = %s, code %q (error %q); want it failed with its failure", row.State, row.ErrorCode, row.Error)
			}
			now = now.Add(time.Hour)
		}
	})
	t.Run("acquisition", func(t *testing.T) {
		t.Parallel()
		ctx, svc, uc := acquireFixture(t, &stagingSource{})
		if _, err := svc.db.Writer().ExecContext(ctx, `CREATE TRIGGER refuse_upload BEFORE INSERT ON uploads
			BEGIN SELECT RAISE(ABORT, 'the disk hiccuped'); END`); err != nil {
			t.Fatal(err)
		}
		task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/playlist?list=PLthree", false, "music", "", "", nil, nil)
		if err != nil {
			t.Fatal(err)
		}
		now := time.Now()
		for attempt := 1; attempt < toolTaskMaxAttempts; attempt++ {
			drainTaskAt(t, ctx, svc, now)
			row := storedTask(t, ctx, svc, task.ID)
			if row.State != taskStateRunning || row.WaitReason != "other" || row.Attempts != attempt || row.Error == "" {
				t.Fatalf("attempt %d: task = %s waiting on %q after %d attempts (error %q)", attempt,
					row.State, row.WaitReason, row.Attempts, row.Error)
			}
			now = now.Add(time.Hour)
		}
		// The last attempt's run ends with the process: the retire pass
		// fails the task with what the attempt before said.
		said := storedTask(t, ctx, svc, task.ID).Error
		if _, err := svc.db.LeaseToolTask(ctx, now.UnixNano(), toolTaskLease.Nanoseconds(), toolTaskMaxAttempts, wdb.TaskTypes{}); err != nil {
			t.Fatal(err)
		}
		svc.Tools.drainToolTasksAt(ctx, sourceDrain, now.Add(toolTaskLease+time.Second).UnixNano())
		row := storedTask(t, ctx, svc, task.ID)
		if row.State != taskStateFailed || row.Error != said || row.ErrorCode != "internal" {
			t.Fatalf("retired task = %s, code %q (error %q); want it failed with %q", row.State, row.ErrorCode, row.Error, said)
		}
	})
}
