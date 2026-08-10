package service

import (
	"context"
	"fmt"
	"strings"
	"testing"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
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

// TestListingCountIsLive replaces the memo that used to sit here.
//
// A listing row's count was cached on the playlist's UpdatedAt with a
// one-minute TTL, because counting meant hydrating every member and the
// user-stream fan-out re-runs the whole page on every star and
// checkpoint. Membership is a query dimension now, so a row is one
// indexed COUNT and can afford to be right: a trashed member leaves the
// row immediately rather than up to a TTL later.
func TestListingCountIsLive(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, uc)[:4]
	plPID := playlistWith(t, ctx, svc, uc, "Road Trip", pids)

	if got := listedCount(t, ctx, svc, uc, plPID); got != 4 {
		t.Fatalf("listing count = %d, want 4", got)
	}
	trashItems(t, ctx, svc, uc, pids[1])

	// No edit in between, so nothing moves UpdatedAt: the old cache key
	// would have held 4 here for the rest of the TTL.
	listed := memberPIDs(t, ctx, svc, uc, plPID)
	if got := listedCount(t, ctx, svc, uc, plPID); got != len(listed) {
		t.Errorf("listing count right after the trash = %d, member listing holds %d",
			got, len(listed))
	}
	pl, err := svc.PlaylistByPID(ctx, uc, plPID)
	if err != nil {
		t.Fatal(err)
	}
	if pl.ItemCount == nil || *pl.ItemCount != len(listed) {
		t.Errorf("opened count = %v, member listing holds %d", pl.ItemCount, len(listed))
	}
}

// TestStaticCountCountsEntriesNotItems pins the corner of the count
// triangle WaxDeck picked. A list holding one track twice reads it
// twice, because
// that is what its member listing hands back; the facet's distinct count
// would say 1 and disagree with the rows on screen.
func TestStaticCountCountsEntriesNotItems(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, uc)[:2]
	plPID := playlistWith(t, ctx, svc, uc, "Twice", []string{pids[0], pids[1], pids[0]})

	listed := memberPIDs(t, ctx, svc, uc, plPID)
	if len(listed) != 3 {
		t.Fatalf("member listing holds %d entries, want 3", len(listed))
	}
	if got := listedCount(t, ctx, svc, uc, plPID); got != 3 {
		t.Errorf("listing count = %d, want the 3 entries the listing shows", got)
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

// TestStaticCountIsScopedToTheCallersGrants pins the second clause of
// the narrow. The count is a query now, so the library scoping that was
// a per-item check has to be in the query too, or a restricted reader
// gets the owner's number beside their own shorter listing.
func TestStaticCountIsScopedToTheCallersGrants(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, uc)[:3]
	plPID := playlistWith(t, ctx, svc, uc, "Everything", pids)

	elsewhere, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "other", Path: t.TempDir()})
	if err != nil {
		t.Fatalf("adding a second library: %v", err)
	}
	// Granted a library that holds none of the members: every member is
	// filtered, so the count is zero rather than three.
	blind := &UserCtx{
		ID: uc.ID, CatalogPID: uc.CatalogPID,
		Libraries: map[string]bool{strings.TrimPrefix(elsewhere.PID, PrefixLibrary+"-"): true},
	}
	pl, err := svc.PlaylistByPID(ctx, blind, plPID)
	if err != nil {
		t.Fatalf("restricted reader reading the playlist: %v", err)
	}
	listed := memberPIDs(t, ctx, svc, blind, plPID)
	if pl.ItemCount == nil || *pl.ItemCount != len(listed) {
		t.Errorf("restricted count = %v, their member listing holds %d", pl.ItemCount, len(listed))
	}
	if len(listed) != 0 {
		t.Errorf("a reader granted only an empty library sees %d members", len(listed))
	}

	// And a caller with no grant at all counts nothing: an empty allow
	// list compiles to 1=0 rather than to "no filter".
	none := &UserCtx{ID: uc.ID, CatalogPID: uc.CatalogPID}
	pl, err = svc.PlaylistByPID(ctx, none, plPID)
	if err != nil {
		t.Fatalf("ungranted reader reading the playlist: %v", err)
	}
	if pl.ItemCount == nil || *pl.ItemCount != 0 {
		t.Errorf("ungranted count = %v, want 0", pl.ItemCount)
	}
}

