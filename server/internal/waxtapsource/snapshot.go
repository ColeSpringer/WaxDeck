package waxtapsource

import (
	"context"

	waxtap "github.com/colespringer/waxtap/v3"

	"github.com/colespringer/waxdeck/server/internal/syncsource"
)

var _ syncsource.Snapshotter = (*Provider)(nil)

// PlaylistSnapshot enumerates one playlist in playlist order, no
// newest-first stop cursor, unavailable entries flagged rather than
// dropped - the shape a mutable playlist's mirror needs, where
// Enumerate's feed shape fits only an append-only subscription. The
// first opts.EnrichLimit entries (default enrichLimit) get a per-video
// Info call that settles their availability and thumbnail; later
// entries keep the listing fields with availability unknown, so a long
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
	pl, err := p.tap.Enumerate(ctx, url, waxtap.EnumerateOptions{MaxItems: maxEntries})
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
	infoCalls := 0
	for i := range pl.Entries {
		entry := pl.Entries[i]
		e := syncsource.PlaylistSnapshotEntry{
			ID:         entry.VideoID,
			Index:      entry.Index,
			URL:        watchURL(entry.VideoID),
			Title:      entry.Title,
			DurationMS: entry.Duration.Milliseconds(),
		}
		if infoCalls < budget {
			infoCalls++
			v, ierr := p.tap.Info(ctx, entry.VideoID, waxtap.InfoBasic, waxtap.WithFullMetadata())
			switch {
			case ierr == nil:
				e.AvailabilityKnown = true
				if v.Title != "" {
					e.Title = v.Title
				}
				if v.Duration > 0 {
					e.DurationMS = v.Duration.Milliseconds()
				}
				if len(v.Thumbnails) > 0 {
					e.ThumbnailURL = v.Thumbnails[0].URL
				}
				if snap.CoverURL == "" && e.ThumbnailURL != "" {
					snap.CoverURL = e.ThumbnailURL
				}
			case isSkipClass(ierr):
				e.AvailabilityKnown = true
				e.Unavailable = true
				p.log.Warn("unavailable youtube playlist entry", "video", entry.VideoID, "err", ierr)
			default:
				return nil, ierr
			}
		}
		snap.Entries = append(snap.Entries, e)
	}
	return snap, nil
}
