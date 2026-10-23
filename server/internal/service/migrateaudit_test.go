package service

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

func migrationRuns(t *testing.T, ctx context.Context, f *migrateFixture) []AuditEventDTO {
	t.Helper()
	page, err := f.svc.AuditEvents(ctx, wdb.AuditFilter{Action: "migration.run"}, "", 50)
	if err != nil {
		t.Fatal(err)
	}
	return page.Events
}

// drainAll runs the tool queue to idle, the way the worker does.
func drainAll(ctx context.Context, f *migrateFixture) {
	for f.svc.DrainToolTasks(ctx) {
	}
}

// A migration that fails for good leaves a record, as one that succeeds
// does: who ordered it, from what, onto whom, and why it failed.
func TestAFailedMigrationIsOnTheRecord(t *testing.T) {
	ctx, f := newMigrateFixture(t)
	staged, err := f.svc.StageMigrationExport(ctx, f.uc, bytes.NewReader(spotifyExportZip(t)), 0)
	if err != nil {
		t.Fatal(err)
	}
	dto, err := f.svc.StartMigration(ctx, f.uc, MigrationRequest{
		Source: "spotify", ExportID: staged.PID, History: true, DryRun: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	// The upload goes before the run reads it, which no retry can bring
	// back.
	if err := f.svc.DiscardMigrationExport(ctx, f.uc, staged.PID); err != nil {
		t.Fatal(err)
	}
	drainAll(ctx, f)

	if row, err := f.svc.db.ToolTaskByID(ctx, dto.ID); err != nil || row.State != taskStateFailed {
		t.Fatalf("the task = %+v (%v), want it failed", row, err)
	}
	runs := migrationRuns(t, ctx, f)
	if len(runs) != 1 {
		t.Fatalf("migration.run entries = %+v, want one", runs)
	}
	e := runs[0]
	if e.ActorID != f.uc.ID || e.TargetKind != "migration" || e.TargetName != "spotify" {
		t.Errorf("entry = %+v, want the administrator's spotify migration", e)
	}
	if e.Detail["failed"] != true || e.Detail["source"] != "spotify" || e.Detail["dryRun"] != true ||
		e.Detail["account"] != "admin" {
		t.Errorf("detail = %v, want failed, source, dryRun and the target account", e.Detail)
	}
	if why, _ := e.Detail["error"].(string); !strings.Contains(why, "the uploaded export is gone") {
		t.Errorf("error = %q, want why it failed", why)
	}
}

// A failure that runs again under the lease is not the end of the
// migration: the record waits for the attempt that is.
func TestATransientMigrationFailureIsRecordedOnlyWhenItIsTheLast(t *testing.T) {
	ctx, f := newMigrateFixture(t)
	down := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "down for maintenance", http.StatusServiceUnavailable)
	}))
	t.Cleanup(down.Close)
	dto, err := f.svc.StartMigration(ctx, f.uc, MigrationRequest{
		Source: "navidrome", ServerURL: down.URL, Username: "demo", Password: "demo-pass", DryRun: true,
	})
	if err != nil {
		t.Fatal(err)
	}

	drainAll(ctx, f)
	row, err := f.svc.db.ToolTaskByID(ctx, dto.ID)
	if err != nil || row.State != "running" || row.Attempts != 1 {
		t.Fatalf("after the first attempt the task = %+v (%v), want it leased and waiting to run again", row, err)
	}
	if runs := migrationRuns(t, ctx, f); len(runs) != 0 {
		t.Fatalf("a failure that runs again was recorded: %+v", runs)
	}

	// The lease runs out with one attempt left.
	if _, err := f.svc.db.Writer().ExecContext(ctx,
		`UPDATE tool_tasks SET lease_until_ns = 0, attempts = ? WHERE id = ?`, toolTaskMaxAttempts-1, dto.ID); err != nil {
		t.Fatal(err)
	}
	drainAll(ctx, f)
	row, err = f.svc.db.ToolTaskByID(ctx, dto.ID)
	if err != nil || row.State != taskStateFailed {
		t.Fatalf("after the last attempt the task = %+v (%v), want it failed", row, err)
	}
	runs := migrationRuns(t, ctx, f)
	if len(runs) != 1 || runs[0].Detail["failed"] != true {
		t.Fatalf("migration.run entries = %+v, want the one failed run", runs)
	}
}

