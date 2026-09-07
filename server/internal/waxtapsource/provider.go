// Package waxtapsource implements WaxBin's source.Provider over WaxTap, so a
// YouTube channel or playlist can be subscribed and synced like a podcast feed.
// Enumerate maps a channel/playlist listing to a model.Feed, Fetch downloads one
// video's audio through WaxTap, and Resolve is the cheap identity probe. The
// provider is injected into WaxBin via waxbin.Options.SourceProviders; nothing in
// this package touches WaxBin's store directly.
package waxtapsource

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"strings"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/source"
	waxtap "github.com/colespringer/waxtap/v3"
)

// enrichLimit caps the per-video metadata lookups made during one enumeration.
// Full metadata costs two fetches per video, so only the newest new entries are
// enriched; older entries keep the basic listing fields.
const enrichLimit = 25

// defaultMaxItems caps one enumeration when Config.MaxItems is zero.
const defaultMaxItems = 200

// Config configures a Provider.
type Config struct {
	// WorkDir is the scratch directory for in-flight downloads before they are
	// streamed to the caller. Required; created if absent.
	WorkDir string

	// SealBaseURL, when set, points at a WaxSeal-style sidecar that mints PO
	// tokens and attested player contexts. The provider then forces WaxTap's
	// "web" client so streams run under the attested session. SealAPIKey is the
	// optional X-API-Key header value for that sidecar.
	SealBaseURL string
	SealAPIKey  string

	// SponsorBlock lists SponsorBlock category names (such as "sponsor",
	// "selfpromo") to cut from downloaded audio. Empty disables cutting.
	SponsorBlock []string

	// EmbedThumbnail and EmbedMetadata ask WaxTap to embed the video thumbnail
	// and basic tags into the downloaded file when the container supports it.
	EmbedThumbnail bool
	EmbedMetadata  bool

	// MaxItems caps the entries returned by one enumeration (0 = 200).
	MaxItems int

	// Logger receives structured logs; nil discards them.
	Logger *slog.Logger
}

// tap is the narrow slice of *waxtap.Client the provider uses. Tests inject a
// fake; New wires the real client.
type tap interface {
	Enumerate(ctx context.Context, url string, opts waxtap.EnumerateOptions) (*waxtap.Playlist, error)
	Info(ctx context.Context, url string, depth waxtap.InfoDepth, opts ...waxtap.ReadOption) (*waxtap.Video, error)
	Download(ctx context.Context, req waxtap.Request) (*waxtap.Result, error)
}

var _ tap = (*waxtap.Client)(nil)

// Provider is a WaxBin source.Provider for model.SourceYouTube. It is safe for
// concurrent use.
type Provider struct {
	tap        tap
	cfg        Config
	log        *slog.Logger
	categories []waxtap.Category // SponsorBlock cut categories; empty = no cut
}

var _ source.Provider = (*Provider)(nil)

// New builds a Provider over a real WaxTap client.
func New(cfg Config) (*Provider, error) {
	if strings.TrimSpace(cfg.WorkDir) == "" {
		return nil, errors.New("waxtapsource: Config.WorkDir is required")
	}
	if err := os.MkdirAll(cfg.WorkDir, 0o755); err != nil {
		return nil, fmt.Errorf("waxtapsource: creating work dir: %w", err)
	}
	categories, err := parseCategories(cfg.SponsorBlock)
	if err != nil {
		return nil, err
	}
	log := cfg.Logger
	if log == nil {
		log = slog.New(slog.DiscardHandler)
	}

	opts := waxtap.Options{
		Logger:  log,
		TempDir: cfg.WorkDir,
	}
	if cfg.SealBaseURL != "" {
		pot, err := waxtap.NewSidecarPOTokenProvider(cfg.SealBaseURL, waxtap.WithSidecarAPIKey(cfg.SealAPIKey))
		if err != nil {
			return nil, fmt.Errorf("waxtapsource: PO-token sidecar: %w", err)
		}
		pcp, err := waxtap.NewSidecarPlayerContextProvider(cfg.SealBaseURL, waxtap.WithSidecarAPIKey(cfg.SealAPIKey))
		if err != nil {
			return nil, fmt.Errorf("waxtapsource: player-context sidecar: %w", err)
		}
		opts.POTokenProvider = pot
		opts.PlayerContextProvider = pcp
		// The attested context and its tokens are minted for the WEB client, so
		// force a uniform web chain.
		opts.Client = "web"
	}
	client, err := waxtap.New(opts)
	if err != nil {
		return nil, fmt.Errorf("waxtapsource: waxtap client: %w", err)
	}
	return newProvider(client, cfg, log, categories), nil
}

