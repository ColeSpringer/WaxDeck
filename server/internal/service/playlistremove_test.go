package service

import (
	"slices"
	"testing"
)

// A removal guarded by the item the caller saw refuses once the slot
// holds another, or none, so of two devices removing from one listing
// only the first takes a row; several positions refuse together.
func TestRemovingFromAStaleListingConflicts(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, uc)[:3]
	pl := playlistWith(t, ctx, svc, uc, "Two Devices", pids)

	if err := svc.RemovePlaylistItemAt(ctx, uc, pl, 0, pids[0]); err != nil {
		t.Fatal(err)
	}
	if err := svc.RemovePlaylistItemAt(ctx, uc, pl, 0, pids[0]); KindOf(err) != KindConflict {
		t.Fatalf("the second device's removal = %v (kind %q), want a conflict", err, KindOf(err))
	}
	if err := svc.RemovePlaylistItemAt(ctx, uc, pl, 2, pids[2]); KindOf(err) != KindConflict {
		t.Fatalf("a guarded removal past the shortened end = %v, want a conflict", err)
	}
	err := svc.RemovePlaylistItemsAt(ctx, uc, pl, []int{0, 1}, []string{pids[1], pids[0]})
	if KindOf(err) != KindConflict {
		t.Fatalf("a batch with one stale position = %v (kind %q), want a conflict", err, KindOf(err))
	}
	if left := memberPIDs(t, ctx, svc, uc, pl); !slices.Equal(left, pids[1:]) {
		t.Fatalf("members after the refused batch = %v, want %v untouched", left, pids[1:])
	}

	if err := svc.RemovePlaylistItemAt(ctx, uc, pl, 5, ""); KindOf(err) != KindNotFound {
		t.Fatalf("an unguarded removal past the end = %v, want not found", err)
	}
	if err := svc.RemovePlaylistItemsAt(ctx, uc, pl, []int{0, 5}, []string{"", ""}); KindOf(err) != KindNotFound {
		t.Fatalf("an unguarded batch past the end = %v, want not found", err)
	}
	if err := svc.RemovePlaylistItemAt(ctx, uc, pl, 0, "pl-"+pids[0][3:]); KindOf(err) != KindInvalid {
		t.Fatalf("a playlist pid as the expected item = %v, want invalid", err)
	}
}
