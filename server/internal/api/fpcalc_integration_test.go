package api

import (
	"errors"
	"io/fs"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxdeck/server/internal/service"
	"github.com/colespringer/waxdeck/server/internal/testfpcalc"
)

// An upload keeps its file's own length when fpcalc cannot read the
// file: the review unit, and the matching that reads it, are not told
// the track is silent.
func TestUploadKeepsItsFileDurationWhenFpcalcFails(t *testing.T) {
	t.Parallel()
	failing := testfpcalc.Write(t, "", "ERROR: Could not open the input file", 2)
	h := newHarnessWith(t, func(cfg *service.Config) { cfg.FpcalcPath = failing })
	paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
		Name: "unreadable-to-fpcalc", Codec: fixtures.CodecFLAC, Duration: 3 * time.Second,
		Tags: map[string]string{"TITLE": "Long Enough", "ARTIST": "Meter Band"},
	})
	if err != nil {
		t.Fatal(err)
	}
	up := uploadFile(t, h, h.token, paths[0], "music", "")
	drainMatches(t, h)
	tracks := getReview(t, h, *up.ReviewEntryId).Tracks
	if len(tracks) != 1 || tracks[0].DurationMs < 2900 || tracks[0].DurationMs > 3100 {
		t.Fatalf("tracks = %+v, want the file's 3 s kept", tracks)
	}
}

// An upload the library holds byte for byte asks fpcalc for no raw
// fingerprint: that read only feeds the resolve the content match has
// already answered.
func TestAContentDuplicateUploadSkipsTheRawFingerprint(t *testing.T) {
	t.Parallel()
	bin, calls := testfpcalc.WriteLogging(t, "", "ERROR: Could not open the input file", 2)
	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.FpcalcPath = bin
		for i := range cfg.Roots {
			cfg.Roots[i].Managed = true
		}
	})
	paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
		Name: "alpha", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
		Tags: map[string]string{"TITLE": "Alpha Again", "ARTIST": "Someone Else"},
	})
	if err != nil {
		t.Fatal(err)
	}
	up := uploadFile(t, h, h.token, paths[0], "music", "")
	if up.Duplicate == nil || up.Duplicate.Kind != "content" {
		t.Fatalf("duplicate = %+v, want a content match", up.Duplicate)
	}
	runs, err := os.ReadFile(calls)
	if err != nil && !errors.Is(err, fs.ErrNotExist) {
		t.Fatal(err)
	}
	if !strings.Contains(string(runs), "-json") || strings.Contains(string(runs), "-raw") {
		t.Fatalf("fpcalc runs:\n%s\nwant the compressed read alone", runs)
	}
	// The same harness reads the raw form of audio the library lacks, so
	// the skip above is the duplicate's doing.
	fresh, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
		Name: "fresh", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
		Tags: map[string]string{"TITLE": "Fresh", "ARTIST": "Someone New"},
	})
	if err != nil {
		t.Fatal(err)
	}
	uploadFile(t, h, h.token, fresh[0], "music", "")
	if runs, err := os.ReadFile(calls); err != nil || !strings.Contains(string(runs), "-raw") {
		t.Fatalf("fpcalc runs after a new recording:\n%s (%v)\nwant its raw form read", runs, err)
	}
}