// TestSharedStaticCountIsTheViewersNotTheOwners is the cross-user
// contract the userPID argument makes easy to get wrong. CountItems
// takes the list's owner, because a static list's membership is the
// owner's; what the caller is *offered* out of that membership is the
// narrow's job, and it is built from the caller. Two readers of one
// shared list therefore get two counts, each matching their own listing.
func TestSharedStaticCountIsTheViewersNotTheOwners(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, uc)[:3]

	pl, err := svc.CreatePlaylist(ctx, uc, PlaylistCreate{
		Name: "Shared", Kind: "static", Visibility: "shared", ItemPIDs: pids,
	})
	if err != nil {
		t.Fatalf("creating the shared list: %v", err)
	}
	if pl.ItemCount == nil || *pl.ItemCount != 3 {
		t.Fatalf("owner's count = %v, want 3", pl.ItemCount)
	}

	acct, err := svc.CreateAccount(ctx, AccountCreate{Username: "reader", Password: "correct-horse"})
	if err != nil {
		t.Fatal(err)
	}
	other, err := svc.UserCtx(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	// Same list, a reader granted a library that holds nothing of it.
	elsewhere, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "other", Path: t.TempDir()})
	if err != nil {
		t.Fatalf("adding a second library: %v", err)
	}
	other.AllLibraries = false
	other.Libraries = map[string]bool{strings.TrimPrefix(elsewhere.PID, PrefixLibrary+"-"): true}

	theirs, err := svc.PlaylistByPID(ctx, other, pl.PID)
	if err != nil {
		t.Fatalf("second reader reading the shared list: %v", err)
	}
	if theirs.ItemCount == nil || *theirs.ItemCount != 0 {
		t.Errorf("second reader's count = %v, want 0 - they can see none of it", theirs.ItemCount)
	}
	mine, err := svc.PlaylistByPID(ctx, uc, pl.PID)
	if err != nil {
		t.Fatal(err)
	}
	if mine.ItemCount == nil || *mine.ItemCount != 3 {
		t.Errorf("owner's count after the other reader = %v, want 3", mine.ItemCount)
	}
}

// TestPlaylistRuleField drives the `playlist` rule field end to end:
// the vocabulary offers it, a pid round-trips through the engine and
// back as a pid, and "not in that list" actually excludes its members.
//
// The exclusions are as load-bearing as the inclusion. `contains` would
// be a substring match against a pid; `isPresent` would ask "in any
// playlist", which reaches across every other account's private lists.
func TestPlaylistRuleField(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, uc)
	archive := playlistWith(t, ctx, svc, uc, "Archive", pids[:2])

	vocab, err := svc.RuleVocabulary(ctx)
	if err != nil {
		t.Fatal(err)
	}
	var spec *RuleFieldInfo
	for i := range vocab.Fields {
		if vocab.Fields[i].Name == "playlist" {
			spec = &vocab.Fields[i]
		}
	}
	if spec == nil {
		t.Fatal("the vocabulary does not offer a playlist field")
	}
	if spec.Kind != ruleKindPlaylist || spec.Sortable {
		t.Errorf("playlist field = %+v, want an unsortable playlist kind", *spec)
	}
	if len(spec.Ops) != 2 || spec.Ops[0] != "is" || spec.Ops[1] != "isNot" {
		t.Errorf("playlist ops = %v, want is/isNot only", spec.Ops)
	}

	// "Everything that is not in the Archive list."
	notArchived := SmartRule{
		Root: RuleNode{Type: "all", Nodes: []RuleNode{
			allMusic(),
			{Type: "condition", Field: "playlist", Op: "isNot", Value: archive},
		}},
		Sorts: []RuleSort{{Field: "title"}},
	}
	rest := smartPlaylist(t, ctx, svc, uc, "The rest", "private", notArchived)
	got := memberPIDs(t, ctx, svc, uc, rest)
	if len(got) != len(pids)-2 {
		t.Fatalf("isNot over a 2-member list took %d of %d items", len(got), len(pids))
	}
	for _, pid := range got {
		if pid == pids[0] || pid == pids[1] {
			t.Errorf("member %s of the Archive list survived isNot", pid)
		}
	}

	// And the inverse names exactly the two.
	inside := smartPlaylist(t, ctx, svc, uc, "The archive, again", "private", SmartRule{
		Root:  RuleNode{Type: "condition", Field: "playlist", Op: "is", Value: archive},
		Sorts: []RuleSort{{Field: "title"}},
	})
	if got := memberPIDs(t, ctx, svc, uc, inside); len(got) != 2 {
		t.Errorf("`is` over a 2-member list took %d items", len(got))
	}

	// The stored rule reads back as the API pid it was written with, not
	// as the bare engine value.
	pl, err := svc.PlaylistByPID(ctx, uc, inside)
	if err != nil {
		t.Fatal(err)
	}
	if pl.Rule == nil || pl.Rule.Root.Value != archive {
		t.Errorf("round-tripped value = %v, want %s", pl.Rule, archive)
	}

	// A pid naming a list that is smart, or gone, is syntactically fine
	// and simply matches nothing.
	empty := smartPlaylist(t, ctx, svc, uc, "Nothing", "private", SmartRule{
		Root: RuleNode{Type: "condition", Field: "playlist", Op: "is", Value: rest},
	})
	if got := memberPIDs(t, ctx, svc, uc, empty); len(got) != 0 {
		t.Errorf("a smart target matched %d items, want none", len(got))
	}

	// Refusals: an operator the field does not offer, and a value that
	// is not a playlist pid.
	_, err = svc.CreatePlaylist(ctx, uc, PlaylistCreate{
		Name: "Bad op", Kind: "smart", Visibility: "private",
		Rule: &SmartRule{Root: RuleNode{
			Type: "condition", Field: "playlist", Op: "contains", Value: archive,
		}},
	})
	if KindOf(err) != KindInvalid {
		t.Errorf("`contains` on a playlist field = %v, want invalid", err)
	}
	_, err = svc.CreatePlaylist(ctx, uc, PlaylistCreate{
		Name: "Bad value", Kind: "smart", Visibility: "private",
		Rule: &SmartRule{Root: RuleNode{
			Type: "condition", Field: "playlist", Op: "is", Value: "tr-nonsense",
		}},
	})
	if KindOf(err) != KindInvalid {
		t.Errorf("a track pid as a playlist value = %v, want invalid", err)
	}
}

