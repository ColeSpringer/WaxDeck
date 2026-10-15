package service

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"

	"github.com/colespringer/waxdeck/fixtures"
)

// trashItems deletes the named items to the trash, the state of a
// deleted-but-restorable item.
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

// genreTrackPIDs answers the API pids of the genre fixture's tracks with
// these titles, in order.
func genreTrackPIDs(t *testing.T, f genreFixture, titles ...string) []string {
	t.Helper()
	out := make([]string, 0, len(titles))
	for _, title := range titles {
		out = append(out, apiPID(PrefixTrack, f.itemNamed(t, title).PID))
	}
	return out
}

// A shared list's listing and count apply the reader's content rules as
// well as their grants: a tag-denied track another account listed shows
// neither its title nor in the count.
func TestSharedListHidesTagDeniedMembers(t *testing.T) {
	t.Parallel()
	f := newGenreFixture(t)
	f.tag(t, "Canonical", "MOOD", "calm")
	pids := genreTrackPIDs(t, f, "Lowercase", "Canonical", "Off Tree")
	pl, err := f.svc.CreatePlaylist(f.ctx, f.uc, PlaylistCreate{
		Name: "Mixed", Kind: "static", Visibility: "shared", ItemPIDs: pids,
	})
	if err != nil {
		t.Fatalf("creating the shared list: %v", err)
	}

	kid := f.restricted(nil, []TagRule{{Key: "MOOD", Value: "calm"}})
	want := []string{pids[0], pids[2]}
	if got := memberPIDs(t, f.ctx, f.svc, kid, pl.PID); !samePIDs(got, want) {
		t.Errorf("restricted reader lists %v, want %v", got, want)
	}
	opened, err := f.svc.PlaylistByPID(f.ctx, kid, pl.PID)
	if err != nil {
		t.Fatal(err)
	}
	if opened.ItemCount == nil || *opened.ItemCount != 2 {
		t.Errorf("restricted reader's count = %v, want 2", opened.ItemCount)
	}
	if got := listedCount(t, f.ctx, f.svc, kid, pl.PID); got != 2 {
		t.Errorf("restricted reader's listing count = %d, want 2", got)
	}

	if got := memberPIDs(t, f.ctx, f.svc, f.uc, pl.PID); !samePIDs(got, pids) {
		t.Errorf("owner lists %v, want every member %v", got, pids)
	}
}

// TestReplaceRefusesWhenAMemberIsContentHidden is the guard's fourth
// arm: a reorder built from a listing the owner's content rules have
// narrowed would drop the hidden members for good.
func TestReplaceRefusesWhenAMemberIsContentHidden(t *testing.T) {
	t.Parallel()
	f := newGenreFixture(t)
	f.tag(t, "Canonical", "MOOD", "calm")
	pids := genreTrackPIDs(t, f, "Lowercase", "Canonical", "Off Tree")
	plPID := playlistWith(t, f.ctx, f.svc, f.uc, "Mine", pids)

	kid := f.restricted(nil, []TagRule{{Key: "MOOD", Value: "calm"}})
	visible := memberPIDs(t, f.ctx, f.svc, kid, plPID)
	if err := f.svc.ReplacePlaylistItems(f.ctx, kid, plPID, visible, nil); KindOf(err) != KindConflict {
		t.Fatalf("replacing with the narrowed listing = %v, want a conflict", err)
	}
	if got := memberPIDs(t, f.ctx, f.svc, f.uc, plPID); !samePIDs(got, pids) {
		t.Errorf("after the refusal, members = %v, want %v", got, pids)
	}
}

