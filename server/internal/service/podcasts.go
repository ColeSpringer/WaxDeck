package service

import (
	"context"
	"errors"
	"fmt"
	"net/url"
	"sort"
	"strings"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/podcast"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// PodcastShow is the API-facing show summary. DescriptionHTML is
// sanitized here, never in handlers, so every surface that renders a
// show goes through the same allowlist.
type PodcastShow struct {
	PID             string
	Title           string
	Author          string
	DescriptionHTML string
	// FeedURL is empty for private shows; the emptiness is the privacy
	// rule, not missing data.
	FeedURL         string
	Link            string
	SourceType      string
	EpisodeCount    int
	LastPublishedNS int64
	RefreshDisabled bool
}

// SubscriptionSettings is one user's per-subscription settings; nil
// pointers mean the server default.
type SubscriptionSettings struct {
	RetentionKeep *int64
	AutoDownload  bool
	Folder        string
	Private       bool
	Speed         *float64
	TrimSilence   *bool
	VoiceBoost    *bool
	SkipIntroSec  *int64
	SkipOutroSec  *int64
}

// Subscription is one user's subscription with its show.
type Subscription struct {
	Show           PodcastShow
	Settings       SubscriptionSettings
	SubscribedAtNS int64
}

// PodcastDetail is a show plus the caller's subscription state.
type PodcastDetail struct {
	Show       PodcastShow
	Subscribed bool
	Settings   *SubscriptionSettings
}

// SubscribeRequest is a subscription request.
type SubscribeRequest struct {
	URL        string
	SourceType string
	Username   string
	Password   string
	Folder     string
}

// EpisodeSummary is the episode list row: the generic item summary
// plus the episode dimension.
type EpisodeSummary struct {
	ItemSummary
	ShowPID     string
	Season      int
	EpisodeNo   int
	EpisodeType string
	PublishedNS int64
	Downloaded  bool
	FetchState  string
	FetchError  string
	Explicit    bool
	HasTx       bool
}

// EpisodeDetail is the full episode view.
type EpisodeDetail struct {
	EpisodeSummary
	DescriptionHTML string
	Link            string
	Chapters        []ChapterMark
}

// ChapterMark is one chapter on an item's timeline. EndMS zero means
// open-ended.
type ChapterMark struct {
	Index   int
	Title   string
	StartMS int64
	EndMS   int64
}

// OpmlImportEntry is one feed's import outcome.
type OpmlImportEntry struct {
	FeedURL string
	Title   string
	PID     string
	Err     string
}

// subChangeMeta annotates subscription changes made through the
// compatibility adapter so other gpodder clients can filter by device.
type subChangeMeta struct {
	deviceID string
}

// Subscribe subscribes the caller to a show, cataloging it globally on
// first subscription. Returns the subscription and whether it is new;
// re-subscribing updates only supplied credentials (the rotation path).
func (l *Library) Subscribe(ctx context.Context, uc *UserCtx, req SubscribeRequest) (Subscription, bool, error) {
	return l.subscribe(ctx, uc, req, subChangeMeta{})
}

func (l *Library) subscribe(ctx context.Context, uc *UserCtx, req SubscribeRequest, meta subChangeMeta) (Subscription, bool, error) {
	rawURL := strings.TrimSpace(req.URL)
	if rawURL == "" {
		return Subscription{}, false, errInvalid("url is required")
	}
	if u, err := url.Parse(rawURL); err != nil || (u.Scheme != "http" && u.Scheme != "https") {
		return Subscription{}, false, errInvalid("url must be http or https")
	}

	sourceType := model.SourceRSS
	switch strings.TrimSpace(req.SourceType) {
	case "", "rss":
	case "youtube":
		sourceType = model.SourceYouTube
	default:
		return Subscription{}, false, &Error{Kind: KindUnsupported,
			Msg: "unsupported source type " + req.SourceType}
	}

	opts := podcast.AddOptions{User: req.Username, Pass: req.Password}
	pod, err := l.lib.Podcasts().AddSource(ctx, rawURL, sourceType, opts)
	if err != nil {
		return Subscription{}, false, l.classifyFeedErr(ctx, err, rawURL, req.Password != "" || req.Username != "")
	}
	show := string(pod.PID)

	hasCreds := req.Username != "" || req.Password != ""
	if hasCreds {
		// AddSource applies credentials on create; re-adding an existing
		// show syncs but keeps old auth, so rotation writes explicitly.
		if err := l.lib.Podcasts().SetAuth(ctx, pod.PID, req.Username, req.Password); err != nil {
			return Subscription{}, false, classify(err)
		}
		l.markShowPrivate(ctx, show)
	}

	now := time.Now().UnixNano()
	_, err = l.db.SubscriptionFor(ctx, uc.ID, show)
	created := errors.Is(err, wdb.ErrNotFound)
	if err != nil && !created {
		return Subscription{}, false, &Error{Kind: KindInternal, Err: err}
	}
	if created {
		sub := wdb.Subscription{
			UserID: uc.ID, ShowPID: show,
			Folder: strings.TrimSpace(req.Folder), Private: hasCreds,
			CreatedAtNS: now, UpdatedAtNS: now,
		}
		if err := l.db.UpsertSubscription(ctx, sub); err != nil {
			return Subscription{}, false, &Error{Kind: KindInternal, Err: err}
		}
		if sub.Private {
			l.markShowPrivate(ctx, show)
		}
		l.afterSubscriptionChange(ctx, uc, show, pod.FeedURL, "add", meta)
	}

	out, err := l.subscriptionFor(ctx, uc, pod)
	if err != nil {
		return Subscription{}, false, err
	}
	return out, created, nil
}

// Unsubscribe removes the caller's subscription; the show and its
// episodes stay. With removeDownloads, and only when the caller was
// the last subscriber, the show's downloaded audio moves to the trash
// (recoverable; playback state untouched); while other subscribers
// remain their retention owns the files and the flag is ignored.
// Unsubscribing from an unfollowed show is a no-op.
func (l *Library) Unsubscribe(ctx context.Context, uc *UserCtx, apiShowPID string, removeDownloads bool) error {
	return l.unsubscribe(ctx, uc, apiShowPID, removeDownloads, subChangeMeta{})
}

func (l *Library) unsubscribe(ctx context.Context, uc *UserCtx, apiShowPID string, removeDownloads bool, meta subChangeMeta) error {
	pod, err := l.getShow(ctx, apiShowPID)
	if err != nil {
		return err
	}
	existed, err := l.db.DeleteSubscription(ctx, uc.ID, string(pod.PID))
	if err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	if !existed {
		return nil
	}
	l.afterSubscriptionChange(ctx, uc, string(pod.PID), pod.FeedURL, "remove", meta)
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

// removeShowDownloads trashes every downloaded episode of a show that
// nobody subscribes to anymore, skipping files that read as actively
// played (a non-subscriber can still be listening). Best effort: the
// unsubscribe already succeeded, and a skipped or failed file simply
// stays until a later cleanup.
func (l *Library) removeShowDownloads(ctx context.Context, showPID model.PID) {
	eps, err := l.lib.Podcasts().Episodes(ctx, showPID, 0)
	if err != nil {
		l.log.Warn("listing episodes for cleanup", "show", string(showPID), "err", err)
		return
	}
	users, err := l.db.ListUsers(ctx, "", 10000)
	if err != nil {
		l.log.Warn("listing users for cleanup", "err", err)
		return
	}
	var remove []model.PID
	skipped := 0
	for _, ep := range eps {
		// A queued fetch would re-land its file after this cleanup, so
		// cancel it whether or not the episode has a file yet.
		if err := l.db.CompleteFetch(ctx, string(ep.PID)); err != nil {
			l.log.Warn("canceling queued fetch", "episode", string(ep.PID), "err", err)
		}
		if !ep.Downloaded {
			continue
		}
		inUse := false
		for _, u := range users {
			st, err := l.lib.Playback().State(ctx, model.PID(u.WaxbinUserPID), ep.PID)
			if err != nil {
				continue
			}
			if l.stateReadsInUse(st) {
				inUse = true
				break
			}
		}
		if inUse {
			skipped++
			continue
		}
		remove = append(remove, ep.PID)
	}
	if skipped > 0 {
		l.log.Info("cleanup skipped in-use episodes", "show", string(showPID), "skipped", skipped)
	}
	if len(remove) == 0 {
		return
	}
	plan, err := l.lib.PlanDeletePIDs(ctx, remove, model.DeleteTrash)
	if err != nil {
		l.log.Warn("planning download cleanup", "show", string(showPID), "err", err)
		return
	}
	if _, err := l.lib.ApplyDelete(ctx, plan); err != nil {
		l.log.Warn("applying download cleanup", "show", string(showPID), "err", err)
		return
	}
	l.log.Info("unsubscribe reclaimed downloads", "show", string(showPID), "episodes", len(remove))
}

// afterSubscriptionChange fans out everything a subscription change
// implies: the user's own sync event, the gpodder change log, a
// retention re-evaluation (the union may have shifted), and the
// caller's catalog cursors retired. The cursor bump matters because
// subscriptions scope which episodes and shows the caller's catalog
// view contains: a mirror synced under the old membership holds rows
// (or lacks rows) the new membership disagrees on, and episode change
// seqs predate a fresh subscribe, so only a clean re-mirror converges.
// Never fails the mutation.
func (l *Library) afterSubscriptionChange(ctx context.Context, uc *UserCtx, showPID, feedURL, action string, meta subChangeMeta) {
	l.emitUserEvent(ctx, uc.ID, eventSubscription, showPID)
	l.bumpGrantEpoch(ctx, uc.ID)
	if feedURL != "" {
		if err := l.db.AppendGpodderSubEvent(ctx, wdb.GpodderSubEvent{
			UserID: uc.ID, FeedURL: feedURL, Action: action,
			DeviceID: meta.deviceID, TsSec: time.Now().Unix(),
		}); err != nil {
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
func (l *Library) Subscriptions(ctx context.Context, uc *UserCtx, cursor string, limit int) ([]Subscription, string, error) {
	rows, err := l.db.SubscriptionsByUser(ctx, uc.ID)
	if err != nil {
		return nil, "", &Error{Kind: KindInternal, Err: err}
	}
	subs := make([]Subscription, 0, len(rows))
	for _, row := range rows {
		pod, err := l.lib.Podcasts().Get(ctx, model.PID(row.ShowPID))
		if err != nil {
			// A show removed out from under a subscription row is a
			// dangling reference; tolerate and skip.
			continue
		}
		s, err := l.subscriptionRow(ctx, pod, row)
		if err != nil {
			return nil, "", err
		}
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
	next := ""
	if end < len(subs) && len(page) > 0 {
		last := page[len(page)-1]
		next = encodeTitleCursor(last.Show.Title, last.Show.PID)
	}
	return page, next, nil
}

// PodcastDetailFor returns any cataloged show with the caller's
// subscription state.
func (l *Library) PodcastDetailFor(ctx context.Context, uc *UserCtx, apiShowPID string) (PodcastDetail, error) {
	pod, err := l.getShow(ctx, apiShowPID)
	if err != nil {
		return PodcastDetail{}, err
	}
	if !l.podcastsVisible(ctx, uc) {
		return PodcastDetail{}, errNotFound("no show with pid " + apiShowPID)
	}
	show, err := l.showDTO(ctx, pod, true)
	if err != nil {
		return PodcastDetail{}, err
	}
	out := PodcastDetail{Show: show}
	row, err := l.db.SubscriptionFor(ctx, uc.ID, string(pod.PID))
	if err == nil {
		out.Subscribed = true
		st := settingsDTO(row)
		out.Settings = &st
	} else if !errors.Is(err, wdb.ErrNotFound) {
		return PodcastDetail{}, &Error{Kind: KindInternal, Err: err}
	}
	return out, nil
}

// PutSubscriptionSettings fully replaces the caller's settings for one
// subscription.
func (l *Library) PutSubscriptionSettings(ctx context.Context, uc *UserCtx, apiShowPID string, s SubscriptionSettings) (Subscription, error) {
	pod, err := l.getShow(ctx, apiShowPID)
	if err != nil {
		return Subscription{}, err
	}
	show := string(pod.PID)
	existing, err := l.db.SubscriptionFor(ctx, uc.ID, show)
	if errors.Is(err, wdb.ErrNotFound) {
		return Subscription{}, errNotFound("not subscribed to " + apiShowPID)
	}
	if err != nil {
		return Subscription{}, &Error{Kind: KindInternal, Err: err}
	}
	if s.Speed != nil && (*s.Speed < 0.5 || *s.Speed > 3.5) {
		return Subscription{}, errInvalid("speed must be between 0.5 and 3.5")
	}
	if s.RetentionKeep != nil && *s.RetentionKeep < 0 {
		return Subscription{}, errInvalid("retentionKeep must not be negative")
	}
	row := wdb.Subscription{
		UserID: uc.ID, ShowPID: show,
		Folder:        strings.TrimSpace(s.Folder),
		Private:       s.Private,
		RetentionKeep: s.RetentionKeep,
		AutoDownload:  s.AutoDownload,
		Speed:         s.Speed,
		TrimSilence:   s.TrimSilence,
		VoiceBoost:    s.VoiceBoost,
		SkipIntroSec:  s.SkipIntroSec,
		SkipOutroSec:  s.SkipOutroSec,
		CreatedAtNS:   existing.CreatedAtNS,
		UpdatedAtNS:   time.Now().UnixNano(),
	}
	if err := l.db.UpsertSubscription(ctx, row); err != nil {
		return Subscription{}, &Error{Kind: KindInternal, Err: err}
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
	return l.subscriptionFor(ctx, uc, pod)
}

// Episodes lists one show's episodes newest first, keyset-paged on
// (publishedAt, pid). Publication falls back to first-seen time so the
// order is total.
func (l *Library) Episodes(ctx context.Context, uc *UserCtx, apiShowPID, cursor string, limit int) ([]EpisodeSummary, string, error) {
	pod, err := l.getShow(ctx, apiShowPID)
	if err != nil {
		return nil, "", err
	}
	if !l.podcastsVisible(ctx, uc) {
		return nil, "", errNotFound("no show with pid " + apiShowPID)
	}
	eps, err := l.lib.Podcasts().Episodes(ctx, pod.PID, 0)
	if err != nil {
		return nil, "", classify(err)
	}
	rows := make([]EpisodeSummary, 0, len(eps))
	for _, ep := range eps {
		rows = append(rows, l.episodeSummary(ctx, ep))
	}
	sort.Slice(rows, func(i, j int) bool {
		if rows[i].PublishedNS != rows[j].PublishedNS {
			return rows[i].PublishedNS > rows[j].PublishedNS
		}
		return rows[i].PID > rows[j].PID
	})

	start := 0
	if cursor != "" {
		pubNS, pid, ok := decodePubCursor(cursor)
		if !ok {
			return nil, "", errInvalid("malformed cursor")
		}
		start = sort.Search(len(rows), func(i int) bool {
			if rows[i].PublishedNS != pubNS {
				return rows[i].PublishedNS < pubNS
			}
			return rows[i].PID < pid
		})
	}
	end := min(start+limit, len(rows))
	page := rows[start:end]
	next := ""
	if end < len(rows) && len(page) > 0 {
		last := page[len(page)-1]
		next = encodePubCursor(last.PublishedNS, last.PID)
	}
	return page, next, nil
}

// EpisodeDetailFor returns one episode with sanitized show notes and
// chapters.
func (l *Library) EpisodeDetailFor(ctx context.Context, uc *UserCtx, apiEpisodePID string) (EpisodeDetail, error) {
	det, err := l.getEpisode(ctx, apiEpisodePID)
	if err != nil {
		return EpisodeDetail{}, err
	}
	if !l.podcastsVisible(ctx, uc) {
		return EpisodeDetail{}, errNotFound("no episode with pid " + apiEpisodePID)
	}
	out := EpisodeDetail{
		EpisodeSummary:  l.episodeSummary(ctx, det.Episode),
		DescriptionHTML: sanitizeShowNotes(det.Episode.Description),
		Link:            det.Episode.Link,
	}
	for i, ch := range det.Chapters {
		out.Chapters = append(out.Chapters, ChapterMark{
			Index: i, Title: ch.Title, StartMS: ch.StartMS, EndMS: ch.EndMS,
		})
	}
	return out, nil
}

// RefreshPodcast syncs one show's feed now (subscribers only) and
// reports new episodes. Refreshes within a minute of the last sync
// answer from it.
func (l *Library) RefreshPodcast(ctx context.Context, uc *UserCtx, apiShowPID string) (int, error) {
	pod, err := l.getShow(ctx, apiShowPID)
	if err != nil {
		return 0, err
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
	return l.syncShow(ctx, pod.PID)
}

// QueueEpisodeFetch queues a server-side enclosure download. The
// caller must be subscribed to the show; an already-present episode is
// a no-op.
func (l *Library) QueueEpisodeFetch(ctx context.Context, uc *UserCtx, apiEpisodePID string) error {
	det, err := l.getEpisode(ctx, apiEpisodePID)
	if err != nil {
		return err
	}
	ep := det.Episode
	if _, err := l.db.SubscriptionFor(ctx, uc.ID, string(ep.PodcastPID)); err != nil {
		if errors.Is(err, wdb.ErrNotFound) {
			return &Error{Kind: KindForbidden, Msg: "fetching needs a subscription to the show"}
		}
		return &Error{Kind: KindInternal, Err: err}
	}
	if ep.Downloaded {
		return nil
	}
	if l.podcastDir == "" {
		// Never queue into a void: without a download directory no
		// worker runs and a queued row would read as pending forever.
		return &Error{Kind: KindUnsupported,
			Msg: "episode downloads are disabled on this server (no podcast directory configured)"}
	}
	if err := l.db.EnqueueFetch(ctx, string(ep.PID), uc.ID, time.Now().UnixNano()); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	return nil
}

// RemoveEpisodeDownload is the fetch's inverse: the episode's audio
// moves into the library trash (archive, never delete: playback state
// survives, the file is restorable until purged, the episode is
// fetchable again). Subscribers only, like the fetch; an episode that
// reads as actively played refuses with conflict rather than killing
// the listener's stream.
func (l *Library) RemoveEpisodeDownload(ctx context.Context, uc *UserCtx, apiEpisodePID string) error {
	det, err := l.getEpisode(ctx, apiEpisodePID)
	if err != nil {
		return err
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

	subs, err := l.db.SubscribersByShow(ctx, string(ep.PodcastPID))
	if err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	for _, s := range subs {
		u, err := l.userCatalogPID(ctx, s.UserID)
		if err != nil || u == "" {
			continue
		}
		st, err := l.lib.Playback().State(ctx, u, ep.PID)
		if err != nil {
			continue
		}
		if l.stateReadsInUse(st) {
			return &Error{Kind: KindConflict,
				Msg: "someone is listening to this episode right now; try again when playback stops"}
		}
	}

	plan, err := l.lib.PlanDeletePIDs(ctx, []model.PID{ep.PID}, model.DeleteTrash)
	if err != nil {
		return classify(err)
	}
	if _, err := l.lib.ApplyDelete(ctx, plan); err != nil {
		return classify(err)
	}
	return nil
}

// --- internals ---------------------------------------------------------------

// subscribedShowSet loads the caller's subscribed show set (bare
// pids). Subscriptions are per-user views, so this set is what scopes
// episodes in listings, browse, search, and catalog sync.
func (l *Library) subscribedShowSet(ctx context.Context, uc *UserCtx) (map[string]bool, error) {
	rows, err := l.db.SubscriptionsByUser(ctx, uc.ID)
	if err != nil {
		return nil, err
	}
	set := make(map[string]bool, len(rows))
	for _, row := range rows {
		set[row.ShowPID] = true
	}
	return set, nil
}

// subscriptionFilter scopes podcast episodes to the caller's own
// subscriptions, loading the set lazily so item pages without episodes
// never pay for it. Failures fail closed: an episode is hidden rather
// than leaked into a view whose scope could not be established.
type subscriptionFilter struct {
	uc     *UserCtx
	loaded bool
	failed bool
	set    map[string]bool
}

func (l *Library) newSubscriptionFilter(uc *UserCtx) *subscriptionFilter {
	return &subscriptionFilter{uc: uc}
}

// allowsItem reports whether the caller's listings include this item.
// Non-episodes always pass; episodes pass only for subscribers of
// their show.
func (f *subscriptionFilter) allowsItem(ctx context.Context, l *Library, it *model.ItemView) bool {
	if it.Kind != model.KindEpisode {
		return true
	}
	return f.allowsEpisode(ctx, l, it.PID)
}

func (f *subscriptionFilter) allowsEpisode(ctx context.Context, l *Library, episodePID model.PID) bool {
	f.ensure(ctx, l)
	if f.failed || len(f.set) == 0 {
		return false
	}
	det, err := l.lib.Podcasts().Episode(ctx, episodePID)
	if err != nil {
		return false
	}
	return f.set[string(det.Episode.PodcastPID)]
}

// allowsShow reports whether the caller subscribes to the show itself.
func (f *subscriptionFilter) allowsShow(ctx context.Context, l *Library, showPID string) bool {
	f.ensure(ctx, l)
	return !f.failed && f.set[showPID]
}

func (f *subscriptionFilter) ensure(ctx context.Context, l *Library) {
	if f.loaded {
		return
	}
	f.loaded = true
	set, err := l.subscribedShowSet(ctx, f.uc)
	if err != nil {
		l.log.Warn("loading subscription set", "user", f.uc.ID, "err", err)
		f.failed = true
	}
	f.set = set
}

// getShow resolves an API show PID.
func (l *Library) getShow(ctx context.Context, apiShowPID string) (*model.Podcast, error) {
	prefix, pid, ok := parseAPIPID(apiShowPID)
	if !ok || prefix != PrefixPodcast {
		return nil, errNotFound("no show with pid " + apiShowPID)
	}
	pod, err := l.lib.Podcasts().Get(ctx, pid)
	if err != nil {
		return nil, classify(err)
	}
	return pod, nil
}

// getEpisode resolves an API episode PID to its detail.
func (l *Library) getEpisode(ctx context.Context, apiEpisodePID string) (*model.EpisodeDetail, error) {
	prefix, pid, ok := parseAPIPID(apiEpisodePID)
	if !ok || prefix != PrefixEpisode {
		return nil, errNotFound("no episode with pid " + apiEpisodePID)
	}
	det, err := l.lib.Podcasts().Episode(ctx, pid)
	if err != nil {
		return nil, classify(err)
	}
	return det, nil
}

// subscriptionFor builds the caller's subscription DTO for a show.
func (l *Library) subscriptionFor(ctx context.Context, uc *UserCtx, pod *model.Podcast) (Subscription, error) {
	row, err := l.db.SubscriptionFor(ctx, uc.ID, string(pod.PID))
	if err != nil {
		return Subscription{}, &Error{Kind: KindInternal, Err: err}
	}
	return l.subscriptionRow(ctx, pod, row)
}

func (l *Library) subscriptionRow(ctx context.Context, pod *model.Podcast, row wdb.Subscription) (Subscription, error) {
	show, err := l.showDTO(ctx, pod, false)
	if err != nil {
		return Subscription{}, err
	}
	return Subscription{
		Show:           show,
		Settings:       settingsDTO(row),
		SubscribedAtNS: row.CreatedAtNS,
	}, nil
}

func settingsDTO(row wdb.Subscription) SubscriptionSettings {
	return SubscriptionSettings{
		RetentionKeep: row.RetentionKeep,
		AutoDownload:  row.AutoDownload,
		Folder:        row.Folder,
		Private:       row.Private,
		Speed:         row.Speed,
		TrimSilence:   row.TrimSilence,
		VoiceBoost:    row.VoiceBoost,
		SkipIntroSec:  row.SkipIntroSec,
		SkipOutroSec:  row.SkipOutroSec,
	}
}

// showDTO builds the API show view. withCounts adds the episode count
// and newest publication time (a full episode listing; detail surfaces
// only).
func (l *Library) showDTO(ctx context.Context, pod *model.Podcast, withCounts bool) (PodcastShow, error) {
	out := PodcastShow{
		PID:             apiPID(PrefixPodcast, pod.PID),
		Title:           pod.Title,
		Author:          pod.Author,
		DescriptionHTML: sanitizeShowNotes(pod.Description),
		Link:            pod.Link,
		SourceType:      string(pod.SourceType),
	}
	if out.SourceType == "" {
		out.SourceType = "rss"
	}
	if !l.showIsPrivate(ctx, pod) {
		out.FeedURL = pod.FeedURL
	}
	st, err := l.db.FeedStateFor(ctx, string(pod.PID))
	if err == nil {
		out.RefreshDisabled = st.Disabled
	}
	if withCounts {
		eps, err := l.lib.Podcasts().Episodes(ctx, pod.PID, 0)
		if err == nil {
			out.EpisodeCount = len(eps)
			for _, ep := range eps {
				if ep.PubDateNS > out.LastPublishedNS {
					out.LastPublishedNS = ep.PubDateNS
				}
			}
		}
	}
	return out, nil
}

// showIsPrivate applies the sticky privacy rule: credentialed shows
// and shows any subscriber ever flagged private stay private.
func (l *Library) showIsPrivate(ctx context.Context, pod *model.Podcast) bool {
	if pod.AuthUser != "" {
		return true
	}
	private, err := l.db.SyncStateGet(ctx, syncKeyShowPrivate+string(pod.PID))
	if err != nil {
		l.log.Warn("reading show privacy", "show", string(pod.PID), "err", err)
		return true
	}
	return private != ""
}

// markShowPrivate makes a show sticky-private.
func (l *Library) markShowPrivate(ctx context.Context, showPID string) {
	if err := l.db.SyncStateSet(ctx, syncKeyShowPrivate+showPID, "1"); err != nil {
		l.log.Warn("marking show private", "show", showPID, "err", err)
	}
}

// episodeSummary builds the episode list row from the catalog episode.
func (l *Library) episodeSummary(ctx context.Context, ep *model.Episode) EpisodeSummary {
	pub := ep.PubDateNS
	if pub == 0 {
		// Feeds without pubDate still need a total order; first-seen
		// time is stable and monotone enough for paging.
		pub = ep.CreatedAt
	}
	out := EpisodeSummary{
		ItemSummary: ItemSummary{
			PID:        apiPID(PrefixEpisode, ep.PID),
			MediaType:  "podcast",
			Title:      ep.Title,
			Artist:     ep.PodcastTitle,
			Album:      ep.PodcastTitle,
			DurationMS: ep.DurationMS,
		},
		ShowPID:     apiPID(PrefixPodcast, ep.PodcastPID),
		Season:      ep.Season,
		EpisodeNo:   ep.EpisodeNo,
		EpisodeType: string(ep.EpisodeType),
		PublishedNS: pub,
		Downloaded:  ep.Downloaded,
		Explicit:    ep.Explicit,
		HasTx:       ep.TranscriptURL != "",
	}
	if !ep.Downloaded {
		if attempts, lastErr, err := l.db.FetchQueueRow(ctx, string(ep.PID)); err == nil {
			if attempts >= fetchMaxAttempts {
				out.FetchState, out.FetchError = "failed", lastErr
			} else {
				out.FetchState = "queued"
			}
		}
	}
	return out
}

// classifyFeedErr maps a subscribe or sync failure onto the API error
// model, scrubbing feed URLs out of upstream detail for private shows.
func (l *Library) classifyFeedErr(ctx context.Context, err error, feedURL string, private bool) error {
	kind := KindOf(classify(err))
	switch kind {
	case KindInvalid, KindUnsupported, KindConflict, KindMaintenance:
		return classify(err)
	}
	msg := err.Error()
	if private {
		msg = "the feed could not be fetched; detail withheld for a private feed (see the server log)"
		l.log.Warn("private feed fetch failed", "err", err)
	} else if feedURL != "" {
		msg = strings.ReplaceAll(msg, feedURL, "the feed url")
	}
	return &Error{Kind: KindUpstream, Msg: msg, Err: err}
}

// --- cursors -----------------------------------------------------------------

func encodeTitleCursor(title, pid string) string {
	return encodeOpaqueCursor(fmt.Sprintf("t1|%d|%s|%s", len(title), title, pid))
}

func decodeTitleCursor(s string) (title, pid string, ok bool) {
	raw, ok := decodeOpaqueCursor(s)
	if !ok {
		return "", "", false
	}
	rest, found := strings.CutPrefix(raw, "t1|")
	if !found {
		return "", "", false
	}
	i := strings.IndexByte(rest, '|')
	if i < 0 {
		return "", "", false
	}
	n := 0
	if _, err := fmt.Sscanf(rest[:i], "%d", &n); err != nil || n < 0 || i+1+n+1 > len(rest) {
		return "", "", false
	}
	title = rest[i+1 : i+1+n]
	if rest[i+1+n] != '|' {
		return "", "", false
	}
	return title, rest[i+1+n+1:], true
}

func encodePubCursor(pubNS int64, pid string) string {
	return encodeOpaqueCursor(fmt.Sprintf("p1|%d|%s", pubNS, pid))
}

func decodePubCursor(s string) (pubNS int64, pid string, ok bool) {
	raw, ok := decodeOpaqueCursor(s)
	if !ok {
		return 0, "", false
	}
	parts := strings.SplitN(raw, "|", 3)
	if len(parts) != 3 || parts[0] != "p1" {
		return 0, "", false
	}
	if _, err := fmt.Sscanf(parts[1], "%d", &pubNS); err != nil {
		return 0, "", false
	}
	return pubNS, parts[2], true
}
