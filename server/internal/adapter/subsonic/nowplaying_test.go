package subsonic

import (
	"slices"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/connect"
)

// getNowPlaying lists a playing session however long ago it last
// reported, and a paused one only for ten minutes after: a session parked
// in an open tab or on a speaker lives for days, and clients show the
// list as who is listening now.
func TestNowPlayingDropsAPausedSessionAfterTenMinutes(t *testing.T) {
	now := time.Date(2026, 10, 21, 12, 0, 0, 0, time.UTC)
	on := []connect.QueueEntry{{PID: "tr-x"}}
	sessions := []connect.Session{
		{ID: "playing, an hour on", Playing: true, Entries: on, UpdatedAt: now.Add(-time.Hour)},
		{ID: "paused just now", Entries: on, UpdatedAt: now.Add(-time.Minute)},
		{ID: "paused ten minutes ago", Entries: on, UpdatedAt: now.Add(-10 * time.Minute)},
		{ID: "paused eleven minutes ago", Entries: on, UpdatedAt: now.Add(-11 * time.Minute)},
		{ID: "ended", Playing: true, Ended: true, Entries: on, UpdatedAt: now},
		{ID: "past its queue", Playing: true, Index: 1, Entries: on, UpdatedAt: now},
	}
	var got []string
	for _, s := range nowPlayingSessions(sessions, now) {
		got = append(got, s.ID)
	}
	if want := []string{"playing, an hour on", "paused just now", "paused ten minutes ago"}; !slices.Equal(got, want) {
		t.Fatalf("listed %q, want %q", got, want)
	}
}