// newProvider assembles a Provider over any tap, applying config defaults. It is
// the seam tests use to inject a fake client.
func newProvider(t tap, cfg Config, log *slog.Logger, categories []waxtap.Category) *Provider {
	if cfg.MaxItems <= 0 {
		cfg.MaxItems = defaultMaxItems
	}
	if log == nil {
		log = slog.New(slog.DiscardHandler)
	}
	return &Provider{tap: t, cfg: cfg, log: log, categories: categories}
}

// parseCategories validates SponsorBlock category names against WaxTap's
// vocabulary so a typo fails at construction, not silently at cut time.
func parseCategories(names []string) ([]waxtap.Category, error) {
	if len(names) == 0 {
		return nil, nil
	}
	out := make([]waxtap.Category, 0, len(names))
	for _, name := range names {
		c := waxtap.Category(name)
		if !c.Valid() {
			return nil, fmt.Errorf("waxtapsource: unknown SponsorBlock category %q", name)
		}
		out = append(out, c)
	}
	return out, nil
}

// SourceType reports youtube: shows with that source type are dispatched here.
func (p *Provider) SourceType() model.SourceType { return model.SourceYouTube }

// identityKey derives the stable show identity from the provider-native
// playlist id (a channel URL resolves to its uploads playlist, whose id is
// derived from the UC channel id, so it is equally stable).
func identityKey(playlistID string) string { return "youtube:" + playlistID }

// watchURL is the canonical enclosure URL for one video.
func watchURL(videoID string) string { return "https://www.youtube.com/watch?v=" + videoID }

// Resolve probes the channel/playlist identity with a one-item enumeration.
func (p *Provider) Resolve(ctx context.Context, req source.Request) (*source.Resolved, error) {
	pl, err := p.tap.Enumerate(ctx, req.URL, waxtap.EnumerateOptions{MaxItems: 1})
	if err != nil {
		return nil, err
	}
	return &source.Resolved{
		IdentityKey: identityKey(pl.ID),
		SourceID:    pl.ID,
		SourceType:  model.SourceYouTube,
		Title:       pl.Title,
	}, nil
}

