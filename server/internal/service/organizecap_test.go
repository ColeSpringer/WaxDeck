package service

import (
	"testing"

	"github.com/colespringer/waxbin/model"
)

// itemPids is n well-formed item pids.
func itemPids(n int) []string {
	out := make([]string, n)
	for i := range out {
		out[i] = apiPID(PrefixTrack, model.NewPID())
	}
	return out
}

// An organize request or a health fix names at most 1000 items, as the
// API says: past that it is refused before anything is planned, run or
// queued, and up to it the count is no reason to refuse.
func TestAnOrganizeOrAFixPastTheItemCapIsRefused(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _, _ := managedTrackFixture(t)
	over := itemPids(maxItemPids + 1)
	if _, err := svc.PreviewOrganize(ctx, uc, "", over); KindOf(err) != KindInvalid {
		t.Fatalf("a preview of %d items = %v, want invalid", len(over), err)
	}
	if _, err := svc.ApplyOrganize(ctx, uc, "", over); KindOf(err) != KindInvalid {
		t.Fatalf("an apply of %d items = %v, want invalid", len(over), err)
	}
	if _, err := svc.StartHealthFix(ctx, uc, rulePathMismatch, over); KindOf(err) != KindInvalid {
		t.Fatalf("a path fix of %d items = %v, want invalid", len(over), err)
	}
	jobs, err := svc.lib.Jobs(ctx, 50)
	if err != nil {
		t.Fatal(err)
	}
	for _, j := range jobs {
		if j.Kind == "organize" {
			t.Fatalf("an organize job ran for a refused apply: %+v", j)
		}
	}
	if tasks, _, err := svc.ListToolTasksFor(ctx, uc, "", 10); err != nil || len(tasks) != 0 {
		t.Fatalf("tasks = %+v (%v), want none queued", tasks, err)
	}
	if _, err := svc.PreviewOrganize(ctx, uc, "", itemPids(maxItemPids)); err != nil {
		t.Fatalf("a preview of %d items = %v, want it planned", maxItemPids, err)
	}
}
