package service

import (
	"context"
	"fmt"
	"net/url"
	"slices"
	"sort"
	"strings"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
	"github.com/colespringer/waxbin/read"
	"github.com/colespringer/waxbin/waxerr"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// The reads behind the API: the caller's subscribed shows and their
// filter, show and episode lookups, the show DTO, the subscribed
// episode listing, and the sticky show-privacy rule.

// subscribedShowSet loads the caller's subscribed show set (bare
// pids). Subscriptions are per-user views, so this set is what scopes
// episodes in listings, browse, search, and catalog sync.
func (l *Podcasts) subscribedShowSet(ctx context.Context, uc *UserCtx) (map[string]bool, error) {
	shows, err := l.db.SubscribedShowPIDsByUser(ctx, uc.ID)
	if err != nil {
		return nil, err
	}
	set := make(map[string]bool, len(shows))
	for _, show := range shows {
		set[show] = true
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

func (l *Podcasts) newSubscriptionFilter(uc *UserCtx) *subscriptionFilter {
	return &subscriptionFilter{uc: uc}
}

// allowsItem reports whether the caller's listings include this item.
// Non-episodes always pass; episodes pass only for subscribers of
// their show.
func (f *subscriptionFilter) allowsItem(ctx context.Context, l *Podcasts, it *model.ItemView) bool {
	if it.Kind != model.KindEpisode {
		return true
	}
	return f.allowsEpisode(ctx, l, it)
}

// allowsEpisode reports whether the caller subscribes to the episode's
// show. The view projects the show handle, so this costs no reads.
func (f *subscriptionFilter) allowsEpisode(ctx context.Context, l *Podcasts, it *model.ItemView) bool {
	f.ensure(ctx, l)
	if f.failed || len(f.set) == 0 {
		return false
	}
	return f.set[string(it.PodcastPID)]
}

// allowsEpisodePID is allowsEpisode for callers holding only a pid
// (search hits), which pay one item read for the show handle. It stays a
// separate name rather than an overload so the cheap path is the one
// that reads cheap at the call site.
func (f *subscriptionFilter) allowsEpisodePID(ctx context.Context, l *Podcasts, episodePID model.PID) bool {
	f.ensure(ctx, l)
	if f.failed || len(f.set) == 0 {
		return false
	}
	it, err := l.lib.Get(ctx, episodePID)
	if err != nil {
		return false
	}
	return f.allowsEpisode(ctx, l, it)
}

// followsAny reports whether the caller follows at least one show.
func (f *subscriptionFilter) followsAny(ctx context.Context, l *Podcasts) bool {
	f.ensure(ctx, l)
	return !f.failed && len(f.set) > 0
}

// allowsShow reports whether the caller subscribes to the show itself.
func (f *subscriptionFilter) allowsShow(ctx context.Context, l *Podcasts, showPID string) bool {
	f.ensure(ctx, l)
	return !f.failed && f.set[showPID]
}

func (f *subscriptionFilter) ensure(ctx context.Context, l *Podcasts) {
	if f.loaded {
		return
	}
	f.loaded = true
	set, err := l.subscribedShowSet(ctx, f.uc)
	if err != nil {
		l.log.Warn("loading subscription set", "user", f.uc.ID, "err", err)
		f.failed = true
		noteDegraded(ctx)
	}
	f.set = set
}

// getShow resolves an API show PID.
func (l *Podcasts) getShow(ctx context.Context, apiShowPID string) (*model.Podcast, error) {
	prefix, pid, ok := parseAPIPID(apiShowPID)
	if !ok || prefix != PrefixPodcast {
		return nil, errNotFound("no show with pid " + apiShowPID)
	}
	pod, err := l.lib.Podcasts().Get(ctx, pid)
	if err != nil {
		if KindOf(err) == KindNotFound {
			return nil, errNotFound("no show with pid " + apiShowPID)
		}
		return nil, classify(err)
	}
	return pod, nil
}

// getEpisode resolves an API episode PID to its detail.
func (l *Podcasts) getEpisode(ctx context.Context, apiEpisodePID string) (*model.EpisodeDetail, error) {
	prefix, pid, ok := parseAPIPID(apiEpisodePID)
	if !ok || prefix != PrefixEpisode {
		return nil, errNotFound("no episode with pid " + apiEpisodePID)
	}
	det, err := l.lib.Podcasts().Episode(ctx, pid)
	if err != nil {
		if KindOf(err) == KindNotFound {
			return nil, errNotFound("no episode with pid " + apiEpisodePID)
		}
		return nil, classify(err)
	}
	return det, nil
}

// episodesByPIDs reads episodes by bare pid in one catalog read, in
// request order and each once, leaving out a pid that is no episode.
func (l *Podcasts) episodesByPIDs(ctx context.Context, pids []model.PID) ([]*model.Episode, error) {
	read := l.lib.Podcasts().EpisodesByPIDs
	if l.episodeReadHook != nil {
		read = l.episodeReadHook
	}
	eps, err := read(ctx, pids)
	if err != nil {
		return nil, classify(err)
	}
	return eps, nil
}

// subscriptionFor builds the caller's subscription DTO for a show.
func (l *Podcasts) subscriptionFor(ctx context.Context, uc *UserCtx, pod *model.Podcast) (Subscription, error) {
	row, err := l.db.SubscriptionFor(ctx, uc.ID, string(pod.PID))
	if err != nil {
		return Subscription{}, &Error{Kind: KindInternal, Err: err}
	}
	return l.subscriptionRow(ctx, uc, pod, row)
}

func (l *Podcasts) subscriptionRow(ctx context.Context, uc *UserCtx, pod *model.Podcast, row wdb.Subscription) (Subscription, error) {
	show, err := l.showDTO(ctx, uc, pod, false, row.FeedURL)
	if err != nil {
		return Subscription{}, err
	}
	return Subscription{
		Show:           show,
		Settings:       settingsDTO(row),
		SubscribedAtNS: row.CreatedAtNS,
		Withheld:       showWithheld(uc, pod),
	}, nil
}

// showWithheld reports that uc may not hear pod: an explicit show, to an
// account without explicit content.
func showWithheld(uc *UserCtx, pod *model.Podcast) bool { return pod.Explicit && !uc.Explicit }

// showReached reports whether the show's detail answers the caller: the
// podcast library in its grants, and an explicit show only with explicit
// content. A show the catalog does not hold is not reached.
func (l *Podcasts) showReached(ctx context.Context, uc *UserCtx, pid model.PID) (bool, error) {
	if !l.Grants.podcastsVisible(ctx, uc) {
		return false, nil
	}
	if uc.Explicit {
		return true, nil
	}
	pod, err := l.lib.Podcasts().Get(ctx, pid)
	if waxerr.CodeOf(err) == waxerr.CodeNotFound {
		return false, nil
	}
	if err != nil {
		return false, classify(err)
	}
	return !showWithheld(uc, pod), nil
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
// and newest publication time (detail surfaces only), counted through
// uc's view of the show; uc is consulted for nothing else. own is the
// address uc follows the show by, "" when it does not follow it: a
// follower is shown its own address, never the one the catalog took up
// from the last account to add the show.
func (l *Podcasts) showDTO(ctx context.Context, uc *UserCtx, pod *model.Podcast, withCounts bool, own string) (PodcastShow, error) {
	out := PodcastShow{
		PID:             apiPID(PrefixPodcast, pod.PID),
		Title:           clipFeedTitle(pod.Title),
		Author:          pod.Author,
		DescriptionHTML: sanitizeShowNotes(pod.Description),
		notes:           pod.Description,
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
	switch {
	case own != "":
		out.FeedURL = own
	case !l.showIsPrivate(ctx, pod):
		out.FeedURL = pod.FeedURL
	}
	st, err := l.db.FeedStateFor(ctx, string(pod.PID))
	if err == nil {
		out.RefreshDisabled = st.Disabled
	}
	if withCounts {
		// The caller's view, not the show's raw size, so the detail
		// header agrees with the episode listing drawn beneath it, which
		// drops explicit rows for a restricted caller. Best effort.
		if n, err := l.lib.Count(ctx, showEpisodeQueryFor(uc, pod).Build(), model.PID(uc.CatalogPID)); err == nil {
			out.EpisodeCount = n
		}
		if newest, err := l.newestVisibleEpisodeNS(ctx, uc, pod); err == nil {
			out.LastPublishedNS = newest
		}
		out.ArtSource = l.Reads.artSourceForRef(ctx, model.EntityRef{Type: model.ArtPodcast, PID: pod.PID})
	}
	return out, nil
}

// feedTitleMaxChars bounds a show's or an episode's title wherever WaxDeck
// names one: its feed gives it, and a feed can carry one as long as the
// feed itself.
const feedTitleMaxChars = 1000

// clipFeedTitle is a feed-given title cut to its first feedTitleMaxChars
// characters.
func clipFeedTitle(s string) string {
	n := feedTitleMaxChars
	for i := range s {
		if n == 0 {
			return s[:i]
		}
		n--
	}
	return s
}

// privateShow is the sticky privacy rule, written once: credentialed
// shows and shows any subscriber ever flagged private (the mark in
// sync_state) stay private, and a mark that could not be read counts as
// set. showIsPrivate and the playlist share filter both ask it.
func privateShow(pod *model.Podcast, mark string, markErr error) bool {
	return pod.AuthUser != "" || markErr != nil || mark != ""
}

// secretParams are the query parameters, by name in any case, that carry
// a credential in a feed's address.
var secretParams = []string{"auth", "token", "key", "secret", "sig", "signature",
	"password", "pass", "apikey", "api_key", "access_token"}

// addressCarriesSecret reports whether a feed address carries a
// credential: user info, or a query parameter named like one, split on
// either separator a host may read.
func addressCarriesSecret(raw string) bool {
	u, err := url.Parse(raw)
	if err != nil {
		return false
	}
	if u.User != nil {
		return true
	}
	for _, pair := range strings.FieldsFunc(u.RawQuery, func(r rune) bool { return r == '&' || r == ';' }) {
		name, _, _ := strings.Cut(pair, "=")
		if plain, err := url.QueryUnescape(name); err == nil {
			name = plain
		}
		if slices.Contains(secretParams, strings.ToLower(name)) {
			return true
		}
	}
	return false
}

// showIsPrivate reads the show's mark and applies privateShow.
func (l *Podcasts) showIsPrivate(ctx context.Context, pod *model.Podcast) bool {
	mark, err := l.db.SyncStateGet(ctx, syncKeyShowPrivate+string(pod.PID))
	if err != nil {
		l.log.Warn("reading show privacy", "show", string(pod.PID), "err", err)
	}
	return privateShow(pod, mark, err)
}

// markShowPrivate makes a show sticky-private.
func (l *Podcasts) markShowPrivate(ctx context.Context, showPID string) {
	if err := l.db.SyncStateSet(ctx, syncKeyShowPrivate+showPID, "1"); err != nil {
		l.log.Warn("marking show private", "show", showPID, "err", err)
	}
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

// subscribedEpisodeScope is the item query for "episodes of the shows
// this caller follows, that this caller may see".
//
// The show set rides one `in` predicate, which seeks the same index `is`
// does at every arity including one, so a thousand-feed importer costs
// what ten do; past the engine's cap on one set it is chunked (inSet). An
// empty set compiles to `1=0` - the right answer for a caller with no
// subscriptions, and the reason this needs no guard above it. showPIDs is
// sorted so one caller's scope compiles to a stable string, which keeps a
// cursor issued under it meaningful.
func subscribedEpisodeScope(uc *UserCtx, showPIDs []string) *query.Builder {
	q := visibleItems().
		Where("kind", query.OpIs, string(model.KindEpisode)).
		WhereNode(inSet("podcast_pid", showPIDs))
	if !uc.Explicit {
		q = q.Where("explicit", query.OpIs, 0).
			Where("podcast_explicit", query.OpIs, 0)
	}
	return q
}

// SubscribedEpisodes pages episodes across every show the caller
// follows.
//
// Ordering follows the filter, because the two questions want different
// orders: what is new is newest-published first, and what to pick up
// again is most-recently-progressed first. Both are keyset browses of
// the catalog over the same subscription scope. The second used to rank
// in Go, because no list could define its order - a checkpoint stamps no
// last_played_at - and the catalog now stamps last_progress_at on every
// progress write, which is what `in-progress` browses.
func (l *Podcasts) SubscribedEpisodes(
	ctx context.Context,
	uc *UserCtx,
	filter SubscribedEpisodeFilter,
	cursor string,
	limit int,
) ([]EpisodeSummary, string, error) {
	if !filter.Valid() {
		return nil, "", errInvalid("unknown filter " + string(filter))
	}
	if !l.Grants.podcastsVisible(ctx, uc) {
		return []EpisodeSummary{}, "", nil
	}
	// Before the reads, so a cursor from another filter is refused at the
	// same cost whatever the caller follows.
	payload := ""
	if cursor != "" {
		issued, rest, ok := decodeFilteredCursor(cursor)
		if !ok {
			return nil, "", errInvalid("malformed cursor")
		}
		if issued != filter {
			return nil, "", errInvalid(
				"cursor was issued for filter " + string(issued) +
					" and cannot be used with " + string(filter))
		}
		payload = rest
	}
	rows, err := l.db.SubscriptionsByUser(ctx, uc.ID)
	if err != nil {
		return nil, "", &Error{Kind: KindInternal, Err: err}
	}
	if len(rows) == 0 {
		// An empty `in` set compiles to 1=0, which is already the right
		// answer; saying so here keeps a follower of no shows from
		// compiling a query at all.
		return []EpisodeSummary{}, "", nil
	}
	showPIDs := make([]string, 0, len(rows))
	for _, row := range rows {
		showPIDs = append(showPIDs, row.ShowPID)
	}
	sort.Strings(showPIDs)
	scope := subscribedEpisodeScope(uc, showPIDs)

	// The list carries the ordering and, for in-progress, the membership
	// too (a resume position on an unfinished item); the scope carries
	// who may see what.
	list := read.ListRecentEpisodes
	switch filter {
	case EpisodesInProgress:
		list = read.ListInProgress
	case EpisodesUnplayed:
		// Never started, matching countShow's badge and the episode row's
		// own dot: a first checkpoint moves an episode out of this shelf
		// and into the in-progress one, rather than sitting in both.
		scope = scope.Where("played", query.OpIs, 0).
			Where("position_ms", query.OpIs, 0)
	}
	page, err := l.lib.Browse(ctx, list, read.BrowseOptions{
		UserPID: model.PID(uc.CatalogPID),
		Cursor:  read.Cursor(payload),
		Limit:   limit,
		Query:   scope.Build(),
	})
	if err != nil {
		return nil, "", classify(err)
	}
	out, err := l.episodeRows(ctx, page.Items)
	if err != nil {
		return nil, "", err
	}
	next := ""
	if page.HasMore {
		next = encodeFilteredCursor(filter, string(page.Next))
	}
	return out, next, nil
}

// episodeRows turns a cut page of item views into episode summaries.
//
// The page is hydrated after the cut, never before it: an item view
// cannot fill an EpisodeSummary (show title, enclosure, transcript), so
// the episodes are read for the rows returned, in one catalog read, and
// their fetch states in one more.
//
// Only a vanished episode is skipped. Anything else fails the read,
// because the two look identical to a client and are not: a row removed
// between the query and the hydration is a short page and correct, while
// a transient store failure silently dropping rows is a page that looks
// complete and is not.
func (l *Podcasts) episodeRows(ctx context.Context, items []*model.ItemView) ([]EpisodeSummary, error) {
	batch, err := l.episodeBatchFor(ctx, items)
	if err != nil {
		return nil, err
	}
	out := make([]EpisodeSummary, 0, len(items))
	for _, it := range items {
		if ep := batch.eps[it.PID]; ep != nil {
			out = append(out, l.episodeSummary(ctx, ep, batch.facts))
		}
	}
	return out, nil
}

// episodeBatch is one page's episodes, read together, with what their
// rows report beyond the catalog's episode.
type episodeBatch struct {
	eps   map[model.PID]*model.Episode
	facts episodeFacts
}

// episodeBatchFor reads the episodes behind a page of item views: one
// catalog read for them all, and one fetch-queue read. Views of other
// kinds are passed over, and a pid that is no longer an episode is
// absent from the answer.
func (l *Podcasts) episodeBatchFor(ctx context.Context, views []*model.ItemView) (episodeBatch, error) {
	var pids []model.PID
	for _, it := range views {
		if it.Kind == model.KindEpisode {
			pids = append(pids, it.PID)
		}
	}
	if len(pids) == 0 {
		return episodeBatch{}, nil
	}
	eps, err := l.episodesByPIDs(ctx, pids)
	if err != nil {
		return episodeBatch{}, err
	}
	out := episodeBatch{eps: make(map[model.PID]*model.Episode, len(eps))}
	for _, ep := range eps {
		out.eps[ep.PID] = ep
	}
	byPID := make(map[model.PID]*model.ItemView, len(views))
	for _, it := range views {
		byPID[it.PID] = it
	}
	out.facts = l.readEpisodeFacts(ctx, eps, byPID)
	return out, nil
}

// episodeFacts is what an episode row reports from outside the episode
// itself, read for a whole page at once: the fetch queue's word on the
// episodes not on the server, and the stored container of those that
// are.
type episodeFacts struct {
	fetches    map[string]wdb.FetchAttempts
	containers map[model.PID]string
}

// readEpisodeFacts reads the facts for a page of episodes. views are the
// page's item views where the caller holds them; the fetched episodes it
// does not hold are read in one more catalog read. A failed read leaves
// its rows without the fact rather than failing the page, which is what
// one row's failed read always did.
func (l *Podcasts) readEpisodeFacts(ctx context.Context, eps []*model.Episode, views map[model.PID]*model.ItemView) episodeFacts {
	facts := episodeFacts{containers: map[model.PID]string{}}
	var waiting []string
	var unread []model.PID
	for _, ep := range eps {
		switch {
		case !ep.Downloaded:
			waiting = append(waiting, string(ep.PID))
		case views[ep.PID] != nil:
			facts.containers[ep.PID] = views[ep.PID].Container
		default:
			unread = append(unread, ep.PID)
		}
	}
	if len(unread) > 0 {
		if got, err := l.lib.GetMany(ctx, unread); err != nil {
			l.log.Warn("reading fetched episodes' formats", "err", err)
		} else {
			for _, it := range got {
				facts.containers[it.PID] = it.Container
			}
		}
	}
	if len(waiting) > 0 {
		fetches, err := l.db.FetchQueueRows(ctx, waiting)
		if err != nil {
			l.log.Warn("reading episode fetch states", "err", err)
		}
		facts.fetches = fetches
	}
	return facts
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
// refusal rather than a wrong page: the filters interleave differently,
// and a keyset search under the wrong one lands somewhere plausible and
// wrong.
//
// The payload is the catalog's own keyset cursor for all three filters
// now, which is why the tag carries the version: pe1 meant a hand-rolled
// `key|pid` ranking for in-progress, and feeding one to Browse would
// land somewhere plausible and wrong. The tag is this family's alone;
// reads.go's scoped envelope owns s1.
func encodeFilteredCursor(filter SubscribedEpisodeFilter, payload string) string {
	return encodeOpaqueCursor(fmt.Sprintf("pe2|%s|%s", filter, payload))
}

func decodeFilteredCursor(s string) (filter SubscribedEpisodeFilter, payload string, ok bool) {
	raw, ok := decodeOpaqueCursor(s)
	if !ok {
		return "", "", false
	}
	parts := strings.SplitN(raw, "|", 3)
	// pe2: the in-progress payload was a hand-rolled key|pid ranking and is
	// the catalog's browse keyset now, so a pe1 cursor mid-scroll across a
	// deploy has to 400 rather than be fed to Browse as a keyset.
	if len(parts) != 3 || parts[0] != "pe2" {
		return "", "", false
	}
	return SubscribedEpisodeFilter(parts[1]), parts[2], true
}

// episodeSummary builds the episode list row from the catalog episode
// and the facts its page read beside it.
func (l *Podcasts) episodeSummary(ctx context.Context, ep *model.Episode, facts episodeFacts) EpisodeSummary {
	// Feeds without pubDate still need a total order; first-seen time
	// is stable and monotone enough for paging.
	pub := episodePublishedNS(ep)
	out := EpisodeSummary{
		ItemSummary: ItemSummary{
			PID:        apiPID(PrefixEpisode, ep.PID),
			MediaType:  "podcast",
			Title:      clipFeedTitle(ep.Title),
			Artist:     clipFeedTitle(ep.PodcastTitle),
			Album:      clipFeedTitle(ep.PodcastTitle),
			SortKey:    model.SortKey(ep.Title),
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
		notes:       ep.Description,
	}
	// A show whose source cannot be read relays nothing, here as at the
	// relay, so no row promises audio the relay would then refuse.
	source, known := l.showSourceType(ctx, ep.PodcastPID)
	out.HasEnclosure = known && relayableEnclosure(source, ep.EnclosureURL, ep.EnclosureType)
	if row, ok := facts.fetches[string(ep.PID)]; ok && !ep.Downloaded {
		if row.Attempts >= fetchMaxAttempts {
			out.FetchState, out.FetchError = "failed", row.LastError
		} else {
			out.FetchState = "queued"
		}
	}
	out.Container, out.MimeType = episodeFormat(ep, facts.containers[ep.PID])
	return out
}
