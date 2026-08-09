package service

import (
	"context"
	"testing"
)

// trashItems deletes the named items to the trash, the state ADR-0048
// gave a deleted-but-restorable item.
func trashItems(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, pids ...string) {
	t.Helper()
	if _, err := svc.DeleteItems(ctx, uc, pids, "trash", false); err != nil {
		t.Fatalf("trashing %v: %v", pids, err)
	}
}

// smartPlaylist creates a smart playlist owned by uc and returns its
// API pid.
func smartPlaylist(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, name, visibility string, rule SmartRule) string {
	t.Helper()
	pl, err := svc.CreatePlaylist(ctx, uc, PlaylistCreate{
		Name: name, Kind: "smart", Visibility: visibility, Rule: &rule,
	})
	if err != nil {
		t.Fatalf("creating smart playlist: %v", err)
	}
	return pl.PID
}

// allMusic matches every music item; the fixture library is four music
// tracks, so it is "everything" with a field the rule engine accepts.
func allMusic() RuleNode {
	return RuleNode{Type: "condition", Field: "mediaType", Op: "is", Value: "music"}
}

func memberPIDs(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, plPID string) []string {
	t.Helper()
	var out []string
	cursor := ""
	for {
		page, err := svc.PlaylistItems(ctx, uc, plPID, cursor, 50)
		if err != nil {
			t.Fatalf("paging playlist members: %v", err)
		}
		for _, e := range page.Entries {
			out = append(out, e.Item.PID)
		}
		if page.Next == "" {
			return out
		}
		cursor = page.Next
	}
}

// TestSmartPlaylistLimitSurvivesTheArchivedFilter is the inversion
// PreviewRule's own comment exists to prevent: the rule's Limit used to
// be spent in SQL and the archived rows dropped in Go afterwards, so a
// list asking for three delivered two the moment one of its top three
// went to the trash. The editor, which evaluates the predicate inside
// the query, showed three the whole time.
func TestSmartPlaylistLimitSurvivesTheArchivedFilter(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, uc)
	if len(pids) < 4 {
		t.Fatalf("fixture has %d items, want 4", len(pids))
	}
	rule := SmartRule{
		Root:  allMusic(),
		Sorts: []RuleSort{{Field: "title"}},
		Limit: 3,
	}
	plPID := smartPlaylist(t, ctx, svc, uc, "Top Three", "private", rule)

	if got := memberPIDs(t, ctx, svc, uc, plPID); len(got) != 3 {
		t.Fatalf("members before the trash = %d, want 3", len(got))
	}
	first := memberPIDs(t, ctx, svc, uc, plPID)[0]
	trashItems(t, ctx, svc, uc, first)

	got := memberPIDs(t, ctx, svc, uc, plPID)
	if len(got) != 3 {
		t.Errorf("members after trashing one of the top three = %d, want 3", len(got))
	}
	for _, pid := range got {
		if pid == first {
			t.Errorf("the trashed member %s is still listed", pid)
		}
	}

	// The editor and the saved list have to agree, which is the whole
	// point: PreviewRule already evaluated the predicate inside the
	// query, so it was right and the listing was short.
	preview, err := svc.PreviewRule(ctx, uc, rule, 50)
	if err != nil {
		t.Fatalf("previewing rule: %v", err)
	}
	if len(preview.Items) != len(got) {
		t.Errorf("preview holds %d items, the saved listing %d", len(preview.Items), len(got))
	}

	// And the count the DTO reports is the same number the listing hands
	// back, rather than the rule's unfiltered match count.
	pl, err := svc.PlaylistByPID(ctx, uc, plPID)
	if err != nil {
		t.Fatalf("reading playlist: %v", err)
	}
	if pl.ItemCount == nil || *pl.ItemCount != len(got) {
		t.Errorf("reported itemCount = %v, listing holds %d", pl.ItemCount, len(got))
	}
}

