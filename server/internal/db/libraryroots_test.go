package db

import (
	"context"
	"fmt"
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
	for _, path := range []string{"/a", "/missing"} {
		if err := d.LibraryRootsDelete(ctx, path); err != nil {
			t.Fatal(err)
		}
	}
	got, err = d.LibraryRootsList(ctx)
	want = []LibraryRoot{{Path: "/b", Name: "Bee", CreatedAtNS: 2}}
	if err != nil || !reflect.DeepEqual(got, want) {
		t.Fatalf("roots after delete = %+v (%v), want %+v", got, err, want)
	}
}

// A removed library leaves no grant naming it, on an account or on an
// invite still to be used, and every other grant stays as it was.
func TestPruneLibraryGrants(t *testing.T) {
	ctx := context.Background()
	d := openTest(t)
	for _, id := range []string{"us-1", "us-2"} {
		if err := d.CreateUser(ctx, mkUser(id, id, nil), false); err != nil {
			t.Fatal(err)
		}
	}
	if err := d.SetLibraryGrants(ctx, "us-1", []string{"gone", "kept"}); err != nil {
		t.Fatal(err)
	}
	if err := d.SetLibraryGrants(ctx, "us-2", []string{"gone"}); err != nil {
		t.Fatal(err)
	}
	for i, grants := range []string{`["gone","kept"]`, `["kept"]`, `[]`} {
		if err := d.InsertInvite(ctx, Invite{
			ID: fmt.Sprintf("iv-%d", i), TokenHash: []byte{byte(i)}, LibraryAccess: "granted", LibraryGrants: grants, MaxUses: 1,
		}); err != nil {
			t.Fatal(err)
		}
	}
	if err := d.PruneLibraryGrants(ctx, "gone"); err != nil {
		t.Fatal(err)
	}
	for id, want := range map[string][]string{"us-1": {"kept"}, "us-2": nil} {
		got, err := d.LibraryGrants(ctx, id)
		if err != nil || !reflect.DeepEqual(got, want) {
			t.Errorf("%s grants = %v (%v), want %v", id, got, err, want)
		}
	}
	invites, err := d.ListInvites(ctx)
	if err != nil {
		t.Fatal(err)
	}
	got := map[string]string{}
	for _, iv := range invites {
		got[iv.ID] = iv.LibraryGrants
	}
	want := map[string]string{"iv-0": `["kept"]`, "iv-1": `["kept"]`, "iv-2": `[]`}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("invite grants = %v, want %v", got, want)
	}
}

// Every library pid a grant names is listed once, whether an account or
// an invite holds it.
func TestGrantedLibraryPIDs(t *testing.T) {
	ctx := context.Background()
	d := openTest(t)
	if err := d.CreateUser(ctx, mkUser("us-1", "us-1", nil), false); err != nil {
		t.Fatal(err)
	}
	if err := d.SetLibraryGrants(ctx, "us-1", []string{"held", "shared"}); err != nil {
		t.Fatal(err)
	}
	for i, grants := range []string{`["shared","invited"]`, `[]`} {
		if err := d.InsertInvite(ctx, Invite{
			ID: fmt.Sprintf("iv-%d", i), TokenHash: []byte{byte(i)}, LibraryAccess: "granted", LibraryGrants: grants, MaxUses: 1,
		}); err != nil {
			t.Fatal(err)
		}
	}
	got, err := d.GrantedLibraryPIDs(ctx)
	if want := []string{"held", "invited", "shared"}; err != nil || !reflect.DeepEqual(got, want) {
		t.Errorf("granted = %v (%v), want %v", got, err, want)
	}
}
