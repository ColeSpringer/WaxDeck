package service

import (
	"context"
	"slices"
	"sync"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
	"github.com/colespringer/waxbin/read"
)

// advisoryTagKey is the custom tag the content-advisory surfaces read:
// the kids-mode deny rule the admin screen offers targets it, and the
// Subsonic explicitStatus emission below queries it.
const advisoryTagKey = "ITUNESADVISORY"

// advisoryExplicitValues are the values that assert explicit: "1", and
// the legacy "4" older iTunes wrote for the same fact. "2" is a
// declared clean and "0" says nothing; neither is matched, and the
// emission stays positive-only.
var advisoryExplicitValues = []string{"1", "4"}

// TrackFacts is the flat per-track shape the Subsonic adapter groups
// into its artist and album views. The display strings carry the
// grouping labels; the entity pids carry the identity the catalog
// actually keeps, so the compatibility surface can key a group on the
// real artist or album instead of on its spelling. A pid is empty when
// the catalog holds no such entity for the track (a loose track has no
// album row), and the adapter falls back to a minted identifier there.
type TrackFacts struct {
	PID         string
	Title       string
	Artist      string
	AlbumArtist string
	Album       string
	Genre       string
	TrackNo     int
	DiscNo      int
	Year        int
	DurationMS  int64
	Codec       string
	Container   string

	// Explicit reports an ITUNESADVISORY custom tag asserting explicit
	// (advisoryExplicitValues); a declared clean and an absent tag both
	// stay false, and the adapter's emission is positive-only, so false
	// reads as unasserted rather than clean.
	Explicit bool

	// API-form entity pids (ar-..., al-...). AlbumArtistPID carries the same
	// fallback as the AlbumArtist display string above, so it is the
	// grouping handle; the raw track-artist pid is deliberately absent,
	// because a consumer reaching for it would be reaching for the
	// wrong key.
	AlbumArtistPID string
	AlbumPID       string
}

// trackFactsCache holds the unrestricted sweep, keyed by the catalog
// feed position so any catalog change invalidates it.
type trackFactsCache struct {
	mu    sync.Mutex
	tail  int64
	valid bool
	rows  []TrackFacts
}

// CatalogTailSeq reports the change-feed position the service has
// consumed to; cache layers key on it.
func (l *Library) CatalogTailSeq() int64 {
	l.feed.mu.Lock()
	defer l.feed.mu.Unlock()
	return l.feed.tail
}

// TrackFacts sweeps every music track visible to the caller. Only the
// unrestricted sweep is cached - full visibility and no tag rules, the
// same predicate the facet cache applies - because a narrowed sweep
// published under the shared entry would hand everyone the narrowed
// rows. Everyone else pays the sweep each time, keeping visibility
// exact; the adapter's own index cache in front of this keys restricted
// builds on the caller's grants and rules.
func (l *Library) TrackFacts(ctx context.Context, uc *UserCtx) ([]TrackFacts, error) {
	tail := l.CatalogTailSeq()
	ruleFree := uc.Admin || (len(uc.TagAllow) == 0 && len(uc.TagDeny) == 0)
	cacheable := uc.AllLibraries && ruleFree
	if cacheable {
		l.trackFacts.mu.Lock()
		if l.trackFacts.valid && l.trackFacts.tail == tail {
			rows := l.trackFacts.rows
			l.trackFacts.mu.Unlock()
			return rows, nil
		}
		l.trackFacts.mu.Unlock()
	}
	rows, err := l.sweepTrackFacts(ctx, uc)
	if err != nil {
		return nil, err
	}
	if cacheable {
		l.trackFacts.mu.Lock()
		// Published only while the catalog still stands where the sweep
		// began (the adapter's index cache and publishFacetBuckets hold
		// the same rule): rows computed across a moving catalog would be
		// stamped with a position they no longer answer for, and could
		// overwrite a newer sweep's entry.
		if l.CatalogTailSeq() == tail {
			l.trackFacts.tail, l.trackFacts.valid, l.trackFacts.rows = tail, true, rows
		}
		l.trackFacts.mu.Unlock()
	}
	return rows, nil
}

