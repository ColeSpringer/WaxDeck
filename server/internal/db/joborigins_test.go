package db

import (
	"context"
	"errors"
	"slices"
	"testing"
)

// An origin stays while its job is settled, so a fix still reads as
// running through its re-check, and one process settles it once. A
// settle cut short by a stop is taken over by the next process.
func TestJobOriginClaimHoldsUntilSettled(t *testing.T) {
	ctx := context.Background()
	d := openTest(t)
	for _, o := range []JobOrigin{
		{PID: "fix", UserID: "u1", Rule: "missing-lyrics", CreatedAtNS: 1},
		{PID: "scan", UserID: "u1", CreatedAtNS: 2},
	} {
		if err := d.InsertJobOrigin(ctx, o); err != nil {
			t.Fatal(err)
		}
	}
	const opened = 50
	if o, err := d.ClaimJobOrigin(ctx, "fix", 100, opened); err != nil || o.Rule != "missing-lyrics" || o.UserID != "u1" {
		t.Fatalf("claim = %+v (%v), want the fix's origin", o, err)
	}
	if _, err := d.ClaimJobOrigin(ctx, "fix", 101, opened); !errors.Is(err, ErrNotFound) {
		t.Fatalf("a second claim in the same process = %v, want ErrNotFound", err)
	}
	if rules, err := d.JobOriginRules(ctx); err != nil || !slices.Equal(rules, []string{"missing-lyrics"}) {
		t.Fatalf("rules while settling = %v (%v), want the fix's", rules, err)
	}
	if o, err := d.ClaimJobOrigin(ctx, "fix", 300, 200); err != nil || o.PID != "fix" {
		t.Fatalf("claim by the next process = %+v (%v), want it taken over", o, err)
	}
	if rule, err := d.DeleteJobOrigin(ctx, "fix"); err != nil || rule != "missing-lyrics" {
		t.Fatalf("delete = %q (%v), want the fix's rule", rule, err)
	}
	if _, err := d.DeleteJobOrigin(ctx, "fix"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("a second delete = %v, want ErrNotFound", err)
	}
	if rules, err := d.JobOriginRules(ctx); err != nil || len(rules) != 0 {
		t.Fatalf("rules once settled = %v (%v), want none", rules, err)
	}
	if left, err := d.JobOrigins(ctx); err != nil || len(left) != 1 || left[0].PID != "scan" {
		t.Fatalf("origins = %+v (%v), want the scan's alone", left, err)
	}
}

// A health fix task goes in only while its rule is not being fixed, by a
// task or a pass, in one statement: two requests cannot both get in.
func TestInsertHealthFixTaskOnlyOncePerRule(t *testing.T) {
	ctx := context.Background()
	d := openTest(t)
	task := func(id, rule string) ToolTask {
		return ToolTask{ID: id, Type: "health-fix", State: "queued", Params: `{"rule":"` + rule + `"}`, ResultPIDs: "[]", CreatedAtNS: 1}
	}
	if ok, err := d.InsertHealthFixTask(ctx, task("tk-1", "write-unsynced"), "write-unsynced"); err != nil || !ok {
		t.Fatalf("first = (%v, %v), want inserted", ok, err)
	}
	if ok, err := d.InsertHealthFixTask(ctx, task("tk-2", "write-unsynced"), "write-unsynced"); err != nil || ok {
		t.Fatalf("second = (%v, %v), want refused", ok, err)
	}
	if err := d.InsertJobOrigin(ctx, JobOrigin{PID: "jb-1", UserID: "u1", Rule: "missing-lyrics", CreatedAtNS: 1}); err != nil {
		t.Fatal(err)
	}
	if ok, err := d.InsertHealthFixTask(ctx, task("tk-3", "missing-lyrics"), "missing-lyrics"); err != nil || ok {
		t.Fatalf("while a pass fixes it = (%v, %v), want refused", ok, err)
	}
	if ok, err := d.InsertHealthFixTask(ctx, task("tk-4", "path-mismatch"), "path-mismatch"); err != nil || !ok {
		t.Fatalf("another rule = (%v, %v), want inserted", ok, err)
	}
}
