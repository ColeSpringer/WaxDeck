package service

import (
	"testing"
	"time"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// The snapshot ladder answers only with a picture that will be stored,
// and only from a rung the operator has left switched on.
func TestRadioSavedSnapshotSkipsOversizeAndTheSwitchedOffRung(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	const line = "Charlie Parker - Ornithology"
	const station = "rs-01JZX5N8QW3F4V9T2B7KDEXAMPLE"
	key := radioArtKey(radioSearchField("Charlie Parker"), radioSearchField("Ornithology"))
	cover := radioLogoFromBytes([]byte("tiny-cover"), "image/png")
	store := func() {
		svc.storeRadioArt(key, radioArtEntry{
			art: cover, fetched: time.Now(), fresh: radioArtFreshFor,
		})
	}

	// On, and a cover that fits: the external rung answers.
	enableRadioExternalArt(t, ctx, svc)
	store()
	data, mime, _ := svc.radioSavedSnapshot(ctx, uc, station, "Deck FM", line, "Charlie Parker", "Ornithology")
	if string(data) != "tiny-cover" || mime != "image/png" {
		t.Fatalf("snapshot = (%q, %q), want the cached external cover", data, mime)
	}

	// Off, and the same cover is left where it is. A snapshot outlives
	// both the toggle and the forget that comes with it, so copying one
	// here would put the operator's decision permanently out of reach.
	disableRadioExternalArt(t, ctx, svc)
	store()
	if data, _, _ := svc.radioSavedSnapshot(ctx, uc, station, "Deck FM", line, "Charlie Parker", "Ornithology"); data != nil {
		t.Fatalf("snapshot = %q with the external rung off, want nothing", data)
	}

	// Back on, but the cover is past what the column takes: the rung has
	// not answered, so the row saves artless rather than the ladder
	// stopping on a picture that will be dropped.
	enableRadioExternalArt(t, ctx, svc)
	svc.storeRadioArt(key, radioArtEntry{
		art: radioLogoFromBytes(
			make([]byte, wdb.RadioSavedArtMaxBytes+1), "image/png"),
		fetched: time.Now(),
		fresh:   radioArtFreshFor,
	})
	if data, _, _ := svc.radioSavedSnapshot(ctx, uc, station, "Deck FM", line, "Charlie Parker", "Ornithology"); data != nil {
		t.Fatalf("snapshot = %d bytes, want the oversize cover skipped", len(data))
	}
}

// The identity a saved song is filed under is unchangeable the moment
// rows exist, so the properties it has to hold are pinned here rather
// than left to the endpoint tests.
func TestRadioSavedIdentity(t *testing.T) {
	t.Parallel()
	orn := radioSavedIdentity("Charlie Parker", "Ornithology", "Charlie Parker - Ornithology")

	// The same song announced with different case and different noise
	// around it is one row, which is what makes a filled heart's tap
	// remove rather than duplicate.
	if got := radioSavedIdentity("charlie parker", "Ornithology (Official Audio)",
		"charlie parker - Ornithology (Official Audio)"); got != orn {
		t.Fatalf("noisy announcement identity = %q, want the same as the clean one", got)
	}
	// A different song is a different row.
	if got := radioSavedIdentity("Charlie Parker", "Confirmation", "Charlie Parker - Confirmation"); got == orn {
		t.Fatal("two songs share an identity")
	}

	// The two key spaces are disjoint by construction, and this is the
	// case that would collide without the prefixes: a parsed line whose
	// halves spell what an unparsed line folds to.
	parsed := radioSavedIdentity("raw", "x", "raw - x")
	unparsed := radioSavedIdentity("", "", "raw\x00x")
	if parsed == unparsed {
		t.Fatal("a parsed identity collided with a raw one")
	}

	// An unparsed line is itself, folded only by case and whitespace -
	// not by the bracket-stripping the parsed branch uses, which would
	// file two different bumpers as one saved thing.
	ident := radioSavedIdentity("", "", "Deck FM  overnight   session")
	if got := radioSavedIdentity("", "", "deck fm overnight session"); got != ident {
		t.Fatalf("whitespace-folded line identity = %q, want the same", got)
	}
	if radioSavedIdentity("", "", "[ad break]") == radioSavedIdentity("", "", "[promo]") {
		t.Fatal("two bracketed idents collapsed onto one identity")
	}

	// A parse whose halves do not survive normalization falls back to
	// the raw line rather than filing every such announcement under the
	// one empty-halves key.
	punct := radioSavedIdentity("!!!", "???", "!!! - ???")
	other := radioSavedIdentity("***", "???", "*** - ???")
	if punct == other {
		t.Fatal("two announcements whose halves normalize away share an identity")
	}
	if punct != radioSavedIdentity("", "", "!!! - ???") {
		t.Fatal("an announcement whose halves normalize away is not keyed by its raw line")
	}
}
