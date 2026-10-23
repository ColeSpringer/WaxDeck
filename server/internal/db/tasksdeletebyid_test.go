package db

import (
	"context"
	"fmt"
	"testing"
)

// Clearing finished tasks deletes them all in one statement: thousands of
// ids go at once, an unfinished one among them stays, and a refusal of any
// row leaves every row where it was rather than the ones before it gone.
func TestDeleteToolTasksByIDGoesInOneStatement(t *testing.T) {
	ctx := context.Background()
	d := openTest(t)
	const finished = 3000
	ids := make([]string, 0, finished+1)
	for i := range finished {
		id := fmt.Sprintf("tk-%05d", i)
		if err := d.InsertToolTask(ctx, ToolTask{ID: id, Type: "acquire", State: "done", UserID: "us-a",
			Params: "{}", ResultPIDs: "[]", CreatedAtNS: int64(i + 1)}); err != nil {
			t.Fatal(err)
		}
		ids = append(ids, id)
	}
	if err := d.InsertToolTask(ctx, ToolTask{ID: "tk-running", Type: "acquire", State: "running", UserID: "us-a",
		Params: "{}", ResultPIDs: "[]", CreatedAtNS: finished + 1}); err != nil {
		t.Fatal(err)
	}
	ids = append(ids, "tk-running")
	count := func() int {
		t.Helper()
		var n int
		if err := d.w.QueryRowContext(ctx, `SELECT COUNT(*) FROM tool_tasks`).Scan(&n); err != nil {
			t.Fatal(err)
		}
		return n
	}

	last := fmt.Sprintf("tk-%05d", finished-1)
	if _, err := d.w.ExecContext(ctx, `CREATE TRIGGER refuse_one BEFORE DELETE ON tool_tasks
		WHEN OLD.id = '`+last+`' BEGIN SELECT RAISE(ABORT, 'refused'); END`); err != nil {
		t.Fatal(err)
	}
	if n, err := d.DeleteToolTasksByID(ctx, ids); err == nil || n != 0 {
		t.Fatalf("a clear one row of which is refused = %d (%v), want an error and nothing gone", n, err)
	}
	if got := count(); got != finished+1 {
		t.Fatalf("rows after the refused clear = %d, want all %d", got, finished+1)
	}
	if _, err := d.w.ExecContext(ctx, `DROP TRIGGER refuse_one`); err != nil {
		t.Fatal(err)
	}

	n, err := d.DeleteToolTasksByID(ctx, ids)
	if err != nil || n != finished {
		t.Fatalf("clear = %d (%v), want the %d finished rows", n, err, finished)
	}
	if got := count(); got != 1 {
		t.Fatalf("rows after the clear = %d, want the running one", got)
	}
	if n, err := d.DeleteToolTasksByID(ctx, nil); err != nil || n != 0 {
		t.Fatalf("clearing no ids = %d (%v), want nothing", n, err)
	}
}
