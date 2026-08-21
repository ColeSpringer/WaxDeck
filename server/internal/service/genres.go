package service

// Genre normalization: the canonical vocabulary an instance runs on, the
// continuous sweeper that folds newly scanned tags onto it, and the
// full-catalog pass exposed as a tool task.
//
// The shape is unusual for this codebase, and deliberately so. Genres
// read from file tags never pass through WaxDeck: the catalog's scanner
// resolves and stores them itself, so there is no ingest hook to
// normalize at. Enrichment is the only path WaxDeck owns, and it fires
// only for an item with no genre at all. Normalization therefore has to
// run continuously over the catalog, or a library scanned tomorrow is
// unnormalized again.
//
// What normalization does and does not fix. Rewriting an item's genre
// scalar changes which genre entity the item links to, so a "Rap" tag
// rewritten to "Hip Hop" moves the item onto the Hip Hop row: that is the
// synonym case, and it is real data movement. It does not rename an
// existing genre row - the catalog folds "hip hop" and "Hip Hop" onto one
// row whose display name is whichever spelling was scanned first, and
// offers no way to rename it. WaxDeck therefore owns the label: every
// surface that shows a genre bucket resolves its name through the same
// vocabulary (see facetBuckets), so the canonical spelling wins whatever
// the catalog stored.

import (
	"context"
	"encoding/json"
	"fmt"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/oklog/ulid/v2"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
	"github.com/colespringer/waxbin/read"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/genre"
)

const (
	// genreSweepCursorKey holds the catalog change seq the continuous
	// sweeper has normalized through.
	genreSweepCursorKey = "genre-normalize-cursor"

	// genreSweepBatch bounds how many distinct items one sweeper pass
	// normalizes. A first run over a large catalog would otherwise walk
	// the whole retained change log in one tick; the worker loops while
	// the report says there is more.
	genreSweepBatch = 500

	// taskTypeGenreNormalize is the full-catalog pass on the tool-task
	// framework, with the dry-run-then-apply shape the importer uses.
	taskTypeGenreNormalize = "genre-normalize"

	// genreSampleCap bounds the examples a normalization report carries;
	// the counts stay exact.
	genreSampleCap = 20
)

// genreVocabulary caches the built normalizer. The tree changes only
// through PutGenreTree, which drops the cache, so a sweep pays one load.
type genreVocabulary struct {
	mu   sync.Mutex
	norm *genre.Normalizer
	// source is the vocabulary actually in force, which is not always the
	// one that is stored: a stored tree that no longer builds degrades to
	// the shipped default, and the surface has to report what is really
	// resolving names rather than what happens to be in the table.
	source string
	valid  bool
	// version counts vocabulary changes. Anything caching a value derived
	// from the vocabulary keys on it, because a vocabulary edit writes no
	// catalog state and so moves nothing else those caches watch. Atomic
	// rather than guarded by mu so a reader can sample it without
	// contending with a load that is hitting the database.
	version atomic.Int64
}

// GenreNodeDTO is one genre in the vocabulary for the API layer.
type GenreNodeDTO struct {
	Name    string
	Parent  string
	Aliases []string
}

// GenreTreeDTO is the whole vocabulary plus where it came from.
type GenreTreeDTO struct {
	// Source is "default" while the instance runs on the shipped tree,
	// "custom" once an administrator has stored one.
	Source string
	Genres []GenreNodeDTO
}

// GenreSweepReport is one continuous-sweeper pass.
type GenreSweepReport struct {
	// Scanned counts items the pass looked at, Normalized the ones whose
	// genre scalar it rewrote, Locked the ones whose genre a user had
	// locked, and Unmapped the ones carrying at least one genre the
	// vocabulary does not know (left as they are).
	Scanned    int
	Normalized int
	Locked     int
	Unmapped   int
	// More reports that the change log holds further work, so the worker
	// should loop instead of waiting for its next tick.
	More bool
}

