package service

import (
	"context"
	"strconv"
	"strings"

	"github.com/colespringer/waxbin/model"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// Scan discoveries become review entries here. A scan hashes files and
// reads tags; it identifies nothing, so before this the only ways into
// the matching pipeline were an upload, an acquisition, and a
// hand-pressed rematch - and files an administrator dropped into a
// library root sat unidentified until somebody noticed. This tails the
// catalog's change log and turns what a scan added into album-unit
// entries, which is what makes the first-run promise ("we are matching
// your library") true rather than something the onboarding copy has to
// talk around.

const (
	// discoveryCursorKey holds the catalog change seq the sweeper has
	// consumed through.
	discoveryCursorKey = "discovery-match-cursor"

	// discoveryChangeBatch bounds how many newly added items one pass
	// collects from the change log.
	discoveryChangeBatch = 500

	// discoveryUnitsPerPass bounds how many review entries one pass
	// opens. A first scan of a large library holds thousands of album
	// units; opening them a slice at a time keeps a pass short and lets
	// the identify worker start on the early ones while the rest wait.
	// Hitting the cap leaves the cursor where the pass started, and the
	// pending-unit guard is what makes that re-read open the next slice
	// rather than the same one.
	discoveryUnitsPerPass = 25
)

// discoveredItem is one newly created item and the change row it
// arrived on. The seq travels with it so a pass that stops early can
// say precisely how far it got.
type discoveredItem struct {
	pid model.PID
	seq int64
}

// DiscoverySweepReport is one pass's outcome.
type DiscoverySweepReport struct {
	// Considered counts the newly added items the pass looked at.
	Considered int
	// Opened counts the review entries it created.
	Opened int
	// Deferred is true while a catalog job runs: the pass did nothing and
	// the changes are still waiting.
	Deferred bool
	// More is true when work remains, so the worker loops rather than
	// waiting out its ticker.
	More bool
}

// SweepDiscoveries opens review entries for the music a scan discovered
// since the last pass. The supervised discovery-match worker calls it on
// its ticker, never a bare goroutine.
//
// It defers entirely while a catalog job runs, which is the debounce: a
// scan writes its additions file by file, and a pass running mid-scan
// would cut an album into as many entries as it had files indexed so
// far. Waiting for the scan to settle means an album arrives whole,
// which is the unit the matching engine scores.
func (l *Library) SweepDiscoveries(ctx context.Context) (DiscoverySweepReport, error) {
	report := DiscoverySweepReport{}
	running, err := l.catalogJobRunning(ctx)
	if err != nil {
		return report, err
	}
	if running {
		report.Deferred = true
		return report, nil
	}

	raw, err := l.db.SyncStateGet(ctx, discoveryCursorKey)
	if err != nil {
		return report, &Error{Kind: KindInternal, Err: err}
	}
	since, cursorKnown := parseSweepCursor(raw)
	if !cursorKnown {
		// First run starts at the tail, which is the opposite of what the
		// genre sweeper does and deliberately so. That one rewrites a
		// scalar onto a vocabulary: idempotent, invisible, and worth
		// applying to everything already there. This one opens entries a
		// person has to decide, so rewinding would drop an entire
		// existing library into the review queue as an upgrade side
		// effect nobody asked for. From here on what arrives is covered;
		// what is already there is what rematch and the health screen
		// are for.
		tail, err := l.lib.LatestChangeSeq(ctx)
		if err != nil {
			return report, classify(err)
		}
		if err := l.db.SyncStateSet(ctx, discoveryCursorKey, strconv.FormatInt(tail, 10)); err != nil {
			return report, &Error{Kind: KindInternal, Err: err}
		}
		return report, nil
	}
	from := since

	// Collect newly created items, coalesced, in change order. Creations
	// only: an apply rewrites the items it matched, and reading its
	// update rows back would re-review what was just decided.
	//
	// Each item keeps the seq it arrived on, so a pass that stops at its
	// unit cap can put the cursor exactly where it stopped instead of
	// rewinding to the start of the batch and reading it all again.
	seen := map[model.PID]bool{}
	var added []discoveredItem
	for len(added) < discoveryChangeBatch {
		rows, err := l.lib.Changes(ctx, since)
		if err != nil {
			return report, classify(err)
		}
		if len(rows) == 0 {
			break
		}
		// The pages come back strictly after the seq asked for, so this
		// advances every turn; if that ever stopped being true the loop
		// would spin forever inside a supervised worker, which recovers
		// panics and cannot see a wedge.
		if rows[len(rows)-1].Seq <= since {
			break
		}
		for _, ch := range rows {
			if len(added) >= discoveryChangeBatch {
				break
			}
			since = ch.Seq
			if ch.EntityType != "item" || ch.Op != model.OpCreate || seen[ch.EntityPID] {
				continue
			}
			seen[ch.EntityPID] = true
			added = append(added, discoveredItem{pid: ch.EntityPID, seq: ch.Seq})
		}
	}
	if len(added) >= discoveryChangeBatch {
		report.More = true
	}
	if len(added) == 0 {
		return report, l.storeDiscoveryCursor(ctx, from, since)
	}

	pids := make([]model.PID, 0, len(added))
	seqOf := make(map[model.PID]int64, len(added))
	for _, item := range added {
		pids = append(pids, item.pid)
		seqOf[item.pid] = item.seq
	}
	views, err := l.lib.GetMany(ctx, pids)
	if err != nil {
		return report, classify(err)
	}
	uploaded, err := l.uploadedItems(ctx, views)
	if err != nil {
		return report, err
	}
	// Units already waiting for a decision, so a re-read of the change
	// log and an album whose files straddled two passes both find their
	// entry rather than opening a second one. Keyed here rather than in
	// SQL: one spelling of the fold, and it is the Unicode-correct one.
	pending, err := l.db.PendingReviewUnits(ctx)
	if err != nil {
		return report, &Error{Kind: KindInternal, Err: err}
	}
	units := make(map[string]bool, len(pending))
	for _, unit := range pending {
		units[discoveryUnitKey(unit.LibraryPID, unit.Title, unit.Artist)] = true
	}

	// Keyed rather than ranged over: GetMany does not promise to answer
	// in the order it was asked, and this loop walks the items in change
	// order so the cursor it leaves behind means what it says.
	byPID := make(map[model.PID]*model.ItemView, len(views))
	for _, it := range views {
		if it != nil {
			byPID[it.PID] = it
		}
	}

	// covered holds every item inside a unit this pass has already
	// handled, so an album's twelve discovery rows produce one entry
	// rather than twelve overlapping ones.
	covered := map[string]bool{}
	modes := map[string]string{}
	// One entry id from this pass, as the batched marker's payload. The
	// hint says "the queue moved, here is one of them"; the screens it
	// wakes refetch their lists rather than reading the id.
	lastOpened := ""
	// The seq of the last item this pass finished with. A capped pass
	// stores it, so the next one starts at the first item it did not
	// reach rather than re-reading the whole batch.
	consumedTo := from
	capped := false
	for _, entryItem := range added {
		it := byPID[entryItem.pid]
		if it == nil {
			// Deleted between the change row and this read. Consumed all
			// the same: there is nothing here to come back for.
			consumedTo = entryItem.seq
			continue
		}
		// Consumed the moment it is looked at, whatever happens below:
		// every branch from here either opens an entry for this item or
		// decides there is nothing to open, and neither is a reason to
		// read it again. The cap breaks after this assignment, so the
		// next pass starts at the first item this one did not reach.
		consumedTo = entryItem.seq
		report.Considered++
		if covered[string(it.PID)] {
			continue
		}
		// Books and podcast episodes identify through their own
		// pipelines; the matching engine scores music releases.
		if it.Kind != model.KindTrack {
			continue
		}
		// A file that arrived through the upload or acquisition pipeline
		// was reviewed on its way in. The scan that indexes it afterwards
		// is the same audio arriving a second time.
		if uploaded[string(it.PID)] {
			continue
		}
		libraryPID := string(it.LibraryPID)
		mode, ok := modes[libraryPID]
		if !ok {
			mode = l.LibraryMatchingMode(ctx, libraryPID)
			modes[libraryPID] = mode
		}
		// An as-is library is a collection somebody already curated. The
		// mode exists to say "leave this alone", and filling the queue
		// with entries nobody will decide is the touching it forbids.
		if mode == matchingOff {
			continue
		}
		title := firstNonEmpty(it.Album, it.Title)
		artist := firstNonEmpty(it.AlbumArtist, it.Artist)
		key := discoveryUnitKey(libraryPID, title, artist)
		if units[key] {
			continue
		}
		unit, err := l.albumUnit(ctx, it)
		if err != nil {
			l.log.Warn("discovery: building an album unit", "item", it.PID, "err", err)
			continue
		}
		for _, doc := range unit {
			covered[doc.PID] = true
		}
		entry := wdb.ReviewEntry{
			Kind:       reviewKindMatch,
			MediaType:  mediaTypeForKind(it.Kind),
			Origin:     reviewOriginScan,
			LibraryPID: libraryPID,
			Title:      title,
			Artist:     artist,
		}
		// A scan discovery exists to be identified; the per-submission
		// opt-out is about what somebody hands the server, and nobody
		// handed this over. The library's own matching mode is the
		// switch that covers a scan.
		entryID, err := l.openReviewEntry(ctx, entry, reviewPayload{Tracks: unit}, true)
		if err != nil {
			l.log.Warn("discovery: opening a review entry", "item", it.PID, "err", err)
			continue
		}
		units[key] = true
		lastOpened = entryID
		report.Opened++
		if report.Opened >= discoveryUnitsPerPass {
			capped = true
			break
		}
	}

	// One marker for the whole pass, whatever it opened. openReviewEntry
	// deliberately raises none for scan-origin entries.
	if lastOpened != "" {
		l.notifyReview(ctx, lastOpened, "")
	}

	if capped {
		// Stop at the item the cap fell on rather than at the end of the
		// batch: everything after it is unread, and rewinding to the
		// start of the batch instead would re-read up to 500 change rows
		// and every album unit in them on every tick of a large first
		// scan. The pending-unit guard covers the overlap either way,
		// which is what makes this an optimization rather than the thing
		// holding correctness up.
		report.More = true
		return report, l.storeDiscoveryCursor(ctx, from, consumedTo)
	}
	return report, l.storeDiscoveryCursor(ctx, from, since)
}

// discoveryUnitKey names an album unit. The only place the fold
// happens: both the stored entries and the candidates run through this,
// because two spellings disagreeing means either duplicate entries or
// entries never opened at all.
func discoveryUnitKey(libraryPID, title, artist string) string {
	return libraryPID + "|" + strings.ToLower(title) + "|" + strings.ToLower(artist)
}

// storeDiscoveryCursor advances the stored position, writing nothing
// when an idle pass read no new changes.
func (l *Library) storeDiscoveryCursor(ctx context.Context, from, to int64) error {
	if to == from {
		return nil
	}
	if err := l.db.SyncStateSet(ctx, discoveryCursorKey, strconv.FormatInt(to, 10)); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	return nil
}

// catalogJobRunning reports whether a scan or another catalog job is in
// flight. It reads the facade rather than the service's own listing,
// which is role-gated; a job that starts just after this answers only
// means the pass runs one tick early, and the next one covers what it
// wrote.
func (l *Library) catalogJobRunning(ctx context.Context) (bool, error) {
	jobs, err := l.lib.Jobs(ctx, 20)
	if err != nil {
		return false, classify(err)
	}
	for _, job := range jobs {
		if job.State == model.JobRunning {
			return true, nil
		}
	}
	return false, nil
}

// uploadedItems asks which of these items an upload session produced.
func (l *Library) uploadedItems(ctx context.Context, views []*model.ItemView) (map[string]bool, error) {
	pids := make([]string, 0, len(views))
	for _, it := range views {
		if it != nil {
			pids = append(pids, string(it.PID))
		}
	}
	owned, err := l.db.UploadedItemPIDs(ctx, pids)
	if err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	return owned, nil
}
