package db

import (
	"context"
	"reflect"
	"testing"
)

// The journal answers an item's libraries at a cursor from its newest
// change at or before it, every library a later change names, and where
// it stands; an item with no row at or before the cursor is not placed.
func TestItemLibrariesAroundACursor(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	state := LibraryJournalState{Through: 12, ThroughTS: 1200, Start: 2, Generation: 3}
	if err := d.RecordItemLibraries(ctx, []ItemLibrary{
		{ItemPID: "moved", Seq: 3, LibraryPID: "lb-a"},
		{ItemPID: "moved", Seq: 7, LibraryPID: "lb-b"},
		{ItemPID: "moved", Seq: 12, LibraryPID: "lb-c"},
		{ItemPID: "made", Seq: 11, LibraryPID: "lb-b"},
		{ItemPID: "copies", Seq: 2, LibraryPID: "lb-a"},
		{ItemPID: "copies", Seq: 2, LibraryPID: "lb-b"},
	}, &state); err != nil {
		t.Fatal(err)
	}
	got, err := d.ItemLibrariesAround(ctx, []string{"moved", "made", "copies", "unknown"}, 9)
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]ItemLibraries{
		"moved":  {AtCursor: []string{"lb-b"}, Placed: true, Since: []string{"lb-c"}},
		"made":   {Since: []string{"lb-b"}},
		"copies": {AtCursor: []string{"lb-a", "lb-b"}, Placed: true},
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("around 9 = %+v, want %+v", got, want)
	}
	if got, ok, err := d.LibraryJournalStateFor(ctx); err != nil || !ok || got != state {
		t.Errorf("state = %+v, %v, %v; want %+v", got, ok, err, state)
	}
	latest, err := d.LatestItemLibraries(ctx, []string{"moved", "made", "copies", "unknown"})
	if err != nil {
		t.Fatal(err)
	}
	if want := map[string][]string{"moved": {"lb-c"}, "made": {"lb-b"}, "copies": {"lb-a", "lb-b"}}; !reflect.DeepEqual(latest, want) {
		t.Errorf("latest = %v, want %v", latest, want)
	}
	// Rows alone leave where the journal stands as it was.
	if err := d.RecordItemLibraries(ctx, []ItemLibrary{{ItemPID: "made", Seq: 13, LibraryPID: "lb-c"}}, nil); err != nil {
		t.Fatal(err)
	}
	if got, _, _ := d.LibraryJournalStateFor(ctx); got != state {
		t.Errorf("state after rows alone = %+v, want %+v", got, state)
	}
}

// A prune at the change log's floor keeps each item's rows placing it at
// the floor and every row after it, and drops the rest, an item dropped
// at or below the floor with all of its rows. A reset drops every row and
// where the journal stands.
func TestItemLibrariesPruneWithTheFloor(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	if err := d.RecordItemLibraries(ctx, []ItemLibrary{
		{ItemPID: "moved", Seq: 3, LibraryPID: "lb-a"},
		{ItemPID: "moved", Seq: 7, LibraryPID: "lb-b"},
		{ItemPID: "moved", Seq: 12, LibraryPID: "lb-c"},
		{ItemPID: "still", Seq: 2, LibraryPID: "lb-a"},
		{ItemPID: "still", Seq: 2, LibraryPID: "lb-b"},
		{ItemPID: "gone", Seq: 4, LibraryPID: "lb-a"},
		{ItemPID: "gone", Seq: 6, LibraryPID: ""},
		{ItemPID: "late", Seq: 9, LibraryPID: "lb-a"},
		{ItemPID: "late", Seq: 11, LibraryPID: ""},
	}, &LibraryJournalState{Through: 12}); err != nil {
		t.Fatal(err)
	}
	n, err := d.PruneItemLibraries(ctx, 8)
	if err != nil {
		t.Fatal(err)
	}
	if n != 3 {
		t.Errorf("pruned %d rows, want 3", n)
	}
	got, err := d.ItemLibrariesAround(ctx, []string{"moved", "still", "gone", "late"}, 8)
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]ItemLibraries{
		"moved": {AtCursor: []string{"lb-b"}, Placed: true, Since: []string{"lb-c"}},
		"still": {AtCursor: []string{"lb-a", "lb-b"}, Placed: true},
		"late":  {Since: []string{"lb-a", ""}},
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("after the prune = %+v, want %+v", got, want)
	}
	if err := d.ResetItemLibraries(ctx); err != nil {
		t.Fatal(err)
	}
	if got, err := d.LatestItemLibraries(ctx, []string{"moved", "still", "late"}); err != nil || len(got) != 0 {
		t.Errorf("after a reset = %v, %v; want nothing", got, err)
	}
	if _, ok, err := d.LibraryJournalStateFor(ctx); err != nil || ok {
		t.Errorf("a reset journal stands somewhere (%v, %v), want nowhere until its walk ends", ok, err)
	}
}
