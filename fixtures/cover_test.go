package fixtures

import (
	"bytes"
	"image"
	"os"
	"path/filepath"
	"testing"

	_ "golang.org/x/image/tiff"
)

// The cover is what the artwork surfaces assert against, so its
// dimensions and its format are the fixture's contract: a spec reads
// "tiff, 240 x 180" off the screen and off the catalog.
func TestExoticCoverIsATiffOfTheDeclaredSize(t *testing.T) {
	dir := t.TempDir()
	path, err := GenerateExoticCover(dir)
	if err != nil {
		t.Fatal(err)
	}
	if filepath.Base(path) != ExoticCoverName {
		t.Fatalf("wrote %q, want %q", filepath.Base(path), ExoticCoverName)
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	cfg, format, err := image.DecodeConfig(bytes.NewReader(raw))
	if err != nil {
		t.Fatal(err)
	}
	if format != "tiff" {
		t.Errorf("format = %q, want tiff", format)
	}
	if cfg.Width != ExoticCoverWidth || cfg.Height != ExoticCoverHeight {
		t.Errorf("size = %dx%d, want %dx%d",
			cfg.Width, cfg.Height, ExoticCoverWidth, ExoticCoverHeight)
	}
}
