package service

import (
	"context"
	"time"

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
)

// The empty user PID below selects WaxBin's default user everywhere.
// That is correct while the auth stub maps every login to one built-in
// admin; when real accounts land, these calls must bind the calling
// user's catalog PID instead (part of the identity work).

// PlayState returns the calling user's state for one item. Items never
// played return a zero state.
func (l *Library) PlayState(ctx context.Context, apiItemPID string) (PlayState, error) {
	it, err := l.getItem(ctx, apiItemPID)
	if err != nil {
		return PlayState{}, err
	}
	st, err := l.lib.Playback().State(ctx, "", it.PID)
	if err != nil {
		return PlayState{}, classify(err)
	}
	out := PlayState{PID: apiItemPID}
	if st != nil {
		out.PositionMS = st.PositionMS
		out.Played = st.Played
		out.Finished = st.Finished
		out.PlayCount = st.PlayCount
		out.Starred = st.Starred
		if st.UpdatedAt > 0 {
			out.UpdatedAt = time.Unix(0, st.UpdatedAt).UTC()
		}
	}
	return out, nil
}

// Checkpoint persists the user's resume position for the item. WaxBin
// buffers high-frequency progress internally; Checkpoint writes
// through, which is what clients call at their coarse interval.
func (l *Library) Checkpoint(ctx context.Context, apiItemPID string, positionMS int64) error {
	it, err := l.getItem(ctx, apiItemPID)
	if err != nil {
		return err
	}
	if positionMS < 0 {
		return errInvalid("positionMs must not be negative")
	}
	if err := l.lib.Playback().Checkpoint(ctx, "", it.PID, positionMS); err != nil {
		return classify(err)
	}
	return nil
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
func (l *Library) IngestListens(ctx context.Context, userID string, sessions []ListenSession) (ListenIngestResult, error) {
	var res ListenIngestResult
	for _, s := range sessions {
		if reason := invalidSession(s); reason != "" {
			res.Rejected = append(res.Rejected, RejectedListen{
				SessionID: s.SessionID, Code: "invalid-request", Message: reason,
			})
			continue
		}
		it, err := l.getItem(ctx, s.PID)
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
			UserID:    userID,
			SessionID: s.SessionID,
			ItemPID:   string(it.PID),
			MediaType: mediaTypeForKind(it.Kind),
			StartedAt: s.StartedAt,
			MsPlayed:  s.MsPlayed,
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
		if crossedPlayedThreshold(mediaTypeForKind(it.Kind), s.MsPlayed, it.DurationMS) || s.Finished {
			if err := l.lib.Playback().MarkPlayed(ctx, "", it.PID, s.Finished); err != nil {
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
					if delErr := l.db.DeleteListen(ctx, userID, s.SessionID); delErr != nil {
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
