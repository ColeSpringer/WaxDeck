package service

import (
	"testing"

	"github.com/colespringer/waxbin/model"
)

// TestResumeShelfFillsPastTrashedItems is the shelf coming back short.
//
// The stamps query spent the whole limit before any of the four filters
// beside it ran - kind, trashed, library visibility, subscription - so
// trashing the most recently positioned book emptied a one-slot shelf
// that had another positioned book right behind it. Unlike the
// visibility and subscription filters, this one bites full-visibility
// callers, and Subsonic's resume surface reads the same list.
func TestResumeShelfFillsPastTrashedItems(t *testing.T) {
	ctx, f := newMigrateFixture(t)
	older := f.itemPID(t, ctx, model.KindBook, "The Fixture Book")
	newer := f.itemPID(t, ctx, model.KindBook, "The Chaptered Fixture")

	// Stamped in order, so `newer` is the head of the stamp table.
	if _, err := f.svc.Checkpoint(ctx, f.uc, older, 5000, nil); err != nil {
		t.Fatalf("checkpointing the older book: %v", err)
	}
	if _, err := f.svc.Checkpoint(ctx, f.uc, newer, 5000, nil); err != nil {
		t.Fatalf("checkpointing the newer book: %v", err)
	}
	if got := resumePIDs(t, f, 1); len(got) != 1 || got[0] != newer {
		t.Fatalf("one-slot shelf = %v, want [%s]", got, newer)
	}

	if _, err := f.svc.DeleteItems(ctx, f.uc, []string{newer}, "trash", false); err != nil {
		t.Fatalf("trashing the newer book: %v", err)
	}

	got := resumePIDs(t, f, 1)
	if len(got) != 1 || got[0] != older {
		t.Errorf("one-slot shelf after trashing its head = %v, want [%s]", got, older)
	}
}

func resumePIDs(t *testing.T, f *migrateFixture, limit int) []string {
	t.Helper()
	items, err := f.svc.RecentlyPositionedItems(t.Context(), f.uc, limit)
	if err != nil {
		t.Fatalf("RecentlyPositionedItems: %v", err)
	}
	out := make([]string, 0, len(items))
	for _, it := range items {
		out = append(out, it.PID)
	}
	return out
}
