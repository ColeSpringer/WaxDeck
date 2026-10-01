package db

import (
	"context"
	"reflect"
	"testing"
)

func TestLibraryRootsRoundTrip(t *testing.T) {
	ctx := context.Background()
	d := openTest(t)
	for _, r := range []LibraryRoot{
		{Path: "/b", Name: "Bee", CreatedAtNS: 2},
		{Path: "/a", Name: "Ay", CreatedAtNS: 1},
		{Path: "/a", Name: "Renamed", CreatedAtNS: 9},
	} {
		if err := d.LibraryRootsUpsert(ctx, r); err != nil {
			t.Fatal(err)
		}
	}
	got, err := d.LibraryRootsList(ctx)
	want := []LibraryRoot{{Path: "/a", Name: "Renamed", CreatedAtNS: 1}, {Path: "/b", Name: "Bee", CreatedAtNS: 2}}
	if err != nil || !reflect.DeepEqual(got, want) {
		t.Fatalf("roots = %+v (%v), want %+v", got, err, want)
	}
}
