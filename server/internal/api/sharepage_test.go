package api

import "testing"

func TestCountableShareFetch(t *testing.T) {
	cases := []struct {
		rangeHeader string
		want        bool
		why         string
	}{
		{"", true, "a rangeless GET starts a listen"},
		{"bytes=0-", true, "the open-ended first fetch browsers send"},
		{"bytes=0-52428799", true, "Safari's bounded full-file fetch after its probe"},
		{"bytes=0-1", false, "Safari's two-byte preflight probe is not a listen"},
		{"bytes=0-511", false, "anything under the probe floor stays a probe"},
		{"bytes=0-1023", true, "the floor itself counts"},
		{"bytes=100-", false, "a mid-playback seek"},
		{"bytes=100-200", false, "a bounded seek window"},
		{"bytes=0-1,5-9", false, "multi-range strings count nothing"},
		{"bytes=junk", false, "junk counts nothing"},
	}
	for _, tc := range cases {
		if got := countableShareFetch(tc.rangeHeader); got != tc.want {
			t.Errorf("countableShareFetch(%q) = %v, want %v (%s)", tc.rangeHeader, got, tc.want, tc.why)
		}
	}
}
