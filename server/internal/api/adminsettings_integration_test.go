package api

import "testing"

// A PUT carrying one setting leaves every other setting as stored, so two
// administrators changing different switches never undo each other.
func TestSettingsPutKeepsWhatItLeavesOut(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	read := func() AdminSettings {
		t.Helper()
		return decode[AdminSettings](t, get(t, h.ts, "/api/v1/admin/settings", h.token))
	}
	put := func(body map[string]any) AdminSettings {
		t.Helper()
		resp := h.putJSON(t, "/api/v1/admin/settings", body)
		if resp.StatusCode != 200 {
			t.Fatalf("put settings status = %d, want 200", resp.StatusCode)
		}
		return decode[AdminSettings](t, resp)
	}

	put(map[string]any{
		"signupEnabled":      true,
		"backupKeepCount":    7,
		"backupKeepBytes":    4096,
		"trashRetentionDays": 30,
		"taskRetentionDays":  14,
		"sonicAnalysis":      false,
		"radioExternalArt":   false,
	})
	before := read()

	// The answer and a fresh read both show only readOnly moved.
	got := put(map[string]any{"readOnly": true})
	if !got.ReadOnly {
		t.Fatalf("readOnly = false after a PUT that set it")
	}
	got.ReadOnly = before.ReadOnly
	if !settingsEqual(got, before) {
		t.Fatalf("a PUT carrying only readOnly changed other settings:\n got  %+v\n want %+v", got, before)
	}
	if after := read(); !after.ReadOnly || !after.SignupEnabled || after.BackupKeepCount != 7 ||
		after.BackupKeepBytes != 4096 || *after.TrashRetentionDays != 30 || *after.TaskRetentionDays != 14 ||
		*after.SonicAnalysis || *after.RadioExternalArt {
		t.Fatalf("settings after a readOnly-only PUT: %+v", after)
	}

	// The same for a number: one retention field, the rest untouched.
	put(map[string]any{"readOnly": false})
	got = put(map[string]any{"backupKeepCount": 3})
	if got.BackupKeepCount != 3 || !got.SignupEnabled || got.BackupKeepBytes != 4096 || got.ReadOnly {
		t.Fatalf("a PUT carrying only backupKeepCount: %+v", got)
	}

	// An empty body writes nothing and answers what is stored.
	if got := put(map[string]any{}); got.BackupKeepCount != 3 || !got.SignupEnabled {
		t.Fatalf("an empty PUT changed settings: %+v", got)
	}

	// A refused field stores none of the others sent with it.
	resp := h.putJSON(t, "/api/v1/admin/settings", map[string]any{
		"signupEnabled":      false,
		"trashRetentionDays": 200000,
	})
	wantStatus(t, resp, 400, "overflow retention rejected")
	if !read().SignupEnabled {
		t.Fatalf("a refused PUT still stored the signup switch it carried")
	}
}

func settingsEqual(a, b AdminSettings) bool {
	return a.SignupEnabled == b.SignupEnabled && a.ReadOnly == b.ReadOnly &&
		a.BackupKeepCount == b.BackupKeepCount && a.BackupKeepBytes == b.BackupKeepBytes &&
		*a.SonicAnalysis == *b.SonicAnalysis && *a.TrashRetentionDays == *b.TrashRetentionDays &&
		*a.TaskRetentionDays == *b.TaskRetentionDays && *a.EnrichmentWriteTags == *b.EnrichmentWriteTags &&
		*a.RadioExternalArt == *b.RadioExternalArt
}
