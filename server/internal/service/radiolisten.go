package service

import (
	"context"
	"time"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// Radio in the listening record. Stats aggregate `listen_sessions`,
// which clients write when a session ends; nothing wrote a row for a
// station, so radio time was invisible. The stream proxy is the one
// place that knows the account, the station, and how long the stream
// stayed open, so it is where the measurement belongs.

// RadioListenMinListen is how long a tune-in must have run before it
// is worth a row.
//
// Its own constant rather than a second use of
// [RadioScrobbleMinListen], which happens to hold the same value
// today. They are different rules - one decides what is worth
// announcing to a third-party scrobbler, the other what counts as
// listening - and sharing a constant is how two rules quietly become
// one.
const RadioListenMinListen = 30 * time.Second

// RadioListenCheckpoint is how often an open stream writes its elapsed
// time.
//
// A tune-in has no end until the listener disconnects, so a server that
// stops first would otherwise lose the whole listen. Every checkpoint
// carries the total rather than a delta, so this is also the most that
// can be lost.
const RadioListenCheckpoint = 60 * time.Second

// radioListenPoint is one tune-in's elapsed time on its way to the
// writer. See [radioWrite] for why an absolute total rather than a
// delta is what lets it share the scrobble queue.
type radioListenPoint struct {
	userID     string
	sessionID  string
	stationPID string
	startedAt  time.Time
	elapsed    time.Duration
}

func (p radioListenPoint) writeTo(ctx context.Context, l *Library) {
	l.writeRadioListen(ctx, p)
}

func (radioListenPoint) kind() string { return "listen" }

// RecordRadioListen queues one tune-in's elapsed time. sessionID is
// this connection's own ULID, minted by the proxy: it is the
// idempotency key the row upserts on, so every checkpoint of one
// connection lands on one row.
//
// One row per connection, stated rather than implied: a listener who
// reconnects mints a new id, so a stretch of listening broken by a
// dropped socket keeps its total time but reports as two sessions. The
// heatmap and the streaks read session counts as well as time, so that
// is a visible choice rather than an implementation detail.
//
// The caller is the goroutine relaying that listener's audio, so
// nothing here may touch SQLite; the listener's context is deliberately
// not carried into the write, for the reason [ScrobbleRadioPlay] gives.
func (l *Library) RecordRadioListen(_ context.Context, userID, sessionID, apiStationPID string, startedAt time.Time, elapsed time.Duration) {
	if elapsed < l.radioListenFloor {
		return
	}
	l.queueRadioWrite(radioListenPoint{
		userID:     userID,
		sessionID:  sessionID,
		stationPID: apiStationPID,
		startedAt:  startedAt,
		elapsed:    elapsed,
	}, apiStationPID)
}

// writeRadioListen records or extends one tune-in's row.
func (l *Library) writeRadioListen(ctx context.Context, p radioListenPoint) {
	prefix, pid, ok := parseAPIPID(p.stationPID)
	if !ok || prefix != PrefixRadioStation {
		return
	}
	err := l.db.UpsertRadioListen(ctx, wdb.ListenSession{
		UserID:    p.userID,
		SessionID: p.sessionID,
		// The bare ULID, like every other row; the media type is what
		// says which table answers for it.
		ItemPID:   string(pid),
		MediaType: "radio",
		StartedAt: p.startedAt,
		MsPlayed:  p.elapsed.Milliseconds(),
		// The server measured this rather than a client reporting it,
		// and `source` is what tells the two apart in the log.
		Client: "",
		Source: "radio",
	})
	if err != nil {
		l.log.Warn("recording radio listen", "station", p.stationPID, "err", err)
	}
}
