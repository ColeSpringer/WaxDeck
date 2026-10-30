package service

// The catalog check and its repair. The check compares what the catalog
// keeps derived from its own rows with a fresh recompute; the repair is
// the catalog's own `db verify --fix`, run step by step as a tool task.
// No step touches a library's files, so neither waits on read-only.

import (
	"context"
	"encoding/json"
	"errors"
	"slices"
	"time"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

const (
	taskTypeCatalogRepair = "catalog-repair"

	// catalogRepairLock is what a repair holds while it is queued or
	// running: a second would only redo the first.
	catalogRepairLock = "catalog"

	// catalogRepairTimeout bounds one attempt: every step reads the whole
	// catalog, which on a large one on slow storage takes hours.
	catalogRepairTimeout = 6 * time.Hour
)

// A repair's steps, in the order the catalog's own fix runs them.
const (
	catalogRepairRollups       = "rollups"
	catalogRepairSortKeys      = "sort-keys"
	catalogRepairOrphans       = "orphans"
	catalogRepairArt           = "art"
	catalogRepairTagProvenance = "tag-provenance"
	catalogRepairStrandedTags  = "stranded-tags"
	catalogRepairSearch        = "search"
	catalogRepairVerify        = "verify"
)

// catalogRepairWords say what each step was doing, for a failure.
var catalogRepairWords = map[string]string{
	catalogRepairRollups:       "recounting totals and years",
	catalogRepairSortKeys:      "rewriting sort keys",
	catalogRepairOrphans:       "removing entries with no items",
	catalogRepairArt:           "reclaiming unused images",
	catalogRepairTagProvenance: "reclaiming records under reserved tag keys",
	catalogRepairStrandedTags:  "reclaiming tag rows under refused keys",
	catalogRepairSearch:        "rebuilding the search index",
	catalogRepairVerify:        "checking the catalog again",
}

// CatalogConsistencyDTO is the catalog's derived data against a fresh
// recompute: rows that disagree, and unused rows a repair deletes. Its
// JSON is the API's, since a repair's summary carries it as it is.
type CatalogConsistencyDTO struct {
	ItemsMissingFromSearch  int  `json:"itemsMissingFromSearch"`
	OrphanSearchRows        int  `json:"orphanSearchRows"`
	ArtistRollupDrift       int  `json:"artistRollupDrift"`
	GenreRollupDrift        int  `json:"genreRollupDrift"`
	ReleaseGroupRollupDrift int  `json:"releaseGroupRollupDrift"`
	SortKeyDrift            int  `json:"sortKeyDrift"`
	BookDurationDrift       int  `json:"bookDurationDrift"`
	BookISBNKeyDrift        int  `json:"bookIsbnKeyDrift"`
	AlbumYearDrift          int  `json:"albumYearDrift"`
	ReleaseYearDrift        int  `json:"releaseYearDrift"`
	PlaylistPositionDrift   int  `json:"playlistPositionDrift"`
	OrphanArtSources        int  `json:"orphanArtSources"`
	OrphanThumbnails        int  `json:"orphanThumbnails"`
	OrphanTagProvenance     int  `json:"orphanTagProvenance"`
	StrandedTagRows         int  `json:"strandedTagRows"`
	Consistent              bool `json:"consistent"`
	Reclaimable             bool `json:"reclaimable"`
}

// CatalogConsistency checks the catalog's derived data. Administrators
// only.
func (l *Library) CatalogConsistency(ctx context.Context, uc *UserCtx) (CatalogConsistencyDTO, error) {
	if !uc.Admin {
		return CatalogConsistencyDTO{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	return l.verifyCatalog(ctx)
}

// verifyCatalog reads the catalog's own drift report.
func (l *Library) verifyCatalog(ctx context.Context) (CatalogConsistencyDTO, error) {
	rep, err := l.lib.VerifyDerived(ctx)
	if err != nil {
		return CatalogConsistencyDTO{}, classify(err)
	}
	return CatalogConsistencyDTO{
		ItemsMissingFromSearch:  rep.ItemsMissingFTS,
		OrphanSearchRows:        rep.OrphanFTSRows,
		ArtistRollupDrift:       rep.ArtistRollupDrift,
		GenreRollupDrift:        rep.GenreRollupDrift,
		ReleaseGroupRollupDrift: rep.ReleaseGroupRollupDrift,
		SortKeyDrift:            rep.SortKeyDrift,
		BookDurationDrift:       rep.BookDurationDrift,
		BookISBNKeyDrift:        rep.BookISBNKeyDrift,
		AlbumYearDrift:          rep.AlbumYearDrift,
		ReleaseYearDrift:        rep.ReleaseYearDrift,
		PlaylistPositionDrift:   rep.PlaylistPositionDrift,
		OrphanArtSources:        rep.OrphanArtSources,
		OrphanThumbnails:        rep.OrphanThumbnails,
		OrphanTagProvenance:     rep.OrphanReservedTagProvenance,
		StrandedTagRows:         rep.StrandedTagKeyRows,
		Consistent:              rep.Consistent(),
		Reclaimable:             rep.Reclaimable(),
	}, nil
}

// StartCatalogRepair queues the catalog's repair unless one is queued or
// running. Administrators only, and refused while the catalog is handed
// off, as a check would be.
func (l *Library) StartCatalogRepair(ctx context.Context, uc *UserCtx) (ToolTaskDTO, error) {
	if !uc.Admin {
		return ToolTaskDTO{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	if l.Maintenance() {
		return ToolTaskDTO{}, &Error{Kind: KindMaintenance}
	}
	t := newToolTask(uc, taskTypeCatalogRepair, "", toolTaskParams{}, "")
	t.LockKey = catalogRepairLock
	return l.queueLockedToolTask(ctx, t, "a catalog repair")
}

// catalogRepairSummary is a repair's report: what each step did, what
// each run did, then what the check read after. A count is there once its
// step has run, and adds up every attempt's, each the rows that attempt
// changed; the task keeps it as the steps land, so one that failed says
// how far it got, and the next run starts from there.
type catalogRepairSummary struct {
	SortKeysRewritten *int `json:"sortKeysRewritten,omitempty"`
	OrphansDeleted    *int `json:"orphansDeleted,omitempty"`
	// OrphansPending is what the last orphans step left for the next
	// repair: a standing count, so it is replaced rather than added up.
	OrphansPending           *int                   `json:"orphansPending,omitempty"`
	ArtSourcesReclaimed      *int                   `json:"artSourcesReclaimed,omitempty"`
	ThumbnailsReclaimed      *int                   `json:"thumbnailsReclaimed,omitempty"`
	TagProvenanceReclaimed   *int                   `json:"tagProvenanceReclaimed,omitempty"`
	StrandedTagRowsReclaimed *int                   `json:"strandedTagRowsReclaimed,omitempty"`
	SearchRowsRebuilt        *int                   `json:"searchRowsRebuilt,omitempty"`
	Runs                     []catalogRepairRun     `json:"runs,omitempty"`
	After                    *CatalogConsistencyDTO `json:"after,omitempty"`
}

// catalogRepairRun is what one run of a repair did: the steps it finished,
// in order, and why it stopped short of the end when it did.
type catalogRepairRun struct {
	Steps     []string `json:"steps"`
	Error     string   `json:"error,omitempty"`
	HandedOff bool     `json:"handedOff,omitempty"`
}

// tally adds n changed rows to a step's count.
func tally(count *int, n int) *int {
	if count != nil {
		n += *count
	}
	return &n
}

// resumeAt is the step a new run starts at: the one after the last step a
// run finished, or the first after a run a hand-off cut short, since the
// catalog the hand-off gave back may not be the one those steps repaired.
func (s *catalogRepairSummary) resumeAt(steps []string) int {
	next := 0
	for _, r := range s.Runs {
		if r.HandedOff {
			next = 0
			continue
		}
		if n := len(r.Steps); n > 0 {
			next = slices.Index(steps, r.Steps[n-1]) + 1
		}
	}
	return next
}

// ran reports whether a run finished the step.
func (s *catalogRepairSummary) ran(step string) bool {
	for _, r := range s.Runs {
		if slices.Contains(r.Steps, step) {
			return true
		}
	}
	return false
}

// runCatalogRepair runs a repair's steps, then checks again, starting after
// the last step an earlier run finished. Each step recomputes from the
// catalog's own rows, so one cut short partway is safe to run again.
func (l *Library) runCatalogRepair(ctx context.Context, t *wdb.ToolTask) error {
	var sum catalogRepairSummary
	_ = json.Unmarshal([]byte(t.Summary), &sum)
	steps := []struct {
		name string
		run  func() error
	}{
		// The reset its writes call for is owed before they land, so the
		// process stopping anywhere from here to the repair's end still
		// leaves it to give at the next start.
		{catalogRepairRollups, func() error {
			if err := l.db.SyncStateSet(context.WithoutCancel(ctx), syncKeyCatalogResyncOwed, t.ID); err != nil {
				return &Error{Kind: KindInternal, Err: err}
			}
			err := l.lib.RefreshRollups(ctx)
			if err != nil && !sum.ran(catalogRepairRollups) {
				// Its one transaction rolled back, and no earlier run's
				// rollups stand: nothing is owed.
				l.forgetOwedResync(ctx)
			}
			return err
		}},
		// A step that fails partway still counts the rows it changed.
		{catalogRepairSortKeys, func() error {
			n, err := l.lib.RefreshSortKeys(ctx)
			if err == nil || n > 0 {
				sum.SortKeysRewritten = tally(sum.SortKeysRewritten, n)
			}
			return err
		}},
		{catalogRepairOrphans, func() error {
			rep, err := l.lib.GCOrphans(ctx)
			if err == nil {
				sum.OrphansDeleted = tally(sum.OrphansDeleted, rep.Total())
				sum.OrphansPending = &rep.Pending
			}
			return err
		}},
		{catalogRepairArt, func() error {
			sources, thumbnails, err := l.lib.GCArt(ctx)
			if err == nil || sources+thumbnails > 0 {
				sum.ArtSourcesReclaimed = tally(sum.ArtSourcesReclaimed, sources)
				sum.ThumbnailsReclaimed = tally(sum.ThumbnailsReclaimed, thumbnails)
			}
			return err
		}},
		{catalogRepairTagProvenance, func() error {
			n, err := l.lib.GCReservedTagProvenance(ctx)
			if err == nil || n > 0 {
				sum.TagProvenanceReclaimed = tally(sum.TagProvenanceReclaimed, n)
			}
			return err
		}},
		{catalogRepairStrandedTags, func() error {
			n, err := l.lib.GCStrandedTagKeys(ctx)
			if err == nil || n > 0 {
				sum.StrandedTagRowsReclaimed = tally(sum.StrandedTagRowsReclaimed, n)
			}
			return err
		}},
		// Last, so it indexes what the steps above left.
		{catalogRepairSearch, func() error {
			n, err := l.lib.RebuildSearchIndex(ctx)
			if err == nil || n > 0 {
				sum.SearchRowsRebuilt = tally(sum.SearchRowsRebuilt, n)
			}
			return err
		}},
		{catalogRepairVerify, func() error {
			after, err := l.verifyCatalog(ctx)
			if err == nil {
				sum.After = &after
			}
			return err
		}},
	}
	names := make([]string, len(steps))
	for i, step := range steps {
		names[i] = step.name
	}
	from := sum.resumeAt(names)
	if from == len(steps) {
		return nil
	}
	// The counts carry over; the check closes the run that finishes.
	sum.After = nil
	sum.Runs = append(sum.Runs, catalogRepairRun{Steps: []string{}})
	run := &sum.Runs[len(sum.Runs)-1]
	// Kept as each step lands, for the next run and for the record: a
	// failed step's own rows are counted too.
	keep := func() {
		t.Summary = marshalJSON(sum)
		if err := l.db.UpdateToolTask(context.WithoutCancel(ctx), *t); err != nil {
			l.log.Warn("recording a catalog repair's progress", "task", t.ID, "err", err)
		}
	}
	for i := from; i < len(steps); i++ {
		step := steps[i]
		err := ctx.Err()
		if err == nil && l.catalogRepairHook != nil {
			err = l.catalogRepairHook(step.name)
		}
		if err == nil {
			err = step.run()
		}
		if err != nil {
			stop := l.catalogRepairStop(run, step.name, err)
			keep()
			return stop
		}
		run.Steps = append(run.Steps, step.name)
		t.ProgressPct = 100 * float64(i+1) / float64(len(steps))
		keep()
		l.notifyToolTaskProgress(ctx, t.ID)
	}
	return nil
}

// catalogRepairStop is a step's failure as the run records it and the
// drain takes it: a hand-off that cut the run short is waited out, the
// attempt not counted, and anything else fails the attempt, saying which
// step it was. The words are the failure's own, as a task records them,
// since a recorded failure keeps only the catalog's text of an error that
// carries it.
func (l *Library) catalogRepairStop(run *catalogRepairRun, step string, err error) error {
	if KindOf(err) == KindMaintenance || l.Maintenance() {
		run.HandedOff = true
		return &toolRetry{after: toolBackoff(1), err: err, reason: "catalog-maintenance"}
	}
	run.Error = catalogRepairWords[step] + ": " + taskFailureText(err)
	return &Error{Kind: KindOf(err), Msg: run.Error}
}

// catalogRepairEnded records a repair's end, however it ended: who asked
// for it and what it did. One whose rollups step ran gives the reset it
// owes, sending every client back to a snapshot of the catalog, once: the
// release years that step puts back emit no delta, and the sort keys the
// step after it rewrites for artists and albums emit only artist and
// album deltas, which reach no client; both order what clients list.
func (l *Library) catalogRepairEnded(ctx context.Context, t *wdb.ToolTask) {
	if l.catalogRepairEndHook != nil && l.catalogRepairEndHook() {
		return
	}
	ctx = context.WithoutCancel(ctx)
	var sum catalogRepairSummary
	_ = json.Unmarshal([]byte(t.Summary), &sum)
	owed, err := l.db.SyncStateGet(ctx, syncKeyCatalogResyncOwed)
	if err != nil {
		l.log.Warn("reading the catalog reset a repair owes", "task", t.ID, "err", err)
	}
	if owed == t.ID || sum.ran(catalogRepairRollups) {
		l.payOwedResync(ctx)
	}
	detail := map[string]any{}
	if t.Summary != "" {
		_ = json.Unmarshal([]byte(t.Summary), &detail)
	}
	detail["task"], detail["state"] = t.ID, t.State
	if t.Error != "" {
		detail["error"] = t.Error
	}
	l.Audit(ctx, &UserCtx{ID: t.UserID}, "catalog.repair",
		AuditTarget{Kind: "catalog"}, detail)
}

// payOwedResync gives the catalog reset a repair owes and forgets the
// debt. The process stopping between the two gives it again at the next
// start, which costs every client one more snapshot.
func (l *Library) payOwedResync(ctx context.Context) {
	l.mintCatalogGeneration(ctx)
	l.forgetOwedResync(ctx)
}

// forgetOwedResync drops the record of an owed catalog reset.
func (l *Library) forgetOwedResync(ctx context.Context) {
	if err := l.db.SyncStateSet(context.WithoutCancel(ctx), syncKeyCatalogResyncOwed, ""); err != nil {
		l.log.Warn("forgetting an owed catalog reset", "err", err)
	}
}

// settleOwedResync gives, at the start, the reset a repair still owes
// whose end is recorded or whose task is gone: the process stopped before
// it was given. A repair still to run again gives its own at its end.
func (l *Library) settleOwedResync(ctx context.Context) {
	owed, err := l.db.SyncStateGet(ctx, syncKeyCatalogResyncOwed)
	if err != nil {
		l.log.Warn("reading an owed catalog reset", "err", err)
		return
	}
	if owed == "" {
		return
	}
	t, err := l.db.ToolTaskByID(ctx, owed)
	switch {
	case errors.Is(err, wdb.ErrNotFound):
	case err != nil:
		l.log.Warn("reading the repair that owes a catalog reset", "task", owed, "err", err)
		return
	case !ToolTaskFinished(t.State):
		return
	}
	l.payOwedResync(ctx)
}
