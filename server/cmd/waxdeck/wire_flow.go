package main

import (
	"context"
	"log/slog"
	"time"

	"github.com/colespringer/waxdeck/server/internal/auth"
	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
	"github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/service"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// startFlow seeds the streaming engine's roots file and starts the bridge
// to the engine, when one is configured; without one the bridge is nil.
func startFlow(ctx context.Context, group *supervise.Group, cfg streamingConfig, roots []root, podcastRoot, podcastDir string,
	svc *service.Library, store *db.DB, media *auth.MediaTokens, log *slog.Logger) (*flow.Bridge, error) {
	// First start: write the sidecar's roots file (compose starts the
	// engine after this server), with or without an engine URL.
	if cfg.flowConfig != "" {
		seed := engineSeedRoots(roots, podcastRoot, podcastDir)
		switch created, err := flow.SeedRootsConfig(cfg.flowConfig, seed); {
		case err != nil:
			log.Warn("could not write the streaming engine's roots file", "path", cfg.flowConfig, "err", err)
		case created:
			log.Info("wrote the streaming engine's roots file", "path", cfg.flowConfig, "roots", len(seed))
		}
	}

	// The streaming engine is optional: without one, and while a
	// configured one is not answering, originals play directly. The bridge
	// asks nothing of it at construction; its supervised loop connects in
	// the background and reports each crossing to the service.
	var bridge *flow.Bridge
	if cfg.flowURL != "" {
		// The catalog's roots the sidecar serves: the configured ones, and
		// the runtime ones it has accepted.
		var configured, table []flow.Root
		for _, r := range roots {
			configured = append(configured, flow.Root{Name: r.Name, Path: r.Path})
		}
		for _, r := range svc.Roots.Table() {
			table = append(table, flow.Root{Name: r.Name, Path: r.Path})
		}
		flowRoots := flow.SeedRoots(configured, table, cfg.flowConfig)
		if podcastDir != "" {
			// The podcast dir is its own root pair: the catalog refuses a
			// download dir inside a user root, and the sidecar streams
			// episodes only from a root it mounts.
			flowRoots = append(flowRoots, flow.Root{Name: podcastRoot, Path: podcastDir})
		}
		var err error
		bridge, err = flow.New(ctx, flow.Config{
			BaseURL:    cfg.flowURL,
			APIKey:     cfg.flowAPIKey,
			Roots:      flowRoots,
			ConfigPath: cfg.flowConfig,
			Tokens:     media,
			Resolver:   svc.Playback,
			Timelines:  store,
			Logger:     log,
		})
		if err != nil {
			return nil, err
		}
		svc.Tools.SetFlowJobs(bridge)
		bridge.SetTranscodeGate(svc.Playback.TranscodeGate())
		svc.Roots.FollowEngine(ctx, bridge)
		group.Go(ctx, "flow-bridge", bridge.Run)
		// A gapless queue holds a transcode slot the way a stream does,
		// and there is no end-of-response to give it back at: the slot
		// goes back once every one of a listener's timelines has gone
		// quiet. Supervised like every other periodic sweep here, and
		// cheap when nobody is listening.
		group.Go(ctx, "timeline-slots", func(ctx context.Context) error {
			tick := time.NewTicker(15 * time.Second)
			defer tick.Stop()
			for {
				select {
				case <-ctx.Done():
					return nil
				case <-tick.C:
					bridge.SweepTimelineSlots()
				}
			}
		})
	} else {
		log.Warn("WAXDECK_FLOW_URL is not set; playing original files directly (no transcoding, gapless timelines, or voice boost)")
		// No sidecar config to take a removed library's root out of, so
		// nothing owed to a bridge waits for one.
		svc.Roots.SetFlowRoots(nil)
	}
	return bridge, nil
}

// engineSeedRoots is what the engine's roots file starts with: the
// configured roots, then the podcast root when podcasts are on.
func engineSeedRoots(roots []root, podcastRoot, podcastDir string) []flow.Root {
	out := make([]flow.Root, 0, len(roots)+1)
	for _, r := range roots {
		out = append(out, flow.Root{Name: r.Name, Path: r.Path})
	}
	if podcastDir != "" {
		out = append(out, flow.Root{Name: podcastRoot, Path: podcastDir})
	}
	return out
}
