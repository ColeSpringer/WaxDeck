package fixtures

import (
	"bytes"
	"fmt"
	"image"
	"image/color"
	"os"
	"path/filepath"

	"golang.org/x/image/tiff"
)

// Cover art the artwork surfaces are tested against, synthesized here
// for the same reason the audio is: no binary media in the repository,
// and a generator says what the bytes are instead of a file asking to be
// trusted.

// ExoticCoverWidth and ExoticCoverHeight are what a test asserts the
// catalog measured. Not square, so a cover reported as 240 x 180 proves
// the dimensions were read rather than guessed from one number.
const (
	ExoticCoverWidth  = 240
	ExoticCoverHeight = 180
)

// ExoticCoverName is the file GenerateExoticCover writes. The extension
// is what a picker filters on, so it has to be one the app offers.
const ExoticCoverName = "sleeve.tiff"

// GenerateExoticCover writes a TIFF cover into dir and returns its path.
//
// TIFF is the useful format to test with: it is the one the catalog
// decodes and the Go standard library does not, so a cover that reaches
// the slot measured proves the artwork guard asked the catalog's own
// recognizer rather than http.DetectContentType.
func GenerateExoticCover(dir string) (string, error) {
	img := image.NewRGBA(image.Rect(0, 0, ExoticCoverWidth, ExoticCoverHeight))
	for x := 0; x < ExoticCoverWidth; x++ {
		for y := 0; y < ExoticCoverHeight; y++ {
			img.Set(x, y, color.RGBA{R: uint8(x), G: uint8(y), B: 160, A: 255})
		}
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", fmt.Errorf("fixtures: cover directory: %w", err)
	}
	// Encoded whole and written once, like every other fixture: a
	// streamed encode reports its last error at Close, and a deferred
	// Close that drops it hands back a truncated file with a nil error.
	var buf bytes.Buffer
	if err := tiff.Encode(&buf, img, nil); err != nil {
		return "", fmt.Errorf("fixtures: encoding cover: %w", err)
	}
	path := filepath.Join(dir, ExoticCoverName)
	if err := os.WriteFile(path, buf.Bytes(), 0o644); err != nil {
		return "", fmt.Errorf("fixtures: writing cover: %w", err)
	}
	return path, nil
}
