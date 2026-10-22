package db

import (
	"context"
	"errors"
	"testing"
)

// Queuing a fetch that spent its attempts starts it over: it is due at
// once, from no attempts and no error, rather than staying failed with a
// 202 that leases nothing.
func TestQueuingAFailedFetchRetriesIt(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	d := openTest(t)
	const max = 5
	if err := d.EnqueueFetch(ctx, "ep", "", 1, max); err != nil {
		t.Fatal(err)
	}
	now := int64(100)
	for range max {
		row, err := d.LeaseFetch(ctx, now, 10, max)
		if err != nil {
			t.Fatal(err)
		}
		if err := d.FailFetch(ctx, row.Key, "host answered 503", now+50); err != nil {
			t.Fatal(err)
		}
		now += 100
	}
	if _, err := d.LeaseFetch(ctx, now, 10, max); !errors.Is(err, ErrNotFound) {
		t.Fatalf("leasing a spent fetch = %v, want nothing to lease", err)
	}

	if err := d.EnqueueFetch(ctx, "ep", "u1", now, max); err != nil {
		t.Fatal(err)
	}
	rows, err := d.FetchQueueRows(ctx, []string{"ep"})
	if err != nil {
		t.Fatal(err)
	}
	if got := rows["ep"]; got.Attempts != 0 || got.LastError != "" {
		t.Errorf("a re-queued failed fetch = %+v, want no attempts and no error", got)
	}
	row, err := d.LeaseFetch(ctx, now, 10, max)
	if err != nil {
		t.Fatalf("leasing a re-queued failed fetch = %v, want it due now", err)
	}
	if row.Key != "ep" || row.Attempts != 0 {
		t.Errorf("leased %+v, want ep from no attempts", row)
	}
}

// Queuing a fetch that is running, or waiting out a failure's backoff,
// changes nothing about it: the running download keeps its lease and
// the backoff stands.
func TestQueuingALiveFetchLeavesItAlone(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	d := openTest(t)
	const max = 5
	if err := d.EnqueueFetch(ctx, "running", "", 1, max); err != nil {
		t.Fatal(err)
	}
	if _, err := d.LeaseFetch(ctx, 100, 1_000_000, max); err != nil {
		t.Fatal(err)
	}
	if err := d.EnqueueFetch(ctx, "running", "u1", 150, max); err != nil {
		t.Fatal(err)
	}
	if row, err := d.LeaseFetch(ctx, 200, 1000, max); !errors.Is(err, ErrNotFound) {
		t.Fatalf("leasing beside a running fetch = %+v (%v), want its lease to stand", row, err)
	}

	if err := d.EnqueueFetch(ctx, "waiting", "", 300, max); err != nil {
		t.Fatal(err)
	}
	if err := d.FailFetch(ctx, "waiting", "host answered 503", 5000); err != nil {
		t.Fatal(err)
	}
	if err := d.EnqueueFetch(ctx, "waiting", "u1", 400, max); err != nil {
		t.Fatal(err)
	}
	rows, err := d.FetchQueueRows(ctx, []string{"waiting"})
	if err != nil {
		t.Fatal(err)
	}
	if got := rows["waiting"]; got.Attempts != 1 || got.LastError != "host answered 503" {
		t.Errorf("a re-queued fetch in its backoff = %+v, want its attempt and error kept", got)
	}
	if _, err := d.LeaseFetch(ctx, 4000, 1000, max); !errors.Is(err, ErrNotFound) {
		t.Fatalf("leasing inside the backoff = %v, want nothing due", err)
	}
}
