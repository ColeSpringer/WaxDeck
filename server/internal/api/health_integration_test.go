package api

import (
	"context"
	"io"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin/enrich"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxdeck/fixtures"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// TestHealthSweepAndIssues drives a full health sweep over the demo
// library (whose fixtures carry no art, genre, year, or lyrics) and
// checks the summary, the per-rule issue listing with its keyset
// cursor, and the bulk-fix queue.
func TestHealthSweepAndIssues(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	ctx := context.Background()

	// The sweep endpoint queues; the worker is wired in main, so the
	// test asserts the flag and then drives the sweep synchronously
	// through the service handle.
	resp := h.postJSON(t, "/api/v1/library/health/sweep", nil)
	if resp.StatusCode != 202 {
		t.Fatalf("sweep status = %d, want 202", resp.StatusCode)
	}
	resp.Body.Close()
	if !h.svc.SweepRequested(ctx) {
		t.Fatal("sweep request flag not set")
	}
	if sum := decode[HealthSummary](t, get(t, h.ts, "/api/v1/library/health", h.token)); sum.Sweeping == nil || !*sum.Sweeping {
		t.Fatalf("sweeping = %v while the request waits, want true", sum.Sweeping)
	}
	if err := h.svc.RunHealthSweep(ctx); err != nil {
		t.Fatalf("sweeping: %v", err)
	}
	if h.svc.SweepRequested(ctx) {
		t.Fatal("sweep request flag not cleared")
	}

	resp = get(t, h.ts, "/api/v1/library/health", h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("health status = %d", resp.StatusCode)
	}
	sum := decode[HealthSummary](t, resp)
	if sum.WarmingUp {
		t.Fatal("warmingUp after a completed sweep")
	}
	if sum.TotalItems != 4 || sum.EvaluatedItems != 4 {
		t.Fatalf("total/evaluated = %d/%d, want 4/4", sum.TotalItems, sum.EvaluatedItems)
	}
	if sum.SweptAt == nil {
		t.Fatal("no sweptAt after a sweep")
	}
	if sum.Sweeping == nil || *sum.Sweeping {
		t.Fatalf("sweeping = %v after the sweep, want false", sum.Sweeping)
	}
	if sum.Score >= 100 {
		t.Fatalf("score = %v, want under 100 for an unenriched library", sum.Score)
	}
	counts := map[string]int{}
	fixable := map[string]bool{}
	for _, r := range sum.Rules {
		counts[r.Rule] = r.Failing
		fixable[r.Rule] = r.Fixable
	}
	for _, rule := range []string{"missing-art", "missing-genre", "missing-year", "missing-lyrics"} {
		if counts[rule] != 4 {
			t.Fatalf("%s failing = %d, want 4 (rules: %+v)", rule, counts[rule], sum.Rules)
		}
	}
	if fixable["corrupt-audio"] || fixable["legacy-tags"] || fixable["missing-year"] {
		t.Fatalf("unfixable rules flagged fixable: %+v", fixable)
	}

	// The issues worklist, filtered to one rule and keyset-paged.
	resp = get(t, h.ts, "/api/v1/library/health/issues?rule=missing-genre&limit=3", h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("issues status = %d", resp.StatusCode)
	}
	page := decode[HealthIssuePage](t, resp)
	if len(page.Items) != 3 || page.NextCursor == nil {
		t.Fatalf("first page = %d items, cursor %v", len(page.Items), page.NextCursor)
	}
	seen := map[string]bool{}
	for _, it := range page.Items {
		seen[it.Pid] = true
		if it.MediaType != "music" {
			t.Fatalf("issue mediaType = %q", it.MediaType)
		}
		has := false
		for _, r := range it.Rules {
			if r == "missing-genre" {
				has = true
			}
		}
		if !has {
			t.Fatalf("filtered issue %q lacks the rule: %v", it.Pid, it.Rules)
		}
	}
	resp = get(t, h.ts, "/api/v1/library/health/issues?rule=missing-genre&limit=3&cursor="+url.QueryEscape(*page.NextCursor), h.token)
	page2 := decode[HealthIssuePage](t, resp)
	if len(page2.Items) != 1 || page2.NextCursor != nil {
		t.Fatalf("second page = %d items, cursor %v", len(page2.Items), page2.NextCursor)
	}
	for _, it := range page2.Items {
		if seen[it.Pid] {
			t.Fatalf("pid %q repeated across pages", it.Pid)
		}
		seen[it.Pid] = true
	}
	if len(seen) != 4 {
		t.Fatalf("paged pids = %d distinct, want 4", len(seen))
	}

	// A garbage cursor answers invalid-request.
	resp = get(t, h.ts, "/api/v1/library/health/issues?cursor=garbage", h.token)
	if resp.StatusCode != 400 {
		t.Fatalf("garbage cursor status = %d, want 400", resp.StatusCode)
	}
	resp.Body.Close()

	// Rules with no automated fix refuse by name.
	resp = h.postJSON(t, "/api/v1/library/health/fix", map[string]any{"rule": "corrupt-audio"})
	if resp.StatusCode != 400 {
		t.Fatalf("corrupt-audio fix status = %d, want 400", resp.StatusCode)
	}
	resp.Body.Close()

	// A rule this install cannot fix says why and refuses: no contact,
	// so nothing may ask MusicBrainz for genres.
	for _, r := range sum.Rules {
		if r.Rule == "missing-genre" && (r.Fixable || r.FixBlocked == nil || *r.FixBlocked != NeedsContact) {
			t.Fatalf("missing-genre = %+v, want unfixable for want of a contact", r)
		}
		if r.Rule == "write-unsynced" && (!r.Fixable || r.FixBlocked != nil) {
			t.Fatalf("write-unsynced = %+v, want fixable", r)
		}
	}
	resp = h.postJSON(t, "/api/v1/library/health/fix", map[string]any{"rule": "missing-genre"})
	wantStatus(t, resp, 400, "a blocked rule's fix")

	// A write-back retry runs as a task that reports what it did.
	resp = h.postJSON(t, "/api/v1/library/health/fix", map[string]any{
		"rule": "write-unsynced", "itemPids": []string{page.Items[0].Pid},
	})
	if resp.StatusCode != 202 {
		t.Fatalf("write-unsynced fix status = %d, want 202", resp.StatusCode)
	}
	fix := decode[HealthFixResult](t, resp)
	if fix.Queued != 1 || fix.TaskId == nil || fix.JobPid != nil {
		t.Fatalf("fix = %+v, want one item on a task", fix)
	}
	for h.svc.DrainHealthFixes(ctx) {
	}
	task := decode[ToolTask](t, get(t, h.ts, "/api/v1/tools/tasks/"+*fix.TaskId, h.token))
	if task.State != "done" || task.Summary == nil || (*task.Summary)["attempted"] != float64(1) ||
		(*task.Summary)["filled"] != float64(1) || (*task.Summary)["rule"] != "write-unsynced" {
		t.Fatalf("task = %+v (summary %v), want one item written back", task, task.Summary)
	}
}

// stubLyricist answers lyrics for one title and holds every answer at
// its gate until the test lets it go.
type stubLyricist struct {
	title string
	gate  chan struct{}
	asked chan struct{}
}

func (p *stubLyricist) Name() string                    { return "stublyrics" }
func (p *stubLyricist) Capabilities() enrich.Capability { return enrich.CapLyrics }
func (p *stubLyricist) Enrich(ctx context.Context, req enrich.Request) (*enrich.Candidate, error) {
	select {
	case p.asked <- struct{}{}:
	default:
	}
	select {
	case <-p.gate:
	case <-ctx.Done():
		return nil, ctx.Err()
	}
	if req.Title != p.title {
		return nil, nil
	}
	return &enrich.Candidate{Lyrics: &model.Lyrics{Unsynced: "la la la"}}, nil
}

// A fix of missing lyrics runs the catalog's lyrics pass as a job the
// administrator can follow, refuses a second while it runs, and on
// finishing re-checks the rule and says what it filled.
func TestHealthFixStartsEnrichJob(t *testing.T) {
	t.Parallel()
	stub := &stubLyricist{title: "Alpha Song", gate: make(chan struct{}), asked: make(chan struct{}, 1)}
	h := newHarnessWith(t, func(c *service.Config) {
		c.EnrichmentProviders = []enrich.Provider{stub}
	})
	ctx := context.Background()
	if err := h.svc.RunHealthSweep(ctx); err != nil {
		t.Fatal(err)
	}
	since := decode[ServerSyncPage](t, get(t, h.ts, "/api/v1/sync/server", h.token)).NextSince

	resp := h.postJSON(t, "/api/v1/library/health/fix", map[string]any{"rule": "missing-lyrics"})
	if resp.StatusCode != 202 {
		t.Fatalf("fix status = %d, want 202", resp.StatusCode)
	}
	fix := decode[HealthFixResult](t, resp)
	if fix.Queued != 4 || fix.JobPid == nil || !strings.HasPrefix(*fix.JobPid, "jb-") || fix.TaskId != nil {
		t.Fatalf("fix = %+v, want the four failing items on a catalog job", fix)
	}
	<-stub.asked
	resp = h.postJSON(t, "/api/v1/library/health/fix", map[string]any{"rule": "missing-lyrics"})
	wantStatus(t, resp, 409, "a second fix while the pass runs")
	fixing := func() bool {
		sum := decode[HealthSummary](t, get(t, h.ts, "/api/v1/library/health", h.token))
		for _, r := range sum.Rules {
			if r.Rule == "missing-lyrics" {
				return r.Fixing
			}
		}
		t.Fatal("no missing-lyrics in the summary")
		return false
	}
	if !fixing() {
		t.Fatal("the summary does not say missing-lyrics is fixing while its pass runs")
	}
	close(stub.gate)

	row := waitForNotificationRow(t, h, "health-fix-finished")
	if row.TargetPid == nil || *row.TargetPid != *fix.JobPid || !strings.Contains(row.Body, "Filled 1 of 4") {
		t.Fatalf("row = %+v, want the job's fix filling one of four", row)
	}
	var sawJob, sawHealth bool
	for _, ev := range decode[ServerSyncPage](t, get(t, h.ts, "/api/v1/sync/server?since="+since, h.token)).Events {
		sawJob = sawJob || (ev.Kind == "job" && ev.Pid != nil && *ev.Pid == *fix.JobPid)
		sawHealth = sawHealth || ev.Kind == "health"
	}
	if !sawJob || !sawHealth {
		t.Fatalf("stream: job marker %v, health marker %v; want both", sawJob, sawHealth)
	}
	issues := decode[HealthIssuePage](t, get(t, h.ts, "/api/v1/library/health/issues?rule=missing-lyrics", h.token))
	if len(issues.Items) != 3 {
		t.Fatalf("still missing lyrics = %d, want the three nothing answered for", len(issues.Items))
	}
	deadline := time.Now().Add(10 * time.Second)
	for fixing() {
		if time.Now().After(deadline) {
			t.Fatal("missing-lyrics still reads as fixing after its re-check")
		}
		time.Sleep(10 * time.Millisecond)
	}
}

// waitForNotificationRow waits for the admin's inbox to hold a row for event.
func waitForNotificationRow(t *testing.T, h *harness, event string) Notification {
	t.Helper()
	deadline := time.Now().Add(10 * time.Second)
	for {
		page := decode[NotificationPage](t, get(t, h.ts, "/api/v1/users/me/notifications?limit=100", h.token))
		for _, n := range page.Notifications {
			if n.Event == event {
				return n
			}
		}
		if time.Now().After(deadline) {
			t.Fatalf("no %s row reached the inbox", event)
		}
		time.Sleep(10 * time.Millisecond)
	}
}

// An analyzed file whose header states half its audio fails
// duration-mismatch, and its issue row carries both lengths; the honest
// demo files do not.
func TestHealthFlagsAHeaderThatMisstatesTheAudio(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	ctx := context.Background()
	paths, err := fixtures.Generate(filepath.Join(h.library, "Half Artist", "Half Album"), fixtures.Spec{
		Name: "Half Song", Codec: fixtures.CodecFLAC, Duration: 8 * time.Second,
		Tags: map[string]string{"TITLE": "Half Song", "ARTIST": "Half Artist", "ALBUM": "Half Album"},
	})
	if err != nil {
		t.Fatal(err)
	}
	understateFLAC(t, paths[0], 1, 2)
	h.rescanAndWait(t)
	analyzeAndWait(t, h)
	if err := h.svc.SweepHealth(ctx); err != nil {
		t.Fatalf("sweeping: %v", err)
	}

	sum := decode[HealthSummary](t, get(t, h.ts, "/api/v1/library/health", h.token))
	var rule *HealthRuleCount
	for i := range sum.Rules {
		if sum.Rules[i].Rule == "duration-mismatch" {
			rule = &sum.Rules[i]
		}
	}
	if rule == nil || rule.Failing != 1 || rule.Fixable {
		t.Fatalf("duration-mismatch in the summary = %+v, want one failing, not fixable", rule)
	}
	page := decode[HealthIssuePage](t, get(t, h.ts, "/api/v1/library/health/issues?rule=duration-mismatch", h.token))
	if len(page.Items) != 1 || page.Items[0].Title != "Half Song" {
		t.Fatalf("duration-mismatch issues = %+v, want Half Song alone", page.Items)
	}
	d := page.Items[0].Detail
	if d == nil || d.HeaderMs == nil || d.DecodedMs == nil || *d.HeaderMs != 4000 || *d.DecodedMs != 8000 {
		t.Fatalf("issue detail = %+v, want header 4000 ms and audio 8000 ms", d)
	}
	if d.PartIndex != nil || (d.WholeFile != nil && *d.WholeFile) {
		t.Errorf("a track's own file named part %v, whole file %v", d.PartIndex, d.WholeFile)
	}

	// A header fixed since the sweep: the row stands until the next one,
	// but no longer shows lengths that now agree.
	understateFLAC(t, paths[0], 2, 1)
	h.rescanAndWait(t)
	page = decode[HealthIssuePage](t, get(t, h.ts, "/api/v1/library/health/issues?rule=duration-mismatch", h.token))
	if len(page.Items) != 1 || page.Items[0].Detail != nil {
		t.Fatalf("after the fix, issues = %+v, want the stale row without a detail", page.Items)
	}
}

// A multi-file book answers for every part, not only the one its path
// names: its third part's header states half of its 6 s.
func TestHealthFindsAMisstatedPartOfABook(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	ctx := context.Background()
	staged := t.TempDir()
	bookDir, err := fixtures.GenerateBook(staged)
	if err != nil {
		t.Fatal(err)
	}
	understateMP4(t, filepath.Join(bookDir, "03 - Part Three.m4b"), 1, 2)
	if err := os.CopyFS(filepath.Join(h.library, "book"), os.DirFS(staged)); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	analyzeAndWait(t, h)
	if err := h.svc.SweepHealth(ctx); err != nil {
		t.Fatalf("sweeping: %v", err)
	}

	page := decode[HealthIssuePage](t, get(t, h.ts, "/api/v1/library/health/issues?rule=duration-mismatch", h.token))
	if len(page.Items) != 1 || page.Items[0].MediaType != "audiobook" {
		t.Fatalf("duration-mismatch issues = %+v, want the book", page.Items)
	}
	d := page.Items[0].Detail
	if d == nil || d.HeaderMs == nil || d.DecodedMs == nil ||
		*d.HeaderMs < 2900 || *d.HeaderMs > 3100 || *d.DecodedMs < 5900 || *d.DecodedMs > 6100 {
		t.Fatalf("issue detail = %+v, want part three's 3 s header over 6 s of audio", d)
	}
	if d.PartIndex == nil || *d.PartIndex != 2 {
		t.Errorf("issue detail names part %v, want 2", d.PartIndex)
	}
}

// A cue-carved track is flagged for the file it is cut from, and says the
// lengths are that whole file's rather than its own.
func TestHealthNamesTheWholeFileACarvedTrackIsCutFrom(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	ctx := context.Background()
	ripDir := filepath.Join(h.library, "Rip Artist", "Rip Album")
	paths, err := fixtures.Generate(ripDir, fixtures.Spec{
		Name: "Rip Album", Codec: fixtures.CodecFLAC, Duration: 8 * time.Second,
		Tags: map[string]string{"TITLE": "Rip Album", "ALBUM": "Rip Album", "ARTIST": "Rip Artist", "ALBUMARTIST": "Rip Artist"},
	})
	if err != nil {
		t.Fatal(err)
	}
	understateFLAC(t, paths[0], 1, 2)
	sheet := "PERFORMER \"Rip Artist\"\nTITLE \"Rip Album\"\nFILE \"Rip Album.flac\" WAVE\n" +
		"  TRACK 01 AUDIO\n    TITLE \"Rip One\"\n    INDEX 01 00:00:00\n" +
		"  TRACK 02 AUDIO\n    TITLE \"Rip Two\"\n    INDEX 01 00:02:00\n"
	if err := os.WriteFile(filepath.Join(ripDir, "Rip Album.cue"), []byte(sheet), 0o644); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	analyzeAndWait(t, h)
	if err := h.svc.SweepHealth(ctx); err != nil {
		t.Fatalf("sweeping: %v", err)
	}

	page := decode[HealthIssuePage](t, get(t, h.ts, "/api/v1/library/health/issues?rule=duration-mismatch", h.token))
	if len(page.Items) != 2 {
		t.Fatalf("duration-mismatch issues = %+v, want both carved tracks", page.Items)
	}
	for _, it := range page.Items {
		d := it.Detail
		if d == nil || d.HeaderMs == nil || *d.HeaderMs != 4000 || d.DecodedMs == nil || *d.DecodedMs != 8000 ||
			d.WholeFile == nil || !*d.WholeFile {
			t.Errorf("%s detail = %+v, want the whole file's 4 s header over 8 s", it.Title, d)
		}
	}
}

// TestHealthAdminGates checks that the mutating and audit-priced
// surfaces are admin-only while the dashboard reads stay open to every
// authenticated user.
func TestHealthAdminGates(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	resp := h.postJSON(t, "/api/v1/users", map[string]any{"username": "sam", "password": testPassword})
	if resp.StatusCode != 201 {
		t.Fatalf("creating user: status %d", resp.StatusCode)
	}
	resp.Body.Close()
	sam := loginAs(t, h.ts, "sam", testPassword).Token

	for _, tc := range []struct {
		method, path string
		body         any
	}{
		{"POST", "/api/v1/library/health/sweep", nil},
		{"POST", "/api/v1/library/health/fix", map[string]any{"rule": "missing-genre"}},
		{"GET", "/api/v1/library/duplicates", nil},
		{"POST", "/api/v1/library/duplicates/merge", map[string]any{
			"entityType": "artist", "survivorPid": "01ARZ3NDEKTSV4RRFFQ69G5FAV",
			"loserPids": []string{"01BX5ZZKBKACTAV9WEVGEMMVRZ"}}},
		{"GET", "/api/v1/library/upgrades", nil},
		{"POST", "/api/v1/library/upgrades/resolve", map[string]any{
			"keepItemPid":    "tr-01ARZ3NDEKTSV4RRFFQ69G5FAV",
			"removeItemPids": []string{"tr-01BX5ZZKBKACTAV9WEVGEMMVRZ"}}},
		{"GET", "/api/v1/library/enrichment", nil},
		{"POST", "/api/v1/library/enrichment/run", map[string]any{}},
	} {
		resp := reqAs(t, h, tc.method, tc.path, sam, tc.body)
		if resp.StatusCode != 403 {
			t.Fatalf("%s %s as non-admin: status %d, want 403", tc.method, tc.path, resp.StatusCode)
		}
		resp.Body.Close()
	}

	// The health dashboard reads are for everyone.
	resp = get(t, h.ts, "/api/v1/library/health", sam)
	if resp.StatusCode != 200 {
		t.Fatalf("health as non-admin: status %d, want 200", resp.StatusCode)
	}
	resp.Body.Close()
	resp = get(t, h.ts, "/api/v1/library/health/issues", sam)
	if resp.StatusCode != 200 {
		t.Fatalf("issues as non-admin: status %d, want 200", resp.StatusCode)
	}
	resp.Body.Close()
}

// TestDuplicatesListAndMerge seeds two artist spellings the audit's
// collation-key check groups ("Dupe Artist" vs "The Dupe Artist"),
// merges them through the API, and checks the group resolves.
func TestDuplicatesListAndMerge(t *testing.T) {
	t.Parallel()
	dupes := t.TempDir()
	specs := []fixtures.Spec{
		{Name: "echo", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second, Tags: map[string]string{
			"TITLE": "Echo Song", "ARTIST": "Dupe Artist", "ALBUM": "Dupe Album"}},
		{Name: "foxtrot", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second, Tags: map[string]string{
			"TITLE": "Foxtrot Song", "ARTIST": "The Dupe Artist", "ALBUM": "Other Album"}},
	}
	if _, err := fixtures.Generate(dupes, specs...); err != nil {
		t.Fatalf("generating duplicate fixtures: %v", err)
	}
	h := newHarness(t, service.Root{Name: "dupes", Path: dupes})

	resp := get(t, h.ts, "/api/v1/library/duplicates", h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("duplicates status = %d", resp.StatusCode)
	}
	groups := decode[DuplicateGroups](t, resp).Groups
	var grp *DuplicateGroup
	for i := range groups {
		if groups[i].EntityType == "artist" && len(groups[i].Losers) == 1 {
			grp = &groups[i]
			break
		}
	}
	if grp == nil {
		t.Fatalf("no duplicate artist group in %+v", groups)
	}
	if grp.Survivor.Name == "" || grp.Losers[0].Name == "" {
		t.Fatalf("group names not resolved: %+v", *grp)
	}

	resp = h.postJSON(t, "/api/v1/library/duplicates/merge", map[string]any{
		"entityType":  "artist",
		"survivorPid": grp.Survivor.Pid,
		"loserPids":   []string{grp.Losers[0].Pid},
	})
	if resp.StatusCode != 200 {
		t.Fatalf("merge status = %d", resp.StatusCode)
	}
	res := decode[MergeResult](t, resp)
	if res.Merged != 1 {
		t.Fatalf("merged = %d, want 1", res.Merged)
	}

	// The group is resolved: listing again shows no artist duplicates.
	resp = get(t, h.ts, "/api/v1/library/duplicates", h.token)
	for _, g := range decode[DuplicateGroups](t, resp).Groups {
		if g.EntityType == "artist" {
			t.Fatalf("artist duplicate survived the merge: %+v", g)
		}
	}

	// The loser is gone from search; the survivor's name still finds
	// both tracks' artist entity.
	resp = get(t, h.ts, "/api/v1/library/search?q=Dupe", h.token)
	sr := decode[SearchResults](t, resp)
	if len(sr.Artists) != 1 {
		t.Fatalf("post-merge artist hits = %+v, want exactly one", sr.Artists)
	}
}

// TestReleaseGroupsMergeAndNeverFork covers the group rung the
// duplicates listing gained. Two halves, because the listing's own
// finding is not reachable on a catalog this server built: upstream
// refuses a user edit that would put one MusicBrainz id on two groups,
// and a scan of an edition carrying that id adopts it into the group
// already holding it rather than forking a twin. So the check earns its
// place for catalogs predating the mbid-first key, and what is testable
// here is the no-fork rule and the merge verb behind it.
func TestReleaseGroupsMergeAndNeverFork(t *testing.T) {
	t.Parallel()
	const rgMBID = "44444444-4444-4444-4444-444444444444"
	dupes := t.TempDir()
	if _, err := fixtures.Generate(dupes, fixtures.Spec{
		Name: "hotel", Codec: fixtures.CodecFLAC, Duration: 3 * time.Second, Tags: map[string]string{
			"TITLE": "Hotel Song", "ARTIST": "Group Twins", "ALBUM": "Loose Edition"},
	}); err != nil {
		t.Fatalf("generating the loose fixture: %v", err)
	}
	h := newHarness(t, service.Root{Name: "dupes", Path: dupes})

	// The loose group takes the id in its column, which is what
	// enrichment does: the group's own key does not move with it.
	loose := releaseGroupOf(t, h, "Hotel Song")
	resp := h.patchJSON(t, "/api/v1/entities/release-group/"+loose, map[string]any{
		"edits": map[string]string{"mbid": rgMBID},
	})
	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		t.Fatalf("setting the release-group mbid status = %d: %s", resp.StatusCode, body)
	}

	// A second edition arrives carrying the same id in its tags, under
	// a title that would key a group of its own. It joins the group
	// holding the id instead, which is why the duplicate finding does
	// not arise here.
	if _, err := fixtures.Generate(dupes, fixtures.Spec{
		Name: "golf", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second, Tags: map[string]string{
			"TITLE": "Golf Song", "ARTIST": "Group Twins", "ALBUM": "Keyed Edition",
			"MUSICBRAINZ_RELEASEGROUPID": rgMBID},
	}); err != nil {
		t.Fatalf("generating the keyed fixture: %v", err)
	}
	h.rescanAndWait(t)
	if keyed := releaseGroupOf(t, h, "Golf Song"); keyed != loose {
		t.Fatalf("the id-carrying edition forked group %s beside %s", keyed, loose)
	}
	resp = get(t, h.ts, "/api/v1/library/duplicates", h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("duplicates status = %d", resp.StatusCode)
	}
	for _, g := range decode[DuplicateGroups](t, resp).Groups {
		if g.EntityType == "release-group" {
			t.Fatalf("release-group duplicate reported on a catalog that cannot hold one: %+v", g)
		}
	}

	// The merge verb takes the group rung, which is what a listed
	// finding would ask it to do.
	if _, err := fixtures.Generate(dupes, fixtures.Spec{
		Name: "india", Codec: fixtures.CodecFLAC, Duration: 4 * time.Second, Tags: map[string]string{
			"TITLE": "India Song", "ARTIST": "Group Twins", "ALBUM": "Third Edition"},
	}); err != nil {
		t.Fatalf("generating the third fixture: %v", err)
	}
	h.rescanAndWait(t)
	third := releaseGroupOf(t, h, "India Song")
	if third == loose {
		t.Fatalf("the third edition landed on the same group %s", loose)
	}
	resp = h.postJSON(t, "/api/v1/library/duplicates/merge", map[string]any{
		"entityType":  "release-group",
		"survivorPid": loose,
		"loserPids":   []string{third},
	})
	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		t.Fatalf("release-group merge status = %d: %s", resp.StatusCode, body)
	}
	res := decode[MergeResult](t, resp)
	if res.Merged != 1 || res.ChildrenMoved == 0 {
		t.Fatalf("merge result = %+v, want one merge that re-parented an album", res)
	}
	if got := releaseGroupOf(t, h, "India Song"); got != loose {
		t.Fatalf("after the merge the third edition sits under %s, want the survivor %s", got, loose)
	}
}

