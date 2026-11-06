package service

import (
	"context"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
)

// fixtureTracks answers the shelf fixture's three tracks' pids.
func fixtureTracks(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx) []string {
	t.Helper()
	page, err := svc.Items(ctx, uc, ItemFilter{}, "", 10)
	if err != nil || len(page.Items) != 3 {
		t.Fatalf("items = %+v (%v), want the fixture's three tracks", page.Items, err)
	}
	pids := make([]string, 0, len(page.Items))
	for _, it := range page.Items {
		pids = append(pids, it.PID)
	}
	return pids
}

func summaryPIDs(items []ItemSummary) []string {
	out := make([]string, 0, len(items))
	for _, it := range items {
		out = append(out, it.PID)
	}
	return out
}

// The caller's order is the answer's order, a repeated pid once per
// occurrence, so a queue of handles reads back as it stands.
func TestResolveItemsAnswersInRequestOrder(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newShelfFixture(t)
	tracks := fixtureTracks(t, ctx, svc, uc)
	a, b, c := tracks[0], tracks[1], tracks[2]

	items, departed, err := svc.ResolveItems(ctx, uc, []string{c, a, b, a})
	if err != nil {
		t.Fatal(err)
	}
	if got, want := summaryPIDs(items), []string{c, a, b, a}; !slices.Equal(got, want) {
		t.Fatalf("answered %v, want %v", got, want)
	}
	if len(departed) != 0 {
		t.Fatalf("departed = %v, want none", departed)
	}
	if items[1].Title == "" || items[1].MediaType != "music" {
		t.Fatalf("a summary = %+v, want the track's own", items[1])
	}

	// The catalog keys its answer by the stored pid, so a lower-case ULID
	// that read and then failed to match would be an item silently gone.
	lower, _, err := svc.ResolveItems(ctx, uc, []string{strings.ToLower(a)})
	if err != nil || !slices.Equal(summaryPIDs(lower), []string{a}) {
		t.Fatalf("a lower-case pid answered %v (%v), want %s", summaryPIDs(lower), err, a)
	}

	// A track's pid and a book's reach the same item, which is how an
	// item a kind change converted is still reached by the pid a list
	// held: it answers under the prefix its kind has now.
	asBook := PrefixBook + "-" + a[strings.IndexByte(a, '-')+1:]
	same, _, err := svc.ResolveItems(ctx, uc, []string{asBook})
	if err != nil || !slices.Equal(summaryPIDs(same), []string{a}) {
		t.Fatalf("%s answered %v (%v), want %s", asBook, summaryPIDs(same), err, a)
	}
}

// Departed is what no item answers to, for anyone; an item merely out of
// the caller's sight is left out unnamed, since a widened grant brings it
// back and a client dropping it would make that a loss.
func TestResolveItemsNameOnlyTheDeparted(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newShelfFixture(t)
	tracks := fixtureTracks(t, ctx, svc, uc)
	a := tracks[0]
	never := "tr-01JZX5N8QW3F4V9T2B7KD3M9R6"
	// An episode's prefix on a track's ULID never named an item.
	wrongKind := PrefixEpisode + "-" + a[strings.IndexByte(a, '-')+1:]

	items, departed, err := svc.ResolveItems(ctx, uc, []string{never, a, wrongKind, never})
	if err != nil {
		t.Fatal(err)
	}
	if got := summaryPIDs(items); !slices.Equal(got, []string{a}) {
		t.Fatalf("answered %v, want only %s", got, a)
	}
	if want := []string{never, wrongKind}; !slices.Equal(departed, want) {
		t.Fatalf("departed = %v, want %v", departed, want)
	}
	// Departed answers each pid as it was asked for.
	lowerNever := strings.ToLower(never)
	if _, departed, err := svc.ResolveItems(ctx, uc, []string{lowerNever}); err != nil || !slices.Equal(departed, []string{lowerNever}) {
		t.Fatalf("a lower-case pid departed as %v (%v), want it as asked", departed, err)
	}

	restricted := &UserCtx{
		ID:         uc.ID,
		CatalogPID: uc.CatalogPID,
		Libraries:  map[string]bool{"lb-nothing": true},
	}
	items, departed, err = svc.ResolveItems(ctx, restricted, []string{a})
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 0 || len(departed) != 0 {
		t.Fatalf("out of the grant = items %v, departed %v; want neither", summaryPIDs(items), departed)
	}
}

// One request is bounded, and only item pids are asked about.
func TestResolveItemsRefusesWhatIsNotAnItemLookup(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newShelfFixture(t)
	a := fixtureTracks(t, ctx, svc, uc)[0]

	over := make([]string, maxItemLookup+1)
	for i := range over {
		over[i] = a
	}
	if _, _, err := svc.ResolveItems(ctx, uc, over); KindOf(err) != KindInvalid {
		t.Fatalf("over the cap = %v, want invalid-request", err)
	}
	full := over[:maxItemLookup]
	if items, _, err := svc.ResolveItems(ctx, uc, full); err != nil || len(items) != maxItemLookup {
		t.Fatalf("at the cap = %d answers (%v), want %d", len(items), err, maxItemLookup)
	}
	if _, _, err := svc.ResolveItems(ctx, uc, []string{"al-01JZX5N8QW3F4V9T2B7KD3M9R6"}); KindOf(err) != KindInvalid {
		t.Fatalf("an album pid = %v, want invalid-request", err)
	}
	if items, departed, err := svc.ResolveItems(ctx, uc, nil); err != nil || len(items) != 0 || len(departed) != 0 {
		t.Fatalf("an empty request = %v, %v, %v; want an empty answer", items, departed, err)
	}
}

