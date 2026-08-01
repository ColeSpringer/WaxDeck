package service

import (
	"context"
	"io"
	"log/slog"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxdeck/fixtures"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// genreFixture is a scanned catalog whose tracks carry the genre tags
// the normalization rules are about: a true synonym ("Rap"), a spelling
// the catalog's own match key already folds but whose display name it
// keeps as scanned ("hip hop"), an alias with no separator ("HipHop"),
// a genre already canonical ("Jazz"), and one the vocabulary has never
// heard of. The library dir comes back so a later scan can add to it.
type genreFixture struct {
	ctx    context.Context
	svc    *Library
	uc     *UserCtx
	libDir string
}

func genreTrack(name, title, genre string, d time.Duration) fixtures.Spec {
	return fixtures.Spec{
		Name:     name,
		Codec:    fixtures.CodecFLAC,
		Duration: d,
		Tags: map[string]string{
			"TITLE":  title,
			"ARTIST": "Vocabulary Test",
			"ALBUM":  "Folded",
			"GENRE":  genre,
		},
	}
}

func newGenreFixture(t *testing.T) genreFixture {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	log := slog.New(slog.NewTextHandler(io.Discard, nil))

	libDir := t.TempDir()
	// "lower" is generated first so the catalog's genre row for the
	// hip hop match key is created with the lowercase display name: the
	// first-writer-wins case the canonical label has to survive.
	if _, err := fixtures.Generate(libDir,
		genreTrack("lower", "Lowercase", "hip hop", 2*time.Second),
		genreTrack("synonym", "Synonym", "Rap", 2500*time.Millisecond),
		genreTrack("runtogether", "Run Together", "HipHop", 3*time.Second),
		genreTrack("canonical", "Canonical", "Jazz", 3500*time.Millisecond),
		genreTrack("offtree", "Off Tree", "Sea Shanty Revival", 4*time.Second),
	); err != nil {
		t.Fatalf("generating fixtures: %v", err)
	}

	dataDir := t.TempDir()
	store, err := wdb.Open(ctx, filepath.Join(dataDir, "waxdeck.db"))
	if err != nil {
		t.Fatal(err)
	}
	group := supervise.NewGroup(log)
	svc, err := Open(ctx, Config{
		DataDir: dataDir,
		Roots:   []Root{{Name: "lib", Path: libDir}},
		Logger:  log,
	}, store, group)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		cancel()
		group.Wait()
		svc.Close()
		store.Close()
	})
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatalf("scanning fixture library: %v", err)
	}
	acct, err := svc.CreateAccount(ctx, AccountCreate{
		Username: "admin", Password: "correct-horse", Roles: []string{"admin"},
	})
	if err != nil {
		t.Fatal(err)
	}
	uc, err := svc.UserCtx(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	return genreFixture{ctx: ctx, svc: svc, uc: uc, libDir: libDir}
}

// sweepToQuiet runs the continuous sweeper until it reports no further
// work, the way the supervised worker drains it.
func (f genreFixture) sweepToQuiet(t *testing.T) GenreSweepReport {
	t.Helper()
	var last GenreSweepReport
	for i := 0; i < 20; i++ {
		rep, err := f.svc.SweepGenres(f.ctx)
		if err != nil {
			t.Fatalf("genre sweep: %v", err)
		}
		last = rep
		if !rep.More {
			return last
		}
	}
	t.Fatal("the genre sweeper never reported itself caught up")
	return last
}

// genreOf reads one item's stored genre scalar by title.
func (f genreFixture) genreOf(t *testing.T, title string) string {
	t.Helper()
	it := f.itemNamed(t, title)
	return it.Genre
}

func (f genreFixture) itemNamed(t *testing.T, title string) *model.ItemView {
	t.Helper()
	page, err := f.svc.Items(f.ctx, f.uc, ItemFilter{}, "", 100)
	if err != nil {
		t.Fatalf("listing items: %v", err)
	}
	for _, row := range page.Items {
		_, pid, ok := parseAPIPID(row.PID)
		if !ok {
			continue
		}
		it, err := f.svc.lib.Get(f.ctx, pid)
		if err != nil {
			t.Fatalf("reading item %s: %v", row.PID, err)
		}
		if it.Title == title {
			return it
		}
	}
	t.Fatalf("no item titled %q in the fixture", title)
	return nil
}

