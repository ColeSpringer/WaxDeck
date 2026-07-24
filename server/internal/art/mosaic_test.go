package art

import (
	"bytes"
	"encoding/binary"
	"hash/crc32"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"testing"
)

// solid encodes a w x h PNG of one color, standing in for a cover.
func solid(t *testing.T, w, h int, c color.RGBA) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for y := range h {
		for x := range w {
			img.Set(x, y, c)
		}
	}
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

var (
	red   = color.RGBA{220, 30, 30, 255}
	green = color.RGBA{30, 200, 30, 255}
	blue  = color.RGBA{30, 30, 220, 255}
	white = color.RGBA{245, 245, 245, 255}
)

// nearest reports whether c is closer to want than to any of others.
func nearest(c color.Color, want color.RGBA, others ...color.RGBA) bool {
	dist := func(a color.RGBA) int {
		r, g, b, _ := c.RGBA()
		dr, dg, db := int(r>>8)-int(a.R), int(g>>8)-int(a.G), int(b>>8)-int(a.B)
		return dr*dr + dg*dg + db*db
	}
	best := dist(want)
	for _, o := range others {
		if dist(o) < best {
			return false
		}
	}
	return true
}

// TestMosaicQuadrants pins the layout: source order fills the grid left
// to right, top to bottom, so the caller's "first four distinct covers"
// order is what a viewer sees.
func TestMosaicQuadrants(t *testing.T) {
	out, err := Mosaic([][]byte{
		solid(t, 300, 300, red),
		solid(t, 300, 300, green),
		solid(t, 300, 300, blue),
		solid(t, 300, 300, white),
	}, 400)
	if err != nil {
		t.Fatalf("Mosaic: %v", err)
	}
	img, err := jpeg.Decode(bytes.NewReader(out))
	if err != nil {
		t.Fatalf("the mosaic is not decodable JPEG: %v", err)
	}
	b := img.Bounds()
	if b.Dx() != 400 || b.Dy() != 400 {
		t.Fatalf("size = %dx%d, want 400x400", b.Dx(), b.Dy())
	}
	// Sample well inside each quadrant, away from the scaler's seams.
	corners := []struct {
		name   string
		x, y   int
		want   color.RGBA
		others []color.RGBA
	}{
		{"top left", 100, 100, red, []color.RGBA{green, blue, white}},
		{"top right", 300, 100, green, []color.RGBA{red, blue, white}},
		{"bottom left", 100, 300, blue, []color.RGBA{red, green, white}},
		{"bottom right", 300, 300, white, []color.RGBA{red, green, blue}},
	}
	for _, c := range corners {
		if !nearest(img.At(c.x, c.y), c.want, c.others...) {
			t.Errorf("%s quadrant = %v, want the %v source", c.name, img.At(c.x, c.y), c.want)
		}
	}
}

// TestMosaicCropsToSquare covers the non-square cover: a wide single or
// a tall book fills its quadrant from the middle rather than
// letterboxing, so the grid has no gaps.
func TestMosaicCropsToSquare(t *testing.T) {
	wide := image.NewRGBA(image.Rect(0, 0, 600, 200))
	for y := range 200 {
		for x := range 600 {
			// Red band down the middle third, blue at both ends: a
			// center crop keeps only the red.
			if x >= 200 && x < 400 {
				wide.Set(x, y, red)
			} else {
				wide.Set(x, y, blue)
			}
		}
	}
	var buf bytes.Buffer
	if err := png.Encode(&buf, wide); err != nil {
		t.Fatal(err)
	}
	out, err := Mosaic([][]byte{
		buf.Bytes(), buf.Bytes(), buf.Bytes(), buf.Bytes(),
	}, 200)
	if err != nil {
		t.Fatalf("Mosaic: %v", err)
	}
	img, err := jpeg.Decode(bytes.NewReader(out))
	if err != nil {
		t.Fatal(err)
	}
	if !nearest(img.At(50, 50), red, blue) {
		t.Errorf("top left = %v, want the center crop's red, not the edges' blue", img.At(50, 50))
	}
}

// TestMosaicRejectsWrongCount keeps the layout honest: three covers is
// a presentation decision for the caller, not a grid with a hole in it.
func TestMosaicRejectsWrongCount(t *testing.T) {
	one := solid(t, 100, 100, red)
	for _, n := range []int{0, 1, 3, 5} {
		srcs := make([][]byte, n)
		for i := range srcs {
			srcs[i] = one
		}
		if _, err := Mosaic(srcs, 200); err == nil {
			t.Errorf("Mosaic with %d sources = nil error, want a refusal", n)
		}
	}
}

