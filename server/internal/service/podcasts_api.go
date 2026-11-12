package service

import (
	"context"
	"errors"
	"hash/fnv"
	"log/slog"
	"net/url"
	"sort"
	"strings"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/podcast"
	"github.com/colespringer/waxbin/query"
	"github.com/colespringer/waxbin/read"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// lockMembership serializes one account's changes to who follows which
// show, the state and the change log together, so neither a change nor
// its event can land inside another and the log keeps their order.
func (l *Podcasts) lockMembership(userID string) func() {
	h := fnv.New32a()
	_, _ = h.Write([]byte(userID))
	m := &l.membershipLocks[h.Sum32()%playedStripes]
	m.Lock()
	return m.Unlock
}

// testHookMembership, nil outside tests, runs where two requests for one
// account could otherwise interleave: inside a change of who follows a
// show, at the named steps a test can hold one at.
var testHookMembership func(step string)

// subChangeMeta annotates subscription changes made through the
// compatibility adapter so other gpodder clients can filter by device.
// known is a show the catalog already holds, attached without a fetch.
// park is a parked feed the add lands: every device still asking for it
// holds the show too, and the park goes, under the account lock. A retry's
// landing (parkOnly) holds it for those devices alone, and attaches
// nothing once none of them is left asking. failureLog is the level a
// feed-side failure is logged at: Info, the zero value, for the apps'
// subscribes, Debug for gpodder's, which a full list asks again on every
// sync and the inbox records.
type subChangeMeta struct {
	deviceID   string
	known      *model.Podcast
	park       string
	parkOnly   bool
	failureLog slog.Level
}

// ErrPodcastsOff is the cause of the refusal a server whose podcast
// directory is off answers every subscribe with.
var ErrPodcastsOff = errors.New("podcasts are turned off on this server")

// On reports whether this server keeps podcasts: false when its
// podcast directory is turned off, which refuses every subscribe.
func (l *Podcasts) On() bool { return l.podcastDir != "" }

// requirePodcastsOn refuses a subscribe for good on a server whose
// podcast directory is off: it keeps no podcasts, so it follows none and
// fetches no feed.
func (l *Podcasts) requirePodcastsOn() error {
	if l.podcastDir == "" {
		return &Error{Kind: KindFeature, Msg: ErrPodcastsOff.Error(), Err: ErrPodcastsOff}
	}
	return nil
}

// Subscribe subscribes the caller to a show, cataloging it globally on
// first subscription. Returns the subscription and whether it is new;
// re-subscribing updates only supplied credentials (the rotation path).
func (l *Podcasts) Subscribe(ctx context.Context, uc *UserCtx, req SubscribeRequest) (Subscription, bool, error) {
	return l.subscribe(ctx, uc, req, subChangeMeta{})
}

func (l *Podcasts) subscribe(ctx context.Context, uc *UserCtx, req SubscribeRequest, meta subChangeMeta) (Subscription, bool, error) {
	if err := requirePodcastManagement(uc); err != nil {
		return Subscription{}, false, err
	}
	if err := l.requirePodcastsOn(); err != nil {
		return Subscription{}, false, err
	}
	// Following a show is for hearing it, and the podcast library is what
	// an account is granted to hear podcasts by.
	if !l.Grants.podcastsVisible(ctx, uc) {
		return Subscription{}, false, &Error{Kind: KindForbidden,
			Msg: "this account cannot see the podcast library; an administrator can grant it"}
	}
	rawURL := strings.TrimSpace(req.URL)
	if rawURL == "" {
		return Subscription{}, false, errInvalid("url is required")
	}
	if u, err := url.Parse(rawURL); err != nil || (u.Scheme != "http" && u.Scheme != "https") {
		return Subscription{}, false, errInvalid("url must be http or https")
	}
	if !l.allowPrivateFeedHosts && refusedNAT64Host(rawURL) {
		return Subscription{}, false, blockedFeedAddress()
	}
	folder, err := subscriptionFolder(req.Folder)
	if err != nil {
		return Subscription{}, false, err
	}
	req.Folder = folder

	sourceType := model.SourceRSS
	switch strings.TrimSpace(req.SourceType) {
	case "", "rss":
	case "youtube":
		sourceType = model.SourceYouTube
	default:
		return Subscription{}, false, &Error{Kind: KindUnsupported,
			Msg: "unsupported source type " + req.SourceType}
	}

	if meta.known != nil {
		return l.attachSubscription(ctx, uc, meta.known, req, meta)
	}
	opts := podcast.AddOptions{User: req.Username, Pass: req.Password}
	pod, err := l.lib.Podcasts().AddSource(ctx, rawURL, sourceType, opts)
	if err != nil {
		out := l.classifyFeedErr(ctx, err)
		if reason := FeedFailureReason(out); reason != "" {
			l.logFeedFailureAt(meta.failureLog, "subscribing to a feed failed", rawURL, reason, err)
		}
		return Subscription{}, false, out
	}
	// The catalog has just taken this address up as the show's, so a
	// secret in it makes the show private before anything can refuse.
	if addressCarriesSecret(rawURL) {
		l.markShowPrivate(ctx, string(pod.PID))
	}
	return l.attachSubscription(ctx, uc, pod, req, meta)
}

// attachSubscription subscribes the caller to a cataloged show and
// records who holds it: meta's device, or the first-party apps.
func (l *Podcasts) attachSubscription(ctx context.Context, uc *UserCtx, pod *model.Podcast, req SubscribeRequest, meta subChangeMeta) (Subscription, bool, error) {
	if showWithheld(uc, pod) {
		return Subscription{}, false, &Error{Kind: KindForbidden,
			Msg: "this account cannot subscribe to explicit shows"}
	}
	show := string(pod.PID)
	// The account's own URL for the show, whatever the catalog took up.
	feedURL := strings.TrimSpace(req.URL)

	hasCreds := req.Username != "" || req.Password != ""
	if hasCreds {
		// AddSource applies credentials on create; re-adding an existing
		// show syncs but keeps old auth, so rotation writes explicitly.
		if err := l.lib.Podcasts().SetAuth(ctx, pod.PID, req.Username, req.Password); err != nil {
			return Subscription{}, false, classify(err)
		}
	}
	// An address that carries a credential is as much the show's secret
	// as a login; one no fetch put in the catalog is marked here.
	private := hasCreds || addressCarriesSecret(feedURL)
	if private {
		l.markShowPrivate(ctx, show)
	}

	now := time.Now().UnixNano()
	var created bool
	var row wdb.Subscription
	if err := func() error {
		defer l.lockMembership(uc.ID)()
		holders, err := l.landingHolders(ctx, uc.ID, show, meta)
		if err != nil {
			return err
		}
		if testHookMembership != nil {
			testHookMembership("landing")
		}
		// A URL no fetch proved is the holder's, and the account's only
		// when it had none.
		attach := l.db.AttachSubscription
		if meta.known != nil {
			attach = l.db.AttachKnownSubscription
		}
		for _, holder := range holders {
			made, err := attach(ctx, wdb.Subscription{
				UserID: uc.ID, ShowPID: show,
				Folder: strings.TrimSpace(req.Folder), Private: private,
				CreatedAtNS: now, UpdatedAtNS: now,
			}, holder, feedURL)
			if err != nil {
				return &Error{Kind: KindInternal, Err: err}
			}
			if made {
				created = true
				if private {
					l.markShowPrivate(ctx, show)
				}
				l.afterSubscriptionChange(ctx, uc, show, gpodderEventURL(pod, feedURL), "add", subChangeMeta{deviceID: holder})
			}
		}
		if meta.park != "" {
			if err := l.db.DeleteGpodderPending(ctx, uc.ID, meta.park); err != nil {
				return &Error{Kind: KindInternal, Err: err}
			}
		}
		if testHookMembership != nil {
			testHookMembership("attach")
		}
		// Read before the lock goes: an unsubscribe right after cannot
		// turn a subscribe that landed into a failure.
		if row, err = l.db.SubscriptionFor(ctx, uc.ID, show); err != nil {
			return &Error{Kind: KindInternal, Err: err}
		}
		return nil
	}(); err != nil {
		return Subscription{}, false, err
	}
	out, err := l.subscriptionRow(ctx, uc, pod, row)
	if err != nil {
		return Subscription{}, false, err
	}
	return out, created, nil
}

// Unsubscribe removes the caller's subscription; the show and its
// episodes stay. With removeDownloads, and only when the caller was
// the last subscriber, the show's downloaded audio is unfetched: the
// bytes are reclaimed, the episodes stay listed and re-fetchable, and
// playback state is untouched. While other subscribers remain their
// retention owns the files and the flag is ignored. Unsubscribing from
// an unfollowed show is a no-op.
func (l *Podcasts) Unsubscribe(ctx context.Context, uc *UserCtx, apiShowPID string, removeDownloads bool) error {
	if err := requirePodcastManagement(uc); err != nil {
		return err
	}
	if !l.Grants.podcastsVisible(ctx, uc) {
		return errNotFound("no show with pid " + apiShowPID)
	}
	return l.unsubscribe(ctx, uc, apiShowPID, removeDownloads, subChangeMeta{})
}

func (l *Podcasts) unsubscribe(ctx context.Context, uc *UserCtx, apiShowPID string, removeDownloads bool, meta subChangeMeta) error {
	pod, err := l.getShow(ctx, apiShowPID)
	if err != nil {
		return err
	}
	// An unsubscribe is the whole account's: every device's hold goes too,
	// and every device's parked ask for the show, which a retry would land
	// again.
	var existed bool
	if err := func() error {
		defer l.lockMembership(uc.ID)()
		var err error
		var feedURL string
		if existed, feedURL, err = l.db.RemoveSubscription(ctx, uc.ID, string(pod.PID)); err != nil {
			return &Error{Kind: KindInternal, Err: err}
		}
		if testHookMembership != nil {
			testHookMembership("removed")
		}
		// Committed: the parks and the change log follow whether or not
		// the request is still there, or a client gone at the wrong
		// moment leaves the account's other devices never told.
		ctx := context.WithoutCancel(ctx)
		if err := l.dropShowParks(ctx, uc.ID, pod, feedURL); err != nil {
			return err
		}
		if testHookMembership != nil {
			testHookMembership("unsubscribe")
		}
		if existed {
			l.afterSubscriptionChange(ctx, uc, string(pod.PID), gpodderEventURL(pod, feedURL), "remove", meta)
		}
		return nil
	}(); err != nil {
		return err
	}
	if !existed {
		return nil
	}
	if removeDownloads {
		remaining, err := l.db.SubscribersByShow(ctx, string(pod.PID))
		if err != nil {
			l.log.Warn("checking remaining subscribers", "show", apiShowPID, "err", err)
			return nil
		}
		if len(remaining) == 0 {
			l.removeShowDownloads(ctx, pod.PID)
		}
	}
	return nil
}

// removeShowDownloads reclaims the bytes of every downloaded episode of
// a show nobody subscribes to anymore, through the podcast facade's own
// Unfetch: the file goes, the episode row and every user's play state
// stay, and the episode is re-fetchable. Files that read as actively
// played are skipped (a non-subscriber can still be listening), as are
// files whose lease stays contended past a short retry. Nothing sweeps
// those up later - sweepShowRetention returns early once a show has no
// subscribers - so a skipped file lingers until someone unfetches it
// explicitly, the same accepted posture as the in-use skip.
func (l *Podcasts) removeShowDownloads(ctx context.Context, showPID model.PID) {
	eps, err := l.lib.Podcasts().Episodes(ctx, showPID, 0)
	if err != nil {
		l.log.Warn("listing episodes for cleanup", "show", string(showPID), "err", err)
		return
	}
	var remove []model.PID
	skipped := 0
	var downloaded []model.PID
	for _, ep := range eps {
		// A queued fetch would re-land its file after this cleanup, so
		// cancel it whether or not the episode has a file yet.
		if err := l.db.CompleteFetch(ctx, string(ep.PID)); err != nil {
			l.log.Warn("canceling queued fetch", "episode", string(ep.PID), "err", err)
		}
		if ep.Downloaded {
			downloaded = append(downloaded, ep.PID)
		}
	}
	if len(downloaded) == 0 {
		return
	}
	// One batch read of every user's state across the downloaded episodes,
	// instead of a Playback().State call per (episode, user) pair.
	states, err := l.lib.PlayStatesForItems(ctx, downloaded)
	if err != nil {
		l.log.Warn("reading playback state for cleanup", "show", string(showPID), "err", err)
		return
	}
	for _, ep := range downloaded {
		inUse := false
		for i := range states[ep] {
			if l.stateReadsInUse(&states[ep][i]) {
				inUse = true
				break
			}
		}
		if inUse {
			skipped++
			continue
		}
		remove = append(remove, ep)
	}
	if skipped > 0 {
		l.log.Info("cleanup skipped in-use episodes", "show", string(showPID), "skipped", skipped)
	}
	if len(remove) == 0 {
		return
	}
	if err := l.checkPodcastWritable(ctx); err != nil {
		l.log.Info("cleanup keeps the downloads while the server is read-only", "show", string(showPID))
		return
	}
	// The unsubscribe already committed and this runs inside its request,
	// so a client disconnect must not strand a half-done cleanup - hence
	// WithoutCancel. It stays synchronous because it stays bounded:
	// contended episodes are collected and swept again rather than slept
	// on one at a time, so the whole cleanup waits out the lease at most
	// unfetchRetries-1 times regardless of how many episodes a show
	// holds. The holders are brief - another unfetch, a retention apply,
	// a download's commit tail - so a settle between sweeps rides out
	// the overlap; whatever still conflicts after the last sweep is
	// logged and left fetched.
	cleanupCtx := context.WithoutCancel(ctx)
	var reclaimed int64
	unfetched := 0
	remaining := remove
	for sweep := 0; sweep < unfetchRetries && len(remaining) > 0; sweep++ {
		if sweep > 0 {
			time.Sleep(unfetchRetryDelay)
		}
		var contended []model.PID
		for _, ep := range remaining {
			res, err := l.lib.Podcasts().Unfetch(cleanupCtx, ep)
			if err != nil {
				if KindOf(err) == KindConflict {
					contended = append(contended, ep)
					continue
				}
				l.log.Warn("unfetching episode for cleanup",
					"show", string(showPID), "episode", string(ep), "err", err)
				continue
			}
			if res != nil && res.Unfetched {
				unfetched++
				reclaimed += res.ReclaimedBytes
			}
		}
		remaining = contended
	}
	if len(remaining) > 0 {
		l.log.Warn("cleanup left contended episodes fetched",
			"show", string(showPID), "episodes", len(remaining))
	}
	if unfetched > 0 {
		l.log.Info("unsubscribe reclaimed downloads", "show", string(showPID),
			"episodes", unfetched, "reclaimedBytes", reclaimed)
	}
}

// unfetchRetries sweeps and unfetchRetryDelay between them bound
// removeShowDownloads' wait on a contended podcast filesystem lease.
const (
	unfetchRetries    = 3
	unfetchRetryDelay = 250 * time.Millisecond
)

// afterSubscriptionChange fans out everything a subscription change
// implies: the user's own sync event, the gpodder change log, a
// retention re-evaluation (the union may have shifted), and the
// caller's catalog cursors retired. The cursor bump matters because
// subscriptions scope which episodes and shows the caller's catalog
// view contains: a mirror synced under the old membership holds rows
// (or lacks rows) the new membership disagrees on, and episode change
// seqs predate a fresh subscribe, so only a clean re-mirror converges.
// feedURL is the account's URL for the show the change log records it
// under, empty for a show gpodder clients do not sync. Never fails the
// mutation, and runs whether or not the request that made it is still
// there: the change has committed, and a retry finds it done and files
// nothing.
func (l *Podcasts) afterSubscriptionChange(ctx context.Context, uc *UserCtx, showPID, feedURL, action string, meta subChangeMeta) {
	ctx = context.WithoutCancel(ctx)
	l.emitUserEvent(ctx, uc.ID, eventSubscription, showPID)
	l.Grants.bumpGrantEpoch(ctx, uc.ID)
	// A show followed a moment ago has to be reachable by its first
	// podping, not by the index's next scheduled rebuild.
	l.InvalidatePodpingFeeds()
	if feedURL != "" {
		if err := l.db.AppendGpodderSubEvent(ctx, wdb.GpodderSubEvent{
			UserID: uc.ID, ShowPID: showPID, FeedURL: feedURL, Action: action,
			DeviceID: meta.deviceID, TsSec: time.Now().Unix(),
		}, gpodderRemovalsPerUser); err != nil {
			l.log.Warn("appending gpodder sub event", "err", err)
		}
	}
	if err := l.db.EnqueueRetention(ctx, showPID, time.Now().UnixNano()); err != nil {
		l.log.Warn("queuing retention", "show", showPID, "err", err)
	}
}

// Subscriptions lists the caller's subscriptions, ordered by show
// title then pid, keyset-paged. The load, sort, and slice happen in
// memory deliberately: display order is the show title, which lives in
// the catalog database, and cross-database ordering cannot move into
// SQL without denormalizing titles into waxdeck.db (the two databases
// are never joined by design). One user's subscription count is
// bounded at a few hundred rows of point lookups.
// [withCounts] asks for the unplayed backlog on each row, which costs
// three catalog queries per subscription. The surfaces that draw a tile
// want it; the Subsonic
// adapter, which pages every subscription and then lists their episodes
// anyway, does not, and asking for it there would double the work for a
// number nothing in that protocol carries.
func (l *Podcasts) Subscriptions(ctx context.Context, uc *UserCtx, cursor string, limit int, withCounts bool) ([]Subscription, string, error) {
	// An account that cannot see the podcast library follows nothing it
	// can see; its rows stay for the day it can again.
	if !l.Grants.podcastsVisible(ctx, uc) {
		return []Subscription{}, "", nil
	}
	rows, err := l.db.SubscriptionsByUser(ctx, uc.ID)
	if err != nil {
		return nil, "", &Error{Kind: KindInternal, Err: err}
	}
	subs := make([]Subscription, 0, len(rows))
	shows := make(map[string]*model.Podcast, len(rows))
	for _, row := range rows {
		pod, err := l.lib.Podcasts().Get(ctx, model.PID(row.ShowPID))
		if err != nil {
			// A show removed out from under a subscription row is a
			// dangling reference; tolerate and skip.
			continue
		}
		s, err := l.subscriptionRow(ctx, uc, pod, row)
		if err != nil {
			return nil, "", err
		}
		shows[s.Show.PID] = pod
		subs = append(subs, s)
	}
	sort.Slice(subs, func(i, j int) bool {
		if subs[i].Show.Title != subs[j].Show.Title {
			return subs[i].Show.Title < subs[j].Show.Title
		}
		return subs[i].Show.PID < subs[j].Show.PID
	})

	start := 0
	if cursor != "" {
		title, pid, ok := decodeTitleCursor(cursor)
		if !ok {
			return nil, "", errInvalid("malformed cursor")
		}
		start = sort.Search(len(subs), func(i int) bool {
			if subs[i].Show.Title != title {
				return subs[i].Show.Title > title
			}
			return subs[i].Show.PID > pid
		})
	}
	end := min(start+limit, len(subs))
	page := subs[start:end]
	// After the slice, never before it: the counts are per show, and
	// doing them for every subscription to answer a page of twenty would
	// be paying for the whole list on every page of it.
	if withCounts {
		for i := range page {
			if err := l.countShow(ctx, uc, shows[page[i].Show.PID], &page[i]); err != nil {
				return nil, "", err
			}
		}
	}
	next := ""
	if end < len(subs) && len(page) > 0 {
		last := page[len(page)-1]
		next = encodeTitleCursor(last.Show.Title, last.Show.PID)
	}
	return page, next, nil
}

// countShow fills the three numbers a subscription tile draws, all
// three from the caller's own view of the show.
func (l *Podcasts) countShow(
	ctx context.Context,
	uc *UserCtx,
	pod *model.Podcast,
	sub *Subscription,
) error {
	if pod == nil {
		return nil
	}
	// A total, not a per-user number: the query references no per-user
	// field. The pid is passed anyway because an empty one is not "no
	// user" in WaxBin, it resolves to the default user, and a query that
	// grows a per-user field later would silently read the wrong one.
	total, err := l.lib.Count(ctx, showEpisodeQueryFor(uc, pod).Build(), model.PID(uc.CatalogPID))
	if err != nil {
		return classify(err)
	}
	// Unplayed means never started, not "not finished": an episode
	// somebody is five minutes into is in progress, and a backlog badge
	// that keeps counting it is telling a listener to do what they are
	// already doing. The episode-row dot has always drawn it this way, so
	// this is the surfaces agreeing rather than a new definition.
	unplayed, err := l.lib.Count(ctx,
		showEpisodeQueryFor(uc, pod).
			Where("played", query.OpIs, 0).
			Where("position_ms", query.OpIs, 0).Build(),
		model.PID(uc.CatalogPID))
	if err != nil {
		return classify(err)
	}
	sub.Show.EpisodeCount = total
	sub.UnplayedCount = &unplayed

	newest, err := l.newestVisibleEpisodeNS(ctx, uc, pod)
	if err != nil {
		return err
	}
	sub.Show.LastPublishedNS = newest
	return nil
}

// showEpisodeQuery is the item-query form of "this show's episodes".
// `kind is episode` is redundant beside podcast_pid but states intent.
// The counts are honest because an items query counts an episode nobody
// has fetched: the file join is a LEFT JOIN with no state filter, and
// visibleItems drops only archived episodes, keeping remote ones.
func showEpisodeQuery(pod *model.Podcast) *query.Builder {
	return visibleItems().
		Where("kind", query.OpIs, string(model.KindEpisode)).
		Where("podcast_pid", query.OpIs, string(pod.PID))
}

// showEpisodeQueryFor narrows showEpisodeQuery to what one caller may
// see. Both advisory flags, matching allowedByContent and
// DetailFor's 404: a feed can mark itself explicit at the channel
// level and leave every episode unmarked, so a restricted subscriber to
// an explicit show sees nothing of it rather than its unmarked episodes.
func showEpisodeQueryFor(uc *UserCtx, pod *model.Podcast) *query.Builder {
	q := showEpisodeQuery(pod)
	if !uc.Explicit {
		q = q.Where("explicit", query.OpIs, 0).
			Where("podcast_explicit", query.OpIs, 0)
	}
	return q
}

// newestVisibleEpisodeNS is the publication time of the newest episode
// of one show the caller may see, or zero when there is none.
//
// The list excludes undated episodes, which is the answer we want: an
// undated episode never won a max over publication times either.
func (l *Podcasts) newestVisibleEpisodeNS(ctx context.Context, uc *UserCtx, pod *model.Podcast) (int64, error) {
	page, err := l.lib.Browse(ctx, read.ListRecentEpisodes, read.BrowseOptions{
		UserPID: model.PID(uc.CatalogPID),
		Limit:   1,
		Query:   showEpisodeQueryFor(uc, pod).Build(),
	})
	if err != nil {
		return 0, classify(err)
	}
	if page == nil || len(page.Items) == 0 {
		return 0, nil
	}
	return page.Items[0].PubDateNS, nil
}

// DetailFor returns any cataloged show with the caller's
// subscription state.
func (l *Podcasts) DetailFor(ctx context.Context, uc *UserCtx, apiShowPID string) (PodcastDetail, error) {
	pod, err := l.getShow(ctx, apiShowPID)
	if err != nil {
		return PodcastDetail{}, err
	}
	if !l.Grants.podcastsVisible(ctx, uc) {
		return PodcastDetail{}, errNotFound("no show with pid " + apiShowPID)
	}
	if showWithheld(uc, pod) {
		return PodcastDetail{}, errNotFound("no show with pid " + apiShowPID)
	}
	var out PodcastDetail
	row, err := l.db.SubscriptionFor(ctx, uc.ID, string(pod.PID))
	if err == nil {
		out.Subscribed = true
		st := settingsDTO(row)
		out.Settings = &st
	} else if !errors.Is(err, wdb.ErrNotFound) {
		return PodcastDetail{}, &Error{Kind: KindInternal, Err: err}
	}
	if out.Show, err = l.showDTO(ctx, uc, pod, true, row.FeedURL); err != nil {
		return PodcastDetail{}, err
	}
	return out, nil
}

// PutSubscriptionSettings fully replaces the caller's settings for one
// subscription.
func (l *Podcasts) PutSubscriptionSettings(ctx context.Context, uc *UserCtx, apiShowPID string, s SubscriptionSettings) (Subscription, error) {
	pod, err := l.getShow(ctx, apiShowPID)
	if err != nil {
		return Subscription{}, err
	}
	if !l.Grants.podcastsVisible(ctx, uc) {
		return Subscription{}, errNotFound("no show with pid " + apiShowPID)
	}
	show := string(pod.PID)
	// Under the account's lock, so an unsubscribe cannot land between the
	// read and the write; and the write only updates, so a show the account
	// does not follow stays unfollowed whatever the order.
	var row wdb.Subscription
	if err := func() error {
		defer l.lockMembership(uc.ID)()
		if _, err := l.db.SubscriptionFor(ctx, uc.ID, show); errors.Is(err, wdb.ErrNotFound) {
			return errNotFound("not subscribed to " + apiShowPID)
		} else if err != nil {
			return &Error{Kind: KindInternal, Err: err}
		}
		if testHookMembership != nil {
			testHookMembership("settings")
		}
		if s.Speed != nil && (*s.Speed < 0.5 || *s.Speed > 3.5) {
			return errInvalid("speed must be between 0.5 and 3.5")
		}
		if s.RetentionKeep != nil && *s.RetentionKeep < 0 {
			return errInvalid("retentionKeep must not be negative")
		}
		folder, err := subscriptionFolder(s.Folder)
		if err != nil {
			return err
		}
		found, err := l.db.UpdateSubscriptionSettings(ctx, wdb.Subscription{
			UserID: uc.ID, ShowPID: show,
			Folder:        folder,
			Private:       s.Private,
			RetentionKeep: s.RetentionKeep,
			AutoDownload:  s.AutoDownload,
			Speed:         s.Speed,
			TrimSilence:   s.TrimSilence,
			VoiceBoost:    s.VoiceBoost,
			SkipIntroSec:  s.SkipIntroSec,
			SkipOutroSec:  s.SkipOutroSec,
			AutoDLInclude: normalizeTerms(s.AutoDLFilter.Include),
			AutoDLExclude: normalizeTerms(s.AutoDLFilter.Exclude),
			UpdatedAtNS:   time.Now().UnixNano(),
		})
		if err != nil {
			return &Error{Kind: KindInternal, Err: err}
		}
		if !found {
			return errNotFound("not subscribed to " + apiShowPID)
		}
		if row, err = l.db.SubscriptionFor(ctx, uc.ID, show); err != nil {
			return &Error{Kind: KindInternal, Err: err}
		}
		return nil
	}(); err != nil {
		return Subscription{}, err
	}
	if s.Private {
		// Privacy is sticky at the show level; setting the flag false
		// never clears it (the URL may already have leaked less).
		l.markShowPrivate(ctx, show)
	}
	l.emitUserEvent(ctx, uc.ID, eventSubscription, show)
	if err := l.db.EnqueueRetention(ctx, show, time.Now().UnixNano()); err != nil {
		l.log.Warn("queuing retention", "show", show, "err", err)
	}
	return l.subscriptionRow(ctx, uc, pod, row)
}

// Episodes lists one show's episodes newest first, keyset-paged on
// (publishedAt, pid). Publication falls back to first-seen time so the
// order is total.
func (l *Podcasts) Episodes(ctx context.Context, uc *UserCtx, apiShowPID, cursor string, limit int) ([]EpisodeSummary, string, error) {
	pod, err := l.getShow(ctx, apiShowPID)
	if err != nil {
		return nil, "", err
	}
	if !l.Grants.podcastsVisible(ctx, uc) {
		return nil, "", errNotFound("no show with pid " + apiShowPID)
	}
	if showWithheld(uc, pod) {
		return nil, "", errNotFound("no show with pid " + apiShowPID)
	}
	eps, err := l.lib.Podcasts().Episodes(ctx, pod.PID, 0)
	if err != nil {
		return nil, "", classify(err)
	}
	kept := make([]*model.Episode, 0, len(eps))
	for _, ep := range eps {
		if ep.Explicit && !uc.Explicit {
			continue
		}
		kept = append(kept, ep)
	}
	// Ordered and cut before a row is built: a row costs reads beyond the
	// catalog's episode, and only the page's rows go back.
	sort.Slice(kept, func(i, j int) bool {
		if pi, pj := episodePublishedNS(kept[i]), episodePublishedNS(kept[j]); pi != pj {
			return pi > pj
		}
		return kept[i].PID > kept[j].PID
	})

	start := 0
	if cursor != "" {
		pubNS, pid, ok := decodePubCursor(cursor)
		if !ok {
			return nil, "", errInvalid("malformed cursor")
		}
		start = sort.Search(len(kept), func(i int) bool {
			if pub := episodePublishedNS(kept[i]); pub != pubNS {
				return pub < pubNS
			}
			return apiPID(PrefixEpisode, kept[i].PID) < pid
		})
	}
	end := min(start+limit, len(kept))
	facts := l.readEpisodeFacts(ctx, kept[start:end], nil)
	page := make([]EpisodeSummary, 0, end-start)
	for _, ep := range kept[start:end] {
		page = append(page, l.episodeSummary(ctx, ep, facts))
	}
	next := ""
	if end < len(kept) && len(page) > 0 {
		last := page[len(page)-1]
		next = encodePubCursor(last.PublishedNS, last.PID)
	}
	return page, next, nil
}

// EpisodeDetailFor returns one episode with sanitized show notes and
// chapters.
func (l *Podcasts) EpisodeDetailFor(ctx context.Context, uc *UserCtx, apiEpisodePID string) (EpisodeDetail, error) {
	det, err := l.getEpisode(ctx, apiEpisodePID)
	if err != nil {
		return EpisodeDetail{}, err
	}
	if !l.Grants.podcastsVisible(ctx, uc) {
		return EpisodeDetail{}, errNotFound("no episode with pid " + apiEpisodePID)
	}
	// The show's flag as well as the episode's: reaching an episode by
	// its own pid is the one path that does not pass its show, so this
	// is where the two would otherwise disagree.
	if !l.Grants.episodeAllowed(ctx, uc, det.Episode) {
		return EpisodeDetail{}, errNotFound("no episode with pid " + apiEpisodePID)
	}
	out := EpisodeDetail{
		EpisodeSummary:  l.episodeSummary(ctx, det.Episode, l.readEpisodeFacts(ctx, []*model.Episode{det.Episode}, nil)),
		DescriptionHTML: sanitizeShowNotes(det.Episode.Description),
		Link:            det.Episode.Link,
		Persons:         feedPersonsDTO(det.Persons),
		Soundbites:      soundbitesDTO(det.Soundbites),
	}
	for i, ch := range det.Chapters {
		out.Chapters = append(out.Chapters, ChapterMark{
			Index: i, Title: ch.Title, StartMS: ch.StartMS, EndMS: ch.EndMS,
		})
	}
	// The catalog stores an episode's chapters when it downloads it, so
	// one that is only streamed has them from the feed's document instead.
	if len(out.Chapters) == 0 {
		out.Chapters = l.fetchedChapters(ctx, uc.ID, det.Episode)
	}
	return out, nil
}

// EpisodeSummaryFor answers one episode as its listing row, and whether its
// show declares itself explicit, under the checks EpisodeDetailFor makes and
// without the display extras that read costs (show notes, chapters, which
// can mean a fetch from the feed's host).
func (l *Podcasts) EpisodeSummaryFor(ctx context.Context, uc *UserCtx, apiEpisodePID string) (EpisodeSummary, bool, error) {
	det, err := l.getEpisode(ctx, apiEpisodePID)
	if err != nil {
		return EpisodeSummary{}, false, err
	}
	if !l.Grants.podcastsVisible(ctx, uc) {
		return EpisodeSummary{}, false, errNotFound("no episode with pid " + apiEpisodePID)
	}
	ep := det.Episode
	if !l.Grants.episodeAllowed(ctx, uc, ep) {
		return EpisodeSummary{}, false, errNotFound("no episode with pid " + apiEpisodePID)
	}
	// The show's own advisory, for a caller the rule above let through
	// without reading it; a show that cannot be read says nothing here, as
	// it says nothing on the detail read.
	showExplicit := false
	if pod, err := l.readShow(ctx, ep.PodcastPID); err == nil {
		showExplicit = pod.Explicit
	}
	return l.episodeSummary(ctx, ep, l.readEpisodeFacts(ctx, []*model.Episode{ep}, nil)), showExplicit, nil
}

// feedPersonsDTO maps facade person credits onto the service DTO, dropping
// to nil for an empty slice so the surface omits the field.
func feedPersonsDTO(in []model.FeedPerson) []FeedPerson {
	if len(in) == 0 {
		return nil
	}
	out := make([]FeedPerson, 0, len(in))
	for _, p := range in {
		out = append(out, FeedPerson{Name: p.Name, Role: p.Role, Group: p.Group, Img: p.Img, Href: p.Href})
	}
	return out
}

// soundbitesDTO maps facade soundbites onto the service DTO.
func soundbitesDTO(in []model.FeedSoundbite) []Soundbite {
	if len(in) == 0 {
		return nil
	}
	out := make([]Soundbite, 0, len(in))
	for _, s := range in {
		out = append(out, Soundbite{StartMS: s.StartMS, DurationMS: s.DurationMS, Title: s.Title})
	}
	return out
}

// RefreshPodcast syncs one show's feed now (subscribers only) and
// reports new episodes. Refreshes within a minute of the last sync
// answer from it.
func (l *Podcasts) RefreshPodcast(ctx context.Context, uc *UserCtx, apiShowPID string) (int, error) {
	if err := requirePodcastManagement(uc); err != nil {
		return 0, err
	}
	pod, err := l.getShow(ctx, apiShowPID)
	if err != nil {
		return 0, err
	}
	if !l.Grants.podcastsVisible(ctx, uc) {
		return 0, errNotFound("no show with pid " + apiShowPID)
	}
	if _, err := l.db.SubscriptionFor(ctx, uc.ID, string(pod.PID)); err != nil {
		if errors.Is(err, wdb.ErrNotFound) {
			return 0, &Error{Kind: KindForbidden, Msg: "refresh is for subscribers of the show"}
		}
		return 0, &Error{Kind: KindInternal, Err: err}
	}
	st, err := l.db.FeedStateFor(ctx, string(pod.PID))
	if err != nil {
		return 0, &Error{Kind: KindInternal, Err: err}
	}
	if time.Since(time.Unix(0, st.LastSyncedNS)) < time.Minute {
		return 0, nil
	}
	return l.syncShow(ctx, pod.PID, syncOwn)
}

// checkPodcastWritable refuses writing into the podcast download tree
// while the server is read-only; the catalog never flags that library.
func (l *Podcasts) checkPodcastWritable(ctx context.Context) error {
	return l.Settings.CheckWritable(ctx, "")
}

// QueueEpisodeFetch queues a server-side enclosure download. The
// caller must be subscribed to the show; an episode already here is
// fetched no further, only held for the caller as a landing holds it.
func (l *Podcasts) QueueEpisodeFetch(ctx context.Context, uc *UserCtx, apiEpisodePID string) error {
	if err := requirePodcastManagement(uc); err != nil {
		return err
	}
	if err := l.checkPodcastWritable(ctx); err != nil {
		return err
	}
	det, err := l.getEpisode(ctx, apiEpisodePID)
	if err != nil {
		return err
	}
	if !l.Grants.podcastsVisible(ctx, uc) {
		return errNotFound("no episode with pid " + apiEpisodePID)
	}
	ep := det.Episode
	if _, err := l.db.SubscriptionFor(ctx, uc.ID, string(ep.PodcastPID)); err != nil {
		if errors.Is(err, wdb.ErrNotFound) {
			return &Error{Kind: KindForbidden, Msg: "fetching needs a subscription to the show"}
		}
		return &Error{Kind: KindInternal, Err: err}
	}
	if ep.Downloaded {
		if err := l.db.HoldFetch(ctx, string(ep.PodcastPID), string(ep.PID), uc.ID, time.Now().UnixNano()); err != nil {
			return &Error{Kind: KindInternal, Err: err}
		}
		return nil
	}
	if l.playlistEnclosure(ctx, ep) {
		return errNotFound("episode " + apiEpisodePID + " names a playlist, not audio; there is nothing to fetch")
	}
	if l.podcastDir == "" {
		// Never queue into a void: without a download directory no
		// worker runs and a queued row would read as pending forever.
		return &Error{Kind: KindUnsupported,
			Msg: "episode downloads are disabled on this server (no podcast directory configured)"}
	}
	if err := l.db.EnqueueFetch(ctx, string(ep.PID), uc.ID, time.Now().UnixNano(), fetchMaxAttempts); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	return nil
}

// RemoveEpisodeDownload is the fetch's inverse: the episode's audio is
// deleted and the episode returns to remote, keeping the subscription,
// the episode row, and every subscriber's play state, so it streams by
// enclosure passthrough and is fetchable again. Subscribers only, like
// the fetch; an episode that reads as actively played refuses with
// conflict rather than killing the listener's stream.
//
// It used to trash the item instead, and that archived it - every delete
// mode archives an item on losing its last file - so `countShow`, which
// counts through visibleItems(), stopped seeing an episode that
// `Episodes` still listed, and a three-episode feed read "2 unplayed" on
// the hub beside three unplayed episodes on the show. Shared, too: one
// catalog row, so one subscriber's unfetch moved everybody's count.
// The listing was the surface that was right, which is why the fix is
// the podcast facade's own Unfetch rather than a filter on the listing.
func (l *Podcasts) RemoveEpisodeDownload(ctx context.Context, uc *UserCtx, apiEpisodePID string) error {
	if err := requirePodcastManagement(uc); err != nil {
		return err
	}
	det, err := l.getEpisode(ctx, apiEpisodePID)
	if err != nil {
		return err
	}
	if !l.Grants.podcastsVisible(ctx, uc) {
		return errNotFound("no episode with pid " + apiEpisodePID)
	}
	ep := det.Episode
	if _, err := l.db.SubscriptionFor(ctx, uc.ID, string(ep.PodcastPID)); err != nil {
		if errors.Is(err, wdb.ErrNotFound) {
			return &Error{Kind: KindForbidden, Msg: "removing a download needs a subscription to the show"}
		}
		return &Error{Kind: KindInternal, Err: err}
	}

	// Removing also cancels a queued fetch, so remove-after-queue never
	// races the worker into re-landing the file moments later.
	if err := l.db.CompleteFetch(ctx, string(ep.PID)); err != nil {
		l.log.Warn("canceling queued fetch", "episode", apiEpisodePID, "err", err)
	}
	if !ep.Downloaded {
		return nil
	}

	// One batch read of every user's state for this episode, instead of a
	// Playback().State call per subscriber. The file is shared, so it must
	// be idle for anyone playing it, not only current subscribers, before
	// it is removed.
	states, err := l.lib.PlayStatesForItems(ctx, []model.PID{ep.PID})
	if err != nil {
		return classify(err)
	}
	for i := range states[ep.PID] {
		if l.stateReadsInUse(&states[ep.PID][i]) {
			return &Error{Kind: KindConflict,
				Msg: "someone is listening to this episode right now; try again when playback stops"}
		}
	}

	if err := l.checkPodcastWritable(ctx); err != nil {
		return err
	}
	// classifyMutation: Unfetch holds the podcast filesystem lease for its
	// whole body, so a concurrent retention pass or unsubscribe answers a
	// conflict that clears on its own. The in-use refusal above is the
	// other kind - the caller has to stop playing - and stays a conflict.
	res, err := l.lib.Podcasts().Unfetch(ctx, ep.PID)
	if err != nil {
		return classifyMutation(err)
	}
	if res != nil && res.Unfetched {
		l.log.Info("unfetched episode",
			"episode", apiEpisodePID, "reclaimedBytes", res.ReclaimedBytes)
	}
	return nil
}
