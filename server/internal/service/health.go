package service

// Library health: the sweep that grades every item against the health
// rules, the issue index it maintains, the durable fix queue, and the
// duplicate and upgrade maintenance surfaces built on the catalog
// audit.
//
// Rule coverage notes. The spec names missing-mbid in the rule set; it
// is not implemented because the recording MBID is not reachable from
// here at sweep cost: model.ItemView carries no MBID, the store's query
// grammar (store/sqlite/fields.go) whitelists no mbid field, and the
// facade has no per-item identifier read. small-art rides along with
// missing-art for free: resolving art for that rule already loads the
// source blob, whose decoded dimensions come with it.

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/organize"
	"github.com/colespringer/waxbin/query"
	"github.com/colespringer/waxbin/read"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/genre"
)

const (
	// healthStateKey holds the sweep's aggregate JSON (healthState) in
	// the settings table; healthSweepReqKey is the off-schedule sweep
	// request flag the worker checks.
	healthStateKey    = "health:state"
	healthSweepReqKey = "health:sweep-requested"

	// healthSweepInterval is how stale the last sweep may get before
	// HealthSweepDue asks the worker for another.
	healthSweepInterval = 24 * time.Hour

	// fixMaxAttempts and fixLease bound the durable fix queue: a fix
	// out of attempts is pruned, and a crashed worker's lease expires.
	fixMaxAttempts = 5
	fixLease       = 2 * time.Minute

	// fixQueueDefaultScope caps how many failing items an un-scoped
	// bulk fix enqueues in one request.
	fixQueueDefaultScope = 10000

	// smallArtMinSide is the minimum width and height source art must
	// have to pass the small-art rule.
	smallArtMinSide = 500

	// releaseStatusBootleg is the second RELEASESTATUS value the
	// unofficial exemption honors (pre-tagged content; the review flow
	// itself only ever writes releaseStatusUnofficial).
	releaseStatusBootleg = "bootleg"
)

// Health rule names, exactly as the API spec spells them.
const (
	ruleMissingArt      = "missing-art"
	ruleSmallArt        = "small-art"
	ruleMissingYear     = "missing-year"
	ruleMissingGenre    = "missing-genre"
	ruleGenreWhitelist  = "genre-whitelist"
	ruleMissingLyrics   = "missing-lyrics"
	ruleMissingNarrator = "missing-narrator"
	ruleMissingASIN     = "missing-asin"
	rulePathMismatch    = "path-mismatch"
	ruleWriteUnsynced   = "write-unsynced"
	ruleLegacyTags      = "legacy-tags"
	ruleCorruptAudio    = "corrupt-audio"
)

// healthRules is every implemented rule, in the order the summary lists
// ties.
var healthRules = []string{
	ruleCorruptAudio, ruleMissingArt, ruleSmallArt, ruleMissingGenre,
	ruleGenreWhitelist, ruleMissingYear, ruleMissingLyrics, ruleMissingNarrator,
	ruleMissingASIN, rulePathMismatch, ruleWriteUnsynced, ruleLegacyTags,
}

var healthRuleLabels = map[string]string{
	ruleMissingArt:      "Missing cover art",
	ruleSmallArt:        "Low-resolution cover art",
	ruleMissingYear:     "Missing release year",
	ruleMissingGenre:    "Missing genre",
	ruleGenreWhitelist:  "Genre outside the canonical tree",
	ruleMissingLyrics:   "Missing lyrics",
	ruleMissingNarrator: "Missing narrator",
	ruleMissingASIN:     "Missing ASIN",
	rulePathMismatch:    "File path does not match the organize profile",
	ruleWriteUnsynced:   "File tags out of sync with the catalog",
	ruleLegacyTags:      "Legacy-only tags",
	ruleCorruptAudio:    "Corrupt audio",
}

// healthFixable names the rules the bulk-fix endpoint automates.
// missing-year is computable but has no per-item fix path (identity
// fields ride the whole-library enrichment pass), small-art would need
// the force-overwrite the fill-when-empty enrichment path refuses, and
// corrupt-audio plus legacy-tags have no automated fix at all.
// genre-whitelist is deliberately absent: the normalization sweeper
// already rewrites everything the vocabulary knows, continuously, so an
// item still flagged carries a genre the tree does not cover. The fix is
// an edit to the tree, not to the item, and a per-item button would only
// queue no-op work.
var healthFixable = map[string]bool{
	ruleMissingArt: true, ruleMissingLyrics: true, ruleMissingGenre: true,
	ruleMissingNarrator: true, ruleMissingASIN: true,
	rulePathMismatch: true, ruleWriteUnsynced: true,
}

