package api

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
)

// lockedTrack scans one track into its own folder of the harness library
// and answers its pid and folder. Its length follows its names, so two
// tracks of one test never share their audio and join as copies.
func lockedTrack(t *testing.T, h *harness, folder, title string) (string, string) {
	t.Helper()
	dir := filepath.Join(h.library, folder)
	length := time.Duration(2000+100*len(folder)+10*len(title)) * time.Millisecond
	if _, err := fixtures.Generate(dir, fixtures.Spec{
		Name: "track", Codec: fixtures.CodecFLAC, Duration: length,
		Tags: map[string]string{"TITLE": title, "ARTIST": "Lock Smith", "ALBUM": folder, "TRACKNUMBER": "1"},
	}); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	return h.itemTitled(t, h.token, title).Pid, dir
}

// A delete on a folder the server cannot write answers storage-unwritable
// with nothing moved: the file stays, the trash journals nothing, and the
// audit says the delete was refused.
func TestDeletingOnAnUnwritableLibraryAnswersStorageUnwritable(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritablePaths(t)
	h := newHarness(t)
	pid, dir := lockedTrack(t, h, "Locked Shelf", "Locked Away")

	plan := decodeStatus[DeleteItemsResult](t, h.postJSON(t, "/api/v1/library/items/delete", map[string]any{
		"pids": []string{pid}, "mode": "trash", "dryRun": true,
	}), 200, "the plan")
	if len(plan.Entries) != 1 || plan.Entries[0].Paths == nil || len(*plan.Entries[0].Paths) != 1 ||
		(*plan.Entries[0].Paths)[0] != "Locked Shelf/track.flac" {
		t.Fatalf("plan entries = %+v, want the file named by its place in the library", plan.Entries)
	}
	if plan.Trashed != nil || plan.Failed != nil {
		t.Fatalf("plan totals = trashed %v failed %v, want none on a dry run", plan.Trashed, plan.Failed)
	}

	if err := os.Chmod(dir, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(dir, 0o755) })
	resp := h.postJSON(t, "/api/v1/library/items/delete", map[string]any{"pids": []string{pid}, "mode": "trash"})
	if resp.StatusCode != 409 {
		resp.Body.Close()
		t.Fatalf("delete on an unwritable folder = %d, want 409", resp.StatusCode)
	}
	if e := decode[Error](t, resp); e.Code != "storage-unwritable" || strings.Contains(e.Message, h.library) {
		t.Fatalf("refusal = %+v, want storage-unwritable without the server's folder", e)
	}
	if _, err := os.Stat(filepath.Join(dir, "track.flac")); err != nil {
		t.Fatalf("the refused file moved: %v", err)
	}
	if entries := decode[TrashList](t, get(t, h.ts, "/api/v1/admin/trash", h.token)).Entries; len(entries) != 0 {
		t.Fatalf("trash = %+v, want nothing journaled for a refused delete", entries)
	}
	refused := decode[AuditEventPage](t, get(t, h.ts, "/api/v1/admin/audit?action=items.delete.refused", h.token)).Events
	done := decode[AuditEventPage](t, get(t, h.ts, "/api/v1/admin/audit?action=items.delete", h.token)).Events
	if len(refused) != 1 || len(done) != 0 {
		t.Fatalf("audit refused %d, deleted %d, want the one refusal and no delete", len(refused), len(done))
	}
}

// A delete the filesystem took half of answers what went and counts what
// stayed, per item.
func TestAPartlyRefusedDeleteCountsWhatStayed(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritablePaths(t)
	h := newHarness(t)
	open, _ := lockedTrack(t, h, "Open Shelf", "Free To Go")
	locked, dir := lockedTrack(t, h, "Locked Shelf", "Held Fast")
	if err := os.Chmod(dir, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(dir, 0o755) })
	res := decodeStatus[DeleteItemsResult](t, h.postJSON(t, "/api/v1/library/items/delete", map[string]any{
		"pids": []string{open, locked}, "mode": "trash",
	}), 200, "a half-refused delete")
	if !res.Applied || derefIntOr(res.Trashed) != 1 || derefIntOr(res.Failed) != 1 {
		t.Fatalf("result = applied %v trashed %v failed %v, want 1 and 1", res.Applied, res.Trashed, res.Failed)
	}
	for _, e := range res.Entries {
		if e.Pid == locked && (derefIntOr(e.Failed) != 1 || !strings.Contains(deref(e.Error), "permission denied")) {
			t.Errorf("the refused item's entry = %+v, want one failed file and why", e)
		}
	}
	// The record counts the one item that went, and says which stayed.
	done := decode[AuditEventPage](t, get(t, h.ts, "/api/v1/admin/audit?action=items.delete", h.token)).Events
	if len(done) != 1 || done[0].Detail == nil {
		t.Fatalf("delete audits = %+v, want one", done)
	}
	detail := *done[0].Detail
	failures, _ := detail["failures"].([]any)
	if detail["count"] != float64(1) || detail["failed"] != float64(1) || len(failures) != 1 {
		t.Errorf("audit detail = %v, want a count of 1 and the one failure", detail)
	}
}

