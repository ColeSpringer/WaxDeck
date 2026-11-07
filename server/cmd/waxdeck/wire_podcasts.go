package main

import (
	"cmp"
	"context"
	"log/slog"
	"strings"
	"time"

	"github.com/colespringer/waxdeck/server/internal/podping"
	"github.com/colespringer/waxdeck/server/internal/service"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// startPodcastWorkers starts the feed refresh scheduler, the PodPing
// watcher when enabled, the retention sweeper and the fetch queue
// drainer.
func startPodcastWorkers(ctx context.Context, group *supervise.Group, svc *service.Library, cfg podcastsConfig, agent string,
	log *slog.Logger) {
	// Podcast background work: the feed refresh scheduler, the retention
	// sweeper, and the queue drainers. All are supervised ticker loops on
	// the process context; each cycle is cheap when idle.
	refreshEvery := time.Duration(cfg.feedRefreshMinutes) * time.Minute
	group.Go(ctx, "feed-refresh", func(ctx context.Context) error {
		tick := time.NewTicker(time.Minute)
		defer tick.Stop()
		for {
			select {
			case <-ctx.Done():
				return nil
			case <-tick.C:
				svc.RefreshDueFeeds(ctx, refreshEvery)
			}
		}
	})
	// PodPing: a floor-lowering signal, not a second sync path. It
	// watches somebody else's public chain for "this feed changed" and
	// drives the same syncShow the scheduler does, so an episode lands
	// within seconds of publication instead of at the next refresh.
	// Off by default because it is a standing outbound connection to
	// a third party, and the refresh above stays the floor either way.
	if cfg.podping.on {
		client := podping.New(podping.Config{NodeURL: cfg.podping.node, UserAgent: agent})
		watcher := podping.NewWatcher(client, log, func(ctx context.Context, ping podping.Ping) {
			svc.NotePodping(ctx, ping.IRI)
		})
		pinned := splitNonEmpty(cfg.podping.writers, ",")
		if len(pinned) > 0 {
			watcher.PinWriters(pinned)
		}
		// Said once, at start: the operator turned on an outbound
		// connection to a third party, and the next log line about it
		// may not come until a subscribed show is published to.
		log.Info("podping watcher started",
			"node", cmp.Or(cfg.podping.node, podping.DefaultNode),
			"writers", cmp.Or(strings.Join(pinned, ","), "from the chain"))
		group.Go(ctx, "podping", watcher.Run)
	}
	group.Go(ctx, "retention-sweeper", func(ctx context.Context) error {
		tick := time.NewTicker(time.Minute)
		defer tick.Stop()
		for {
			select {
			case <-ctx.Done():
				return nil
			case <-tick.C:
				svc.SweepRetention(ctx)
			}
		}
	})
	group.Go(ctx, "fetch-worker", func(ctx context.Context) error {
		tick := time.NewTicker(5 * time.Second)
		defer tick.Stop()
		for {
			select {
			case <-ctx.Done():
				return nil
			case <-tick.C:
				for svc.DrainFetchQueue(ctx) {
					if ctx.Err() != nil {
						return nil
					}
				}
			}
		}
	})
}
