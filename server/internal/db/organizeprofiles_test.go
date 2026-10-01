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
