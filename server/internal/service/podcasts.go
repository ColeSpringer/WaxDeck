package service

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"errors"
	"fmt"
	"hash/fnv"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/url"
	"regexp"
	"slices"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/podcast"
	"github.com/colespringer/waxbin/query"
	"github.com/colespringer/waxbin/read"
	"github.com/colespringer/waxbin/waxerr"
	waxtap "github.com/colespringer/waxtap/v3"

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
	// FeedURL is the address the caller follows the show by; for anyone
	// else it is the catalog's, and empty for a private show: the
	// emptiness is the privacy rule, not missing data.
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
	// ArtSource says where the show's cover came from - the feed, or a
	// hand-set replacement. Detail reads only, beside Persons: a
	// subscription row draws no caption.
	ArtSource ArtSourceDTO
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
	// Container and MimeType are the format a client should expect: the
	// fetched file's, or the type the feed declared (held to the relay's
	// rule) and the container that type names. Empty when neither is
	// known.
	Container string
	MimeType  string
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

// OpmlImportEntry is one feed's import outcome. Err is a sentence for a
// person, and Reason the feed-side failure's reason when it was one.
type OpmlImportEntry struct {
	FeedURL string
	Title   string
	PID     string
	Err     string
	Reason  string
}

// lockMembership serializes one account's changes to who follows which
// show, the state and the change log together, so neither a change nor
// its event can land inside another and the log keeps their order.
func (l *Library) lockMembership(userID string) func() {
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

// requirePodcastsOn refuses a subscribe for good on a server whose
// podcast directory is off: it keeps no podcasts, so it follows none and
// fetches no feed.
func (l *Library) requirePodcastsOn() error {
	if l.podcastDir == "" {
		return &Error{Kind: KindFeature, Msg: ErrPodcastsOff.Error(), Err: ErrPodcastsOff}
	}
	return nil
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
	if err := l.requirePodcastsOn(); err != nil {
		return Subscription{}, false, err
	}
	// Following a show is for hearing it, and the podcast library is what
	// an account is granted to hear podcasts by.
	if !l.podcastsVisible(ctx, uc) {
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
func (l *Library) attachSubscription(ctx context.Context, uc *UserCtx, pod *model.Podcast, req SubscribeRequest, meta subChangeMeta) (Subscription, bool, error) {
	if pod.Explicit && !uc.Explicit {
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
func (l *Library) Unsubscribe(ctx context.Context, uc *UserCtx, apiShowPID string, removeDownloads bool) error {
	if err := requirePodcastManagement(uc); err != nil {
		return err
	}
	if !l.podcastsVisible(ctx, uc) {
		return errNotFound("no show with pid " + apiShowPID)
	}
	return l.unsubscribe(ctx, uc, apiShowPID, removeDownloads, subChangeMeta{})
}

func (l *Library) unsubscribe(ctx context.Context, uc *UserCtx, apiShowPID string, removeDownloads bool, meta subChangeMeta) error {
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
func (l *Library) afterSubscriptionChange(ctx context.Context, uc *UserCtx, showPID, feedURL, action string, meta subChangeMeta) {
	ctx = context.WithoutCancel(ctx)
	l.emitUserEvent(ctx, uc.ID, eventSubscription, showPID)
	l.bumpGrantEpoch(ctx, uc.ID)
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
func (l *Library) Subscriptions(ctx context.Context, uc *UserCtx, cursor string, limit int, withCounts bool) ([]Subscription, string, error) {
	// An account that cannot see the podcast library follows nothing it
	// can see; its rows stay for the day it can again.
	if !l.podcastsVisible(ctx, uc) {
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
func (l *Library) countShow(
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
// PodcastDetailFor's 404: a feed can mark itself explicit at the channel
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
func (l *Library) newestVisibleEpisodeNS(ctx context.Context, uc *UserCtx, pod *model.Podcast) (int64, error) {
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
func (l *Library) PutSubscriptionSettings(ctx context.Context, uc *UserCtx, apiShowPID string, s SubscriptionSettings) (Subscription, error) {
	pod, err := l.getShow(ctx, apiShowPID)
	if err != nil {
		return Subscription{}, err
	}
	if !l.podcastsVisible(ctx, uc) {
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
func (l *Library) EpisodeDetailFor(ctx context.Context, uc *UserCtx, apiEpisodePID string) (EpisodeDetail, error) {
	det, err := l.getEpisode(ctx, apiEpisodePID)
	if err != nil {
		return EpisodeDetail{}, err
	}
	if !l.podcastsVisible(ctx, uc) {
		return EpisodeDetail{}, errNotFound("no episode with pid " + apiEpisodePID)
	}
	// The show's flag as well as the episode's: reaching an episode by
	// its own pid is the one path that does not pass its show, so this
	// is where the two would otherwise disagree.
	if !l.episodeAllowed(ctx, uc, det.Episode) {
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
func (l *Library) EpisodeSummaryFor(ctx context.Context, uc *UserCtx, apiEpisodePID string) (EpisodeSummary, bool, error) {
	det, err := l.getEpisode(ctx, apiEpisodePID)
	if err != nil {
		return EpisodeSummary{}, false, err
	}
	if !l.podcastsVisible(ctx, uc) {
		return EpisodeSummary{}, false, errNotFound("no episode with pid " + apiEpisodePID)
	}
	ep := det.Episode
	if !l.episodeAllowed(ctx, uc, ep) {
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
func (l *Library) RefreshPodcast(ctx context.Context, uc *UserCtx, apiShowPID string) (int, error) {
	if err := requirePodcastManagement(uc); err != nil {
		return 0, err
	}
	pod, err := l.getShow(ctx, apiShowPID)
	if err != nil {
		return 0, err
	}
	if !l.podcastsVisible(ctx, uc) {
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
func (l *Library) checkPodcastWritable(ctx context.Context) error {
	return l.CheckWritable(ctx, "")
}

// QueueEpisodeFetch queues a server-side enclosure download. The
// caller must be subscribed to the show; an episode already here is
// fetched no further, only held for the caller as a landing holds it.
func (l *Library) QueueEpisodeFetch(ctx context.Context, uc *UserCtx, apiEpisodePID string) error {
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
	if !l.podcastsVisible(ctx, uc) {
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
func (l *Library) RemoveEpisodeDownload(ctx context.Context, uc *UserCtx, apiEpisodePID string) error {
	if err := requirePodcastManagement(uc); err != nil {
		return err
	}
	det, err := l.getEpisode(ctx, apiEpisodePID)
	if err != nil {
		return err
	}
	if !l.podcastsVisible(ctx, uc) {
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

// --- internals ---------------------------------------------------------------

// subscribedShowSet loads the caller's subscribed show set (bare
// pids). Subscriptions are per-user views, so this set is what scopes
// episodes in listings, browse, search, and catalog sync.
func (l *Library) subscribedShowSet(ctx context.Context, uc *UserCtx) (map[string]bool, error) {
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
	return f.allowsEpisode(ctx, l, it)
}

// allowsEpisode reports whether the caller subscribes to the episode's
// show. The view projects the show handle, so this costs no reads.
func (f *subscriptionFilter) allowsEpisode(ctx context.Context, l *Library, it *model.ItemView) bool {
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
func (f *subscriptionFilter) allowsEpisodePID(ctx context.Context, l *Library, episodePID model.PID) bool {
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
func (f *subscriptionFilter) followsAny(ctx context.Context, l *Library) bool {
	f.ensure(ctx, l)
	return !f.failed && len(f.set) > 0
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
		noteDegraded(ctx)
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

// episodesByPIDs reads episodes by bare pid in one catalog read, in
// request order and each once, leaving out a pid that is no episode.
func (l *Library) episodesByPIDs(ctx context.Context, pids []model.PID) ([]*model.Episode, error) {
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
func (l *Library) subscriptionFor(ctx context.Context, uc *UserCtx, pod *model.Podcast) (Subscription, error) {
	row, err := l.db.SubscriptionFor(ctx, uc.ID, string(pod.PID))
	if err != nil {
		return Subscription{}, &Error{Kind: KindInternal, Err: err}
	}
	return l.subscriptionRow(ctx, uc, pod, row)
}

func (l *Library) subscriptionRow(ctx context.Context, uc *UserCtx, pod *model.Podcast, row wdb.Subscription) (Subscription, error) {
	show, err := l.showDTO(ctx, uc, pod, false, row.FeedURL)
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
// and newest publication time (detail surfaces only), counted through
// uc's view of the show; uc is consulted for nothing else. own is the
// address uc follows the show by, "" when it does not follow it: a
// follower is shown its own address, never the one the catalog took up
// from the last account to add the show.
func (l *Library) showDTO(ctx context.Context, uc *UserCtx, pod *model.Podcast, withCounts bool, own string) (PodcastShow, error) {
	out := PodcastShow{
		PID:             apiPID(PrefixPodcast, pod.PID),
		Title:           clipFeedTitle(pod.Title),
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
		out.ArtSource = l.artSourceForRef(ctx, model.EntityRef{Type: model.ArtPodcast, PID: pod.PID})
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
func (l *Library) showIsPrivate(ctx context.Context, pod *model.Podcast) bool {
	mark, err := l.db.SyncStateGet(ctx, syncKeyShowPrivate+string(pod.PID))
	if err != nil {
		l.log.Warn("reading show privacy", "show", string(pod.PID), "err", err)
	}
	return privateShow(pod, mark, err)
}

// markShowPrivate makes a show sticky-private.
func (l *Library) markShowPrivate(ctx context.Context, showPID string) {
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
func (l *Library) episodeRows(ctx context.Context, items []*model.ItemView) ([]EpisodeSummary, error) {
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
func (l *Library) episodeBatchFor(ctx context.Context, views []*model.ItemView) (episodeBatch, error) {
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
func (l *Library) readEpisodeFacts(ctx context.Context, eps []*model.Episode, views map[model.PID]*model.ItemView) episodeFacts {
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
func (l *Library) episodeSummary(ctx context.Context, ep *model.Episode, facts episodeFacts) EpisodeSummary {
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

// classifyFeedErr maps a subscribe failure onto the API error model. A
// feed the server will not take (not a feed, too large, on a private
// network) is the caller's address to change and refused as invalid; the
// host's own failure is unreachable. Either way the error says why in a
// sentence of its own and carries the reason. The rest answer by kind.
func (l *Library) classifyFeedErr(ctx context.Context, err error) error {
	if !feedAtFault(ctx, err) {
		return classify(err)
	}
	reason, sentence := feedFailureReason(err)
	switch reason {
	case reasonNotAFeed, reasonTooLarge, reasonBlockedAddress:
		return &Error{Kind: KindInvalid, Msg: sentence, Err: &feedFault{reason: reason, err: err}}
	}
	return feedUnreachable(err)
}

// logFeedFailure logs a feed-side failure by its host, reason and cause,
// and never the URL or the error: a feed URL can be its own credential,
// and the error's text repeats it.
func (l *Library) logFeedFailure(msg, rawURL, reason string, err error) {
	l.logFeedFailureAt(slog.LevelInfo, msg, rawURL, reason, err)
}

// logFeedFailureAt is logFeedFailure at the level the caller chooses.
func (l *Library) logFeedFailureAt(level slog.Level, msg, rawURL, reason string, err error) {
	host := ""
	if u, perr := url.Parse(rawURL); perr == nil {
		host = u.Hostname()
	}
	l.log.Log(context.Background(), level, msg, "host", host, "reason", reason, "cause", feedCause(err))
}

// feedCause names what a feed-side failure was in words that carry no
// URL, for the log: the host's status, or the kind of network failure.
func feedCause(err error) string {
	if err == nil {
		return ""
	}
	msg := err.Error()
	var (
		status      *hostStatusError
		netErr      net.Error
		dnsErr      *net.DNSError
		opErr       *net.OpError
		urlErr      *url.Error
		verifyErr   *tls.CertificateVerificationError
		unknownAuth x509.UnknownAuthorityError
		badHost     x509.HostnameError
		badCert     x509.CertificateInvalidError
		badRecord   tls.RecordHeaderError
	)
	if errors.As(err, &status) {
		return "status " + strconv.Itoa(status.status)
	}
	if m := httpStatusFragment.FindStringSubmatch(msg); m != nil {
		return "status " + m[1]
	}
	switch {
	case errors.Is(err, errPrivateAddress), strings.Contains(msg, "non-public address"):
		return "non-public address"
	case errors.Is(err, errTranscriptTooLarge), byteLimitFragment.MatchString(msg):
		return "size limit"
	case redirectFragment.MatchString(msg):
		return "redirects"
	case errors.Is(err, context.DeadlineExceeded), errors.As(err, &netErr) && netErr.Timeout():
		return "timeout"
	case errors.As(err, &dnsErr):
		return "dns"
	case errors.As(err, &verifyErr), errors.As(err, &unknownAuth), errors.As(err, &badHost),
		errors.As(err, &badCert), errors.As(err, &badRecord):
		return "tls"
	case errors.As(err, &opErr) && opErr.Op == "dial":
		return "dial"
	case errors.Is(err, io.ErrUnexpectedEOF), errors.Is(err, io.EOF):
		return "connection closed"
	case errors.As(err, &opErr):
		return opErr.Op
	case errors.As(err, &urlErr) && urlErr.Op == "parse":
		return "address"
	}
	if code := waxerr.CodeOf(err); code != "" {
		return string(code)
	}
	return "error"
}

// feedUnreachable reports a feed's own failure. Its sentence names neither
// the URL nor anything the host said; the log keeps the reason and a
// cause without the URL (feedCause), never the error itself.
func feedUnreachable(err error) error {
	reason, sentence := feedFailureReason(err)
	return &Error{Kind: KindUpstream, Msg: sentence, Err: &feedFault{reason: reason, err: err}}
}

// The reasons a feed-side fetch fails for: a closed set, so a client can
// word each one itself.
const (
	reasonNotAFeed       = "not-a-feed"
	reasonTooLarge       = "too-large"
	reasonBlockedAddress = "blocked-address"
	reasonHostRefused    = "host-refused"
	reasonHostMissing    = "host-missing"
	reasonHostError      = "host-error"
	reasonUnreachable    = "unreachable"
)

// feedSentences is what the API says for each reason about a feed.
var feedSentences = map[string]string{
	reasonNotAFeed:       "That address did not return a podcast feed.",
	reasonTooLarge:       "That feed is larger than this server accepts (16 MiB).",
	reasonBlockedAddress: "This server does not fetch feeds from private or local network addresses.",
	reasonHostRefused:    "The feed's host refused the request; it may need a login.",
	reasonHostMissing:    "No feed was found at that address.",
	reasonHostError:      "The feed's host answered with an error.",
	reasonUnreachable:    "The feed's host could not be reached.",
}

// transcriptSentences is the same for an episode's transcript, which is
// another document from another address, with a cap of its own.
var transcriptSentences = map[string]string{
	reasonNotAFeed:       "The transcript's address did not return a transcript.",
	reasonTooLarge:       "That transcript is larger than this server accepts.",
	reasonBlockedAddress: "This server does not fetch transcripts from private or local network addresses.",
	reasonHostRefused:    "The transcript's host refused the request; it may need a login.",
	reasonHostMissing:    "No transcript was found at the address the feed gives.",
	reasonHostError:      "The transcript's host answered with an error.",
	reasonUnreachable:    "The transcript's host could not be reached.",
}

// downloadSentences is the same for an episode's audio, which the fetch
// queue keeps for the episode's listing to show.
var downloadSentences = map[string]string{
	reasonNotAFeed:       "The episode's address did not return audio.",
	reasonTooLarge:       "The episode is larger than this server downloads.",
	reasonBlockedAddress: "This server does not download from private or local network addresses.",
	reasonHostRefused:    "The episode's host refused the download; it may need a login.",
	reasonHostMissing:    "The episode's host has no audio at that address anymore.",
	reasonHostError:      "The episode's host answered with an error.",
	reasonUnreachable:    "The episode's host could not be reached.",
}

// feedFault carries a feed-side failure's reason inside the service error,
// for the API to put in the body's params.
type feedFault struct {
	reason string
	err    error
}

func (f *feedFault) Error() string {
	if f.err == nil {
		return "feed-side failure: " + f.reason
	}
	return f.err.Error()
}

func (f *feedFault) Unwrap() error { return f.err }

// FeedFailureReason is the reason a feed-side failure carries, "" for any
// other error.
func FeedFailureReason(err error) string {
	var f *feedFault
	if errors.As(err, &f) {
		return f.reason
	}
	return ""
}

// feedReasonPermanent reports whether asking again can change the answer:
// a host's error or a host out of reach can pass, the rest answer the same
// until somebody changes the address or the server.
func feedReasonPermanent(reason string) bool {
	return reason != reasonHostError && reason != reasonUnreachable
}

// WaxBin's feed client words these failures without a type to test (its
// netsafe package is internal), so they are read off its messages, which
// feedfailure_test.go pins against the real client.
var (
	httpStatusFragment = regexp.MustCompile(`returned HTTP (\d{3})`)
	byteLimitFragment  = regexp.MustCompile(`exceeds \d+-byte limit`)
	redirectFragment   = regexp.MustCompile(`stopped after \d+ redirects|too many redirects`)
)

// feedFailureReason says why a feed-side fetch failed, and in what words,
// for an error feedAtFault holds to be the feed's.
func feedFailureReason(err error) (reason, sentence string) {
	reason = feedReason(err)
	return reason, feedSentences[reason]
}

func feedReason(err error) string {
	msg := err.Error()
	var status *hostStatusError
	switch {
	case errors.Is(err, errPrivateAddress), strings.Contains(msg, "non-public address"):
		return reasonBlockedAddress
	case errors.Is(err, errTranscriptTooLarge), byteLimitFragment.MatchString(msg):
		return reasonTooLarge
	case errors.As(err, &status):
		return statusReason(status.status)
	}
	if m := httpStatusFragment.FindStringSubmatch(msg); m != nil {
		code, _ := strconv.Atoi(m[1])
		return statusReason(code)
	}
	if reason, ok := tapReason(err); ok {
		return reason
	}
	var (
		syntax  *json.SyntaxError
		mistype *json.UnmarshalTypeError
		urlErr  *url.Error
		netErr  net.Error
	)
	switch {
	case waxerr.CodeOf(err) == waxerr.CodeNotFound:
		return reasonHostMissing
	case waxerr.CodeOf(err) == waxerr.CodeInvalid, waxerr.CodeOf(err) == waxerr.CodeUnsupported,
		errors.As(err, &syntax), errors.As(err, &mistype):
		return reasonNotAFeed
	case redirectFragment.MatchString(msg):
		return reasonHostError
	case errors.As(err, &urlErr) && (urlErr.Op == "parse" || strings.Contains(urlErr.Err.Error(), "unsupported protocol scheme")):
		// An address the client cannot even ask is wrong as written, and
		// no try later can reach it.
		return reasonNotAFeed
	case errors.As(err, &urlErr), errors.As(err, &netErr), errors.Is(err, io.ErrUnexpectedEOF):
		return reasonUnreachable
	}
	return reasonHostError
}

// tapReason reads a YouTube source's failure by the cause WaxTap names,
// which the provider's and the catalog's wraps keep. The rest of what it
// can say (a throttle, a page shape its parser does not know) is the
// host's trouble and left to pass.
func tapReason(err error) (string, bool) {
	var status *waxtap.HTTPStatusError
	switch {
	case errors.As(err, &status):
		return statusReason(status.StatusCode), true
	case errors.Is(err, waxtap.ErrPlaylistUnavailable):
		return reasonHostMissing, true
	case errors.Is(err, waxtap.ErrUnsupportedInput), errors.Is(err, waxtap.ErrInvalidPlaylistID),
		errors.Is(err, waxtap.ErrInvalidVideoID), errors.Is(err, waxtap.ErrVideoIDTooShort),
		errors.Is(err, waxtap.ErrVideoIDTooLong), errors.Is(err, waxtap.ErrPlaylistEmpty):
		return reasonNotAFeed, true
	case errors.Is(err, waxtap.ErrLoginRequired), errors.Is(err, waxtap.ErrMembersOnly),
		errors.Is(err, waxtap.ErrAgeRestricted), errors.Is(err, waxtap.ErrGeoBlocked),
		errors.Is(err, waxtap.ErrVideoRestricted):
		return reasonHostRefused, true
	}
	return "", false
}

// statusReason reads a host's HTTP answer: gone, refused, or an error of
// its own, which is the one a later try can find mended.
func statusReason(status int) string {
	switch {
	case status == http.StatusNotFound, status == http.StatusGone:
		return reasonHostMissing
	case status == http.StatusRequestTimeout, status == http.StatusTooEarly,
		status == http.StatusTooManyRequests, status >= 500:
		return reasonHostError
	case status >= 400:
		return reasonHostRefused
	}
	return reasonHostError
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
