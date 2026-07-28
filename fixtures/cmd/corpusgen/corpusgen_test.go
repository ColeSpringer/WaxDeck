package main

import (
	"bytes"
	"crypto/sha256"
	"image"
	"image/png"
	"os"
	"path/filepath"
	"testing"

	"github.com/colespringer/waxbin/model"
)

func TestRunWritesOneDirectoryPerAlbum(t *testing.T) {
	out := t.TempDir()
	if err := run(out, 12, 4, true); err != nil {
		t.Fatal(err)
	}

	entries, err := os.ReadDir(out)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 3 {
		t.Fatalf("albums = %d, want 3", len(entries))
	}
	for _, entry := range entries {
		if !entry.IsDir() {
			t.Fatalf("%s is not a directory; the corpus is per-album now", entry.Name())
		}
		dir := filepath.Join(out, entry.Name())
		for _, want := range []string{entry.Name() + ".flac", entry.Name() + ".cue", "cover.png"} {
			if _, err := os.Stat(filepath.Join(dir, want)); err != nil {
				t.Errorf("%s: %v", filepath.Join(entry.Name(), want), err)
			}
		}
	}
}

func TestCoverIsAFolderArtNameTheScannerKnows(t *testing.T) {
	// The whole point of writing cover.png is that WaxBin's scanner
	// discovers it; a rename that fell off the registry would leave a
	// corpus that measures a library with no artwork again.
	for _, name := range model.CoverArtNames {
		if name == "cover.png" {
			return
		}
	}
	t.Fatal("cover.png is not in model.CoverArtNames")
}

func TestCoversAreDistinctPerAlbum(t *testing.T) {
	// Artwork is addressed by content hash. Covers that repeat would
	// share one cache entry and one render, and the gate would report a
	// cost a thousand albums lighter than a real library's. Hashed as
	// pixels rather than as encoded PNGs: the encoder is not what is
	// under test here, and a full corpus of encodes is slow enough to be
	// its own reason not to run this.
	seen := map[[32]byte]int{}
	for i := 0; i < 1000; i++ {
		img, ok := coverImage(i).(*image.RGBA)
		if !ok {
			t.Fatalf("cover %d is not an RGBA image", i)
		}
		sum := sha256.Sum256(img.Pix)
		if prev, dup := seen[sum]; dup {
			t.Fatalf("cover %d is pixel-identical to cover %d", i, prev)
		}
		seen[sum] = i
	}
}

func TestCoverIsDeterministic(t *testing.T) {
	// A corpus regenerated between two measurement runs has to be the
	// same corpus, or the numbers are not comparable. Through the real
	// write path, so the encoder is covered too.
	first, second := t.TempDir(), t.TempDir()
	if err := writeCover(first, 41); err != nil {
		t.Fatal(err)
	}
	if err := writeCover(second, 41); err != nil {
		t.Fatal(err)
	}
	a, err := os.ReadFile(filepath.Join(first, "cover.png"))
	if err != nil {
		t.Fatal(err)
	}
	b, err := os.ReadFile(filepath.Join(second, "cover.png"))
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(a, b) {
		t.Fatal("the same index wrote two different covers")
	}
}

func TestCoverDecodesAtTheDeclaredSize(t *testing.T) {
	out := t.TempDir()
	if err := writeCover(out, 7); err != nil {
		t.Fatal(err)
	}
	f, err := os.Open(filepath.Join(out, "cover.png"))
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	cfg, err := png.DecodeConfig(f)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Width != coverSize || cfg.Height != coverSize {
		t.Fatalf("cover is %dx%d, want %dx%d", cfg.Width, cfg.Height, coverSize, coverSize)
	}
}

func TestCoversCanBeSkipped(t *testing.T) {
	// The comparison the web perf gate's open question wants: the same
	// corpus with and without artwork.
	out := t.TempDir()
	if err := run(out, 4, 4, false); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(out, "album00000", "cover.png")); !os.IsNotExist(err) {
		t.Fatalf("cover.png exists with -covers=false (err = %v)", err)
	}
}

func TestCueSitsBesideItsAudio(t *testing.T) {
	// A cue's FILE reference resolves relative to the cue sheet, so the
	// move into subdirectories only works because both moved together.
	out := t.TempDir()
	if err := run(out, 4, 4, true); err != nil {
		t.Fatal(err)
	}
	cue, err := os.ReadFile(filepath.Join(out, "album00000", "album00000.cue"))
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Contains(cue, []byte(`FILE "album00000.flac" WAVE`)) {
		t.Fatalf("cue does not name its sibling audio:\n%s", cue)
	}
}
