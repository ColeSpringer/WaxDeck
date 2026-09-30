package service

// Health fixes. An unscoped fix of an enrichment-backed rule is the
// catalog's own pass over the phases that fill it, run as a job; a fix
// scoped to items, and every fix of path-mismatch or write-unsynced, is a
// health-fix tool task working item by item. Either ends by re-checking
// the rule for the items it covers, which the summary shows at once; the
// score waits for the next full sweep.

import (
	"cmp"
	"context"
	"encoding/json"
	"fmt"
	"math"
	"slices"
	"sort"
	"strings"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/enrich"
	"github.com/colespringer/waxbin/model"
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
	healthFixPathChunk = 500
)

// What an install lacks to fix a rule, as the summary's fixBlocked says it.
const (
	fixBlockedContact      = "needs-contact"
	fixBlockedLyricsSource = "needs-lyrics-source"
	fixBlockedArtSource    = "needs-art-source"
	fixBlockedGenreSource  = "needs-genre-source"
	fixBlockedBookSource   = "needs-book-source"
	fixBlockedNoManaged    = "no-managed-library"
)

// healthFixPhases are the catalog phases whose forced pass fills each
// enrichment-backed rule; a fix forces those this install runs. Genres
// ride the release-group walk, so fixing them re-asks MusicBrainz about
// every album.
var healthFixPhases = map[string][]model.EnrichPhase{
	ruleMissingLyrics:   {model.EnrichPhaseLyrics},
	ruleMissingArt:      {model.EnrichPhaseGroupArt, model.EnrichPhaseAlbumArt},
	ruleMissingGenre:    {model.EnrichPhaseReleaseGroup},
	ruleMissingNarrator: {model.EnrichPhaseBookFields},
	ruleMissingASIN:     {model.EnrichPhaseBookFields},
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
		return true, ""
	case rulePathMismatch:
		if !slices.ContainsFunc(l.libraryRoots(), func(r Root) bool { return r.Managed }) {
			return false, fixBlockedNoManaged
		}
		return true, ""
	}
	if _, ok := healthFixPhases[rule]; !ok {
		return false, ""
	}
	if len(l.runningFixPhases(rule)) == 0 {
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

// runningFixPhases are the phases among those that fill rule which this
// install runs: missing art is filled by either of its two pictures'
// phases, whichever has a source.
func (l *Library) runningFixPhases(rule string) []model.EnrichPhase {
	running := l.lib.EnrichmentPhases()
	var out []model.EnrichPhase
	for _, p := range healthFixPhases[rule] {
		if slices.Contains(running, p) {
			out = append(out, p)
		}
	}
	return out
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
	if fixable, _ := l.healthFixability(rule); !fixable {
		return HealthFixStartDTO{}, errInvalid("no automated fix for rule " + rule + " on this server")
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
	_, enrichBacked := healthFixPhases[rule]
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
		phases := l.runningFixPhases(rule)
		pid, err := l.startEnrichJob(ctx, uc, waxbin.EnrichOptions{ForcePhases: phases}, rule)
		if err != nil {
			if KindOf(classify(err)) == KindConflict {
				return HealthFixStartDTO{}, errEnrichBusy
			}
			return HealthFixStartDTO{}, l.explainEnrichRefusal(err, apiNames(phases))
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
		for i := 0; i < len(scope); i += healthFixPathChunk {
			if err := ctx.Err(); err != nil {
				return err
			}
			l.fixPaths(ctx, scope[i:min(i+healthFixPathChunk, len(scope))], &sum)
			prog.report(ctx, 100*float64(min(i+healthFixPathChunk, len(scope)))/float64(len(scope)))
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

// healthFixTaskEnded tells every account a fix task's rule is no longer
// being fixed, once the task's end is recorded, and its starter what it
// did or why it failed.
func (l *Library) healthFixTaskEnded(ctx context.Context, t *wdb.ToolTask) {
	var p toolTaskParams
	_ = json.Unmarshal([]byte(t.Params), &p)
	l.emitEveryoneEvent(ctx, eventHealth)
	body := "The fix failed: " + cmp.Or(t.Error, "no reason was recorded")
	if t.State == taskStateDone {
		var sum healthFixSummary
		if json.Unmarshal([]byte(t.Summary), &sum) == nil {
			body = healthFixBody(sum)
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
		// Re-editing the title to its current value, with WriteBack and
		// Force, rewrites the file's tags and clears the unsynced
		// diagnostic; Force only gets the no-op edit past a locked title.
		// It is not mark-free: an edit naming no source records a user
		// one, so the title then reads as hand-curated.
		if err := l.lib.EditFields(ctx, pid, map[string]string{"title": it.Title},
			waxbin.EditOptions{WriteBack: true, Force: true, Lock: model.LockUnchanged}); err != nil {
			sum.Failed++
			return
		}
		sum.Filled++
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

// fixPaths moves one chunk of path-mismatched items where the default
// profile places them, counting items rather than files: a book moves as
// all its parts, and fails if one of them does.
func (l *Library) fixPaths(ctx context.Context, pids []string, sum *healthFixSummary) {
	sum.Attempted += len(pids)
	plan, err := l.lib.PlanOrganize(ctx,
		query.New(query.EntityItems).WhereValues("pid", query.OpIn, query.Values(pids)...).Build(),
		l.defaultOrganizeProfile())
	if err != nil {
		sum.Failed += len(pids)
		return
	}
	rep, err := l.lib.ApplyOrganize(ctx, plan)
	// A run cut short has reached its actions in plan order.
	reached := len(plan.Actions)
	failedFiles := map[model.PID]bool{}
	if rep != nil {
		if err != nil {
			reached = rep.Moved + rep.Skipped + rep.Errored
		}
		for _, f := range rep.Failures {
			failedFiles[f.FilePID] = true
		}
	} else if err != nil {
		reached = 0
	}
	type outcome struct {
		moved, failed bool
		held          string
	}
	byItem := map[model.PID]*outcome{}
	for i, a := range plan.Actions {
		o := byItem[a.ItemPID]
		if o == nil {
			o = &outcome{}
			byItem[a.ItemPID] = o
		}
		switch {
		case i >= reached || failedFiles[a.FilePID]:
			o.failed = true
		case !a.Skip:
			o.moved = true
		case strings.HasPrefix(a.Reason, "destination collides"):
			o.held = "destination taken"
		case o.held == "":
			o.held = a.Reason
		}
	}
	for _, pid := range pids {
		o := byItem[model.PID(pid)]
		switch {
		case o == nil:
			// Planned for nothing: gone, or no longer under a managed root.
			sum.Skipped["not placed by organize"]++
		case o.failed:
			sum.Failed++
		case o.moved && o.held == "":
			sum.Filled++
		default:
			sum.Skipped[cmp.Or(o.held, "already in place")]++
		}
	}
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
	moves  map[model.PID]bool
	byPath map[string][]string
	lyrics map[model.PID]bool
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
		if in.moves, err = l.readPlannedMoves(ctx); err != nil {
			return res, err
		}
	case ruleWriteUnsynced:
		if in.byPath, err = l.fileDiagnosticRules(ctx); err != nil {
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
		return slices.Contains(l.itemFileRules(ctx, it, in.byPath), ruleWriteUnsynced)
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
// (no match 55, locked 5); 0 failed".
func healthFixBody(s healthFixSummary) string {
	body := fmt.Sprintf("Filled %d of %d", s.Filled, s.Attempted)
	if n := s.Attempted - s.Filled - s.Failed; n > 0 {
		reasons := make([]string, 0, len(s.Skipped))
		for r := range s.Skipped {
			reasons = append(reasons, r)
		}
		sort.Slice(reasons, func(a, b int) bool {
			if s.Skipped[reasons[a]] != s.Skipped[reasons[b]] {
				return s.Skipped[reasons[a]] > s.Skipped[reasons[b]]
			}
			return reasons[a] < reasons[b]
		})
		parts := make([]string, len(reasons))
		for i, r := range reasons {
			parts[i] = fmt.Sprintf("%s %d", r, s.Skipped[r])
		}
		body += fmt.Sprintf("; %d skipped (%s)", n, strings.Join(parts, ", "))
	}
	return body + fmt.Sprintf("; %d failed", s.Failed)
}
