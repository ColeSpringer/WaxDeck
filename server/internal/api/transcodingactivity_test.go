package api

import "testing"

// The limits screen reads what the caps are bounding right now. A
// separate endpoint from the limits themselves, because configuration
// and telemetry have different lifetimes - and administrative, like
// everything else under /admin.
func TestTranscodingActivityIsAdministrative(t *testing.T) {
	t.Parallel()
	h := newHarness(t)

	activity := decode[TranscodingActivity](t, get(t, h.ts, "/api/v1/admin/transcoding/activity", h.token))
	// Nothing is streaming through this harness, and the honest answer
	// is zero rather than an absent field a screen would have to guess
	// about.
	if activity.ActiveSessions != 0 {
		t.Fatalf("activeSessions = %d, want 0 with nothing streaming", activity.ActiveSessions)
	}

	resp := h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "pip", "password": testPassword,
	})
	if resp.StatusCode != 201 {
		resp.Body.Close()
		t.Fatalf("create user status = %d, want 201", resp.StatusCode)
	}
	resp.Body.Close()
	pip := loginAs(t, h.ts, "pip", testPassword)
	wantStatus(t, get(t, h.ts, "/api/v1/admin/transcoding/activity", pip.Token), 403, "a listener reads the activity")
}