// TestSweeperFoldsSynonymsOntoOneBucket is the alias case no match key
// can reach: three different tags, one canonical genre, one bucket.
func TestSweeperFoldsSynonymsOntoOneBucket(t *testing.T) {
	f := newGenreFixture(t)
	f.sweepToQuiet(t)

	for _, title := range []string{"Lowercase", "Synonym", "Run Together"} {
		if got := f.genreOf(t, title); got != "Hip Hop" {
			t.Fatalf("%s kept genre %q; the sweeper should have folded it onto Hip Hop", title, got)
		}
	}

	page, err := f.svc.Facets(f.ctx, f.uc, FacetQuery{Dimension: "genre", Limit: 100})
	if err != nil {
		t.Fatalf("enumerating genres: %v", err)
	}
	var hipHop *FacetBucket
	for i, b := range page.Buckets {
		if b.Label == "Hip Hop" {
			if hipHop != nil {
				t.Fatalf("Hip Hop came back as two buckets: %+v and %+v", *hipHop, b)
			}
			hipHop = &page.Buckets[i]
		}
		if b.Label == "Rap" {
			t.Fatal("the Rap bucket survived the sweep")
		}
	}
	if hipHop == nil {
		t.Fatalf("no Hip Hop bucket in %+v", page.Buckets)
	}
	if hipHop.Count != 3 {
		t.Fatalf("Hip Hop bucket counts %d items, want 3", hipHop.Count)
	}
}

// TestCanonicalLabelBeatsScanOrder pins the first-writer-wins defect.
// The catalog's genre row is created with whichever spelling was scanned
// first and cannot be renamed, so the canonical label has to come from
// the vocabulary at read time. Rewriting the items alone does not do it.
func TestCanonicalLabelBeatsScanOrder(t *testing.T) {
	f := newGenreFixture(t)
	f.sweepToQuiet(t)

	// The stored entity really is the lowercase spelling: without the
	// canonical label this assertion would be what the browse tab shows.
	res, err := f.svc.lib.Facet(f.ctx, f.svc.facetScopeQuery(f.uc), "genre", "", 0, model.PID(f.uc.CatalogPID))
	if err != nil {
		t.Fatalf("raw facet: %v", err)
	}
	stored := ""
	for _, b := range res.Buckets {
		if strings.EqualFold(b.Display, "hip hop") {
			stored = b.Display
		}
	}
	if stored != "hip hop" {
		t.Fatalf("the catalog's genre row is named %q; the fixture meant it to keep the first-scanned spelling", stored)
	}

	page, err := f.svc.Facets(f.ctx, f.uc, FacetQuery{Dimension: "genre", Limit: 100})
	if err != nil {
		t.Fatalf("enumerating genres: %v", err)
	}
	for _, b := range page.Buckets {
		if b.Label == "hip hop" {
			t.Fatal("the browse label is the first-scanned spelling, not the canonical one")
		}
	}
}

// TestSweeperSkipsLockedGenres: a user's locked genre is theirs, and
// normalization is housekeeping.
func TestSweeperSkipsLockedGenres(t *testing.T) {
	f := newGenreFixture(t)
	it := f.itemNamed(t, "Synonym")
	if _, err := f.svc.SetItemLocks(f.ctx, f.uc, apiPID(PrefixTrack, it.PID), []string{"genre"}, true); err != nil {
		t.Fatalf("locking the genre field: %v", err)
	}

	var locked int
	for i := 0; i < 20; i++ {
		rep, err := f.svc.SweepGenres(f.ctx)
		if err != nil {
			t.Fatalf("genre sweep: %v", err)
		}
		locked += rep.Locked
		if !rep.More {
			break
		}
	}
	if locked == 0 {
		t.Fatal("the sweep reported no locked items; the lock was not honored or not counted")
	}
	if got := f.genreOf(t, "Synonym"); got != "Rap" {
		t.Fatalf("a locked genre was rewritten to %q", got)
	}
	// The unlocked siblings still normalized: one lock must not stall the batch.
	if got := f.genreOf(t, "Run Together"); got != "Hip Hop" {
		t.Fatalf("an unlocked sibling of a locked item kept genre %q", got)
	}
}

