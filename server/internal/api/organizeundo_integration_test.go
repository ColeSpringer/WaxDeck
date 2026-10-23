package api

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// newManagedHarness is the stock harness with its libraries managed, so
// organize lays out the demo tracks, which sit off every profile.
func newManagedHarness(t *testing.T) *harness {
	t.Helper()
	return newHarnessWith(t, func(cfg *service.Config) {
		for i := range cfg.Roots {
			cfg.Roots[i].Managed = true
		}
	})
}

// auditActions is every audit action under prefix, newest first.
func auditActions(t *testing.T, h *harness, prefix string) []string {
	t.Helper()
	page := decode[AuditEventPage](t, get(t, h.ts, "/api/v1/admin/audit?action="+prefix, h.token))
	var out []string
	for _, e := range page.Events {
		out = append(out, e.Action)
	}
	return out
}

// An apply answers the job it ran as, the history lists it, an undo
// moves the files back under a job of its own, and both are audited.
func TestOrganizeApplyUndoAndHistory(t *testing.T) {
	t.Parallel()
	h := newManagedHarness(t)
	stray := filepath.Join(h.library, "alpha.flac")
	if _, err := os.Stat(stray); err != nil {
		t.Fatalf("the demo track is not where the fixture put it: %v", err)
	}

	rep := decodeStatus[OrganizeReport](t, h.postJSON(t, "/api/v1/organize/apply", map[string]any{}), 200, "apply")
	if !strings.HasPrefix(rep.JobPid, "jb-") || rep.Moved != 4 || rep.Failed != 0 {
		t.Fatalf("apply = %+v, want every demo track moved by a job", rep)
	}
	if _, err := os.Stat(stray); err == nil {
		t.Fatal("the demo track did not move")
	}
	history := decode[OrganizeHistory](t, get(t, h.ts, "/api/v1/organize/history", h.token))
	if len(history.Batches) != 1 || history.Batches[0].JobPid != rep.JobPid ||
		history.Batches[0].Kind != OrganizeBatchKindOrganize || !history.Batches[0].Undoable ||
		history.Batches[0].Committed != 4 || deref(history.Batches[0].Profile) != "waxbin-native" {
		t.Fatalf("history = %+v, want the apply, undoable", history.Batches)
	}

	undo := decodeStatus[OrganizeReport](t, h.postJSON(t, "/api/v1/organize/undo",
		map[string]any{"jobPid": rep.JobPid}), 200, "undo")
	if !strings.HasPrefix(undo.JobPid, "jb-") || undo.JobPid == rep.JobPid || undo.Moved != 4 {
		t.Fatalf("undo = %+v, want every track moved back by a job of its own", undo)
	}
	if _, err := os.Stat(stray); err != nil {
		t.Fatalf("the demo track is not back: %v", err)
	}
	history = decode[OrganizeHistory](t, get(t, h.ts, "/api/v1/organize/history?limit=1", h.token))
	if len(history.Batches) != 1 || history.Batches[0].JobPid != undo.JobPid ||
		history.Batches[0].Kind != OrganizeBatchKindOrganizeUndo || history.Batches[0].Profile != nil {
		t.Fatalf("newest run = %+v, want the undo alone", history.Batches)
	}
	if got := decode[OrganizeHistory](t, get(t, h.ts, "/api/v1/organize/history", h.token)); len(got.Batches) != 2 {
		t.Fatalf("history = %+v, want the run and its undo", got.Batches)
	}
	if actions := auditActions(t, h, "organize."); strings.Join(actions, ",") != "organize.undo,organize.apply" {
		t.Fatalf("audit = %v, want the apply and the undo", actions)
	}
	// Back in the root, the files leave the artist and album folders the
	// apply made empty, and the undo removes them.
	if undo.DirsPruned == nil || *undo.DirsPruned < 1 {
		t.Fatalf("undo dirsPruned = %v, want the emptied folders counted", undo.DirsPruned)
	}
	job := decode[Job](t, get(t, h.ts, "/api/v1/jobs/"+undo.JobPid, h.token))
	if job.Kind != "organize-undo" || job.Result == nil || (*job.Result)["moved"] != float64(4) ||
		(*job.Result)["held"] != float64(0) || (*job.Result)["dirsPruned"] != float64(*undo.DirsPruned) {
		t.Fatalf("undo job = %+v, want its tally", job)
	}
	if _, named := (*job.Result)["profile"]; named {
		t.Errorf("undo job result = %v, want no profile: an undo lays out by none", *job.Result)
	}
	if run := decode[Job](t, get(t, h.ts, "/api/v1/jobs/"+rep.JobPid, h.token)); run.Result == nil ||
		(*run.Result)["profile"] != "waxbin-native" {
		t.Errorf("run job = %+v, want the profile it laid out by", run)
	}
	// A deliberate act whose result is worth its row, so the finished undo
	// stays listed like the run it undid.
	listed := map[string]string{}
	for _, j := range decode[JobList](t, get(t, h.ts, "/api/v1/jobs", h.token)).Jobs {
		listed[j.Pid] = j.State
	}
	if listed[undo.JobPid] != "done" || listed[rep.JobPid] != "done" {
		t.Fatalf("jobs = %v, want the run and its finished undo", listed)
	}
	wantStatus(t, get(t, h.ts, "/api/v1/organize/history?limit=0", h.token), 400, "a zero limit")
}

