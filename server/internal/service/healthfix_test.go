package service

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"os"
	"slices"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/enrich"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"

	"github.com/colespringer/waxdeck/fixtures"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// Every phase a fix asks for is one the catalog has.
func TestHealthFixPhasesAreTheCatalogs(t *testing.T) {
	t.Parallel()
	for rule, phases := range healthFixPhases {
		for _, p := range phases {
			if !slices.Contains(model.EnrichPhases(), p) {
				t.Errorf("%s asks for phase %q, which the catalog does not have", rule, p)
			}
		}
	}
}

// A rule whose fix this install cannot run says what it lacks, in the
// terms an administrator can act on.
func TestHealthFixabilityNamesWhatIsMissing(t *testing.T) {
	t.Parallel()
	type want struct {
		fixable bool
		blocked string
	}
	for _, tc := range []struct {
		name    string
		mutate  func(*Config)
		sources []EnrichmentSource
		want    map[string]want
	}{
		{
			name:   "nothing configured",
			mutate: func(*Config) {},
			want: map[string]want{
				ruleMissingLyrics:   {false, fixBlockedContact},
				ruleMissingArt:      {false, fixBlockedContact},
				ruleMissingGenre:    {false, fixBlockedContact},
				ruleMissingNarrator: {false, fixBlockedBookSource},
				ruleMissingASIN:     {false, fixBlockedBookSource},
				rulePathMismatch:    {false, fixBlockedNoManaged},
				ruleWriteUnsynced:   {true, ""},
				ruleCorruptAudio:    {false, ""},
				ruleGenreWhitelist:  {false, ""},
			},
		},
		{
			name: "a lyrics provider and a managed root",
			mutate: func(c *Config) {
				c.EnrichmentProviders = []enrich.Provider{&lyricist{name: "a"}}
				c.Roots[0].Managed = true
			},
			want: map[string]want{
				ruleMissingLyrics: {true, ""},
				ruleMissingArt:    {false, fixBlockedContact},
				rulePathMismatch:  {true, ""},
			},
		},
		{
			name:   "a contact",
			mutate: func(c *Config) { c.EnrichmentContact = "ops@example.org" },
			want: map[string]want{
				ruleMissingLyrics: {true, ""},
				ruleMissingArt:    {true, ""},
				ruleMissingGenre:  {true, ""},
			},
		},
		{
			name:   "a contact with its lyrics and genre sources off",
			mutate: func(c *Config) { c.EnrichmentContact = "ops@example.org" },
			sources: []EnrichmentSource{
				{enrich.ProviderLRCLIB, false},
				{enrich.ProviderMusicBrainz, false},
				{enrich.ProviderListenBrainz, false},
			},
			want: map[string]want{
				ruleMissingLyrics: {false, fixBlockedLyricsSource},
				ruleMissingGenre:  {false, fixBlockedGenreSource},
				ruleMissingArt:    {true, ""},
			},
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			ctx, svc, uc := openEnrichFixture(t, tc.mutate)
			if tc.sources != nil {
				if _, err := svc.PutEnrichmentSources(ctx, uc, tc.sources); err != nil {
					t.Fatal(err)
				}
			}
			for rule, w := range tc.want {
				if fixable, blocked := svc.healthFixability(rule); fixable != w.fixable || blocked != w.blocked {
					t.Errorf("%s = (%v, %q), want (%v, %q)", rule, fixable, blocked, w.fixable, w.blocked)
				}
			}
		})
	}
}

