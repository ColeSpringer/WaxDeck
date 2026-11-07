package main

import (
	"context"
	"log/slog"
	"time"

	"github.com/colespringer/waxdeck/server/internal/analyzer"
	"github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/service"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// startSweeps starts the similarity sweep and the embedded analyzer it
// feeds, and the trash-retention and listen-mark sweeps.
func startSweeps(ctx context.Context, group *supervise.Group, svc *service.Library, log *slog.Logger) {
	// The similarity sweep keeps the analysis queue reconciled with the
	// catalog (new tracks enqueue, deleted audio prunes and backfills),
	// running once a scan goes quiet and on a ten-minute backstop, and the
	// embedded analyzer drains that queue in process: sonic
	// similarity with zero setup, no second container (the server
	// already links the decoders through the catalog). Both loops
	// self-gate on the runtime admin setting, so administrators flip
	// analysis on and off without a restart; external workers remain
	// the offload path for installs that want analysis off this
	// machine.
	group.Go(ctx, "similarity-sweep", svc.RunSimilaritySweeps)
	group.Go(ctx, "embedded-analysis", func(ctx context.Context) error {
		an := analyzer.New()
		first := time.NewTimer(45 * time.Second)
		defer first.Stop()
		tick := time.NewTicker(30 * time.Second)
		defer tick.Stop()
		for {
			select {
			case <-ctx.Done():
				return nil
			case <-first.C:
			case <-tick.C:
			}
			for {
				worked, err := svc.DrainEmbeddedAnalysis(ctx, an)
				if err != nil {
					log.Warn("embedded analysis", "err", err)
					break
				}
				if !worked {
					break
				}
			}
		}
	})

	// Trash retention: purge trashed files older than the configured
	// window (0 disables it). Self-gates on the runtime admin setting so
	// administrators change the policy without a restart, and a slow
	// cadence is plenty for a space-reclaim pass.
	group.Go(ctx, "trash-retention", func(ctx context.Context) error {
		first := time.NewTimer(5 * time.Minute)
		defer first.Stop()
		tick := time.NewTicker(6 * time.Hour)
		defer tick.Stop()
		for {
			select {
			case <-ctx.Done():
				return nil
			case <-first.C:
			case <-tick.C:
			}
			rep, err := svc.SweepTrashRetention(ctx)
			if err != nil {
				log.Warn("trash retention sweep", "err", err)
				continue
			}
			if rep.Purged > 0 || rep.Errored > 0 {
				log.Info("trash retention sweep",
					"purged", rep.Purged, "errored", rep.Errored, "reclaimedBytes", rep.ReclaimedBytes)
			}
		}
	})

	// Stranded listen marks: a listen row is claimed, then marked, then
	// recorded as marked, and a crash between the last two leaves a
	// claim whose play was never counted. This re-runs those marks at
	// the session's own time, so a play that arrived before a restart
	// still lands where it belongs on the recency lists.
	group.Go(ctx, "listen-mark-sweep", func(ctx context.Context) error {
		first := time.NewTimer(2 * time.Minute)
		defer first.Stop()
		tick := time.NewTicker(time.Hour)
		defer tick.Stop()
		for {
			select {
			case <-ctx.Done():
				return nil
			case <-first.C:
			case <-tick.C:
			}
			rep, err := svc.SweepListenMarks(ctx)
			if err != nil {
				log.Warn("listen mark sweep", "err", err)
				continue
			}
			if rep.Marked > 0 || rep.Settled > 0 {
				log.Info("listen mark sweep",
					"scanned", rep.Scanned, "marked", rep.Marked, "settled", rep.Settled)
			}
		}
	})
}

// startJanitor starts the hourly clean-up of expired auth state and
// the prunes of the outboxes, notifications and migration exports.
func startJanitor(ctx context.Context, group *supervise.Group, store *db.DB, svc *service.Library, log *slog.Logger) {
	// Expired sessions, spent OIDC state, and stale one-time codes are
	// swept on a coarse timer; correctness never depends on the sweep
	// (lookups check expiry themselves), it just keeps the tables lean.
	// The outbox prunes ride the same coarse timer.
	group.Go(ctx, "session-janitor", func(ctx context.Context) error {
		tick := time.NewTicker(time.Hour)
		defer tick.Stop()
		for {
			select {
			case <-ctx.Done():
				return nil
			case <-tick.C:
				if err := store.SweepExpired(ctx); err != nil {
					log.Warn("sweeping expired auth state", "err", err)
				}
				svc.PruneScrobbleOutbox(ctx)
				svc.PruneNotifyOutbox(ctx)
				svc.PruneNotifications(ctx)
				svc.SweepMigrationExports(ctx)
			}
		}
	})
}

// startCurationWorkers starts the curation workers and the sweeps that
// follow the catalog's change log.
func startCurationWorkers(ctx context.Context, group *supervise.Group, svc *service.Library, log *slog.Logger) {
	// Curation background work: the identify worker (woken by new review
	// entries, ticker as backstop), the health fix drainer, the tool
	// task runner, the upload janitor, and the health sweep scheduler.
	group.Go(ctx, "match-worker", func(ctx context.Context) error {
		tick := time.NewTicker(30 * time.Second)
		defer tick.Stop()
		for {
			select {
			case <-ctx.Done():
				return nil
			case <-svc.MatchWakeups():
			case <-tick.C:
			}
			for svc.DrainMatchQueue(ctx) {
				if ctx.Err() != nil {
					return nil
				}
			}
		}
	})
	for name, drain := range map[string]func(context.Context) bool{
		"tool-worker": svc.DrainToolTasks,
		// Health fixes and catalog repairs run for hours; on the tool
		// worker, every acquisition and sync queued behind one would wait
		// as long.
		"long-task-worker": svc.DrainLongToolTasks,
	} {
		group.Go(ctx, name, func(ctx context.Context) error {
			tick := time.NewTicker(10 * time.Second)
			defer tick.Stop()
			for {
				select {
				case <-ctx.Done():
					return nil
				case <-tick.C:
					for drain(ctx) {
						if ctx.Err() != nil {
							return nil
						}
					}
				}
			}
		})
	}
	group.Go(ctx, "upload-janitor", func(ctx context.Context) error {
		tick := time.NewTicker(time.Hour)
		defer tick.Stop()
		for {
			select {
			case <-ctx.Done():
				return nil
			case <-tick.C:
				// Overdue batches finalize first (their members regain
				// normal retention), then expired sessions reclaim.
				for svc.DrainExpiredUploadBatches(ctx) {
					if ctx.Err() != nil {
						return nil
					}
				}
				for svc.DrainExpiredUploads(ctx) {
					if ctx.Err() != nil {
						return nil
					}
				}
			}
		}
	})
	group.Go(ctx, "health-sweep", func(ctx context.Context) error {
		tick := time.NewTicker(time.Minute)
		defer tick.Stop()
		for {
			select {
			case <-ctx.Done():
				return nil
			case <-tick.C:
				if !svc.HealthSweepDue(ctx) {
					continue
				}
				if err := svc.RunHealthSweep(ctx); err != nil {
					log.Warn("health sweep", "err", err)
				}
			}
		}
	})

	// Genre normalization is continuous rather than an ingest hook:
	// genres read from file tags are resolved and stored by the catalog's
	// own scanner and never pass through WaxDeck, so a library scanned
	// tomorrow would be unnormalized again. This follows the catalog's
	// change log, so newly scanned items fold onto the canonical
	// vocabulary shortly after they land; the full-catalog pass is a tool
	// task for anything older than the log retains.
	group.Go(ctx, "genre-normalize", func(ctx context.Context) error {
		first := time.NewTimer(time.Minute)
		defer first.Stop()
		tick := time.NewTicker(2 * time.Minute)
		defer tick.Stop()
		for {
			select {
			case <-ctx.Done():
				return nil
			case <-first.C:
			case <-tick.C:
			}
			for {
				rep, err := svc.SweepGenres(ctx)
				if err != nil {
					log.Warn("genre normalization sweep", "err", err)
					break
				}
				if rep.Normalized > 0 || rep.Locked > 0 {
					log.Info("genre normalization sweep",
						"scanned", rep.Scanned, "normalized", rep.Normalized,
						"locked", rep.Locked, "offTree", rep.Unmapped)
				}
				if !rep.More || ctx.Err() != nil {
					break
				}
			}
		}
	})

	// Files a scan discovers reach the matching pipeline the same way:
	// by tailing the catalog's change log rather than by an ingest hook,
	// because a scan indexes files without WaxDeck being in the loop.
	// The pass defers while a catalog job runs, which is what lets an
	// album arrive whole rather than one entry per file indexed so far,
	// so the ticker is slower than the sweeps that are pure computation.
	group.Go(ctx, "discovery-match", func(ctx context.Context) error {
		first := time.NewTimer(90 * time.Second)
		defer first.Stop()
		tick := time.NewTicker(3 * time.Minute)
		defer tick.Stop()
		for {
			select {
			case <-ctx.Done():
				return nil
			case <-first.C:
			case <-tick.C:
			}
			// Paced, not drained. A first scan of a large library holds
			// thousands of album units and each pass re-reads the
			// pending set, so looping back to back would spend the
			// import as one long burst against a table the burst is
			// growing - and the identify worker behind it is the thing
			// that actually has to keep up. A short breath between
			// passes turns that into a steady trickle; the ticker is
			// the backstop either way.
			for {
				rep, err := svc.SweepDiscoveries(ctx)
				if err != nil {
					log.Warn("scan discovery sweep", "err", err)
					break
				}
				if rep.Opened > 0 {
					log.Info("scan discovery sweep",
						"considered", rep.Considered, "opened", rep.Opened)
				}
				if !rep.More || ctx.Err() != nil {
					break
				}
				select {
				case <-ctx.Done():
					return nil
				case <-time.After(2 * time.Second):
				}
			}
		}
	})
}
