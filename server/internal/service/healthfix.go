package service

// Health fixes. An unscoped fix of an enrichment-backed rule is the
// catalog's own pass over the phases that fill it, run as a job; a fix
// scoped to items, and every fix of write-unsynced, is a health-fix tool
// task working item by item. A path-mismatch fix names its items, which it
// moves as organize jobs: the whole library's is an organize pass. Either
// ends by re-checking the rule for the items it covers, which the summary
// shows at once; the score waits for the next full sweep.

import (
	"cmp"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"maps"
	"math"
	"slices"
	"sort"
	"strings"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/enrich"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/organize"
	"github.com/colespringer/waxbin/query"
	"github.com/colespringer/waxbin/read"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/providers"
)

const (
	taskTypeHealthFix = "health-fix"

	// healthFixScopeCap bounds how many failing items one fix reaches.
	healthFixScopeCap = 10000

	// healthFixTimeout bounds one health-fix task: an item's lookups run
	// at provider-etiquette pace, so a whole rule takes hours.
	healthFixTimeout = 6 * time.Hour

	// healthFixPathChunk is how many items one organize plan covers, the
	// catalog's cap on a set-membership condition.
	healthFixPathChunk = catalogSetCap

	// pathFixJobSilence is how long a path fix waits on an organize job
	// that reports nothing new before taking its row for one the catalog
	// failed to close. A run beats once per file, after the file's whole
	// move, which a tag rewrite of a large audiobook or a copy across
	// devices on slow storage stretches to minutes, never to an hour.
	pathFixJobSilence = time.Hour

	// catalogBusyReason is a path fix's word for items another job's hold
	// on the file-mutation scope kept from moving.
	catalogBusyReason = "catalog busy"
)

// What an install lacks to fix a rule, as the summary's fixBlocked says it.
const (
	fixBlockedContact      = "needs-contact"
	fixBlockedLyricsSource = "needs-lyrics-source"
	fixBlockedArtSource    = "needs-art-source"
	fixBlockedGenreSource  = "needs-genre-source"
	fixBlockedBookSource   = "needs-book-source"
	fixBlockedNoManaged    = "no-managed-library"
	fixBlockedReadOnly     = "read-only"
)

// wantPhases are the catalog phases that fill each per-item want, and a
// rule's fix forces its want's. Genres ride the release-group walk, so
// fixing them re-asks MusicBrainz about every album.
var wantPhases = map[string][]model.EnrichPhase{
	enrichWantLyrics: {model.EnrichPhaseLyrics},
	enrichWantCover:  {model.EnrichPhaseGroupArt, model.EnrichPhaseAlbumArt},
	enrichWantGenres: {model.EnrichPhaseReleaseGroup},
	enrichWantBook:   {model.EnrichPhaseBookFields},
}

// phasePrereqs are the identity phases a phase keys on: the album match
// and the art rungs read the ids these land earlier in the same run.
var phasePrereqs = map[model.EnrichPhase][]model.EnrichPhase{
	model.EnrichPhaseReleaseGroup: {model.EnrichPhaseArtist},
	model.EnrichPhaseAlbumRelease: {model.EnrichPhaseArtist, model.EnrichPhaseReleaseGroup},
	model.EnrichPhaseGroupArt:     {model.EnrichPhaseArtist, model.EnrichPhaseReleaseGroup},
	model.EnrichPhaseAlbumArt:     {model.EnrichPhaseArtist, model.EnrichPhaseReleaseGroup, model.EnrichPhaseAlbumRelease},
	model.EnrichPhaseArtistArt:    {model.EnrichPhaseArtist},
}

// runningOf keeps the phases of want that run, in the catalog's order.
func runningOf(want, running []model.EnrichPhase) []model.EnrichPhase {
	out := []model.EnrichPhase{}
	for _, p := range model.EnrichPhases() {
		if slices.Contains(want, p) && slices.Contains(running, p) {
			out = append(out, p)
		}
	}
	return out
}

// withPrereqs adds the identity phases each phase keys on.
func withPrereqs(phases []model.EnrichPhase) []model.EnrichPhase {
	out := slices.Clone(phases)
	for _, p := range phases {
		for _, q := range phasePrereqs[p] {
			if !slices.Contains(out, q) {
				out = append(out, q)
			}
		}
	}
	return out
}

// fixPhases are a fix's phases: it forces those filling its rule and
// walks, unforced, the identity phases they key on.
func fixPhases(rule string, running []model.EnrichPhase) (walk, force []model.EnrichPhase) {
	force = runningOf(wantPhases[healthFixWants[rule]], running)
	if len(force) == 0 {
		return nil, nil
	}
	return runningOf(withPrereqs(force), running), force
}

