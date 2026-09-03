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
	"github.com/colespringer/waxtap/v3/waxerr"
)

// enrichLimit caps the per-video metadata (Info) calls made during one
// enumeration. Full metadata costs one extra fetch per video, so only the newest
// new entries are enriched; older entries keep the basic listing fields.
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
// enriched with per-video metadata, capped at enrichLimit Info calls, so the
// first sync of a large backlog stays cheap.
func (p *Provider) Enumerate(ctx context.Context, req source.Request) (*source.Enumeration, error) {
	lastSeen := req.ETag
	opts := waxtap.EnumerateOptions{MaxItems: p.cfg.MaxItems}
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
	infoCalls := 0
	throttled := false
	for i := range pl.Entries {
		entry := pl.Entries[i]
		ep := model.FeedEpisode{
			GUID:          entry.VideoID,
			Title:         entry.Title,
			DurationMS:    entry.Duration.Milliseconds(),
			EnclosureURL:  watchURL(entry.VideoID),
			EnclosureType: "audio/mp4",
		}
		if infoCalls < enrichLimit && !throttled {
			infoCalls++
			v, ierr := p.tap.Info(ctx, entry.VideoID, waxtap.InfoBasic, waxtap.WithFullMetadata())
			if ierr != nil {
				if isMetadataThrottle(ierr) {
					// Not a verdict about this video: YouTube is refusing
					// metadata to this identity. The entry is cataloged
					// unenriched - it keeps the listing's title and duration,
					// which is what the basic page already gave - and the rest
					// of the budget is left unspent, because every remaining
					// call would be refused the same way.
					throttled = true
					p.log.Info("youtube metadata throttled; enriching no further this pass",
						"video", entry.VideoID, "enriched", infoCalls-1, "err", ierr)
					feed.Episodes = append(feed.Episodes, ep)
					continue
				}
				if isSkipClass(ierr) {
					// The video exists but cannot be delivered (members-only,
					// geo-blocked, removed, ...). Cataloging it would create an
					// episode that can never download, so drop it and move on.
					p.log.Warn("skipping unavailable youtube entry", "video", entry.VideoID, "err", ierr)
					continue
				}
				return nil, ierr
			}
			enrichEpisode(&ep, v)
			if i == 0 && len(v.Thumbnails) > 0 {
				feed.ImageURL = v.Thumbnails[0].URL
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
	if throttled {
		// A throttled pass is the one case where advancing the cursor would
		// make the gap permanent. The skip case above drops entries that are
		// genuinely gone, so moving past them loses nothing; a throttled entry
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

// isMetadataThrottle reports whether an Info failure is YouTube's
// metadata throttle rather than a verdict about the video.
//
// The two are the same sentinel - ErrVideoUnavailable - and only the
// playability status separates them: the throttle answers UNPLAYABLE
// while a deleted, private, or nonexistent video answers ERROR. This
// mirrors WaxTap's own unexported throttleShaped, which its enumeration
// uses to decide a rotation; nothing exports the predicate, and getting
// it wrong here is the bug this exists for - a throttled channel had a
// third of its catalogue marked permanently unavailable.
//
// ErrTemporarilyUnavailable is checked too even though no Info call
// mints it today: it is minted only inside WaxTap's own enrichment, so
// it arrives the day this package uses Enrich instead.
func isMetadataThrottle(err error) bool {
	if errors.Is(err, waxtap.ErrTemporarilyUnavailable) {
		return true
	}
	var pe *waxerr.PlayabilityError
	return errors.As(err, &pe) && pe.Status == "UNPLAYABLE" &&
		errors.Is(err, waxtap.ErrVideoUnavailable)
}
