// Package waxtapsource implements WaxBin's source.Provider over WaxTap, so a
// YouTube channel or playlist can be subscribed and synced like a podcast feed.
// Enumerate maps a channel/playlist listing to a model.Feed, and looks again
// at live entries an earlier listing passed over; Fetch downloads one
// video's audio through WaxTap, and Resolve is the cheap identity probe. The
// provider is injected into WaxBin via waxbin.Options.SourceProviders; nothing in
// this package touches WaxBin's store directly.
package waxtapsource

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"math"
	"math/rand/v2"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/source"
	"github.com/colespringer/waxbin/waxerr"
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

	// Pending holds the live and upcoming entries a subscription's
	// listing passed over, for later polls to look at again. Nil
	// disables the second look.
	Pending PendingLive

	// Logger receives structured logs; nil discards them.
	Logger *slog.Logger
}

// PendingLive stores the entries Enumerate passed over while they were
// live or upcoming, keyed by the listing's playlist id. *db.DB
// implements it, and owns the horizon: an entry a listing last showed
// live longer ago than that is no longer listed, and a sweep outside
// the provider deletes it.
type PendingLive interface {
	// YouTubePending lists one playlist's held ids at nowNS, least
	// recently probed first, leaving out those past the horizon.
	YouTubePending(ctx context.Context, sourceID string, nowNS int64) ([]string, error)
	// RememberYouTubePending holds ids a listing showed live at nowNS.
	// One already held takes the sighting, which restarts its horizon,
	// and keeps its probe stamp.
	RememberYouTubePending(ctx context.Context, sourceID string, ids []string, nowNS int64) error
	// MarkYouTubePendingProbed stamps a look that left an id held.
	MarkYouTubePendingProbed(ctx context.Context, sourceID, videoID string, nowNS int64) error
	// HandOverYouTubePending marks ids handed to the catalog under
	// token; they stay held until confirmed.
	HandOverYouTubePending(ctx context.Context, sourceID string, ids []string, token int64) error
	// ConfirmYouTubePending drops the ids handed over under token.
	ConfirmYouTubePending(ctx context.Context, sourceID string, token int64) error
	// ForgetYouTubePending drops ids from one playlist's held set.
	ForgetYouTubePending(ctx context.Context, sourceID string, ids []string) error
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
	now        func() time.Time
}

var _ source.Provider = (*Provider)(nil)

// tapTimeouts are the CLI's, but for the chunk: a long file runs four 10 MiB
// chunks at once, unattended here, and 120s would fail it below 2.8 Mbit/s.
var tapTimeouts = waxtap.Timeouts{
	Extraction:   45 * time.Second,
	Resolve:      30 * time.Second,
	WebContext:   60 * time.Second,
	SponsorBlock: 10 * time.Second,
	ChunkRetry:   10 * time.Minute,
}

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
		Logger:   log,
		TempDir:  cfg.WorkDir,
		Timeouts: tapTimeouts,
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
	return &Provider{tap: t, cfg: cfg, log: log, categories: categories, now: time.Now}
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
		return nil, sourceErr(ctx, "waxtapsource.Resolve", err)
	}
	return &source.Resolved{
		IdentityKey: identityKey(pl.ID),
		SourceID:    pl.ID,
		SourceType:  model.SourceYouTube,
		Title:       pl.Title,
	}, nil
}

// Enumerate lists a channel or playlist for a subscription's poll, enriching
// at most enrichLimit new entries. The ETag is the cursor plus the token of
// any second-look hand-over, which the catalog returns only once stored.
func (p *Provider) Enumerate(ctx context.Context, req source.Request) (*source.Enumeration, error) {
	return p.enumerate(ctx, req, p.cfg.Pending)
}

// EnumerateOnce is Enumerate for a one-shot read such as an acquisition.
// It leaves the second look's held entries alone: a lookup there would
// hand an aired premiere to the one-shot reader and forget it before the
// subscription saw it.
func (p *Provider) EnumerateOnce(ctx context.Context, req source.Request) (*source.Enumeration, error) {
	return p.enumerate(ctx, req, nil)
}

