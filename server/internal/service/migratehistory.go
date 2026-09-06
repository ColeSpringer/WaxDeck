package service

import (
	"context"
	"strings"
	"time"

	"github.com/colespringer/waxbin/model"
)

// The shared half of the real-timestamp history imports. Last.fm,
// ListenBrainz and a Spotify export all answer the same thing - a list
// of plays with the time each happened - and differ only in how that
// list is fetched. What they share is the expensive part: resolving
// each distinct recording once, and ingesting the plays in batches
// under deterministic ids so a re-run adds nothing.

// migrateHistoryBatch is how many synthesized sessions ride one ingest
// call. Each one costs a catalog read for the item and a played
// evaluation, so the batch is about bounding the slice, not the work.
const migrateHistoryBatch = 100

// migrateMaxMsPlayed is the longest single play any source may claim.
// Every one of these numbers is written by whoever submitted the play -
// an uploaded file, or another server's API - and it is both stored as
// listening time and, for an export that records when a play stopped,
// subtracted from that to derive when it started. Unbounded, one moves
// a play years into the future or overflows the duration outright.
const migrateMaxMsPlayed = int64(24 * time.Hour / time.Millisecond)

// migratePlay is one play as a history source reports it.
type migratePlay struct {
	// SourceID keys the deterministic session id, so it has to identify
	// this play on this source and nothing else.
	SourceID string
	MBID     string
	Artist   string
	Title    string
	Album    string
	At       time.Time
	// MsPlayed is what the source recorded. Meaningful only beside
	// MsMeasured: a source that records nothing leaves both zero and
	// takes the matched item's duration instead.
	MsPlayed int64
	// MsMeasured says the source actually measured this play, so a zero
	// MsPlayed is the measurement rather than a gap in it. An account
	// export is full of instant skips and failed starts, and reading
	// those as "unknown, so assume the whole track" turns every one of
	// them into a finished play: the count bumps, the played mark goes
	// on, and the stored session says something that did not happen.
	MsMeasured bool
	// Finished says whether the source calls this play complete. A
	// source that reports only scrobbles reports finished plays; one
	// that reports every partial play leaves it false and lets the
	// played threshold decide.
	Finished bool
}

// migrateHistory replays a source's plays onto the target account.
//
// Distinct recordings resolve once: a scrobble history is mostly the
// same few hundred tracks, and the ladder's resolve is the expensive
// step. Misses are cached too, so a track absent from the library costs
// one lookup however many times it was played.
type migrateHistory struct {
	l      *Library
	uc     *UserCtx
	source string
	dryRun bool
	// resolved caches the ladder's answer per distinct recording; a nil
	// value is a remembered miss.
	resolved map[string]*model.ItemView
	pending  []ListenSession
	// touched is every item this run wrote a listen for, so the run
	// announces each once at the end rather than once per play.
	touched map[string]bool
	// tick is called as each batch lands, for a source whose fetch loop
	// has no natural place to renew the task lease.
	tick func()
	// seen counts every row offered, matched or not, which is what the
	// lease renewal is paced by.
	seen int
	sum  *migrationSummary
}

func (l *Library) newMigrateHistory(uc *UserCtx, p migrationParams, sum *migrationSummary) *migrateHistory {
	return &migrateHistory{
		l: l, uc: uc, source: p.Source, dryRun: p.DryRun,
		resolved: map[string]*model.ItemView{},
		touched:  map[string]bool{},
		sum:      sum,
	}
}

// historyKey identifies one recording across the plays that name it.
func historyKey(p migratePlay) string {
	if p.MBID != "" {
		return "mbid:" + strings.ToLower(p.MBID)
	}
	return strings.ToLower(p.Artist + "\x00" + p.Title + "\x00" + p.Album)
}

// resolve answers the local item one play names, nil for a miss. The
// answer is cached per distinct recording, misses included: a scrobble
// history is mostly the same few hundred tracks, and a track absent
// from the library must not cost a ladder walk per play.
func (h *migrateHistory) resolve(ctx context.Context, p migratePlay) (*model.ItemView, error) {
	key := historyKey(p)
	if it, seen := h.resolved[key]; seen {
		return it, nil
	}
	found, rung, err := h.l.resolveMigrationRef(ctx, model.PortableRef{
		Kind:   model.KindTrack,
		MBID:   p.MBID,
		Artist: p.Artist,
		Title:  p.Title,
		Album:  p.Album,
	})
	if err != nil {
		return nil, classify(err)
	}
	var it *model.ItemView
	if found != nil && rung != model.MatchNone {
		it = found
		h.sum.Matched++
	} else {
		h.sum.noteUnmatched(p.Artist, p.Title)
	}
	h.resolved[key] = it
	return it, nil
}