// releaseGroupOf resolves the release group behind the track with the
// given title, which is two hops: an item names its album and an album
// names its group.
func releaseGroupOf(t *testing.T, h *harness, title string) string {
	t.Helper()
	for _, it := range h.items(t, "?limit=100").Items {
		if it.Title != title || it.AlbumPid == nil {
			continue
		}
		album := decode[AlbumDetail](t, get(t, h.ts, "/api/v1/albums/"+*it.AlbumPid, h.token))
		if album.ReleaseGroupPid == nil {
			t.Fatalf("album %s carries no release group", *it.AlbumPid)
		}
		return *album.ReleaseGroupPid
	}
	t.Fatalf("no track titled %q in the library", title)
	return ""
}

// TestUpgradesEndpoints exercises the listing and resolve validation.
// The fixtures are never fingerprint-analyzed in the harness (analysis
// is a separate catalog pass no server path triggers here), so the
// listing is legitimately empty; grouping itself is upstream-tested.
func TestUpgradesEndpoints(t *testing.T) {
	t.Parallel()
	h := newHarness(t)

	resp := get(t, h.ts, "/api/v1/library/upgrades", h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("upgrades status = %d", resp.StatusCode)
	}
	if groups := decode[UpgradeGroups](t, resp).Groups; len(groups) != 0 {
		t.Fatalf("unanalyzed library produced upgrade groups: %+v", groups)
	}

	// A malformed keeper pid refuses.
	resp = h.postJSON(t, "/api/v1/library/upgrades/resolve", map[string]any{
		"keepItemPid":    "garbage",
		"removeItemPids": []string{"tr-01ARZ3NDEKTSV4RRFFQ69G5FAV"},
	})
	if resp.StatusCode != 400 {
		t.Fatalf("bad keeper status = %d, want 400", resp.StatusCode)
	}
	resp.Body.Close()

	// A keeper listed for removal refuses.
	resp = h.postJSON(t, "/api/v1/library/upgrades/resolve", map[string]any{
		"keepItemPid":    "tr-01ARZ3NDEKTSV4RRFFQ69G5FAV",
		"removeItemPids": []string{"tr-01ARZ3NDEKTSV4RRFFQ69G5FAV"},
	})
	if resp.StatusCode != 400 {
		t.Fatalf("self-removal status = %d, want 400", resp.StatusCode)
	}
	resp.Body.Close()

	// A well-formed but unknown keeper answers not-found before
	// anything moves.
	resp = h.postJSON(t, "/api/v1/library/upgrades/resolve", map[string]any{
		"keepItemPid":    "tr-01ARZ3NDEKTSV4RRFFQ69G5FAV",
		"removeItemPids": []string{"tr-01BX5ZZKBKACTAV9WEVGEMMVRZ"},
	})
	if resp.StatusCode != 404 {
		t.Fatalf("unknown keeper status = %d, want 404", resp.StatusCode)
	}
	resp.Body.Close()
}