// A fix scoped to named items runs as a task over them, fills what a
// source answers, re-checks the rule and says what it did.
func TestAScopedFixFillsWhatItNames(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, track := openLyricsFixture(t, &lyricist{name: "a"})
	if err := svc.RunHealthSweep(ctx); err != nil {
		t.Fatal(err)
	}
	api := apiPID(PrefixTrack, track)
	start, err := svc.StartHealthFix(ctx, uc, ruleMissingLyrics, []string{api})
	if err != nil {
		t.Fatal(err)
	}
	if start.Queued != 1 || start.TaskID == "" || start.JobPID != "" {
		t.Fatalf("start = %+v, want one item on a task", start)
	}
	sum := fixSummary(t, ctx, svc, uc, start.TaskID)
	if sum.Rule != ruleMissingLyrics || sum.Attempted != 1 || sum.Filled != 1 || sum.Failed != 0 {
		t.Fatalf("summary %+v, want one item filled", sum)
	}
	if issues, _, err := svc.ListHealthIssuesFor(ctx, ruleMissingLyrics, "", 10); err != nil || len(issues) != 0 {
		t.Fatalf("still missing lyrics = %+v (%v), want none after the re-check", issues, err)
	}
	rows := inboxOf(t, ctx, svc, uc, "health-fix-finished")
	if len(rows) != 1 || rows[0].TargetPID != start.TaskID || rows[0].Title != "Fix finished: Missing lyrics" {
		t.Fatalf("rows = %+v, want the task's fix", rows)
	}
}

// A fix that needs the enrichment lease while a pass holds it answers
// that it is busy rather than queueing work that would wait on it.
func TestAScopedFixWhileAPassRunsIsAConflict(t *testing.T) {
	t.Parallel()
	a := &lyricist{name: "a", asked: make(chan struct{}, 1), gate: make(chan struct{})}
	ctx, svc, uc, track := openLyricsFixture(t, a)
	pid, err := svc.lib.StartEnrich(ctx, waxbin.EnrichOptions{})
	if err != nil {
		t.Fatal(err)
	}
	defer waitForJob(t, ctx, svc, pid)
	defer close(a.gate)
	<-a.asked
	for _, scope := range [][]string{nil, {apiPID(PrefixTrack, track)}} {
		if _, err := svc.StartHealthFix(ctx, uc, ruleMissingLyrics, scope); KindOf(err) != KindConflict {
			t.Errorf("fix scoped to %v during a pass = %v, want a conflict", scope, err)
		}
	}
}

// ruleFixing reads whether the summary says a fix for rule is running.
func ruleFixing(t *testing.T, ctx context.Context, svc *Library, rule string) bool {
	t.Helper()
	sum, err := svc.HealthSummaryFor(ctx)
	if err != nil {
		t.Fatal(err)
	}
	for _, r := range sum.Rules {
		if r.Rule == rule {
			return r.Fixing
		}
	}
	t.Fatalf("no %s in the summary", rule)
	return false
}

// A fix reads as running from its start until its re-check has landed,
// not only while its pass runs: the counts move at the re-check.
func TestARuleReadsAsFixingUntilItsRecheckLands(t *testing.T) {
	t.Parallel()
	a := &lyricist{name: "a", asked: make(chan struct{}, 1), gate: make(chan struct{})}
	ctx, svc, uc, _ := openLyricsFixture(t, a)
	if err := svc.RunHealthSweep(ctx); err != nil {
		t.Fatal(err)
	}
	if ruleFixing(t, ctx, svc, ruleMissingLyrics) {
		t.Fatal("a rule nobody fixes reads as fixing")
	}
	start, err := svc.StartHealthFix(ctx, uc, ruleMissingLyrics, nil)
	if err != nil {
		t.Fatal(err)
	}
	gate := sync.OnceFunc(func() { close(a.gate) })
	defer gate()
	<-a.asked
	if !ruleFixing(t, ctx, svc, ruleMissingLyrics) {
		t.Fatalf("fix %+v under way, but the rule does not read as fixing", start)
	}
	gate()
	row := waitForInbox(t, ctx, svc, uc, "health-fix-finished")
	if row.TargetPID != start.JobPID {
		t.Fatalf("row = %+v, want the fix's job", row)
	}
	waitFor(t, func() bool { return !ruleFixing(t, ctx, svc, ruleMissingLyrics) },
		"the rule should stop reading as fixing once its re-check landed")
	if counts, err := svc.db.HealthRuleCounts(ctx); err != nil || counts[ruleMissingLyrics] != 0 {
		t.Fatalf("missing lyrics = %d (%v), want the re-check's 0", counts[ruleMissingLyrics], err)
	}
}