// An undo is refused before anything moves: a job that is no organize
// run, one that is not there, a read-only server, a listener.
func TestOrganizeUndoRefusals(t *testing.T) {
	t.Parallel()
	h := newManagedHarness(t)
	rep := decodeStatus[OrganizeReport](t, h.postJSON(t, "/api/v1/organize/apply", map[string]any{}), 200, "apply")

	scan := h.rescanAndWait(t)
	resp := h.postJSON(t, "/api/v1/organize/undo", map[string]any{"jobPid": scan})
	if e := decodeStatus[Error](t, resp, 400, "undo of a scan"); e.Code != "invalid-request" {
		t.Fatalf("undo of a scan = %+v, want invalid-request", e)
	}
	resp = h.postJSON(t, "/api/v1/organize/undo", map[string]any{"jobPid": "jb-01JZX5N8QW3F4V9T2B7KD3M9R6"})
	if e := decodeStatus[Error](t, resp, 404, "undo of no job"); e.Code != "not-found" {
		t.Fatalf("undo of no job = %+v, want not-found", e)
	}

	resp = h.postJSON(t, "/api/v1/users", map[string]any{"username": "sam", "password": testPassword})
	wantStatus(t, resp, 201, "creating a listener")
	sam := loginAs(t, h.ts, "sam", testPassword).Token
	wantStatus(t, reqAs(t, h, "POST", "/api/v1/organize/undo", sam, map[string]any{"jobPid": rep.JobPid}), 403, "an undo by a listener")
	wantStatus(t, get(t, h.ts, "/api/v1/organize/history", sam), 403, "the history for a listener")

	st := decode[AdminSettings](t, get(t, h.ts, "/api/v1/admin/settings", h.token))
	wantStatus(t, h.putJSON(t, "/api/v1/admin/settings", map[string]any{
		"signupEnabled":   st.SignupEnabled,
		"readOnly":        true,
		"backupKeepCount": st.BackupKeepCount,
		"backupKeepBytes": st.BackupKeepBytes,
	}), 200, "a read-only server")
	resp = h.postJSON(t, "/api/v1/organize/undo", map[string]any{"jobPid": rep.JobPid})
	if e := decodeStatus[Error](t, resp, 409, "undo on a read-only server"); e.Code != "read-only" {
		t.Fatalf("undo on a read-only server = %+v, want read-only", e)
	}
}
