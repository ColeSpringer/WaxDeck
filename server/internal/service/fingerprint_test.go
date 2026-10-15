package service

import (
	"path/filepath"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/testfpcalc"
)

// A read fpcalc ended in an error is kept when its fingerprint covers
// the span asked for, which is the file's own length capped at fpcalc's
// two minutes, and refused when it stops short or the length is unknown.
func TestFingerprintKeepsACoveringPartialRead(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newCatalogFixture(t)
	for _, c := range []struct {
		name     string
		stub     string
		expected time.Duration
		keep     bool
	}{
		{"a damaged frame past the span", testfpcalc.Write(t, testfpcalc.Compressed(300.4, 948), testfpcalc.DecodeNote, 3), 300 * time.Second, true},
		{"a read that stopped short", testfpcalc.Write(t, testfpcalc.Compressed(300.4, 300), testfpcalc.DecodeNote, 3), 300 * time.Second, false},
		{"an unknown length", testfpcalc.Write(t, testfpcalc.Compressed(300.4, 948), testfpcalc.DecodeNote, 3), 0, false},
		{"a clean run", testfpcalc.Write(t, testfpcalc.Compressed(300.4, 948), "", 0), 0, true},
	} {
		svc.fpcalcPath = c.stub
		fp, secs := svc.fingerprintFile(ctx, "/music/song.flac", c.expected)
		if got := fp != ""; got != c.keep {
			t.Errorf("%s: fingerprint kept = %v (%q), want %v", c.name, got, fp, c.keep)
		}
		if c.keep && secs != 300 {
			t.Errorf("%s: length = %d s, want fpcalc's 300", c.name, secs)
		}
	}
}

// The identify pipeline asks fpcalc with the length the review unit
// stored, so a file whose last frame is damaged still gets its
// fingerprint.
func TestMatchTracksKeepsAPartialFingerprint(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newCatalogFixture(t)
	svc.fpcalcPath = testfpcalc.Write(t, testfpcalc.Compressed(300.4, 948), testfpcalc.DecodeNote, 3)
	tracks := svc.matchTracks(ctx, []reviewTrackDoc{{Path: filepath.Join(t.TempDir(), "song.flac"), DurationMS: 300000}})
	if len(tracks) != 1 || tracks[0].Fingerprint == "" {
		t.Fatalf("tracks = %+v, want the partial read's fingerprint", tracks)
	}
}