// TestMosaicRejectsUndecodableSource keeps a corrupt stored cover from
// producing a half-drawn tile.
func TestMosaicRejectsUndecodableSource(t *testing.T) {
	good := solid(t, 100, 100, red)
	_, err := Mosaic([][]byte{good, good, good, []byte("not an image")}, 200)
	if err == nil {
		t.Fatal("Mosaic accepted an undecodable source")
	}
}

// TestMosaicOddSize covers the seam an odd canvas would leave between
// quadrants: the tile rounds up and the canvas follows it.
func TestMosaicOddSize(t *testing.T) {
	one := solid(t, 64, 64, red)
	out, err := Mosaic([][]byte{one, one, one, one}, 301)
	if err != nil {
		t.Fatalf("Mosaic: %v", err)
	}
	img, err := jpeg.Decode(bytes.NewReader(out))
	if err != nil {
		t.Fatal(err)
	}
	if b := img.Bounds(); b.Dx() != b.Dy() || b.Dx()%2 != 0 {
		t.Errorf("size = %dx%d, want an even square with no seam", b.Dx(), b.Dy())
	}
}

// pngWithDeclaredSize forges a PNG header claiming w x h pixels. Only
// the IHDR is read by image.DecodeConfig, which is the whole point: a
// few bytes on the wire can claim gigapixels, so the budget has to be
// enforced from the header rather than from the byte count.
func pngWithDeclaredSize(t *testing.T, w, h uint32) []byte {
	t.Helper()
	raw := solid(t, 1, 1, red)
	// PNG layout: 8-byte signature, then the IHDR chunk as
	// length(4) type(4) width(4) height(4) ... crc(4).
	const ihdrStart = 8
	const dataStart = ihdrStart + 8
	out := append([]byte(nil), raw...)
	binary.BigEndian.PutUint32(out[dataStart:], w)
	binary.BigEndian.PutUint32(out[dataStart+4:], h)
	// The CRC covers the chunk type and its data (13 bytes for IHDR).
	sum := crc32.ChecksumIEEE(out[ihdrStart+4 : dataStart+13])
	binary.BigEndian.PutUint32(out[dataStart+13:], sum)
	return out
}

// TestUsableRejectsOversizedSource is the decompression-bomb guard:
// compressed bytes say nothing about decoded size, and compositing now
// runs from an ordinary read path.
func TestUsableRejectsOversizedSource(t *testing.T) {
	if !Usable(solid(t, 64, 64, red)) {
		t.Error("a plain 64x64 cover should be usable")
	}
	if Usable(pngWithDeclaredSize(t, 40000, 40000)) {
		t.Error("a header claiming 1.6 gigapixels should be refused")
	}
	if Usable([]byte("not an image")) {
		t.Error("undecodable bytes should be refused")
	}
}

// TestMosaicRefusesOversizedSource keeps the budget on the primitive
// itself, not only on the filter callers are asked to use.
func TestMosaicRefusesOversizedSource(t *testing.T) {
	good := solid(t, 64, 64, red)
	huge := pngWithDeclaredSize(t, 40000, 40000)
	if _, err := Mosaic([][]byte{good, good, good, huge}, 200); err == nil {
		t.Fatal("Mosaic accepted a source over the pixel budget")
	}
}

// TestMosaicCompositesAlphaOverWhite covers the ground the canvas has to
// provide: a zero RGBA canvas is transparent black and Go's RGBA is
// premultiplied, so transparency would darken toward black and then lose
// the alpha channel entirely at the JPEG encode.
func TestMosaicCompositesAlphaOverWhite(t *testing.T) {
	clear := image.NewRGBA(image.Rect(0, 0, 64, 64)) // fully transparent
	var buf bytes.Buffer
	if err := png.Encode(&buf, clear); err != nil {
		t.Fatal(err)
	}
	transparent := buf.Bytes()
	out, err := Mosaic([][]byte{
		transparent, solid(t, 64, 64, red), solid(t, 64, 64, red), solid(t, 64, 64, red),
	}, 200)
	if err != nil {
		t.Fatalf("Mosaic: %v", err)
	}
	img, err := jpeg.Decode(bytes.NewReader(out))
	if err != nil {
		t.Fatal(err)
	}
	r, g, b, _ := img.At(50, 50).RGBA()
	if r>>8 < 200 || g>>8 < 200 || b>>8 < 200 {
		t.Errorf("transparent tile = (%d,%d,%d), want near white, not blended toward black",
			r>>8, g>>8, b>>8)
	}
}
