package service

import (
	"context"
	"slices"
	"strings"
	"testing"

	"github.com/colespringer/waxbin/model"
	"github.com/oklog/ulid/v2"
)

// removedFixture is a managed library after four ways an item can end up
// out of a mirror: left alone, trashed with its undo journal, deleted
// outright, and trashed then purged. snapshot is the cursor taken before
// any of it.
type removedFixture struct {
	ctx                           context.Context
	svc                           *Library
	admin                         *UserCtx
	kept, trashed, erased, purged string
	snapshot                      string
}

func newRemovedFixture(t *testing.T) removedFixture {
	t.Helper()
	ctx, svc, admin, _, tracks := newTrashFixture(t, "Kept", "Trashed", "Erased", "Purged")
	f := removedFixture{
		ctx: ctx, svc: svc, admin: admin,
		kept: tracks["Kept"].pid, trashed: tracks["Trashed"].pid,
		erased: tracks["Erased"].pid, purged: tracks["Purged"].pid,
	}
	snap, err := svc.SyncCatalogSnapshot(ctx, admin, "", 500)
	if err != nil || len(snap.Entries) != 4 {
		t.Fatalf("snapshot = %d entries (%v), want 4", len(snap.Entries), err)
	}
	f.snapshot = snap.NextSince
	if _, err := svc.Tools.DeleteItems(ctx, admin, []string{f.trashed, f.purged}, "trash", false); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Tools.DeleteItems(ctx, admin, []string{f.erased}, "permanent", false); err != nil {
		t.Fatal(err)
	}
	entries, err := svc.Tools.TrashEntries(ctx, admin, false, 100)
	if err != nil {
		t.Fatal(err)
	}
	for _, e := range entries {
		if e.ItemPID == f.purged {
			if _, err := svc.Tools.PurgeTrashEntry(ctx, admin, e.ID); err != nil {
				t.Fatal(err)
			}
			return f
		}
	}
	t.Fatalf("no trash entry for %s in %+v", f.purged, entries)
	return f
}

// tombstones is what the real delta says about each deleted item after
// the fixture's snapshot, by pid.
func (f removedFixture) tombstones(t *testing.T) map[string]string {
	t.Helper()
	out := map[string]string{}
	since := f.snapshot
	for {
		delta, err := f.svc.SyncCatalogDelta(f.ctx, f.admin, since, 500)
		if err != nil {
			t.Fatal(err)
		}
		for _, e := range delta.Entries {
			if e.Op == syncOpDelete {
				out[e.PID] = e.Reason
			}
		}
		since = delta.NextSince
		if !delta.More {
			return out
		}
	}
}

// A snapshot carries no tombstones, so a device that re-mirrors asks the
// server which of the items it still holds bytes for are gone for good.
// For every item the catalog holds the answer is the delta's own: pinned
// to the reasons the real delta gives the same items, not to a second
// statement of the rule.
func TestRemovedItemsFollowTheDeltasTombstoneRule(t *testing.T) {
	f := newRemovedFixture(t)
	tombstones := f.tombstones(t)
	for pid, want := range map[string]string{
		f.trashed: syncReasonHidden,
		f.erased:  syncReasonRemoved,
		f.purged:  syncReasonRemoved,
	} {
		if tombstones[pid] != want {
			t.Fatalf("the delta's reason for %s = %q, want %q (all: %v)", pid, tombstones[pid], want, tombstones)
		}
	}

	unknown := apiPID(PrefixTrack, model.PID(ulid.Make().String()))
	asked := []string{f.kept, f.trashed, f.erased, f.purged, unknown}
	got, err := f.svc.RemovedItems(f.ctx, asked)
	if err != nil {
		t.Fatal(err)
	}
	if want := []string{f.erased, f.purged}; !slices.Equal(got, want) {
		t.Fatalf("named %v, want %v", got, want)
	}
	for _, pid := range []string{f.kept, f.trashed, f.erased, f.purged} {
		if named, removed := slices.Contains(got, pid), tombstones[pid] == syncReasonRemoved; named != removed {
			t.Errorf("%s: named = %v but the delta's reason is %q", pid, named, tombstones[pid])
		}
	}
}

