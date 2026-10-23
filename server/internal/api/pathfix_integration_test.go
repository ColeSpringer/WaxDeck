package api

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// The path rule's bulk fix is the Organize screen's to preview and
// apply: a fix that names no items is refused and points there.
func TestHealthPathFixNeedsAScope(t *testing.T) {
	t.Parallel()
	h := newManagedHarness(t)
	if err := h.svc.RunHealthSweep(context.Background()); err != nil {
		t.Fatal(err)
	}
	resp := h.postJSON(t, "/api/v1/library/health/fix", map[string]any{"rule": "path-mismatch"})
	if e := decodeStatus[Error](t, resp, 400, "an unscoped path fix"); e.Code != "invalid-request" ||
		!strings.Contains(e.Message, "/organize") {
		t.Fatalf("refusal = %+v, want invalid-request pointing at organize", e)
	}
}

// A path fix naming one item moves it as a task whose summary says it
// moved, and names the organize job that did.
func TestAScopedPathFixMovesOneItem(t *testing.T) {
	t.Parallel()
	h := newManagedHarness(t)
	alpha := h.itemTitled(t, h.token, "Alpha Song")
	resp := h.postJSON(t, "/api/v1/library/health/fix", map[string]any{
		"rule": "path-mismatch", "itemPids": []string{alpha.Pid},
	})
	fix := decodeStatus[HealthFixResult](t, resp, 202, "a scoped path fix")
	if fix.TaskId == nil || fix.JobPid != nil || fix.Queued != 1 {
		t.Fatalf("fix = %+v, want one item on a task", fix)
	}
	for h.svc.DrainHealthFixes(context.Background()) {
	}
	task := decode[ToolTask](t, get(t, h.ts, "/api/v1/tools/tasks/"+*fix.TaskId, h.token))
	if task.State != "done" || task.Summary == nil {
		t.Fatalf("task = %+v, want it done with a summary", task)
	}
	sum := *task.Summary
	jobs, _ := sum["jobPids"].([]any)
	if sum["moved"] != float64(1) || sum["attempted"] != float64(1) || len(jobs) != 1 {
		t.Fatalf("summary = %v, want the one item moved by a named job", sum)
	}
	if _, err := os.Stat(filepath.Join(h.library, "alpha.flac")); err == nil {
		t.Fatal("the track did not move")
	}
	history := decode[OrganizeHistory](t, get(t, h.ts, "/api/v1/organize/history", h.token))
	if len(history.Batches) != 1 || history.Batches[0].JobPid != jobs[0] {
		t.Fatalf("history = %+v, want the fix's job", history.Batches)
	}
}
