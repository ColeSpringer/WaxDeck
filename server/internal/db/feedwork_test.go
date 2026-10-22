package db

import (
	"context"
	"errors"
	"slices"
	"testing"
)

// A fetch ends with everyone who asked for it, whenever they asked: an
// automatic fetch has nobody, and a canceled one forgets who asked.
func TestAFetchEndsWithEveryoneWhoAskedForIt(t *testing.T) {
	ctx := context.Background()
	d := openTest(t)
	if err := d.EnqueueFetch(ctx, "ep", "", 1, 5); err != nil {
		t.Fatal(err)
	}
	if _, err := d.LeaseFetch(ctx, 10, 100, 5); err != nil {
		t.Fatal(err)
	}
	for i, u := range []string{"u2", "u1", "u2"} {
		if err := d.EnqueueFetch(ctx, "ep", u, int64(20+i), 5); err != nil {
			t.Fatal(err)
		}
	}
	if by, err := d.FinishFetch(ctx, "ep", "show", 100); err != nil || !slices.Equal(by, []string{"u1", "u2"}) {
		t.Fatalf("finish = %v (%v), want both accounts that asked", by, err)
	}
	if rows, err := d.FetchQueueRows(ctx, []string{"ep"}); err != nil || len(rows) != 0 {
		t.Fatalf("rows after finishing = %v (%v), want it gone", rows, err)
	}
	if _, err := d.FinishFetch(ctx, "ep", "show", 100); !errors.Is(err, ErrNotFound) {
		t.Fatalf("finishing a finished fetch = %v, want ErrNotFound", err)
	}

	if err := d.EnqueueFetch(ctx, "ep2", "u1", 50, 5); err != nil {
		t.Fatal(err)
	}
	if err := d.CompleteFetch(ctx, "ep2"); err != nil {
		t.Fatal(err)
	}
	if err := d.EnqueueFetch(ctx, "ep2", "", 60, 5); err != nil {
		t.Fatal(err)
	}
	if by, err := d.FinishFetch(ctx, "ep2", "show", 100); err != nil || len(by) != 0 {
		t.Fatalf("finish after a cancel = %v (%v), want nobody", by, err)
	}
}
