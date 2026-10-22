package db

import (
	"context"
	"fmt"
	"testing"
)

// A listing reads a whole page's fetch states at once: queued and failed
// episodes answer with their attempts, and an episode with nothing queued
// is simply absent, however many the page names.
func TestFetchQueueRowsReadsAPageAtOnce(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	d := openTest(t)
	var pids []string
	for i := range 1200 {
		pid := fmt.Sprintf("ep-%04d", i)
		pids = append(pids, pid)
		if i%2 == 0 {
			if err := d.EnqueueFetch(ctx, pid, "", int64(i), 5); err != nil {
				t.Fatal(err)
			}
		}
	}
	if err := d.FailFetch(ctx, "ep-0002", "host answered 404", 99); err != nil {
		t.Fatal(err)
	}

	rows, err := d.FetchQueueRows(ctx, append(pids, "ep-never"))
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 600 {
		t.Fatalf("rows = %d, want the 600 queued", len(rows))
	}
	if got := rows["ep-0002"]; got.Attempts != 1 || got.LastError != "host answered 404" {
		t.Errorf("failed row = %+v, want one attempt and its error", got)
	}
	if got, ok := rows["ep-1198"]; !ok || got.Attempts != 0 || got.LastError != "" {
		t.Errorf("queued row = %+v (%v), want an untried queued fetch", got, ok)
	}
	if _, ok := rows["ep-0001"]; ok {
		t.Error("an episode with nothing queued answered a row")
	}

	if rows, err := d.FetchQueueRows(ctx, nil); err != nil || len(rows) != 0 {
		t.Errorf("no pids = %v (%v), want an empty answer", rows, err)
	}
}
