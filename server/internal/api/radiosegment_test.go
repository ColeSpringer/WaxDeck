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

// An ident is not a song boundary. Automation sends an empty title over
// station idents and jingles and then announces the same song again;
// closing on it charged one play as two scrobbles.
func TestRadioSegmentRidesThroughAnIdent(t *testing.T) {
	t.Parallel()
	clock := time.Unix(0, 0)
	seg, out := newTestSegment(&clock)
	ident := icyMeta{titleOK: true}
	song := func(title string) icyMeta { return icyMeta{title: title, titleOK: true} }

	seg.observe(song("Artist - One Song"))
	clock = clock.Add(service.RadioScrobbleMinListen)
	seg.observe(ident)
	if len(*out) != 0 {
		t.Fatalf("reported = %+v at the ident, want the song still open", *out)
	}
	// The same song comes back, which is what makes closing on the ident
	// wrong rather than merely early.
	seg.observe(song("Artist - One Song"))
	clock = clock.Add(service.RadioScrobbleMinListen)
	seg.observe(song("Artist - Next Song"))

	if len(*out) != 1 || (*out)[0].title != "Artist - One Song" {
		t.Fatalf("reported = %+v, want one play for the song either side of the ident", *out)
	}
	// Timed from where it started, not from where the ident put it back.
	if !(*out)[0].since.Equal(time.Unix(0, 0)) {
		t.Fatalf("since = %v, want the start of the first announcement", (*out)[0].since)
	}
}

// A block that names nothing at all is the picture-only one stations
// send between songs, and says as little about the segment as an ident.
func TestRadioSegmentIgnoresBlocksThatNameNoSong(t *testing.T) {
	t.Parallel()
	clock := time.Unix(0, 0)
	seg, out := newTestSegment(&clock)

	seg.observe(icyMeta{title: "Artist - One Song", titleOK: true})
	clock = clock.Add(service.RadioScrobbleMinListen)
	seg.observe(icyMeta{artURL: "https://art.example/c.jpg"})
	if len(*out) != 0 || seg.title != "Artist - One Song" {
		t.Fatalf("reported = %+v, title = %q, want the song untouched", *out, seg.title)
	}
}

func TestRadioSegmentReportsOnlyWhatPlayedLongEnough(t *testing.T) {
	t.Parallel()
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
	t.Parallel()
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