// TestUnmappedGenrePassesThrough: the vocabulary reports a miss rather
// than guessing, and the health rule is what surfaces it.
func TestUnmappedGenrePassesThrough(t *testing.T) {
	f := newGenreFixture(t)
	f.sweepToQuiet(t)

	if got := f.genreOf(t, "Off Tree"); got != "Sea Shanty Revival" {
		t.Fatalf("an unmapped genre came back as %q; it should pass through untouched", got)
	}
	if got := f.genreOf(t, "Canonical"); got != "Jazz" {
		t.Fatalf("an already-canonical genre was rewritten to %q", got)
	}

	if err := f.svc.SweepHealth(f.ctx); err != nil {
		t.Fatalf("health sweep: %v", err)
	}
	issues, _, err := f.svc.ListHealthIssuesFor(f.ctx, ruleGenreWhitelist, "", 50)
	if err != nil {
		t.Fatalf("listing genre-whitelist issues: %v", err)
	}
	var titles []string
	for _, i := range issues {
		titles = append(titles, i.Title)
	}
	if len(titles) != 1 || titles[0] != "Off Tree" {
		t.Fatalf("genre-whitelist flagged %v; want only the off-tree item", titles)
	}
}

// TestSweeperNormalizesFreshlyScannedFiles is the reason this runs as a
// sweeper rather than an ingest hook: file-tag genres are resolved by
// the catalog's own scanner and never pass through WaxDeck, so a library
// scanned after the fact must still normalize with no manual task run.
func TestSweeperNormalizesFreshlyScannedFiles(t *testing.T) {
	f := newGenreFixture(t)
	f.sweepToQuiet(t)

	if _, err := fixtures.Generate(f.libDir,
		genreTrack("late", "Arrived Late", "DnB", 5*time.Second)); err != nil {
		t.Fatalf("generating a late fixture: %v", err)
	}
	if _, err := f.svc.lib.Scan(f.ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatalf("rescanning: %v", err)
	}
	if got := f.genreOf(t, "Arrived Late"); got != "DnB" {
		t.Fatalf("the freshly scanned tag is %q; the fixture meant it to arrive raw", got)
	}

	f.sweepToQuiet(t)
	if got := f.genreOf(t, "Arrived Late"); got != "Drum & Bass" {
		t.Fatalf("a freshly scanned off-vocabulary tag stayed %q after a sweep", got)
	}
}

// TestGenreNormalizeTaskDryRunThenApply drives the full-catalog pass on
// the tool-task framework in the shape the importer established.
func TestGenreNormalizeTaskDryRunThenApply(t *testing.T) {
	f := newGenreFixture(t)

	dry, err := f.svc.StartGenreNormalize(f.ctx, f.uc, true)
	if err != nil {
		t.Fatalf("queuing the dry run: %v", err)
	}
	f.drainTasks(t)
	report := f.taskSummary(t, dry.ID)
	if report["dryRun"] != true {
		t.Fatalf("the dry run reported dryRun=%v", report["dryRun"])
	}
	if n, _ := report["normalized"].(float64); n < 3 {
		t.Fatalf("the dry run would normalize %v items; want at least the three hip hop spellings", report["normalized"])
	}
	if got := f.genreOf(t, "Synonym"); got != "Rap" {
		t.Fatalf("the dry run wrote: Synonym is now %q", got)
	}

	apply, err := f.svc.StartGenreNormalize(f.ctx, f.uc, false)
	if err != nil {
		t.Fatalf("queuing the apply: %v", err)
	}
	f.drainTasks(t)
	report = f.taskSummary(t, apply.ID)
	if n, _ := report["normalized"].(float64); n < 3 {
		t.Fatalf("the apply normalized %v items", report["normalized"])
	}
	if got := f.genreOf(t, "Synonym"); got != "Hip Hop" {
		t.Fatalf("after the apply, Synonym is %q", got)
	}
}

func (f genreFixture) drainTasks(t *testing.T) {
	t.Helper()
	for i := 0; i < 20 && f.svc.DrainToolTasks(f.ctx); i++ {
	}
}

func (f genreFixture) taskSummary(t *testing.T, taskID string) map[string]any {
	t.Helper()
	task, err := f.svc.GetToolTaskFor(f.ctx, f.uc, taskID)
	if err != nil {
		t.Fatalf("reading task %s: %v", taskID, err)
	}
	if task.State != taskStateDone {
		t.Fatalf("task %s is %s (%s)", taskID, task.State, task.Error)
	}
	return task.Summary
}