// TestContainsItemDoesNotProbeAHiddenItem: the add-to-playlist filter
// read stored members directly, so naming a pid the caller cannot see
// told them which lists hold it.
func TestContainsItemDoesNotProbeAHiddenItem(t *testing.T) {
	t.Parallel()
	f := newGenreFixture(t)
	f.tag(t, "Canonical", "MOOD", "calm")
	pids := genreTrackPIDs(t, f, "Lowercase", "Canonical")
	if _, err := f.svc.CreatePlaylist(f.ctx, f.uc, PlaylistCreate{
		Name: "Mixed", Kind: "static", Visibility: "shared", ItemPIDs: pids,
	}); err != nil {
		t.Fatal(err)
	}
	holding := func(uc *UserCtx, item string) int {
		t.Helper()
		page, err := f.svc.Playlists(f.ctx, uc, item, "", 50)
		if err != nil {
			t.Fatalf("filtering by %s: %v", item, err)
		}
		return len(page.Playlists)
	}
	if got := holding(f.uc, pids[1]); got != 1 {
		t.Fatalf("owner sees %d lists holding the track, want 1", got)
	}
	kid := f.restricted(nil, []TagRule{{Key: "MOOD", Value: "calm"}})
	if got := holding(kid, pids[1]); got != 0 {
		t.Errorf("a reader the track is hidden from sees %d lists holding it, want 0", got)
	}
	if got := holding(kid, pids[0]); got != 1 {
		t.Errorf("the same reader sees %d lists holding a track they can see, want 1", got)
	}
}

// blindReader is the fixture's admin re-scoped to a fresh, empty library:
// every fixture track is outside their grant.
func blindReader(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx) *UserCtx {
	t.Helper()
	elsewhere, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "other", Path: t.TempDir()})
	if err != nil {
		t.Fatalf("adding a second library: %v", err)
	}
	return &UserCtx{
		ID: uc.ID, CatalogPID: uc.CatalogPID,
		Libraries: map[string]bool{strings.TrimPrefix(elsewhere.PID, PrefixLibrary+"-"): true},
	}
}

// The resolver matches across the whole catalog, so an import drops
// every match its caller cannot read rather than store it for a share to
// publish.
func TestImportDropsWhatTheCallerCannotSee(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	blind := blindReader(t, ctx, svc, uc)

	text := PlaylistImportInput{Source: "text", Name: "Road Tape", Payload: "Test Ensemble - Amber Waves\n"}
	out, err := svc.ImportStreamingPlaylist(ctx, blind, text)
	if err != nil {
		t.Fatal(err)
	}
	if out.Resolved != 0 || len(out.Missing) != 1 || out.PlaylistPID != "" {
		t.Errorf("restricted text import = %+v, want one miss and no playlist", out)
	}
	if out, err = svc.ImportStreamingPlaylist(ctx, uc, text); err != nil || out.Resolved != 1 {
		t.Errorf("unrestricted text import = %+v (%v), want the track resolved", out, err)
	}

	// Portable refs resolve on the strong rungs, which a hidden match
	// cannot pass either.
	pids := fixtureItemPIDs(t, ctx, svc, uc)[:2]
	_, refs, err := svc.ExportPlaylistPortable(ctx, uc, playlistWith(t, ctx, svc, uc, "Source", pids))
	if err != nil {
		t.Fatal(err)
	}
	out, err = svc.ImportStreamingPlaylist(ctx, blind, PlaylistImportInput{Source: "portable", Refs: refs})
	if err != nil {
		t.Fatal(err)
	}
	if out.Resolved != 0 || len(out.Missing) != 2 {
		t.Errorf("restricted portable import = %+v, want both refs missing", out)
	}
}