// An item the trash can still put back is not named, however long it has
// sat there, and is once the journal no longer holds it.
func TestRemovedItemsFollowTheTrashJournal(t *testing.T) {
	f := newRemovedFixture(t)
	entries, err := f.svc.Tools.TrashEntries(f.ctx, f.admin, false, 100)
	if err != nil {
		t.Fatal(err)
	}
	var entry string
	for _, e := range entries {
		if e.ItemPID == f.trashed {
			entry = e.ID
		}
	}
	if entry == "" {
		t.Fatalf("no trash entry for %s in %+v", f.trashed, entries)
	}
	if got, err := f.svc.RemovedItems(f.ctx, []string{f.trashed}); err != nil || len(got) != 0 {
		t.Fatalf("a restorable item was named: %v (%v)", got, err)
	}
	if _, err := f.svc.Tools.PurgeTrashEntry(f.ctx, f.admin, entry); err != nil {
		t.Fatal(err)
	}
	if got, err := f.svc.RemovedItems(f.ctx, []string{f.trashed}); err != nil || !slices.Equal(got, []string{f.trashed}) {
		t.Fatalf("a purged item was named %v (%v), want it", got, err)
	}
}

// A device can hold downloads from a server it was pointed at before this
// one, and a pid this catalog holds no row for cannot say whether it was
// dropped here or never minted here. Neither is named, so asking about
// another server's downloads frees none of them; an item held archived
// with nothing left to restore it from still is.
func TestRemovedItemsNameNothingTheCatalogDoesNotHold(t *testing.T) {
	f := newRemovedFixture(t)
	var asked []string
	for _, prefix := range []string{PrefixTrack, PrefixBook, PrefixEpisode} {
		asked = append(asked, apiPID(prefix, model.PID(ulid.Make().String())))
	}
	got, err := f.svc.RemovedItems(f.ctx, append(asked, f.erased))
	if err != nil {
		t.Fatal(err)
	}
	if want := []string{f.erased}; !slices.Equal(got, want) {
		t.Fatalf("named %v, want only the item deleted outright %v", got, want)
	}
}

// The answer repeats each named pid as it was asked, once, in the order
// asked. A pid without an item prefix, or no pid at all, is skipped and no
// error. Nothing named is an empty list; an empty ask, or one past the
// bound, is refused.
func TestRemovedItemsAnswerAsAsked(t *testing.T) {
	f := newRemovedFixture(t)
	unknown := apiPID(PrefixTrack, model.PID(ulid.Make().String()))
	other := strings.ToLower(f.erased)

	got, err := f.svc.RemovedItems(f.ctx, []string{
		f.purged, f.kept, f.purged, unknown, other,
		"al-" + strings.TrimPrefix(f.erased, "tr-"), // an album's prefix
		"not-a-pid", "", "tr-",
	})
	if err != nil {
		t.Fatal(err)
	}
	if want := []string{f.purged, other}; !slices.Equal(got, want) {
		t.Fatalf("named %v, want %v", got, want)
	}

	got, err = f.svc.RemovedItems(f.ctx, []string{f.kept, f.trashed, "not-a-pid"})
	if err != nil || got == nil || len(got) != 0 {
		t.Fatalf("nothing to name = %#v (%v), want an empty list", got, err)
	}
	for _, empty := range [][]string{nil, {}} {
		if got, err := f.svc.RemovedItems(f.ctx, empty); KindOf(err) != KindInvalid {
			t.Fatalf("an empty ask = %#v (%v), want an invalid-request error", got, err)
		}
	}

	tooMany := make([]string, 501)
	for i := range tooMany {
		tooMany[i] = f.purged
	}
	if _, err := f.svc.RemovedItems(f.ctx, tooMany); KindOf(err) != KindInvalid {
		t.Fatalf("501 pids = %v, want an invalid-request error", err)
	}
	if got, err := f.svc.RemovedItems(f.ctx, tooMany[:500]); err != nil || len(got) != 1 {
		t.Fatalf("500 repeats of one pid = %v (%v), want it once", got, err)
	}
}
