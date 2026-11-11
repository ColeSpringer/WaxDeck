package service

import (
	"slices"
	"strings"
	"testing"
	"time"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// A queue row out of attempts with its audio never judged (a storage
// outage spent them, or a worker leased it and never reported) is queued
// again once it has rested a week, by the next sweep even though the
// catalog did not move. A row the analyzer judged unreadable and one that
// gave up within the week stay.
func TestAnExhaustedSonicRowIsQueuedAgainAfterTheWeek(t *testing.T) {
	t.Parallel()
	logs := &syncBuffer{}
	ctx, svc, uc := newCatalogFixtureWith(t, catalogFixtureOptions{logs: logs})
	enableSonicAnalysis(t, ctx, svc, uc)
	if _, err := svc.SimilaritySweep(ctx); err != nil {
		t.Fatal(err)
	}
	states, err := svc.db.SimilarityQueueStates(ctx)
	if err != nil {
		t.Fatal(err)
	}
	keys := make([]string, 0, len(states))
	for key := range states {
		keys = append(keys, key)
	}
	slices.Sort(keys)
	if len(keys) < 3 {
		t.Fatalf("the sweep queued %d rows, want three to tell apart", len(keys))
	}
	old, retired, fresh := keys[0], keys[1], keys[2]

	// Every lease charges an attempt: lease the queue empty.
	for {
		work, err := svc.db.LeaseSimilarityWork(ctx, 50, 0, true)
		if err != nil {
			t.Fatal(err)
		}
		if len(work) == 0 {
			break
		}
	}
	lastTried := func(key string, ago time.Duration) {
		t.Helper()
		if _, err := svc.db.Writer().ExecContext(ctx,
			`UPDATE similarity_queue SET lease_until_ns = ? WHERE essence = ?`,
			time.Now().Add(-ago).UnixNano(), key); err != nil {
			t.Fatal(err)
		}
	}
	lastTried(old, 8*24*time.Hour)
	lastTried(fresh, 6*24*time.Hour)
	if err := svc.db.RetireSimilarityWork(ctx, retired, "too short"); err != nil {
		t.Fatal(err)
	}
	lastTried(retired, 30*24*time.Hour)

	version, err := svc.lib.DataVersion(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if err := svc.RunPrune(ctx); err != nil {
		t.Fatal(err)
	}
	if again, err := svc.lib.DataVersion(ctx); err != nil || again != version {
		t.Fatalf("the prune moved the catalog's data version (%d to %d, %v); the sweep would walk for it", version, again, err)
	}
	if _, err := svc.SimilaritySweep(ctx); err != nil {
		t.Fatal(err)
	}

	states, err = svc.db.SimilarityQueueStates(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if state, ok := states[old]; !ok {
		t.Error("the row that rested past the week was not queued again by a sweep on an unchanged catalog")
	} else if n := attemptsOf(t, ctx, svc, old); state != wdb.QueueWaiting || n != 0 {
		t.Errorf("the row that rested past the week is %v with %d attempts, want queued afresh", state, n)
	}
	if states[retired] != wdb.QueueRetired {
		t.Errorf("the row the analyzer judged is %v, want it still resting", states[retired])
	}
	if states[fresh] != wdb.QueueExhausted {
		t.Errorf("the row that gave up within the week is %v, want it still exhausted", states[fresh])
	}
	if !strings.Contains(logs.String(), "pruned exhausted sonic analysis") {
		t.Errorf("the prune said nothing; log:\n%s", logs.String())
	}
}