// TestImportM3UDropsUnreachablePaths: a path naming an item the caller
// cannot see reads as unmatched, and so does a line merged into it.
func TestImportM3UDropsUnreachablePaths(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	blind := blindReader(t, ctx, svc, uc)
	track := fixtureItemPIDs(t, ctx, svc, uc)[0]
	it, err := svc.getVisibleItem(ctx, uc, track)
	if err != nil {
		t.Fatal(err)
	}
	// The absolute path, then the same file by a relative suffix: one
	// item through two spellings, which the import merges into one entry.
	paths := []string{it.DisplayPath, filepath.Base(it.DisplayPath)}
	doc := "#EXTM3U\n" + strings.Join(paths, "\n") + "\n"

	mine, err := svc.ImportPlaylistM3U(ctx, uc, "Mine", "", doc)
	if err != nil {
		t.Fatal(err)
	}
	if mine.Matched != 1 || mine.Unmatched != 0 {
		t.Fatalf("unrestricted import = matched %d unmatched %d, want 1/0", mine.Matched, mine.Unmatched)
	}
	if got := memberPIDs(t, ctx, svc, uc, mine.Playlist.PID); !samePIDs(got, []string{track}) {
		t.Errorf("unrestricted members = %v, want %v", got, []string{track})
	}

	theirs, err := svc.ImportPlaylistM3U(ctx, blind, "Theirs", "", doc)
	if err != nil {
		t.Fatal(err)
	}
	if theirs.Matched != 0 || theirs.Unmatched != 2 || !samePIDs(theirs.UnmatchedPaths, paths) {
		t.Errorf("restricted import = matched %d unmatched %d %v, want 0/2 %v",
			theirs.Matched, theirs.Unmatched, theirs.UnmatchedPaths, paths)
	}
	if got := memberPIDs(t, ctx, svc, uc, theirs.Playlist.PID); len(got) != 0 {
		t.Errorf("the restricted import stored %v", got)
	}
}

// Both exports write only what the reader is shown: a restricted reader
// of somebody else's shared list gets no path or identity of a track the
// listing hides from them.
func TestSharedListExportsOnlyTheViewersMembers(t *testing.T) {
	t.Parallel()
	f := newGenreFixture(t)
	f.tag(t, "Canonical", "MOOD", "calm")
	hidden := f.itemNamed(t, "Canonical")
	pids := genreTrackPIDs(t, f, "Lowercase", "Canonical", "Off Tree")
	pl, err := f.svc.CreatePlaylist(f.ctx, f.uc, PlaylistCreate{
		Name: "Mixed", Kind: "static", Visibility: "shared", ItemPIDs: pids,
	})
	if err != nil {
		t.Fatal(err)
	}
	kid := f.calmDenied()

	doc, err := f.svc.ExportPlaylistM3U(f.ctx, kid, pl.PID)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(doc, hidden.DisplayPath) || strings.Contains(doc, "Canonical") {
		t.Errorf("the restricted export names the hidden member:\n%s", doc)
	}
	if n := strings.Count(doc, "#EXTINF:"); n != 2 {
		t.Errorf("the restricted export holds %d entries, want 2:\n%s", n, doc)
	}
	_, refs, err := f.svc.ExportPlaylistPortable(f.ctx, kid, pl.PID)
	if err != nil {
		t.Fatal(err)
	}
	if len(refs) != 2 {
		t.Errorf("the restricted portable export holds %d refs, want 2", len(refs))
	}
	for _, r := range refs {
		if r.Title == "Canonical" {
			t.Errorf("the restricted portable export carries the hidden member: %+v", r)
		}
	}

	// The owner's export is the catalog's own document, byte for byte:
	// the importer's label pick reads that format back.
	mine, err := f.svc.ExportPlaylistM3U(f.ctx, f.uc, pl.PID)
	if err != nil {
		t.Fatal(err)
	}
	_, bare, _ := parseAPIPID(pl.PID)
	var want bytes.Buffer
	if err := f.svc.lib.Playlists().ExportM3U8(f.ctx, bare, &want, model.PID(f.uc.CatalogPID)); err != nil {
		t.Fatal(err)
	}
	if mine != want.String() {
		t.Errorf("owner export =\n%s\nwant the catalog's\n%s", mine, want.String())
	}
	if _, refs, err := f.svc.ExportPlaylistPortable(f.ctx, f.uc, pl.PID); err != nil || len(refs) != 3 {
		t.Errorf("owner portable export = %d refs (%v), want 3", len(refs), err)
	}
}

