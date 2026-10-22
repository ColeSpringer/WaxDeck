package service

import (
	"cmp"
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"hash/fnv"
	"log/slog"
	"sync"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/podcast"
	"github.com/colespringer/waxbin/source"
	"github.com/colespringer/waxbin/waxerr"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// Background podcast work: the feed refresh scheduler, the retries of
// feeds gpodder devices added, the retention sweeper, and the enclosure
// fetch worker. All are driven by supervised ticker loops in the
// composition root and share the process context so a shutdown stops
// them cleanly.

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
	if l.Maintenance() {
		return
	}
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
		if !l.showHeard(ctx, model.PID(show)) {
			continue
		}
		// syncShow records and logs a failure itself.
		_, _ = l.syncShow(ctx, model.PID(show), syncOwn)
	}
}

// RetryPendingGpodder tries every parked feed that is due, landing it for
// the devices that asked, which hold it then and whose add reaches the
// account's other devices as any add does.
func (l *Library) RetryPendingGpodder(ctx context.Context) {
	l.RetryPendingGpodderAt(ctx, time.Now())
}

// RetryPendingGpodderAt is RetryPendingGpodder on a given clock. A feed
// that fails for good, or is still failing a week after it was first
// asked for, is dropped and the account's inbox says so.
func (l *Library) RetryPendingGpodderAt(ctx context.Context, now time.Time) {
	if l.Maintenance() {
		return
	}
	due, err := l.db.DueGpodderParks(ctx, now.UnixNano(), 100)
	if err != nil {
		l.log.Warn("listing parked gpodder feeds", "err", err)
		return
	}
	accounts := map[string]*UserCtx{}
	notices := map[string][]gpodderNotice{}
	// However the pass ends: a try that panics takes the pass down, and
	// what the tries before it gave up on is still the account's to hear.
	defer func() {
		for id, uc := range accounts {
			l.fileGpodderNotices(ctx, uc, notices[id])
		}
	}()
	for _, p := range due {
		if ctx.Err() != nil {
			break
		}
		uc, notice := l.retryGpodderPark(ctx, p, now)
		if notice != nil {
			accounts[uc.ID] = uc
			notices[uc.ID] = append(notices[uc.ID], *notice)
		}
	}
}

// retryGpodderPark tries one parked feed, answering what the account's
// inbox is to say about it, if anything. It goes by the park's asks as
// they stand when the retry reaches it, read under the account lock: the
// park is as old as the first of them, and only their schedule is the
// retry's to move, an ask parked meanwhile keeping its own. The try is
// counted, and the next one scheduled, before it is made, so a try that
// panics moves its park back and holds up only itself. A park whose
// account cannot see the podcast library waits for the grant, untried and
// uncounted, until its week is up.
func (l *Library) retryGpodderPark(ctx context.Context, p wdb.GpodderPark, now time.Time) (*UserCtx, *gpodderNotice) {
	read, err := func() ([]wdb.GpodderPending, error) {
		defer l.lockMembership(p.UserID)()
		return l.db.GpodderParkAsks(ctx, p.UserID, p.FeedURL)
	}()
	if err != nil {
		l.log.Warn("reading a parked gpodder feed", "err", err)
		return nil, nil
	}
	if len(read) == 0 {
		return nil, nil
	}
	attempts, lastErr := 0, ""
	for _, a := range read {
		if a.Attempts >= attempts {
			attempts, lastErr = a.Attempts, a.LastError
		}
	}
	reschedule := func(tries int, reason string) {
		if err := l.db.RescheduleGpodderParkAsks(ctx, p.UserID, p.FeedURL, read, tries,
			now.Add(gpodderRetryDelay(tries)).UnixNano(), reason); err != nil {
			l.log.Warn("rescheduling a parked gpodder feed", "err", err)
		}
	}
	// Only an account that can sign in has anything landed for it; a
	// disabled, pending or deleted one has its parked feeds dropped.
	uc, err := l.userCtxByID(ctx, p.UserID)
	if KindOf(err) == KindNotFound {
		if err := l.db.DeleteGpodderPending(ctx, p.UserID, p.FeedURL); err != nil {
			l.log.Warn("dropping a parked gpodder feed", "err", err)
		}
		return nil, nil
	}
	if err != nil {
		l.log.Warn("reading the account of a parked gpodder feed", "err", err)
		reschedule(attempts+1, string(KindOf(err)))
		return nil, nil
	}
	expired := now.Sub(time.Unix(0, read[0].CreatedAtNS)) >= gpodderPendingLifetime
	if !expired && !l.podcastsVisible(ctx, uc) {
		reschedule(attempts, lastErr)
		return uc, nil
	}
	reschedule(attempts+1, lastErr)
	// The landing holds the show for every device still asking when it
	// attaches, and for none once they all let go while this pass was on
	// its way to the park.
	_, _, err = l.subscribe(ctx, uc, SubscribeRequest{URL: p.FeedURL},
		subChangeMeta{park: p.FeedURL, parkOnly: true, failureLog: slog.LevelDebug})
	if err == nil || errors.Is(err, errParkWithdrawn) {
		return uc, nil
	}
	why, reason := subscribeFailure(err)
	switch {
	case !gpodderAddCanPass(err):
		return uc, l.giveUpGpodderPark(ctx, uc, p.FeedURL, read, now, false,
			gpodderNotice{feedURL: p.FeedURL, why: why, account: gpodderRefusesEveryFeed(err), off: errors.Is(err, ErrPodcastsOff)})
	case expired:
		return uc, l.giveUpGpodderPark(ctx, uc, p.FeedURL, read, now, true,
			gpodderNotice{feedURL: p.FeedURL, why: why, expired: true})
	default:
		reschedule(attempts+1, cmp.Or(reason, string(KindOf(err))))
		return uc, nil
	}
}

