// Package art composites cover images. The catalog owns art storage,
// thumbnails, and the resolve chain; what it has no notion of is a
// cover assembled from several others, which is what a playlist (and
// later a genre, decade, or entity shelf) needs when it has no cover of
// its own.
package art

import (
	"bytes"
	"errors"
	"fmt"
	"image"
	"image/color"
	"image/draw"
	"image/jpeg"

	// Decoders for the formats the catalog stores. Registering them here
	// keeps the format list in one place; the encoder is always JPEG.
	_ "image/gif"
	_ "image/jpeg"
	_ "image/png"

	xdraw "golang.org/x/image/draw"
	_ "golang.org/x/image/webp"
)

// MosaicTiles is how many sources a mosaic takes. Four is the layout,
// not a maximum: the grid is 2x2 and every quadrant is filled. A caller
// with fewer distinct covers shows one of them rather than tiling a
// gap, which is a presentation decision and not this package's.
const MosaicTiles = 4

// mosaicQuality is the JPEG quality of the composited cover. The tiles
// are already lossy source art scaled down, so the quantization ceiling
// is the sources, not this number; 88 keeps ringing off the seams
// without doubling the bytes.
const mosaicQuality = 88

// MaxSourcePixels caps one source image's decoded area. Compressed
// bytes say nothing about decoded size -- a few megabytes of PNG expand
// to gigabytes of pixels -- and compositing now runs from ordinary read
// paths, so the budget is enforced from the header before any allocation.
// 16 megapixels is four times the largest cover art in circulation and
// still bounds one decode at roughly 64 MB.
const MaxSourcePixels = 16 << 20

// Usable reports whether raw decodes as an image within the pixel
// budget, reading only the header. Callers use it to filter candidates
// before handing four of them to Mosaic, so one unreadable or oversized
// stored cover costs a skipped tile rather than the whole composite.
func Usable(raw []byte) bool {
	cfg, _, err := image.DecodeConfig(bytes.NewReader(raw))
	if err != nil {
		return false
	}
	return withinBudget(cfg.Width, cfg.Height)
}

func withinBudget(w, h int) bool {
	return w > 0 && h > 0 && int64(w)*int64(h) <= MaxSourcePixels
}

// Mosaic tiles four cover images into one square JPEG of size pixels a
// side. Each source is center-cropped to a square and scaled into its
// quadrant, so covers that are not square (a wide single, a tall book)
// fill their tile instead of letterboxing it.
//
// The sources are decoded here rather than taken as image.Image so
// callers can hand over the bytes the catalog gave them; every format
// the catalog stores is registered above. A source outside
// MaxSourcePixels is refused rather than decoded (see Usable, which
// callers should filter with first).
func Mosaic(sources [][]byte, size int) ([]byte, error) {
	if len(sources) != MosaicTiles {
		return nil, fmt.Errorf("art: a mosaic takes exactly %d sources, got %d", MosaicTiles, len(sources))
	}
	if size <= 0 {
		return nil, errors.New("art: mosaic size must be positive")
	}
	// An odd size would leave a one-pixel seam between quadrants, so the
	// tile is the half rounded up and the canvas follows it.
	tile := (size + 1) / 2
	canvas := image.NewRGBA(image.Rect(0, 0, tile*2, tile*2))
	// Opaque white ground. A zero RGBA canvas is transparent black, and
	// Go's RGBA is premultiplied, so a source with alpha composited over
	// it darkens toward black and then loses the alpha channel entirely
	// at the JPEG encode. White is what a viewer shows transparency as.
	draw.Draw(canvas, canvas.Bounds(), image.NewUniform(color.White), image.Point{}, draw.Src)
	for i, raw := range sources {
		cfg, _, err := image.DecodeConfig(bytes.NewReader(raw))
		if err != nil {
			return nil, fmt.Errorf("art: reading mosaic source %d: %w", i, err)
		}
		if !withinBudget(cfg.Width, cfg.Height) {
			return nil, fmt.Errorf("art: mosaic source %d is %dx%d, over the %d-pixel budget",
				i, cfg.Width, cfg.Height, MaxSourcePixels)
		}
		src, _, err := image.Decode(bytes.NewReader(raw))
		if err != nil {
			return nil, fmt.Errorf("art: decoding mosaic source %d: %w", i, err)
		}
		dst := image.Rect(
			(i%2)*tile, (i/2)*tile,
			(i%2)*tile+tile, (i/2)*tile+tile,
		)
		// CatmullRom over the cheaper kernels: this runs once per cover
		// change, never per request, and the output is a stored asset that
		// every later thumbnail is derived from.
		xdraw.CatmullRom.Scale(canvas, dst, src, squareCrop(src), draw.Over, nil)
	}
	var out bytes.Buffer
	if err := jpeg.Encode(&out, canvas, &jpeg.Options{Quality: mosaicQuality}); err != nil {
		return nil, fmt.Errorf("art: encoding mosaic: %w", err)
	}
	return out.Bytes(), nil
}

// squareCrop returns the largest centered square inside an image's
// bounds.
func squareCrop(src image.Image) image.Rectangle {
	b := src.Bounds()
	side := min(b.Dx(), b.Dy())
	x := b.Min.X + (b.Dx()-side)/2
	y := b.Min.Y + (b.Dy()-side)/2
	return image.Rect(x, y, x+side, y+side)
}