// A migration whose worker died on its last lease is retired without a
// run to return an error, and it is on the record all the same.
func TestAMigrationThatRanOutOfAttemptsUnderTheLeaseIsOnTheRecord(t *testing.T) {
	ctx, f := newMigrateFixture(t)
	dto, err := f.svc.StartMigration(ctx, f.uc, MigrationRequest{
		Source: "navidrome", ServerURL: "http://old-box.example:4533", Username: "demo", Password: "demo-pass",
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.db.Writer().ExecContext(ctx,
		`UPDATE tool_tasks SET state = 'running', lease_until_ns = 1, attempts = ? WHERE id = ?`,
		toolTaskMaxAttempts, dto.ID); err != nil {
		t.Fatal(err)
	}

	drainAll(ctx, f)

	row, err := f.svc.db.ToolTaskByID(ctx, dto.ID)
	if err != nil || row.State != taskStateFailed {
		t.Fatalf("the task = %+v (%v), want it retired as failed", row, err)
	}
	runs := migrationRuns(t, ctx, f)
	if len(runs) != 1 || runs[0].Detail["failed"] != true || runs[0].TargetName != "navidrome" {
		t.Fatalf("migration.run entries = %+v, want the one failed navidrome run", runs)
	}
	if why, _ := runs[0].Detail["error"].(string); !strings.Contains(why, "gave up") {
		t.Errorf("error = %q, want the reason it was retired", why)
	}
}

// An import that ends on its run's deadline is recorded: the drain
// records the end on its own context, not on the attempt's, which has
// expired by then.
func TestAMigrationWhoseLastRunTimedOutIsStillOnTheRecord(t *testing.T) {
	ctx, f := newMigrateFixture(t)
	stall := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		<-r.Context().Done()
	}))
	t.Cleanup(stall.Close)
	dto, err := f.svc.StartMigration(ctx, f.uc, MigrationRequest{
		Source: "navidrome", ServerURL: stall.URL, Username: "demo", Password: "demo-pass", DryRun: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	row, err := f.svc.db.ToolTaskByID(ctx, dto.ID)
	if err != nil {
		t.Fatal(err)
	}
	row.Attempts = toolTaskMaxAttempts

	// What the drain does with an attempt: bound it, run it, and record
	// the end on its own context.
	runCtx, cancel := context.WithTimeout(ctx, 200*time.Millisecond)
	runErr := f.svc.runToolTask(runCtx, &row)
	cancel()
	if !errors.Is(runErr, context.DeadlineExceeded) {
		t.Fatalf("the run = %v, want its deadline", runErr)
	}
	f.svc.failToolTask(ctx, &row, runErr)

	runs := migrationRuns(t, ctx, f)
	if len(runs) != 1 || runs[0].Detail["failed"] != true {
		t.Fatalf("migration.run entries = %+v, want the one failed run", runs)
	}
	if runs[0].ActorName != "admin" || runs[0].Detail["account"] != "admin" {
		t.Errorf("entry = %+v, want the names resolved, not the raw ids", runs[0])
	}
}

// The error an entry keeps is the task's own words with every web
// address cut to its host: an address can carry a credential in its user
// part, its path or its query.
func TestAMigrationFailureIsScrubbedBeforeItIsRecorded(t *testing.T) {
	cause := fmt.Errorf("%w: GET https://demo:hunter2@old.example:4533/rest/ping.view?u=demo&t=0123abcd&s=salt: connection reset",
		errToolPermanent)
	got := migrationFailureText(taskFailureText(cause))
	for _, leak := range []string{"hunter2", "0123abcd", "salt", "/rest/ping.view"} {
		if strings.Contains(got, leak) {
			t.Errorf("failure text %q keeps %q", got, leak)
		}
	}
	if !strings.Contains(got, "https://old.example:4533") || !strings.Contains(got, "connection reset") {
		t.Errorf("failure text %q lost the host or the reason", got)
	}
	if long := migrationFailureText(strings.Repeat("x", 5000)); len(long) > 600 {
		t.Errorf("a long failure is kept whole: %d bytes", len(long))
	}
}