// TestEnrichmentStatusAndItemEnrich covers the status shape on a server
// with no injected providers and the per-item fetch's skip reporting.
func TestEnrichmentStatusAndItemEnrich(t *testing.T) {
	t.Parallel()
	h := newHarness(t)

	resp := get(t, h.ts, "/api/v1/library/enrichment", h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("enrichment status = %d", resp.StatusCode)
	}
	st := decode[EnrichmentStatus](t, resp)
	if st.Running {
		t.Fatal("running with no pass started")
	}
	// No injected providers in the harness: only the catalog built-ins.
	if len(st.Providers) != 4 {
		t.Fatalf("providers = %+v, want the four built-ins", st.Providers)
	}
	// No contact, so the catalog registered none of them: listed in the
	// order with their switches, not configured.
	for _, p := range st.Providers {
		if !p.Builtin || p.Configured || p.Enabled == nil || !*p.Enabled {
			t.Fatalf("built-in %q reported builtin=%v configured=%v enabled=%v", p.Name, p.Builtin, p.Configured, p.Enabled)
		}
	}
	if st.Coverage.Lyrics.Total != 4 || st.Coverage.Lyrics.Enriched != 0 || st.Coverage.LyricsAsked != 0 {
		t.Fatalf("lyrics = %+v, asked %d; want none of the 4 music tracks, none asked",
			st.Coverage.Lyrics, st.Coverage.LyricsAsked)
	}

	// Per-item enrich with no injected providers: nothing applies and
	// every want reports why.
	page := h.items(t, "?limit=1")
	pid := page.Items[0].Pid
	resp = h.postJSON(t, "/api/v1/items/"+pid+"/enrich", map[string]any{
		"want": []string{"cover", "genres", "lyrics"},
	})
	if resp.StatusCode != 200 {
		t.Fatalf("enrich item status = %d", resp.StatusCode)
	}
	res := decode[EnrichItemResult](t, resp)
	if len(res.Applied) != 0 || len(res.Skipped) != 3 {
		t.Fatalf("enrich result = %+v, want 0 applied / 3 skipped", res)
	}

	// An unknown want refuses.
	resp = h.postJSON(t, "/api/v1/items/"+pid+"/enrich", map[string]any{"want": []string{"everything"}})
	if resp.StatusCode != 400 {
		t.Fatalf("unknown want status = %d, want 400", resp.StatusCode)
	}
	resp.Body.Close()

	if st.Configured {
		t.Fatalf("configured = %v, want false without a contact", st.Configured)
	}

	// 501, and the message must name the WaxDeck knob, not upstream's.
	resp = h.postJSON(t, "/api/v1/library/enrichment/run", map[string]any{})
	if resp.StatusCode != 501 {
		t.Fatalf("enrichment run status = %d, want 501 without a contact", resp.StatusCode)
	}
	body, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if !strings.Contains(string(body), "WAXDECK_ENRICHMENT_CONTACT") {
		t.Errorf("refusal does not name the WaxDeck flag: %s", body)
	}
	if strings.Contains(string(body), "WAXBIN_ENRICH_CONTACT") {
		t.Errorf("refusal passes upstream's own knob through: %s", body)
	}
}
