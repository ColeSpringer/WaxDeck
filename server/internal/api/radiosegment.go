package api

import (
	"time"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// radioSegment is the stretch of one title a listener is actually
// hearing, which is a different thing from what the station last
// announced.
//
// A segment reports itself only when something ends it, so a station
// with a never-changing pseudo-title scrobbles nothing and the
// unfinished tail at disconnect stays off the record. What ends one is
// the next title - or an ad break, which ends the song even though the
// spot itself is never reported: leaving the segment open across the
// break would charge the ad's minutes to the song before it, and a
// track somebody heard ten seconds of would scrobble as three minutes.
type radioSegment struct {
	title string
	since time.Time
	// now is the clock, injected so the threshold is testable without
	// waiting out RadioScrobbleMinListen.
	now func() time.Time
	// report takes a segment that ran long enough to count.
	report func(title string, since time.Time)
}

// observe advances the segment for one metadata block.
//
// An ident - a block whose title key is empty - is deliberately not a
// boundary. Automation sends one over station idents and jingles and
// then announces the same song again, and closing on it split one play
// into two scrobbles. Left open, the song is reported once when the
// next real title arrives, at the cost of the ident's own seconds
// counting toward it and of a listener who disconnects mid-ident losing
// the play - which is what disconnecting mid-song already does.
func (s *radioSegment) observe(meta icyMeta) {
	switch {
	case meta.ad:
		s.close()
	case !meta.announcement():
		// A picture-only block or an ident: nothing about the song.
	case meta.title != s.title:
		s.close()
		s.start(meta.title)
	}
}

// close ends whatever was playing, reporting it if it ran long enough.
func (s *radioSegment) close() {
	if s.title != "" && s.now().Sub(s.since) >= service.RadioScrobbleMinListen {
		s.report(s.title, s.since)
	}
	s.title, s.since = "", time.Time{}
}

// start begins a new segment at the current instant.
func (s *radioSegment) start(title string) {
	s.title, s.since = title, s.now()
}
