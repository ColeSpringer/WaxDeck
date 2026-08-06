package service

import (
	"context"
	"encoding/base64"
	"fmt"
	"time"

	"github.com/colespringer/waxbin/model"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// Background podcast work: the feed refresh scheduler, the retention
// sweeper, and the enclosure fetch worker. All three are driven by
// supervised ticker loops in the composition root and share the
// process context so a shutdown stops them cleanly.

const (
	// feedDisableAfter is how many consecutive sync failures suspend a
	// feed from scheduled refresh (a successful manual refresh
	// re-enables it).
	feedDisableAfter = 10
	// fetchMaxAttempts caps enclosure download retries; the row then
	// reads as failed on the episode summary until re-queued.
	fetchMaxAttempts = 5
	// fetchLease bounds one download attempt; a crashed worker's row
	// becomes claimable again when it expires.
	fetchLease = 30 * time.Minute
)

// queueRetryDelay is the failure backoff for the durable work queues:
// one minute doubling per prior attempt, capped at half an hour, so a
// failing enclosure host or a wedged analysis is never hammered
// back-to-back.
func queueRetryDelay(attempts int) time.Duration {
	d := time.Minute << min(attempts, 5)
	if d > 30*time.Minute {
		d = 30 * time.Minute
	}
	return d
}

// RefreshDueFeeds syncs every subscribed show whose last attempt is
// older than interval, skipping disabled feeds. One failing feed never
// stops the others.
func (l *Library) RefreshDueFeeds(ctx context.Context, interval time.Duration) {
	shows, err := l.db.SubscribedShowPIDs(ctx)
	if err != nil {
		l.log.Warn("listing subscribed shows", "err", err)
		return
	}
	now := time.Now()
	for _, show := range shows {
		if ctx.Err() != nil {
			return
		}
		st, err := l.db.FeedStateFor(ctx, show)
		if err != nil {
			l.log.Warn("reading feed state", "show", show, "err", err)
			continue
		}
		if st.Disabled {
			continue
		}
		if now.Sub(time.Unix(0, st.LastAttemptNS)) < interval {
			continue
		}
		if _, err := l.syncShow(ctx, model.PID(show)); err != nil {
			// syncShow recorded the failure; the log line is the operator
			// surface until notifications land.
			l.log.Warn("scheduled feed sync failed", "show", show, "err", err)
		}
	}
}

// syncShow syncs one show now, records the outcome in feed_state, and
// fans out what a change implies: auto-download for the newest
// arrivals and a retention re-evaluation.
func (l *Library) syncShow(ctx context.Context, showPID model.PID) (int, error) {
	pod, err := l.lib.Podcasts().Get(ctx, showPID)
	if err != nil {
		return 0, classify(err)
	}
	res, err := l.lib.Podcasts().Sync(ctx, showPID)
	now := time.Now().UnixNano()
	if err != nil {
		st, dbErr := l.db.RecordFeedFailure(ctx, string(showPID), err.Error(), now, feedDisableAfter)
		if dbErr != nil {
			l.log.Warn("recording feed failure", "show", string(showPID), "err", dbErr)
		} else if st.Disabled && st.ConsecutiveFailures == feedDisableAfter {
			l.log.Warn("feed disabled after repeated failures", "show", string(showPID), "failures", st.ConsecutiveFailures)
			if subs, subErr := l.db.SubscribersByShow(ctx, string(showPID)); subErr == nil {
				userIDs := make([]string, 0, len(subs))
				for _, s := range subs {
					userIDs = append(userIDs, s.UserID)
				}
				// Titles only: feed URLs are scrubbed from every
				// notification surface, private shows especially.
				l.EmitNotification(ctx, "feed-disabled",
					"Podcast feed disabled: "+pod.Title,
					fmt.Sprintf("The feed failed %d refreshes in a row and was disabled. A manual refresh re-enables it.", st.ConsecutiveFailures),
					userIDs)
				// The same news to whoever is running a client; the pid is
				// the api show one so the row opens the show.
				apiShow := apiPID(PrefixPodcast, showPID)
				for _, uid := range userIDs {
					l.emitUserEvent(ctx, uid, eventFeedDisabled, apiShow)
				}
			}
		}
		return 0, l.classifyFeedErr(ctx, err, pod.FeedURL, l.showIsPrivate(ctx, pod))
	}
	if err := l.db.RecordFeedSuccess(ctx, string(showPID), now); err != nil {
		l.log.Warn("recording feed success", "show", string(showPID), "err", err)
	}
	if res.EpisodesAdded > 0 {
		l.autoDownloadNewest(ctx, showPID, res.EpisodesAdded)
		if err := l.db.EnqueueRetention(ctx, string(showPID), now); err != nil {
			l.log.Warn("queuing retention", "show", string(showPID), "err", err)
		}
	}
	return res.EpisodesAdded, nil
}

// autoDownloadNewest queues enclosure fetches for the newest arrivals
// that at least one subscriber's auto-download policy admits.
//
// The decision is per subscriber and per episode, because a keyword
// filter makes it so. The union is deliberate and matches retention's:
// the effective policy for a show is the most generous across its
// subscribers, so one subscriber wanting an episode is enough to fetch
// the shared file, and a filter narrows what that subscriber asks for
// rather than what everyone else gets.
func (l *Library) autoDownloadNewest(ctx context.Context, showPID model.PID, added int) {
	subs, err := l.db.SubscribersByShow(ctx, string(showPID))
	if err != nil {
		l.log.Warn("listing subscribers", "show", string(showPID), "err", err)
		return
	}
	filters := make([]EpisodeFilter, 0, len(subs))
	for _, s := range subs {
		if s.AutoDownload {
			filters = append(filters, EpisodeFilter{Include: s.AutoDLInclude, Exclude: s.AutoDLExclude})
		}
	}
	if len(filters) == 0 {
		return
	}
	eps, err := l.lib.Podcasts().Episodes(ctx, showPID, added)
	if err != nil {
		l.log.Warn("listing new episodes", "show", string(showPID), "err", err)
		return
	}
	now := time.Now().UnixNano()
	for _, ep := range eps {
		if ep.Downloaded || !anyFilterAdmits(filters, ep.Title) {
			continue
		}
		if err := l.db.EnqueueFetch(ctx, string(ep.PID), "auto", now); err != nil {
			l.log.Warn("queuing auto download", "episode", string(ep.PID), "err", err)
		}
	}
}

// anyFilterAdmits is the union: one subscriber wanting the episode is
// enough, since the downloaded file is shared.
func anyFilterAdmits(filters []EpisodeFilter, title string) bool {
	for _, f := range filters {
		if f.Admits(title) {
			return true
		}
	}
	return false
}

// DrainFetchQueue works one queued enclosure download; returns false
// when the queue is idle so the caller can sleep.
func (l *Library) DrainFetchQueue(ctx context.Context) bool {
	row, err := l.db.LeaseFetch(ctx, time.Now().UnixNano(), fetchLease.Nanoseconds(), fetchMaxAttempts)
	if err != nil {
		if err != wdb.ErrNotFound {
			l.log.Warn("leasing fetch work", "err", err)
		}
		return false
	}
	res, err := l.lib.Podcasts().Download(ctx, model.PID(row.Key))
	if err != nil {
		l.log.Warn("episode fetch failed", "episode", row.Key, "attempt", row.Attempts+1, "err", err)
		retryAt := time.Now().Add(queueRetryDelay(row.Attempts)).UnixNano()
		if dbErr := l.db.FailFetch(ctx, row.Key, err.Error(), retryAt); dbErr != nil {
			l.log.Warn("recording fetch failure", "episode", row.Key, "err", dbErr)
		}
		return true
	}
	if err := l.db.CompleteFetch(ctx, row.Key); err != nil {
		l.log.Warn("completing fetch", "episode", row.Key, "err", err)
	}
	l.log.Info("episode fetched", "episode", row.Key, "bytes", res.Bytes)
	// Bytes now exist where the located-path cache saw none, and it only
	// drops entries on its own poll: until refreshed, analysis resolves no
	// file and play-info answers not-found for a downloaded episode.
	if _, err := l.paths.Relocate(ctx, model.PID(row.Key)); err != nil {
		l.log.Warn("refreshing a fetched episode's path", "episode", row.Key, "err", err)
	}
	// A fresh spoken-word file wants a silence map; queue analysis by
	// essence so a replayed fetch never duplicates the work.
	l.enqueueAnalysisForItem(ctx, model.PID(row.Key))
	l.notifyEpisodeDownloaded(ctx, model.PID(row.Key))
	return true
}

// notifyEpisodeDownloaded fans a finished download out to the show's
// subscribers and the admin relay. Best effort by design.
func (l *Library) notifyEpisodeDownloaded(ctx context.Context, episodePID model.PID) {
	det, err := l.lib.Podcasts().Episode(ctx, episodePID)
	if err != nil {
		return
	}
	subs, err := l.db.SubscribersByShow(ctx, string(det.Episode.PodcastPID))
	if err != nil {
		l.log.Warn("reading subscribers for notification", "err", err)
		return
	}
	userIDs := make([]string, 0, len(subs))
	for _, s := range subs {
		userIDs = append(userIDs, s.UserID)
	}
	show := det.Episode.PodcastTitle
	if show == "" {
		show = "podcast"
	}
	l.EmitNotification(ctx, "episode-downloaded", "New episode: "+show, det.Episode.Title, userIDs)
	// The same news to whoever is running a client; the pid is the
	// episode so the row opens it.
	for _, uid := range userIDs {
		l.emitUserEvent(ctx, uid, eventEpisodeDownloaded, apiPID(PrefixEpisode, det.Episode.PID))
	}
}

// SweepRetention re-evaluates every queued show: pushes the union
// keep-N into the catalog, protects starred and queued episodes by
// pinning, and applies retention only when no candidate file is in
// use. Deferred shows re-queue for the next cycle.
func (l *Library) SweepRetention(ctx context.Context) {
	shows, err := l.db.TakeRetentionQueue(ctx)
	if err != nil {
		l.log.Warn("draining retention queue", "err", err)
		return
	}
	for _, show := range shows {
		if ctx.Err() != nil {
			return
		}
		if err := l.sweepShowRetention(ctx, model.PID(show)); err != nil {
			l.log.Warn("retention sweep", "show", show, "err", err)
		}
	}
}

func (l *Library) sweepShowRetention(ctx context.Context, showPID model.PID) error {
	subs, err := l.db.SubscribersByShow(ctx, string(showPID))
	if err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	if len(subs) == 0 {
		// A show nobody follows keeps its files; destructive cleanup is
		// an explicit admin decision, never a side effect (removing the
		// show would cascade away every user's play history).
		return nil
	}
	keep := l.unionRetention(subs)
	if err := l.lib.Podcasts().SetRetention(ctx, showPID, int(keep)); err != nil {
		return classify(err)
	}
	if keep == 0 {
		return nil
	}

	eps, err := l.lib.Podcasts().Episodes(ctx, showPID, 0)
	if err != nil {
		return classify(err)
	}
	// Newest-first downloaded episodes; the ones beyond keep are what
	// the catalog's sweep would remove, minus pinned.
	downloaded := make([]*model.Episode, 0, len(eps))
	for _, ep := range eps {
		if ep.Downloaded {
			downloaded = append(downloaded, ep)
		}
	}
	if int64(len(downloaded)) <= keep {
		return nil
	}
	candidates := downloaded[keep:]

	// Protection pass: starred-by-any-subscriber or sitting in any
	// subscriber's queue pins the episode (the catalog's own retention
	// exemption); in-use defers the whole show to the next cycle.
	users := make([]model.PID, 0, len(subs))
	for _, s := range subs {
		if u, err := l.userCatalogPID(ctx, s.UserID); err == nil && u != "" {
			users = append(users, u)
		}
	}
	queued := l.queuedItems(ctx, users)
	inUse := false
	for _, ep := range candidates {
		protect := queued[ep.PID]
		for _, u := range users {
			st, err := l.lib.Playback().State(ctx, u, ep.PID)
			if err != nil {
				continue
			}
			if st.Starred {
				protect = true
			}
			if l.stateReadsInUse(st) {
				inUse = true
			}
		}
		if protect != ep.Pinned {
			if err := l.setEpisodePinned(ctx, showPID, ep, protect); err != nil {
				l.log.Warn("pinning episode", "episode", string(ep.PID), "err", err)
			}
		}
	}
	if inUse {
		if err := l.db.EnqueueRetention(ctx, string(showPID), time.Now().UnixNano()); err != nil {
			l.log.Warn("re-queuing deferred retention", "show", string(showPID), "err", err)
		}
		return nil
	}

	res, err := l.lib.Podcasts().ApplyRetention(ctx, showPID)
	if err != nil {
		return classify(err)
	}
	if res.Removed > 0 {
		l.log.Info("retention reclaimed episodes", "show", string(showPID),
			"removed", res.Removed, "bytes", res.ReclaimedBytes)
	}
	return nil
}

// stateReadsInUse reports whether one user's play state looks like
// live playback: a position that moved within the window (live clients
// checkpoint every few seconds), unfinished. Removing a file under an
// active listener kills their stream, so both the retention sweep and
// manual removal consult this. A negative window disables the guard.
func (l *Library) stateReadsInUse(st *model.PlayState) bool {
	if st == nil || l.retentionInUseWindow <= 0 {
		return false
	}
	return st.UpdatedAt > time.Now().Add(-l.retentionInUseWindow).UnixNano() &&
		st.PositionMS > 0 && !st.Finished
}

// unionRetention resolves the most generous keep-N across subscribers:
// any keep-all wins; otherwise the largest N. Unset rows use the
// server default.
func (l *Library) unionRetention(subs []wdb.Subscription) int64 {
	keep := int64(-1)
	for _, s := range subs {
		eff := l.defaultRetentionKeep
		if s.RetentionKeep != nil {
			eff = *s.RetentionKeep
		}
		if eff == 0 {
			return 0
		}
		if eff > keep {
			keep = eff
		}
	}
	if keep < 0 {
		return 0
	}
	return keep
}

// queuedItems collects every item sitting in any of the given users'
// persistent play queues.
func (l *Library) queuedItems(ctx context.Context, users []model.PID) map[model.PID]bool {
	out := make(map[model.PID]bool)
	for _, u := range users {
		items, err := l.lib.Playback().Queue(ctx, u)
		if err != nil {
			continue
		}
		for _, it := range items {
			out[it.PID] = true
		}
	}
	return out
}

// userCatalogPID maps a WaxDeck user id to its catalog user.
func (l *Library) userCatalogPID(ctx context.Context, userID string) (model.PID, error) {
	u, err := l.db.UserByID(ctx, userID)
	if err != nil {
		return "", err
	}
	return model.PID(u.WaxbinUserPID), nil
}

// setEpisodePinned re-upserts the episode with only the pinned flag
// changed. The upsert path preserves state and identity when every
// field round-trips, which feedEpisodeOf guarantees by copying them
// all.
func (l *Library) setEpisodePinned(ctx context.Context, showPID model.PID, ep *model.Episode, pinned bool) error {
	_, err := l.lib.Podcasts().AddEpisode(ctx, showPID, feedEpisodeOf(ep), pinned)
	return classify(err)
}

// feedEpisodeOf mirrors a cataloged episode back into its feed shape,
// field for field, so a pin-only upsert changes nothing else.
func feedEpisodeOf(ep *model.Episode) model.FeedEpisode {
	return model.FeedEpisode{
		GUID:           ep.GUID,
		Title:          ep.Title,
		Description:    ep.Description,
		Link:           ep.Link,
		PubDateNS:      ep.PubDateNS,
		Year:           ep.Year,
		Season:         ep.Season,
		EpisodeNo:      ep.EpisodeNo,
		EpisodeType:    ep.EpisodeType,
		DurationMS:     ep.DurationMS,
		Explicit:       ep.Explicit,
		EnclosureURL:   ep.EnclosureURL,
		EnclosureType:  ep.EnclosureType,
		EnclosureSize:  ep.EnclosureSize,
		TranscriptURL:  ep.TranscriptURL,
		TranscriptType: ep.TranscriptType,
		ChaptersURL:    ep.ChaptersURL,
		ImageURL:       ep.ImageURL,
	}
}

// --- opaque cursor helpers ---------------------------------------------------

func encodeOpaqueCursor(raw string) string {
	return base64.RawURLEncoding.EncodeToString([]byte(raw))
}

func decodeOpaqueCursor(s string) (string, bool) {
	raw, err := base64.RawURLEncoding.DecodeString(s)
	if err != nil {
		return "", false
	}
	return string(raw), true
}