// A random smart list with no pinned seed draws a new order on every
// read, so its portable export cannot be checked against a second read;
// it still exports, and still only what the reader can see.
func TestShuffledSmartListExportsPortably(t *testing.T) {
	t.Parallel()
	f := newGenreFixture(t)
	f.tag(t, "Canonical", "MOOD", "calm")
	pl := smartPlaylist(t, f.ctx, f.svc, f.uc, "Shuffle", "shared", SmartRule{
		Root: allMusic(), Limit: len(genreFixtureTitles), LimitMode: "random",
	})
	titles := func(refs []PortableRefDTO) []string {
		out := make([]string, len(refs))
		for i, r := range refs {
			out[i] = r.Title
		}
		slices.Sort(out)
		return out
	}
	everything := slices.Sorted(slices.Values(genreFixtureTitles))
	for range 3 {
		_, refs, err := f.svc.ExportPlaylistPortable(f.ctx, f.uc, pl)
		if err != nil {
			t.Fatalf("owner export: %v", err)
		}
		if got := titles(refs); !slices.Equal(got, everything) {
			t.Errorf("owner export = %v, want %v", got, everything)
		}
	}
	_, refs, err := f.svc.ExportPlaylistPortable(f.ctx, f.calmDenied(), pl)
	if err != nil {
		t.Fatalf("restricted export: %v", err)
	}
	want := slices.DeleteFunc(slices.Clone(everything), func(s string) bool { return s == "Canonical" })
	if got := titles(refs); !slices.Equal(got, want) {
		t.Errorf("restricted export = %v, want %v", got, want)
	}
}

// shareOwner creates a plain account and returns its id and context.
func shareOwner(t *testing.T, ctx context.Context, svc *Library, name string) (string, *UserCtx) {
	t.Helper()
	acct, err := svc.CreateAccount(ctx, AccountCreate{Username: name, Password: "correct-horse"})
	if err != nil {
		t.Fatal(err)
	}
	uc, err := svc.UserCtx(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	return acct.User.ID, uc
}

// resolvedShare resolves a share by its API pid, answering how many
// items it serves, or -1 when it does not resolve.
func resolvedShare(t *testing.T, ctx context.Context, svc *Library, apiShareID string) int {
	t.Helper()
	_, id, _ := parseAPIPID(apiShareID)
	pub, err := svc.ResolveShare(ctx, string(id))
	if KindOf(err) == KindNotFound {
		return -1
	}
	if err != nil {
		t.Fatalf("resolving %s: %v", apiShareID, err)
	}
	return len(pub.Items)
}

// A link serves what its owner can see each time it is opened: what a
// list held when its owner lost access stops playing to anyone holding
// the URL.
func TestResolveShareServesTheOwnersCurrentReach(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, admin)[:2]
	ownerID, owner := shareOwner(t, ctx, svc, "publisher")

	pl, err := svc.CreatePlaylist(ctx, owner, PlaylistCreate{Name: "Out", Kind: "static", ItemPIDs: pids})
	if err != nil {
		t.Fatal(err)
	}
	album, err := svc.getVisibleItem(ctx, admin, pids[0])
	if err != nil {
		t.Fatal(err)
	}
	var shares []string
	for _, target := range []string{pl.PID, apiPID(PrefixAlbum, album.AlbumPID), pids[1]} {
		info, err := svc.CreateShare(ctx, owner, target, 0, false, 0)
		if err != nil {
			t.Fatalf("sharing %s: %v", target, err)
		}
		if resolvedShare(t, ctx, svc, info.ID) <= 0 {
			t.Fatalf("the fresh share of %s serves nothing", target)
		}
		shares = append(shares, info.ID)
	}

	elsewhere, err := svc.AddLibrary(ctx, admin, AddLibraryInput{Name: "other", Path: t.TempDir()})
	if err != nil {
		t.Fatal(err)
	}
	granted := "granted"
	if _, err := svc.UpdateAccount(ctx, ownerID, AccountUpdate{AccessMode: &granted, LibraryPIDs: []string{elsewhere.PID}}); err != nil {
		t.Fatal(err)
	}
	for _, id := range shares {
		if n := resolvedShare(t, ctx, svc, id); n != -1 {
			t.Errorf("share %s serves %d items to an owner who lost the library, want not-found", id, n)
		}
	}

	all := "all"
	if _, err := svc.UpdateAccount(ctx, ownerID, AccountUpdate{AccessMode: &all}); err != nil {
		t.Fatal(err)
	}
	if n := resolvedShare(t, ctx, svc, shares[0]); n != 2 {
		t.Errorf("the playlist share after the grant came back serves %d, want 2", n)
	}
	off, on := true, false
	if _, err := svc.UpdateAccount(ctx, ownerID, AccountUpdate{Disabled: &off}); err != nil {
		t.Fatal(err)
	}
	for _, id := range shares {
		if n := resolvedShare(t, ctx, svc, id); n != -1 {
			t.Errorf("share %s of a disabled owner serves %d items, want not-found", id, n)
		}
	}
	if _, err := svc.UpdateAccount(ctx, ownerID, AccountUpdate{Disabled: &on}); err != nil {
		t.Fatal(err)
	}
	if n := resolvedShare(t, ctx, svc, shares[2]); n != 1 {
		t.Errorf("the track share after re-enabling serves %d, want 1", n)
	}
}

