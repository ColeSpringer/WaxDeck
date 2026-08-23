package service

import "testing"

// The share page's art read is the second producer of an ArtBlob, and
// what it leaves out is invisible: nothing about the response says which
// rung answered it. The oversize guard in front of it short-circuits on
// an unsized blob, so a Box left at zero turns "refuse an original too
// big to paint" into "stream it to anonymous visitors under an hour of
// public caching".
func TestPublicArtAnswersTheSameRungAsTheAuthenticatedRead(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	pid := fixtureItemPIDs(t, ctx, svc, uc)[0]
	giveCovers(t, ctx, svc, uc, []string{pid}, coverPNG(t, 40))

	// A size between two rungs, so "the rung it answered at" and "the
	// size that was asked for" cannot be confused for each other.
	const asked = 200

	private, err := svc.Art(ctx, uc, pid, "", asked)
	if err != nil {
		t.Fatalf("reading item art: %v", err)
	}
	public, err := svc.PublicArt(ctx, pid, asked)
	if err != nil {
		t.Fatalf("reading share art: %v", err)
	}

	if private.Box == 0 {
		t.Fatal("the authenticated read named no rung")
	}
	if private.Box <= asked {
		t.Errorf("Box = %d, want the rung above %d", private.Box, asked)
	}
	if public.Box != private.Box {
		t.Errorf("share art Box = %d, item art Box = %d", public.Box, private.Box)
	}
}

// A resolve nobody gave a size to is the stored original, and the guard
// reads that as "not a thumbnail request" rather than as a rung.
func TestPublicArtNamesNoRungWhenNoSizeWasAsked(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	pid := fixtureItemPIDs(t, ctx, svc, uc)[0]
	giveCovers(t, ctx, svc, uc, []string{pid}, coverPNG(t, 90))

	blob, err := svc.PublicArt(ctx, pid, 0)
	if err != nil {
		t.Fatalf("reading share art: %v", err)
	}
	if blob.Box != 0 {
		t.Errorf("Box = %d, want 0 for an unsized resolve", blob.Box)
	}
}