// A second fix for a rule whose fix is still running, or still settling
// its re-check, answers busy and starts nothing.
func TestAFixWhileTheRuleIsFixingIsAConflict(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := openLyricsFixture(t, &lyricist{name: "a"})
	if err := svc.RunHealthSweep(ctx); err != nil {
		t.Fatal(err)
	}
	// A pass-backed fix whose pass has ended and whose re-check runs.
	if err := svc.db.InsertJobOrigin(ctx, wdb.JobOrigin{
		PID: string(model.NewPID()), UserID: uc.ID, Rule: ruleMissingLyrics, CreatedAtNS: 1,
	}); err != nil {
		t.Fatal(err)
	}
	if !ruleFixing(t, ctx, svc, ruleMissingLyrics) {
		t.Fatal("a rule with a fix settling does not read as fixing")
	}
	if _, err := svc.StartHealthFix(ctx, uc, ruleMissingLyrics, nil); KindOf(err) != KindConflict {
		t.Fatalf("a second pass-backed fix = %v, want a conflict", err)
	}
	// A task-backed fix, twice.
	if _, err := svc.StartHealthFix(ctx, uc, ruleWriteUnsynced, nil); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.StartHealthFix(ctx, uc, ruleWriteUnsynced, nil); KindOf(err) != KindConflict {
		t.Fatalf("a second task-backed fix = %v, want a conflict", err)
	}
	tasks, _, err := svc.ListToolTasksFor(ctx, uc, "", 100)
	if err != nil {
		t.Fatal(err)
	}
	if len(tasks) != 1 {
		t.Fatalf("tasks = %+v, want the first fix's alone", tasks)
	}
	jobs, err := svc.lib.Jobs(ctx, 50)
	if err != nil {
		t.Fatal(err)
	}
	for _, j := range jobs {
		if j.Kind == "enrich" {
			t.Fatalf("a refused fix started pass %s", j.PID)
		}
	}
}

// A fix whose end a stopped process took in hand is told by this one:
// the origin outlives the claim until the re-check and the notification.
func TestAFixSettleCutShortIsTakenOver(t *testing.T) {
	t.Parallel()
	a := &lyricist{name: "a", asked: make(chan struct{}, 1), gate: make(chan struct{})}
	ctx, svc, uc, _ := openLyricsFixture(t, a)
	pid, err := svc.lib.StartEnrich(ctx, waxbin.EnrichOptions{})
	if err != nil {
		t.Fatal(err)
	}
	gate := sync.OnceFunc(func() { close(a.gate) })
	defer waitForJob(t, ctx, svc, pid)
	defer gate()
	<-a.asked
	if err := svc.db.InsertJobOrigin(ctx, wdb.JobOrigin{PID: string(pid), UserID: uc.ID, Rule: ruleMissingLyrics, CreatedAtNS: 1}); err != nil {
		t.Fatal(err)
	}
	// Taken in hand by a process that stopped before telling anyone:
	// nothing settles a job while it runs, so the claim holds till then.
	if _, err := svc.db.ClaimJobOrigin(ctx, string(pid), 1, 2); err != nil {
		t.Fatal(err)
	}
	gate()
	if row := waitForInbox(t, ctx, svc, uc, "health-fix-finished"); row.TargetPID != apiPID(PrefixJob, pid) {
		t.Fatalf("row = %+v, want the cut-short fix's", row)
	}
	waitFor(t, func() bool {
		left, err := svc.db.JobOrigins(ctx)
		return err == nil && len(left) == 0
	}, "the settled origin should be gone")
}