// healthRuleWeight is a rule's contribution to an item's failure
// weight: corrupt audio is the worst thing that can be true of a file,
// missing art is the most visible gap, everything else weighs one.
func healthRuleWeight(rule string) float64 {
	switch rule {
	case ruleCorruptAudio:
		return 3
	case ruleMissingArt:
		return 2
	default:
		return 1
	}
}

// itemFailWeightCap caps one item's summed rule weights, so the score
// reads as "share of items in good shape" rather than letting one
// thoroughly broken item swing it.
const itemFailWeightCap = 3.0

// healthState is the aggregate JSON stored under healthStateKey.
type healthState struct {
	Score          float64 `json:"score"`
	TotalItems     int     `json:"totalItems"`
	EvaluatedItems int     `json:"evaluatedItems"`
	SweptAtNS      int64   `json:"sweptAtNs"`
}

// HealthRuleCountDTO is one rule's standing for the API.
type HealthRuleCountDTO struct {
	Rule    string
	Label   string
	Failing int
	Fixable bool
}

// HealthSummaryDTO is the health dashboard aggregate.
type HealthSummaryDTO struct {
	Score          float64
	TotalItems     int
	EvaluatedItems int
	SweptAt        time.Time
	WarmingUp      bool
	Rules          []HealthRuleCountDTO
}

// HealthIssueDTO is one failing item with the rules it fails.
type HealthIssueDTO struct {
	PID       string
	MediaType string
	Title     string
	Artist    string
	Rules     []string
}

// DuplicateEntityDTO is one member of a duplicate group.
type DuplicateEntityDTO struct {
	PID  string
	Name string
}

// DuplicateGroupDTO is one duplicate finding, survivor first.
type DuplicateGroupDTO struct {
	EntityType string
	Detail     string
	Survivor   DuplicateEntityDTO
	Losers     []DuplicateEntityDTO
}

// MergeResultDTO is a duplicate merge outcome.
type MergeResultDTO struct {
	Merged        int
	ChildrenMoved int
}

// UpgradeMemberDTO is one encoding of a recording.
type UpgradeMemberDTO struct {
	ItemPID    string
	Title      string
	Artist     string
	Codec      string
	Bitrate    int
	SampleRate int
	BitDepth   int
	Lossless   bool
	Best       bool
}

// UpgradeGroupDTO is one recording's encodings, best first.
type UpgradeGroupDTO struct {
	Members []UpgradeMemberDTO
}

// duplicateGroupCap bounds the duplicates listing, per the spec.
const duplicateGroupCap = 200

// SweepHealth walks the whole library once, stores each failing item's
// rules in the health index, prunes rows the pass did not touch (items
// now clean, deleted, or newly exempt), and writes the aggregate state.
// It runs synchronously; the main-registered health worker calls it on
// its ticker (see HealthSweepDue), never a bare goroutine.
func (l *Library) SweepHealth(ctx context.Context) error {
	sweepStart := time.Now().UnixNano()

	unofficial, err := l.unofficialItems(ctx)
	if err != nil {
		return err
	}
	fileRules, err := l.fileDiagnosticRules(ctx)
	if err != nil {
		return err
	}
	lyricsPresent, err := l.lyricsPresence(ctx)
	if err != nil {
		// A bulk-lyrics-query failure skips the missing-lyrics rule this sweep
		// (nil map = "unknown" to itemHealthRules) rather than aborting every
		// other rule for every item; the periodic sweep re-runs and catches up.
		l.log.Warn("health: bulk lyrics presence unavailable; skipping missing-lyrics this sweep", "err", err)
		lyricsPresent = nil
	}
	moves := l.plannedMoves(ctx)
	// The genre vocabulary is loaded once for the whole sweep. A failure
	// leaves it nil, which skips genre-whitelist for this pass rather
	// than aborting every other rule for every item.
	norm, err := l.genreNormalizer(ctx)
	if err != nil {
		l.log.Warn("health: genre vocabulary unavailable; skipping genre-whitelist this sweep", "err", err)
		norm = nil
	}

	var evaluated int
	var failWeight float64
	// Only present items are in scope: archived, missing, and remote
	// items have no local file to grade.
	q := query.New(query.EntityItems).Where("state", query.OpIs, string(model.StatePresent)).Build()
	cursor := read.Cursor("")
	for {
		page, err := l.lib.QueryPage(ctx, q, cursor, 500, false, "")
		if err != nil {
			return classify(err)
		}
		for _, it := range page.Items {
			rules := l.itemHealthRules(ctx, it, unofficial[it.PID], fileRules[it.DisplayPath], moves[it.PID], lyricsPresent, norm)
			evaluated++
			if len(rules) == 0 {
				continue
			}
			w := 0.0
			for _, r := range rules {
				w += healthRuleWeight(r)
			}
			failWeight += min(w, itemFailWeightCap) / itemFailWeightCap
			raw, err := json.Marshal(rules)
			if err != nil {
				return &Error{Kind: KindInternal, Err: err}
			}
			if err := l.db.UpsertHealthRow(ctx, wdb.HealthRow{
				ItemPID:   string(it.PID),
				MediaType: mediaTypeForKind(it.Kind),
				Title:     it.Title,
				Artist:    it.Artist,
				Rules:     string(raw),
				RuleCount: len(rules),
				SweptAtNS: sweepStart,
			}); err != nil {
				return &Error{Kind: KindInternal, Err: err}
			}
		}
		if !page.HasMore {
			break
		}
		cursor = page.Next
	}
	if _, err := l.db.PruneHealthRows(ctx, sweepStart); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}

	// Score: 100 * (1 - weightedFailShare). Each item contributes
	// min(sum of its failed rules' weights, itemFailWeightCap) divided
	// by the cap, so a clean item contributes 0, a thoroughly broken
	// one contributes 1, and the score is the weighted share of
	// evaluated items passing every rule that applies to them.
	score := 100.0
	if evaluated > 0 {
		score = 100 * (1 - failWeight/float64(evaluated))
	}
	state := healthState{
		Score:          score,
		TotalItems:     evaluated,
		EvaluatedItems: evaluated,
		SweptAtNS:      time.Now().UnixNano(),
	}
	raw, err := json.Marshal(state)
	if err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	if err := l.db.SettingSet(ctx, healthStateKey, string(raw), time.Now().UnixNano()); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	return nil
}