func (l *Library) sweepTrackFacts(ctx context.Context, uc *UserCtx) ([]TrackFacts, error) {
	explicit := l.explicitTrackPIDs(ctx)
	// The caller's tag rules ride the query, as they do on the
	// first-party listing path: itemVisible below covers library grants
	// only, and without the node a tag-deny account would browse tracks
	// through the compatibility surface that every other surface hides
	// and the stream refuses.
	q := visibleTracks().WhereNode(l.contentRuleNode(ctx, uc)).Build()
	var out []TrackFacts
	cursor := read.Cursor("")
	for {
		page, err := l.lib.QueryPage(ctx, q, cursor, 1000, false, model.PID(uc.CatalogPID))
		if err != nil {
			return nil, classify(err)
		}
		for _, it := range page.Items {
			if !uc.AllLibraries && !l.itemVisible(ctx, uc, it.PID) {
				continue
			}
			albumArtist := it.AlbumArtist
			if albumArtist == "" {
				albumArtist = it.Artist
			}
			// Mirror that fallback in pid space. The catalog's own
			// album-artist handle resolves a book's author but does not
			// fall back to the track artist, so a track with no
			// album-artist tag would otherwise come back with no
			// album-artist identity at all and drop out of the artist
			// index the display string still places it in.
			albumArtistPID := it.AlbumArtistPID
			if albumArtistPID == "" {
				albumArtistPID = it.ArtistPID
			}
			out = append(out, TrackFacts{
				PID:         itemAPIPID(it),
				Title:       it.Title,
				Artist:      it.Artist,
				AlbumArtist: albumArtist,
				Album:       it.Album,
				Genre:       it.Genre,
				TrackNo:     it.TrackNo,
				DiscNo:      it.DiscNo,
				Year:        it.Year,
				DurationMS:  it.DurationMS,
				Codec:       it.Codec,
				Container:   it.Container,
				// Deliberately not it.Explicit, which is the episode
				// advisory pair's item half and always false for tracks.
				Explicit: explicit[it.PID],

				AlbumArtistPID: entityAPIPID(PrefixArtist, albumArtistPID),
				AlbumPID:       entityAPIPID(PrefixAlbum, it.AlbumPID),
			})
		}
		if !page.HasMore {
			return out, nil
		}
		cursor = page.Next
	}
}

// explicitTrackPIDs gathers the tracks asserting the explicit advisory
// as one tag query rather than a per-track tag read, which would be an
// N+1 on the compatibility surface's request path whenever the sweep
// re-runs. The key check keeps the common no-advisory library from
// paying the tag walk at all. Failures degrade to no labels with a
// warning rather than failing the sweep: the flag is a decoration on
// rows the sweep still owns, and 24 handler sites answer "reading the
// library failed" when the index cannot build (the genre-label
// fallback in facets is the same call). No per-item visibility pass:
// the set is only consulted for rows the sweep itself admits.
func (l *Library) explicitTrackPIDs(ctx context.Context) map[model.PID]bool {
	out := map[model.PID]bool{}
	keys, err := l.lib.TagKeys(ctx)
	if err != nil {
		l.log.Warn("track facts: advisory tag keys unreadable; serving no explicit flags", "err", err)
		return out
	}
	if !slices.ContainsFunc(keys, func(k read.TagKeyCount) bool { return k.Key == advisoryTagKey }) {
		return out
	}
	items, err := l.lib.Query(ctx, visibleTracks().
		WhereValues("tag."+advisoryTagKey, query.OpIn, query.Values(advisoryExplicitValues)...).
		Build(), "")
	if err != nil {
		l.log.Warn("track facts: advisory tag query failed; serving no explicit flags", "err", err)
		return out
	}
	for _, it := range items {
		out[it.PID] = true
	}
	return out
}
