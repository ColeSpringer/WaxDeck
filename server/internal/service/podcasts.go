package service

import (
	"cmp"
	"context"
	"net/http"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/colespringer/waxbin/model"

	"github.com/colespringer/waxdeck/server/internal/providers"
)

// Podcasts is podcasts: subscriptions, episodes and their downloads,
// gpodder sync, OPML, transcripts, chapters, podping and the directory.
type Podcasts struct {
	*core
	// podcastDir locates the episode download library;
	// defaultRetentionKeep is the unset-subscriber policy;
	// retentionInUseWindow gates the sweep's in-use deferral.
	podcastDir           string
	defaultRetentionKeep int64
	retentionInUseWindow time.Duration
	// membershipLocks serializes changes to who follows which show, per
	// account; see lockMembership.
	membershipLocks [playedStripes]sync.Mutex
	// showHolds keep a download from landing in a show while its
	// retention sweep runs; see showHold.
	showHolds [playedStripes]sync.Mutex
	// gpodderDownloads is what gpodder episodes downloads answered lately,
	// which an episodes upload answers no later than.
	gpodderDownloads gpodderDownloads
	// transcriptHTTP is the guarded client for transcript pointers,
	// built on first use; allowPrivateFeedHosts relaxes its SSRF guard.
	transcriptHTTP        *http.Client
	transcriptHTTPOnce    sync.Once
	allowPrivateFeedHosts bool
	// transcriptCacheBytes overrides transcriptCacheMaxBytes when set
	// (tests).
	transcriptCacheBytes int64
	// chapterDocs keeps what episodes' chapters documents read for display.
	chapterDocs chaptersCache
	// enclosureHTTP is the guarded client the podcast enclosure
	// passthrough relays through, built on first use and sharing
	// allowPrivateFeedHosts with transcript fetches. It carries no
	// overall timeout: an episode relay lasts as long as the listening
	// session, so the request context is its only bound.
	enclosureHTTP     *http.Client
	enclosureHTTPOnce sync.Once
	// showSources remembers each show's source type; see showSourceType.
	showSources sync.Map
	// episodeReadHook stands in for the catalog's episode read by pids in
	// a test; nothing in the server sets it.
	episodeReadHook func(context.Context, []model.PID) ([]*model.Episode, error)
	// showReadHook stands in for readShow's catalog read in a test;
	// nothing in the server sets it.
	showReadHook func(context.Context, model.PID) (*model.Podcast, error)
	// listenerReadHook stands in for Podcasts.listeners' read of a
	// subscriber's account in a test; nothing in the server sets it.
	listenerReadHook func(context.Context, string) (*UserCtx, error)
	// retentionStatesHook stands in for the retention sweep's read of
	// its candidates' play states in a test; nothing in the server sets
	// it.
	retentionStatesHook func(context.Context, []model.PID) (map[model.PID][]model.PlayState, error)
	// pinHook stands in for the catalog write that pins or unpins an
	// episode in a test; nothing in the server sets it.
	pinHook func(context.Context, model.PID, *model.Episode, bool) error
	// secretReadHook stands in for the catalog's read of a show's stored
	// feed password in a test; nothing in the server sets it.
	secretReadHook func(context.Context, string) (string, error)
	// podcastDirectory answers show name searches, built on first use
	// so an install that never searches never allocates its cache.
	podcastDirectoryBase string
	podcastDirectory     *providers.PodcastDirectory
	podcastDirectoryOnce sync.Once
	// podping holds the feed-URL index a chain notification resolves
	// against, and the per-show floor between two podping-driven syncs.
	podping podpingIndex
}

func newPodcasts(c *core, cfg Config) *Podcasts {
	return &Podcasts{
		core:                  c,
		podcastDir:            cfg.PodcastDir,
		defaultRetentionKeep:  cfg.DefaultRetentionKeep,
		retentionInUseWindow:  cmp.Or(cfg.RetentionInUseWindow, 2*time.Minute),
		allowPrivateFeedHosts: cfg.AllowPrivateFeedHosts,
		podcastDirectoryBase:  cfg.PodcastDirectoryBase,
	}
}

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

	// notes is the feed's own description, unsanitized, read only through
	// DescriptionText: the sanitized form escapes what markup it drops.
	notes string
}

// DescriptionText is the show's description as plain text, for a surface
// that carries no markup.
func (s PodcastShow) DescriptionText() string { return feedPlainText(s.notes) }

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
	// Withheld is a subscription to a show the caller may not hear now
	// (showWithheld): its episodes and its detail answer not found, and
	// the row stays for the day that changes.
	Withheld bool
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

	// notes is the feed's own description, unsanitized, read only through
	// DescriptionText: reduced when asked, since most surfaces never ask.
	notes string
}

// DescriptionText is the episode's description as plain text, for a
// surface that carries no markup.
func (e EpisodeSummary) DescriptionText() string { return feedPlainText(e.notes) }

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
