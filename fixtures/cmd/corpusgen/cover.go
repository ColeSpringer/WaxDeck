package main

import (
	"bytes"
	"image"
	"image/color"
	"image/png"
	"os"
	"path/filepath"
)

// coverSize is the edge of a synthesized cover in pixels. Real album art
// runs a few hundred pixels square upward, and the server's cost here is
// a decode plus a resize per requested rung, which scales with pixel
// count and not with file size — so an honest measurement needs a
// realistic edge rather than a thumbnail.
const coverSize = 600

// writeCover synthesizes an album cover and writes it as cover.png, one
// of the names WaxBin's scanner recognizes as folder art.
//
// Pure Go, per repo policy: no vendored image and no external tool. The
// output is a deterministic function of index, and distinct for every
// index, which is the property the whole exercise rests on — artwork is
// addressed by content hash, so a corpus sharing one cover would share
// one cache entry and report a render cost 1000 albums lighter than a
// real library's.
func writeCover(dir string, index int) error {
	var buf bytes.Buffer
	enc := png.Encoder{CompressionLevel: png.BestSpeed}
	if err := enc.Encode(&buf, coverImage(index)); err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(dir, "cover.png"), buf.Bytes(), 0o644)
}

// coverImage draws the cover for index: a two-tone diagonal wash under a
// coarse block pattern carrying the index's own bits, plus a fine
// deterministic grain.
//
// The grain is not decoration. A flat synthetic image compresses to
// almost nothing and decodes far faster than a photograph, which would
// understate exactly what this corpus exists to measure; texture puts
// the file size and the decode in the neighbourhood of a real scan.
func coverImage(index int) image.Image {
	img := image.NewRGBA(image.Rect(0, 0, coverSize, coverSize))
	near, far := coverPalette(index)
	const cells = 8
	cell := coverSize / cells
	// One well-mixed bit per cell of the grid. Multiplying by the golden
	// ratio in 64 bits spreads consecutive indices apart, so albums that
	// sit next to each other in a scrolled grid do not read as near
	// variations of one image. index+1 because index 0 would otherwise
	// be the one album with no pattern at all.
	pattern := uint64(index+1) * 0x9E3779B97F4A7C15
	for y := 0; y < coverSize; y++ {
		for x := 0; x < coverSize; x++ {
			// The wash: near colour at the top left, far at the bottom
			// right.
			t := (x + y) * 255 / (2 * coverSize)
			r := int(near.R) + (int(far.R)-int(near.R))*t/255
			g := int(near.G) + (int(far.G)-int(near.G))*t/255
			b := int(near.B) + (int(far.B)-int(near.B))*t/255
			if bit := (y/cell)*cells + (x / cell); pattern>>(bit&63)&1 == 1 {
				r, g, b = 255-r, 255-g, 255-b
			}
			// The grain: a cheap deterministic hash of the pixel.
			n := (x*73856093 ^ y*19349663 ^ index*83492791) % 12
			img.SetRGBA(x, y, color.RGBA{
				R: clamp8(r + n),
				G: clamp8(g + n),
				B: clamp8(b + n),
				A: 255,
			})
		}
	}
	return img
}

// coverPalette picks the two ends of an album's wash. The index walks a
// coarse hue wheel so neighbouring albums in a scrolled grid do not all
// read as the same colour.
func coverPalette(index int) (near, far color.RGBA) {
	hue := (index * 37) % 360
	return hueColor(hue, 90), hueColor((hue+140)%360, 40)
}

// hueColor is a hue at full saturation, scaled to value (0..100). Enough
// colour arithmetic for a fixture; nothing here needs a colour library.
func hueColor(hue, value int) color.RGBA {
	region := hue / 60
	rem := hue % 60
	high := value * 255 / 100
	rise := rem * high / 60
	fall := high - rise
	switch region {
	case 0:
		return color.RGBA{R: uint8(high), G: uint8(rise), A: 255}
	case 1:
		return color.RGBA{R: uint8(fall), G: uint8(high), A: 255}
	case 2:
		return color.RGBA{G: uint8(high), B: uint8(rise), A: 255}
	case 3:
		return color.RGBA{G: uint8(fall), B: uint8(high), A: 255}
	case 4:
		return color.RGBA{R: uint8(rise), B: uint8(high), A: 255}
	default:
		return color.RGBA{R: uint8(high), B: uint8(fall), A: 255}
	}
}

func clamp8(v int) uint8 {
	if v < 0 {
		return 0
	}
	if v > 255 {
		return 255
	}
	return uint8(v)
}