// genreNormalizeSummary is the full-pass tool task's stored report.
type genreNormalizeSummary struct {
	DryRun     bool `json:"dryRun"`
	Scanned    int  `json:"scanned"`
	Normalized int  `json:"normalized"`
	Locked     int  `json:"locked"`
	Unmapped   int  `json:"unmapped"`
	// Samples carries bounded examples: rewrites as "before -> after",
	// and the genre names the vocabulary did not cover.
	Samples genreNormalizeSamples `json:"samples"`
}

type genreNormalizeSamples struct {
	Changes  []string `json:"changes,omitempty"`
	Unmapped []string `json:"unmapped,omitempty"`
}

// genreNormalizer returns the instance's vocabulary, building it from
// the stored tree or, when none is stored, from the shipped default. A
// stored tree that no longer builds (hand-edited into a contradiction
// through the database rather than the API) degrades to the default
// rather than taking normalization down with it.
func (l *Library) genreNormalizer(ctx context.Context) (*genre.Normalizer, error) {
	norm, _, err := l.genreVocabularyInForce(ctx)
	return norm, err
}

// genreVocabularyInForce returns the built vocabulary and which one it
// is ("default" or "custom"). The two travel together because they can
// disagree with the table: a stored tree that no longer builds resolves
// nothing, so the default is what is really in force and that is what
// the surface must report.
func (l *Library) genreVocabularyInForce(ctx context.Context) (*genre.Normalizer, string, error) {
	l.genres.mu.Lock()
	defer l.genres.mu.Unlock()
	if l.genres.valid {
		return l.genres.norm, l.genres.source, nil
	}
	rows, err := l.db.GenreTree(ctx)
	if err != nil {
		return nil, "", &Error{Kind: KindInternal, Err: err}
	}
	tree, source := genre.Default(), genreSourceDefault
	if len(rows) > 0 {
		stored := make(genre.Tree, 0, len(rows))
		for _, r := range rows {
			stored = append(stored, genre.Node{Name: r.Name, Parent: r.Parent, Aliases: r.Aliases})
		}
		tree, source = stored, genreSourceCustom
	}
	norm, err := genre.New(tree)
	if err != nil {
		if len(rows) == 0 {
			return nil, "", &Error{Kind: KindInternal, Err: err}
		}
		l.log.Warn("genre: the stored vocabulary does not build; falling back to the shipped default", "err", err)
		if norm, err = genre.New(genre.Default()); err != nil {
			return nil, "", &Error{Kind: KindInternal, Err: err}
		}
		source = genreSourceDefault
	}
	l.genres.norm, l.genres.source, l.genres.valid = norm, source, true
	return norm, source, nil
}

// Vocabulary sources as the API spells them.
const (
	genreSourceDefault = "default"
	genreSourceCustom  = "custom"
)

// invalidateGenreVocabulary drops the cached normalizer after a tree
// write and bumps the version every vocabulary-derived cache keys on.
func (l *Library) invalidateGenreVocabulary() {
	l.genres.mu.Lock()
	l.genres.norm, l.genres.source, l.genres.valid = nil, "", false
	l.genres.mu.Unlock()
	// After the reset, so a reader that samples the new version can never
	// then be handed the old normalizer.
	l.genres.version.Add(1)
}

