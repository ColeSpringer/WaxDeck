package db

import (
	"context"
	"testing"
)

// A sweep reads the terminal rows of the scope it was given and nothing
// else: a running row is work in progress, another account's row is not
// the caller's, and a sweep that lost its owner id reads nothing rather
// than everything. What it read is what it deletes.
func TestFinishedToolTasksKeepToTheirScope(t *testing.T) {
	ctx := context.Background()
	d := openTest(t)
	seed := func(id, user, state string) {
		t.Helper()
		if err := d.InsertToolTask(ctx, ToolTask{
			ID: id, Type: "acquire", State: state, UserID: user,
			Params: "{}", ResultPIDs: "[]", CreatedAtNS: 1,
		}); err != nil {
			t.Fatal(err)
		}
	}
	remaining := func() map[string]bool {
		t.Helper()
		rows, err := d.ListToolTasks(ctx, "", 0, "", 50)
		if err != nil {
			t.Fatal(err)
		}
		ids := map[string]bool{}
		for _, row := range rows {
			ids[row.ID] = true
		}
		return ids
	}
	sweep := func(userID string, everyone bool) int {
		t.Helper()
		rows, err := d.FinishedToolTasks(ctx, userID, everyone, 0)
		if err != nil {
			t.Fatal(err)
		}
		ids := make([]string, len(rows))
		for i, row := range rows {
			ids[i] = row.ID
		}
		n, err := d.DeleteToolTasksByID(ctx, ids)
		if err != nil {
			t.Fatal(err)
		}
		return n
	}
	seed("a-done", "us-a", "done")
	seed("a-failed", "us-a", "failed")
	seed("a-parked", "us-a", "parked")
	seed("a-running", "us-a", "running")
	seed("b-done", "us-b", "done")
	seed("b-queued", "us-b", "queued")

	if n := sweep("", false); n != 0 {
		t.Fatalf("a sweep with no owner and no everyone deleted %d, want 0", n)
	}
	if n := sweep("us-a", false); n != 3 {
		t.Fatalf("a's sweep deleted %d, want its three finished rows", n)
	}
	if got := remaining(); len(got) != 3 || !got["a-running"] || !got["b-done"] || !got["b-queued"] {
		t.Fatalf("after a's sweep: %v, want a's running row and all of b's", got)
	}
	if n := sweep("us-a", true); n != 1 {
		t.Fatalf("the everyone sweep deleted %d, want b's finished row", n)
	}
	if got := remaining(); len(got) != 2 || !got["a-running"] || !got["b-queued"] {
		t.Fatalf("after the everyone sweep: %v, want only the unfinished rows", got)
	}
}
