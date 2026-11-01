package api

import (
	"slices"
	"testing"
)

func listedJobPIDs(t *testing.T, h *harness, token string) []string {
	t.Helper()
	var pids []string
	for _, j := range decode[JobList](t, get(t, h.ts, "/api/v1/jobs", token)).Jobs {
		pids = append(pids, j.Pid)
	}
	return pids
}

// Clearing hides the ended jobs from the caller's list only: the job is
// still read by pid, another administrator still lists it, and a job that
// ends later lists as usual.
func TestClearingFinishedJobsHidesThemForTheCaller(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	decodeStatus[UserAccount](t, h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "deputy", "password": testPassword, "roles": []string{"admin"},
	}), 201, "a second administrator")
	deputy := loginAs(t, h.ts, "deputy", testPassword).Token
	wantStatus(t, h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "listener", "password": testPassword,
	}), 201, "a member")
	member := loginAs(t, h.ts, "listener", testPassword).Token

	pid := h.rescanAndWait(t)
	if !slices.Contains(listedJobPIDs(t, h, h.token), pid) {
		t.Fatalf("the finished rescan %s is not listed before the clear", pid)
	}

	cleared := decodeStatus[JobsCleared](t, reqAs(t, h, "POST", "/api/v1/jobs/clear-finished", h.token, nil), 200, "clear finished jobs")
	if cleared.Cleared < 1 {
		t.Fatalf("cleared = %d, want at least the rescan", cleared.Cleared)
	}
	if slices.Contains(listedJobPIDs(t, h, h.token), pid) {
		t.Errorf("the cleared job %s is still listed for the clearing administrator", pid)
	}
	wantStatus(t, get(t, h.ts, "/api/v1/jobs/"+pid, h.token), 200, "the cleared job read by pid")
	if !slices.Contains(listedJobPIDs(t, h, deputy), pid) {
		t.Errorf("the second administrator no longer lists %s", pid)
	}

	wantStatus(t, reqAs(t, h, "POST", "/api/v1/jobs/clear-finished", member, nil), 403, "a member's clear")
	wantStatus(t, reqAs(t, h, "POST", "/api/v1/jobs/clear-finished", "", nil), 401, "an unauthenticated clear")

	later := h.rescanAndWait(t)
	if !slices.Contains(listedJobPIDs(t, h, h.token), later) {
		t.Errorf("the job %s that ended after the clear is not listed", later)
	}
	again := decodeStatus[JobsCleared](t, reqAs(t, h, "POST", "/api/v1/jobs/clear-finished", h.token, nil), 200, "clear again")
	if again.Cleared < 1 {
		t.Errorf("the second clear = %d, want the later job counted", again.Cleared)
	}
	if got := decodeStatus[JobsCleared](t, reqAs(t, h, "POST", "/api/v1/jobs/clear-finished", h.token, nil), 200, "clear with nothing new"); got.Cleared != 0 {
		t.Errorf("a clear with nothing finished = %d, want 0", got.Cleared)
	}
}
