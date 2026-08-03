package db

import (
	"context"
	"errors"
	"testing"
	"time"
)

// The nightly sweeps are the only thing that bounds these two tables, so
// what they must prove is the pair of edges: what they take, and what
// they leave for the work that is still live.

func TestPruneFinishedToolTasksTakesOnlyOldTerminalRows(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	now := time.Now().UnixNano()
	horizon := now - int64(30*24*time.Hour)

	insert := func(id, state string, finishedNS int64) {
		t.Helper()
		if err := d.InsertToolTask(ctx, ToolTask{
			ID: id, Type: "cue-split", State: state, ItemPID: "tr-1",
			Params: "{}", ResultPIDs: "[]", CreatedAtNS: now - int64(90*24*time.Hour),
			FinishedAtNS: finishedNS,
		}); err != nil {
			t.Fatal(err)
		}
	}
	insert("old-done", "done", horizon-1)
	insert("old-failed", "failed", horizon-1)
	insert("fresh-done", "done", now)
	// A queued row has never finished, so its finished_at_ns is zero,
	// which is older than any horizon. The state term is what saves it.
	insert("queued", "queued", 0)
	insert("running", "running", 0)

	n, err := d.PruneFinishedToolTasks(ctx, horizon)
	if err != nil {
		t.Fatal(err)
	}
	if n != 2 {
		t.Errorf("pruned %d rows, want the two old terminal ones", n)
	}
	for _, id := range []string{"fresh-done", "queued", "running"} {
		if _, err := d.ToolTaskByID(ctx, id); err != nil {
			t.Errorf("%s was swept: %v", id, err)
		}
	}
	for _, id := range []string{"old-done", "old-failed"} {
		if _, err := d.ToolTaskByID(ctx, id); !errors.Is(err, ErrNotFound) {
			t.Errorf("%s survived, want it swept (err %v)", id, err)
		}
	}
}

func TestPruneExhaustedAnalysisReopensTheWork(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	const maxAttempts = 5
	now := time.Now().UnixNano()
	horizon := now - int64(7*24*time.Hour)

	// enqueuedNS is when the essence was first seen; lastTriedNS is what
	// the sweep actually reads, and the two are deliberately independent
	// here because only the second one moves in production.
	enqueue := func(hash string, enqueuedNS, lastTriedNS int64, attempts int) {
		t.Helper()
		if err := d.EnqueueAnalysis(ctx, hash, "tr-"+hash, enqueuedNS); err != nil {
			t.Fatal(err)
		}
		for range attempts {
			if err := d.FailAnalysis(ctx, hash, "no", lastTriedNS); err != nil {
				t.Fatal(err)
			}
		}
	}
	enqueue("old-exhausted", horizon-1, horizon-1, maxAttempts)
	enqueue("fresh-exhausted", now, now, maxAttempts)
	enqueue("old-underbudget", horizon-1, horizon-1, maxAttempts-1)
	enqueue("old-untried", horizon-1, 0, 0)
	// The case the enqueue time cannot express: scanned months ago, gave
	// up tonight. Sweeping it now would delete and re-enqueue it in the
	// same night, which is the thrash the horizon exists to prevent.
	enqueue("long-queued-just-gave-up", horizon-1, now, maxAttempts)

	n, err := d.PruneExhaustedAnalysis(ctx, horizon, maxAttempts)
	if err != nil {
		t.Fatal(err)
	}
	if n != 1 {
		t.Fatalf("pruned %d rows, want only the old exhausted one", n)
	}

	// Deleting the row is what re-opens the work: the enqueue is a no-op
	// while a row for the key exists, so a spent attempt count is
	// permanent until something sweeps it.
	if err := d.EnqueueAnalysis(ctx, "old-exhausted", "tr-again", now); err != nil {
		t.Fatal(err)
	}
	var attempts int
	var itemPID string
	if err := d.r.QueryRowContext(ctx,
		`SELECT attempts, item_pid FROM analysis_queue WHERE essence_hash = ?`,
		"old-exhausted").Scan(&attempts, &itemPID); err != nil {
		t.Fatalf("the re-enqueued row is missing: %v", err)
	}
	if attempts != 0 || itemPID != "tr-again" {
		t.Errorf("re-enqueued row = attempts %d, item %q; want a fresh row",
			attempts, itemPID)
	}

	// The survivors are still there, and the ones with attempts left are
	// still leasable.
	for _, hash := range []string{
		"fresh-exhausted", "old-underbudget", "old-untried", "long-queued-just-gave-up",
	} {
		var count int
		if err := d.r.QueryRowContext(ctx,
			`SELECT COUNT(*) FROM analysis_queue WHERE essence_hash = ?`, hash).
			Scan(&count); err != nil {
			t.Fatal(err)
		}
		if count != 1 {
			t.Errorf("%s was swept, want it kept", hash)
		}
	}
}
