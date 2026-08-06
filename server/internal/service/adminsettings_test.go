package service

import (
	"testing"
	"time"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// Three answers to tell apart: unset, an explicit zero, and a number.
// Trash retention needs only two, which is why they share no reader.
func TestTaskRetentionDaysTellsUnsetFromZero(t *testing.T) {
	ctx, svc, admin := newAdminFixture(t)

	if got := svc.TaskRetentionDays(ctx); got != defaultTaskRetentionDays {
		t.Fatalf("unconfigured task retention = %d, want the shipped %d", got, defaultTaskRetentionDays)
	}
	st, err := svc.AdminSettingsGet(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if st.TaskRetentionDays != defaultTaskRetentionDays {
		t.Fatalf("settings report %d, want %d", st.TaskRetentionDays, defaultTaskRetentionDays)
	}

	st.TaskRetentionDays = 0
	if _, err := svc.AdminSettingsPut(ctx, admin, st); err != nil {
		t.Fatal(err)
	}
	if got := svc.TaskRetentionDays(ctx); got != 0 {
		t.Fatalf("an explicit zero read back as %d; a stored keep-them must not fall to the default", got)
	}

	st.TaskRetentionDays = 7
	if _, err := svc.AdminSettingsPut(ctx, admin, st); err != nil {
		t.Fatal(err)
	}
	if got := svc.TaskRetentionDays(ctx); got != 7 {
		t.Fatalf("stored 7 read back as %d", got)
	}

	// The same overflow guard, since this reaches a duration conversion.
	st.TaskRetentionDays = 200000
	if _, err := svc.AdminSettingsPut(ctx, admin, st); KindOf(err) != KindInvalid {
		t.Fatalf("an overflowing window answered %v, want invalid-request", err)
	}
}

// The prune honours the knob, re-read every pass.
func TestRunPruneHonoursTaskRetention(t *testing.T) {
	ctx, svc, admin := newAdminFixture(t)

	old := time.Now().Add(-10 * 24 * time.Hour).UnixNano()
	if err := svc.db.InsertToolTask(ctx, wdb.ToolTask{
		ID:           "tk-old-1",
		Type:         "cue-split",
		State:        taskStateDone,
		UserID:       admin.ID,
		Params:       "{}",
		CreatedAtNS:  old,
		FinishedAtNS: old,
	}); err != nil {
		t.Fatal(err)
	}

	// Retention off: an old receipt stays.
	st, err := svc.AdminSettingsGet(ctx)
	if err != nil {
		t.Fatal(err)
	}
	st.TaskRetentionDays = 0
	if _, err := svc.AdminSettingsPut(ctx, admin, st); err != nil {
		t.Fatal(err)
	}
	if err := svc.RunPrune(ctx); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.db.ToolTaskByID(ctx, "tk-old-1"); err != nil {
		t.Fatalf("a task was pruned with retention off: %v", err)
	}

	// A week: the same row is now past the window and goes.
	st.TaskRetentionDays = 7
	if _, err := svc.AdminSettingsPut(ctx, admin, st); err != nil {
		t.Fatal(err)
	}
	if err := svc.RunPrune(ctx); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.db.ToolTaskByID(ctx, "tk-old-1"); err == nil {
		t.Fatal("an old finished task survived a seven-day retention pass")
	}
}
