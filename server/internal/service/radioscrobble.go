package service

import (
	"context"
	"strings"
	"time"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// Radio scrobbling: the stream proxy observes ICY title transitions
// per listener and reports finished segments here. Only segments that
// END with an observed transition scrobble - a station whose "title"
// never changes (a slogan, a URL) produces no transitions and so no
// junk, and the tail segment at disconnect (whose end was never
// heard) stays off the record. The half-or-four-minutes rule needs a
// track length radio does not carry; the minimum listen below stands
// in for it.

// RadioScrobbleMinListen is how long a titled segment must have played
// before its transition scrobbles it; the proxy applies it.
const RadioScrobbleMinListen = 30 * time.Second

// ScrobbleRadioPlay queues a finished radio segment to every scrobble
// connection the listener holds. rawTitle is the ICY StreamTitle the
// segment played under; startedAt is when it appeared on this
// listener's stream. Failures log: the stream proxy calling this must
// never stall on bookkeeping.
func (l *Library) ScrobbleRadioPlay(ctx context.Context, userID, apiStationPID, rawTitle string, startedAt time.Time) {
	prefix, pid, ok := parseAPIPID(apiStationPID)
	if !ok || prefix != PrefixRadioStation {
		return
	}
	// Read before the station and the title parse, which are the two
	// reads a listener who wants none of this should not be paying for.
	if l.PrefsForUser(ctx, userID).RadioScrobbleOptOut {
		return
	}
	station, err := l.db.RadioStationByID(ctx, string(pid))
	if err != nil {
		return // deleted mid-listen; nothing to attribute
	}
	artist, title, ok := parseRadioTitle(rawTitle, station.Name)
	if !ok {
		return
	}
	conns, err := l.db.ScrobbleConnections(ctx, userID)
	if err != nil {
		l.log.Warn("reading scrobble connections", "err", err)
		return
	}
	now := time.Now().UnixNano()
	for _, c := range conns {
		row := wdb.ScrobbleRow{
			UserID:       userID,
			Service:      c.Service,
			ItemPID:      apiStationPID,
			Artist:       artist,
			Title:        title,
			ListenedAtNS: startedAt.UnixNano(),
		}
		if err := l.db.EnqueueScrobble(ctx, row, now); err != nil {
			l.log.Warn("queuing radio scrobble", "service", c.Service, "err", err)
		}
	}
}

// parseRadioTitle splits an ICY StreamTitle into artist and title.
// The convention is "Artist - Title"; anything that does not fit it
// honestly is rejected rather than guessed at: a scrobble log full of
// station slogans is worse than a missed track.
func parseRadioTitle(raw, stationName string) (artist, title string, ok bool) {
	raw = strings.TrimSpace(raw)
	if raw == "" || len(raw) > 400 {
		return "", "", false
	}
	// A URL in the title is an ad or a station plug, never a track.
	if strings.Contains(raw, "://") {
		return "", "", false
	}
	if stationName != "" && strings.EqualFold(raw, strings.TrimSpace(stationName)) {
		return "", "", false
	}
	artist, title, found := strings.Cut(raw, " - ")
	if !found {
		return "", "", false
	}
	artist, title = strings.TrimSpace(artist), strings.TrimSpace(title)
	if artist == "" || title == "" {
		return "", "", false
	}
	// "StationName - Groove Show" is the station talking about itself.
	if stationName != "" &&
		(strings.EqualFold(artist, strings.TrimSpace(stationName)) ||
			strings.EqualFold(title, strings.TrimSpace(stationName))) {
		return "", "", false
	}
	return artist, title, true
}