// itemPassPhases are what an item's pass walks for its wants: their phases
// and the identity phases those key on. Nil, walking every phase, when a
// want maps to none; empty when none of them runs here.
func itemPassPhases(wants []string, running []model.EnrichPhase) []model.EnrichPhase {
	var phases []model.EnrichPhase
	for _, w := range wants {
		ps, ok := wantPhases[w]
		if !ok {
			return nil
		}
		phases = append(phases, ps...)
	}
	filled := runningOf(phases, running)
	if len(filled) == 0 {
		return filled
	}
	return runningOf(withPrereqs(filled), running)
}

// healthFixWants are what a scoped fix asks per item, and fixBlockedSource
// what a rule waits on when the contact is not the missing piece.
var (
	healthFixWants = map[string]string{
		ruleMissingLyrics: enrichWantLyrics, ruleMissingArt: enrichWantCover,
		ruleMissingGenre: enrichWantGenres, ruleMissingNarrator: enrichWantBook,
		ruleMissingASIN: enrichWantBook,
	}
	fixBlockedSource = map[string]string{
		ruleMissingLyrics: fixBlockedLyricsSource, ruleMissingArt: fixBlockedArtSource,
		ruleMissingGenre: fixBlockedGenreSource, ruleMissingNarrator: fixBlockedBookSource,
		ruleMissingASIN: fixBlockedBookSource,
	}
)

// healthFixability says whether this install can fix a rule and, for a
// rule with a fix it cannot run, what it lacks. The contact comes first
// where it is the missing piece, since setting it is what registers the
// free public sources; book metadata has none of those. genre-whitelist
// and the file-quality rules have no fix at all.
func (l *Library) healthFixability(rule string) (bool, string) {
	switch rule {
	case ruleWriteUnsynced:
		if l.currentToggles().readOnly {
			return false, fixBlockedReadOnly
		}
		return true, ""
	case rulePathMismatch:
		if !slices.ContainsFunc(l.libraryRoots(), func(r Root) bool { return r.Managed }) {
			return false, fixBlockedNoManaged
		}
		if l.currentToggles().readOnly {
			return false, fixBlockedReadOnly
		}
		return true, ""
	}
	if _, ok := healthFixWants[rule]; !ok {
		return false, ""
	}
	if _, force := fixPhases(rule, l.lib.EnrichmentPhases()); len(force) == 0 {
		if !l.musicbrainzConfigured && fixBlockedSource[rule] != fixBlockedBookSource {
			return false, fixBlockedContact
		}
		return false, fixBlockedSource[rule]
	}
	// The release-group walk runs on the contact alone, and fills genres
	// only from the genre sources in the pass.
	if rule == ruleMissingGenre && !l.sourceServes(enrich.CapGenres, enrich.TargetReleaseGroup) {
		return false, fixBlockedGenreSource
	}
	return true, ""
}

// sourceServes reports a switched-on source serving capability c at target.
func (l *Library) sourceServes(c enrich.Capability, target enrich.TargetType) bool {
	for _, src := range l.sources.resolved() {
		if !src.Enabled {
			continue
		}
		p := l.sources.provider(src.Name)
		if p == nil {
			p = l.sources.builtin(src.Name)
		}
		if p != nil && providers.CapabilitiesAt(p, target).Has(c) {
			return true
		}
	}
	return false
}

// HealthFixStartDTO is a fix that started: exactly one of JobPID and
// TaskID names where it runs. Queued is the items it set out to reach.
type HealthFixStartDTO struct {
	Queued int
	JobPID string
	TaskID string
}

// errEnrichBusy answers a fix that needs the enrichment lease a running
// pass holds, and errFixRunning one for a rule already being fixed.
var (
	errEnrichBusy = &Error{Kind: KindConflict, Msg: "an enrichment pass is already running; start the fix when it ends"}
	errFixRunning = &Error{Kind: KindConflict, Msg: "a fix for this rule is already running"}
)