// syncOrigin says who asked for a sync, which decides what a failure is
// allowed to conclude about the feed.
type syncOrigin int

const (
	// syncOwn is this server's own cadence: the scheduled refresh and a
	// subscriber's manual one. A run of failures there is real evidence
	// the feed is broken, so it walks the disable counter.
	syncOwn syncOrigin = iota
	// syncPinged is a third party naming the feed on a public chain.
	// The attempt is recorded so the floor that keeps this server off a
	// struggling host survives a restart, but the failure counts for
	// nothing: strangers do not get to disable a subscription.
	syncPinged
)

// syncShow syncs one show now, records the outcome in feed_state, and
// fans out what a change implies: auto-download for what the sync added
// and a retention re-evaluation.
func (l *Library) syncShow(ctx context.Context, showPID model.PID, origin syncOrigin) (int, error) {
	pod, err := l.lib.Podcasts().Get(ctx, showPID)
	if err != nil {
		l.syncWithoutVerdict(ctx, showPID, origin, err)
		return 0, classify(err)
	}
	started := time.Now().UnixNano()
	res, err := l.lib.Podcasts().Sync(ctx, showPID)
	now := time.Now().UnixNano()
	if err != nil {
		// A ping is a stranger's news and a server-side failure is not the
		// feed's, so neither walks the counter. See syncPinged.
		if origin == syncPinged || !feedAtFault(ctx, err) {
			l.syncWithoutVerdict(ctx, showPID, origin, err)
			if feedAtFault(ctx, err) {
				return 0, feedUnreachable(err)
			}
			return 0, classify(err)
		}
		unreachable := feedUnreachable(err)
		reason, cause := FeedFailureReason(unreachable), feedCause(err)
		l.log.Warn("feed sync failed", "show", string(showPID), "reason", reason, "cause", cause)
		// The error repeats the feed's address, which can be its own
		// credential: the state keeps the sentence and the cause instead.
		st, dbErr := l.db.RecordFeedFailure(ctx, string(showPID),
			fmt.Sprintf("%s (%s)", feedSentences[reason], cause), now, feedDisableAfter)
		if dbErr != nil {
			l.log.Warn("recording feed failure", "show", string(showPID), "err", dbErr)
		} else if st.Disabled && st.ConsecutiveFailures == feedDisableAfter {
			l.log.Warn("feed disabled after repeated failures", "show", string(showPID), "failures", st.ConsecutiveFailures)
			if subs, subErr := l.db.SubscribersByShow(ctx, string(showPID)); subErr == nil {
				subs, _ = l.podcastListeners(ctx, subs)
				userIDs := make([]string, 0, len(subs))
				for _, s := range subs {
					userIDs = append(userIDs, s.UserID)
				}
				// Titles only: feed URLs are scrubbed from every
				// notification surface, private shows especially.
				apiShow := apiPID(PrefixPodcast, showPID)
				title := clipFeedTitle(pod.Title)
				l.EmitNotificationFor(ctx, "feed-disabled",
					"Podcast feed disabled: "+title,
					// The show's own name, even though the title carries
					// it too: the inbox row draws the body as its detail
					// line under a localized heading, and two disabled
					// feeds must not read identically there.
					fmt.Sprintf("%s failed %d refreshes in a row and was disabled. A manual refresh re-enables it.",
						title, st.ConsecutiveFailures),
					apiShow, userIDs)
				// The same news to whoever is running a client; the pid is
				// the api show one so the row opens the show.
				for _, uid := range userIDs {
					l.emitUserEvent(ctx, uid, eventFeedDisabled, apiShow)
				}
			}
		}
		return 0, unreachable
	}
	if err := l.db.RecordFeedSuccess(ctx, string(showPID), now); err != nil {
		l.log.Warn("recording feed success", "show", string(showPID), "err", err)
	}
	if res.EpisodesAdded > 0 {
		l.handleArrivals(ctx, pod, started, res.EpisodesAdded)
		if err := l.db.EnqueueRetention(ctx, string(showPID), now); err != nil {
			l.log.Warn("queuing retention", "show", string(showPID), "err", err)
		}
	}
	return res.EpisodesAdded, nil
}

