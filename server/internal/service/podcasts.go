package service

import (
	"context"
	"errors"
	"fmt"
	"net/url"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/podcast"
	"github.com/colespringer/waxbin/query"

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
	Explicit        bool
	// Podcasting 2.0 channel extras. FundingURL/FundingMessage and Medium
	// come back on every read; Persons is populated on the detail read only.
	FundingURL     string
	FundingMessage string
	Medium         string
	Persons        []FeedPerson
}

// FeedPerson is one <podcast:person> credit at the show or episode level.
// An empty Role reads as "host" per the podcast namespace.
type FeedPerson struct {
	Name  string
	Role  string
	Group string
	Img   string
	Href  string
}

// Soundbite is one <podcast:soundbite> highlight clip of an episode: a
// window into the episode audio. An empty Title reuses the episode title.
type Soundbite struct {
	StartMS    int64
	DurationMS int64
	Title      string
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
	// AutoDLFilter narrows what auto-download takes; the zero value
	// takes everything.
	AutoDLFilter EpisodeFilter
}

// EpisodeFilter decides which new episodes auto-download takes, by
// keyword against the episode title. Empty Include admits everything;
// Exclude wins where both match.
type EpisodeFilter struct {
	Include []string
	Exclude []string
}

// Empty reports a filter that admits every episode, which is what an
// unset one does.
func (f EpisodeFilter) Empty() bool { return len(f.Include) == 0 && len(f.Exclude) == 0 }

// Admits reports whether an episode title passes the filter. Terms
// match case-insensitively as substrings; titles only, never
// descriptions, because a feed description carries sponsor copy and
// boilerplate a listener would never call a match.
func (f EpisodeFilter) Admits(title string) bool {
	folded := strings.ToLower(title)
	for _, term := range f.Exclude {
		if t := strings.ToLower(strings.TrimSpace(term)); t != "" && strings.Contains(folded, t) {
			return false
		}
	}
	if len(f.Include) == 0 {
		return true
	}
	for _, term := range f.Include {
		if t := strings.ToLower(strings.TrimSpace(term)); t != "" && strings.Contains(folded, t) {
			return true
		}
	}
	// An include list that is nothing but blank terms is not a filter
	// anybody expressed, so it admits rather than rejecting everything.
	return !hasTerm(f.Include)
}

// hasTerm reports whether a term list carries at least one usable term.
func hasTerm(terms []string) bool {
	for _, t := range terms {
		if strings.TrimSpace(t) != "" {
			return true
		}
	}
	return false
}

// normalizeTerms trims, drops blanks, and caps a term list for storage.
func normalizeTerms(terms []string) []string {
	if len(terms) == 0 {
		return nil
	}
	out := make([]string, 0, len(terms))
	for _, t := range terms {
		t = strings.TrimSpace(t)
		if t == "" {
			continue
		}
		// By runes, not bytes. A byte slice would cut a multi-byte rune
		// in half and store invalid UTF-8, which a non-English show
		// title filter reaches immediately; the spec's maxLength counts
		// characters, so this is also what makes the two agree.
		if utf8.RuneCountInString(t) > maxFilterTermLen {
			t = string([]rune(t)[:maxFilterTermLen])
		}
		out = append(out, t)
		if len(out) == maxFilterTerms {
			break
		}
	}
	if len(out) == 0 {
		return nil
	}
	return out
}

// The spec's own bounds on a filter, enforced here so a client that
// ignores them stores something sane rather than an unbounded document.
const (
	maxFilterTerms   = 64
	maxFilterTermLen = 128
)

// Subscription is one user's subscription with its show.
type Subscription struct {
	Show           PodcastShow
	Settings       SubscriptionSettings
	SubscribedAtNS int64

	// UnplayedCount is how many of the show's visible episodes the
	// caller has not crossed the played threshold on: the whole
	// backlog, which is the number a subscription tile shows and the
	// one no client can compute from a page of episodes.
	//
	// A pointer because absent and zero are different answers. Only the
	// listing computes it, and the two single-subscription surfaces
	// (subscribe, save settings) answer without one. A hard zero there
	// would tell a client that just followed a four-hundred-episode
	// show it has nothing waiting.
	UnplayedCount *int
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
	// HasEnclosure reports that the feed named audio for this episode,
	// so an unfetched one still streams by passthrough.
	HasEnclosure bool
}