// StartHealthFix starts the fix for one rule, over the named items or
// every item failing it. Administrators only.
func (l *Library) StartHealthFix(ctx context.Context, uc *UserCtx, rule string, apiItemPids []string) (HealthFixStartDTO, error) {
	if !uc.Admin {
		return HealthFixStartDTO{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	// The whole library's moves are an organize pass, which an
	// administrator previews before it runs.
	if rule == rulePathMismatch && len(apiItemPids) == 0 {
		return HealthFixStartDTO{}, errInvalid("the path fix moves every mismatched file; preview and apply it from /organize")
	}
	if rule == ruleWriteUnsynced || rule == rulePathMismatch {
		if err := l.CheckWritable(ctx, ""); err != nil {
			return HealthFixStartDTO{}, err
		}
	}
	if fixable, _ := l.healthFixability(rule); !fixable {
		return HealthFixStartDTO{}, errInvalid("no automated fix for rule " + rule + " on this server")
	}
	if len(apiItemPids) > maxItemPids {
		return HealthFixStartDTO{}, errInvalid(fmt.Sprintf("at most %d items per fix", maxItemPids))
	}
	var scope []string
	for _, p := range apiItemPids {
		prefix, pid, ok := parseAPIPID(p)
		if !ok || !itemPrefix(prefix) {
			return HealthFixStartDTO{}, errInvalid("bad item pid " + p)
		}
		scope = append(scope, string(pid))
	}
	fixing, err := l.fixingRules(ctx)
	if err != nil {
		return HealthFixStartDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	if fixing[rule] {
		return HealthFixStartDTO{}, errFixRunning
	}
	_, enrichBacked := healthFixWants[rule]
	if enrichBacked {
		if _, running, err := l.runningJob(ctx, "enrich", enrichJobWindow); err != nil {
			return HealthFixStartDTO{}, err
		} else if running {
			return HealthFixStartDTO{}, errEnrichBusy
		}
	}
	queued := len(scope)
	if queued == 0 {
		counts, err := l.db.HealthRuleCounts(ctx)
		if err != nil {
			return HealthFixStartDTO{}, &Error{Kind: KindInternal, Err: err}
		}
		queued = min(counts[rule], healthFixScopeCap)
	}

	var out HealthFixStartDTO
	if enrichBacked && len(scope) == 0 {
		walk, force := fixPhases(rule, l.lib.EnrichmentPhases())
		pid, err := l.startEnrichJob(ctx, uc, waxbin.EnrichOptions{Phases: walk, ForcePhases: force}, rule)
		if err != nil {
			if KindOf(classify(err)) == KindConflict {
				return HealthFixStartDTO{}, errEnrichBusy
			}
			return HealthFixStartDTO{}, l.explainEnrichRefusal(err, apiNames(force))
		}
		out = HealthFixStartDTO{Queued: queued, JobPID: apiPID(PrefixJob, pid)}
	} else {
		// The row carries its rule from the start, so it is labelled at
		// once; it goes in only while no fix of the rule is under way.
		t := newToolTask(uc, taskTypeHealthFix, "", toolTaskParams{Rule: rule, ItemPIDs: scope},
			marshalJSON(map[string]any{"rule": rule}))
		inserted, err := l.db.InsertHealthFixTask(ctx, t, rule)
		if err != nil {
			return HealthFixStartDTO{}, &Error{Kind: KindInternal, Err: err}
		}
		if !inserted {
			return HealthFixStartDTO{}, errFixRunning
		}
		l.notifyToolTask(ctx, t.ID)
		out = HealthFixStartDTO{Queued: queued, TaskID: t.ID}
	}
	l.Audit(ctx, uc, "health.fix", AuditTarget{Kind: "health-rule", Name: rule},
		map[string]any{"queued": out.Queued, "scoped": len(scope) > 0, "job": out.JobPID, "task": out.TaskID})
	// Every open health screen learns the rule is fixing.
	l.emitEveryoneEvent(ctx, eventHealth)
	return out, nil
}

// healthFixSummary is a health-fix task's report: of the items it
// attempted, how many it filled, left alone by reason, or failed on.
type healthFixSummary struct {
	Rule      string         `json:"rule"`
	Attempted int            `json:"attempted"`
	Filled    int            `json:"filled"`
	Skipped   map[string]int `json:"skipped"`
	Failed    int            `json:"failed"`
	// A path fix's alone: the items it moved, which are the ones it
	// filled, those held back by hold code, and the organize jobs that
	// moved them.
	Moved   *int           `json:"moved,omitempty"`
	Held    map[string]int `json:"held,omitempty"`
	JobPIDs []string       `json:"jobPids,omitempty"`
}

// runHealthFixTask works a health-fix task's items, then re-checks the
// rule and says what it did.
func (l *Library) runHealthFixTask(ctx context.Context, t *wdb.ToolTask, p toolTaskParams) error {
	scope := p.ItemPIDs
	if len(scope) == 0 {
		pids, err := l.db.FailingItems(ctx, p.Rule, healthFixScopeCap)
		if err != nil {
			return &Error{Kind: KindInternal, Err: err}
		}
		scope = pids
	}
	sum := healthFixSummary{Rule: p.Rule, Skipped: map[string]int{}}
	prog := newToolProgress(l, t)
	if p.Rule == rulePathMismatch {
		var err error
		if sum, err = l.fixPathScope(ctx, t, &p, scope, prog, healthFixPathChunk); err != nil {
			return err
		}
	} else {
		for i, pid := range scope {
			if err := ctx.Err(); err != nil {
				return err
			}
			l.fixHealthItem(ctx, p.Rule, model.PID(pid), &sum)
			prog.report(ctx, 100*float64(i+1)/float64(len(scope)))
		}
	}
	t.Summary = marshalJSON(sum)
	// What it reached, not the rule's every row: the rest are the next
	// sweep's.
	if _, err := l.recheckHealthRule(ctx, p.Rule, scope); err != nil {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		l.log.Warn("health: re-checking a fixed rule", "rule", p.Rule, "err", err)
	}
	return nil
}

// pathFixProgress is how far a path fix has gone, kept in its task as it
// goes: how many of its items' chunks are done, their totals with every
// organize run the fix made, and the items the chunk in hand set out to
// move. A rerun after a stop goes on from there, and the fix's end, however
// it ends, covers every attempt.
type pathFixProgress struct {
	Done   int              `json:"done"`
	Sum    healthFixSummary `json:"sum"`
	Moving []string         `json:"moving,omitempty"`
}

// add counts a finished chunk into the totals.
func (s *healthFixSummary) add(chunk healthFixSummary) {
	s.Attempted += chunk.Attempted
	s.Filled += chunk.Filled
	s.Failed += chunk.Failed
	for r, n := range chunk.Skipped {
		s.Skipped[r] += n
	}
	for c, n := range chunk.Held {
		s.Held[c] += n
	}
}

// fixPathScope moves a path fix's items, chunk by chunk, from where an
// earlier attempt left off, keeping in the task how far it got, and
// answers what the whole fix did. A chunk a stop cuts short is done again
// by the next attempt, which counts what this one moved of it.
func (l *Library) fixPathScope(ctx context.Context, t *wdb.ToolTask, p *toolTaskParams, scope []string,
	prog *toolProgress, chunk int) (healthFixSummary, error) {
	pf := p.PathFix
	if pf == nil {
		pf = &pathFixProgress{}
		p.PathFix = pf
	}
	pf.Sum.Rule = p.Rule
	if pf.Sum.Skipped == nil {
		pf.Sum.Skipped = map[string]int{}
	}
	if pf.Sum.Held == nil {
		pf.Sum.Held = map[string]int{}
	}
	save := func() {
		raw := marshalJSON(*p)
		if err := l.db.UpdateToolTaskParams(context.WithoutCancel(ctx), t.ID, raw); err != nil {
			l.log.Warn("recording a path fix's progress", "task", t.ID, "err", err)
			return
		}
		t.Params = raw
	}
	for pf.Done < len(scope) {
		if err := ctx.Err(); err != nil {
			return healthFixSummary{}, err
		}
		end := min(pf.Done+chunk, len(scope))
		sum := healthFixSummary{Skipped: map[string]int{}, Held: map[string]int{}}
		l.fixPaths(ctx, scope[pf.Done:end], &sum, prog, pf, save)
		if err := ctx.Err(); err != nil {
			return healthFixSummary{}, err
		}
		pf.Sum.add(sum)
		pf.Done, pf.Moving = end, nil
		save()
		prog.report(ctx, 100*float64(end)/float64(len(scope)))
	}
	out := pf.Sum
	moved := out.Filled
	out.Moved = &moved
	return out, nil
}

// auditPathFix records a path fix's end as the fix, once, however it
// ended: naming every organize run it made, which History lists and an
// undo takes back, and what every attempt of it did. A fix that did not
// finish counts what it moved of the chunk in hand by where those items
// are now.
func (l *Library) auditPathFix(ctx context.Context, t *wdb.ToolTask, p toolTaskParams) {
	ctx = context.WithoutCancel(ctx)
	var sum healthFixSummary
	if t.State != taskStateDone || json.Unmarshal([]byte(t.Summary), &sum) != nil {
		if p.PathFix != nil {
			sum = p.PathFix.Sum
			if len(p.PathFix.Moving) > 0 {
				placed, err := l.itemsInPlace(ctx, p.PathFix.Moving)
				if err != nil {
					l.log.Warn("path fix: reading where its last items are", "task", t.ID, "err", err)
				}
				sum.Filled += len(placed)
			}
		}
	}
	l.Audit(ctx, &UserCtx{ID: t.UserID}, "health.fix", AuditTarget{Kind: "health-rule", Name: rulePathMismatch},
		map[string]any{"task": t.ID, "jobPids": sum.JobPIDs, "moved": sum.Filled, "held": sum.Held, "failed": sum.Failed})
}

// itemsInPlace answers which of pids have every file where their library's
// profile places it.
func (l *Library) itemsInPlace(ctx context.Context, pids []string) (map[model.PID]bool, error) {
	plan, err := l.lib.PlanOrganize(ctx, visibleItems().WhereValues("pid", query.OpIn, query.Values(pids)...).Build(),
		waxbin.OrganizeOptions{})
	if err != nil {
		return nil, classify(err)
	}
	out := map[model.PID]bool{}
	for i := range plan.Actions {
		a := &plan.Actions[i]
		if a.ItemPID == "" {
			continue
		}
		if placed, seen := out[a.ItemPID]; !seen || placed {
			out[a.ItemPID] = a.Skip && a.Code == organize.HoldInPlace
		}
	}
	maps.DeleteFunc(out, func(_ model.PID, placed bool) bool { return !placed })
	return out, nil
}

// healthFixTaskEnded tells every account a fix task's rule is no longer
// being fixed, once the task's end is recorded, and its starter what it
// did or why it failed. A path fix is audited here, at its one end.
func (l *Library) healthFixTaskEnded(ctx context.Context, t *wdb.ToolTask) {
	var p toolTaskParams
	_ = json.Unmarshal([]byte(t.Params), &p)
	if p.Rule == rulePathMismatch {
		l.auditPathFix(ctx, t, p)
	}
	l.emitEveryoneEvent(ctx, eventHealth)
	body := "The fix failed: " + cmp.Or(t.Error, "no reason was recorded")
	if t.State == taskStateDone {
		var sum healthFixSummary
		if json.Unmarshal([]byte(t.Summary), &sum) == nil {
			body = healthFixBody(sum, l.readOnlyCause())
		}
	}
	l.EmitNotificationFor(ctx, "health-fix-finished", healthFixTitle(p.Rule), body, t.ID, []string{t.UserID})
}

// fixHealthItem fixes one item's rule, counting what came of it.
func (l *Library) fixHealthItem(ctx context.Context, rule string, pid model.PID, sum *healthFixSummary) {
	sum.Attempted++
	it, err := l.lib.Get(ctx, pid)
	if err != nil {
		if KindOf(classify(err)) == KindNotFound {
			sum.Skipped["gone"]++
		} else {
			sum.Failed++
		}
		return
	}
	if rule == ruleWriteUnsynced {
		if err := l.checkPathWritable(ctx, string(it.Path)); err != nil {
			if KindOf(err) == KindReadOnly {
				sum.Skipped[l.readOnlyCause()]++
			} else {
				sum.Failed++
			}
			return
		}
		l.fixWriteDrift(ctx, it, sum)
		return
	}
	want := healthFixWants[rule]
	_, skipped, err := l.enrichItemFully(ctx, it, []string{want})
	if err != nil {
		sum.Failed++
		return
	}
	// Filled is the rule passing now, not something applied: a book
	// source can fill the narrator and leave the ASIN missing.
	now, err := l.lib.Get(ctx, pid)
	switch {
	case err != nil:
		sum.Failed++
	case l.stillFails(ctx, rule, now, recheckInputs{}):
		sum.Skipped[skipReason(skipped, want)]++
	default:
		sum.Filled++
	}
}

// fixPaths moves one chunk of path-mismatched items where their library's
// profile places them, as an organize job, counting items rather than
// files: a book moves as all its parts, and fails if one of them does.
// The items it sets out to move and the job it runs go into the fix's
// progress pf, saved by save, before the job runs; an item an earlier
// attempt set out to move and that is in place now counts as moved.
func (l *Library) fixPaths(ctx context.Context, pids []string, sum *healthFixSummary, prog *toolProgress,
	pf *pathFixProgress, save func()) {
	sum.Attempted += len(pids)
	q := query.New(query.EntityItems).WhereValues("pid", query.OpIn, query.Values(pids)...).Build()
	plan, err := l.lib.PlanOrganize(ctx, q, waxbin.OrganizeOptions{})
	if err != nil {
		sum.Failed += len(pids)
		return
	}
	l.holdReadOnly(plan)
	earlier, listed := map[model.PID]bool{}, map[model.PID]bool{}
	for _, pid := range pf.Moving {
		earlier[model.PID(pid)], listed[model.PID(pid)] = true, true
	}
	// Nothing to move is no job, and no lease a scan could be holding.
	var rep *organize.Report
	if plan.Pending() > 0 {
		for i := range plan.Actions {
			if a := &plan.Actions[i]; !a.Skip && a.ItemPID != "" && !listed[a.ItemPID] {
				listed[a.ItemPID] = true
				pf.Moving = append(pf.Moving, string(a.ItemPID))
			}
		}
		save()
		rep, err = l.organizePaths(ctx, q, pf, save, prog)
	}
	// Another job holding the scope refused the run before it moved
	// anything.
	busy := KindOf(err) == KindCatalogBusy
	// The job holds again as things then stand, so its report has the
	// last word on what was held and what failed.
	held := map[model.PID]organize.HoldCode{}
	failedFiles := map[model.PID]bool{}
	if rep != nil {
		for _, h := range rep.Holds {
			held[h.FilePID] = h.Code
		}
		for _, f := range rep.Failures {
			failedFiles[f.FilePID] = true
		}
	}
	type outcome struct {
		moved, failed, busy bool
		held                organize.HoldCode
	}
	byItem := map[model.PID]*outcome{}
	for i := range plan.Actions {
		a := &plan.Actions[i]
		o := byItem[a.ItemPID]
		if o == nil {
			o = &outcome{}
			byItem[a.ItemPID] = o
		}
		code, isHeld := held[a.FilePID]
		if rep == nil && isHold(a) {
			code, isHeld = a.Code, true
		}
		switch {
		case failedFiles[a.FilePID]:
			o.failed = true
		case isHeld:
			// A book's other parts are held for the one that cannot
			// move, which names the item's hold.
			if o.held == "" || o.held == organize.HoldBookHeld {
				o.held = code
			}
		case a.Skip && (rep == nil || a.Code == organize.HoldInPlace):
			// Already in place, which is the default below.
		case busy:
			o.busy = true
		case err != nil:
			// A run cut short cannot say which moves landed, since the
			// blocked ones run last.
			o.failed = true
		default:
			o.moved = true
		}
	}
	var planless []model.PID
	for _, pid := range pids {
		if byItem[model.PID(pid)] == nil {
			planless = append(planless, model.PID(pid))
		}
	}
	var readOnly map[model.PID]bool
	if plan.ReadOnlyLibraries > 0 {
		readOnly = l.itemsInReadOnlyLibraries(ctx, planless)
	}
	for _, pid := range pids {
		o := byItem[model.PID(pid)]
		switch {
		case o == nil && readOnly[model.PID(pid)]:
			sum.Held[string(organize.HoldReadOnly)]++
		case o == nil:
			// Planned for nothing: gone, or no longer under a managed root.
			sum.Skipped["not placed by organize"]++
		case o.failed:
			sum.Failed++
		case o.held != "":
			sum.Held[string(o.held)]++
		case o.busy:
			sum.Skipped[catalogBusyReason]++
		case o.moved, earlier[model.PID(pid)]:
			// Moved now, or by an attempt a stop cut short.
			sum.Filled++
		default:
			sum.Skipped["already in place"]++
		}
	}
}

// organizePaths runs a path fix's chunk as an organize job, naming it in
// the fix's progress, keeping the task's lease while it waits the job out,
// and answers what the job recorded; a job that did not finish is an
// error beside what it did.
func (l *Library) organizePaths(ctx context.Context, q query.Query, pf *pathFixProgress, save func(),
	prog *toolProgress) (*organize.Report, error) {
	pid, err := l.lib.RunOrganize(l.procCtx, q, waxbin.OrganizeOptions{})
	if err != nil {
		return nil, classifyMutation(err)
	}
	l.followJob(pid)
	pf.Sum.JobPIDs = append(pf.Sum.JobPIDs, apiPID(PrefixJob, pid))
	save()
	j, err := l.awaitJob(ctx, pid, pathFixJobSilence, func(ctx context.Context) { prog.report(ctx, prog.lastPct) })
	if errors.Is(err, errJobSilent) {
		l.log.Warn("path fix: an organize job stopped reporting; its moves count as failed", "job", string(pid))
	}
	if err != nil {
		return nil, err
	}
	var rep *organize.Report
	if res := organizeRunResult(j); res != nil {
		rep = &res.Report
	}
	if j.State != model.JobDone {
		return rep, fmt.Errorf("organize job %s ended %s: %s", pid, j.State, j.Error)
	}
	return rep, nil
}

// holdLabel words a hold for a fix's news from its code alone, since a
// hold's reason can carry a path; readOnly is what made a read-only hold.
func holdLabel(c organize.HoldCode, readOnly string) string {
	switch c {
	case organize.HoldCollision, organize.HoldOccupied, organize.HoldOccupiedCase:
		return "destination taken"
	case organize.HoldReadOnly:
		return readOnly
	case organize.HoldUntagged:
		return "missing tags"
	case organize.HoldMissing:
		return "file not on disk"
	case organize.HoldVirtual:
		return "part of a cue rip"
	case organize.HoldBookHeld:
		return "rest of the book held"
	}
	return "held back"
}

// itemsInReadOnlyLibraries answers which items sit in a library the
// catalog flags read-only.
func (l *Library) itemsInReadOnlyLibraries(ctx context.Context, pids []model.PID) map[model.PID]bool {
	out := map[model.PID]bool{}
	if len(pids) == 0 {
		return out
	}
	items, err := l.lib.GetMany(ctx, pids)
	if err != nil {
		l.log.Warn("reading items for their libraries", "err", err)
		return out
	}
	for _, it := range items {
		if it != nil && l.libraryReadOnly(string(it.LibraryPID)) {
			out[it.PID] = true
		}
	}
	return out
}

// skipReason is why a fix left an item alone, from the enrichment's own
// skip entries ("lyrics: no provider hit").
func skipReason(skipped []string, want string) string {
	for _, e := range skipped {
		if reason, ok := strings.CutPrefix(e, want+": "); ok {
			switch reason {
			case "no provider hit":
				return "no match"
			case "no provider":
				return "no source"
			}
			return reason
		}
	}
	return "no match"
}

// healthRecheck is what re-checking a rule found: items that now pass,
// items that still fail, and items that are gone.
type healthRecheck struct{ passing, failing, gone int }

// recheckInputs are the bulk reads a rule's re-test looks items up in;
// a nil lyrics set reads each item's lyrics instead.
type recheckInputs struct {
	moves    map[model.PID]bool
	findings map[string]*fileFinding
	lyrics   map[model.PID]bool
}

// recheckHealthRule re-tests one rule for every item the index holds it
// against, taking it off the items that now pass and dropping the rows of
// items gone. Each change is made against the row as it stands, so a
// sweep writing the same rows meanwhile keeps what it wrote.
func (l *Library) recheckHealthRule(ctx context.Context, rule string, scope []string) (healthRecheck, error) {
	var res healthRecheck
	pids := scope
	if pids == nil {
		var err error
		if pids, err = l.db.FailingItems(ctx, rule, math.MaxInt); err != nil {
			return res, &Error{Kind: KindInternal, Err: err}
		}
	}
	var err error
	var in recheckInputs
	switch rule {
	case rulePathMismatch:
		if in.moves, err = l.plannedMovesOf(ctx, pids); err != nil {
			return res, err
		}
	case ruleWriteUnsynced:
		if in.findings, err = l.fileDiagnosticRules(ctx); err != nil {
			return res, err
		}
	case ruleMissingLyrics:
		if in.lyrics, err = l.lyricsPresence(ctx); err != nil {
			return res, err
		}
	}
	for i := 0; i < len(pids); i += healthFixPathChunk {
		chunk := pids[i:min(i+healthFixPathChunk, len(pids))]
		items, err := l.presentItems(ctx, chunk)
		if err != nil {
			return res, err
		}
		for _, pid := range chunk {
			it, ok := items[model.PID(pid)]
			switch {
			case !ok:
				res.gone++
				err = l.db.DeleteHealthRow(ctx, pid)
			case l.stillFails(ctx, rule, it, in):
				res.failing++
				continue
			default:
				res.passing++
				err = l.db.DropHealthRule(ctx, pid, rule)
			}
			if err != nil {
				return res, &Error{Kind: KindInternal, Err: err}
			}
		}
	}
	return res, nil
}

// plannedMovesOf is readPlannedMoves for the named items alone, so a
// re-check stats their files rather than the library's.
func (l *Library) plannedMovesOf(ctx context.Context, pids []string) (map[model.PID]bool, error) {
	out := map[model.PID]bool{}
	for i := 0; i < len(pids); i += healthFixPathChunk {
		chunk := pids[i:min(i+healthFixPathChunk, len(pids))]
		if l.pathPlanHook != nil {
			l.pathPlanHook(chunk)
		}
		plan, err := l.lib.PlanOrganize(ctx, visibleItems().WhereValues("pid", query.OpIn, query.Values(chunk)...).Build(),
			waxbin.OrganizeOptions{})
		if err != nil {
			return nil, classify(err)
		}
		for j := range plan.Actions {
			if a := &plan.Actions[j]; a.ItemPID != "" && misplaced(a) {
				out[a.ItemPID] = true
			}
		}
	}
	return out, nil
}

// presentItems reads which of pids are present items, as the sweep
// grades only those.
func (l *Library) presentItems(ctx context.Context, pids []string) (map[model.PID]*model.ItemView, error) {
	q := query.New(query.EntityItems).
		Where("state", query.OpIs, string(model.StatePresent)).
		WhereValues("pid", query.OpIn, query.Values(pids)...).Build()
	out := make(map[model.PID]*model.ItemView, len(pids))
	cursor := read.Cursor("")
	for {
		page, err := l.lib.QueryPage(ctx, q, cursor, healthFixPathChunk, false, "")
		if err != nil {
			return nil, classify(err)
		}
		for _, it := range page.Items {
			out[it.PID] = it
		}
		if !page.HasMore {
			return out, nil
		}
		cursor = page.Next
	}
}

// stillFails re-tests one rule for one item as the sweep does; an answer
// it cannot read counts as failing.
func (l *Library) stillFails(ctx context.Context, rule string, it *model.ItemView, in recheckInputs) bool {
	switch rule {
	case ruleMissingLyrics:
		if in.lyrics != nil {
			return !in.lyrics[it.PID]
		}
		ly, err := l.lib.Lyrics(ctx, it.PID)
		return err != nil || !ly.HasContent()
	case ruleMissingArt:
		_, err := l.lib.ArtProvenance(ctx, model.EntityRef{Type: model.ArtTrack, PID: it.PID}, model.ArtRoleFront)
		return err != nil
	case ruleMissingGenre:
		return it.Genre == ""
	case ruleMissingNarrator:
		return it.Narrator == ""
	case ruleMissingASIN:
		return it.ASIN == ""
	case rulePathMismatch:
		return in.moves[it.PID]
	case ruleWriteUnsynced:
		rules, _ := l.itemFileRules(ctx, it, in.findings)
		return in.findings == nil || slices.Contains(rules, ruleWriteUnsynced)
	}
	return true
}

// finishHealthFixJob ends a fix the catalog's pass ran: the rule is
// re-checked, the administrator who started it hears what it filled, and
// the rule stops reading as fixing. A stop during the re-check leaves the
// origin for the next start to finish.
func (l *Library) finishHealthFixJob(ctx context.Context, o wdb.JobOrigin, j Job) {
	res, err := l.recheckHealthRule(ctx, o.Rule, nil)
	if err != nil {
		if ctx.Err() != nil {
			return
		}
		l.log.Warn("health: re-checking a fixed rule", "rule", o.Rule, "err", err)
	}
	ctx = context.WithoutCancel(ctx)
	l.EmitNotificationFor(ctx, "health-fix-finished", healthFixTitle(o.Rule),
		healthFixJobBody(j, res, err), j.PID, []string{o.UserID})
	l.dropJobOrigin(ctx, o.PID)
	l.emitEveryoneEvent(ctx, eventHealth)
}

// fixingRules is every rule a fix is under way for: a pass-backed fix
// from its start until its re-check lands, a task-backed one while its
// task is queued or running.
func (l *Library) fixingRules(ctx context.Context) (map[string]bool, error) {
	jobs, err := l.db.JobOriginRules(ctx)
	if err != nil {
		return nil, err
	}
	tasks, err := l.db.ActiveToolTaskRules(ctx, taskTypeHealthFix)
	if err != nil {
		return nil, err
	}
	out := make(map[string]bool, len(jobs)+len(tasks))
	for _, r := range slices.Concat(jobs, tasks) {
		out[r] = true
	}
	return out, nil
}

// healthFixJobBody says what a pass-backed fix did: what its re-check
// found, or that the re-check failed, after why the pass did not finish.
func healthFixJobBody(j Job, res healthRecheck, recheckErr error) string {
	body := fmt.Sprintf("Filled %d of %d; %d still missing", res.passing, res.passing+res.failing, res.failing)
	if recheckErr != nil {
		body = "The rule could not be re-checked (" + recheckErr.Error() + "); its count moves at the next sweep"
	}
	if model.JobState(j.State) != model.JobDone {
		body = "The enrichment pass failed (" + jobFailure(j) + "). " + body
	}
	return body
}

func healthFixTitle(rule string) string {
	return "Fix finished: " + cmp.Or(healthRuleLabels[rule], rule)
}

// healthFixBody says what a fix task did: "Filled 120 of 180; 60 skipped
// (no match 55, locked 5); 0 failed", or for a path fix "Moved 2 of 3; 1
// held (destination taken 1); 0 failed". readOnly words its read-only
// holds: a fix starts only on a writable server, so the switch on at its
// end is what held them.
func healthFixBody(s healthFixSummary, readOnly string) string {
	if s.Moved != nil {
		body := fmt.Sprintf("Moved %d of %d", *s.Moved, s.Attempted)
		held := map[string]int{}
		for code, n := range s.Held {
			held[holdLabel(organize.HoldCode(code), readOnly)] += n
		}
		if n, words := countsInWords(held); n > 0 {
			body += fmt.Sprintf("; %d held (%s)", n, words)
		}
		if n, words := countsInWords(s.Skipped); n > 0 {
			body += fmt.Sprintf("; %d skipped (%s)", n, words)
		}
		return body + fmt.Sprintf("; %d failed", s.Failed)
	}
	body := fmt.Sprintf("Filled %d of %d", s.Filled, s.Attempted)
	if n := s.Attempted - s.Filled - s.Failed; n > 0 {
		_, words := countsInWords(s.Skipped)
		body += fmt.Sprintf("; %d skipped (%s)", n, words)
	}
	return body + fmt.Sprintf("; %d failed", s.Failed)
}

// countsInWords sums counts by reason and words them, most first:
// "no match 55, locked 5".
func countsInWords(counts map[string]int) (int, string) {
	reasons := make([]string, 0, len(counts))
	total := 0
	for r, n := range counts {
		if n > 0 {
			reasons = append(reasons, r)
			total += n
		}
	}
	sort.Slice(reasons, func(a, b int) bool {
		if counts[reasons[a]] != counts[reasons[b]] {
			return counts[reasons[a]] > counts[reasons[b]]
		}
		return reasons[a] < reasons[b]
	})
	parts := make([]string, len(reasons))
	for i, r := range reasons {
		parts[i] = fmt.Sprintf("%s %d", r, counts[r])
	}
	return total, strings.Join(parts, ", ")
}