// Enumerate lists a channel/playlist as a feed. The conditional-GET validator
// round trip carries the incremental-sync cursor: req.ETag is the newest video
// id seen by the previous enumeration, and the returned ETag is the newest id of
// this one. A channel uploads feed is newest-first and append-only, so
// enumeration stops at the first already-seen id; when nothing precedes it the
// source is unchanged and the answer is NotModified. Only new entries are
// enriched with per-video metadata, capped at enrichLimit lookups, so the first
// sync of a large backlog stays cheap.
func (p *Provider) Enumerate(ctx context.Context, req source.Request) (*source.Enumeration, error) {
	lastSeen := req.ETag
	opts := enrichedOptions(p.cfg.MaxItems, enrichLimit)
	if lastSeen != "" {
		opts.Stop = func(id string) bool { return id == lastSeen }
	}
	pl, err := p.tap.Enumerate(ctx, req.URL, opts)
	if err != nil {
		return nil, err
	}
	if lastSeen != "" && len(pl.Entries) == 0 {
		// The stop cursor matched the newest entry: nothing new upstream.
		return &source.Enumeration{
			NotModified: true,
			ETag:        lastSeen,
			IdentityKey: identityKey(pl.ID),
			SourceID:    pl.ID,
		}, nil
	}

	feed := &model.Feed{Title: pl.Title, Author: pl.Author}
	failures, wholesale := p.enrichFailures(pl, enrichLimit)
	deferred := false
	for i := range pl.Entries {
		entry := pl.Entries[i]
		if ferr, ok := failures[entry.Index]; ok {
			switch {
			case wholesale || errors.Is(ferr, waxtap.ErrTemporarilyUnavailable):
				// Not a verdict about this video: enrichment ran out of
				// budget before a fresh identity could settle it, or the
				// whole pass was refused (see enrichFailures). The entry
				// is cataloged unenriched - it keeps the listing's title and
				// duration, which is what the basic page already gave - and
				// the pass carries on, because the entries after it were
				// asked about under the same rotation.
				deferred = true
				p.log.Info("youtube metadata deferred; entry left unenriched",
					"video", entry.VideoID, "err", ferr)
			case isSkipClass(ferr):
				// The video exists but cannot be delivered (members-only,
				// geo-blocked, removed, ...). Cataloging it would create an
				// episode that can never download, so drop it and move on.
				p.log.Warn("skipping unavailable youtube entry", "video", entry.VideoID, "err", ferr)
				continue
			default:
				return nil, ferr
			}
		}
		ep := model.FeedEpisode{
			GUID:          entry.VideoID,
			Title:         entry.Title,
			DurationMS:    entry.Duration.Milliseconds(),
			EnclosureURL:  watchURL(entry.VideoID),
			EnclosureType: "audio/mp4",
		}
		if entry.Video != nil {
			enrichEpisode(&ep, entry.Video)
			if i == 0 && len(entry.Video.Thumbnails) > 0 {
				feed.ImageURL = entry.Video.Thumbnails[0].URL
			}
		}
		feed.Episodes = append(feed.Episodes, ep)
	}

	etag := ""
	if len(pl.Entries) > 0 {
		// The newest listed id, even if enrichment dropped that entry: the cursor
		// tracks what was seen, not what was cataloged.
		etag = pl.Entries[0].VideoID
	}
	if deferred {
		// A deferred pass is the one case where advancing the cursor would
		// make the gap permanent. The skip case above drops entries that are
		// genuinely gone, so moving past them loses nothing; a deferred entry
		// is cataloged but bare - listing title and duration only - and the
		// next run's Stop would list nothing at or below this cursor, leaving
		// those episodes without a description, a date or an image for the life
		// of the subscription. Holding the cursor where it was re-lists them
		// once the throttle lifts. It costs a re-walk of the same page, which
		// is what the throttle already forced.
		etag = lastSeen
	}
	return &source.Enumeration{
		Feed:        feed,
		ETag:        etag,
		IdentityKey: identityKey(pl.ID),
		SourceID:    pl.ID,
	}, nil
}

// enrichedOptions builds the enumeration options both listing paths share: a
// listing capped at maxItems whose leading budget entries are refreshed with
// full per-video metadata.
//
// Enrichment is asked of WaxTap rather than driven here with Info calls because
// only WaxTap can escape the metadata throttle - a session that has asked about
// enough videos is refused the rest, worded exactly like a removed video, and
// telling the two apart takes retiring the identity and asking again, which is
// internal to it.
func enrichedOptions(maxItems, budget int) waxtap.EnumerateOptions {
	return waxtap.EnumerateOptions{
		MaxItems:      maxItems,
		Enrich:        true,
		MaxEnrich:     budget,
		EnrichOptions: []waxtap.ReadOption{waxtap.WithFullMetadata()},
	}
}