// TestResolveShareHidesWhatTheOwnersRulesDeny: a tag rule added after a
// link was minted narrows what it serves, and a target it hides
// entirely stops resolving.
func TestResolveShareHidesWhatTheOwnersRulesDeny(t *testing.T) {
	t.Parallel()
	f := newGenreFixture(t)
	pids := genreTrackPIDs(t, f, "Lowercase", "Canonical")
	ownerID, owner := shareOwner(t, f.ctx, f.svc, "publisher")
	pl, err := f.svc.CreatePlaylist(f.ctx, owner, PlaylistCreate{Name: "Out", Kind: "static", ItemPIDs: pids})
	if err != nil {
		t.Fatal(err)
	}
	list, err := f.svc.CreateShare(f.ctx, owner, pl.PID, 0, false, 0)
	if err != nil {
		t.Fatal(err)
	}
	track, err := f.svc.CreateShare(f.ctx, owner, pids[1], 0, false, 0)
	if err != nil {
		t.Fatal(err)
	}

	f.tag(t, "Canonical", "MOOD", "calm")
	perms := DefaultPermissions()
	perms.TagDeny = []TagRule{{Key: "MOOD", Value: "calm"}}
	if _, err := f.svc.UpdateAccount(f.ctx, ownerID, AccountUpdate{Permissions: &perms}); err != nil {
		t.Fatal(err)
	}
	if n := resolvedShare(t, f.ctx, f.svc, list.ID); n != 1 {
		t.Errorf("the list share serves %d items, want the one the owner may still hear", n)
	}
	if n := resolvedShare(t, f.ctx, f.svc, track.ID); n != -1 {
		t.Errorf("the denied track's share serves %d items, want not-found", n)
	}
}

// TestPreviewTotalCountsOnlyWhatTheCallerCanSee: the preview counted a
// rule over the whole catalog, so a restricted caller read how many
// tracks matched `path contains ...` in libraries and under tag rules
// that hid them, and the page beside it listed tag-denied titles.
func TestPreviewTotalCountsOnlyWhatTheCallerCanSee(t *testing.T) {
	t.Parallel()
	f := newGenreFixture(t)
	f.tag(t, "Canonical", "MOOD", "calm")
	rule := SmartRule{Root: allMusic()}

	mine, err := f.svc.PreviewRule(f.ctx, f.uc, rule, 50)
	if err != nil {
		t.Fatal(err)
	}
	if mine.Total != 5 || len(mine.Items) != 5 {
		t.Fatalf("unrestricted preview = %d of %d, want 5 of 5", len(mine.Items), mine.Total)
	}
	theirs, err := f.svc.PreviewRule(f.ctx, f.calmDenied(), rule, 50)
	if err != nil {
		t.Fatal(err)
	}
	if theirs.Total != 4 || len(theirs.Items) != 4 {
		t.Errorf("restricted preview = %d of %d, want 4 of 4", len(theirs.Items), theirs.Total)
	}
	for _, it := range theirs.Items {
		if it.Title == "Canonical" {
			t.Errorf("the restricted preview lists the denied track")
		}
	}
	blind, err := f.svc.PreviewRule(f.ctx, blindReader(t, f.ctx, f.svc, f.uc), rule, 50)
	if err != nil {
		t.Fatal(err)
	}
	if blind.Total != 0 || len(blind.Items) != 0 {
		t.Errorf("a reader granted nothing previews %d of %d, want nothing", len(blind.Items), blind.Total)
	}
}