// EpisodeDetail is the full episode view.
type EpisodeDetail struct {
	EpisodeSummary
	DescriptionHTML string
	Link            string
	Chapters        []ChapterMark
	Persons         []FeedPerson
	Soundbites      []Soundbite
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
	if err := requirePodcastManagement(uc); err != nil {
		return Subscription{}, false, err
	}
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
	if pod.Explicit && !uc.Explicit {
		return Subscription{}, false, &Error{Kind: KindForbidden,
			Msg: "this account cannot subscribe to explicit shows"}
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
	if err := requirePodcastManagement(uc); err != nil {
		return err
	}
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
// [withCounts] asks for the unplayed backlog on each row, which costs a
// walk of the show's episodes and a batched play-state read per
// subscription. The surfaces that draw a tile want it; the Subsonic
// adapter, which pages every subscription and then lists their episodes
// anyway, does not, and asking for it there would double the work for a
// number nothing in that protocol carries.
func (l *Library) Subscriptions(ctx context.Context, uc *UserCtx, cursor string, limit int, withCounts bool) ([]Subscription, string, error) {
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
		s, err := l.subscriptionRow(ctx, pod, row)
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
	// After the slice, never before it: the walk is per show, and doing
	// it for every subscription to answer a page of twenty would be
	// paying for the whole list on every page of it.
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

// countShow fills the three numbers a subscription tile draws.
//
// Counting queries for a caller who may see everything; a walk for one
// who may not, since the explicit gate has no item query field to push
// down (filed upstream). Explicit is granted by default, so the walk is
// the rare branch.
func (l *Library) countShow(
	ctx context.Context,
	uc *UserCtx,
	pod *model.Podcast,
	sub *Subscription,
) error {
	if pod == nil {
		return nil
	}
	if uc.Explicit {
		return l.countShowByQuery(ctx, uc, pod, sub)
	}
	eps, states, err := l.showEpisodeStates(ctx, uc, pod)
	if err != nil {
		return err
	}
	unplayed := 0
	for _, ep := range eps {
		if st := states[ep.PID]; st == nil || !st.Played {
			unplayed++
		}
	}
	sub.UnplayedCount = &unplayed
	sub.Show.EpisodeCount = len(eps)
	for _, ep := range eps {
		if ep.PubDateNS > sub.Show.LastPublishedNS {
			sub.Show.LastPublishedNS = ep.PubDateNS
		}
	}
	return nil
}

// showEpisodeQuery is the item-query form of "this show's episodes".
// `kind is episode` is redundant beside podcast_pid but states intent.
// The counts match the walk because an items query counts an episode
// nobody has fetched: the file join is a LEFT JOIN with no state
// filter.
func showEpisodeQuery(pod *model.Podcast) *query.Builder {
	return query.New(query.EntityItems).
		Where("kind", query.OpIs, string(model.KindEpisode)).
		Where("podcast_pid", query.OpIs, string(pod.PID))
}

// countShowByQuery fills the same three numbers without a row per
// episode. Unrestricted callers only; see countShow.
func (l *Library) countShowByQuery(
	ctx context.Context,
	uc *UserCtx,
	pod *model.Podcast,
	sub *Subscription,
) error {
	// No per-user field in this one, so it needs no user pid.
	total, err := l.lib.Count(ctx, showEpisodeQuery(pod).Build(), "")
	if err != nil {
		return classify(err)
	}
	// `played` is per-user, so an empty pid would count somebody
	// else's backlog.
	unplayed, err := l.lib.Count(ctx,
		showEpisodeQuery(pod).Where("played", query.OpIs, 0).Build(),
		model.PID(uc.CatalogPID))
	if err != nil {
		return classify(err)
	}
	sub.Show.EpisodeCount = total
	sub.UnplayedCount = &unplayed

	// Newest publication first, undated last, so the first row is the
	// max the walk computed. No episodes and all-undated both leave
	// LastPublishedNS zero, as the walk did.
	newest, err := l.lib.Podcasts().Episodes(ctx, pod.PID, 1)
	if err != nil {
		return classify(err)
	}
	if len(newest) > 0 {
		sub.Show.LastPublishedNS = newest[0].PubDateNS
	}
	return nil
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
	if pod.Explicit && !uc.Explicit {
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
		AutoDLInclude: normalizeTerms(s.AutoDLFilter.Include),
		AutoDLExclude: normalizeTerms(s.AutoDLFilter.Exclude),
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
	if pod.Explicit && !uc.Explicit {
		return nil, "", errNotFound("no show with pid " + apiShowPID)
	}
	eps, err := l.lib.Podcasts().Episodes(ctx, pod.PID, 0)
	if err != nil {
		return nil, "", classify(err)
	}
	rows := make([]EpisodeSummary, 0, len(eps))
	for _, ep := range eps {
		if ep.Explicit && !uc.Explicit {
			continue
		}
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
	if det.Episode.Explicit && !uc.Explicit {
		return EpisodeDetail{}, errNotFound("no episode with pid " + apiEpisodePID)
	}
	out := EpisodeDetail{
		EpisodeSummary:  l.episodeSummary(ctx, det.Episode),
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
	return out, nil
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
func (l *Library) RefreshPodcast(ctx context.Context, uc *UserCtx, apiShowPID string) (int, error) {
	if err := requirePodcastManagement(uc); err != nil {
		return 0, err
	}
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
	if err := requirePodcastManagement(uc); err != nil {
		return err
	}
	if l.podcastDir != "" {
		if pid, err := l.libraryForPath(ctx, l.podcastDir); err == nil {
			if err := l.CheckWritable(ctx, pid); err != nil {
				return err
			}
		}
	}
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
	if err := requirePodcastManagement(uc); err != nil {
		return err
	}
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

	plan, err := l.lib.PlanDeletePIDs(ctx, []model.PID{ep.PID}, model.DeleteTrash)
	if err != nil {
		return classify(err)
	}
	// The in-use refusal above needs a listener to stop; this one only
	// needs another job to finish, so it carries the code that says so.
	if _, err := l.lib.ApplyDelete(ctx, plan); err != nil {
		return classifyMutation(err)
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
		AutoDLFilter: EpisodeFilter{
			Include: row.AutoDLInclude,
			Exclude: row.AutoDLExclude,
		},
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
		Explicit:        pod.Explicit,
		FundingURL:      pod.FundingURL,
		FundingMessage:  pod.FundingMessage,
		Medium:          pod.Medium,
		Persons:         feedPersonsDTO(pod.Persons),
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
		// No explicit filter here (the show's own size, not a caller's
		// view), so nothing to gate. Best effort, as the walk was.
		if n, err := l.lib.Count(ctx, showEpisodeQuery(pod).Build(), ""); err == nil {
			out.EpisodeCount = n
		}
		if newest, err := l.lib.Podcasts().Episodes(ctx, pod.PID, 1); err == nil && len(newest) > 0 {
			out.LastPublishedNS = newest[0].PubDateNS
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

// showEpisodeStates reads one show's visible episodes together with the
// caller's play state for each, in one batched state pass.
//
// The two surfaces that need it (the unplayed count on a subscription
// and the cross-show episode listing) both want "this show's episodes,
// and what has this listener done with them", and a second copy of that
// walk is how the count and the list come to disagree about which
// episodes are hidden from the caller.
func (l *Library) showEpisodeStates(
	ctx context.Context,
	uc *UserCtx,
	pod *model.Podcast,
) ([]*model.Episode, map[model.PID]*model.PlayState, error) {
	eps, err := l.lib.Podcasts().Episodes(ctx, pod.PID, 0)
	if err != nil {
		return nil, nil, classify(err)
	}
	visible := make([]*model.Episode, 0, len(eps))
	pids := make([]model.PID, 0, len(eps))
	for _, ep := range eps {
		if ep.Explicit && !uc.Explicit {
			continue
		}
		visible = append(visible, ep)
		pids = append(pids, ep.PID)
	}
	if len(visible) == 0 {
		return visible, map[model.PID]*model.PlayState{}, nil
	}
	batch, err := l.lib.PlayStatesForItems(ctx, pids)
	if err != nil {
		return nil, nil, classify(err)
	}
	userPID := model.PID(uc.CatalogPID)
	states := make(map[model.PID]*model.PlayState, len(visible))
	for _, ep := range visible {
		if st := userPlayState(batch[ep.PID], userPID); st != nil {
			states[ep.PID] = st
		}
	}
	return visible, states, nil
}

// SubscribedEpisodeFilter names which episodes a cross-show listing
// keeps.
type SubscribedEpisodeFilter string

const (
	// EpisodesLatest is every episode of every followed show.
	EpisodesLatest SubscribedEpisodeFilter = "latest"
	// EpisodesUnplayed drops what the caller has finished hearing.
	EpisodesUnplayed SubscribedEpisodeFilter = "unplayed"
	// EpisodesInProgress keeps what was started and not finished.
	EpisodesInProgress SubscribedEpisodeFilter = "in-progress"
)

// Valid reports whether f is a filter this server serves.
func (f SubscribedEpisodeFilter) Valid() bool {
	switch f {
	case EpisodesLatest, EpisodesUnplayed, EpisodesInProgress:
		return true
	default:
		return false
	}
}

// SubscribedEpisodes pages episodes across every show the caller
// follows.
//
// Ordering follows the filter, because the two questions want different
// orders: what is new is newest-published first, and what to pick up
// again is most-recently-played first. The cursor carries the same pair
// either way (a sort key and a pid), so paging is keyset in both.
func (l *Library) SubscribedEpisodes(
	ctx context.Context,
	uc *UserCtx,
	filter SubscribedEpisodeFilter,
	cursor string,
	limit int,
) ([]EpisodeSummary, string, error) {
	if !filter.Valid() {
		return nil, "", errInvalid("unknown filter " + string(filter))
	}
	if !l.podcastsVisible(ctx, uc) {
		return []EpisodeSummary{}, "", nil
	}
	rows, err := l.db.SubscriptionsByUser(ctx, uc.ID)
	if err != nil {
		return nil, "", &Error{Kind: KindInternal, Err: err}
	}

	// The episode, not its DTO: building a summary costs a fetch-queue
	// read per undownloaded episode, and passthrough makes undownloaded
	// the ordinary state, so building fifteen thousand of them to return
	// twelve would be fifteen thousand queries for a shelf. The rows are
	// built after the page is cut.
	type ranked struct {
		episode *model.Episode
		pid     string
		// key orders the listing: publication time, or last-played time
		// for the in-progress strip.
		key int64
	}
	out := make([]ranked, 0, 64)
	for _, sub := range rows {
		pod, err := l.lib.Podcasts().Get(ctx, model.PID(sub.ShowPID))
		if err != nil {
			// A show removed out from under a subscription row is a
			// dangling reference; tolerate and skip, as the listing does.
			continue
		}
		if pod.Explicit && !uc.Explicit {
			continue
		}
		eps, states, err := l.showEpisodeStates(ctx, uc, pod)
		if err != nil {
			return nil, "", err
		}
		for _, ep := range eps {
			st := states[ep.PID]
			switch filter {
			case EpisodesUnplayed:
				if st != nil && st.Played {
					continue
				}
			case EpisodesInProgress:
				if st == nil || st.Finished || st.PositionMS <= 0 {
					continue
				}
			case EpisodesLatest:
			}
			key := episodePublishedNS(ep)
			if filter == EpisodesInProgress {
				// When it was last played, not when its play state last
				// changed: starring a half-heard episode from two years
				// ago must not push it to the top of "where was I".
				key = st.LastPlayedAt
				if key == 0 {
					key = st.UpdatedAt
				}
			}
			out = append(out, ranked{
				episode: ep,
				pid:     apiPID(PrefixEpisode, ep.PID),
				key:     key,
			})
		}
	}

	sort.Slice(out, func(i, j int) bool {
		if out[i].key != out[j].key {
			return out[i].key > out[j].key
		}
		return out[i].pid > out[j].pid
	})

	start := 0
	if cursor != "" {
		// The filter rides in the cursor because the orders interleave
		// differently: a key issued against publication time means
		// something else entirely read as a last-played time, and the
		// keyset search would land somewhere plausible and wrong. The
		// contract promises a refusal here rather than a quiet misread.
		issued, key, pid, ok := decodeFilteredCursor(cursor)
		if !ok {
			return nil, "", errInvalid("malformed cursor")
		}
		if issued != filter {
			return nil, "", errInvalid(
				"cursor was issued for filter " + string(issued) +
					" and cannot be used with " + string(filter))
		}
		start = sort.Search(len(out), func(i int) bool {
			if out[i].key != key {
				return out[i].key < key
			}
			return out[i].pid < pid
		})
	}
	end := min(start+limit, len(out))
	page := make([]EpisodeSummary, 0, end-start)
	for _, r := range out[start:end] {
		page = append(page, l.episodeSummary(ctx, r.episode))
	}
	next := ""
	if end < len(out) && len(page) > 0 {
		last := out[end-1]
		next = encodeFilteredCursor(filter, last.key, last.pid)
	}
	return page, next, nil
}

// episodePublishedNS is the ordering time for one episode: its
// publication date, or first-seen when the feed declared none, which is
// what keeps paging total. Shared with episodeSummary, which reports the
// same number, so the order a page is cut in and the date a row shows
// can never disagree.
func episodePublishedNS(ep *model.Episode) int64 {
	if ep.PubDateNS != 0 {
		return ep.PubDateNS
	}
	return ep.CreatedAt
}

// encodeFilteredCursor stamps a cross-show listing cursor with the
// filter it was issued under, so resuming under a different one is a
// refusal rather than a wrong page.
func encodeFilteredCursor(filter SubscribedEpisodeFilter, key int64, pid string) string {
	return encodeOpaqueCursor(fmt.Sprintf("s1|%s|%d|%s", filter, key, pid))
}

func decodeFilteredCursor(s string) (
	filter SubscribedEpisodeFilter, key int64, pid string, ok bool,
) {
	raw, ok := decodeOpaqueCursor(s)
	if !ok {
		return "", 0, "", false
	}
	parts := strings.SplitN(raw, "|", 4)
	if len(parts) != 4 || parts[0] != "s1" {
		return "", 0, "", false
	}
	// ParseInt rather than Sscanf, and the reason is strictness rather
	// than speed: `Sscanf` with %d stops at the first non-digit and
	// reports success, so "123abc" decodes as 123. A cursor arrives in
	// the query string, so it is input, and input that is nearly a
	// number is not one.
	key, err := strconv.ParseInt(parts[2], 10, 64)
	if err != nil {
		return "", 0, "", false
	}
	return SubscribedEpisodeFilter(parts[1]), key, parts[3], true
}

// episodeSummary builds the episode list row from the catalog episode.
func (l *Library) episodeSummary(ctx context.Context, ep *model.Episode) EpisodeSummary {
	// Feeds without pubDate still need a total order; first-seen time
	// is stable and monotone enough for paging.
	pub := episodePublishedNS(ep)
	out := EpisodeSummary{
		ItemSummary: ItemSummary{
			PID:        apiPID(PrefixEpisode, ep.PID),
			MediaType:  "podcast",
			Title:      ep.Title,
			Artist:     ep.PodcastTitle,
			Album:      ep.PodcastTitle,
			DurationMS: ep.DurationMS,
		},
		ShowPID:      apiPID(PrefixPodcast, ep.PodcastPID),
		Season:       ep.Season,
		EpisodeNo:    ep.EpisodeNo,
		EpisodeType:  string(ep.EpisodeType),
		PublishedNS:  pub,
		Downloaded:   ep.Downloaded,
		Explicit:     ep.Explicit,
		HasTx:        ep.TranscriptURL != "",
		HasEnclosure: streamableEnclosure(ep.EnclosureURL),
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
	pubNS, err := strconv.ParseInt(parts[1], 10, 64)
	if err != nil {
		return 0, "", false
	}
	return pubNS, parts[2], true
}
