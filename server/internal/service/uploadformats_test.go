package service

import (
	"slices"
	"strings"
	"testing"
)

// The format gate at session create: the allow-list refuses with a
// sentence naming the extension, and the DRM deny-list answers with a
// code of its own - and wins even over an operator's widened format
// set, which replaces the default rather than extending it.

func TestCreateUploadRefusesDRMFormatsByName(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := uploadFixture(t)
	// The positive control walks all the way to the staging check, and
	// the real probe answers for the test volume; see uploadFixture's
	// file for why it is stubbed rather than trusted.
	svc.stagingFree = func(string) (int64, bool) { return 1 << 62, true }

	for _, name := range []string{"book.aax", "book.aaxc", "BOOK.AAX"} {
		err := openSessionErr(ctx, svc, uc, name, 4096)
		// Its own code, not unsupported-format: the client words errors
		// from the code, and this refusal must never read as a codec
		// gap somebody could configure away.
		if KindOf(err) != KindDRM {
			t.Fatalf("%s errored %v (kind %q), want drm-protected", name, err, KindOf(err))
		}
		// The sentence still says why, for a log reader and for any
		// client that does not know the code yet.
		if !strings.Contains(err.Error(), "DRM") {
			t.Fatalf("%s was refused without naming DRM: %v", name, err)
		}
	}

	if _, err := openSession(ctx, svc, uc, "album.flac", 4096); err != nil {
		t.Fatalf("a flac was refused by the default set: %v", err)
	}
}

func TestDRMDenyListWinsOverAWidenedFormatSet(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := uploadFixtureFormats(t, []string{"flac", "aax"})
	svc.stagingFree = func(string) (int64, bool) { return 1 << 62, true }

	if e := openSessionErr(ctx, svc, uc, "book.aax", 4096); KindOf(e) != KindDRM {
		t.Fatalf("an operator listing aax still gets it refused as DRM; got %v (kind %q)", e, KindOf(e))
	}
	if _, err := openSession(ctx, svc, uc, "album.flac", 4096); err != nil {
		t.Fatalf("a listed format was refused: %v", err)
	}
	// The operator's set replaces the default rather than extending it,
	// which is the property that makes the deny-list necessary at all.
	if e := openSessionErr(ctx, svc, uc, "single.mp3", 4096); KindOf(e) != KindFormat {
		t.Fatalf("an unlisted format errored %v (kind %q), want unsupported-format", e, KindOf(e))
	}
}

// The health payload's format sets come from these accessors, so what
// they report is what pickers filter with: the operator's replacement
// set when one is configured, normalized and sorted; the DRM deny-list
// regardless - and subtracted from the accepted set, because the gate
// refuses those files whatever the operator listed.
func TestUploadFormatsReporting(t *testing.T) {
	t.Parallel()
	custom := &Library{}
	custom.setUploadFormats([]string{" .WV", "Ape"})
	if got := custom.UploadFormats(); !slices.Equal(got, []string{"ape", "wv"}) {
		t.Fatalf("custom UploadFormats() = %v", got)
	}
	if got := custom.RejectedFormats(); !slices.Equal(got, []string{"aax", "aaxc"}) {
		t.Fatalf("RejectedFormats() = %v", got)
	}
	widened := &Library{}
	widened.setUploadFormats([]string{"aax", "flac"})
	if got := widened.UploadFormats(); !slices.Equal(got, []string{"flac"}) {
		t.Fatalf("a widened set must not report deny-listed formats as accepted; got %v", got)
	}
	def := &Library{}
	def.setUploadFormats(nil)
	if got := def.UploadFormats(); len(got) != 13 || !slices.Contains(got, "flac") || !slices.IsSorted(got) {
		t.Fatalf("default UploadFormats() = %v", got)
	}
}
