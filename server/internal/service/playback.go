package service

import (
	"context"
	"time"

	"github.com/colespringer/waxbin/model"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// Played thresholds per medium. A session marks its item played when
// msPlayed crosses the medium's threshold; the rules differ because
// "played" means different things per medium (it drives archive and
// retention for podcasts, completion for books). Defaults follow the
// plan of record; configuration arrives with the settings surface.
const (
	musicPlayedFloor    = 4 * time.Minute // or half the track, whichever is less
	musicPlayedFraction = 0.5
	// Above this length the four-minute rule stops applying and only the
	// proportional rule counts: four minutes into a two-hour set is not a
	// play.
	musicLongTrack    = 30 * time.Minute
	podcastFraction   = 0.9
	audiobookFraction = 0.99
	// spokenFinishedFraction is the completion bar for spoken word.
	// Deliberately stricter than the podcast played threshold: played
	// at 90 percent drives archive and retention, but finished means
	// the listener actually reached the end, and a podcast at 92
	// percent is played yet unfinished. Its own constant so tuning
	// the audiobook played threshold can never move completion.
	spokenFinishedFraction = 0.99
)

// How far the resume shelf will walk the stamp table to fill its page.
// The cap is the honest half of the trade: a listener whose recent
// stamps are all music, all trashed, or all outside their libraries
// gets a short shelf rather than a scan, and 2000 rows is several
// months of ordinary listening ahead of a shelf that asks for ten.
const (
	resumeStampPage    = 200
	resumeStampScanCap = 2000
)

// RecentlyPositionedItems lists the caller's spoken-word items with a
// saved resume position, most recently checkpointed first. Backed by
// the per-user position stamps, so an item counts from its first
// checkpoint; the catalog's recently-played list would miss anything
// never played to completion, which is exactly the state a resume
// surface exists for.
func (l *Library) RecentlyPositionedItems(ctx context.Context, uc *UserCtx, limit int) ([]ItemSummary, error) {
	if limit <= 0 {
		return []ItemSummary{}, nil
	}
	subs := l.newSubscriptionFilter(uc)
	out := make([]ItemSummary, 0, limit)
	seen := make(map[string]bool, limit)
	// Four filters run below - kind, trashed, library visibility,
	// subscription - and the last three can drop arbitrarily many rows,
	// so one bare page of stamps comes back short for exactly the
	// partial-visibility listener who needs the shelf most. Read in
	// pages until the shelf is full, bounded so a user whose whole
	// stamp table is music (kind drops every row) cannot walk it.
	for scanned := 0; len(out) < limit && scanned < resumeStampScanCap; scanned += resumeStampPage {
		pids, err := l.db.RecentPositionStamps(ctx, uc.ID, resumeStampPage, scanned)
		if err != nil {
			return nil, &Error{Kind: KindInternal, Err: err}
		}
		if len(pids) == 0 {
			break
		}
		for _, pid := range pids {
			if len(out) == limit {
				break
			}
			// A checkpoint landing mid-walk can shift a row across a page
			// boundary; the offset does not follow it, so drop the repeat.
			if seen[pid] {
				continue
			}
			seen[pid] = true
			it, err := l.lib.Get(ctx, model.PID(pid))
			if err != nil {
				// Stamps are dangling-tolerant: the item may be gone.
				continue
			}
			if it.Kind != model.KindEpisode && it.Kind != model.KindBook {
				continue
			}
			// Hydrated by pid rather than by query, so the state predicate
			// cannot reach it. Subsonic's resume surface reads this
			// list, so a trashed book would come back there alone.
			if archived(it) {
				continue
			}
			if !uc.AllLibraries && !l.itemVisible(ctx, uc, it.PID) {
				continue
			}
			if !subs.allowsItem(ctx, l, it) {
				continue
			}
			out = append(out, summary(it))
		}
		if len(pids) < resumeStampPage {
			break
		}
	}
	return out, nil
}

// PlayState returns the calling user's state for one item. Items never
// played return a zero state.
func (l *Library) PlayState(ctx context.Context, uc *UserCtx, apiItemPID string) (PlayState, error) {
	it, err := l.getVisibleItem(ctx, uc, apiItemPID)
	if err != nil {
		return PlayState{}, err
	}
	return l.playStateFor(ctx, uc, apiItemPID, it.PID)
}

// playStateFor reads the user's state for an already-authorized item.
func (l *Library) playStateFor(ctx context.Context, uc *UserCtx, apiItemPID string, pid model.PID) (PlayState, error) {
	st, err := l.lib.Playback().State(ctx, model.PID(uc.CatalogPID), pid)
	if err != nil {
		return PlayState{}, classify(err)
	}
	return playStateDTO(apiItemPID, st), nil
}

// playStateDTO projects a catalog play state onto the API DTO. A nil
// state (the user has not touched the item) yields the zero positions,
// so batch readers can pass the missing entry straight through.
func playStateDTO(apiItemPID string, st *model.PlayState) PlayState {
	out := PlayState{PID: apiItemPID}
	if st != nil {
		out.PositionMS = st.PositionMS
		out.Played = st.Played
		out.Finished = st.Finished
		out.PlayCount = st.PlayCount
		out.Starred = st.Starred
		if st.HasRating {
			r := st.Rating
			out.Rating = &r
		}
		if st.UpdatedAt > 0 {
			out.UpdatedAt = time.Unix(0, st.UpdatedAt).UTC()
		}
	}
	return out
}

// userPlayState picks one user's state out of the per-item batch that
// PlayStatesForItems returns (every user's state, keyed by item), or nil
// when the user has not touched the item.
func userPlayState(states []model.PlayState, userPID model.PID) *model.PlayState {
	for i := range states {
		if states[i].UserPID == userPID {
			return &states[i]
		}
	}
	return nil
}

// recencyGuard bounds how much older a replayed further position may be
// and still beat a more recent nearer one (furthest-wins media): past
// it, the nearer position was a deliberate recent rewind and wins.
const recencyGuard = 10 * time.Minute

// clampRecorded normalizes a client-reported change time: future values
// (skewed clocks) clamp to the server clock.
func clampRecorded(t time.Time) int64 {
	now := time.Now()
	if t.After(now) {
		t = now
	}
	return t.UnixNano()
}

// recencyPrimary reports whether the item's resume conflicts resolve on
// recency alone: audiobooks always, and long tracks, where a stale
// furthest position permanently losing your place is the unforgivable
// case. Episodes stay furthest-wins regardless of length.
func recencyPrimary(it *model.ItemView) bool {
	if it.Kind == model.KindBook {
		return true
	}
	return it.Kind == model.KindTrack && it.DurationMS >= musicLongTrack.Milliseconds()
}

// applyReplayedPosition is the per-medium replay decision, pure so the
// policy is testable in isolation: recency-primary media apply only
// newer-than-stamp replays; furthest-wins media additionally apply an
// older-but-further replay unless the current position is substantially
// more recent (a deliberate rewind).
func applyReplayedPosition(recencyPrim bool, positionMS, recNS, curPositionMS, stampNS int64) bool {
	if recNS > stampNS {
		return true
	}
	if recencyPrim {
		return false
	}
	return positionMS > curPositionMS && stampNS-recNS <= recencyGuard.Nanoseconds()
}

// Checkpoint persists the user's resume position for the item. WaxBin
// buffers high-frequency progress internally; Checkpoint writes
// through, which is what clients call at their coarse interval. A nil
// recordedAt is a live checkpoint and always applies; a non-nil one is
// an offline replay, reconciled per medium against the position stamp.
//
// The reported applied says whether the position moved. A skipped
// replay is a success, not an error - the winning state is already in
// the event stream - but a caller counting what it wrote (a migration
// report) must not count one, so the outcome is returned rather than
// hidden behind a nil error.
func (l *Library) Checkpoint(ctx context.Context, uc *UserCtx, apiItemPID string, positionMS int64, recordedAt *time.Time) (applied bool, err error) {
	it, err := l.getVisibleItem(ctx, uc, apiItemPID)
	if err != nil {
		return false, err
	}
	if positionMS < 0 {
		return false, errInvalid("positionMs must not be negative")
	}
	stampNS := time.Now().UnixNano()
	if recordedAt != nil {
		recNS := clampRecorded(*recordedAt)
		stamp, err := l.db.PlayStamp(ctx, uc.ID, string(it.PID))
		if err != nil {
			return false, &Error{Kind: KindInternal, Err: err}
		}
		var curPos int64
		if !recencyPrimary(it) {
			cur, err := l.lib.Playback().State(ctx, model.PID(uc.CatalogPID), it.PID)
			if err != nil {
				return false, classify(err)
			}
			if cur != nil {
				curPos = cur.PositionMS
			}
		}
		if !applyReplayedPosition(recencyPrimary(it), positionMS, recNS, curPos, stamp.PositionNS) {
			// Skipped replays answer success: the winning state is
			// already in the event stream for this client to pull.
			return false, nil
		}
		stampNS = recNS
		if stamp.PositionNS > stampNS {
			// A further-but-older replay wins the position but must not
			// rewind the stamp: replays recorded between the two times
			// would then read as newer than the newest observation and
			// apply unconditionally.
			stampNS = stamp.PositionNS
		}
	}
	if err := l.lib.Playback().Checkpoint(ctx, model.PID(uc.CatalogPID), it.PID, positionMS); err != nil {
		return false, classify(err)
	}
	if err := l.db.StampPlayState(ctx, uc.ID, string(it.PID), stampNS); err != nil {
		l.log.Warn("stamping position", "pid", apiItemPID, "err", err)
	}
	l.markSpokenWordProgress(ctx, uc, it, positionMS)
	l.emitUserEvent(ctx, uc.ID, eventPlayState, string(it.PID))
	return true, nil
}

// markSpokenWordProgress derives played and finished for podcasts and
// audiobooks from the position reached against the item's full
// duration, marking only on a transition. Position, never a
// listened-milliseconds ratio, so silence trimming and speed changes
// cannot distort the thresholds; for multi-file books the position is
// already book-timeline by contract. Best effort on the checkpoint
// path: a missed mark self-heals at the next checkpoint.
func (l *Library) markSpokenWordProgress(ctx context.Context, uc *UserCtx, it *model.ItemView, positionMS int64) {
	crossed, finished, err := l.spokenWordCrossing(ctx, uc, it, positionMS)
	if err != nil || !crossed {
		return
	}
	if err := l.lib.Playback().MarkPlayed(ctx, model.PID(uc.CatalogPID), it.PID, finished); err != nil {
		l.log.Warn("marking spoken word played", "pid", string(it.PID), "err", err)
	}
}

// spokenWordCrossing evaluates the position-derived played rules for
// podcasts and audiobooks: whether a mark is due now (a transition the
// stored state has not recorded) and whether it also finishes the
// item. Non-spoken-word items never cross here.
func (l *Library) spokenWordCrossing(ctx context.Context, uc *UserCtx, it *model.ItemView, positionMS int64) (crossed, finished bool, err error) {
	mt := mediaTypeForKind(it.Kind)
	if mt != "podcast" && mt != "audiobook" {
		return false, false, nil
	}
	// The catalog's duration already covers an episode nobody has
	// fetched: the item is fileless, and the view coalesces to the
	// length the feed declared, which is the same number every listing
	// reports. So a backlog is markable without a fetch, which is what
	// "mark older episodes as played" needs, since a fresh
	// subscription's episodes are all in exactly that state, and this
	// needs no lookup of its own. Passthrough makes streaming an
	// unfetched episode ordinary, and a checkpoint arrives every few
	// seconds while one plays, so a read here would be a read per tick.
	if it.DurationMS <= 0 {
		return false, false, nil
	}
	frac := podcastFraction
	if mt == "audiobook" {
		frac = audiobookFraction
	}
	if float64(positionMS) < frac*float64(it.DurationMS) {
		return false, false, nil
	}
	finished = float64(positionMS) >= spokenFinishedFraction*float64(it.DurationMS)
	st, err := l.lib.Playback().State(ctx, model.PID(uc.CatalogPID), it.PID)
	if err != nil {
		return false, false, classify(err)
	}
	if st != nil && st.Played {
		// One mark per listen-through: the catalog's mark increments
		// the play count unconditionally and offers no count-free way
		// to set finished afterwards, so a played item never marks
		// again (letting the later completion crossing through counted
		// every finished podcast as two plays). The recorded trade: a
		// podcast that crosses its 90 percent played bar first keeps
		// finished false when it later reaches the end; stats count
		// one play, which is the truth that matters.
		return false, false, nil
	}
	return true, finished, nil
}

// asOfNS projects a client-reported change time onto the catalog's
// as-of argument: nil for a live change (the catalog stamps its own
// clock), the clamped recorded time for an offline replay. The catalog
// enforces recorded-time last-writer-wins itself, so a stale replay is
// dropped there rather than guarded here.
func asOfNS(recordedAt *time.Time) *int64 {
	if recordedAt == nil {
		return nil
	}
	ns := clampRecorded(*recordedAt)
	return &ns
}

// SetStar stars or unstars the item for the acting user and returns the
// resulting state. A replayed offline toggle (recordedAt set) carries
// its recorded time to the catalog, which drops it when the star
// changed more recently, so a stale replay never resurrects an undone
// state.
//
// The sync event goes out only when the write changed something: the
// delta builder is a pure projection of stored events, so an event
// carrying no change carries nothing. A stale replay still learns the
// truth from the response body below.
func (l *Library) SetStar(ctx context.Context, uc *UserCtx, apiItemPID string, starred bool, recordedAt *time.Time) (PlayState, error) {
	it, err := l.getVisibleItem(ctx, uc, apiItemPID)
	if err != nil {
		return PlayState{}, err
	}
	changed, err := l.lib.Playback().SetStar(ctx, model.PID(uc.CatalogPID), it.PID, starred, asOfNS(recordedAt))
	if err != nil {
		return PlayState{}, classify(err)
	}
	if changed {
		l.emitUserEvent(ctx, uc.ID, eventPlayState, string(it.PID))
	}
	return l.playStateFor(ctx, uc, apiItemPID, it.PID)
}

// SetRating sets (0..100) or clears (nil) the acting user's rating and
// returns the resulting state. Replayed offline changes carry their
// recorded time and are ordered by the catalog, and a no-op write emits
// no sync event; see SetStar.
func (l *Library) SetRating(ctx context.Context, uc *UserCtx, apiItemPID string, rating *int, recordedAt *time.Time) (PlayState, error) {
	if rating != nil && (*rating < 0 || *rating > 100) {
		return PlayState{}, errInvalid("rating must be between 0 and 100")
	}
	it, err := l.getVisibleItem(ctx, uc, apiItemPID)
	if err != nil {
		return PlayState{}, err
	}
	changed, err := l.lib.Playback().SetRating(ctx, model.PID(uc.CatalogPID), it.PID, rating, asOfNS(recordedAt))
	if err != nil {
		return PlayState{}, classify(err)
	}
	if changed {
		l.emitUserEvent(ctx, uc.ID, eventPlayState, string(it.PID))
	}
	return l.playStateFor(ctx, uc, apiItemPID, it.PID)
}

// SetPlayed sets the acting user's played and finished flags directly
// and returns the resulting state. This is the direction the completion
// rules cannot go: markSpokenWordProgress refuses to re-mark a played
// item on purpose, and MarkPlayed is monotonic by construction, so
// undoing a mis-tapped "mark finished" needs its own verb rather than
// another position write.
//
// playCount is three-way and the caller means the difference: nil keeps
// the stored count, a zero clears it so an undo takes the play the
// mis-tap added with it, and a positive value sets it exactly. The
// catalog refuses a negative count, a finished-but-unplayed row, and a
// played row with an explicit zero count; those come back as
// invalid-request rather than as internal errors.
func (l *Library) SetPlayed(ctx context.Context, uc *UserCtx, apiItemPID string, played, finished bool, playCount *int, recordedAt *time.Time) (PlayState, error) {
	it, err := l.getVisibleItem(ctx, uc, apiItemPID)
	if err != nil {
		return PlayState{}, err
	}
	changed, err := l.lib.Playback().SetPlayed(ctx, model.PID(uc.CatalogPID), it.PID,
		played, finished, playCount, asOfNS(recordedAt))
	if err != nil {
		return PlayState{}, classify(err)
	}
	if changed {
		l.emitUserEvent(ctx, uc.ID, eventPlayState, string(it.PID))
	}
	return l.playStateFor(ctx, uc, apiItemPID, it.PID)
}

// IngestListens records a batch of listen sessions for user userID,
// deduplicating on each session's idempotency ID. Accepted sessions
// that cross their medium's played threshold also mark the item played
// in the catalog, which feeds play counts and the play-derived browse
// lists.
//
// Per-session rejections are PERMANENT by contract: a rejected session
// can never be recorded, so clients drop it from their queues. Anything
// transient (catalog maintenance, internal failures) must instead fail
// the whole request so the client retries the batch, which the
// idempotency IDs make safe. Conflating the two here silently loses
// listens.
func (l *Library) IngestListens(ctx context.Context, uc *UserCtx, sessions []ListenSession) (ListenIngestResult, error) {
	var res ListenIngestResult
	for _, s := range sessions {
		if reason := invalidSession(s); reason != "" {
			res.Rejected = append(res.Rejected, RejectedListen{
				SessionID: s.SessionID, Code: "invalid-request", Message: reason,
			})
			continue
		}
		it, err := l.getVisibleItem(ctx, uc, s.PID)
		if err != nil {
			switch KindOf(err) {
			case KindNotFound, KindInvalid:
				res.Rejected = append(res.Rejected, RejectedListen{
					SessionID: s.SessionID, Code: string(KindOf(err)), Message: "unknown item " + s.PID,
				})
				continue
			default:
				return res, err
			}
		}
		source := s.Source
		if source == "" {
			source = "live"
		}
		inserted, err := l.db.InsertListen(ctx, wdb.ListenSession{
			UserID:    uc.ID,
			SessionID: s.SessionID,
			ItemPID:   string(it.PID),
			MediaType: mediaTypeForKind(it.Kind),
			StartedAt: s.StartedAt,
			MsPlayed:  s.MsPlayed,
			SkippedMs: s.SkippedMs,
			Finished:  s.Finished,
			Client:    s.Client,
			Source:    source,
		})
		if err != nil {
			return res, &Error{Kind: KindInternal, Err: err}
		}
		if !inserted {
			res.Duplicates++
			continue
		}
		res.Accepted++
		mt := mediaTypeForKind(it.Kind)
		crossed := false
		finished := s.Finished
		switch mt {
		case "podcast", "audiobook":
			// Spoken word derives played from the position reached, never
			// the listened-milliseconds ratio (trimming and speed changes
			// must not distort it); the client finished flag counts for
			// single-file episodes but never finishes a multi-part book.
			// The stored position is the right input here even though a
			// session carries no position of its own: clients flush
			// checkpoints before listen reports (live and in the offline
			// outbox), and the checkpoint path evaluates the same crossing
			// independently, so an out-of-order listen can never lose a
			// mark for good.
			st, stErr := l.lib.Playback().State(ctx, model.PID(uc.CatalogPID), it.PID)
			if stErr != nil {
				res.Accepted--
				if delErr := l.db.DeleteListen(ctx, uc.ID, s.SessionID); delErr != nil {
					l.log.Error("compensating listen delete", "session", s.SessionID, "err", delErr)
				}
				return res, classify(stErr)
			}
			var pos int64
			if st != nil {
				pos = st.PositionMS
			}
			var evalErr error
			crossed, finished, evalErr = l.spokenWordCrossing(ctx, uc, it, pos)
			if evalErr != nil {
				res.Accepted--
				if delErr := l.db.DeleteListen(ctx, uc.ID, s.SessionID); delErr != nil {
					l.log.Error("compensating listen delete", "session", s.SessionID, "err", delErr)
				}
				return res, evalErr
			}
			if mt == "podcast" && s.Finished && (st == nil || !st.Played) {
				crossed = true
				finished = true
			}
		default:
			crossed = crossedPlayedThreshold(mt, s.MsPlayed, it.DurationMS) || s.Finished
		}
		if crossed {
			if err := l.lib.Playback().MarkPlayed(ctx, model.PID(uc.CatalogPID), it.PID, finished); err == nil {
				l.emitUserEvent(ctx, uc.ID, eventPlayState, string(it.PID))
				// A crossed music listen is exactly the scrobble
				// threshold; deliveries drain from the durable outbox.
				if mt == "music" {
					l.enqueueScrobbles(ctx, uc, it, s.StartedAt)
				}
			} else {
				err = classify(err)
				switch KindOf(err) {
				case KindNotFound, KindInvalid:
					// The mark can never apply (the item vanished mid-batch);
					// the listen itself is still valid data, so keep it.
					l.log.Warn("marking played", "pid", s.PID, "err", err)
				default:
					// Transient. The inserted row would make a retry a
					// duplicate that skips the mark forever, so take the row
					// back out and fail the batch; the retry redoes both.
					res.Accepted--
					if delErr := l.db.DeleteListen(ctx, uc.ID, s.SessionID); delErr != nil {
						l.log.Error("compensating listen delete", "session", s.SessionID, "err", delErr)
					}
					return res, err
				}
			}
		}
	}
	return res, nil
}

// invalidSession reports why a reported session can never be recorded,
// or "" when it is well formed. The declared body constraints are
// enforced here because the generated binding does not enforce them,
// and these values feed a permanent store.
func invalidSession(s ListenSession) string {
	switch {
	case s.SessionID == "":
		return "sessionId is required"
	case len(s.SessionID) > 64:
		return "sessionId must be at most 64 characters"
	case s.PID == "":
		return "pid is required"
	case s.MsPlayed < 0:
		return "msPlayed must not be negative"
	case s.SkippedMs < 0:
		return "skippedMs must not be negative"
	case len(s.Client) > 128:
		return "client must be at most 128 characters"
	case s.Source != "" && s.Source != "live" && s.Source != "import":
		return "source must be live or import"
	}
	return ""
}

// crossedPlayedThreshold applies the per-medium played rules.
func crossedPlayedThreshold(mediaType string, msPlayed, durationMS int64) bool {
	if msPlayed <= 0 {
		return false
	}
	if durationMS <= 0 {
		return false
	}
	switch mediaType {
	case "podcast":
		return float64(msPlayed) >= podcastFraction*float64(durationMS)
	case "audiobook":
		return float64(msPlayed) >= audiobookFraction*float64(durationMS)
	default:
		if float64(msPlayed) >= musicPlayedFraction*float64(durationMS) {
			return true
		}
		// The four-minute floor applies to ordinary track lengths only;
		// long tracks (DJ sets, live recordings) count proportionally.
		return msPlayed >= musicPlayedFloor.Milliseconds() &&
			durationMS <= musicLongTrack.Milliseconds()
	}
}
