package service

import (
	"testing"

	"github.com/colespringer/waxbin/scan"
)

// Every split output has to land on a name the scanner picks up: the
// import that follows a split resolves the piece it just wrote, and a
// piece outside the audio-extension set resolves nothing, failing the
// whole job permanently after every piece has already been encoded.
// The format name is not always the extension - WavPack writes .wv -
// which is the trap this pins.
func TestToolSplitPiecesLandOnScannableNames(t *testing.T) {
	t.Parallel()
	for _, codec := range []string{
		"flac", "alac", "aac", "mp3", "opus", "wav", "wavpack", "ape", "musepack", "wma",
	} {
		format := toolSplitFormat(codec)
		for _, asBook := range []bool{false, true} {
			ext := toolSplitExt(format, asBook)
			if !scan.IsAudio("piece." + ext) {
				t.Errorf("codec %q splits to format %q, extension %q, which the scanner ignores",
					codec, format, ext)
			}
		}
	}
	// The two named exceptions, spelled out so a change to either is
	// deliberate rather than absorbed by the loop above.
	if got := toolSplitExt("wavpack", false); got != "wv" {
		t.Errorf("wavpack extension = %q, want wv", got)
	}
	if got := toolSplitExt("alac", true); got != "m4b" {
		t.Errorf("a book's alac extension = %q, want m4b", got)
	}
	if got := toolSplitExt("alac", false); got != "alac" {
		t.Errorf("a track's alac extension = %q, want the format's own", got)
	}
}
