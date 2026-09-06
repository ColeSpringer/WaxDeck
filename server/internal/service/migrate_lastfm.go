package service

import (
	"context"
	"fmt"
	"strconv"
	"time"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/scrobble"
)

// The Last.fm import. Unlike every other source this one is read with
// the server's own API credentials rather than the household's: a
// scrobble history is public, so the only thing needed is the account
// name. What comes back is a real play log - a time per play - which is
// what separates this from the count-only sources whose history has to
// be synthesized backwards.

// migrateLastfmPageSize is the API's own maximum for a history page. A
// variable so a test can put a page boundary where it needs one.
var migrateLastfmPageSize = 200

const (
	// migrateLastfmMaxPages bounds one import. Two thousand five hundred
	// pages is half a million plays, which is more history than any real
	// account has; the cap is there so a pathological answer cannot walk
	// forever, and the summary says when it was reached.
	migrateLastfmMaxPages = 2500
	// migrateLastfmPause spaces the requests. The terms state no numeric
	// limit, so this is politeness rather than a rule: an import is not
	// something anybody is waiting on.
	migrateLastfmPause = 250 * time.Millisecond
)

// lastPage reports whether a page ends the walk.
//
// The service's own page count decides when it arrives. When it does
// not - a missing @attr, or a count in a shape this client did not
// expect - the walk falls back to the rows: a page short of the limit
// is the last one. That fallback is the whole point. Trusting a zero
// page count instead reads as "one page", which turns forty thousand
// scrobbles into two hundred and reports them as the whole history.
func lastPage(pg scrobble.HistoryPage, page, limit int) bool {
	if pg.Rows == 0 {
		return true
	}
	if pg.TotalPages > 0 {
		return page >= pg.TotalPages
	}
	return pg.Rows < limit
}

// runLastfmImport replays a Last.fm account's scrobble history and
// loved tracks onto the target account, newest first.
func (l *Library) runLastfmImport(ctx context.Context, t *wdb.ToolTask, uc *UserCtx, p migrationParams) (migrationSummary, error) {
	sum := migrationSummary{Source: p.Source, DryRun: p.DryRun, Samples: migrationSamples{Unmatched: []string{}}}
	client := l.lastfmClient()
	if client == nil {
		// Permanent, and worded as the thing to go and do: without the
		// server's API credentials there is nothing to retry.
		return sum, fmt.Errorf("%w: configure the server's Last.fm API key first", errToolPermanent)
	}
	prog := newMigrateProgress(l, t)
	hist := l.newMigrateHistory(uc, p, &sum)

	if p.History {
		// The newer end is pinned at the run's start: the history is
		// being written while it is read, so without a fixed `to` a
		// scrobble arriving mid-walk shifts every later page by one and
		// the import silently skips a play.
		to := time.Now().Unix()
		for page := 1; page <= migrateLastfmMaxPages; page++ {
			if ctx.Err() != nil {
				return sum, ctx.Err()
			}
			pg, err := client.RecentTracks(ctx, p.Username, page, migrateLastfmPageSize, to)
			if err != nil {
				return sum, migrateScrobbleErr(err)
			}
			for _, tr := range pg.Tracks {
				if tr.At == 0 {
					continue
				}
				if err := hist.add(ctx, migratePlay{
					SourceID: strconv.FormatInt(tr.At, 10) + "|" + tr.Artist + "|" + tr.Title,
					MBID:     tr.MBID,
					Artist:   tr.Artist,
					Title:    tr.Title,
					Album:    tr.Album,
					At:       time.Unix(tr.At, 0),
					// A scrobble is a play the service already decided
					// counted, so it lands finished rather than being
					// re-judged against a threshold it cannot answer.
					Finished: true,
				}); err != nil {
					return sum, err
				}
			}
			if pg.TotalPages > 0 {
				prog.report(ctx, float64(page)/float64(pg.TotalPages)*85)
			} else {
				// No page count came back, so nothing moves the bar;
				// the walk still has to renew its lease.
				prog.report(ctx, 0)
			}
			if lastPage(pg, page, migrateLastfmPageSize) {
				break
			}
			if page == migrateLastfmMaxPages {
				// The cap, with pages left: what landed is the most
				// recent of the history, and the report has to say so
				// rather than reading as the whole of it.
				sum.HistoryTruncated = true
				break
			}
			select {
			case <-ctx.Done():
				return sum, ctx.Err()
			case <-time.After(migrateLastfmPause):
			}
		}
		if err := hist.finish(ctx); err != nil {
			return sum, err
		}
	}

	if p.Stars {
		for page := 1; page <= migrateLastfmMaxPages; page++ {
			if ctx.Err() != nil {
				return sum, ctx.Err()
			}
			pg, err := client.LovedTracks(ctx, p.Username, page, migrateLastfmPageSize)
			if err != nil {
				return sum, migrateScrobbleErr(err)
			}
			for _, tr := range pg.Tracks {
				// A loved track without a date lands as of now, like every
				// other source's undated star. time.Unix(0, 0) is 1970,
				// not the zero time, so it has to be kept out: the
				// catalog orders star writes by recorded time, and a
				// star from 1970 loses to anything already there.
				at := time.Time{}
				if tr.At > 0 {
					at = time.Unix(tr.At, 0)
				}
				if err := hist.star(ctx, migratePlay{
					MBID:   tr.MBID,
					Artist: tr.Artist,
					Title:  tr.Title,
					Album:  tr.Album,
					At:     at,
				}); err != nil {
					return sum, err
				}
			}
			prog.report(ctx, 90)
			if lastPage(pg, page, migrateLastfmPageSize) {
				break
			}
			if page == migrateLastfmMaxPages {
				// The cap, with pages left: what landed is the most
				// recent of them, and the report has to say so rather
				// than reading as the whole list.
				sum.HistoryTruncated = true
				break
			}
			select {
			case <-ctx.Done():
				return sum, ctx.Err()
			case <-time.After(migrateLastfmPause):
			}
		}
	}

	prog.report(ctx, 95)
	return sum, nil
}