// enrichFailures indexes a playlist's per-entry enrichment failures by the
// entry's own playlist position, and says whether the whole budget was
// refused. The position is the key, not the video id: Skip leaves holes
// in the listing so a slice index means nothing, and one playlist can list
// the same video twice.
//
// A verdict in the map is trusted one entry at a time, and the trust
// rests on what WaxTap does before reporting one: an entry refused with
// the throttle's shape is re-asked under a fresh identity, and only one
// still refused there is reported as it came. What that cannot tell apart
// is an address the platform has flagged as a whole: every identity
// minted from it is refused the same way, the re-ask recovers nothing,
// and WaxTap - whose rule is that a pass recovering nothing proves the
// failures real - reports twenty-five removed videos for a channel that
// lost none. That is what wholesale catches: a pass in which every entry
// the budget reached failed is a refusal of the pass, not a set of
// verdicts, and the caller keeps its entries and its cursor - the same
// answer a deferral gets, because a false deferral costs one more listing
// and a false verdict costs the episodes for good. The rotation itself
// needs an identity WaxTap can retire, which holds here because New passes
// no HTTPClient - the default client's jar rotates - and both sidecar
// providers implement potoken.SessionInvalidator.
//
// The signature is unanimity at scale, so two things bound it. Only
// refusals count - a hard error, a rate limit or a fetch that never
// answered, fails the run as it always did rather than being mistaken
// for a verdict of either kind. And the pass has to have filled a budget
// of at least wholesaleFloor entries: a short incremental poll whose one
// new upload is members-only is a verdict, and holding the cursor on it
// would re-list that video every poll for as long as it stood alone.
//
// Errors that are not per-entry enrichment failures are the listing's own
// partial-page failures, which enumeration has always tolerated; they are
// logged and the pass carries on.
func (p *Provider) enrichFailures(pl *waxtap.Playlist, budget int) (failures map[int]error, wholesale bool) {
	if len(pl.Errors) == 0 {
		return nil, false
	}
	failures = make(map[int]error, len(pl.Errors))
	refusals := 0
	for _, err := range pl.Errors {
		var ee *waxtap.EnrichError
		if !errors.As(err, &ee) {
			p.log.Warn("partial youtube enumeration", "err", err)
			continue
		}
		failures[ee.Index] = err
		if isSkipClass(err) || errors.Is(err, waxtap.ErrTemporarilyUnavailable) {
			refusals++
		}
	}
	attempted := len(pl.Entries)
	if budget > 0 && budget < attempted {
		attempted = budget
	}
	if attempted >= wholesaleFloor && refusals == attempted {
		p.log.Warn("every youtube entry the budget reached was refused; keeping the pass unenriched",
			"refused", refusals)
		return failures, true
	}
	return failures, false
}

// wholesaleFloor is the smallest pass whose unanimous refusal reads as
// the address being refused rather than as that many verdicts.
const wholesaleFloor = 5

// enrichEpisode overlays per-video metadata onto a listing-derived episode.
func enrichEpisode(ep *model.FeedEpisode, v *waxtap.Video) {
	if v.Title != "" {
		ep.Title = v.Title
	}
	if v.Duration > 0 {
		ep.DurationMS = v.Duration.Milliseconds()
	}
	ep.Description = v.Description
	if !v.PublishDate.IsZero() {
		ep.PubDateNS = v.PublishDate.UnixNano()
	}
	if len(v.Thumbnails) > 0 {
		ep.ImageURL = v.Thumbnails[0].URL
	}
}

// skipClass lists the WaxTap availability sentinels that mean "this one video
// cannot be delivered and retrying will not help". Per WaxTap's taxonomy a feed
// consumer skips these entries; everything else is a hard error.
var skipClass = []error{
	waxtap.ErrLiveContent,
	waxtap.ErrLiveNotStarted,
	waxtap.ErrLoginRequired,
	waxtap.ErrAgeRestricted,
	waxtap.ErrVideoRestricted,
	waxtap.ErrMembersOnly,
	waxtap.ErrGeoBlocked,
	waxtap.ErrVideoUnavailable,
	waxtap.ErrNoAudioFormats,
}

func isSkipClass(err error) bool {
	for _, s := range skipClass {
		if errors.Is(err, s) {
			return true
		}
	}
	return false
}