// TestDryRunAccountsForLockedGenres: a dry run exists to say what the
// apply will do. The apply refuses a locked genre, so a dry run that
// counted those as rewrites -- and reported none as locked -- would
// misreport exactly the items the apply is going to leave alone.
func TestDryRunAccountsForLockedGenres(t *testing.T) {
	f := newGenreFixture(t)
	it := f.itemNamed(t, "Synonym")
	if _, err := f.svc.SetItemLocks(f.ctx, f.uc, apiPID(PrefixTrack, it.PID), []string{"genre"}, true); err != nil {
		t.Fatalf("locking the genre field: %v", err)
	}

	dry, err := f.svc.StartGenreNormalize(f.ctx, f.uc, true)
	if err != nil {
		t.Fatalf("queuing the dry run: %v", err)
	}
	f.drainTasks(t)
	report := f.taskSummary(t, dry.ID)
	dryNormalized, _ := report["normalized"].(float64)
	dryLocked, _ := report["locked"].(float64)
	if dryLocked != 1 {
		t.Fatalf("the dry run reported %v locked items; the fixture locked one", report["locked"])
	}

	apply, err := f.svc.StartGenreNormalize(f.ctx, f.uc, false)
	if err != nil {
		t.Fatalf("queuing the apply: %v", err)
	}
	f.drainTasks(t)
	report = f.taskSummary(t, apply.ID)
	if got, _ := report["normalized"].(float64); got != dryNormalized {
		t.Fatalf("the dry run predicted %v rewrites, the apply made %v", dryNormalized, got)
	}
	if got, _ := report["locked"].(float64); got != dryLocked {
		t.Fatalf("the dry run predicted %v locked, the apply skipped %v", dryLocked, got)
	}
	if got := f.genreOf(t, "Synonym"); got != "Rap" {
		t.Fatalf("the apply rewrote a locked genre to %q", got)
	}
}

// TestGenreTreeReplaceAndReset covers the admin surface: a vocabulary
// that could not resolve one way is refused rather than stored, a stored
// one takes over, and an empty list is the way back to the default.
func TestGenreTreeReplaceAndReset(t *testing.T) {
	f := newGenreFixture(t)

	tree, err := f.svc.GenreTreeFor(f.ctx, f.uc)
	if err != nil {
		t.Fatalf("reading the tree: %v", err)
	}
	if tree.Source != "default" {
		t.Fatalf("a fresh instance reports source %q", tree.Source)
	}
	shipped := len(tree.Genres)

	if _, err := f.svc.PutGenreTree(f.ctx, f.uc, []GenreNodeDTO{
		{Name: "Hip Hop", Aliases: []string{"Rap"}},
		{Name: "Grime", Aliases: []string{"rap"}},
	}); err == nil {
		t.Fatal("a vocabulary with one alias claimed twice was stored")
	} else if KindOf(err) != KindInvalid {
		t.Fatalf("an ambiguous vocabulary answered %v, want invalid-request", KindOf(err))
	}

	stored, err := f.svc.PutGenreTree(f.ctx, f.uc, []GenreNodeDTO{
		{Name: "Sea Shanty"},
		{Name: "Sea Shanty Revival", Parent: "Sea Shanty", Aliases: []string{"Shanty Revival"}},
	})
	if err != nil {
		t.Fatalf("storing a vocabulary: %v", err)
	}
	if stored.Source != "custom" || len(stored.Genres) != 2 {
		t.Fatalf("stored tree = %+v", stored)
	}

	// The new vocabulary is what normalization now runs on: what used to
	// be off-tree resolves, and what used to resolve does not.
	f.sweepToQuiet(t)
	if got := f.genreOf(t, "Synonym"); got != "Rap" {
		t.Fatalf("Synonym normalized to %q under a vocabulary with no Hip Hop", got)
	}

	back, err := f.svc.PutGenreTree(f.ctx, f.uc, nil)
	if err != nil {
		t.Fatalf("clearing the vocabulary: %v", err)
	}
	if back.Source != "default" || len(back.Genres) != shipped {
		t.Fatalf("clearing left source %q with %d genres, want the shipped %d",
			back.Source, len(back.Genres), shipped)
	}
}