// TestSmartPlaylistKeepsItsRuleSemantics pins what routing this through
// QueryPage would have broken. Its doc is explicit that "q's own
// sort/limit/offset/limit-mode are ignored; the canonical sort_key
// ordering owns the page", so a descending rule would have come back
// ascending and a budget rule would have returned everything.
func TestSmartPlaylistKeepsItsRuleSemantics(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)

	// An explicit descending sort is honoured rather than replaced by
	// the catalog's own page ordering.
	desc := smartPlaylist(t, ctx, svc, uc, "Z first", "private", SmartRule{
		Root:  allMusic(),
		Sorts: []RuleSort{{Field: "title", Desc: true}},
	})
	asc := smartPlaylist(t, ctx, svc, uc, "A first", "private", SmartRule{
		Root:  allMusic(),
		Sorts: []RuleSort{{Field: "title"}},
	})
	down := memberPIDs(t, ctx, svc, uc, desc)
	up := memberPIDs(t, ctx, svc, uc, asc)
	if len(down) != len(up) || len(down) == 0 {
		t.Fatalf("sorted lists hold %d and %d members", len(down), len(up))
	}
	for i := range up {
		if up[i] != down[len(down)-1-i] {
			t.Fatalf("descending rule did not reverse the ascending one:\n asc %v\ndesc %v", up, down)
		}
	}

	// A budget limit is a budget, not a row cap: "one minute of music"
	// over a library of two-to-four-second tracks takes every track,
	// while a count limit of 1 takes one.
	minutes := smartPlaylist(t, ctx, svc, uc, "A minute", "private", SmartRule{
		Root:      allMusic(),
		Sorts:     []RuleSort{{Field: "title"}},
		Limit:     1,
		LimitMode: "minutes",
	})
	if got := memberPIDs(t, ctx, svc, uc, minutes); len(got) != len(up) {
		t.Errorf("a one-minute budget over %d short tracks took %d of them", len(up), len(got))
	}

	// A seeded random draw is stable, which it would not be if the
	// rule's LimitSeed were dropped on the way to the query.
	seeded := smartPlaylist(t, ctx, svc, uc, "Shuffle", "private", SmartRule{
		Root:      allMusic(),
		Limit:     2,
		LimitMode: "random",
		LimitSeed: 4242,
	})
	first := memberPIDs(t, ctx, svc, uc, seeded)
	second := memberPIDs(t, ctx, svc, uc, seeded)
	if len(first) != 2 {
		t.Fatalf("seeded random draw took %d items, want 2", len(first))
	}
	if !samePIDs(first, second) {
		t.Errorf("a fixed seed drew %v then %v", first, second)
	}
}

func samePIDs(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

// TestSharedSmartPlaylistEvaluatesAsItsOwner is the contract
// PlaylistItems documents and the reason the member read passes
// pl.OwnerPID rather than copying PreviewRule's caller pid: a shared
// list holding a per-user predicate has to answer every reader with the
// owner's evaluation, or two accounts see two different playlists under
// one name. Invisible in any single-account test.
func TestSharedSmartPlaylistEvaluatesAsItsOwner(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, uc)

	// The owner stars one track, so `starred is true` names exactly one
	// item for them and nothing at all for anybody else.
	if _, err := svc.SetStar(ctx, uc, pids[0], true, nil); err != nil {
		t.Fatalf("starring: %v", err)
	}
	plPID := smartPlaylist(t, ctx, svc, uc, "What I starred", "shared", SmartRule{
		Root: RuleNode{Type: "all", Nodes: []RuleNode{
			allMusic(),
			{Type: "condition", Field: "starred", Op: "is", Value: "true"},
		}},
		Sorts: []RuleSort{{Field: "title"}},
	})
	mine := memberPIDs(t, ctx, svc, uc, plPID)
	if len(mine) != 1 || mine[0] != pids[0] {
		t.Fatalf("owner's own view of the list = %v, want [%s]", mine, pids[0])
	}

	acct, err := svc.CreateAccount(ctx, AccountCreate{Username: "reader", Password: "correct-horse"})
	if err != nil {
		t.Fatal(err)
	}
	other, err := svc.UserCtx(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	theirs := memberPIDs(t, ctx, svc, other, plPID)
	if !samePIDs(mine, theirs) {
		t.Errorf("a second reader sees %v, the owner %v", theirs, mine)
	}
	pl, err := svc.PlaylistByPID(ctx, other, plPID)
	if err != nil {
		t.Fatalf("second reader reading the playlist: %v", err)
	}
	if pl.ItemCount == nil || *pl.ItemCount != len(mine) {
		t.Errorf("second reader's itemCount = %v, want %d", pl.ItemCount, len(mine))
	}
}

// TestStaticPlaylistCountMatchesItsListing closes the asymmetry the
// smart branch never had: the static branch reported the catalog's
// stored member count, so a ten-member list with one member trashed
// answered 10 from the playlist and 9 from its items, indefinitely.
func TestStaticPlaylistCountMatchesItsListing(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, uc)[:4]
	plPID := playlistWith(t, ctx, svc, uc, "Road Trip", pids)

	pl, err := svc.PlaylistByPID(ctx, uc, plPID)
	if err != nil {
		t.Fatal(err)
	}
	if pl.ItemCount == nil || *pl.ItemCount != 4 {
		t.Fatalf("itemCount before the trash = %v, want 4", pl.ItemCount)
	}

	trashItems(t, ctx, svc, uc, pids[1])

	listed := memberPIDs(t, ctx, svc, uc, plPID)
	if len(listed) != 3 {
		t.Fatalf("listing holds %d members after trashing one, want 3", len(listed))
	}
	pl, err = svc.PlaylistByPID(ctx, uc, plPID)
	if err != nil {
		t.Fatal(err)
	}
	if pl.ItemCount == nil || *pl.ItemCount != 3 {
		t.Errorf("itemCount = %v while the listing holds 3", pl.ItemCount)
	}

	// The grid row is the surface a listener actually reads this off, and
	// it counts a static list too.
	if got := listedCount(t, ctx, svc, uc, plPID); got != 3 {
		t.Errorf("listing itemCount = %d, want 3", got)
	}
}