// TestStaticCountCompilesPastTheValueCap pins the chunking in inSet:
// the engine caps one set-membership condition at 500 values, so a
// caller following more shows than that has to compile as an Or of
// chunks. Before the chunking, this count failed to compile and every
// static ItemCount read back null for that caller, silently.
func TestStaticCountCompilesPastTheValueCap(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, uc)[:2]
	plPID := playlistWith(t, ctx, svc, uc, "Wide Follows", pids)

	shows := make([]string, 1001)
	for i := range shows {
		shows[i] = fmt.Sprintf("show-%04d", i)
	}
	narrow := query.And{Nodes: []query.Node{
		query.Cond{Field: "state", Op: query.OpIsNot, Value: string(model.StateArchived)},
		query.Or{Nodes: []query.Node{
			query.Cond{Field: "kind", Op: query.OpIsNot, Value: string(model.KindEpisode)},
			inSet("podcast_pid", shows),
		}},
	}}
	_, catalogPID, ok := parseAPIPID(plPID)
	if !ok {
		t.Fatalf("parsing %s", plPID)
	}
	pl, err := svc.lib.Playlists().Get(ctx, catalogPID)
	if err != nil {
		t.Fatal(err)
	}
	n, err := svc.lib.Playlists().CountItems(ctx, pl.PID, pl.OwnerPID, narrow)
	if err != nil {
		t.Fatalf("counting past the value cap: %v", err)
	}
	if n != 2 {
		t.Errorf("count = %d, want 2", n)
	}
}

// TestInSetChunksAtTheCap is the node shape itself: one condition up to
// the cap, an Or of capped chunks above it, and an empty set staying
// one empty membership, which compiles to match-nothing.
func TestInSetChunksAtTheCap(t *testing.T) {
	t.Parallel()
	if _, ok := inSet("library", make([]string, 500)).(query.Cond); !ok {
		t.Error("500 values should stay a single condition")
	}
	node, ok := inSet("library", make([]string, 1001)).(query.Or)
	if !ok {
		t.Fatal("1001 values should chunk into an Or")
	}
	if len(node.Nodes) != 3 {
		t.Fatalf("1001 values chunked into %d conditions, want 3", len(node.Nodes))
	}
	sizes := 0
	for _, n := range node.Nodes {
		c, ok := n.(query.Cond)
		if !ok {
			t.Fatalf("chunk is %T, want a condition", n)
		}
		if len(c.Values) > 500 {
			t.Errorf("chunk holds %d values, over the cap", len(c.Values))
		}
		sizes += len(c.Values)
	}
	if sizes != 1001 {
		t.Errorf("chunks hold %d values in total, want 1001", sizes)
	}
	if c, ok := inSet("library", nil).(query.Cond); !ok || len(c.Values) != 0 {
		t.Error("an empty set should stay one empty membership condition")
	}
}