// handleArrivals tells subscribers what a sync added, those the catalog
// created at or after since, and queues what their auto-download policies
// admit, from one read of the subscribers and of the listing.
func (l *Library) handleArrivals(ctx context.Context, pod *model.Podcast, since int64, added int) {
	subs, err := l.db.SubscribersByShow(ctx, string(pod.PID))
	if err != nil {
		l.log.Warn("listing subscribers", "show", string(pod.PID), "err", err)
		return
	}
	if subs, _ = l.podcastListeners(ctx, subs); len(subs) == 0 {
		return
	}
	// The top rows, unless an arrival is dated among older episodes.
	eps, err := l.lib.Podcasts().Episodes(ctx, pod.PID, added)
	if err == nil && !allCreatedSince(eps, since) {
		eps, err = l.lib.Podcasts().Episodes(ctx, pod.PID, 0)
	}
	if err != nil {
		l.log.Warn("listing new episodes", "show", string(pod.PID), "err", err)
		return
	}
	l.notifyArrivals(ctx, pod, subs, eps, since)
	l.autoDownloadArrivals(ctx, subs, eps, since)
}

// notifyArrivals tells every subscriber of a show what a sync added,
// once per sync, whether or not they download automatically. Best effort
// by design.
func (l *Library) notifyArrivals(ctx context.Context, pod *model.Podcast, subs []wdb.Subscription, eps []*model.Episode, since int64) {
	var arrived []*model.Episode
	for _, ep := range eps {
		if ep.CreatedAt >= since {
			arrived = append(arrived, ep)
		}
	}
	if len(arrived) == 0 {
		return
	}
	// Newest first, as the listing is: the body leads with the latest.
	body := clipFeedTitle(arrived[0].Title)
	if len(arrived) > 1 {
		body = fmt.Sprintf("%s and %d more", body, len(arrived)-1)
	}
	userIDs := make([]string, 0, len(subs))
	for _, s := range subs {
		userIDs = append(userIDs, s.UserID)
	}
	l.EmitNotificationFor(ctx, "episode-arrived", "New episode: "+cmp.Or(clipFeedTitle(pod.Title), "podcast"), body,
		apiPID(PrefixPodcast, pod.PID), userIDs)
}

// syncWithoutVerdict stamps a sync that says nothing about the feed, so
// the next waits its turn, and logs this server's own.
func (l *Library) syncWithoutVerdict(ctx context.Context, showPID model.PID, origin syncOrigin, err error) {
	if origin == syncOwn {
		// A switched-off source fails every poll until it is back.
		level := slog.LevelWarn
		if waxerr.CodeOf(err) == waxerr.CodeUnsupported {
			level = slog.LevelDebug
		}
		l.log.Log(ctx, level, "feed sync failed on this server's side", "show", string(showPID), "err", err)
	}
	if ctx.Err() != nil {
		return
	}
	if dbErr := l.db.RecordFeedAttempt(ctx, string(showPID), time.Now().UnixNano()); dbErr != nil {
		l.log.Warn("recording feed attempt", "show", string(showPID), "err", dbErr)
	}
}

// feedAtFault reports whether a sync failed on the feed itself: the catalog
// marks every failure of a feed's provider, and any other is its own.
func feedAtFault(ctx context.Context, err error) bool {
	if ctx.Err() != nil || errors.Is(err, context.Canceled) || waxerr.CodeOf(err) == waxerr.CodeCanceled ||
		kindFromWaxErr(err) == KindMaintenance {
		return false
	}
	return source.IsProviderError(err)
}