// A re-check tells what now passes from what still fails, leaves an item
// that is gone out of both, and drops the gone item's row.
func TestARecheckCountsWhatPassesAndLeavesTheGoneOut(t *testing.T) {
	t.Parallel()
	ctx, svc, _, track := openLyricsFixture(t, &lyricist{name: "a"})
	if err := svc.RunHealthSweep(ctx); err != nil {
		t.Fatal(err)
	}
	gone := string(model.NewPID())
	if err := svc.db.UpsertHealthRow(ctx, wdb.HealthRow{
		ItemPID: gone, MediaType: "music", Rules: `["missing-lyrics"]`, RuleCount: 1, SweptAtNS: 1,
	}); err != nil {
		t.Fatal(err)
	}
	if err := svc.lib.SetLyrics(ctx, track, &model.Lyrics{Unsynced: "la la"}, model.LockUnchanged, false); err != nil {
		t.Fatal(err)
	}
	res, err := svc.recheckHealthRule(ctx, ruleMissingLyrics, nil)
	if err != nil || res != (healthRecheck{passing: 1, gone: 1}) {
		t.Fatalf("re-check = %+v (%v), want one passing and one gone", res, err)
	}
	if _, err := svc.db.HealthRowByItem(ctx, gone); !errors.Is(err, wdb.ErrNotFound) {
		t.Fatalf("the gone item's row = %v, want it dropped", err)
	}
	if row, err := svc.db.HealthRowByItem(ctx, string(track)); err == nil && strings.Contains(row.Rules, ruleMissingLyrics) {
		t.Fatalf("track row = %+v, want missing lyrics off it", row)
	}
}

// narrator is a book source that knows a book's narrator and nothing else.
type narrator struct{}

func (narrator) Name() string                    { return "narrator" }
func (narrator) Capabilities() enrich.Capability { return enrich.CapBookMeta }
func (narrator) Enrich(context.Context, enrich.Request) (*enrich.Candidate, error) {
	return &enrich.Candidate{Fields: map[string]string{"narrator": "Some Reader"}}, nil
}

// A scoped fix counts an item filled only where the rule it fixes now
// passes: a book source that fills the narrator applied something, and
// the ASIN is still missing.
func TestAScopedFixCountsFilledOnlyWhereTheRuleNowPasses(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := openEnrichFixture(t, func(c *Config) {
		c.EnrichmentProviders = []enrich.Provider{narrator{}}
		if _, err := fixtures.GenerateBook(c.Roots[0].Path); err != nil {
			t.Fatal(err)
		}
	})
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	books, err := svc.lib.Query(ctx, query.New(query.EntityItems).
		Where("kind", query.OpIs, string(model.KindBook)).Build(), "")
	if err != nil || len(books) != 1 {
		t.Fatalf("books = %v (%v), want the fixture's one", books, err)
	}
	// An ISBN to look the book up by, and no ASIN.
	if err := svc.lib.EditFields(ctx, books[0].PID, map[string]string{"isbn": "9780306406157"},
		waxbin.EditOptions{Lock: model.LockUnchanged}); err != nil {
		t.Fatal(err)
	}
	if err := svc.RunHealthSweep(ctx); err != nil {
		t.Fatal(err)
	}
	start, err := svc.StartHealthFix(ctx, uc, ruleMissingASIN, []string{apiPID(PrefixBook, books[0].PID)})
	if err != nil {
		t.Fatal(err)
	}
	sum := fixSummary(t, ctx, svc, uc, start.TaskID)
	if sum.Attempted != 1 || sum.Filled != 0 || sum.Skipped["no match"] != 1 {
		t.Fatalf("summary %+v, want the book attempted and skipped for want of an ASIN", sum)
	}
	it, err := svc.lib.Get(ctx, books[0].PID)
	if err != nil || it.Narrator != "Some Reader" {
		t.Fatalf("narrator = %q (%v), want the source's fill", it.Narrator, err)
	}
}

