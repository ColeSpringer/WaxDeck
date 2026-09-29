package service

import (
	"encoding/binary"
	"testing"

	"github.com/colespringer/waxbin/model"
)

// peaksOf builds a stored envelope whose every bucket carries the same
// full-scale amplitude, which is what makes a stitch readable: an
// output bucket's value names the part it came from.
func peaksOf(buckets int, level uint16) model.PeaksData {
	data := make([]byte, buckets*2)
	for i := range buckets {
		binary.LittleEndian.PutUint16(data[i*2:], level)
	}
	return model.PeaksData{Version: 1, Buckets: buckets, Data: data}
}

func part(pid string, durationMS int64) model.BookPart {
	return model.BookPart{FilePID: model.PID(pid), DurationMS: durationMS}
}

func TestWholeItemBuckets(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name  string
		msecs int64
		want  int
	}{
		// A short book still gets a track's worth of detail rather than
		// six bars.
		{"a two-minute reading", 2 * 60 * 1000, 1000},
		// One bucket per ten seconds through the middle, which is what
		// keeps a chapter a shape.
		{"five hours", 5 * 60 * 60 * 1000, 1800},
		// And a ceiling, so the response stays a few kilobytes however
		// long the book is.
		{"forty hours", 40 * 60 * 60 * 1000, 4000},
	}
	for _, tc := range cases {
		if got := wholeItemBuckets(tc.msecs); got != tc.want {
			t.Errorf("%s: buckets = %d, want %d", tc.name, got, tc.want)
		}
	}
}

// The property the whole feature rests on: a part occupies bucket-space
// in proportion to its length on the book's timeline, which is what the
// player places it by, not to how many buckets it stored or how long its
// audio decoded to. One part's header says three times the other's.
func TestStitchWeightsPartsByDuration(t *testing.T) {
	t.Parallel()
	parts := []model.BookPart{part("fl-1", 90_000), part("fl-2", 30_000)}
	stored := map[string]model.PeaksData{
		"fl-1": peaksOf(1000, 0x4000),
		"fl-2": peaksOf(1000, 0xC000),
	}
	for pid, pk := range stored {
		pk.Frames, pk.SampleRate = 30_000, 1000
		stored[pid] = pk
	}

	out := stitchPeaks(parts, stored, 120_000, 100)
	if len(out) != 100 {
		t.Fatalf("stitched %d buckets, want 100", len(out))
	}
	// Three quarters of the timeline is the first part, and the wire
	// carries the high byte of each stored value.
	for i, v := range out {
		want := byte(0x40)
		if i >= 75 {
			want = byte(0xC0)
		}
		if v != want {
			t.Fatalf("bucket %d = %#x, want %#x (the boundary is at 75)", i, v, want)
		}
	}
}

// Loudest-wins, and it is truthful because the stored values are
// absolute full-scale amplitude with no per-file normalisation: a quiet
// part has to stay quiet beside a loud one, or a whole-book envelope is
// a lie about the book.
func TestStitchKeepsPartsOnOneScale(t *testing.T) {
	t.Parallel()
	parts := []model.BookPart{part("fl-1", 60_000), part("fl-2", 60_000)}
	stored := map[string]model.PeaksData{
		"fl-1": peaksOf(4, 0x1000),
		"fl-2": peaksOf(4, 0xF000),
	}

	out := stitchPeaks(parts, stored, 120_000, 8)
	for i := range 4 {
		if out[i] != 0x10 {
			t.Fatalf("quiet part bucket %d = %#x, want %#x - the stitch rescaled it", i, out[i], 0x10)
		}
	}
	for i := 4; i < 8; i++ {
		if out[i] != 0xF0 {
			t.Fatalf("loud part bucket %d = %#x, want %#x", i, out[i], 0xF0)
		}
	}
}

// Downsampling takes the maximum rather than the first or the mean: a
// transient inside a bucket is what a waveform is for.
func TestStitchTakesTheLoudestInputBucket(t *testing.T) {
	t.Parallel()
	data := make([]byte, 4*2)
	for i, v := range []uint16{0x0100, 0x9000, 0x0200, 0x0300} {
		binary.LittleEndian.PutUint16(data[i*2:], v)
	}
	parts := []model.BookPart{part("fl-1", 1000)}
	stored := map[string]model.PeaksData{
		"fl-1": {Version: 1, Buckets: 4, Data: data},
	}

	out := stitchPeaks(parts, stored, 1000, 1)
	if out[0] != 0x90 {
		t.Fatalf("bucket = %#x, want %#x: the peak inside it was dropped", out[0], 0x90)
	}
}

