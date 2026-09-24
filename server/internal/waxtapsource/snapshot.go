package waxtapsource

import (
	"context"
	"errors"

	waxtap "github.com/colespringer/waxtap/v3"

	"github.com/colespringer/waxdeck/server/internal/syncsource"
)

var _ syncsource.Snapshotter = (*Provider)(nil)

// PlaylistSnapshot enumerates one playlist in playlist order, no
// newest-first stop cursor, unavailable entries flagged rather than
// dropped - the shape a mutable playlist's mirror needs, where
// Enumerate's feed shape fits only an append-only subscription. The
// first opts.EnrichLimit entries (default enrichLimit) get a per-video
// lookup that settles their availability and thumbnail; later entries
// keep the listing fields with availability unknown, so a long
// playlist's snapshot stays one listing plus a bounded number of
// lookups. CoverURL is the first available entry's thumbnail: WaxTap
// surfaces no playlist-level image, and that entry is also what the
// platform shows for a playlist without a hand-set cover.
func (p *Provider) PlaylistSnapshot(ctx context.Context, url string, opts syncsource.SnapshotOptions) (*syncsource.PlaylistSnapshot, error) {
	maxEntries := opts.MaxEntries
	if maxEntries <= 0 {
		maxEntries = p.cfg.MaxItems
	}
	budget := opts.EnrichLimit
	if budget <= 0 {
		budget = enrichLimit
	}
	pl, err := p.tap.Enumerate(ctx, url, enrichedOptions(maxEntries, budget))
	if err != nil {
		return nil, err
	}
	snap := &syncsource.PlaylistSnapshot{
		ID:          pl.ID,
		IdentityKey: identityKey(pl.ID),
		Title:       pl.Title,
		Author:      pl.Author,
		Truncated:   pl.Continuation != "" || (maxEntries > 0 && len(pl.Entries) >= maxEntries),
	}
	failures, wholesale := p.enrichFailures(pl)
	for i := range pl.Entries {
		entry := pl.Entries[i]
		e := syncsource.PlaylistSnapshotEntry{
			ID:         entry.VideoID,
			Index:      entry.Index,
			URL:        watchURL(entry.VideoID),
			Title:      entry.Title,
			DurationMS: entry.Duration.Milliseconds(),
		}
		switch ferr, failed := failures[entry.Index]; {
		case liveEntry(entry):
			e.AvailabilityKnown = true
			e.Unavailable = true
			p.log.Debug("live youtube playlist entry", "video", entry.VideoID, "live", entry.LiveStatus.String())
		case !failed:
			if entry.Video != nil {
				e.AvailabilityKnown = true
				if len(entry.Video.Thumbnails) > 0 {
					e.ThumbnailURL = entry.Video.Thumbnails[0].URL
				}
				if snap.CoverURL == "" && e.ThumbnailURL != "" {
					snap.CoverURL = e.ThumbnailURL
				}
			}
		case wholesale || errors.Is(ferr, waxtap.ErrTemporarilyUnavailable):
			// Or the whole pass was refused, which is the same silence
			// about every video in it.
			// Enrichment ran out of budget before a fresh identity could
			// settle this entry, so it says nothing about the video: the
			// entry keeps AvailabilityKnown false rather than being marked
			// unavailable, which is what once retired a third of a channel
			// for good.
			p.log.Info("youtube metadata deferred; entry availability unknown",
				"video", entry.VideoID, "err", ferr)
		case isSkipClass(ferr):
			e.AvailabilityKnown = true
			e.Unavailable = true
			p.log.Warn("unavailable youtube playlist entry", "video", entry.VideoID, "err", ferr)
		default:
			return nil, ferr
		}
		snap.Entries = append(snap.Entries, e)
	}
	return snap, nil
}