// What the catalog did to an item decides what the lookup says: one a kind
// change folded into another is departed, while one in the trash, one
// purged from it and one deleted permanently are each answered as the
// item's own read answers them, since the catalog keeps no word on which
// archive a re-added folder undoes; and to a caller they are out of sight
// for, they are left out unnamed.
func TestResolveItemsAfterAFoldATrashAndAPurge(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixtureWith(t, catalogFixtureOptions{extra: func(t *testing.T, dir string) {
		if _, err := fixtures.GenerateLooseMP3Book(dir); err != nil {
			t.Fatal(err)
		}
	}})
	page, err := svc.Items(ctx, uc, ItemFilter{}, "", 50)
	if err != nil {
		t.Fatal(err)
	}
	byTitle := map[string]string{}
	for _, it := range page.Items {
		byTitle[it.Title] = it.PID
	}
	one, two := byTitle["Chapter One"], byTitle["Chapter Two"]
	trashed, purged, deleted := byTitle["Amber Waves"], byTitle["Basalt Steps"], byTitle["Cobalt Sky"]

	job, err := svc.SetItemsKind(ctx, uc, []string{one, two}, "audiobook", false)
	if err != nil {
		t.Fatal(err)
	}
	_, jobPID, _ := parseAPIPID(job.PID)
	waitForJob(t, ctx, svc, jobPID)
	if _, err := svc.DeleteItems(ctx, uc, []string{purged}, "trash", false); err != nil {
		t.Fatal(err)
	}
	if emptied, err := svc.EmptyTrash(ctx, uc); err != nil || emptied.Purged != 1 {
		t.Fatalf("emptying the trash = %+v (%v), want one file purged", emptied, err)
	}
	if _, err := svc.DeleteItems(ctx, uc, []string{deleted}, "permanent", false); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.DeleteItems(ctx, uc, []string{trashed}, "trash", false); err != nil {
		t.Fatal(err)
	}

	asked := []string{one, two, trashed, purged, deleted}
	items, departed, err := svc.ResolveItems(ctx, uc, asked)
	if err != nil {
		t.Fatal(err)
	}
	book := PrefixBook + "-" + one[strings.IndexByte(one, '-')+1:]
	if got, want := summaryPIDs(items), []string{book, trashed, purged, deleted}; !slices.Equal(got, want) {
		t.Fatalf("answered %v, want %v", got, want)
	}
	if want := []string{two}; !slices.Equal(departed, want) {
		t.Fatalf("departed = %v, want %v", departed, want)
	}
	// The item's own read answers all three as the lookup does.
	for _, pid := range []string{trashed, purged, deleted} {
		if _, err := svc.Item(ctx, uc, pid); err != nil {
			t.Fatalf("%s reads as %v, want it answered as before", pid, err)
		}
	}

	restricted := &UserCtx{
		ID:         uc.ID,
		CatalogPID: uc.CatalogPID,
		Libraries:  map[string]bool{"lb-nothing": true},
	}
	items, departed, err = svc.ResolveItems(ctx, restricted, asked)
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 0 {
		t.Fatalf("out of the grant answered %v, want nothing", summaryPIDs(items))
	}
	if want := []string{two}; !slices.Equal(departed, want) {
		t.Fatalf("out of the grant departed = %v, want %v and the archived ones unnamed", departed, want)
	}
}

// A removed library's items are archived until its folder is added again,
// so the lookup never names them departed: a re-add and its scan bring
// each back under the pid a queue held.
func TestResolveItemsKeepsARemovedLibrarysItems(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := openServiceAt(t, t.TempDir(), nil)
	dir := t.TempDir()
	if _, err := fixtures.Generate(dir, fixtures.Spec{
		Name: "round-trip", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
		Tags: map[string]string{"TITLE": "Round Trip", "ARTIST": "Remover"},
	}); err != nil {
		t.Fatal(err)
	}
	scanEnded := func(what string) {
		t.Helper()
		waitFor(t, func() bool {
			running, err := svc.catalogJobRunning(ctx)
			return err == nil && !running
		}, what)
	}
	listed := func() string {
		page, err := svc.Items(ctx, uc, ItemFilter{}, "", 50)
		if err != nil {
			t.Fatal(err)
		}
		for _, it := range page.Items {
			if it.Title == "Round Trip" {
				return it.PID
			}
		}
		return ""
	}
	resolves := func(pid, when string) {
		t.Helper()
		items, departed, err := svc.ResolveItems(ctx, uc, []string{pid})
		if err != nil {
			t.Fatal(err)
		}
		if !slices.Equal(summaryPIDs(items), []string{pid}) || len(departed) != 0 {
			t.Fatalf("%s: answered %v, departed %v; want %s answered", when, summaryPIDs(items), departed, pid)
		}
	}

	lib, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "music", Path: dir})
	if err != nil {
		t.Fatal(err)
	}
	scanEnded("the create's scan to end")
	var pid string
	waitFor(t, func() bool { pid = listed(); return pid != "" }, "the track cataloged")

	if _, err := svc.RemoveLibrary(ctx, uc, lib.PID); err != nil {
		t.Fatal(err)
	}
	waitFor(t, func() bool { return removalAudit(t, ctx, svc, lib.PID) != nil }, "the removal audited")
	resolves(pid, "after the removal")

	if _, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "music", Path: dir}); err != nil {
		t.Fatal(err)
	}
	scanEnded("the re-add's scan to end")
	var back string
	waitFor(t, func() bool { back = listed(); return back != "" }, "the track cataloged again")
	if back != pid {
		t.Fatalf("the re-add listed the track as %s, want it back under %s", back, pid)
	}
	resolves(pid, "after the re-add")
}