// GenreTreeFor reads the instance's vocabulary. Administrators only: it
// is server configuration, and the browse surface serves its effect
// rather than its contents.
func (l *Library) GenreTreeFor(ctx context.Context, uc *UserCtx) (GenreTreeDTO, error) {
	if !uc.Admin {
		return GenreTreeDTO{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	// Source comes from the vocabulary that actually resolves names, not
	// from whether the table has rows: a stored tree that no longer builds
	// has degraded to the default, and reporting "custom" beside the
	// default's genres would describe an instance that does not exist.
	norm, source, err := l.genreVocabularyInForce(ctx)
	if err != nil {
		return GenreTreeDTO{}, err
	}
	out := GenreTreeDTO{Source: source, Genres: make([]GenreNodeDTO, 0, norm.Len())}
	for _, n := range norm.Tree() {
		out.Genres = append(out.Genres, GenreNodeDTO{Name: n.Name, Parent: n.Parent, Aliases: n.Aliases})
	}
	return out, nil
}

// PutGenreTree replaces the instance's vocabulary. An empty list clears
// the override and returns to the shipped default, which is the only way
// back: the stored tree is a replacement, never a delta. The tree is
// built before it is stored, so a vocabulary that could not resolve
// deterministically (a duplicate name, an alias claimed twice, a parent
// that is not a top-level genre) is refused rather than persisted.
func (l *Library) PutGenreTree(ctx context.Context, uc *UserCtx, nodes []GenreNodeDTO) (GenreTreeDTO, error) {
	if !uc.Admin {
		return GenreTreeDTO{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	rows := make([]wdb.GenreNode, 0, len(nodes))
	if len(nodes) > 0 {
		tree := make(genre.Tree, 0, len(nodes))
		for _, n := range nodes {
			tree = append(tree, genre.Node{Name: n.Name, Parent: n.Parent, Aliases: n.Aliases})
		}
		built, err := genre.New(tree)
		if err != nil {
			return GenreTreeDTO{}, errInvalid(err.Error())
		}
		for _, n := range built.Tree() {
			rows = append(rows, wdb.GenreNode{Name: n.Name, Parent: n.Parent, Aliases: n.Aliases})
		}
	}
	if err := l.db.ReplaceGenreTree(ctx, rows); err != nil {
		return GenreTreeDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	// This bumps the vocabulary version, which is half the key the browse
	// enumeration cache uses: the genre tab renders labels through the
	// vocabulary, and this edit moves nothing else that cache watches.
	l.invalidateGenreVocabulary()
	// The vocabulary decides both what the sweeper rewrites and what the
	// health rule counts as off-tree, so a changed tree means the whole
	// catalog wants re-checking: rewind the sweeper to the oldest change
	// the log still retains rather than waiting for items to move on
	// their own. The full pass stays available for anything older.
	if _, err := l.rewindGenreSweep(ctx); err != nil {
		l.log.Warn("genre: rewinding the normalization sweeper", "err", err)
	}
	l.Audit(ctx, uc, "genre.tree", AuditTarget{Kind: "genre-tree", Name: "genre tree"},
		map[string]any{"genres": len(rows), "source": treeSource(len(rows))})
	return l.GenreTreeFor(ctx, uc)
}

func treeSource(n int) string {
	if n == 0 {
		return genreSourceDefault
	}
	return genreSourceCustom
}

// rewindGenreSweep points the continuous sweeper back at the oldest
// change the catalog log still retains, and returns the position it
// stored so a caller that is about to sweep does not read it back.
func (l *Library) rewindGenreSweep(ctx context.Context) (int64, error) {
	first, err := l.lib.Changes(ctx, 0)
	if err != nil {
		return 0, classify(err)
	}
	from := int64(0)
	if len(first) > 0 {
		from = first[0].Seq - 1
	}
	if err := l.db.SyncStateSet(ctx, genreSweepCursorKey, strconv.FormatInt(from, 10)); err != nil {
		return 0, err
	}
	return from, nil
}

// SweepGenres normalizes the items the catalog changed since the last
// pass. It is the primary mechanism: file-tag genres never reach WaxDeck
// at scan time, so newly scanned items normalize shortly after they land
// rather than waiting for a manual full pass. The supervised
// genre-normalize worker calls it on its ticker, never a bare goroutine.
func (l *Library) SweepGenres(ctx context.Context) (GenreSweepReport, error) {
	norm, err := l.genreNormalizer(ctx)
	if err != nil {
		return GenreSweepReport{}, err
	}
	raw, err := l.db.SyncStateGet(ctx, genreSweepCursorKey)
	if err != nil {
		return GenreSweepReport{}, &Error{Kind: KindInternal, Err: err}
	}
	since, cursorKnown := parseSweepCursor(raw)
	if !cursorKnown {
		// First run: start at the oldest retained change rather than at
		// the tail, so an existing catalog normalizes without a manual
		// pass. Anything older than the retained log is the full pass's
		// job, which is why that exists as a task.
		if since, err = l.rewindGenreSweep(ctx); err != nil {
			return GenreSweepReport{}, err
		}
	}
	// The position already on disk: an idle sweep must not rewrite it
	// every tick just to store the same number.
	from := since

	// Collect the changed items, coalesced: a scan that rewrites one item
	// several times still normalizes it once.
	seen := map[model.PID]bool{}
	var pids []model.PID
	report := GenreSweepReport{}
	for len(pids) < genreSweepBatch {
		rows, err := l.lib.Changes(ctx, since)
		if err != nil {
			return GenreSweepReport{}, classify(err)
		}
		if len(rows) == 0 {
			break
		}
		for _, ch := range rows {
			if len(pids) >= genreSweepBatch {
				break
			}
			since = ch.Seq
			if ch.EntityType != "item" || ch.Op == model.OpDelete || seen[ch.EntityPID] {
				continue
			}
			seen[ch.EntityPID] = true
			pids = append(pids, ch.EntityPID)
		}
	}
	// A full batch means the log may hold more; the worker loops rather
	// than waiting out its ticker. The cap is checked before a row is
	// consumed, so the cursor never runs ahead of what this pass handled.
	if len(pids) >= genreSweepBatch {
		report.More = true
	}
	if len(pids) > 0 {
		views, err := l.lib.GetMany(ctx, pids)
		if err != nil {
			return GenreSweepReport{}, classify(err)
		}
		res, err := l.normalizeGenres(ctx, norm, views, false, nil)
		if err != nil {
			return GenreSweepReport{}, err
		}
		report.Scanned, report.Normalized = res.scanned, res.normalized
		report.Locked, report.Unmapped = res.locked, res.unmapped
	}
	// The cursor advances past changes this pass rewrote, whose own
	// change rows land after it; the next pass reads them, finds the
	// values already canonical, and writes nothing, so the sweeper
	// converges after one idle pass rather than chasing itself.
	if since != from {
		if err := l.db.SyncStateSet(ctx, genreSweepCursorKey, fmt.Sprintf("%d", since)); err != nil {
			return report, &Error{Kind: KindInternal, Err: err}
		}
	}
	return report, nil
}

// genreNormalizeResult accumulates one batch's outcome.
type genreNormalizeResult struct {
	scanned    int
	normalized int
	locked     int
	unmapped   int
}

// normalizeGenres rewrites a batch of items' genre scalars onto the
// vocabulary. Items are grouped by their target value so one edit covers
// every item landing on the same scalar, and the batch runs with
// SkipLocked so an item whose genre a user locked is reported and left
// alone instead of failing the pass. dryRun computes without writing.
func (l *Library) normalizeGenres(ctx context.Context, norm *genre.Normalizer, views []*model.ItemView, dryRun bool, sum *genreNormalizeSummary) (genreNormalizeResult, error) {
	var res genreNormalizeResult
	byValue := map[string][]model.PID{}
	var order []string
	for _, it := range views {
		if it == nil || it.Genre == "" {
			continue
		}
		res.scanned++
		normalized, unmapped := norm.NormalizeScalar(it.Genre)
		if len(unmapped) > 0 {
			res.unmapped++
			if sum != nil && len(sum.Samples.Unmapped) < genreSampleCap {
				sum.Samples.Unmapped = append(sum.Samples.Unmapped, unmapped...)
			}
		}
		if normalized == "" || normalized == it.Genre {
			continue
		}
		if _, known := byValue[normalized]; !known {
			order = append(order, normalized)
		}
		byValue[normalized] = append(byValue[normalized], it.PID)
		if sum != nil && len(sum.Samples.Changes) < genreSampleCap {
			sum.Samples.Changes = append(sum.Samples.Changes, it.Genre+" -> "+normalized)
		}
	}
	if dryRun {
		// A dry run's whole job is to report what the apply will do, so it
		// has to separate the items the apply would rewrite from the ones
		// it would refuse. The apply learns that from the batch edit's
		// skip-locked accounting; there is no bulk lock read, so the dry
		// run pays one provenance lookup per *candidate* -- the items whose
		// scalar would actually change, which is empty on an already
		// normalized catalog and bounded by how much is off-vocabulary
		// otherwise.
		for _, v := range order {
			for _, pid := range byValue[v] {
				if l.genreFieldLocked(ctx, pid) {
					res.locked++
					continue
				}
				res.normalized++
			}
		}
		return res, nil
	}
	for _, v := range order {
		pids := byValue[v]
		// Lock stays off: normalization is housekeeping, not a user
		// decision, and locking would freeze the value against the
		// enrichment and organize paths that may still improve it. The
		// facade records the write as a user edit regardless, which is the
		// only provenance source its edit surface offers.
		//
		// The write is catalog-only, like every other WaxDeck edit that
		// does not opt into write-back: the file's own tag keeps whatever
		// it said. A `scan --force`, which re-derives unlocked fields from
		// tags, therefore reverts a normalized genre and the next sweep
		// re-applies it -- the same round trip an enriched genre makes, and
		// the intended consequence of the database being the working copy.
		batch, err := l.lib.EditManyFields(ctx, pids, map[string]string{"genre": v},
			waxbin.EditOptions{SkipLocked: true, Lock: model.LockUnchanged})
		if err != nil {
			return res, classify(err)
		}
		res.normalized += len(batch.Edited)
		res.locked += len(batch.Skipped)
	}
	return res, nil
}

// genreFieldLocked reports whether a user has locked the item's genre.
// A read failure answers false: over-reporting what a dry run would
// rewrite is a smaller lie than claiming an item is user-curated when
// nothing says so.
func (l *Library) genreFieldLocked(ctx context.Context, pid model.PID) bool {
	prov, err := l.lib.Provenance(ctx, pid)
	if err != nil {
		l.log.Warn("genre: reading provenance for a dry run", "item", pid, "err", err)
		return false
	}
	for _, p := range prov {
		if p.Field == "genre" && p.Locked {
			return true
		}
	}
	return false
}

// StartGenreNormalize queues a full-catalog normalization pass.
// Administrators only, and dry-run first is the intended shape: the
// report says exactly what would be rewritten before anything is.
func (l *Library) StartGenreNormalize(ctx context.Context, uc *UserCtx, dryRun bool) (ToolTaskDTO, error) {
	if !uc.Admin {
		return ToolTaskDTO{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	if _, err := l.genreNormalizer(ctx); err != nil {
		return ToolTaskDTO{}, err
	}
	t := wdb.ToolTask{
		ID:          "tk-" + ulid.Make().String(),
		Type:        taskTypeGenreNormalize,
		State:       taskStateQueued,
		UserID:      uc.ID,
		Params:      marshalJSON(genreNormalizeParams{DryRun: dryRun}),
		ResultPIDs:  "[]",
		CreatedAtNS: time.Now().UnixNano(),
	}
	if err := l.db.InsertToolTask(ctx, t); err != nil {
		return ToolTaskDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	l.notifyToolTask(ctx, t.ID)
	return toolTaskDTO(t), nil
}

// genreNormalizeParams is the persisted work order.
type genreNormalizeParams struct {
	DryRun bool `json:"dryRun"`
}

// runGenreNormalize walks every item carrying a genre and normalizes it.
// The continuous sweeper covers everything the change log still retains;
// this is the pass for a catalog older than that log, or for a
// vocabulary edit an administrator wants applied now.
func (l *Library) runGenreNormalize(ctx context.Context, t *wdb.ToolTask) error {
	var p genreNormalizeParams
	if err := json.Unmarshal([]byte(t.Params), &p); err != nil {
		return fmt.Errorf("%w: bad task params: %v", errToolPermanent, err)
	}
	norm, err := l.genreNormalizer(ctx)
	if err != nil {
		return fmt.Errorf("%w: %v", errToolPermanent, err)
	}
	sum := genreNormalizeSummary{DryRun: p.DryRun}
	q := query.New(query.EntityItems).WherePresence("genre", query.OpIsPresent).Build()
	cursor := read.Cursor("")
	for {
		page, err := l.lib.QueryPage(ctx, q, cursor, 500, false, "")
		if err != nil {
			return classify(err)
		}
		res, err := l.normalizeGenres(ctx, norm, page.Items, p.DryRun, &sum)
		if err != nil {
			return err
		}
		sum.Scanned += res.scanned
		sum.Normalized += res.normalized
		sum.Locked += res.locked
		sum.Unmapped += res.unmapped
		if !page.HasMore {
			break
		}
		cursor = page.Next
	}
	sum.Samples.Unmapped = dedupeStrings(sum.Samples.Unmapped, genreSampleCap)
	t.Summary = marshalJSON(sum)
	if uc := l.taskUserCtx(ctx, t.UserID); uc != nil {
		l.Audit(ctx, uc, "genre.normalize", AuditTarget{Kind: "genre-tree", Name: "genre normalization"},
			map[string]any{
				"dryRun": p.DryRun, "scanned": sum.Scanned,
				"normalized": sum.Normalized, "locked": sum.Locked, "unmapped": sum.Unmapped,
			})
	}
	return nil
}

// dedupeStrings keeps the first occurrence of each value, capped.
func dedupeStrings(in []string, cap int) []string {
	seen := make(map[string]bool, len(in))
	out := make([]string, 0, len(in))
	for _, s := range in {
		if seen[s] {
			continue
		}
		seen[s] = true
		out = append(out, s)
		if len(out) == cap {
			break
		}
	}
	if len(out) == 0 {
		return nil
	}
	sort.Strings(out)
	return out
}

// parseSweepCursor parses a stored sweep position; the second result is
// false for an unset or unparseable value, which reads as "no cursor
// yet" and rewinds. Trailing junk is a parse failure, not a prefix to
// salvage: a cursor this process cannot have written is not one to
// resume from.
func parseSweepCursor(s string) (int64, bool) {
	n, err := strconv.ParseInt(strings.TrimSpace(s), 10, 64)
	if err != nil {
		return 0, false
	}
	return n, true
}

// normalizeProviderGenres folds a provider's raw genre list onto the
// vocabulary before the enrichment cap applies. The order matters:
// normalizing first collapses two raw tags that name one genre, so the
// cap spends its slots on distinct genres rather than duplicates, and
// the value written is one the sweeper will not immediately rewrite.
func (l *Library) normalizeProviderGenres(ctx context.Context, genres []string) []string {
	norm, err := l.genreNormalizer(ctx)
	if err != nil {
		l.log.Warn("genre: vocabulary unavailable; enriching with raw provider genres", "err", err)
		return genres
	}
	out := make([]string, 0, len(genres))
	seen := map[string]bool{}
	for _, raw := range genres {
		name, _ := norm.Normalize(raw)
		if name == "" {
			continue
		}
		key := genre.Fold(name)
		if key == "" || seen[key] {
			continue
		}
		seen[key] = true
		out = append(out, name)
	}
	return out
}

// canonicalGenreLabel resolves a genre bucket's stored display name to
// the vocabulary's spelling. The catalog's genre row keeps whichever
// spelling was scanned first and cannot be renamed, so this is where the
// canonical label is applied.
func canonicalGenreLabel(norm *genre.Normalizer, display string) string {
	if norm == nil || display == "" {
		return display
	}
	name, _ := norm.Normalize(display)
	return name
}

// offTreeGenres returns the genre names in a scalar the vocabulary does
// not know, for the genre-whitelist health rule.
func offTreeGenres(norm *genre.Normalizer, scalar string) []string {
	if norm == nil || scalar == "" {
		return nil
	}
	_, unmapped := norm.NormalizeScalar(scalar)
	return unmapped
}
