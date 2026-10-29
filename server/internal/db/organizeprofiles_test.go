package db

import (
	"context"
	"reflect"
	"testing"
)

func TestOrganizeProfilesRoundTrip(t *testing.T) {
	ctx := context.Background()
	d := openTest(t)
	for _, p := range []OrganizeProfile{
		{Name: "plex", Music: "{artist}/{title}.{ext}", UpdatedAtNS: 1},
		{Name: "flat", Music: "{title}.{ext}", Audiobook: "{title}/{title}.{ext}", Podcast: "{podcast}/{episode}.{ext}", TagWrite: true, UpdatedAtNS: 2},
		{Name: "plex", Music: "{albumartist}/{title}.{ext}", UpdatedAtNS: 3},
	} {
		if err := d.OrganizeProfilesUpsert(ctx, p); err != nil {
			t.Fatal(err)
		}
	}
	got, err := d.OrganizeProfilesList(ctx)
	want := []OrganizeProfile{
		{Name: "flat", Music: "{title}.{ext}", Audiobook: "{title}/{title}.{ext}", Podcast: "{podcast}/{episode}.{ext}", TagWrite: true, UpdatedAtNS: 2},
		{Name: "plex", Music: "{albumartist}/{title}.{ext}", UpdatedAtNS: 3},
	}
	if err != nil || !reflect.DeepEqual(got, want) {
		t.Fatalf("profiles = %+v (%v), want %+v", got, err, want)
	}
	if err := d.OrganizeProfilesDelete(ctx, "flat"); err != nil {
		t.Fatal(err)
	}
	if got, err := d.OrganizeProfilesList(ctx); err != nil || !reflect.DeepEqual(got, want[1:]) {
		t.Fatalf("profiles = %+v (%v), want %+v", got, err, want[1:])
	}
}

// A compilation folder keeps its three states apart: unset, set empty,
// and a name, and a save without one clears what was there.
func TestOrganizeProfilesKeepTheCompilationFolder(t *testing.T) {
	ctx := context.Background()
	d := openTest(t)
	empty, named := "", "Compilations"
	for _, p := range []OrganizeProfile{
		{Name: "default", UpdatedAtNS: 1},
		{Name: "own", CompilationFolder: &empty, UpdatedAtNS: 1},
		{Name: "named", CompilationFolder: &named, UpdatedAtNS: 1},
		{Name: "cleared", CompilationFolder: &named, UpdatedAtNS: 1},
		{Name: "cleared", UpdatedAtNS: 2},
	} {
		if err := d.OrganizeProfilesUpsert(ctx, p); err != nil {
			t.Fatal(err)
		}
	}
	got, err := d.OrganizeProfilesList(ctx)
	if err != nil {
		t.Fatal(err)
	}
	folders := map[string]*string{}
	for _, p := range got {
		folders[p.Name] = p.CompilationFolder
	}
	if f := folders["default"]; f != nil {
		t.Errorf("unset folder = %q, want NULL", *f)
	}
	if f := folders["own"]; f == nil || *f != "" {
		t.Errorf("empty folder = %v, want the empty string", f)
	}
	if f := folders["named"]; f == nil || *f != named {
		t.Errorf("named folder = %v, want %q", f, named)
	}
	if f := folders["cleared"]; f != nil {
		t.Errorf("a save without a folder left %q", *f)
	}
}