// itemHealthRules grades one item. Unofficial-marked items (and podcast
// episodes, which are not canonical-release content either) answer only
// for corrupt audio and unsynced tag writes.
func (l *Library) itemHealthRules(ctx context.Context, it *model.ItemView, exempt bool, fileRules []string, planned bool, lyricsPresent map[model.PID]bool, norm *genre.Normalizer) []string {
	var rules []string
	for _, r := range fileRules {
		if (exempt || it.Kind == model.KindEpisode) && r == ruleLegacyTags {
			continue
		}
		rules = append(rules, r)
	}
	if exempt || it.Kind == model.KindEpisode {
		return rules
	}

	// Art: the item resolver serves tracks and books alike, walking the
	// fallback chain to album and artist art. Size 0 returns the source
	// blob, whose dimensions also answer small-art.
	blob, err := l.lib.ResolveArt(ctx, model.EntityRef{Type: model.ArtTrack, PID: it.PID}, model.ArtRoleFront, 0)
	switch {
	case err == nil:
		if blob.Width > 0 && blob.Height > 0 && (blob.Width < smallArtMinSide || blob.Height < smallArtMinSide) {
			rules = append(rules, ruleSmallArt)
		}
	case KindOf(classify(err)) == KindNotFound:
		rules = append(rules, ruleMissingArt)
	default:
		// A degraded art store never fails the item; the rule just
		// skips this sweep.
		l.log.Warn("health: resolving art", "item", it.PID, "err", err)
	}

	// Every genre-carrying kind is graded against the canonical
	// vocabulary, books included: a book's genre rides the same scalar
	// and the same browse dimension a track's does.
	if len(offTreeGenres(norm, it.Genre)) > 0 {
		rules = append(rules, ruleGenreWhitelist)
	}

	switch it.Kind {
	case model.KindTrack:
		if it.Genre == "" {
			rules = append(rules, ruleMissingGenre)
		}
		if it.Year == 0 {
			rules = append(rules, ruleMissingYear)
		}
		// Lyrics presence comes from the bulk has_lyrics pass, so the sweep
		// reads no lyrics per music item. A nil map means that pass failed
		// this sweep: skip the rule rather than flag every track (an empty
		// non-nil map is a real "no track has lyrics" and flags them all).
		if lyricsPresent != nil && !lyricsPresent[it.PID] {
			rules = append(rules, ruleMissingLyrics)
		}
	case model.KindBook:
		if it.Narrator == "" {
			rules = append(rules, ruleMissingNarrator)
		}
		if it.ASIN == "" {
			rules = append(rules, ruleMissingASIN)
		}
	}
	if planned {
		rules = append(rules, rulePathMismatch)
	}
	return rules
}

