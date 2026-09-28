package service

import "testing"

func TestWindowBuckets(t *testing.T) {
	t.Parallel()

	// 1000 buckets over 75000 frames: 75 frames (one second) a bucket.
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
		lo, hi, ok := windowBuckets(1000, 75000, c.start, c.end)
		if !ok || lo != c.wantLo || hi != c.wantHi {
			t.Errorf("%s: [%d, %d) = [%d, %d) %v, want [%d, %d)", c.name, c.start, c.end, lo, hi, ok, c.wantLo, c.wantHi)
		}
	}
}

// A window that ends before it starts is no window, and one bucket drawn
// for it would be made up.
func TestAReversedWindowIsNotPlaced(t *testing.T) {
	t.Parallel()
	if lo, hi, ok := windowBuckets(1000, 75000, 30000, 15000); ok {
		t.Errorf("placed the reversed window [30000, 15000) as [%d, %d)", lo, hi)
	}
}

// A window the file's stated length cannot hold means that length is
// wrong for it, and any envelope drawn from it would be a wrong answer.
func TestAWindowPastTheStatedLengthIsNotPlaced(t *testing.T) {
	t.Parallel()
	for _, c := range []struct {
		name       string
		start, end int64
	}{
		{"an end past the file", 70000, 80000},
		{"a start past the file", 80000, 0},
		{"a start at the file's end", 75000, 0},
	} {
		if _, _, ok := windowBuckets(1000, 75000, c.start, c.end); ok {
			t.Errorf("%s: placed [%d, %d) in a 75000-frame file", c.name, c.start, c.end)
		}
	}
}

// A carved track's validator names the length its window was placed by:
// a rescan that corrects it re-slices the buckets.
func TestACarvedValidatorNamesTheLengthItWasPlacedBy(t *testing.T) {
	t.Parallel()
	if waveformWindow(225, 450, 75000) == waveformWindow(225, 450, 76000) {
		t.Fatal("two file lengths give one validator")
	}
}