// listedCount reads one playlist's count off the listing page.
func listedCount(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, plPID string) int {
	t.Helper()
	page, err := svc.Playlists(ctx, uc, "", "", 50)
	if err != nil {
		t.Fatalf("listing playlists: %v", err)
	}
	for _, pl := range page.Playlists {
		if pl.PID != plPID {
			continue
		}
		if pl.ItemCount == nil {
			t.Fatalf("listing row for %s reports no count", plPID)
		}
		return *pl.ItemCount
	}
	t.Fatalf("playlist %s is missing from the listing", plPID)
	return 0
}

// TestListingCountIsCachedButTheOpenedPlaylistIsNot is the split the
// listing row and the opened playlist take.
//
// The listing rides the user-stream fan-out: every star, rating, and
// play-state checkpoint from any device re-runs the whole page, and none
// of those can change a static list's membership - so a row takes its
// count from a cache keyed on the playlist's own UpdatedAt. The opened
// playlist does not, because its count sits beside the member listing it
// has to agree with.
func TestListingCountIsCachedButTheOpenedPlaylistIsNot(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, uc)[:4]
	plPID := playlistWith(t, ctx, svc, uc, "Road Trip", pids)

	if got := listedCount(t, ctx, svc, uc, plPID); got != 4 {
		t.Fatalf("listing count = %d, want 4", got)
	}
	trashItems(t, ctx, svc, uc, pids[1])

	// The opened playlist is exact, and agrees with its own members.
	pl, err := svc.PlaylistByPID(ctx, uc, plPID)
	if err != nil {
		t.Fatal(err)
	}
	listed := memberPIDs(t, ctx, svc, uc, plPID)
	if pl.ItemCount == nil || *pl.ItemCount != len(listed) {
		t.Errorf("opened count = %v, member listing holds %d", pl.ItemCount, len(listed))
	}

	// An edit moves UpdatedAt, so the row catches up without waiting on
	// the TTL. A rename is the cheapest one that does not also have to
	// get past the replace guard, which refuses while a member is
	// trashed - that refusal is its own test above.
	renamed := "Road Trip II"
	if _, err := svc.UpdatePlaylist(ctx, uc, plPID, PlaylistUpdate{Name: &renamed}); err != nil {
		t.Fatalf("renaming: %v", err)
	}
	if got := listedCount(t, ctx, svc, uc, plPID); got != len(listed) {
		t.Errorf("listing count after an edit = %d, want %d", got, len(listed))
	}
}

// TestReplaceRefusesWhenAMemberIsTrashed is the third arm the guard was
// missing. A client PUTting back the listing it can see would otherwise
// store a member list with the trashed row silently dropped, and a
// restore would never re-add it - which contradicts PlaylistItems' own
// promise that positions are kept "so a restore lands where it was".
func TestReplaceRefusesWhenAMemberIsTrashed(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, uc)[:3]
	plPID := playlistWith(t, ctx, svc, uc, "Three", pids)

	trashItems(t, ctx, svc, uc, pids[1])
	visible := memberPIDs(t, ctx, svc, uc, plPID)
	if len(visible) != 2 {
		t.Fatalf("listing holds %d members, want 2", len(visible))
	}

	if err := svc.ReplacePlaylistItems(ctx, uc, plPID, visible, nil); KindOf(err) != KindConflict {
		t.Fatalf("replacing with the visible listing = %v, want a conflict", err)
	}

	// The refusal wrote nothing, so the hidden member is still stored and
	// a restore puts it back where it was.
	entries, err := svc.TrashEntries(ctx, uc, false, 50)
	if err != nil {
		t.Fatalf("listing trash: %v", err)
	}
	if len(entries) != 1 {
		t.Fatalf("trash holds %d entries, want 1", len(entries))
	}
	if err := svc.RestoreTrashEntry(ctx, uc, entries[0].ID); err != nil {
		t.Fatalf("restoring: %v", err)
	}
	if got := memberPIDs(t, ctx, svc, uc, plPID); !samePIDs(got, pids) {
		t.Errorf("after restoring, members = %v, want %v", got, pids)
	}
}
