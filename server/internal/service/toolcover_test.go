package service

import (
	"testing"

	waxart "github.com/colespringer/waxbin/art"
	"github.com/colespringer/waxbin/model"
)

// addToolCover decides which of two resolves to ask for by reading the
// format off ArtProvenance rather than off a blob it then throws away.
// That only works if provenance answers what the resolve would answer -
// same chain level, same stored format - so this is the assumption,
// pinned. Break it and the tagger silently embeds a TIFF a player draws
// as a broken frame, or re-encodes a JPEG for no reason.
func TestArtProvenanceMatchesWhatAResolveAnswers(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	pid := fixtureItemPIDs(t, ctx, svc, uc)[0]
	giveCovers(t, ctx, svc, uc, []string{pid}, coverPNG(t, 60))

	it, err := svc.getVisibleItem(ctx, uc, pid)
	if err != nil {
		t.Fatalf("resolving item: %v", err)
	}
	ref := model.EntityRef{Type: model.ArtTrack, PID: it.PID}

	prov, err := svc.lib.ArtProvenance(ctx, ref, model.ArtRoleFront)
	if err != nil {
		t.Fatalf("reading provenance: %v", err)
	}
	if prov == nil {
		t.Fatal("no provenance for an item that has a cover")
	}

	blob, err := svc.lib.ResolveArt(ctx, ref, model.ArtRoleFront, 0)
	if err != nil {
		t.Fatalf("resolving art: %v", err)
	}
	if blob == nil {
		t.Fatal("no blob for an item that has a cover")
	}

	if prov.Format != blob.Format {
		t.Errorf("provenance format = %q, unsized resolve = %q", prov.Format, blob.Format)
	}
	if prov.SourceHash != blob.SourceHash {
		t.Errorf("provenance hash = %q, resolve = %q", prov.SourceHash, blob.SourceHash)
	}
	if !waxart.Displayable(prov.Format) {
		t.Errorf("a PNG cover reads as non-displayable: %q", prov.Format)
	}
}

// The other half of the decision: an item with no cover anywhere in its
// chain says so by refusing rather than by answering an empty
// provenance. addToolCover reads that refusal as "no cover" and writes
// no picture frame, which is why the shape of it is worth pinning - an
// upstream that started answering a zero-valued provenance instead
// would have the tagger ask for a re-encode of nothing on every file a
// split writes.
func TestArtProvenanceRefusesWhenThereIsNoCover(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	pid := fixtureItemPIDs(t, ctx, svc, uc)[0]
	it, err := svc.getVisibleItem(ctx, uc, pid)
	if err != nil {
		t.Fatalf("resolving item: %v", err)
	}

	prov, err := svc.lib.ArtProvenance(ctx,
		model.EntityRef{Type: model.ArtTrack, PID: it.PID}, model.ArtRoleFront)
	if err == nil {
		t.Fatalf("provenance answered %+v for an item with no cover", prov)
	}
	// And the resolve agrees, which is what makes the cheap read a
	// stand-in for the expensive one here as much as anywhere else.
	blob, err := svc.lib.ResolveArt(ctx,
		model.EntityRef{Type: model.ArtTrack, PID: it.PID}, model.ArtRoleFront, 0)
	if err == nil && blob != nil && len(blob.Bytes) > 0 {
		t.Error("a resolve found bytes where provenance found nothing")
	}
}