// A path fix counts items, not the files it moves: a book is one item
// over several parts, and an item held back because another took its
// place is skipped for that.
func TestAPathFixCountsItemsNotFiles(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := openEnrichFixture(t, func(c *Config) {
		c.Roots[0].Managed = true
		if _, err := fixtures.GenerateBook(c.Roots[0].Path); err != nil {
			t.Fatal(err)
		}
		for i, name := range []string{"twin-a", "twin-b"} {
			if _, err := fixtures.Generate(c.Roots[0].Path, fixtures.Spec{
				Name: name, Codec: fixtures.CodecFLAC, Duration: time.Duration(2+i) * time.Second,
				Tags: map[string]string{"TITLE": "Twin", "ARTIST": "Pair", "ALBUM": "Doubles", "TRACKNUMBER": "1"},
			}); err != nil {
				t.Fatal(err)
			}
		}
	})
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	items, err := svc.lib.Query(ctx, query.New(query.EntityItems).Build(), "")
	if err != nil || len(items) != 3 {
		t.Fatalf("items = %v (%v), want the book and the twins", items, err)
	}
	var scope []string
	for _, it := range items {
		prefix := PrefixTrack
		if it.Kind == model.KindBook {
			prefix = PrefixBook
		}
		scope = append(scope, apiPID(prefix, it.PID))
	}
	start, err := svc.StartHealthFix(ctx, uc, rulePathMismatch, scope)
	if err != nil {
		t.Fatal(err)
	}
	sum := fixSummary(t, ctx, svc, uc, start.TaskID)
	if sum.Attempted != 3 || sum.Filled != 2 || sum.Failed != 0 ||
		sum.Skipped["destination taken"] != 1 || len(sum.Skipped) != 1 {
		t.Fatalf("summary %+v, want the book and one twin moved and the other twin held back", sum)
	}
}

// Missing art is fixable with a source for either of its pictures, and
// the fix forces only the phase that can run: forcing one this install
// skips is refused by the catalog.
func TestMissingArtIsFixableWithOneOfItsSources(t *testing.T) {
	t.Parallel()
	albumCovers := &enrich.Mock{
		ProviderName: "album-covers", Caps: enrich.CapCover,
		CapsAt: map[enrich.TargetType]enrich.Capability{enrich.TargetRelease: enrich.CapCover},
	}
	ctx, svc, uc, _ := openLyricsFixture(t, albumCovers)
	if fixable, blocked := svc.healthFixability(ruleMissingArt); !fixable || blocked != "" {
		t.Fatalf("missing-art = (%v, %q), want fixable with an album cover source", fixable, blocked)
	}
	if err := svc.RunHealthSweep(ctx); err != nil {
		t.Fatal(err)
	}
	start, err := svc.StartHealthFix(ctx, uc, ruleMissingArt, nil)
	if err != nil || start.JobPID == "" {
		t.Fatalf("start = %+v (%v), want a pass", start, err)
	}
	_, pid, _ := parseAPIPID(start.JobPID)
	waitForJob(t, ctx, svc, pid)
}

// A health fix, which can run for hours, has a worker of its own: the
// tool worker takes the task queued after it, and never the fix.
func TestHealthFixesHaveAWorkerOfTheirOwn(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := openLyricsFixture(t, &lyricist{name: "a"})
	fix, err := svc.StartHealthFix(ctx, uc, ruleWriteUnsynced, nil)
	if err != nil {
		t.Fatal(err)
	}
	other, err := svc.StartGenreNormalize(ctx, uc, true)
	if err != nil {
		t.Fatal(err)
	}
	state := func(id string) string {
		task, err := svc.GetToolTaskFor(ctx, uc, id)
		if err != nil {
			t.Fatal(err)
		}
		return task.State
	}
	for svc.DrainToolTasks(ctx) {
	}
	if fixed, normalized := state(fix.TaskID), state(other.ID); fixed != taskStateQueued || normalized != taskStateDone {
		t.Fatalf("after the tool worker: fix %s, normalize %s; want the fix still queued", fixed, normalized)
	}
	for svc.DrainHealthFixes(ctx) {
	}
	if fixed := state(fix.TaskID); fixed != taskStateDone {
		t.Fatalf("after the fix worker: fix %s, want done", fixed)
	}
}

