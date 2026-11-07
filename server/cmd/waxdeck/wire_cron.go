package main

import (
	"context"
	"log/slog"
	"time"

	"github.com/colespringer/waxdeck/server/internal/service"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// startCron starts the scheduler that runs the scheduled prune, scan,
// analyze, enrich and backup passes.
func startCron(ctx context.Context, group *supervise.Group, svc *service.Library, backups *service.Backups, log *slog.Logger) {
	group.Go(ctx, "cron-scheduler", func(ctx context.Context) error {
		tick := time.NewTicker(30 * time.Second)
		defer tick.Stop()
		// The window floor is per kind, not one value for the loop.
		// DueSchedule asks "did this kind's cron fire between the floor
		// and now", so a kind that was due and could not run has to keep
		// its old floor: advancing it would move the window past the
		// firing it just missed and the run would be lost until the next
		// scheduled one, a week away on the analyze and backup defaults.
		// A shared floor cannot express that, which is the bug this
		// replaced.
		lastCheck := map[string]time.Time{}
		start := time.Now()
		for _, kind := range []string{"prune", "scan", "analyze", "enrich", "backup"} {
			lastCheck[kind] = start
		}
		// due reports whether the kind should run now; ran records that
		// it did (or that it was not due), advancing that kind's floor.
		// A kind that was due and deferred simply never calls ran, so it
		// is asked again on the next tick, 30 seconds later.
		due := func(kind string, now time.Time) bool {
			if svc.DueSchedule(ctx, kind, lastCheck[kind], now) {
				return true
			}
			lastCheck[kind] = now
			return false
		}
		ran := func(kind string, now time.Time) { lastCheck[kind] = now }
		for {
			select {
			case <-ctx.Done():
				return ctx.Err()
			case now := <-tick.C:
				// Mid-hand-off every kind waits a tick, its window kept.
				if svc.Maintenance() {
					continue
				}
				// Order matters: prune, scan, analyze and enrich finish
				// fast (the three passes are async catalog jobs), so the
				// one long-running kind, backup, goes last and can only
				// delay the next tick, never a sibling due in this one.
				// Delayed firings are caught up, not lost: DueSchedule
				// measures from the last run, not from the tick that
				// should have fired.
				if due("prune", now) {
					svc.MarkScheduleRun(ctx, "prune", svc.RunPrune(ctx))
					ran("prune", now)
				}
				if due("scan", now) {
					_, err := svc.Rescan(ctx, false)
					svc.MarkScheduleRun(ctx, "scan", err)
					ran("scan", now)
				}
				if due("analyze", now) {
					// An analyze pass launched by hand still holds the
					// scope lease. Marking the schedule as run would
					// defer this firing to the NEXT one (a week, on the
					// default); leaving both the schedule and this kind's
					// window floor alone retries on the next tick.
					_, err := svc.Analyze(ctx)
					if service.KindOf(err) == service.KindConflict {
						log.Info("scheduled analyze waiting on a running analyze pass")
					} else {
						svc.MarkScheduleRun(ctx, "analyze", err)
						ran("analyze", now)
					}
				}
				if due("enrich", now) {
					// A pass an administrator started by hand holds the
					// lease; same reasoning as analyze above, and the
					// nightly cadence makes the retry cheap.
					err := svc.RunScheduledEnrichment(ctx)
					switch {
					case service.KindOf(err) == service.KindConflict:
						log.Info("scheduled enrichment waiting on a running pass")
					case service.KindOf(err) == service.KindUnsupported:
						// Nothing configured to enrich with. The
						// schedule is on by default, so this is an
						// ordinary state rather than a fault; marking
						// the run keeps the log quiet until something
						// is wired.
						svc.MarkScheduleRun(ctx, "enrich", nil)
						ran("enrich", now)
					default:
						svc.MarkScheduleRun(ctx, "enrich", err)
						ran("enrich", now)
					}
				}
				if due("backup", now) {
					row, err := backups.Create(ctx, nil, "scheduled")
					if service.KindOf(err) == service.KindConflict {
						// A manual backup holds the slot; same reasoning
						// as analyze above.
						log.Info("scheduled backup waiting on a running backup")
					} else {
						if err == nil {
							err = backups.Run(ctx, row.ID)
						}
						svc.MarkScheduleRun(ctx, "backup", err)
						ran("backup", now)
					}
				}
			}
		}
	})
}
