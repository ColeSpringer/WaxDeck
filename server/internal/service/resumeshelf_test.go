package service

import (
	"context"
	"testing"

	"github.com/colespringer/waxbin/model"
)

// A book's or an episode's resume position is its Subsonic bookmark, so
// the listing applies what every listing does: the trash and the
// caller's content rules.

// subsonicBookmarkPIDs lists the item pids of who's bookmarks.
func subsonicBookmarkPIDs(t *testing.T, ctx context.Context, svc *Library, who *UserCtx) []string {
	t.Helper()
	marks, err := svc.SubsonicBookmarks(ctx, who)
	if err != nil {
		t.Fatal(err)
	}
	out := make([]string, 0, len(marks))
	for _, b := range marks {
		out = append(out, b.Item.PID)
	}
	return out
}

// A positioned book in the trash is no bookmark, and the one behind it
// still is.
func TestSubsonicBookmarksSkipATrashedBook(t *testing.T) {
	t.Parallel()
	ctx, f := newMigrateFixture(t)
	older := f.itemPID(t, ctx, model.KindBook, "The Fixture Book")
	newer := f.itemPID(t, ctx, model.KindBook, "The Chaptered Fixture")
	for _, book := range []string{older, newer} {
		if _, err := f.svc.Checkpoint(ctx, f.uc, book, 5000, nil); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := f.svc.DeleteItems(ctx, f.uc, []string{newer}, "trash", false); err != nil {
		t.Fatal(err)
	}
	if got := subsonicBookmarkPIDs(t, ctx, f.svc, f.uc); len(got) != 1 || got[0] != older {
		t.Fatalf("bookmarks after trashing a book = %v, want [%s]", got, older)
	}
}

// A positioned book a tag rule denies is no bookmark for the account the
// rule binds, and still one for an account it does not.
func TestSubsonicBookmarksHonourContentRulesForBooks(t *testing.T) {
	t.Parallel()
	ctx, f := newMigrateFixture(t)
	book := f.itemPID(t, ctx, model.KindBook, "The Fixture Book")
	if _, err := f.svc.Checkpoint(ctx, f.uc, book, 5000, nil); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.SetItemTag(ctx, f.uc, book, "MOOD", []string{"calm"}, MetadataEditParams{}); err != nil {
		t.Fatal(err)
	}
	kid := &UserCtx{ID: f.uc.ID, CatalogPID: f.uc.CatalogPID, AllLibraries: true, Explicit: true,
		TagDeny: []TagRule{{Key: "MOOD", Value: "calm"}}}
	if got := subsonicBookmarkPIDs(t, ctx, f.svc, kid); len(got) != 0 {
		t.Errorf("the denied book is a bookmark for the restricted account: %v", got)
	}
	if got := subsonicBookmarkPIDs(t, ctx, f.svc, f.uc); len(got) != 1 || got[0] != book {
		t.Errorf("unrestricted bookmarks = %v, want [%s]", got, book)
	}
}
