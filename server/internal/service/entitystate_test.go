package service

import (
	"context"
	"strings"
	"testing"
)

// The entity star and rating surface is gated exactly as entity search
// hits are: an entity is visible when a library holding one of its
// member items is granted. The gate reads a lookup and a visibility
// check, and those are two separate verdicts - a lookup failure is not
// a not-found - so both halves are pinned here.

// entityFixture returns a catalog fixture, an album entity pid, and two
// restricted contexts: one granted the library holding it, one granted
// a different library entirely.
func entityFixture(t *testing.T) (context.Context, *Library, *UserCtx, string, *UserCtx, *UserCtx) {
	t.Helper()
	ctx, svc, admin := newCatalogFixture(t)

	res, err := svc.Search(ctx, admin, "Signal Garden", 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Albums) == 0 {
		t.Fatal("fixture album not in search results")
	}
	albumPID := res.Albums[0].PID

	libs, err := svc.Libraries(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if len(libs) != 1 {
		t.Fatalf("libraries = %d, want the one fixture root", len(libs))
	}
	granted := &UserCtx{
		ID: admin.ID, CatalogPID: admin.CatalogPID,
		Libraries: map[string]bool{strings.TrimPrefix(libs[0].PID, PrefixLibrary+"-"): true},
	}
	other, err := svc.AddLibrary(ctx, admin, AddLibraryInput{Name: "other", Path: t.TempDir()})
	if err != nil {
		t.Fatalf("adding a second library: %v", err)
	}
	elsewhere := &UserCtx{
		ID: admin.ID, CatalogPID: admin.CatalogPID,
		Libraries: map[string]bool{strings.TrimPrefix(other.PID, PrefixLibrary+"-"): true},
	}
	return ctx, svc, admin, albumPID, granted, elsewhere
}

func TestEntityStateRestrictedVisibility(t *testing.T) {
	ctx, svc, _, albumPID, granted, elsewhere := entityFixture(t)

	// A caller granted the holding library reads and writes it.
	if _, err := svc.EntityPlayStateFor(ctx, granted, albumPID); err != nil {
		t.Fatalf("granted read: %v", err)
	}
	st, err := svc.SetEntityStar(ctx, granted, albumPID, true, nil)
	if err != nil || !st.Starred {
		t.Fatalf("granted star: %+v (%v), want starred", st, err)
	}

	// A caller granted some other library cannot tell the entity from
	// one that does not exist, on any entry point.
	if _, err := svc.EntityPlayStateFor(ctx, elsewhere, albumPID); KindOf(err) != KindNotFound {
		t.Errorf("ungranted read: kind = %v, want not-found", KindOf(err))
	}
	if _, err := svc.SetEntityStar(ctx, elsewhere, albumPID, true, nil); KindOf(err) != KindNotFound {
		t.Errorf("ungranted star: kind = %v, want not-found", KindOf(err))
	}
	rating := 60
	if _, err := svc.SetEntityRating(ctx, elsewhere, albumPID, &rating, nil); KindOf(err) != KindNotFound {
		t.Errorf("ungranted rating: kind = %v, want not-found", KindOf(err))
	}

	// The starred list filters the same way, so an ungranted caller
	// never receives a pid the reads above would refuse.
	list, err := svc.StarredEntities(ctx, elsewhere)
	if err != nil {
		t.Fatalf("ungranted starred list: %v", err)
	}
	if len(list.Albums) != 0 || len(list.Artists) != 0 {
		t.Errorf("ungranted starred list = %+v, want empty", list)
	}
	if list, err := svc.StarredEntities(ctx, granted); err != nil || len(list.Albums) != 1 {
		t.Errorf("granted starred list = %+v (%v), want the one starred album", list, err)
	}
}

// A malformed or non-entity pid is a plain not-found, never a panic or a
// pid handed to the catalog under the wrong kind.
func TestEntityStateRejectsNonEntityPIDs(t *testing.T) {
	ctx, svc, admin, _, _, _ := entityFixture(t)

	for _, pid := range []string{
		"",
		"nonsense",
		"al-not-a-ulid",
		"tr-01JZX5N8QW3F4V9T2B7KD3M9R6", // an item, not an entity
		"pl-01JZX5N8QW3F4V9T2B7KD3M9R6", // a playlist
	} {
		if _, err := svc.EntityPlayStateFor(ctx, admin, pid); KindOf(err) != KindNotFound {
			t.Errorf("read %q: kind = %v, want not-found", pid, KindOf(err))
		}
		if _, err := svc.SetEntityStar(ctx, admin, pid, true, nil); KindOf(err) != KindNotFound {
			t.Errorf("star %q: kind = %v, want not-found", pid, KindOf(err))
		}
	}

	// An out-of-range rating is rejected before the pid is resolved, so
	// it stays an invalid-request rather than becoming a not-found.
	rating := 500
	if _, err := svc.SetEntityRating(ctx, admin, "nonsense", &rating, nil); KindOf(err) != KindInvalid {
		t.Errorf("out-of-range rating: kind = %v, want invalid-request", KindOf(err))
	}
}