// TestUploadDuplicateNamesOnlyWhatTheUploaderCanSee: the duplicate
// warning copied the existing item's title and artist to whoever
// uploaded matching bytes, so an uploader confined to one library learned
// what the others hold.
func TestUploadDuplicateNamesOnlyWhatTheUploaderCanSee(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	it, err := svc.getVisibleItem(ctx, uc, fixtureItemPIDs(t, ctx, svc, uc)[0])
	if err != nil {
		t.Fatal(err)
	}
	raw, err := os.ReadFile(it.DisplayPath)
	if err != nil {
		t.Fatal(err)
	}
	sum := sha256.Sum256(raw)
	params := UploadCreateParams{
		FileName: "again.flac", SizeBytes: int64(len(raw)), MediaType: "music",
		SHA256: hex.EncodeToString(sum[:]),
	}

	mine, err := svc.CreateUpload(ctx, uc, params)
	if err != nil {
		t.Fatal(err)
	}
	if mine.Duplicate == nil || mine.Duplicate.Title != it.Title {
		t.Fatalf("the administrator's warning = %+v, want it to name %q", mine.Duplicate, it.Title)
	}
	blind := blindReader(t, ctx, svc, uc)
	blind.UploadEnabled = true
	theirs, err := svc.CreateUpload(ctx, blind, params)
	if err != nil {
		t.Fatal(err)
	}
	if theirs.Duplicate == nil || theirs.Duplicate.Kind != "content" {
		t.Fatalf("the restricted uploader's warning = %+v, want the content warning kept", theirs.Duplicate)
	}
	if theirs.Duplicate.Title != "" || theirs.Duplicate.Artist != "" {
		t.Errorf("the restricted uploader's warning names the hidden item: %+v", theirs.Duplicate)
	}
}

// A sync run's write backs off when the list changed since the run read
// it: the edit made in between wins, and the run is retried later.
func TestSyncedMembersBackOffAnEditMadeSinceTheRead(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, uc)
	created, err := svc.CreatePlaylist(ctx, uc, PlaylistCreate{Name: "Synced", Kind: "static", ItemPIDs: pids[:1]})
	if err != nil {
		t.Fatal(err)
	}
	_, bare, _ := parseAPIPID(created.PID)
	read, err := svc.lib.Playlists().Get(ctx, bare)
	if err != nil {
		t.Fatal(err)
	}
	if err := svc.AddPlaylistItems(ctx, uc, created.PID, pids[1:2]); err != nil {
		t.Fatal(err)
	}
	_, other, _ := parseAPIPID(pids[2])
	if err := svc.setSyncedMembers(ctx, uc, read, []model.PID{other}); KindOf(err) != KindConflict {
		t.Errorf("a run writing over an edit made since its read = %v, want a conflict", err)
	}
	if got := memberPIDs(t, ctx, svc, uc, created.PID); !slices.Equal(got, pids[:2]) {
		t.Errorf("members = %v, want the edit's %v", got, pids[:2])
	}
}

