package service

import (
	"bytes"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
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

// noisyJPEG encodes a square of incompressible pixels, so the result is
// a real decodable image reliably past the column's cap.
func noisyJPEG(t *testing.T, dim int) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, dim, dim))
	seed := uint32(2463534242)
	next := func() uint8 {
		seed ^= seed << 13
		seed ^= seed >> 17
		seed ^= seed << 5
		return uint8(seed)
	}
	for y := range dim {
		for x := range dim {
			img.Set(x, y, color.RGBA{next(), next(), next(), 255})
		}
	}
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, img, &jpeg.Options{Quality: 95}); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

// The cache holds what the full-screen face draws, which is a bigger
// picture than a list row wants. Measuring it as-is meant the archive's
// large rendition failed the cap outright, and the commonest save there
// is - a song the library does not hold - kept an artless row.
func TestRadioSavedSnapshotScalesAFullSizeCover(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	const line = "Charlie Parker - Ornithology"
	const station = "rs-01JZX5N8QW3F4V9T2B7KDEXAMPLE"
	enableRadioExternalArt(t, ctx, svc)

	full := noisyJPEG(t, 1200)
	if len(full) <= wdb.RadioSavedArtMaxBytes {
		t.Fatalf("fixture cover is %d bytes, want one past the %d cap",
			len(full), wdb.RadioSavedArtMaxBytes)
	}
	svc.storeRadioArt(
		radioArtKey(radioSearchField("Charlie Parker"), radioSearchField("Ornithology")),
		radioArtEntry{
			art:     radioLogoFromBytes(full, "image/jpeg"),
			fetched: time.Now(),
			fresh:   radioArtFreshFor,
		})

	data, mime, etag := svc.radioSavedSnapshot(ctx, uc, station, "Deck FM", line, "Charlie Parker", "Ornithology")
	if len(data) == 0 {
		t.Fatal("snapshot kept nothing, want the cover scaled to fit")
	}
	if len(data) > wdb.RadioSavedArtMaxBytes {
		t.Fatalf("snapshot = %d bytes, past the %d cap", len(data), wdb.RadioSavedArtMaxBytes)
	}
	if mime != "image/jpeg" {
		t.Fatalf("mime = %q, want the scaled encoding's own type", mime)
	}
	// The etag names these bytes rather than the ones they came from.
	if etag != radioSavedETag(data) {
		t.Fatalf("etag = %q, want it over the stored bytes", etag)
	}
	cfg, err := jpeg.DecodeConfig(bytes.NewReader(data))
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Width > radioSavedSnapshotPx || cfg.Height > radioSavedSnapshotPx {
		t.Fatalf("scaled to %dx%d, want it inside %d", cfg.Width, cfg.Height, radioSavedSnapshotPx)
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

// noisyPNG is a source the same size cannot re-encode smaller, which is
// what a 500px archive rendition over the cap behaves like.
func noisyPNG(t *testing.T, dim int) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, dim, dim))
	seed := uint32(2463534242)
	next := func() uint8 {
		seed ^= seed << 13
		seed ^= seed >> 17
		seed ^= seed << 5
		return uint8(seed)
	}
	for y := range dim {
		for x := range dim {
			img.Set(x, y, color.RGBA{next(), next(), next(), 255})
		}
	}
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

// The snapshot box is 512px and the archive's rendition is 500, so
// scaling to the box is a no-op and an oversize cover has to go smaller
// than it or the commonest save of all keeps an artless row.
func TestRadioSavedSnapshotScalesACoverSmallerThanTheBox(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	const line = "Charlie Parker - Ornithology"
	const station = "rs-01JZX5N8QW3F4V9T2B7KDEXAMPLE"
	enableRadioExternalArt(t, ctx, svc)

	rendition := noisyPNG(t, 500)
	if len(rendition) <= wdb.RadioSavedArtMaxBytes {
		t.Fatalf("fixture cover is %d bytes, want one past the %d cap",
			len(rendition), wdb.RadioSavedArtMaxBytes)
	}
	svc.storeRadioArt(
		radioArtKey(radioSearchField("Charlie Parker"), radioSearchField("Ornithology")),
		radioArtEntry{
			art:     radioLogoFromBytes(rendition, "image/png"),
			fetched: time.Now(),
			fresh:   radioArtFreshFor,
		})

	data, _, _ := svc.radioSavedSnapshot(ctx, uc, station, "Deck FM", line, "Charlie Parker", "Ornithology")
	if len(data) == 0 {
		t.Fatal("the row saved artless, want the cover scaled under the cap")
	}
	if len(data) > wdb.RadioSavedArtMaxBytes {
		t.Fatalf("snapshot = %d bytes, past the %d cap", len(data), wdb.RadioSavedArtMaxBytes)
	}
}

// A station's announced cover is capped at 512 KB at any dimensions, so
// a large noisy one can miss the row's cap at more than one rung down.
func TestRadioSavedSnapshotKeepsHalvingUntilItFits(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	const line = "Charlie Parker - Ornithology"
	const station = "rs-01JZX5N8QW3F4V9T2B7KDEXAMPLE"
	enableRadioExternalArt(t, ctx, svc)

	announced := noisyPNG(t, 1500)
	if len(announced) <= wdb.RadioSavedArtMaxBytes {
		t.Fatalf("fixture cover is %d bytes, want one past the %d cap",
			len(announced), wdb.RadioSavedArtMaxBytes)
	}
	svc.storeRadioArt(
		radioArtKey(radioSearchField("Charlie Parker"), radioSearchField("Ornithology")),
		radioArtEntry{
			art:     radioLogoFromBytes(announced, "image/png"),
			fetched: time.Now(),
			fresh:   radioArtFreshFor,
		})

	data, _, _ := svc.radioSavedSnapshot(ctx, uc, station, "Deck FM", line, "Charlie Parker", "Ornithology")
	if len(data) == 0 {
		t.Fatal("the row saved artless, want the cover shrunk under the cap")
	}
	if len(data) > wdb.RadioSavedArtMaxBytes {
		t.Fatalf("snapshot = %d bytes, past the %d cap", len(data), wdb.RadioSavedArtMaxBytes)
	}
}
