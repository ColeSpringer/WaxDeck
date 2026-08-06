package service

import (
	"context"
	"sync"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/read"
)

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

	// API-form entity pids (ar-..., al-...). AlbumArtistPID carries the same
	// fallback as the AlbumArtist display string above, so it is the
	// grouping handle; the raw track-artist pid is deliberately absent,
	// because a consumer reaching for it would be reaching for the
	// wrong key.
	AlbumArtistPID string
	AlbumPID       string
}

// trackFactsCache holds the full-visibility sweep, keyed by the catalog
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

// TrackFacts sweeps every music track visible to the caller. The
// full-visibility result is cached against the feed position (the
// compatibility API's browse endpoints all group over it); restricted
// callers pay the sweep each time, keeping visibility exact.
func (l *Library) TrackFacts(ctx context.Context, uc *UserCtx) ([]TrackFacts, error) {
	tail := l.CatalogTailSeq()
	if uc.AllLibraries {
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
	if uc.AllLibraries {
		l.trackFacts.mu.Lock()
		l.trackFacts.tail, l.trackFacts.valid, l.trackFacts.rows = tail, true, rows
		l.trackFacts.mu.Unlock()
	}
	return rows, nil
}

func (l *Library) sweepTrackFacts(ctx context.Context, uc *UserCtx) ([]TrackFacts, error) {
	q := visibleTracks().Build()
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