// autoDownloadArrivals queues enclosure fetches for the episodes a sync
// added, those the catalog created at or after since, that at least one
// subscriber's auto-download policy admits. Arrival, not date: a sync
// can add an episode older than ones already held (a backfill, or a
// YouTube stream that ended after a newer upload), and the catalog
// reports only a count. Retention keeps the newest downloads by date,
// so an arrival dated behind as many as it keeps is left alone rather
// than fetched for the next sweep to remove.
//
// The decision is per subscriber and per episode, because a keyword
// filter makes it so. The union is deliberate and matches retention's:
// the effective policy for a show is the most generous across its
// subscribers, so one subscriber wanting an episode is enough to fetch
// the shared file, and a filter narrows what that subscriber asks for
// rather than what everyone else gets.
func (l *Library) autoDownloadArrivals(ctx context.Context, subs []wdb.Subscription, eps []*model.Episode, since int64) {
	filters := make([]EpisodeFilter, 0, len(subs))
	for _, s := range subs {
		if s.AutoDownload {
			filters = append(filters, EpisodeFilter{Include: s.AutoDLInclude, Exclude: s.AutoDLExclude})
		}
	}
	if len(filters) == 0 {
		return
	}
	keep := l.unionRetention(subs)
	kept := int64(0) // downloads ahead of this episode by date, fetched ones counted
	now := time.Now().UnixNano()
	for _, ep := range eps {
		if keep > 0 && kept >= keep {
			break
		}
		if ep.Downloaded {
			kept++
			continue
		}
		if ep.CreatedAt < since || !anyFilterAdmits(filters, ep.Title) || l.playlistEnclosure(ctx, ep) {
			continue
		}
		if err := l.db.EnqueueFetch(ctx, string(ep.PID), "", now, fetchMaxAttempts); err != nil {
			l.log.Warn("queuing auto download", "episode", string(ep.PID), "err", err)
		}
		kept++
	}
}

