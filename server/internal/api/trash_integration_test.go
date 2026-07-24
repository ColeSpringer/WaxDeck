package api

import (
	"context"
	"testing"
	"time"
)

// TestTrashRetentionAndPurge covers the age-based trash retention surface:
// the retention-days setting round-trips, the periodic sweep applies the
// age filter (recent entries survive) and refuses to empty everything when
// disabled, and a single entry purges through the new endpoint.
func TestTrashRetentionAndPurge(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()

	// The retention setting defaults to off and round-trips through PUT.
	resp := get(t, h.ts, "/api/v1/admin/settings", h.token)
	st := decode[AdminSettings](t, resp)
	if st.TrashRetentionDays == nil || *st.TrashRetentionDays != 0 {
		t.Fatalf("default trashRetentionDays = %v, want 0", st.TrashRetentionDays)
	}
	resp = h.putJSON(t, "/api/v1/admin/settings", map[string]any{
		"signupEnabled":      st.SignupEnabled,
		"readOnly":           st.ReadOnly,
		"backupKeepCount":    st.BackupKeepCount,
		"backupKeepBytes":    st.BackupKeepBytes,
		"trashRetentionDays": 30,
	})
	if resp.StatusCode != 200 {
		t.Fatalf("put settings status = %d, want 200", resp.StatusCode)
	}
	if got := decode[AdminSettings](t, resp).TrashRetentionDays; got == nil || *got != 30 {
		t.Fatalf("saved trashRetentionDays = %v, want 30", got)
	}

	// A window large enough to overflow the day-to-duration conversion is
	// rejected, rather than silently disabling (or over-running) the sweep.
	resp = h.putJSON(t, "/api/v1/admin/settings", map[string]any{
		"signupEnabled":      st.SignupEnabled,
		"readOnly":           st.ReadOnly,
		"backupKeepCount":    st.BackupKeepCount,
		"backupKeepBytes":    st.BackupKeepBytes,
		"trashRetentionDays": 200000,
	})
	wantStatus(t, resp, 400, "overflow retention rejected")

	// Delete two items to the trash so the journal has entries to work on.
	page := h.items(t, "")
	if len(page.Items) < 2 {
		t.Fatalf("need at least 2 items, have %d", len(page.Items))
	}
	resp = h.postJSON(t, "/api/v1/library/items/delete", map[string]any{
		"pids": []string{page.Items[0].Pid, page.Items[1].Pid}, "mode": "trash",
	})
	wantStatus(t, resp, 200, "delete to trash")
	entries := decode[TrashList](t, get(t, h.ts, "/api/v1/admin/trash", h.token)).Entries
	if len(entries) != 2 {
		t.Fatalf("trash entries = %d, want 2", len(entries))
	}

	// The 30-day policy purges nothing: both entries were just trashed, well
	// inside the window, so the age filter keeps them.
	if rep, err := h.svc.SweepTrashRetention(ctx); err != nil || rep.Purged != 0 {
		t.Fatalf("30-day sweep = %+v, %v; want no purge of recent entries", rep, err)
	}

	// The safety guard: a zero-age purge is a no-op rather than an
	// empty-everything, so a disabled policy can never wipe the journal.
	if rep, err := h.svc.PurgeTrashOlderThan(ctx, 0); err != nil || rep.Purged != 0 {
		t.Fatalf("zero-age purge = %+v, %v; want no-op", rep, err)
	}
	if n := len(decode[TrashList](t, get(t, h.ts, "/api/v1/admin/trash", h.token)).Entries); n != 2 {
		t.Fatalf("trash after no-op sweeps = %d, want 2 (guard failed)", n)
	}

	// Purge one entry through the new endpoint: 200 with reclaimed bytes,
	// and it leaves the journal. Re-purging the same id is a clean 404.
	one := entries[0].Id
	resp = reqAs(t, h, "DELETE", "/api/v1/admin/trash/"+one, h.token, nil)
	if got := decode[TrashPurgeResult](t, resp); got.ReclaimedBytes <= 0 {
		t.Fatalf("purge reclaimed = %d, want > 0", got.ReclaimedBytes)
	}
	if n := len(decode[TrashList](t, get(t, h.ts, "/api/v1/admin/trash", h.token)).Entries); n != 1 {
		t.Fatalf("trash after purge = %d, want 1", n)
	}
	resp = reqAs(t, h, "DELETE", "/api/v1/admin/trash/"+one, h.token, nil)
	wantStatus(t, resp, 404, "re-purge")

	// The age-scoped sweep does purge when the window catches an entry: the
	// remaining entry was trashed in the past, so a one-nanosecond window
	// (older than now) reclaims it.
	if rep, err := h.svc.PurgeTrashOlderThan(ctx, time.Nanosecond); err != nil || rep.Purged != 1 {
		t.Fatalf("nanosecond-age purge = %+v, %v; want 1 purged", rep, err)
	}
	if n := len(decode[TrashList](t, get(t, h.ts, "/api/v1/admin/trash", h.token)).Entries); n != 0 {
		t.Fatalf("trash after age purge = %d, want 0", n)
	}
}
