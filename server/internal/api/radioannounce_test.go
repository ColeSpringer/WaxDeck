package api

import (
	"slices"
	"testing"
	"time"
)

// The proxy announces a tune-in on its first written checkpoint and its
// closing one, and stays quiet between: a first tick under the floor
// writes nothing, so the start rides the next one that is written.
func TestListenAnnouncerAnnouncesTheFirstWrittenAndTheClosingCheckpoint(t *testing.T) {
	t.Parallel()
	const floor = 90 * time.Second
	for _, c := range []struct {
		name   string
		ticks  []int // minutes elapsed at each checkpoint; the last is the close
		wanted []int // the written checkpoints that announce
	}{
		{"every tick written", []int{2, 3, 4, 5}, []int{2, 5}},
		{"first tick under the floor", []int{1, 2, 3, 4}, []int{2, 4}},
		{"closed under the floor", []int{1}, nil},
		{"closed on the first written", []int{1, 2}, []int{2}},
	} {
		t.Run(c.name, func(t *testing.T) {
			var a listenAnnouncer
			var got []int
			for i, tick := range c.ticks {
				elapsed := time.Duration(tick) * time.Minute
				a.checkpoint(i == len(c.ticks)-1, func(announce bool) bool {
					if elapsed < floor {
						return false
					}
					if announce {
						got = append(got, tick)
					}
					return true
				})
			}
			if !slices.Equal(got, c.wanted) {
				t.Errorf("announced at minutes %v, want %v", got, c.wanted)
			}
		})
	}
}
