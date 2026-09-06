package service

import (
	"context"
	"crypto/rand"
	"time"

	"github.com/oklog/ulid/v2"

	"github.com/colespringer/waxbin/model"

	"github.com/colespringer/waxdeck/server/internal/connect"
)

// The connect subsystem's service-layer glue: queue hydration for
// sessions and the per-user playback write-through for remote
// (server-driven) playback. Mirror sessions never write through here;
// their owning client checkpoints itself over the REST surface, and a
// second writer would fight it.

// QueueEntries hydrates queue entries for the pids, in order,
// enforcing the caller's visibility. Any invisible or unknown pid
// fails the whole call: a queue is one decision, never a partial load.
func (l *Library) QueueEntries(ctx context.Context, userID string, pids []string) ([]connect.QueueEntry, error) {
	uc, err := l.userCtxByID(ctx, userID)
	if err != nil {
		return nil, err
	}
	out := make([]connect.QueueEntry, 0, len(pids))
	for _, pid := range pids {
		it, err := l.getVisibleItem(ctx, uc, pid)
		if err != nil {
			return nil, err
		}
		out = append(out, connect.QueueEntry{
			PID:        pid,
			Title:      it.Title,
			Artist:     it.Artist,
			DurationMS: it.DurationMS,
		})
	}
	return out, nil
}

// UserCtxByID rebuilds a user context from a bare user id (the connect
// core carries ids, not principals; the api layer's media resolver
// needs the context back for visibility-checked stream resolution).
func (l *Library) UserCtxByID(ctx context.Context, userID string) (*UserCtx, error) {
	return l.userCtxByID(ctx, userID)
}

func (l *Library) userCtxByID(ctx context.Context, userID string) (*UserCtx, error) {
	u, err := l.db.UserByID(ctx, userID)
	if err != nil || u == nil {
		return nil, errNotFound("no such user")
	}
	return l.UserCtx(ctx, u)
}

// PlayerProgress buffers a position tick for a remote session. The
// per-tick user and item resolution is deliberate, not an oversight:
// both are point reads on a local read pool (the item through the
// pidpath cache), the cadence is one tick per five seconds per
// playing remote session, and resolving fresh keeps organize moves
// and permission changes honest mid-session. A cache here would buy
// microseconds and cost an invalidation contract.
func (l *Library) PlayerProgress(userID, pid string, positionMS int64) {
	// Progress is a buffered facade tick keyed by catalog user; resolve
	// lazily and drop on failure (the periodic checkpoint is durable).
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	uc, err := l.userCtxByID(ctx, userID)
	if err != nil {
		return
	}
	it, err := l.getVisibleItem(ctx, uc, pid)
	if err != nil {
		return
	}
	// Under the item's stripe even though it decides nothing: the tick
	// lands in the catalog's pending buffer and is persisted by
	// whatever flush comes next, from anywhere, so a tick buffered
	// while an undo held the stripe would be written after the undo's
	// own position and beside the flags it cleared - the end position
	// with the flags off, which is the state the stripe exists to make
	// unreachable. Taking it costs one uncontended mutex per five
	// seconds per playing remote session.
	unlock := l.lockPlayed(uc.ID, it.PID)
	defer unlock()
	l.lib.Playback().Progress(model.PID(uc.CatalogPID), it.PID, positionMS)
}

// PlayerCheckpoint persists a remote session's position now (pause,
// stop, track change) and emits the play-state event.
func (l *Library) PlayerCheckpoint(ctx context.Context, userID, pid string, positionMS int64) {
	uc, err := l.userCtxByID(ctx, userID)
	if err != nil {
		return
	}
	if _, err := l.Checkpoint(ctx, uc, pid, positionMS, nil); err != nil {
		l.log.Warn("player checkpoint", "pid", pid, "err", err)
	}
}

// PlayerSetQueue mirrors the active queue into the catalog's per-user
// play queue, so queue state survives WaxDeck itself.
func (l *Library) PlayerSetQueue(ctx context.Context, userID string, pids []string) {
	uc, err := l.userCtxByID(ctx, userID)
	if err != nil {
		return
	}
	catalogPIDs := make([]model.PID, 0, len(pids))
	for _, pid := range pids {
		it, err := l.getVisibleItem(ctx, uc, pid)
		if err != nil {
			continue
		}
		catalogPIDs = append(catalogPIDs, it.PID)
	}
	if err := l.lib.Playback().SetQueue(ctx, model.PID(uc.CatalogPID), catalogPIDs); err != nil {
		l.log.Warn("player queue mirror", "err", err)
	}
}

// PlayerListen ingests a listen accumulated by a remote session,
// riding the same dedupe-correct path client reports use.
func (l *Library) PlayerListen(ctx context.Context, userID, pid string, msPlayed int64, startedAt time.Time) {
	uc, err := l.userCtxByID(ctx, userID)
	if err != nil {
		return
	}
	sess := ListenSession{
		SessionID: newConnectListenID(),
		PID:       pid,
		StartedAt: startedAt,
		MsPlayed:  msPlayed,
		Client:    "connect",
		// Live, because that is what it is: a session playing now, on a
		// device the server is driving. Which device it was is the
		// client field's to say, and "remote" was neither a source the
		// ingest accepts nor one the contract declares, so every one of
		// these was refused before it reached a row.
		Source: "live",
	}
	if _, err := l.IngestListens(ctx, uc, []ListenSession{sess}); err != nil {
		l.log.Warn("player listen ingest", "pid", pid, "err", err)
	}
}

func newConnectListenID() string {
	return ulid.MustNew(ulid.Timestamp(time.Now()), rand.Reader).String()
}
