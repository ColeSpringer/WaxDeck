package api

import (
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/service"
)

type reported struct {
	title string
	since time.Time
}

// A segment wired to a clock a test can move.
func newTestSegment(clock *time.Time) (*radioSegment, *[]reported) {
	var out []reported
	seg := &radioSegment{
		now: func() time.Time { return *clock },
		report: func(title string, since time.Time) {
			out = append(out, reported{title: title, since: since})
		},
	}
	return seg, &out
}

func TestRadioSegmentReportsOnlyWhatPlayedLongEnough(t *testing.T) {
	clock := time.Unix(0, 0)
	seg, out := newTestSegment(&clock)

	seg.start("Artist - Long Song")
	clock = clock.Add(service.RadioScrobbleMinListen)
	seg.close()
	if len(*out) != 1 || (*out)[0].title != "Artist - Long Song" {
		t.Fatalf("reported = %+v, want the long song", *out)
	}

	// A segment that ends a second short of the threshold is not a listen.
	seg.start("Artist - Short Song")
	clock = clock.Add(service.RadioScrobbleMinListen - time.Second)
	seg.close()
	if len(*out) != 1 {
		t.Fatalf("reported = %+v, want the short song left off", *out)
	}
}

// The case the ad branch exists for. A break sits between two songs and
// runs longer than the threshold on its own; without closing the segment
// the break's minutes are charged to the song before it, and a track
// somebody heard ten seconds of scrobbles as if it had played through.
func TestRadioSegmentDoesNotChargeAnAdToThePreviousSong(t *testing.T) {
	clock := time.Unix(0, 0)
	seg, out := newTestSegment(&clock)

	// A listener joins, hears ten seconds of song A, then a long break.
	seg.start("Artist - Song A")
	clock = clock.Add(10 * time.Second)
	seg.close() // the ad block
	if len(*out) != 0 {
		t.Fatalf("reported = %+v, want nothing: song A played ten seconds", *out)
	}

	// Three minutes of advertisement, then song B is announced.
	clock = clock.Add(3 * time.Minute)
	seg.close() // whatever the ad left behind
	seg.start("Artist - Song B")
	if len(*out) != 0 {
		t.Fatalf("reported = %+v, want the advertisement to have reported nothing", *out)
	}

	// Song B plays properly and is the only thing reported.
	clock = clock.Add(service.RadioScrobbleMinListen)
	seg.close()
	if len(*out) != 1 || (*out)[0].title != "Artist - Song B" {
		t.Fatalf("reported = %+v, want only song B", *out)
	}
}