// allCreatedSince reports whether every episode arrived at or after
// since.
func allCreatedSince(eps []*model.Episode, since int64) bool {
	for _, ep := range eps {
		if ep.CreatedAt < since {
			return false
		}
	}
	return true
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
// when the queue is idle so the caller can sleep. A hand-off or a
// read-only server leaves the queue waiting for it.
func (l *Library) DrainFetchQueue(ctx context.Context) bool {
	if l.Maintenance() || l.checkPodcastWritable(ctx) != nil {
		return false
	}
	row, err := l.db.LeaseFetch(ctx, time.Now().UnixNano(), fetchLease.Nanoseconds(), fetchMaxAttempts)
	if err != nil {
		if err != wdb.ErrNotFound {
			l.log.Warn("leasing fetch work", "err", err)
		}
		return false
	}
	det, err := l.lib.Podcasts().Episode(ctx, model.PID(row.Key))
	if waxerr.CodeOf(err) == waxerr.CodeNotFound {
		if err := l.db.CompleteFetch(ctx, row.Key); err != nil {
			l.log.Warn("dropping the fetch of a vanished episode", "episode", row.Key, "err", err)
		}
		return true
	}
	if err != nil {
		l.failFetch(ctx, row, err)
		return true
	}
	if l.playlistEnclosure(ctx, det.Episode) {
		if err := l.db.AbandonFetch(ctx, row.Key, downloadSentences[reasonNotAFeed], fetchMaxAttempts); err != nil {
			l.log.Warn("dropping the fetch of a playlist", "episode", row.Key, "err", err)
		}
		return true
	}
	show := det.Episode.PodcastPID
	// A download's commit tail waits out a busy podcast lease itself (30s
	// budget); losing past that arrives here as any other failure and
	// rides the existing backoff.
	var requesters []string
	res, err := l.downloadHeld(ctx, show, model.PID(row.Key), func() {
		// Everyone who asked, whenever they did: asking while it ran
		// counts, and retention keeps the file for each of them.
		var err error
		requesters, err = l.db.FinishFetch(ctx, row.Key, string(show), time.Now().UnixNano())
		if err != nil && !errors.Is(err, wdb.ErrNotFound) {
			l.log.Warn("completing fetch", "episode", row.Key, "err", err)
		}
	})
	if err != nil {
		l.failFetch(ctx, row, err)
		return true
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
	// The show may hold more downloads now than its followers keep: an
	// automatic fetch, or one landing among the newest it keeps, pushes
	// an older file past the cut. A requested older one is held anyway.
	if len(requesters) == 0 || l.landedInsideKeep(ctx, show, model.PID(row.Key)) {
		if err := l.db.EnqueueRetention(ctx, string(show), time.Now().UnixNano()); err != nil {
			l.log.Warn("queuing retention", "show", string(show), "err", err)
		}
	}
	l.notifyEpisodeDownloaded(ctx, model.PID(row.Key), requesters)
	return true
}

// landedInsideKeep reports whether a landed episode is among the newest
// downloads its show keeps. A read that fails answers true, leaving the
// sweep to judge.
func (l *Library) landedInsideKeep(ctx context.Context, showPID, episodePID model.PID) bool {
	pod, err := l.lib.Podcasts().Get(ctx, showPID)
	if err != nil {
		return true
	}
	if pod.RetentionKeep <= 0 {
		return false
	}
	eps, err := l.lib.Podcasts().Episodes(ctx, showPID, 0)
	if err != nil {
		return true
	}
	newer := 0
	for _, ep := range eps {
		if ep.PID == episodePID {
			return newer < pod.RetentionKeep
		}
		if ep.Downloaded {
			newer++
		}
	}
	return false
}

// failFetch records a failed attempt and its backoff. The error repeats
// the enclosure's address, which a private feed's token can be in: the
// log keeps the reason and a cause without it, and the queue, which the
// episode's listing reads, a sentence.
func (l *Library) failFetch(ctx context.Context, row wdb.QueueRow, err error) {
	why := "The episode could not be saved on this server."
	if feedAtFault(ctx, err) {
		reason := feedReason(err)
		why = downloadSentences[reason]
		l.log.Warn("episode fetch failed", "episode", row.Key, "attempt", row.Attempts+1,
			"reason", reason, "cause", feedCause(err))
	} else {
		l.log.Warn("episode fetch failed on this server's side", "episode", row.Key, "attempt", row.Attempts+1,
			"err", hostOnly(err.Error()))
	}
	retryAt := time.Now().Add(queueRetryDelay(row.Attempts)).UnixNano()
	if dbErr := l.db.FailFetch(ctx, row.Key, why, retryAt); dbErr != nil {
		l.log.Warn("recording fetch failure", "episode", row.Key, "err", dbErr)
	}
}

// showHold is the stripe that keeps a download from landing in a show
// while its retention sweep runs. The sweep judges a snapshot of the
// show's downloads, and the catalog cuts whatever is downloaded when it
// gets there: a landing in between would move the cut onto an episode
// whose guards were never read.
func (l *Library) showHold(showPID model.PID) *sync.Mutex {
	h := fnv.New32a()
	_, _ = h.Write([]byte(showPID))
	return &l.showHolds[h.Sum32()%playedStripes]
}

// downloadHeld fetches one episode under its show's hold, which a sweep
// of the show waits out by deferring, and runs landed before letting go,
// so what a landing records is there before any sweep looks.
func (l *Library) downloadHeld(ctx context.Context, showPID, episodePID model.PID, landed func()) (*podcast.DownloadResult, error) {
	hold := l.showHold(showPID)
	hold.Lock()
	defer hold.Unlock()
	res, err := l.lib.Podcasts().Download(ctx, episodePID)
	if err == nil {
		landed()
	}
	return res, err
}

// notifyEpisodeDownloaded files a finished download in the inbox of each
// account that asked for it, and tells every subscriber's client the
// episode is downloaded now. An automatic fetch files nothing: its
// arrival was the news. Best effort by design.
func (l *Library) notifyEpisodeDownloaded(ctx context.Context, episodePID model.PID, requesters []string) {
	det, err := l.lib.Podcasts().Episode(ctx, episodePID)
	if err != nil {
		return
	}
	apiEpisode := apiPID(PrefixEpisode, det.Episode.PID)
	// Neither the news nor the marker reaches an account that cannot see
	// the podcast library; the download itself ran for it all the same.
	var heard []string
	for _, id := range requesters {
		if visible, _ := l.hearsPodcasts(ctx, id); visible {
			heard = append(heard, id)
		}
	}
	if len(heard) > 0 {
		l.EmitNotificationFor(ctx, "episode-downloaded", "Episode fetched: "+clipFeedTitle(det.Episode.Title),
			cmp.Or(clipFeedTitle(det.Episode.PodcastTitle), "podcast"), apiEpisode, heard)
	}
	subs, err := l.db.SubscribersByShow(ctx, string(det.Episode.PodcastPID))
	if err != nil {
		l.log.Warn("reading subscribers for notification", "err", err)
		return
	}
	subs, _ = l.podcastListeners(ctx, subs)
	// The pid is the episode, so a client's row flips.
	for _, s := range subs {
		l.emitUserEvent(ctx, s.UserID, eventEpisodeDownloaded, apiEpisode)
	}
}

// SweepRetention re-evaluates every queued show: pushes the union
// keep-N into the catalog, protects starred and queued episodes by
// pinning, and applies retention only when no candidate file is in
// use. Deferred shows re-queue for the next cycle.
func (l *Library) SweepRetention(ctx context.Context) {
	// Taken, the queue is gone; a hand-off would fail every show in it.
	if l.Maintenance() {
		return
	}
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
	// A download landing in the show, or in one sharing its stripe, waits
	// the show for the next cycle; the landing queues it again anyway.
	hold := l.showHold(showPID)
	if !hold.TryLock() {
		l.deferRetention(ctx, showPID)
		return nil
	}
	defer hold.Unlock()
	subs, err := l.db.SubscribersByShow(ctx, string(showPID))
	if err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	// Only followers who can see the podcast library have a say, and the
	// union is taken over every one of them or not at all: a follower who
	// could not be judged may be the vote keeping what the rest let go, so
	// the show waits for the next cycle. A show none of them follows keeps
	// its files; destructive cleanup is an explicit admin decision, never
	// a side effect (removing the show would cascade away every user's
	// play history).
	listening, judged := l.podcastListeners(ctx, subs)
	if !judged {
		l.deferRetention(ctx, showPID)
		return nil
	}
	if len(listening) == 0 {
		return nil
	}
	keep := l.unionRetention(listening)
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
	holds, err := l.liveHolds(ctx, showPID, downloaded)
	if err != nil {
		l.log.Warn("retention deferred on a failed read", "show", string(showPID), "err", err)
		l.deferRetention(ctx, showPID)
		return nil
	}
	if int64(len(downloaded)) <= keep {
		return nil
	}
	candidates := downloaded[keep:]

	// Protection pass: starred-by-any-subscriber, sitting in any
	// subscriber's queue or held for a listening requester pins the
	// episode (the catalog's own retention exemption); in-use defers the
	// whole show to the next cycle, and so does a guard that could not be
	// read, before any pin moves.
	protect, inUse, stale, err := l.retentionGuards(ctx, subs, listening, holds, downloaded, candidates)
	if err != nil {
		l.log.Warn("retention deferred on a failed read", "show", string(showPID), "err", err)
		l.deferRetention(ctx, showPID)
		return nil
	}
	if err := l.db.DropFetchHolds(ctx, stale); err != nil {
		l.log.Warn("dropping spent download holds", "show", string(showPID), "err", err)
	}
	pinned := true
	for _, ep := range candidates {
		if protect[ep.PID] != ep.Pinned {
			if err := l.setEpisodePinned(ctx, showPID, ep, protect[ep.PID]); err != nil {
				l.log.Warn("pinning episode", "episode", string(ep.PID), "err", err)
				pinned = pinned && !protect[ep.PID]
			}
		}
	}
	// A pin that did not land protects nothing, and a read-only server
	// defers the show the same way. An unpin that did not land keeps its
	// episode, which holds nothing else back.
	if inUse || !pinned || l.checkPodcastWritable(ctx) != nil {
		l.deferRetention(ctx, showPID)
		return nil
	}

	res, err := l.lib.Podcasts().ApplyRetention(ctx, showPID)
	if err != nil {
		if KindOf(err) == KindConflict {
			// Another holder of the podcast filesystem lease. Same
			// deferral as in-use above: try the show again next cycle.
			l.log.Debug("retention deferred by a busy podcast lease", "show", string(showPID))
			l.deferRetention(ctx, showPID)
			return nil
		}
		return classify(err)
	}
	if res.Removed > 0 {
		l.log.Info("retention reclaimed episodes", "show", string(showPID),
			"removed", res.Removed, "bytes", res.ReclaimedBytes)
	}
	return nil
}

// deferRetention queues the show for the next sweep.
func (l *Library) deferRetention(ctx context.Context, showPID model.PID) {
	if err := l.db.EnqueueRetention(ctx, string(showPID), time.Now().UnixNano()); err != nil {
		l.log.Warn("re-queuing deferred retention", "show", string(showPID), "err", err)
	}
}

// retentionGuards reads what keeps a sweep's candidates: a star of any
// subscriber or a place in any subscriber's queue protects one, as does a
// download a listening subscriber asked for and has not finished, and
// anyone's play in progress holds the show, a reader who follows nothing
// included, since the file is shared. A read that fails with anything but
// not-found fails the answer: the guards it would have shown are unknown.
//
// holds are those on the show's files on the server (liveHolds); stale
// is the ones that keep nothing any more, of a requester who stopped
// following the show or finished the episode after asking for it. A
// requester who cannot see the podcast library keeps the hold for the
// grant's return, and it protects nothing meanwhile.
func (l *Library) retentionGuards(ctx context.Context, subs, listening []wdb.Subscription, holds []wdb.FetchHold,
	downloaded, candidates []*model.Episode,
) (protect map[model.PID]bool, inUse bool, stale []wdb.FetchHold, err error) {
	users := make(map[model.PID]bool, len(subs))
	catalogOf := make(map[string]model.PID, len(subs))
	for _, s := range subs {
		u, err := l.userCatalogPID(ctx, s.UserID)
		if errors.Is(err, wdb.ErrNotFound) {
			continue
		}
		if err != nil {
			return nil, false, nil, fmt.Errorf("reading subscriber %s: %w", s.UserID, err)
		}
		if u != "" {
			users[u] = true
			catalogOf[s.UserID] = u
		}
	}
	protect = make(map[model.PID]bool)
	for u := range users {
		items, err := l.lib.Playback().Queue(ctx, u)
		if err != nil && waxerr.CodeOf(err) != waxerr.CodeNotFound {
			return nil, false, nil, fmt.Errorf("reading the queue of catalog user %s: %w", u, err)
		}
		for _, it := range items {
			protect[it.PID] = true
		}
	}
	length := make(map[model.PID]int64, len(downloaded))
	for _, ep := range downloaded {
		length[ep.PID] = ep.DurationMS
	}
	pids := make([]model.PID, 0, len(candidates)+len(holds))
	asked := make(map[model.PID]bool, len(candidates)+len(holds))
	for _, ep := range candidates {
		pids, asked[ep.PID] = append(pids, ep.PID), true
	}
	var held []wdb.FetchHold
	for _, h := range holds {
		ep := model.PID(h.EpisodePID)
		if catalogOf[h.UserID] == "" {
			stale = append(stale, h)
			continue
		}
		held = append(held, h)
		if !asked[ep] {
			pids, asked[ep] = append(pids, ep), true
		}
	}
	states, err := l.candidateStates(ctx, pids)
	if err != nil {
		return nil, false, nil, fmt.Errorf("reading the candidates' play states: %w", err)
	}
	for _, ep := range candidates {
		for i := range states[ep.PID] {
			st := &states[ep.PID][i]
			if st.Starred && users[st.UserPID] {
				protect[ep.PID] = true
			}
			if l.stateReadsInUse(st) {
				inUse = true
			}
		}
	}
	hearing := make(map[string]bool, len(listening))
	for _, s := range listening {
		hearing[s.UserID] = true
	}
	for _, h := range held {
		ep := model.PID(h.EpisodePID)
		if heardSince(userPlayState(states[ep], catalogOf[h.UserID]), h.HeldAtNS, length[ep]) {
			stale = append(stale, h)
			continue
		}
		if hearing[h.UserID] {
			protect[ep] = true
		}
	}
	return protect, inUse, stale, nil
}

// liveHolds reads the holds on a show's downloads and drops those on a
// file no longer on the server, answering the rest.
func (l *Library) liveHolds(ctx context.Context, showPID model.PID, downloaded []*model.Episode) ([]wdb.FetchHold, error) {
	holds, err := l.db.FetchHoldsByShow(ctx, string(showPID))
	if err != nil {
		return nil, fmt.Errorf("reading the show's download holds: %w", err)
	}
	onServer := make(map[model.PID]bool, len(downloaded))
	for _, ep := range downloaded {
		onServer[ep.PID] = true
	}
	var live, gone []wdb.FetchHold
	for _, h := range holds {
		if onServer[model.PID(h.EpisodePID)] {
			live = append(live, h)
		} else {
			gone = append(gone, h)
		}
	}
	if err := l.db.DropFetchHolds(ctx, gone); err != nil {
		l.log.Warn("dropping holds on files no longer here", "show", string(showPID), "err", err)
	}
	return live, nil
}

// heardSince reports whether a requester finished an episode after
// asking for it at heldAtNS: its played flags moved since, or its
// position reached the end since (hearing a played episode again marks
// nothing new).
func heardSince(st *model.PlayState, heldAtNS, durationMS int64) bool {
	if st == nil {
		return false
	}
	if (st.Played || st.Finished) && st.PlayedChangedAt > heldAtNS {
		return true
	}
	return durationMS > 0 && st.LastProgressAt > heldAtNS &&
		float64(st.PositionMS) >= spokenFinishedFraction*float64(durationMS)
}

// requeueHeldShow queues for retention the show of a download the account
// asked for, once its played state moves: finishing the episode is what
// lets the hold go.
func (l *Library) requeueHeldShow(ctx context.Context, userID string, episodePID model.PID) {
	show, err := l.db.FetchHoldShow(ctx, string(episodePID), userID)
	if errors.Is(err, wdb.ErrNotFound) {
		return
	}
	if err != nil {
		l.log.Warn("reading a download hold", "episode", string(episodePID), "err", err)
		return
	}
	if err := l.db.EnqueueRetention(ctx, show, time.Now().UnixNano()); err != nil {
		l.log.Warn("queuing retention", "show", show, "err", err)
	}
}

// candidateStates reads every user's play state of the given episodes in
// one read, through retentionStatesHook in a test.
func (l *Library) candidateStates(ctx context.Context, pids []model.PID) (map[model.PID][]model.PlayState, error) {
	if l.retentionStatesHook != nil {
		return l.retentionStatesHook(ctx, pids)
	}
	return l.lib.PlayStatesForItems(ctx, pids)
}

// stateReadsInUse reports whether one user's play state looks like
// live playback: a position that moved within the window (live clients
// checkpoint every few seconds), unfinished. Removing a file under an
// active listener kills their stream, so both the retention sweep and
// manual removal consult this. A negative window disables the guard.
//
// LastProgressAt as well as UpdatedAt: a remote session's ticks are
// buffered, never written, and reach a read only through it.
func (l *Library) stateReadsInUse(st *model.PlayState) bool {
	if st == nil || l.retentionInUseWindow <= 0 {
		return false
	}
	return max(st.UpdatedAt, st.LastProgressAt) > time.Now().Add(-l.retentionInUseWindow).UnixNano() &&
		st.PositionMS > 0 && !st.Finished
}

// podcastListeners keeps the subscriptions whose account can see the
// podcast library now, one account read for each. The rest are kept for
// the grant's return and do nothing meanwhile: no notice, no download by
// their policy, no say in retention.
//
// judged says every subscriber was judged. One whose account read failed
// with anything but not-found, or a granted one while the podcast library
// could not be read, is left out unjudged: skipping it costs a notice or
// a download, but the retention sweep must not count without it.
func (l *Library) podcastListeners(ctx context.Context, subs []wdb.Subscription) (listening []wdb.Subscription, judged bool) {
	listening, judged = make([]wdb.Subscription, 0, len(subs)), true
	for _, s := range subs {
		visible, seen := l.hearsPodcasts(ctx, s.UserID)
		if visible {
			listening = append(listening, s)
		}
		judged = judged && seen
	}
	return listening, judged
}

// hearsPodcasts is podcastListeners' verdict on one account: whether it
// can see the podcast library now, and whether that is a judgment.
func (l *Library) hearsPodcasts(ctx context.Context, userID string) (visible, judged bool) {
	uc, err := l.listenerAccount(ctx, userID)
	if err != nil {
		if KindOf(err) != KindNotFound {
			l.log.Warn("reading a subscriber's account", "user", userID, "err", err)
			return false, false
		}
		return false, true
	}
	return l.podcastsJudged(ctx, uc)
}

// showHeard reports whether the show is fetched for anyone: false only
// when every follower was judged unable to see the podcast library. A
// follower who could not be judged, or followers who could not be read,
// keep it fetched.
func (l *Library) showHeard(ctx context.Context, showPID model.PID) bool {
	subs, err := l.db.SubscribersByShow(ctx, string(showPID))
	if err != nil {
		l.log.Warn("listing subscribers", "show", string(showPID), "err", err)
		return true
	}
	listening, judged := l.podcastListeners(ctx, subs)
	return len(listening) > 0 || !judged
}

// listenerAccount reads a subscriber's account, through listenerReadHook
// in a test.
func (l *Library) listenerAccount(ctx context.Context, userID string) (*UserCtx, error) {
	if l.listenerReadHook != nil {
		return l.listenerReadHook(ctx, userID)
	}
	return l.userCtxByID(ctx, userID)
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

// userCatalogPID maps a WaxDeck user id to its catalog user.
func (l *Library) userCatalogPID(ctx context.Context, userID string) (model.PID, error) {
	u, err := l.db.UserByID(ctx, userID)
	if err != nil {
		return "", err
	}
	return model.PID(l.catalogPID(u)), nil
}

// setEpisodePinned re-upserts the episode with only the pinned flag
// changed. The upsert path preserves state and identity when every
// field round-trips, which feedEpisodeOf guarantees by copying them
// all.
func (l *Library) setEpisodePinned(ctx context.Context, showPID model.PID, ep *model.Episode, pinned bool) error {
	if l.pinHook != nil {
		return l.pinHook(ctx, showPID, ep, pinned)
	}
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
