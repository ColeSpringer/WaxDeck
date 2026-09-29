package service

import (
	"testing"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
)

// A new MusicBrainz id on an album drops the art enrichment fetched
// under the old one, so the next pass asks again. A role a pin holds
// keeps its picture, and so does one a person set.
func TestAnIdentifierEditDropsEnrichmentArtButNotAPin(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	it, err := svc.getVisibleItem(ctx, uc, fixtureItemPIDs(t, ctx, svc, uc)[0])
	if err != nil {
		t.Fatal(err)
	}
	album := it.AlbumPID
	fetched := waxbin.ArtEditOptions{Source: model.SourceEnrichment, Provider: "fixturecovers"}
	for role, raw := range map[model.ArtRole][]byte{
		model.ArtRoleFront: coverPNG(t, 40),
		model.ArtRoleBack:  coverPNG(t, 120),
	} {
		if err := svc.lib.SetEntityArt(ctx, model.ArtAlbum, album, role, raw, fetched); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := svc.lib.SetArtLock(ctx, model.ArtAlbum, album, model.ArtRoleBack, true); err != nil {
		t.Fatal(err)
	}
	if err := svc.lib.SetEntityArt(ctx, model.ArtAlbum, album, model.ArtRoleDisc, coverPNG(t, 200), waxbin.ArtEditOptions{}); err != nil {
		t.Fatal(err)
	}

	if _, err := svc.EditEntity(ctx, "album", apiPID(PrefixAlbum, album),
		map[string]string{"mbid": "0b1d6a4e-6f0e-4b43-9b0f-3f6a1e2c9d10"}, MetadataEditParams{}); err != nil {
		t.Fatal(err)
	}
	roles, err := svc.lib.ArtRoles(ctx, model.EntityRef{Type: model.ArtAlbum, PID: album})
	if err != nil {
		t.Fatal(err)
	}
	held := map[model.ArtRole]bool{}
	for _, r := range roles {
		held[r.Role] = r.Format != ""
	}
	if held[model.ArtRoleFront] || !held[model.ArtRoleBack] || !held[model.ArtRoleDisc] {
		t.Fatalf("after the edit the album holds %v, want the pinned back and the hand-set disc only", held)
	}
}
