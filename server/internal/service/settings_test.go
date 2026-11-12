package service

import (
	"sync"
	"testing"
	"time"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// everySetting is a write that names every field of s, which is how a
// test replaces the whole document.
func everySetting(s AdminSettings) AdminSettingsChange {
	return AdminSettingsChange{
		SignupEnabled:       &s.SignupEnabled,
		ReadOnly:            &s.ReadOnly,
		SonicAnalysis:       &s.SonicAnalysis,
		BackupKeepCount:     &s.BackupKeepCount,
		BackupKeepBytes:     &s.BackupKeepBytes,
		TrashRetentionDays:  &s.TrashRetentionDays,
		TaskRetentionDays:   &s.TaskRetentionDays,
		EnrichmentWriteTags: &s.EnrichmentWriteTags,
		RadioExternalArt:    &s.RadioExternalArt,
	}
}

// A write stores the fields it names and nothing else, and its audit
// entry says the same.
func TestAdminSettingsPutKeepsWhatItDoesNotName(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newAdminFixture(t)

	yes, no := true, false
	days, keep := 30, 5
	if _, err := svc.Settings.AdminSettingsPut(ctx, admin, AdminSettingsChange{
		SignupEnabled:      &yes,
		SonicAnalysis:      &no,
		RadioExternalArt:   &no,
		TrashRetentionDays: &days,
		BackupKeepCount:    &keep,
	}); err != nil {
		t.Fatal(err)
	}
	before, err := svc.Settings.AdminSettingsGet(ctx)
	if err != nil {
		t.Fatal(err)
	}

	got, err := svc.Settings.AdminSettingsPut(ctx, admin, AdminSettingsChange{ReadOnly: &yes})
	if err != nil {
		t.Fatal(err)
	}
	want := before
	want.ReadOnly = true
	if got != want {
		t.Fatalf("a write naming readOnly stored %+v, want %+v", got, want)
	}
	if !svc.Settings.ServerReadOnly() || svc.Settings.SonicAnalysisEnabled() || svc.Settings.RadioExternalArtEnabled() {
		t.Fatal("the hot-path toggles did not follow the stored settings")
	}

	// Nothing named: nothing stored, and nothing to audit.
	events := func() int {
		t.Helper()
		page, err := svc.Audit.Events(ctx, AuditFilter{Action: "settings."}, "", 50)
		if err != nil {
			t.Fatal(err)
		}
		return len(page.Events)
	}
	was := events()
	if got, err := svc.Settings.AdminSettingsPut(ctx, admin, AdminSettingsChange{}); err != nil || got != want {
		t.Fatalf("an empty write answered %+v, %v; want %+v", got, err, want)
	}
	if events() != was {
		t.Fatal("an empty write was audited")
	}

	// A refused field stores none of the others in the same write.
	bad := maxRetentionDays + 1
	if _, err := svc.Settings.AdminSettingsPut(ctx, admin, AdminSettingsChange{
		SignupEnabled:      &no,
		TrashRetentionDays: &bad,
	}); KindOf(err) != KindInvalid {
		t.Fatalf("an overflowing window answered %v, want invalid-request", err)
	}
	if now, _ := svc.Settings.AdminSettingsGet(ctx); now != want {
		t.Fatalf("a refused write changed the settings: %+v", now)
	}

	// The entry records what was written.
	page, err := svc.Audit.Events(ctx, AuditFilter{Action: "settings."}, "", 1)
	if err != nil || len(page.Events) != 1 {
		t.Fatalf("audit: %v %+v", err, page.Events)
	}
	detail := page.Events[0].Detail
	if len(detail) != 1 || detail["readOnly"] != true {
		t.Fatalf("audit detail %v, want only readOnly", detail)
	}
}

// The transcode limits reload the same hot-path cache as a settings write,
// so they take the same lock: a reload of one cannot land over the other's.
func TestTranscodingLimitsPutWaitsForTheSettingsLock(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newAdminFixture(t)

	svc.Settings.adminSettingsMu.Lock()
	done := make(chan error, 1)
	go func() {
		_, err := svc.Settings.TranscodingLimitsPut(ctx, admin, TranscodingLimits{MaxConcurrent: 3})
		done <- err
	}()
	select {
	case err := <-done:
		svc.Settings.adminSettingsMu.Unlock()
		t.Fatalf("the limits were stored while a settings write held the lock (err %v)", err)
	case <-time.After(300 * time.Millisecond):
	}
	svc.Settings.adminSettingsMu.Unlock()
	if err := <-done; err != nil {
		t.Fatal(err)
	}
	if got := svc.Settings.TranscodingLimitsGet(ctx).MaxConcurrent; got != 3 {
		t.Fatalf("limits read back %d, want 3", got)
	}
}

// Two writes naming different fields, in flight together, both stick.
func TestAdminSettingsPutsOfDifferentFieldsBothStick(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newAdminFixture(t)

	yes := true
	days, keep := 9, 4
	writes := []AdminSettingsChange{
		{SignupEnabled: &yes},
		{ReadOnly: &yes},
		{TrashRetentionDays: &days},
		{BackupKeepCount: &keep},
	}
	var wg sync.WaitGroup
	for _, w := range writes {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if _, err := svc.Settings.AdminSettingsPut(ctx, admin, w); err != nil {
				t.Error(err)
			}
		}()
	}
	wg.Wait()

	got, err := svc.Settings.AdminSettingsGet(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if !got.SignupEnabled || !got.ReadOnly || got.TrashRetentionDays != 9 || got.BackupKeepCount != 4 {
		t.Fatalf("settings after four concurrent writes: %+v", got)
	}
	if !svc.Settings.ServerReadOnly() {
		t.Fatal("the read-only toggle did not follow the stored setting")
	}
}

// Three answers to tell apart: unset, an explicit zero, and a number.
// Trash retention needs only two, which is why they share no reader.
func TestTaskRetentionDaysTellsUnsetFromZero(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newAdminFixture(t)

	if got := svc.Settings.TaskRetentionDays(ctx); got != defaultTaskRetentionDays {
		t.Fatalf("unconfigured task retention = %d, want the shipped %d", got, defaultTaskRetentionDays)
	}
	st, err := svc.Settings.AdminSettingsGet(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if st.TaskRetentionDays != defaultTaskRetentionDays {
		t.Fatalf("settings report %d, want %d", st.TaskRetentionDays, defaultTaskRetentionDays)
	}

	st.TaskRetentionDays = 0
	if _, err := svc.Settings.AdminSettingsPut(ctx, admin, everySetting(st)); err != nil {
		t.Fatal(err)
	}
	if got := svc.Settings.TaskRetentionDays(ctx); got != 0 {
		t.Fatalf("an explicit zero read back as %d; a stored keep-them must not fall to the default", got)
	}

	st.TaskRetentionDays = 7
	if _, err := svc.Settings.AdminSettingsPut(ctx, admin, everySetting(st)); err != nil {
		t.Fatal(err)
	}
	if got := svc.Settings.TaskRetentionDays(ctx); got != 7 {
		t.Fatalf("stored 7 read back as %d", got)
	}

	// The same overflow guard, since this reaches a duration conversion.
	st.TaskRetentionDays = 200000
	if _, err := svc.Settings.AdminSettingsPut(ctx, admin, everySetting(st)); KindOf(err) != KindInvalid {
		t.Fatalf("an overflowing window answered %v, want invalid-request", err)
	}
}

// The prune honours the knob, re-read every pass.
func TestRunPruneHonoursTaskRetention(t *testing.T) {
	t.Parallel()
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
	st, err := svc.Settings.AdminSettingsGet(ctx)
	if err != nil {
		t.Fatal(err)
	}
	st.TaskRetentionDays = 0
	if _, err := svc.Settings.AdminSettingsPut(ctx, admin, everySetting(st)); err != nil {
		t.Fatal(err)
	}
	if err := svc.Integrations.RunPrune(ctx); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.db.ToolTaskByID(ctx, "tk-old-1"); err != nil {
		t.Fatalf("a task was pruned with retention off: %v", err)
	}

	// A week: the same row is now past the window and goes.
	st.TaskRetentionDays = 7
	if _, err := svc.Settings.AdminSettingsPut(ctx, admin, everySetting(st)); err != nil {
		t.Fatal(err)
	}
	if err := svc.Integrations.RunPrune(ctx); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.db.ToolTaskByID(ctx, "tk-old-1"); err == nil {
		t.Fatal("an old finished task survived a seven-day retention pass")
	}
}

// The prune lets go of the YouTube entries a listing last showed live
// more than the horizon ago, for shows nobody polls any more too.
func TestRunPruneLetsStaleHeldYouTubeEntriesGo(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newAdminFixture(t)
	now := time.Now()
	if err := svc.db.RememberYouTubePending(ctx, "UUgone", []string{"old00000001"}, now.Add(-91*24*time.Hour).UnixNano()); err != nil {
		t.Fatal(err)
	}
	if err := svc.db.RememberYouTubePending(ctx, "UUgone", []string{"new00000001"}, now.Add(-24*time.Hour).UnixNano()); err != nil {
		t.Fatal(err)
	}
	if err := svc.Integrations.RunPrune(ctx); err != nil {
		t.Fatal(err)
	}
	// Listed as of the old sighting, so the horizon hides neither row.
	held, err := svc.db.YouTubePending(ctx, "UUgone", now.Add(-91*24*time.Hour).UnixNano())
	if err != nil {
		t.Fatal(err)
	}
	if len(held) != 1 || held[0] != "new00000001" {
		t.Errorf("held after the prune = %v, want only the recent entry", held)
	}
}