func (p *Provider) enumerate(ctx context.Context, req source.Request, pending PendingLive) (*source.Enumeration, error) {
	lastSeen, receipt := splitETag(req.ETag)
	opts := enrichedOptions(p.cfg.MaxItems, enrichLimit)
	if lastSeen != "" {
		opts.Stop = func(id string) bool { return id == lastSeen }
	}
	pl, err := p.tap.Enumerate(ctx, req.URL, opts)
	if err != nil {
		return nil, sourceErr(ctx, "waxtapsource.Enumerate", err)
	}

	feed := &model.Feed{Title: pl.Title, Author: pl.Author}
	// The newest entry with a video lends the feed its image, which a live
	// one at the top is not.
	lend := func(v *waxtap.Video) {
		if feed.ImageURL == "" && v != nil && len(v.Thumbnails) > 0 {
			feed.ImageURL = v.Thumbnails[0].URL
		}
	}
	failures, wholesale := p.enrichFailures(pl)
	deferred := false
	listed := make(listings, len(pl.Entries))
	for i := range pl.Entries {
		entry := pl.Entries[i]
		if liveEntry(entry) {
			// It cannot download until the broadcast ends; see the cursor below.
			p.log.Debug("skipping live youtube entry", "video", entry.VideoID, "live", entry.LiveStatus.String())
			listed.note(entry.VideoID, listedLive)
			continue
		}
		if ferr, ok := failures[entry.Index]; ok {
			switch {
			case liveVerdict(ferr):
				// Listed as an ordinary video but live or not started by its
				// lookup: a stream that began and ended between two polls, or
				// one whose recording is still processing. Not yet rather
				// than never, so it goes to the second look as a live one
				// does.
				p.log.Debug("holding youtube entry its lookup found live", "video", entry.VideoID, "err", ferr)
				listed.note(entry.VideoID, listedLive)
				continue
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
				if settledVerdict(ferr) {
					listed.note(entry.VideoID, listedSettled)
				} else {
					listed.note(entry.VideoID, listedDropped)
				}
				continue
			default:
				return nil, sourceErr(ctx, "waxtapsource.Enumerate", ferr)
			}
		}
		feed.Episodes = append(feed.Episodes, episodeOf(entry.VideoID, entry.Title, entry.Duration, entry.Video))
		lend(entry.Video)
		if entry.Video != nil {
			listed.note(entry.VideoID, listedCataloged)
		} else {
			listed.note(entry.VideoID, listedBare)
		}
	}

	// The newest listed id, even if enrichment dropped that entry: the cursor
	// tracks what was seen, not what was cataloged. A live or upcoming entry
	// is not seen yet, so one at the top is listed again next poll; one
	// below a newer upload is left to the second look.
	etag := lastSeen
	for _, e := range pl.Entries {
		if !liveEntry(e) {
			etag = e.VideoID
			break
		}
	}
	var handover int64
	if pending != nil {
		// A subscribe or a re-add is no poll, and a throttled listing says a
		// lookup would only be refused too: both leave the lookups to a poll
		// that follows, whose sync then auto-downloads what they find.
		lookups := req.ETag != "" && !deferred
		aired, token, err := p.secondLook(ctx, pending, pl.ID, listed, receipt, lookups)
		if err != nil {
			return nil, sourceErr(ctx, "waxtapsource.Enumerate", err)
		}
		handover = token
		// After the listing's own entries, so those lend the image first.
		for _, a := range aired {
			feed.Episodes = append(feed.Episodes, episodeOf(a.id, "", 0, a.video))
			lend(a.video)
		}
	}
	if lastSeen != "" && etag == lastSeen && len(feed.Episodes) == 0 {
		// Nothing new, or nothing but live entries: the feed has not changed.
		return &source.Enumeration{
			NotModified: true,
			ETag:        req.ETag,
			IdentityKey: identityKey(pl.ID),
			SourceID:    pl.ID,
		}, nil
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
	if handover != 0 {
		etag += receiptSep + strconv.FormatInt(handover, 10)
	}
	return &source.Enumeration{
		Feed:        feed,
		ETag:        etag,
		IdentityKey: identityKey(pl.ID),
		SourceID:    pl.ID,
	}, nil
}

// sourceErr classes a failure to read the source as the source's, which is
// how a sync tells it from the catalog's own, or canceled once the caller is.
func sourceErr(ctx context.Context, op string, err error) error {
	if ctx.Err() != nil {
		return waxerr.FromContext(op, err, waxerr.CodeCanceled)
	}
	return waxerr.Wrap(waxerr.CodeIO, op, err)
}

// episodeOf builds one entry's feed episode: the listing's title and
// duration, overlaid with its lookup's metadata where there is one.
func episodeOf(id, title string, duration time.Duration, v *waxtap.Video) model.FeedEpisode {
	ep := model.FeedEpisode{
		GUID:          id,
		Title:         title,
		DurationMS:    duration.Milliseconds(),
		EnclosureURL:  watchURL(id),
		EnclosureType: "audio/mp4",
	}
	if v != nil {
		enrichEpisode(&ep, v)
	}
	return ep
}

// receiptSep joins the listing cursor and a hand-over token in the ETag.
// A video id never holds it.
const receiptSep = "@"

// splitETag parts a stored ETag into the listing cursor and its hand-over
// token (0 for none). Only a committed sync stores an ETag, so a token read
// back is the receipt for its episodes (source.Provider.Enumerate).
func splitETag(etag string) (cursor string, receipt int64) {
	cursor, token, ok := strings.Cut(etag, receiptSep)
	if ok {
		receipt, _ = strconv.ParseInt(token, 10, 64)
	}
	return cursor, receipt
}

// probeLimit caps the held entries one poll looks up.
const probeLimit = 5

// listing is what one poll's listing did with an entry, which decides
// what the second look does with it if held.
type listing int

const (
	listedLive      listing = iota + 1 // live by its badge or its lookup: not yet
	listedCataloged                    // in the feed with its video
	listedBare                         // in the feed without one
	listedSettled                      // dropped on a verdict that will not change
	listedDropped                      // dropped on one that may
)

// listings maps video ids to what the listing did with them.
type listings map[string]listing

// note records an entry; a playlist can list one video twice, and one
// of those in the feed with its video is the one that counts.
func (l listings) note(id string, o listing) {
	if l[id] != listedCataloged {
		l[id] = o
	}
}

// airedEntry is a held entry whose lookup answered with the video.
type airedEntry struct {
	id    string
	video *waxtap.Video
}

// secondLook is how a live or upcoming entry reaches the feed once the
// cursor has passed it. Every entry the listing found live is held. A
// held entry the listing cataloged with its video is handed over, one it
// dropped on a settled verdict is let go, and the rest stay held: one
// cataloged bare is left for its own lookup. With lookups on, it then
// looks up at most probeLimit held entries the listing did not name, the
// ones looked at longest ago, and returns those that answered with the
// video. A lookup keeps its entry on anything but a settled verdict,
// since the metadata throttle refuses in a removed video's words and a
// recording still processing answers much the same. The store is best
// effort, its failures logged; only a canceled sync fails the look.
//
// A handed-over entry stays held under the returned token until a poll's
// cursor carries it back as receipt: a failed sync, or one another commit
// overtook, offers the entry again, which the catalog takes as an update.
func (p *Provider) secondLook(ctx context.Context, pending PendingLive, sourceID string, listed listings, receipt int64, lookups bool) ([]airedEntry, int64, error) {
	if err := ctx.Err(); err != nil {
		return nil, 0, err
	}
	if receipt != 0 {
		if err := pending.ConfirmYouTubePending(ctx, sourceID, receipt); err != nil {
			p.log.Warn("confirming handed-over youtube entries", "playlist", sourceID, "err", err)
		}
	}
	now := p.now()
	held, err := pending.YouTubePending(ctx, sourceID, now.UnixNano())
	if err != nil {
		p.log.Warn("reading held youtube entries", "playlist", sourceID, "err", err)
	}
	var live []string
	for id, o := range listed {
		if o == listedLive {
			live = append(live, id)
		}
	}
	if len(live) > 0 {
		if err := pending.RememberYouTubePending(ctx, sourceID, live, now.UnixNano()); err != nil {
			p.log.Warn("holding live youtube entries", "playlist", sourceID, "err", err)
		}
	}

	var forget, handed, probe []string
	for _, id := range held {
		switch o, ok := listed[id]; {
		case !ok:
			if lookups && len(probe) < probeLimit {
				probe = append(probe, id)
			}
		case o == listedCataloged:
			handed = append(handed, id)
		case o == listedSettled:
			forget = append(forget, id)
		}
	}
	var aired []airedEntry
	for _, id := range probe {
		v, err := p.tap.Info(ctx, watchURL(id), waxtap.InfoBasic, fullMetadata...)
		if cerr := ctx.Err(); cerr != nil {
			return nil, 0, cerr
		}
		if err == nil {
			p.log.Info("held youtube entry is downloadable now", "video", id)
			aired = append(aired, airedEntry{id: id, video: v})
			handed = append(handed, id)
			continue
		}
		if settledVerdict(err) {
			p.log.Info("held youtube entry will not download; letting it go", "video", id, "err", err)
			forget = append(forget, id)
			continue
		}
		p.log.Debug("held youtube entry still pending", "video", id, "err", err)
		if merr := pending.MarkYouTubePendingProbed(ctx, sourceID, id, now.UnixNano()); merr != nil {
			p.log.Warn("stamping a held youtube entry", "video", id, "err", merr)
		}
		if errors.Is(err, waxtap.ErrRateLimited) {
			p.log.Info("youtube rate limited; held entries wait for the next poll", "playlist", sourceID)
			break
		}
	}
	if len(forget) > 0 {
		if err := pending.ForgetYouTubePending(ctx, sourceID, forget); err != nil {
			p.log.Warn("forgetting held youtube entries", "playlist", sourceID, "err", err)
		}
	}
	var token int64
	if len(handed) > 0 {
		// Random, not a clock reading: two concurrent polls of one show
		// on a coarse clock could otherwise share one, and confirming
		// the stored answer would let the other's entries go too.
		token = rand.Int64N(math.MaxInt64) + 1
		if err := pending.HandOverYouTubePending(ctx, sourceID, handed, token); err != nil {
			p.log.Warn("handing over youtube entries", "playlist", sourceID, "err", err)
		}
	}
	return aired, token, nil
}

// fullMetadata is the read the listing's enrichment and the second
// look's lookups both ask with: the watch-page pass that dates a video.
var fullMetadata = []waxtap.ReadOption{waxtap.WithFullMetadata()}

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
		EnrichOptions: fullMetadata,
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
func (p *Provider) enrichFailures(pl *waxtap.Playlist) (failures map[int]error, wholesale bool) {
	if len(pl.Errors) == 0 {
		return nil, false
	}
	failures = make(map[int]error, len(pl.Errors))
	refusals, attempted := 0, 0
	for _, e := range pl.Entries {
		if e.Video != nil {
			attempted++ // an enriched entry
		}
	}
	for _, err := range pl.Errors {
		var ee *waxtap.EnrichError
		if !errors.As(err, &ee) {
			p.log.Warn("partial youtube enumeration", "err", err)
			continue
		}
		failures[ee.Index] = err
		attempted++
		if isSkipClass(err) || errors.Is(err, waxtap.ErrTemporarilyUnavailable) {
			refusals++
		}
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

// liveEntry reports a live or upcoming broadcast, which WaxTap lists
// without a lookup and which cannot download until it ends.
func liveEntry(e waxtap.PlaylistEntry) bool {
	return e.LiveStatus == waxtap.LiveNow || e.LiveStatus == waxtap.LiveUpcoming
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

// settledVerdicts are the skip-class refusals that say a video will never
// download here, whoever asks. The rest (removed-shaped, no audio, a
// sign-in wall) are also what the metadata throttle, a bot check or a
// recording still processing answer, so a held entry outlasts them.
var settledVerdicts = []error{
	waxtap.ErrMembersOnly,
	waxtap.ErrGeoBlocked,
	waxtap.ErrAgeRestricted,
	waxtap.ErrVideoRestricted,
}

func settledVerdict(err error) bool {
	for _, s := range settledVerdicts {
		if errors.Is(err, s) {
			return true
		}
	}
	return false
}

// liveVerdict reports a lookup that found the video live or not started.
func liveVerdict(err error) bool {
	return errors.Is(err, waxtap.ErrLiveContent) || errors.Is(err, waxtap.ErrLiveNotStarted)
}