// A fix task's end reaches every account once its state is recorded, so
// a client reading the summary on the marker sees the rule no longer
// fixing.
func TestAFixTaskMarksHealthOnceItsEndLands(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := openLyricsFixture(t, &lyricist{name: "a"})
	start, err := svc.StartHealthFix(ctx, uc, ruleWriteUnsynced, nil)
	if err != nil {
		t.Fatal(err)
	}
	for svc.DrainHealthFixes(ctx) {
	}
	evs, _, err := svc.db.EventsSince(ctx, uc.ID, 0, 1000)
	if err != nil {
		t.Fatal(err)
	}
	var ended, health int64
	for _, e := range evs {
		switch {
		case e.Kind == eventTask && e.ItemPID == start.TaskID:
			ended = e.ID
		case e.Kind == eventHealth:
			health = e.ID
		}
	}
	if ended == 0 || health < ended {
		t.Fatalf("task marker %d, health marker %d: want health told after the task's end", ended, health)
	}
	waitForInbox(t, ctx, svc, uc, "health-fix-finished")
}

// A fix task that gave up tells every account its rule is no longer
// being fixed, and its starter why.
func TestAFixTaskThatGaveUpTellsItsStarter(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := openLyricsFixture(t, &lyricist{name: "a"})
	id := "tk-" + string(model.NewPID())
	if err := svc.db.InsertToolTask(ctx, wdb.ToolTask{
		ID: id, Type: taskTypeHealthFix, State: "running", UserID: uc.ID,
		Params: `{"rule":"write-unsynced"}`, Summary: `{"rule":"write-unsynced"}`,
		ResultPIDs: "[]", Attempts: toolTaskMaxAttempts, CreatedAtNS: 1,
	}); err != nil {
		t.Fatal(err)
	}
	if !ruleFixing(t, ctx, svc, ruleWriteUnsynced) {
		t.Fatal("a running fix task does not read as fixing")
	}
	markers := healthMarkers(t, ctx, svc, uc)
	svc.DrainHealthFixes(ctx)
	if task, err := svc.GetToolTaskFor(ctx, uc, id); err != nil || task.State != taskStateFailed {
		t.Fatalf("task = %+v (%v), want it retired", task, err)
	}
	if n := healthMarkers(t, ctx, svc, uc); n <= markers {
		t.Fatal("every account should hear the rule is no longer being fixed")
	}
	row := waitForInbox(t, ctx, svc, uc, "health-fix-finished")
	if row.TargetPID != id || !strings.Contains(row.Body, "gave up") {
		t.Fatalf("row = %+v, want the task's failure", row)
	}
}

// A pass-backed fix whose re-check failed says so, rather than
// reporting counts it never read.
func TestAFixJobThatCouldNotRecheckSaysSo(t *testing.T) {
	t.Parallel()
	done := Job{State: string(model.JobDone)}
	if got := healthFixJobBody(done, healthRecheck{passing: 3, failing: 1}, nil); got != "Filled 3 of 4; 1 still missing" {
		t.Errorf("landed = %q", got)
	}
	got := healthFixJobBody(done, healthRecheck{}, errors.New("the catalog went away"))
	if strings.Contains(got, "Filled") || !strings.Contains(got, "could not be re-checked") {
		t.Errorf("unchecked = %q, want the failed re-check and no counts", got)
	}
	failed := Job{State: string(model.JobFailed), Error: "the disk went away"}
	if got := healthFixJobBody(failed, healthRecheck{passing: 1}, nil); !strings.HasPrefix(got, "The enrichment pass failed (the disk went away). ") {
		t.Errorf("failed = %q", got)
	}
}

