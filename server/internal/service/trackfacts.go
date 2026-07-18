package service

import (
	"context"
	"sync"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
	"github.com/colespringer/waxbin/read"
)

// TrackFacts is the flat per-track shape the Subsonic adapter groups
// into its artist and album views. The catalog has real artist and
// album entities, but the item query grammar addresses them by display
// string, so the compatibility surface derives its groupings from
// these rows and mints string-based identifiers.
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
	q := query.New(query.EntityTracks).Build()
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
			})
		}
		if !page.HasMore {
			return out, nil
		}
		cursor = page.Next
	}
}
