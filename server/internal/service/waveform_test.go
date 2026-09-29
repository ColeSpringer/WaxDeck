package service

import "testing"

func TestWindowBuckets(t *testing.T) {
	t.Parallel()

	// 1000 buckets over 1000 s decoded at 44.1 kHz: 75 CD frames (one
	// second) a bucket.
	cases := []struct {
		name           string
		start, end     int64
		wantLo, wantHi int
	}{
		{"whole file", 0, 0, 0, 1000},
		{"closed window on bucket edges", 7500, 15000, 100, 200},
		{"a partial last bucket is kept", 7500, 15010, 100, 201},
		{"open end runs to the last bucket", 60000, 0, 800, 1000},
		{"a window inside one bucket is that bucket", 7520, 7530, 100, 101},
		{"an empty window still answers a bucket", 7500, 7500, 100, 101},
	}
	for _, c := range cases {
		lo, hi, ok := windowBuckets(1000, 44_100_000, 44100, c.start, c.end)
		if !ok || lo != c.wantLo || hi != c.wantHi {
			t.Errorf("%s: [%d, %d) = [%d, %d) %v, want [%d, %d)", c.name, c.start, c.end, lo, hi, ok, c.wantLo, c.wantHi)
		}
	}
}

// A rate 75 does not divide converts frames to samples multiplied first:
// 7274 frames at 32 kHz is sample 3103573, bucket 969 of 1000 over 100 s
// (960 dividing first, 968 at a truncated 426 samples a frame).
func TestAWindowAtAnUnevenRateIsPlacedToTheSample(t *testing.T) {
	t.Parallel()
	if lo, hi, ok := windowBuckets(1000, 3_200_000, 32000, 7274, 0); !ok || lo != 969 || hi != 1000 {
		t.Errorf("[7274, end) at 32 kHz = [%d, %d) %v, want [969, 1000)", lo, hi, ok)
	}
}

// A window that ends before it starts is no window, and one bucket drawn
// for it would be made up.
func TestAReversedWindowIsNotPlaced(t *testing.T) {
	t.Parallel()
	if lo, hi, ok := windowBuckets(1000, 44_100_000, 44100, 30000, 15000); ok {
		t.Errorf("placed the reversed window [30000, 15000) as [%d, %d)", lo, hi)
	}
}

// A window past the decoded audio cannot be drawn from it, and peaks
// that carry no span place nothing.
func TestAWindowPastTheDecodedSpanIsNotPlaced(t *testing.T) {
	t.Parallel()
	for _, c := range []struct {
		name       string
		frames     int64
		rate       int
		start, end int64
	}{
		{"an end past the audio", 44_100_000, 44100, 70000, 80000},
		{"a start past the audio", 44_100_000, 44100, 80000, 0},
		{"a start at the audio's end", 44_100_000, 44100, 75000, 0},
		{"no frames", 0, 44100, 0, 7500},
		{"no rate", 44_100_000, 0, 0, 7500},
	} {
		if _, _, ok := windowBuckets(1000, c.frames, c.rate, c.start, c.end); ok {
			t.Errorf("%s: placed [%d, %d) in %d frames at %d Hz", c.name, c.start, c.end, c.frames, c.rate)
		}
	}
}

// A carved track's validator names the span its window was placed by: a
// re-analysis that decodes a different length re-slices the buckets.
func TestACarvedValidatorNamesTheSpanItWasPlacedBy(t *testing.T) {
	t.Parallel()
	base := waveformWindow(225, 450, 44_100_000, 44100)
	if base == waveformWindow(225, 450, 44_200_000, 44100) {
		t.Fatal("two decoded lengths give one validator")
	}
	if base == waveformWindow(225, 450, 44_100_000, 48000) {
		t.Fatal("two decoded rates give one validator")
	}
}