// A quality-upgrade resolve the filesystem took half of records what
// went as removed and each file that stayed as a failure, as a delete
// does: never an item that stayed as removed.
func TestAPartlyRefusedResolveRecordsWhatStayed(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritablePaths(t)
	h := newHarness(t)
	keep, _ := lockedTrack(t, h, "Keeper Shelf", "Kept Best")
	open, _ := lockedTrack(t, h, "Open Shelf", "Lesser Copy")
	locked, dir := lockedTrack(t, h, "Locked Shelf", "Stuck Copy")
	if err := os.Chmod(dir, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(dir, 0o755) })
	resp := h.postJSON(t, "/api/v1/library/upgrades/resolve", map[string]any{
		"keepItemPid": keep, "removeItemPids": []string{open, locked},
	})
	if resp.StatusCode != 409 {
		resp.Body.Close()
		t.Fatalf("a half-refused resolve = %d, want 409", resp.StatusCode)
	}
	resp.Body.Close()
	done := decode[AuditEventPage](t, get(t, h.ts, "/api/v1/admin/audit?action=items.delete", h.token)).Events
	if len(done) != 1 || done[0].Detail == nil {
		t.Fatalf("delete audits = %+v, want one", done)
	}
	detail := *done[0].Detail
	removed, _ := detail["removed"].([]any)
	failures, _ := detail["failures"].([]any)
	if len(removed) != 1 || removed[0] != open || detail["trashed"] != float64(1) || detail["failed"] != float64(1) || len(failures) != 1 {
		t.Fatalf("audit detail = %v, want %s alone removed, one trashed and one failure", detail, open)
	}
	if f, _ := failures[0].(map[string]any); f["pid"] != locked || f["file"] != "track.flac" || !strings.Contains(fmt.Sprint(f["reason"]), "permission denied") {
		t.Errorf("failure = %v, want %s's file and why it stayed", failures[0], locked)
	}
}

// A restore the file's folder refuses answers storage-unwritable, as the
// delete would, and the entry stays in the trash to restore once the
// folder takes the write.
func TestARestoreTheFolderRefusesAnswersStorageUnwritable(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritablePaths(t)
	h := newHarness(t)
	pid, dir := lockedTrack(t, h, "Restore Shelf", "Back Again")
	// Kept by another file, the folder stays once its track goes.
	if err := os.WriteFile(filepath.Join(dir, "notes.txt"), []byte("liner notes"), 0o644); err != nil {
		t.Fatal(err)
	}
	wantStatus(t, h.postJSON(t, "/api/v1/library/items/delete", map[string]any{"pids": []string{pid}, "mode": "trash"}),
		200, "the delete")
	entries := decode[TrashList](t, get(t, h.ts, "/api/v1/admin/trash", h.token)).Entries
	if len(entries) != 1 {
		t.Fatalf("trash = %+v, want the one entry", entries)
	}
	if err := os.Chmod(dir, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(dir, 0o755) })
	resp := h.postJSON(t, "/api/v1/admin/trash/"+entries[0].Id+"/restore", nil)
	if resp.StatusCode != 409 {
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		t.Fatalf("a restore into an unwritable folder = %d (%s), want 409", resp.StatusCode, body)
	}
	if e := decode[Error](t, resp); e.Code != "storage-unwritable" || strings.Contains(e.Message, h.library) {
		t.Fatalf("refusal = %+v, want storage-unwritable without the server's folder", e)
	}
	if left := decode[TrashList](t, get(t, h.ts, "/api/v1/admin/trash", h.token)).Entries; len(left) != 1 || left[0].Id != entries[0].Id {
		t.Errorf("trash = %+v, want the entry still there", left)
	}
}
