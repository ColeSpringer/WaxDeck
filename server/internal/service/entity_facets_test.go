package service

import (
	"strings"
	"testing"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/read"
)

// TestEntityInLibraries pins the attribution rule that restores entity
// search for restricted callers: an entity is visible when one of the
// libraries holding its members is granted, and hidden otherwise.
func TestEntityInLibraries(t *testing.T) {
	l := &Library{}
	info := &read.EntityInfo{LibraryPIDs: []model.PID{"libA", "libB"}}

	if !l.entityInLibraries(info, &UserCtx{Libraries: map[string]bool{"libB": true}}) {
		t.Fatal("an entity with a granted member library should be visible")
	}
	if l.entityInLibraries(info, &UserCtx{Libraries: map[string]bool{"libC": true}}) {
		t.Fatal("an entity with no granted member library should be hidden")
	}
	if l.entityInLibraries(&read.EntityInfo{}, &UserCtx{Libraries: map[string]bool{"libA": true}}) {
		t.Fatal("an entity attributed to no library should be hidden")
	}
}

// TestRestrictedEntitySearchAttribution drives the batched attribution
// end to end. Entity hits carry no stored library column, so a
// restricted caller's are kept or dropped by which libraries hold their
// members; the lookup is batched per kind now, and a batch that keyed
// or filtered wrongly would either leak entities or empty the results.
func TestRestrictedEntitySearchAttribution(t *testing.T) {
	ctx, svc, uc := newCatalogFixture(t)

	libs, err := svc.Libraries(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if len(libs) != 1 {
		t.Fatalf("libraries = %d, want the one fixture root", len(libs))
	}
	granted := &UserCtx{
		ID: uc.ID, CatalogPID: uc.CatalogPID,
		Libraries: map[string]bool{strings.TrimPrefix(libs[0].PID, PrefixLibrary+"-"): true},
	}
	res, err := svc.Search(ctx, granted, "Signal Garden", 10)
	if err != nil {
		t.Fatalf("granted search: %v", err)
	}
	if len(res.Albums) == 0 {
		t.Fatal("a caller granted the only library sees no album entities")
	}

	// The same search under a grant for a different library keeps
	// nothing: every hit attributes to a library outside the grant.
	other, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "other", Path: t.TempDir()})
	if err != nil {
		t.Fatalf("adding a second library: %v", err)
	}
	elsewhere := &UserCtx{
		ID: uc.ID, CatalogPID: uc.CatalogPID,
		Libraries: map[string]bool{strings.TrimPrefix(other.PID, PrefixLibrary+"-"): true},
	}
	res, err = svc.Search(ctx, elsewhere, "Signal Garden", 10)
	if err != nil {
		t.Fatalf("ungranted search: %v", err)
	}
	if len(res.Albums) != 0 || len(res.Artists) != 0 {
		t.Fatalf("a caller granted no holding library saw %d albums and %d artists",
			len(res.Albums), len(res.Artists))
	}
}

// The fixture catalog groups every track under the album "Signal
// Garden", so a search for it yields a real album entity pid the mix
// and share surfaces can seed and target.

func TestAlbumMixSeed(t *testing.T) {
	ctx, svc, uc := newCatalogFixture(t)

	res, err := svc.Search(ctx, uc, "Signal Garden", 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Albums) == 0 {
		t.Fatal("fixture album not in search results")
	}
	albumPID := res.Albums[0].PID
	if !strings.HasPrefix(albumPID, "al-") {
		t.Fatalf("album search hit pid = %q, want an al- entity pid", albumPID)
	}

	// An album seed resolves the album's own tracks by entity identity
	// (album_pid), not a display-string match.
	mix, err := svc.InstantMix(ctx, uc, InstantMixInput{SeedPID: albumPID, Size: 10})
	if err != nil {
		t.Fatalf("album-seeded mix: %v", err)
	}
	if len(mix.Items) == 0 {
		t.Fatal("album-seeded mix was empty")
	}
}

func TestAlbumShareResolvesMembers(t *testing.T) {
	ctx, svc, uc := newCatalogFixture(t)

	res, err := svc.Search(ctx, uc, "Signal Garden", 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Albums) == 0 {
		t.Fatal("fixture album not in search results")
	}
	albumPID := res.Albums[0].PID

	info, err := svc.CreateShare(ctx, uc, albumPID, 0, false, 0)
	if err != nil {
		t.Fatalf("sharing an album: %v", err)
	}
	if info.TargetKind != "album" {
		t.Fatalf("share target kind = %q, want album", info.TargetKind)
	}

	// Resolved for anonymous serving, the share opens the album's tracks.
	pub, err := svc.ResolveShare(ctx, strings.TrimPrefix(info.ID, "sh-"))
	if err != nil {
		t.Fatalf("resolving album share: %v", err)
	}
	if pub.Subtitle != "Album" {
		t.Fatalf("share subtitle = %q, want Album", pub.Subtitle)
	}
	if len(pub.Items) == 0 {
		t.Fatal("album share resolved no members")
	}
	// The fixture has two distinct albums both titled "Signal Garden",
	// one per album artist. album_pid groups by album entity, not title,
	// so the share holds exactly one album artist's tracks, never a mix.
	known := map[string]bool{
		"Amber Waves": true, "Basalt Steps": true,
		"Cobalt Sky": true, "Delta Groove": true,
	}
	artist := pub.Items[0].Artist
	for _, it := range pub.Items {
		if !known[it.Title] {
			t.Fatalf("unexpected album member %q", it.Title)
		}
		if it.Artist != artist {
			t.Fatalf("album share mixes artists %q and %q; album_pid must group by entity", artist, it.Artist)
		}
	}
}
