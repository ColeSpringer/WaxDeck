package service

import (
	"context"
	"crypto/rand"
	"maps"
	"slices"
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
func (l *Playback) QueueEntries(ctx context.Context, userID string, pids []string) ([]connect.QueueEntry, error) {
	uc, err := l.Grants.UserCtxByID(ctx, userID)
	if err != nil {
		return nil, err
	}
	out := make([]connect.QueueEntry, 0, len(pids))
	for _, pid := range pids {
		it, err := l.Grants.getVisibleItem(ctx, uc, pid)
		if err != nil {
			return nil, err
		}
		title, artist, _ := itemNames(it)
		out = append(out, connect.QueueEntry{
			PID:        pid,
			Title:      title,
			Artist:     artist,
			DurationMS: it.DurationMS,
		})
	}
	return out, nil
}

// QueueEntriesVisible answers which of a queue's pids the account may
// see, as QueueEntries resolves them: inside its library grants and
// content rules. An account that cannot be read sees none, and a read
// that fails answers none: the caller shows an empty slot for each.
func (l *Playback) QueueEntriesVisible(userID string, pids []string) map[string]bool {
	ctx := context.Background()
	out := make(map[string]bool, len(pids))
	uc, err := l.Grants.UserCtxByID(ctx, userID)
	if err != nil {
		return out
	}
	if seesEverything(uc) {
		for _, pid := range pids {
			out[pid] = true
		}
		return out
	}
	bare := make([]model.PID, 0, len(pids))
	for _, api := range pids {
		if prefix, pid, ok := parseAPIPID(api); ok && itemPrefix(prefix) {
			bare = append(bare, pid)
		}
	}
	views, err := l.Reads.readItems(ctx, bare)
	if err != nil {
		l.log.Warn("reading a shared session's queue for a receiver", "err", err)
		return out
	}
	verdicts, err := l.Grants.tagVerdicts(ctx, uc, slices.Collect(maps.Values(views)))
	if err != nil {
		l.log.Warn("reading a shared session's queue for a receiver", "err", err)
		return out
	}
	for _, api := range pids {
		prefix, pid, ok := parseAPIPID(api)
		if !ok {
			continue
		}
		if v := views[pid]; v != nil && prefixFitsKind(prefix, v.Kind) &&
			l.Grants.viewVisible(ctx, uc, v) && l.Grants.contentAllows(ctx, uc, verdicts, v) {
			out[api] = true
		}
	}
	return out
}

// PlayerProgress buffers a position tick for a remote session. The
// per-tick user and item resolution is deliberate, not an oversight:
// both are point reads on a local read pool (the item through the
// pidpath cache), the cadence is one tick per five seconds per
// playing remote session, and resolving fresh keeps organize moves
// and permission changes honest mid-session. A cache here would buy
// microseconds and cost an invalidation contract.
func (l *Playback) PlayerProgress(userID, pid string, positionMS int64) {
	// Progress is a buffered facade tick keyed by catalog user; resolve
	// lazily and drop on failure (the periodic checkpoint is durable).
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	uc, err := l.Grants.UserCtxByID(ctx, userID)
	if err != nil {
		return
	}
	it, err := l.Grants.getVisibleItem(ctx, uc, pid)
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
func (l *Playback) PlayerCheckpoint(ctx context.Context, userID, pid string, positionMS int64) {
	uc, err := l.Grants.UserCtxByID(ctx, userID)
	if err != nil {
		return
	}
	if _, err := l.Checkpoint(ctx, uc, pid, positionMS, nil); err != nil {
		l.log.Warn("player checkpoint", "pid", pid, "err", err)
	}
}

// PlayerSetQueue mirrors the active queue into the catalog's per-user
// play queue, so queue state survives WaxDeck itself.
func (l *Playback) PlayerSetQueue(ctx context.Context, userID string, pids []string) {
	uc, err := l.Grants.UserCtxByID(ctx, userID)
	if err != nil {
		return
	}
	catalogPIDs := make([]model.PID, 0, len(pids))
	for _, pid := range pids {
		it, err := l.Grants.getVisibleItem(ctx, uc, pid)
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
func (l *Playback) PlayerListen(ctx context.Context, userID, pid string, msPlayed int64, startedAt time.Time) {
	uc, err := l.Grants.UserCtxByID(ctx, userID)
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
