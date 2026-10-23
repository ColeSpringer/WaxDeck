package service

import (
	"slices"
	"sync/atomic"
	"testing"
)

// An apply over a few items re-checks the path rule for those items when
// it ends, which the request waits for: no organize pass over the whole
// library. The moved item leaves the rule at once; the rest stay on it.
func TestAScopedApplyRechecksItsOwnItems(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, stray := fillerLibrary(t)
	if err := svc.RunHealthSweep(ctx); err != nil {
		t.Fatal(err)
	}
	before, err := svc.db.HealthRuleCounts(ctx)
	if err != nil || before[rulePathMismatch] < 100 {
		t.Fatalf("path-mismatch = %d (%v), want the misplaced files", before[rulePathMismatch], err)
	}
	var whole atomic.Int32
	svc.pathPlanHook = func(pids []string) {
		if pids == nil {
			whole.Add(1)
		}
	}
	rep, err := svc.ApplyOrganize(ctx, uc, "", []string{stray})
	if err != nil || rep.Moved != 1 {
		t.Fatalf("apply = %+v (%v), want the stray moved", rep, err)
	}
	if n := whole.Load(); n != 0 {
		t.Fatalf("the run's end planned the whole library %d times, want its own items alone", n)
	}
	after, err := svc.db.HealthRuleCounts(ctx)
	if err != nil || after[rulePathMismatch] != before[rulePathMismatch]-1 {
		t.Fatalf("path-mismatch = %d (%v), want %d: the stray off the rule, the rest on it",
			after[rulePathMismatch], err, before[rulePathMismatch]-1)
	}
	_, bare, _ := parseAPIPID(stray)
	failing, err := svc.db.FailingItems(ctx, rulePathMismatch, 1000)
	if err != nil || slices.Contains(failing, string(bare)) {
		t.Fatalf("failing = %d items (%v), want the stray not among them", len(failing), err)
	}
}

// An apply over every library re-checks the items failing the rule, each
// against a plan of its own items: the rows drop at once, with no pass
// planned over the whole library at the run's end.
func TestAnUnscopedApplyRechecksTheFailingItems(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _, _ := managedTrackFixture(t)
	if err := svc.RunHealthSweep(ctx); err != nil {
		t.Fatal(err)
	}
	var whole atomic.Int32
	svc.pathPlanHook = func(pids []string) {
		if pids == nil {
			whole.Add(1)
		}
	}
	if rep, err := svc.ApplyOrganize(ctx, uc, "", nil); err != nil || rep.Moved != 1 {
		t.Fatalf("apply = %+v (%v), want the track moved", rep, err)
	}
	if n := whole.Load(); n != 0 {
		t.Fatalf("the run's end planned the whole library %d times, want none", n)
	}
	if counts, err := svc.db.HealthRuleCounts(ctx); err != nil || counts[rulePathMismatch] != 0 {
		t.Fatalf("path-mismatch = %d (%v), want the moved track off the rule", counts[rulePathMismatch], err)
	}
}

// An apply over items the path rule never flagged changes no row of the
// health index: their end plans nothing for the rule and tells no account
// the health changed.
func TestAScopedApplyOfUnflaggedItemsLeavesTheHealthAlone(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _, pid := managedTrackFixture(t)
	events := func() int {
		t.Helper()
		var n int
		if err := svc.db.Writer().QueryRowContext(ctx, `SELECT COUNT(*) FROM event_log WHERE kind = ?`,
			eventHealth).Scan(&n); err != nil {
			t.Fatal(err)
		}
		return n
	}
	before := events()
	var plans atomic.Int32
	svc.pathPlanHook = func([]string) { plans.Add(1) }
	if rep, err := svc.ApplyOrganize(ctx, uc, "", []string{pid}); err != nil || rep.Moved != 1 {
		t.Fatalf("apply = %+v (%v), want the track moved", rep, err)
	}
	if n := plans.Load(); n != 0 {
		t.Errorf("the run's end planned the path rule %d times for items it never flagged", n)
	}
	if n := events() - before; n != 0 {
		t.Errorf("health events = %d, want none: no row changed", n)
	}
}