// The portable export pairs the catalog's ref export with a member read,
// and the pairing must not slip when the list changes between the two:
// with two members a reader cannot tell apart by kind, title and length,
// one of them hidden from that reader, an edit racing the export may make
// it refuse, and must never hand out the hidden one's ref.
func TestPortableExportNeverPairsAcrossAnEdit(t *testing.T) {
	t.Parallel()
	f := newGenreFixture(t)
	twin := func(name, artist string) fixtures.Spec {
		s := genreTrack(name, "Twin", "Jazz", 3*time.Second)
		s.Tags["ARTIST"] = artist
		return s
	}
	if _, err := fixtures.Generate(f.libDir, twin("twin-seen", "Seen Twin"), twin("twin-hidden", "Hidden Twin")); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.lib.Scan(f.ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	byArtist := map[string]string{}
	page, err := f.svc.Items(f.ctx, f.uc, ItemFilter{}, "", 100)
	if err != nil {
		t.Fatal(err)
	}
	for _, row := range page.Items {
		if row.Title == "Twin" {
			byArtist[row.Artist] = row.PID
		}
	}
	seen, hidden := byArtist["Seen Twin"], byArtist["Hidden Twin"]
	if seen == "" || hidden == "" {
		t.Fatalf("twins = %v", byArtist)
	}
	if _, err := f.svc.SetItemTag(f.ctx, f.uc, hidden, "MOOD", []string{"calm"}, MetadataEditParams{Lock: false, Force: false}); err != nil {
		t.Fatal(err)
	}
	pl, err := f.svc.CreatePlaylist(f.ctx, f.uc, PlaylistCreate{
		Name: "Twins", Kind: "static", Visibility: "shared", ItemPIDs: []string{hidden, seen},
	})
	if err != nil {
		t.Fatal(err)
	}
	kid := f.calmDenied()

	stop, flipped := make(chan struct{}), make(chan struct{})
	quiet := func() {
		select {
		case <-stop:
		default:
			close(stop)
		}
		<-flipped
	}
	defer quiet()
	go func() {
		defer close(flipped)
		orders := [][]string{{seen, hidden}, {hidden, seen}}
		for i := 0; ; i++ {
			select {
			case <-stop:
				return
			default:
			}
			if err := f.svc.ReplacePlaylistItems(f.ctx, f.uc, pl.PID, orders[i%2], nil); err != nil {
				t.Error(err)
				return
			}
			time.Sleep(time.Millisecond)
		}
	}()
	export := func() ([]PortableRefDTO, error) {
		t.Helper()
		_, refs, err := f.svc.ExportPlaylistPortable(f.ctx, kid, pl.PID)
		for _, r := range refs {
			if r.Artist == "Hidden Twin" {
				t.Fatalf("an export handed out the hidden twin's ref: %+v", r)
			}
		}
		return refs, err
	}
	for range 60 {
		if _, err := export(); err != nil && KindOf(err) != KindConflict {
			t.Fatal(err)
		}
	}
	// Once the list holds still, the export goes through.
	quiet()
	if refs, err := export(); err != nil || len(refs) != 1 || refs[0].Artist != "Seen Twin" {
		t.Errorf("the export of a quiet list = %+v, %v; want the seen twin alone", refs, err)
	}
}

// A static list whose members cannot be added is taken back whole: the
// create and the add are two writes behind one call, and a failure must
// not leave an empty list behind for a retry to duplicate.
func TestCreatePlaylistLeavesNothingWhenItsMembersFail(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, uc)
	execCatalog(t, svc.catalogPath, `CREATE TRIGGER refuse_members BEFORE INSERT ON playlist_item
		BEGIN SELECT RAISE(ABORT, 'refused'); END`)
	if _, err := svc.CreatePlaylist(ctx, uc, PlaylistCreate{Name: "Doomed", Kind: "static", ItemPIDs: pids[:1]}); err == nil {
		t.Fatal("a create whose members failed answered success")
	}
	page, err := svc.Playlists(ctx, uc, "", "", 100)
	if err != nil {
		t.Fatal(err)
	}
	for _, pl := range page.Playlists {
		if pl.Name == "Doomed" {
			t.Errorf("the failed create left %+v behind", pl)
		}
	}
}