// A part shorter than one output bucket still gets a bucket. Rounding
// it away would silence real audio, and silence is the one thing a
// scrubber must not invent.
func TestStitchKeepsAPartShorterThanABucket(t *testing.T) {
	t.Parallel()
	parts := []model.BookPart{
		part("fl-1", 100_000),
		part("fl-2", 500),
		part("fl-3", 100_000),
	}
	stored := map[string]model.PeaksData{
		"fl-1": peaksOf(10, 0x2000),
		"fl-2": peaksOf(10, 0xE000),
		"fl-3": peaksOf(10, 0x2000),
	}

	out := stitchPeaks(parts, stored, 200_500, 10)
	var loud int
	for _, v := range out {
		if v == 0xE0 {
			loud++
		}
	}
	if loud != 1 {
		t.Fatalf("the half-second part occupies %d buckets, want exactly 1", loud)
	}
}

// Every bucket belongs to some part: no gap between two parts, and
// nothing past the end.
func TestStitchLeavesNoGapBetweenParts(t *testing.T) {
	t.Parallel()
	parts := []model.BookPart{
		part("fl-1", 37_000),
		part("fl-2", 41_000),
		part("fl-3", 22_000),
	}
	stored := map[string]model.PeaksData{
		"fl-1": peaksOf(7, 0x1100),
		"fl-2": peaksOf(13, 0x2200),
		"fl-3": peaksOf(3, 0x3300),
	}

	out := stitchPeaks(parts, stored, 100_000, 997)
	for i, v := range out {
		if v == 0 {
			t.Fatalf("bucket %d is silent, but every part carries signal", i)
		}
	}
}

// The validator has to move with everything the picture is built from,
// and stay short enough to survive the round trip that uses it.
func TestWholeItemValidatorFollowsEveryDependency(t *testing.T) {
	parts := []model.BookPart{part("fl-1", 60_000), part("fl-2", 60_000)}
	essence := []string{"aaaa", "bbbb"}
	versions := []int{1, 1}
	base := wholeItemValidator(parts, essence, versions, 1000)

	// A re-analysed part.
	if got := wholeItemValidator(parts, []string{"aaaa", "cccc"}, versions, 1000); got == base {
		t.Fatal("a part's new essence left the validator unchanged")
	}
	// The same parts in the other order.
	if got := wholeItemValidator(parts, []string{"bbbb", "aaaa"}, versions, 1000); got == base {
		t.Fatal("re-ordering the book left the validator unchanged")
	}
	// A rescan that corrects a lying header: same essence, same
	// analysis, every bucket redrawn.
	longer := []model.BookPart{part("fl-1", 60_000), part("fl-2", 90_000)}
	if got := wholeItemValidator(longer, essence, versions, 1000); got == base {
		t.Fatal("a corrected part duration left the validator unchanged")
	}
	// One part re-analysed under a newer version while another already
	// held it, so the highest version is the same.
	if wholeItemValidator(parts, essence, []int{2, 1}, 1000) == wholeItemValidator(parts, essence, []int{2, 2}, 1000) {
		t.Fatal("a part's new analysis version left the validator unchanged")
	}
	// A different resolution over the same audio.
	if got := wholeItemValidator(parts, essence, versions, 1200); got == base {
		t.Fatal("a different bucket count left the validator unchanged")
	}

	// Fixed length whatever the book's size, which is the half that
	// keeps a conditional request inside a proxy's header buffers.
	many := make([]model.BookPart, 0, 200)
	longEssence := make([]string, 0, 200)
	manyVersions := make([]int, 0, 200)
	for i := range 200 {
		many = append(many, part("fl-"+string(rune('a'+i%26)), 60_000))
		longEssence = append(longEssence, "sha256-0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")
		manyVersions = append(manyVersions, 1)
	}
	if got := wholeItemValidator(many, longEssence, manyVersions, 4000); len(got) != 32 {
		t.Fatalf("a 200-part validator is %d chars, want a fixed 32", len(got))
	}
}