// lyricsPresence builds the set of music items carrying their own lyrics
// in one paginated pass over the query engine's has_lyrics field, so the
// sweep grades missing-lyrics from a set lookup instead of a Lyrics point
// read per item. (has_lyrics is item-own, matching the point read it
// replaces; the art rules stay on ResolveArt, which walks the fallback
// chain that the own-only has_art field cannot express.)
func (l *Library) lyricsPresence(ctx context.Context) (map[model.PID]bool, error) {
	present := make(map[model.PID]bool)
	q := query.New(query.EntityItems).
		Where("kind", query.OpIs, string(model.KindTrack)).
		Where("has_lyrics", query.OpIs, 1).Build()
	cursor := read.Cursor("")
	for {
		page, err := l.lib.QueryPage(ctx, q, cursor, 500, false, "")
		if err != nil {
			return nil, classify(err)
		}
		for _, it := range page.Items {
			present[it.PID] = true
		}
		if !page.HasMore {
			break
		}
		cursor = page.Next
	}
	return present, nil
}

// unofficialItems collects the pids carrying the RELEASESTATUS
// unofficial or bootleg custom tag, in one query per value rather than
// one ItemTags read per item.
func (l *Library) unofficialItems(ctx context.Context) (map[model.PID]bool, error) {
	out := map[model.PID]bool{}
	for _, v := range []string{releaseStatusUnofficial, releaseStatusBootleg} {
		items, err := l.lib.Query(ctx, query.New(query.EntityItems).
			Where("tag."+releaseStatusKey, query.OpIs, v).Build(), "")
		if err != nil {
			return nil, classify(err)
		}
		for _, it := range items {
			out[it.PID] = true
		}
	}
	return out, nil
}

// fileDiagnosticRules runs the audit's persisted-diagnostic checks once
// per sweep and buckets the findings by file path (these findings carry
// the path, not the item pid, so the sweep matches them against each
// item's display path). The finding message is "code: path[: detail]"
// by upstream construction (audit diagMessage), so the leading code
// word selects the rule. Sample is raised well past the audit default
// of fifty so a large library is not truncated.
func (l *Library) fileDiagnosticRules(ctx context.Context) (map[string][]string, error) {
	rep, err := l.lib.Audit(ctx, waxbin.AuditOptions{
		Only:   []model.AuditCheck{model.CheckFileDiagnostic, model.CheckCorruptAudio},
		Sample: 1 << 20,
	})
	if err != nil {
		return nil, classify(err)
	}
	out := map[string][]string{}
	add := func(path, rule string) {
		for _, r := range out[path] {
			if r == rule {
				return
			}
		}
		out[path] = append(out[path], rule)
	}
	for _, f := range rep.Findings {
		if f.Path == "" {
			continue // capped-summary rows carry no path
		}
		switch f.Check {
		case model.CheckCorruptAudio:
			add(f.Path, ruleCorruptAudio)
		case model.CheckFileDiagnostic:
			code, _, _ := strings.Cut(f.Message, ":")
			switch model.DiagnosticCode(strings.TrimSpace(code)) {
			case model.DiagTagWriteUnsynced, model.DiagTagWriteLost:
				add(f.Path, ruleWriteUnsynced)
			case model.DiagLegacyOnlyTags:
				add(f.Path, ruleLegacyTags)
			}
		}
	}
	return out, nil
}

// plannedMoves plans the default organize profile across the library
// and returns the items a pass would move, backing the path-mismatch
// rule. Best-effort: a server with no managed library (in-place roots
// only) has no canonical layout to mismatch, so the rule is skipped.
func (l *Library) plannedMoves(ctx context.Context) map[model.PID]bool {
	if len(l.lib.Profiles()) == 0 {
		return nil
	}
	plan, err := l.lib.PlanOrganize(ctx, query.New(query.EntityItems).Build(), l.defaultOrganizeProfile())
	if err != nil {
		l.log.Debug("health: organize plan for path-mismatch", "err", err)
		return nil
	}
	out := map[model.PID]bool{}
	for i := range plan.Actions {
		a := &plan.Actions[i]
		if !a.Skip && a.ItemPID != "" {
			out[a.ItemPID] = true
		}
	}
	return out
}

// defaultOrganizeProfile picks the profile the sweep and the per-item
// path fix plan with: the upstream default when present, else the first
// configured name.
func (l *Library) defaultOrganizeProfile() string {
	names := l.lib.Profiles()
	for _, n := range names {
		if n == organize.DefaultProfileName {
			return n
		}
	}
	if len(names) > 0 {
		return names[0]
	}
	return ""
}

