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
	if err := d.EnqueueFetch(ctx, "ep", "", 1); err != nil {
		t.Fatal(err)
	}
	if _, err := d.LeaseFetch(ctx, 10, 100, 5); err != nil {
		t.Fatal(err)
	}
	for i, u := range []string{"u2", "u1", "u2"} {
		if err := d.EnqueueFetch(ctx, "ep", u, int64(20+i)); err != nil {
			t.Fatal(err)
		}
	}
	if by, err := d.FinishFetch(ctx, "ep"); err != nil || !slices.Equal(by, []string{"u1", "u2"}) {
		t.Fatalf("finish = %v (%v), want both accounts that asked", by, err)
	}
	if _, _, err := d.FetchQueueRow(ctx, "ep"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("row after finishing = %v, want it gone", err)
	}
	if _, err := d.FinishFetch(ctx, "ep"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("finishing a finished fetch = %v, want ErrNotFound", err)
	}

	if err := d.EnqueueFetch(ctx, "ep2", "u1", 50); err != nil {
		t.Fatal(err)
	}
	if err := d.CompleteFetch(ctx, "ep2"); err != nil {
		t.Fatal(err)
	}
	if err := d.EnqueueFetch(ctx, "ep2", "", 60); err != nil {
		t.Fatal(err)
	}
	if by, err := d.FinishFetch(ctx, "ep2"); err != nil || len(by) != 0 {
		t.Fatalf("finish after a cancel = %v (%v), want nobody", by, err)
	}
}
