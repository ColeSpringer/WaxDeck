package main

import (
	"context"
	"time"

	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
	"github.com/colespringer/waxdeck/server/internal/service"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// startDrains starts the queues every server drains: playlist syncs, the
// analysis queue while the streaming engine runs, and the scrobble and
// notification outboxes.
func startDrains(ctx context.Context, group *supervise.Group, svc *service.Library, bridge *flow.Bridge) {
	// Playlist-sync scheduler: queues a sync task for every live source
	// binding whose interval elapsed. Deliberately outside the podcast
	// block - a music-only instance syncs playlists too - and the
	// service self-gates on a snapshot-capable source provider, so a
	// bridge-less instance just idles here.
	group.Go(ctx, "playlist-sync", func(ctx context.Context) error {
		tick := time.NewTicker(time.Minute)
		defer tick.Stop()
		for {
			select {
			case <-ctx.Done():
				return nil
			case <-tick.C:
				svc.Playlists.SyncDuePlaylistSources(ctx)
			}
		}
	})

	// The silence and loudness analysis worker serves audiobooks as
	// much as podcasts (skip maps and voice-boost leveling), so it runs
	// whenever the streaming sidecar does, independent of the podcast
	// surface.
	if bridge != nil {
		group.Go(ctx, "analysis-worker", func(ctx context.Context) error {
			tick := time.NewTicker(10 * time.Second)
			defer tick.Stop()
			for {
				select {
				case <-ctx.Done():
					return nil
				case <-tick.C:
					for svc.Tools.DrainAnalysisQueue(ctx) {
						if ctx.Err() != nil {
							return nil
						}
					}
				}
			}
		})
	}

	// The scrobble and notification outboxes drain continuously; both
	// are cheap when idle and their deliveries back off on failure.
	group.Go(ctx, "scrobble-outbox", func(ctx context.Context) error {
		tick := time.NewTicker(5 * time.Second)
		defer tick.Stop()
		for {
			select {
			case <-ctx.Done():
				return nil
			case <-tick.C:
				for svc.Integrations.DrainScrobbleOutbox(ctx) {
					if ctx.Err() != nil {
						return nil
					}
				}
			}
		}
	})
	group.Go(ctx, "notify-outbox", func(ctx context.Context) error {
		tick := time.NewTicker(5 * time.Second)
		defer tick.Stop()
		for {
			select {
			case <-ctx.Done():
				return nil
			case <-tick.C:
				for svc.Integrations.DrainNotifyOutbox(ctx) {
					if ctx.Err() != nil {
						return nil
					}
				}
			}
		}
	})
}
