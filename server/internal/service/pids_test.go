package service

import (
	"testing"

	"github.com/colespringer/waxbin/model"
)

// Crockford's alphabet reads either case, so every by-id path finds the
// same row whichever case the caller typed.
func TestAnAPIPIDReadsEitherCase(t *testing.T) {
	for _, in := range []string{"sh-01JZX5N8QW3F4V9T2B7KD3M9R6", "sh-01jzx5n8qw3f4v9t2b7kd3m9r6"} {
		prefix, pid, ok := parseAPIPID(in)
		if !ok || prefix != "sh" || pid != "01JZX5N8QW3F4V9T2B7KD3M9R6" {
			t.Errorf("parseAPIPID(%q) = (%q, %q, %v), want the upper-case pid", in, prefix, pid, ok)
		}
	}
}

// Tracks and books answer to each other's prefix, since a kind change
// keeps the pid; an episode's prefix is its own.
func TestATracksAndABooksPrefixReachEachOther(t *testing.T) {
	for _, c := range []struct {
		prefix string
		kind   model.Kind
		want   bool
	}{
		{PrefixTrack, model.KindTrack, true}, {PrefixBook, model.KindTrack, true},
		{PrefixTrack, model.KindBook, true}, {PrefixBook, model.KindBook, true},
		{PrefixEpisode, model.KindEpisode, true}, {PrefixTrack, model.KindEpisode, false},
		{PrefixEpisode, model.KindTrack, false}, {PrefixEpisode, model.KindBook, false},
	} {
		if got := prefixFitsKind(c.prefix, c.kind); got != c.want {
			t.Errorf("prefix %s on a %s = %v, want %v", c.prefix, c.kind, got, c.want)
		}
	}
}
