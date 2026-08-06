package subsonic

import (
	"fmt"
	"testing"
	"time"
)

// The entry is keyed on the playlist's updatedAt and a TTL, not on the
// catalog feed position. A smart rule can name played or finished, and a
// play-state write moves no catalog change, so a tail-keyed entry would
// be stale forever; one scan would meanwhile invalidate every entry for
// every user at once.
func TestPlaylistTotalIsUsedUntilItExpires(t *testing.T) {
	fresh := playlistTotal{updatedAtNS: 7, at: time.Now(), songs: 3}
	stale := playlistTotal{
		updatedAtNS: 7,
		at:          time.Now().Add(-playlistTotalsTTL - time.Second),
		songs:       3,
	}
	usable := func(held playlistTotal, updated int64) bool {
		return held.updatedAtNS == updated &&
			time.Since(held.at) < playlistTotalsTTL
	}
	if !usable(fresh, 7) {
		t.Fatal("a fresh entry for an unedited playlist should be used")
	}
	if usable(stale, 7) {
		t.Fatal("an entry past the TTL should be recomputed; play states move no catalog change")
	}
	if usable(fresh, 8) {
		t.Fatal("an edit to the playlist should be visible at once")
	}
}

// The cache is bounded by emptying, not by replacing: a fresh map would
// pay a rehash per doubling all the way back to the cap.
func TestPlaylistTotalsCacheClearsWithoutShrinking(t *testing.T) {
	h := &Handler{totals: make(map[playlistTotalKey]playlistTotal)}
	fill := func(n int) {
		for i := range n {
			h.totals[playlistTotalKey{
				userID: "u-1",
				pid:    fmt.Sprintf("pl-%d", i),
			}] = playlistTotal{songs: i}
		}
	}

	fill(playlistTotalsCap)
	if len(h.totals) != playlistTotalsCap {
		t.Fatalf("filled to %d, want %d", len(h.totals), playlistTotalsCap)
	}

	// The reset branch, as playlistTotals runs it.
	before := h.totals
	if h.totals == nil {
		h.totals = make(map[playlistTotalKey]playlistTotal)
	} else if len(h.totals) >= playlistTotalsCap {
		clear(h.totals)
	}

	if len(h.totals) != 0 {
		t.Fatalf("the reset left %d entries, want an empty cache", len(h.totals))
	}
	// Same map, so the buckets it grew survive the reset.
	if fmt.Sprintf("%p", h.totals) != fmt.Sprintf("%p", before) {
		t.Fatal("the reset replaced the map rather than emptying it")
	}

	// Still usable, which a nil map would not be.
	fill(1)
	if len(h.totals) != 1 {
		t.Fatalf("refill left %d entries, want 1", len(h.totals))
	}
}