// A fix scoped to named items re-checks those items only: the rest of
// the rule's rows are the next sweep's.
func TestAScopedFixRechecksOnlyWhatItNames(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, track := openLyricsFixture(t, &lyricist{name: "a"})
	if err := svc.RunHealthSweep(ctx); err != nil {
		t.Fatal(err)
	}
	other := string(model.NewPID())
	if err := svc.db.UpsertHealthRow(ctx, wdb.HealthRow{
		ItemPID: other, MediaType: "music", Rules: `["missing-lyrics"]`, RuleCount: 1, SweptAtNS: 1,
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.StartHealthFix(ctx, uc, ruleMissingLyrics, []string{apiPID(PrefixTrack, track)}); err != nil {
		t.Fatal(err)
	}
	for svc.DrainHealthFixes(ctx) {
	}
	if _, err := svc.db.HealthRowByItem(ctx, other); err != nil {
		t.Fatalf("a row the fix never named = %v, want it left for the sweep", err)
	}
}

// A task's progress is not news: it goes out as `task-progress`, which
// refreshes task lists, apart from the `task` markers of its states.
func TestATaskSaysItsProgressApartFromItsNews(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, track := openLyricsFixture(t, &lyricist{name: "a"})
	if err := svc.RunHealthSweep(ctx); err != nil {
		t.Fatal(err)
	}
	start, err := svc.StartHealthFix(ctx, uc, ruleMissingLyrics, []string{apiPID(PrefixTrack, track)})
	if err != nil {
		t.Fatal(err)
	}
	for svc.DrainHealthFixes(ctx) {
	}
	evs, _, err := svc.db.EventsSince(ctx, uc.ID, 0, 1000)
	if err != nil {
		t.Fatal(err)
	}
	var kinds []string
	for _, e := range evs {
		if e.ItemPID == start.TaskID {
			kinds = append(kinds, e.Kind)
		}
	}
	// Queued, running, one item's progress, done.
	if want := []string{eventTask, eventTask, eventTaskProgress, eventTask}; !slices.Equal(kinds, want) {
		t.Fatalf("markers = %v, want %v", kinds, want)
	}
}

// managedTrackFixture opens a managed library holding one track off
// the organize template, scanned; it answers the track's path and its
// API pid.
func managedTrackFixture(t *testing.T) (context.Context, *Library, *UserCtx, string, string) {
	t.Helper()
	var paths []string
	ctx, svc, uc := openEnrichFixture(t, func(c *Config) {
		c.Roots[0].Managed = true
		var err error
		if paths, err = fixtures.Generate(c.Roots[0].Path, fixtures.Spec{
			Name: "stray", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
			Tags: map[string]string{"TITLE": "Stray", "ARTIST": "Nomad", "ALBUM": "Wander", "TRACKNUMBER": "1"},
		}); err != nil {
			t.Fatal(err)
		}
	})
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	items, err := svc.lib.Query(ctx, query.New(query.EntityItems).Build(), "")
	if err != nil || len(items) != 1 {
		t.Fatalf("items = %v (%v), want the one track", items, err)
	}
	return ctx, svc, uc, paths[0], apiPID(PrefixTrack, items[0].PID)
}

// readOnlyFixture is managedTrackFixture with every library read-only.
func readOnlyFixture(t *testing.T) (context.Context, *Library, *UserCtx, string, string) {
	t.Helper()
	ctx, svc, uc, path, pid := managedTrackFixture(t)
	setLibrariesReadOnly(t, ctx, svc, uc, true)
	return ctx, svc, uc, path, pid
}

// setLibrariesReadOnly flags every library read-only, or clears them.
func setLibrariesReadOnly(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, readOnly bool) {
	t.Helper()
	libs, err := svc.lib.Libraries(ctx)
	if err != nil {
		t.Fatal(err)
	}
	for _, lib := range libs {
		if err := svc.LibraryReadOnlySet(ctx, uc, apiPID(PrefixLibrary, lib.PID), readOnly); err != nil {
			t.Fatal(err)
		}
	}
}

// setServerReadOnly flips the server-wide flag.
func setServerReadOnly(t *testing.T, ctx context.Context, svc *Library, readOnly bool) {
	t.Helper()
	if err := svc.db.SettingSet(ctx, settingReadOnly, strconv.FormatBool(readOnly), time.Now().UnixNano()); err != nil {
		t.Fatal(err)
	}
	svc.loadRuntimeToggles(ctx)
}

// fixSummary runs the queued fixes and reads the report of the task,
// which has to have finished.
func fixSummary(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, taskID string) healthFixSummary {
	t.Helper()
	for svc.DrainHealthFixes(ctx) {
	}
	task, err := svc.GetToolTaskFor(ctx, uc, taskID)
	if err != nil {
		t.Fatal(err)
	}
	if task.State != taskStateDone {
		t.Fatalf("task %s, want it done", task.State)
	}
	raw, _ := json.Marshal(task.Summary)
	var sum healthFixSummary
	if err := json.Unmarshal(raw, &sum); err != nil {
		t.Fatal(err)
	}
	return sum
}

func TestAPathFixLeavesAReadOnlyLibraryInPlace(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, path, pid := readOnlyFixture(t)
	start, err := svc.StartHealthFix(ctx, uc, rulePathMismatch, []string{pid})
	if err != nil {
		t.Fatal(err)
	}
	sum := fixSummary(t, ctx, svc, uc, start.TaskID)
	if sum.Filled != 0 || sum.Skipped["read-only library"] != 1 {
		t.Fatalf("summary %+v, want the track held back as read-only", sum)
	}
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("the track moved out of a read-only library: %v", err)
	}
}

func TestAWriteBackFixLeavesAReadOnlyLibraryAlone(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, path, pid := readOnlyFixture(t)
	before, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	start, err := svc.StartHealthFix(ctx, uc, ruleWriteUnsynced, []string{pid})
	if err != nil {
		t.Fatal(err)
	}
	sum := fixSummary(t, ctx, svc, uc, start.TaskID)
	if sum.Filled != 0 || sum.Skipped["read-only library"] != 1 {
		t.Fatalf("summary %+v, want the track left alone as read-only", sum)
	}
	after, err := os.ReadFile(path)
	if err != nil || !bytes.Equal(before, after) {
		t.Fatalf("the fix rewrote a file in a read-only library (%v)", err)
	}
}

func TestAReadOnlyServerRefusesAFileWritingFix(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := openEnrichFixture(t, func(c *Config) { c.Roots[0].Managed = true })
	setServerReadOnly(t, ctx, svc, true)
	for _, rule := range []string{ruleWriteUnsynced, rulePathMismatch} {
		if _, err := svc.StartHealthFix(ctx, uc, rule, nil); KindOf(err) != KindReadOnly {
			t.Fatalf("%s: err = %v, want read-only", rule, err)
		}
	}
}

// A fix that writes files cannot run on a read-only server, and the
// rule says so rather than offering a fix that can only be refused.
func TestAReadOnlyServerBlocksTheFileWritingFixes(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := openEnrichFixture(t, func(c *Config) { c.Roots[0].Managed = true })
	setServerReadOnly(t, ctx, svc, true)
	for _, rule := range []string{ruleWriteUnsynced, rulePathMismatch} {
		if fixable, blocked := svc.healthFixability(rule); fixable || blocked != fixBlockedReadOnly {
			t.Errorf("%s = (%v, %q), want blocked as read-only", rule, fixable, blocked)
		}
	}
}

// A path fix queued before the server went read-only moves nothing
// when it runs.
func TestAPathFixRunningOnAReadOnlyServerMovesNothing(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, path, pid := managedTrackFixture(t)
	start, err := svc.StartHealthFix(ctx, uc, rulePathMismatch, []string{pid})
	if err != nil {
		t.Fatal(err)
	}
	setServerReadOnly(t, ctx, svc, true)
	sum := fixSummary(t, ctx, svc, uc, start.TaskID)
	if sum.Filled != 0 || sum.Skipped[readOnlyReason] != 1 {
		t.Fatalf("summary %+v, want the track held back as read-only", sum)
	}
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("the track moved on a read-only server: %v", err)
	}
}

// A plan whose every move is held back runs no organize job, so it
// neither takes the file-mutation lease nor files a job row.
func TestAHeldPlanRunsNoOrganizeJob(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _, pid := readOnlyFixture(t)
	if _, err := svc.ApplyOrganize(ctx, uc, svc.defaultOrganizeProfile(), nil); err != nil {
		t.Fatal(err)
	}
	start, err := svc.StartHealthFix(ctx, uc, rulePathMismatch, []string{pid})
	if err != nil {
		t.Fatal(err)
	}
	fixSummary(t, ctx, svc, uc, start.TaskID)
	jobs, err := svc.lib.Jobs(ctx, 50)
	if err != nil {
		t.Fatal(err)
	}
	for _, j := range jobs {
		if j.Kind == "organize" {
			t.Fatalf("an organize job ran with nothing to move: %+v", j)
		}
	}
}