// HealthSummaryFor reads the dashboard aggregate: the stored sweep
// state (absent means the first sweep has not landed, reported as
// warming up) plus live per-rule counts from the health index.
func (l *Library) HealthSummaryFor(ctx context.Context) (HealthSummaryDTO, error) {
	out := HealthSummaryDTO{WarmingUp: true}
	raw, err := l.db.SettingGet(ctx, healthStateKey)
	switch {
	case err == nil:
		var st healthState
		if jerr := json.Unmarshal([]byte(raw), &st); jerr == nil {
			out.Score = st.Score
			out.TotalItems = st.TotalItems
			out.EvaluatedItems = st.EvaluatedItems
			out.SweptAt = time.Unix(0, st.SweptAtNS).UTC()
			out.WarmingUp = false
		}
	case errors.Is(err, wdb.ErrNotFound):
		// Warming up: zero counts, provisional score.
	default:
		return HealthSummaryDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	counts, err := l.db.HealthRuleCounts(ctx)
	if err != nil {
		return HealthSummaryDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	for _, rule := range healthRules {
		out.Rules = append(out.Rules, HealthRuleCountDTO{
			Rule:    rule,
			Label:   healthRuleLabels[rule],
			Failing: counts[rule],
			Fixable: healthFixable[rule],
		})
	}
	sort.SliceStable(out.Rules, func(i, j int) bool {
		return out.Rules[i].Failing > out.Rules[j].Failing
	})
	return out, nil
}

// ListHealthIssuesFor pages failing items worst first, optionally
// restricted to one rule.
func (l *Library) ListHealthIssuesFor(ctx context.Context, rule, cursor string, limit int) ([]HealthIssueDTO, string, error) {
	afterCount, afterTitle, afterPID := 0, "", ""
	if cursor != "" {
		c, t, p, ok := decodeHealthCursor(cursor)
		if !ok {
			return nil, "", errInvalid("malformed cursor")
		}
		afterCount, afterTitle, afterPID = c, t, p
	}
	rows, err := l.db.ListHealthRows(ctx, rule, afterCount, afterTitle, afterPID, limit+1)
	if err != nil {
		return nil, "", &Error{Kind: KindInternal, Err: err}
	}
	next := ""
	if len(rows) > limit {
		rows = rows[:limit]
		last := rows[len(rows)-1]
		next = encodeHealthCursor(last.RuleCount, last.Title, last.ItemPID)
	}
	out := make([]HealthIssueDTO, 0, len(rows))
	for _, r := range rows {
		var rules []string
		if jerr := json.Unmarshal([]byte(r.Rules), &rules); jerr != nil {
			rules = nil
		}
		out = append(out, HealthIssueDTO{
			PID:       healthAPIPID(r.MediaType, r.ItemPID),
			MediaType: r.MediaType,
			Title:     r.Title,
			Artist:    r.Artist,
			Rules:     rules,
		})
	}
	return out, next, nil
}

// healthAPIPID renders a stored bare item pid with the API prefix its
// media type implies.
func healthAPIPID(mediaType, pid string) string {
	kind, ok := kindForMediaType(mediaType)
	if !ok {
		kind = model.KindTrack
	}
	return apiPID(prefixForKind(kind), model.PID(pid))
}

// encodeHealthCursor renders the issues listing's three-part keyset
// cursor: ruleCount, base64url(title) (titles are free text), and the
// bare item pid, dot-separated. The base64url alphabet and the other
// two parts are dot-free, so parsing is a strict three-way split.
func encodeHealthCursor(count int, title, pid string) string {
	return strconv.Itoa(count) + "." + base64.RawURLEncoding.EncodeToString([]byte(title)) + "." + pid
}

// decodeHealthCursor strictly parses an issues cursor; ok is false for
// anything encodeHealthCursor did not produce.
func decodeHealthCursor(s string) (count int, title, pid string, ok bool) {
	parts := strings.Split(s, ".")
	if len(parts) != 3 || parts[2] == "" {
		return 0, "", "", false
	}
	n, err := strconv.Atoi(parts[0])
	if err != nil || n < 0 {
		return 0, "", "", false
	}
	raw, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return 0, "", "", false
	}
	if !model.PID(parts[2]).Valid() {
		return 0, "", "", false
	}
	return n, string(raw), parts[2], true
}

// QueueHealthSweep flags an off-schedule full sweep. The 202 answers
// immediately; the main-registered health worker sees the flag on its
// next tick and runs SweepHealth.
func (l *Library) QueueHealthSweep(ctx context.Context, uc *UserCtx) error {
	if !uc.Admin {
		return &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	if err := l.db.SettingSet(ctx, healthSweepReqKey, "1", time.Now().UnixNano()); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	return nil
}

// SweepRequested reports whether an admin has asked for an off-schedule
// sweep.
func (l *Library) SweepRequested(ctx context.Context) bool {
	v, err := l.db.SettingGet(ctx, healthSweepReqKey)
	return err == nil && v == "1"
}

// ClearSweepRequest drops the off-schedule sweep flag; the worker calls
// it after a sweep completes.
func (l *Library) ClearSweepRequest(ctx context.Context) {
	if err := l.db.SettingDelete(ctx, healthSweepReqKey); err != nil {
		l.log.Warn("health: clearing sweep request", "err", err)
	}
}

// HealthSweepDue reports whether the main-registered health worker
// should sweep now: an explicit request is pending, no sweep has ever
// completed, or the last one is older than healthSweepInterval. Main's
// ticker loop calls this, then SweepHealth and ClearSweepRequest, all
// synchronously on the supervised worker.
func (l *Library) HealthSweepDue(ctx context.Context) bool {
	if l.SweepRequested(ctx) {
		return true
	}
	raw, err := l.db.SettingGet(ctx, healthStateKey)
	if err != nil {
		return true // never swept (or unreadable state): sweep
	}
	var st healthState
	if jerr := json.Unmarshal([]byte(raw), &st); jerr != nil {
		return true
	}
	return time.Since(time.Unix(0, st.SweptAtNS)) > healthSweepInterval
}

// QueueHealthFix enqueues the fix matching one rule for the named items
// (or for everything currently failing the rule) on the durable fix
// queue. Re-queueing an already queued (item, rule) is a no-op upstream
// but still counts as queued here, since the work is pending either
// way.
func (l *Library) QueueHealthFix(ctx context.Context, uc *UserCtx, rule string, itemPids []string) (int, error) {
	if !uc.Admin {
		return 0, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	if !healthFixable[rule] {
		return 0, errInvalid("no automated fix for rule " + rule)
	}
	var bare []string
	if len(itemPids) > 0 {
		for _, p := range itemPids {
			prefix, pid, ok := parseAPIPID(p)
			if !ok || !itemPrefix(prefix) {
				return 0, errInvalid("bad item pid " + p)
			}
			bare = append(bare, string(pid))
		}
	} else {
		pids, err := l.db.FailingItems(ctx, rule, fixQueueDefaultScope)
		if err != nil {
			return 0, &Error{Kind: KindInternal, Err: err}
		}
		bare = pids
	}
	for _, pid := range bare {
		if err := l.db.EnqueueFix(ctx, pid, rule); err != nil {
			return 0, &Error{Kind: KindInternal, Err: err}
		}
	}
	return len(bare), nil
}

// DrainFixQueue works one queued health fix; false means the queue is
// idle. The main-registered fix worker loops it at provider-etiquette
// pace. A permanent failure (the item is gone, the rule has no path
// forward) completes the row with a log line; a transient one backs the
// row off for a retry.
func (l *Library) DrainFixQueue(ctx context.Context) bool {
	now := time.Now()
	row, err := l.db.LeaseFix(ctx, now.UnixNano(), fixLease.Nanoseconds(), fixMaxAttempts)
	if err != nil {
		if !errors.Is(err, wdb.ErrNotFound) {
			l.log.Warn("health: leasing fix", "err", err)
		}
		return false
	}
	ferr := l.runHealthFix(ctx, row)
	switch {
	case ferr == nil:
		if err := l.db.CompleteFix(ctx, row.ID); err != nil {
			l.log.Warn("health: completing fix", "id", row.ID, "err", err)
		}
	case KindOf(ferr) == KindInvalid || KindOf(ferr) == KindNotFound:
		l.log.Warn("health: fix dropped", "item", row.ItemPID, "rule", row.Rule, "err", ferr)
		if err := l.db.CompleteFix(ctx, row.ID); err != nil {
			l.log.Warn("health: completing fix", "id", row.ID, "err", err)
		}
	default:
		retry := now.Add(queueRetryDelay(row.Attempts + 1))
		if err := l.db.FailFix(ctx, row.ID, ferr.Error(), retry.UnixNano()); err != nil {
			l.log.Warn("health: recording fix failure", "id", row.ID, "err", err)
		}
	}
	return true
}

// runHealthFix executes one leased fix. The enrichment-backed fixes
// share EnrichItemNow with the editor's per-item endpoint; a run whose
// providers found nothing still completes (the item shows again on the
// next sweep, and re-fixing without new providers cannot do better).
func (l *Library) runHealthFix(ctx context.Context, row wdb.FixQueueRow) error {
	pid := model.PID(row.ItemPID)
	switch row.Rule {
	case ruleMissingArt:
		_, _, err := l.EnrichItemNow(ctx, pid, []string{enrichWantCover})
		return err
	case ruleMissingLyrics:
		_, _, err := l.EnrichItemNow(ctx, pid, []string{enrichWantLyrics})
		return err
	case ruleMissingGenre:
		_, _, err := l.EnrichItemNow(ctx, pid, []string{enrichWantGenres})
		return err
	case ruleMissingNarrator, ruleMissingASIN:
		_, _, err := l.EnrichItemNow(ctx, pid, []string{enrichWantBook})
		return err
	case rulePathMismatch:
		// Re-plan scoped to this one item (the query grammar has a pid
		// field) and apply the move.
		plan, err := l.lib.PlanOrganize(ctx,
			query.New(query.EntityItems).Where("pid", query.OpIs, string(pid)).Build(),
			l.defaultOrganizeProfile())
		if err != nil {
			return classify(err)
		}
		if _, err := l.lib.ApplyOrganize(ctx, plan); err != nil {
			return classify(err)
		}
		return nil
	case ruleWriteUnsynced:
		// Retry the write-back by re-editing the title to its current
		// value with WriteBack and Force: the catalog edit is a no-op,
		// but it forces a tag rewrite of the backing file, and a
		// successful write-back clears the unsynced diagnostic
		// upstream. Lock stays off so the fix leaves no curation marks.
		it, err := l.lib.Get(ctx, pid)
		if err != nil {
			return classify(err)
		}
		if err := l.lib.EditFields(ctx, pid, map[string]string{"title": it.Title},
			waxbin.EditOptions{WriteBack: true, Force: true}); err != nil {
			return classify(err)
		}
		return nil
	default:
		return errInvalid("no automated fix for rule " + row.Rule)
	}
}

// ListDuplicateGroups runs the catalog's duplicate audits and maps the
// findings to merge-ready groups, survivor first, capped at
// duplicateGroupCap.
func (l *Library) ListDuplicateGroups(ctx context.Context, uc *UserCtx) ([]DuplicateGroupDTO, error) {
	if !uc.Admin {
		return nil, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	rep, err := l.lib.Audit(ctx, waxbin.AuditOptions{
		Only: []model.AuditCheck{model.CheckDuplicateArtist, model.CheckDuplicateAlbum, model.CheckDuplicateGenre},
	})
	if err != nil {
		return nil, classify(err)
	}
	out := []DuplicateGroupDTO{}
	for _, f := range rep.Findings {
		if f.MergeType == "" || len(f.Entities) < 2 {
			continue
		}
		if len(out) >= duplicateGroupCap {
			break
		}
		names := duplicateNamesFromMessage(f.Message, len(f.Entities))
		g := DuplicateGroupDTO{
			EntityType: strings.ReplaceAll(string(f.MergeType), "_", "-"),
			Detail:     f.Message,
			Survivor:   DuplicateEntityDTO{PID: string(f.Entities[0]), Name: names[0]},
			Losers:     make([]DuplicateEntityDTO, 0, len(f.Entities)-1),
		}
		for i, pid := range f.Entities[1:] {
			g.Losers = append(g.Losers, DuplicateEntityDTO{PID: string(pid), Name: names[i+1]})
		}
		out = append(out, g)
	}
	return out, nil
}

// duplicateNamesFromMessage recovers member display names from the
// audit finding's message, which upstream renders as
// "duplicate <type> (<reason>): A / B; merge with `waxbin merge`" with
// names in entity order. Best-effort: a name containing " / " defeats
// the split, in which case every name stays empty rather than being
// misattributed.
func duplicateNamesFromMessage(msg string, n int) []string {
	names := make([]string, n)
	_, rest, ok := strings.Cut(msg, "): ")
	if !ok {
		return names
	}
	if i := strings.LastIndex(rest, "; merge with"); i >= 0 {
		rest = rest[:i]
	}
	parts := strings.Split(rest, " / ")
	if len(parts) != n {
		return names
	}
	return parts
}

// MergeDuplicates merges the losers into the survivor atomically.
func (l *Library) MergeDuplicates(ctx context.Context, uc *UserCtx, entityType, survivorPid string, loserPids []string) (MergeResultDTO, error) {
	if !uc.Admin {
		return MergeResultDTO{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	var met model.MergeEntity
	switch entityType {
	case "artist":
		met = model.MergeArtist
	case "album":
		met = model.MergeAlbum
	case "release-group":
		met = model.MergeReleaseGroup
	case "genre":
		met = model.MergeGenre
	default:
		return MergeResultDTO{}, errInvalid("unknown entity type " + entityType)
	}
	if len(loserPids) == 0 {
		return MergeResultDTO{}, errInvalid("loserPids are required")
	}
	survivor, ok := bareEntityPID(survivorPid)
	if !ok {
		return MergeResultDTO{}, errInvalid("bad entity pid " + survivorPid)
	}
	losers := make([]model.PID, 0, len(loserPids))
	for _, p := range loserPids {
		pid, ok := bareEntityPID(p)
		if !ok {
			return MergeResultDTO{}, errInvalid("bad entity pid " + p)
		}
		if pid == survivor {
			return MergeResultDTO{}, errInvalid("survivorPid cannot also be a loser")
		}
		losers = append(losers, pid)
	}
	reports, err := l.lib.MergeMany(ctx, met, survivor, losers)
	if err != nil {
		return MergeResultDTO{}, classify(err)
	}
	res := MergeResultDTO{Merged: len(reports)}
	for _, r := range reports {
		res.ChildrenMoved += r.Children
	}
	l.Audit(ctx, uc, "entity.merge",
		AuditTarget{Kind: entityType, PID: survivorPid},
		map[string]any{"losers": loserPids, "childrenMoved": res.ChildrenMoved})
	return res, nil
}

// bareEntityPID accepts both the bare catalog pids the duplicates
// listing returns (albums, release groups, and genres have no API
// prefix scheme) and a prefixed API pid, yielding the bare pid.
func bareEntityPID(s string) (model.PID, bool) {
	if _, pid, ok := parseAPIPID(s); ok {
		return pid, true
	}
	pid := model.PID(s)
	return pid, pid.Valid()
}

// ListUpgradeGroups reports same-recording different-encoding groups
// from the fingerprint index, best quality first within each group.
func (l *Library) ListUpgradeGroups(ctx context.Context, uc *UserCtx) ([]UpgradeGroupDTO, error) {
	if !uc.Admin {
		return nil, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	groups, err := l.lib.FindUpgrades(ctx)
	if err != nil {
		return nil, classify(err)
	}
	out := make([]UpgradeGroupDTO, 0, len(groups))
	for _, g := range groups {
		dg := UpgradeGroupDTO{Members: make([]UpgradeMemberDTO, 0, len(g.Members))}
		for _, m := range g.Members {
			// Upgrade groups are track-only upstream (FindUpgrades
			// queries the tracks entity), so the prefix is fixed.
			dg.Members = append(dg.Members, UpgradeMemberDTO{
				ItemPID:    apiPID(PrefixTrack, m.ItemPID),
				Title:      m.Title,
				Artist:     m.Artist,
				Codec:      m.Codec,
				Bitrate:    m.Bitrate,
				SampleRate: m.SampleRate,
				BitDepth:   m.BitDepth,
				Lossless:   m.Lossless,
				Best:       m.Best,
			})
		}
		out = append(out, dg)
	}
	return out, nil
}

// ResolveUpgrade keeps one item and moves the named inferior encodings
// to the trash (recoverable within the retention window).
func (l *Library) ResolveUpgrade(ctx context.Context, uc *UserCtx, keepPid string, removePids []string) (int, error) {
	if !uc.Admin {
		return 0, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	keepPrefix, keep, ok := parseAPIPID(keepPid)
	if !ok || !itemPrefix(keepPrefix) {
		return 0, errInvalid("bad item pid " + keepPid)
	}
	if len(removePids) == 0 {
		return 0, errInvalid("removeItemPids are required")
	}
	removes := make([]model.PID, 0, len(removePids))
	for _, p := range removePids {
		prefix, pid, ok := parseAPIPID(p)
		if !ok || !itemPrefix(prefix) {
			return 0, errInvalid("bad item pid " + p)
		}
		if pid == keep {
			return 0, errInvalid("keepItemPid cannot also be removed")
		}
		removes = append(removes, pid)
	}
	// Verify the keeper exists so a typo answers not-found before
	// anything moves.
	if _, err := l.lib.Get(ctx, keep); err != nil {
		return 0, classify(err)
	}
	plan, err := l.lib.PlanDeletePIDs(ctx, removes, model.DeleteTrash)
	if err != nil {
		return 0, classify(err)
	}
	rep, err := l.lib.ApplyDelete(ctx, plan)
	if err != nil {
		return 0, classify(err)
	}
	l.Audit(ctx, uc, "items.delete",
		AuditTarget{Kind: "item", PID: keepPid},
		map[string]any{"reason": "quality-upgrade", "removed": removePids, "trashed": rep.Trashed})
	return rep.Trashed, nil
}