// add matches one play and queues its listen. The summary's matched,
// unmatched and listen counts move here; the caller only fetches.
func (h *migrateHistory) add(ctx context.Context, p migratePlay) error {
	if p.Title == "" || p.At.IsZero() {
		return nil
	}
	h.renew()
	it, err := h.resolve(ctx, p)
	if err != nil || it == nil {
		return err
	}
	ms := p.MsPlayed
	if ms < 0 || ms > migrateMaxMsPlayed {
		// Submitter-supplied on every source that reaches here, and fed
		// straight into the listening-time totals. A two-hour duration
		// against a three-minute edit, or a number in the wrong unit
		// entirely, is not a measurement of anything.
		ms = 0
	}
	if !p.MsMeasured && ms <= 0 {
		ms = it.DurationMS
	}
	if h.dryRun {
		h.sum.Listens++
		return nil
	}
	h.touched[string(it.PID)] = true
	h.pending = append(h.pending, ListenSession{
		SessionID: migrateSessionID(h.source, p.SourceID, 0),
		PID:       apiPID(PrefixTrack, it.PID),
		StartedAt: p.At,
		MsPlayed:  ms,
		Finished:  p.Finished,
		Client:    migrateClientName,
		Source:    "import",
	})
	if len(h.pending) < migrateHistoryBatch {
		return nil
	}
	return h.flush(ctx)
}

// flush ingests whatever is queued. Only new rows count: a re-import's
// duplicates are the deterministic ids working.
func (h *migrateHistory) flush(ctx context.Context) error {
	if len(h.pending) == 0 {
		return nil
	}
	res, err := h.l.ingestListens(ctx, h.uc, h.pending, listenIngestOptions{announcedByCaller: true})
	h.sum.Listens += res.Accepted
	h.sum.noteRefusedListens(res.Rejected)
	h.pending = h.pending[:0]
	if h.tick != nil {
		h.tick()
	}
	return err
}

// finish flushes what is queued and announces the run: one play-state
// event per item it wrote to, rather than one per play. The ingest
// leaves this to the importer because a scrobble history is the same
// few hundred tracks over and over, and a row plus a device wake for
// each play would have every client re-polling for hours.
func (h *migrateHistory) finish(ctx context.Context) error {
	if err := h.flush(ctx); err != nil {
		return err
	}
	if h.dryRun {
		return nil
	}
	for pid := range h.touched {
		h.l.emitUserEvent(ctx, h.uc.ID, eventPlayState, pid)
	}
	return nil
}

// renew keeps the task lease alive on a cadence of rows offered rather
// than rows written.
//
// Every row, because the two are not the same thing. A play that
// matched nothing never reaches a batch, so a history where most of
// them miss pays a resolve walk per distinct recording with the flushes
// minutes apart; a saved-track list is one archive entry with tens of
// thousands of entries in it, and the loop around it reports once
// before the whole of them. Either way the run outlives its lease, and
// a second worker starts a copy of the same import beside it.
func (h *migrateHistory) renew() {
	h.seen++
	if h.tick != nil && h.seen%migrateHistoryBatch == 0 {
		h.tick()
	}
}

// star records a loved track at the time the source loved it, matching
// through the same cache the plays use.
func (h *migrateHistory) star(ctx context.Context, p migratePlay) error {
	h.renew()
	it, err := h.resolve(ctx, p)
	if err != nil || it == nil {
		return err
	}
	if h.dryRun {
		h.sum.Stars++
		return nil
	}
	// The source's own time, so a backdated import cannot overwrite a
	// star set here more recently.
	if _, err := h.l.SetStar(ctx, h.uc, apiPID(PrefixTrack, it.PID), true, recordedTime(p.At)); err != nil {
		if migrateWriteSkippable(err) {
			return nil
		}
		return err
	}
	h.sum.Stars++
	return nil
}
