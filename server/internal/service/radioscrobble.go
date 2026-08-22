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

// radioWriteQueue is how much radio bookkeeping may be waiting on the
// writer before new work is dropped. One listener produces a scrobble
// every few minutes and a checkpoint every minute, so only a writer
// that has stopped moving reaches the end of this.
const radioWriteQueue = 64

// radioWriteDrain bounds the shutdown drain. Well inside the ten
// seconds the process gives itself, because a queue this deep is a
// handful of small writes and the rest of the drain is waiting on it.
const radioWriteDrain = 3 * time.Second

// radioWrite is one piece of radio bookkeeping on its way to the
// writer.
//
// One channel carries two payloads, and they do not have the same
// tolerance for being dropped - which is worth stating rather than
// leaving to be discovered. Dropping a scrobble on a full buffer is
// right: it is best-effort by design, and the audio is not. Dropping a
// checkpoint is survivable for a narrower reason - [radioListenPoint]
// carries the elapsed total rather than a delta, so the next tick
// supersedes whatever was lost and the row lands short at worst. A
// delta-carrying payload could not share this queue.
type radioWrite interface {
	// writeTo does the bookkeeping. On the Library rather than the
	// payload so both stay small structs on the channel.
	writeTo(ctx context.Context, l *Library)
	// kind names the payload for the drop warning, so an operator can
	// tell a best-effort loss from an unrecoverable one.
	kind() string
}

// radioSegmentPlay is one finished segment on its way to the writer.
type radioSegmentPlay struct {
	userID     string
	stationPID string
	rawTitle   string
	startedAt  time.Time
}

func (p radioSegmentPlay) writeTo(ctx context.Context, l *Library) {
	l.writeRadioScrobble(ctx, p)
}

func (radioSegmentPlay) kind() string { return "scrobble" }

// ScrobbleRadioPlay queues a finished radio segment to every scrobble
// connection the listener holds. rawTitle is the ICY StreamTitle the
// segment played under; startedAt is when it appeared on this
// listener's stream.
//
// The caller is the goroutine relaying that listener's audio and the
// call lands at a song boundary, so nothing here may touch SQLite: the
// segment is handed to a supervised writer and the send is
// non-blocking, because a scrobble is best-effort and the audio is not.
//
// The listener's context is deliberately not carried into the write.
// It is cancelled the instant they disconnect, which is the same
// instant the last segment is reported; the writer runs on the process
// context instead.
func (l *Library) ScrobbleRadioPlay(_ context.Context, userID, apiStationPID, rawTitle string, startedAt time.Time) {
	l.queueRadioWrite(radioSegmentPlay{
		userID:     userID,
		stationPID: apiStationPID,
		rawTitle:   rawTitle,
		startedAt:  startedAt,
	}, apiStationPID)
}

// queueRadioWrite hands one piece of bookkeeping to the writer without
// blocking. See [radioWrite] for why a full buffer drops rather than
// waits, and for what that costs each payload.
//
// The warning names what was lost, because the two payloads do not cost
// the same: a dropped scrobble is one missing play on a third-party
// profile, and a dropped closing checkpoint is listening time that no
// later tick will restate.
func (l *Library) queueRadioWrite(w radioWrite, apiStationPID string) {
	select {
	case l.radioWrites <- w:
	default:
		l.log.Warn("dropping radio bookkeeping; the writer is behind",
			"kind", w.kind(), "station", apiStationPID)
	}
}

// writeRadioBookkeeping is the queue's one drainer, started by Open and
// ending with the process.
func (l *Library) writeRadioBookkeeping(ctx context.Context) error {
	for {
		select {
		case play := <-l.radioWrites:
			// Both cases go ready together at shutdown and select picks
			// between them at random, so a segment reaches here with the
			// context already cancelled about half the time - and every
			// read the write makes would fail on it. Carried into the
			// drain instead, which has a context of its own.
			if ctx.Err() != nil {
				l.drainRadioWrites(play)
				return nil
			}
			play.writeTo(ctx, l)
			l.noteRadioWriteDone()
		case <-ctx.Done():
			// What is queued right now, and then [Library.Close] takes
			// the rest. This runs on the signal context, which is the
			// one the listeners' relays have *not* unwound from yet:
			// the process cancels requests and drains the HTTP server
			// after this returns, so every open tune-in's closing
			// checkpoint is still to come.
			l.drainRadioWrites()
			return nil
		}
	}
}

// drainRadioWrites writes held, then what is already queued, on a
// context of its own: the one the writer runs on is the one that just
// ended, and handing it to the store would fail every read on the way
// out.
//
// What is in the buffer now and no more, so it is called twice at
// shutdown. A disconnecting listener adds nothing to the scrobble half
// - a segment only scrobbles when its ending transition is heard - but
// it adds exactly one closing checkpoint, and the relay that sends it
// is still running when the writer stops. [Library.Close] is the second
// call, once nothing can be relaying any more.
func (l *Library) drainRadioWrites(held ...radioWrite) {
	ctx, cancel := context.WithTimeout(context.WithoutCancel(l.procCtx), radioWriteDrain)
	defer cancel()
	for _, play := range held {
		play.writeTo(ctx, l)
		l.noteRadioWriteDone()
	}
	for {
		select {
		case play := <-l.radioWrites:
			play.writeTo(ctx, l)
			l.noteRadioWriteDone()
		default:
			return
		}
	}
}

// noteRadioWriteDone fires the test hook if one is installed.
func (l *Library) noteRadioWriteDone() {
	if hook := l.radioWriteDone.Load(); hook != nil {
		(*hook)()
	}
}

// writeRadioScrobble does the bookkeeping for one queued segment.
// Failures log and are not retried: a radio scrobble nobody can
// attribute is not worth a second attempt.
func (l *Library) writeRadioScrobble(ctx context.Context, play radioSegmentPlay) {
	userID, apiStationPID := play.userID, play.stationPID
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
	artist, title, ok := parseRadioTitle(play.rawTitle, station.Name)
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
			ListenedAtNS: play.startedAt.UnixNano(),
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
