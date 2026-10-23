package api

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/db"
)

// A dismiss its clear refuses (the task's hidden files cannot leave their
// folder) answers 409 with the reason, the folder and the cause, which the
// app words; Clear finished counts the task as kept.
func TestADismissKeptForHiddenFilesSaysWhy(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritablePaths(t)
	h := newHarness(t)
	_, bookDir, book := booksLibrary(t, h)
	var paths, pids []string
	for _, f := range h.itemFiles(t, h.token, book.Pid) {
		paths = append(paths, deref(f.Path))
		bare := f.FilePid
		if _, rest, ok := strings.Cut(bare, "-"); ok {
			bare = rest
		}
		pids = append(pids, bare)
	}
	// A merge that failed after staging its output, every part in place:
	// clearing it removes the hidden output, which the folder refuses.
	const id = "tk-01JZX5N8QW3F4V9T2B7KDTASK1"
	staged := filepath.Join(bookDir, ".waxdeck-tool-"+id+"-0")
	if err := os.WriteFile(staged, []byte("merged"), 0o644); err != nil {
		t.Fatal(err)
	}
	fi, err := os.Stat(staged)
	if err != nil {
		t.Fatal(err)
	}
	params, err := json.Marshal(map[string]any{
		"partPaths": paths, "partFilePids": pids, "created": []string{staged}, "dir": bookDir, "step": "staged",
		"idents": map[string]any{staged: map[string]any{"size": fi.Size(), "modNs": fi.ModTime().UnixNano()}},
	})
	if err != nil {
		t.Fatal(err)
	}
	now := time.Now().UnixNano()
	// The administrator's own task: their Clear finished takes their own.
	if err := h.store.InsertToolTask(context.Background(), db.ToolTask{
		ID: id, Type: "book-merge", State: "failed", UserID: adminUserID(t, h), ItemPID: book.Pid, ItemTitle: book.Title,
		Params: string(params), ResultPIDs: "[]", Error: "the engine failed", CreatedAtNS: now, FinishedAtNS: now,
	}); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(bookDir, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(bookDir, 0o755) })

	refused := decodeStatus[Error](t, reqAs(t, h, "DELETE", "/api/v1/tools/tasks/"+id, h.token, nil), 409, "dismiss")
	if refused.Params == nil || (*refused.Params)["reason"] != "outputs-hidden" || (*refused.Params)["folder"] == "" ||
		!strings.Contains((*refused.Params)["cause"], "permission denied") {
		t.Fatalf("dismiss refusal = %+v (params %v), want outputs-hidden with the folder and cause", refused, refused.Params)
	}
	cleared := decodeStatus[ToolTasksCleared](t, h.postJSON(t, "/api/v1/tools/tasks/clear-finished", map[string]any{}), 200, "clear finished")
	if cleared.Deleted != 0 || cleared.Kept != 1 {
		t.Fatalf("clear finished = %+v, want the task kept and counted", cleared)
	}
	if err := os.Chmod(bookDir, 0o755); err != nil {
		t.Fatal(err)
	}
	wantStatus(t, reqAs(t, h, "DELETE", "/api/v1/tools/tasks/"+id, h.token, nil), 204, "dismiss once the folder lets go")
	if _, err := os.Stat(staged); !os.IsNotExist(err) {
		t.Errorf("the hidden output = %v, want it gone", err)
	}
}
