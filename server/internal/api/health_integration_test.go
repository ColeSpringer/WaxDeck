package api

import (
	"context"
	"io"
	"net/url"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// TestHealthSweepAndIssues drives a full health sweep over the demo
// library (whose fixtures carry no art, genre, year, or lyrics) and
// checks the summary, the per-rule issue listing with its keyset
// cursor, and the bulk-fix queue.
func TestHealthSweepAndIssues(t *testing.T) {
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
	if err := h.svc.SweepHealth(ctx); err != nil {
		t.Fatalf("sweeping: %v", err)
	}
	h.svc.ClearSweepRequest(ctx)
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
	if !fixable["missing-genre"] || !fixable["missing-art"] {
		t.Fatalf("fixable rules not flagged: %+v", fixable)
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

	// An un-scoped fix queues everything failing the rule; with no
	// providers configured each fix drains as a completed no-op.
	resp = h.postJSON(t, "/api/v1/library/health/fix", map[string]any{"rule": "missing-genre"})
	if resp.StatusCode != 202 {
		t.Fatalf("fix status = %d, want 202", resp.StatusCode)
	}
	fix := decode[HealthFixResult](t, resp)
	if fix.Queued != 4 {
		t.Fatalf("queued = %d, want 4", fix.Queued)
	}
	worked := 0
	for h.svc.DrainFixQueue(ctx) {
		worked++
		if worked > 20 {
			t.Fatal("fix queue never drained")
		}
	}
	if worked != 4 {
		t.Fatalf("drained %d fixes, want 4", worked)
	}
}

// TestHealthAdminGates checks that the mutating and audit-priced
// surfaces are admin-only while the dashboard reads stay open to every
// authenticated user.
func TestHealthAdminGates(t *testing.T) {
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

// TestUpgradesEndpoints exercises the listing and resolve validation.
// The fixtures are never fingerprint-analyzed in the harness (analysis
// is a separate catalog pass no server path triggers here), so the
// listing is legitimately empty; grouping itself is upstream-tested.
func TestUpgradesEndpoints(t *testing.T) {
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
	if len(st.Providers) != 3 {
		t.Fatalf("providers = %+v, want the three built-ins", st.Providers)
	}
	for _, p := range st.Providers {
		if !p.Builtin || !p.Configured {
			t.Fatalf("built-in %q reported builtin=%v configured=%v", p.Name, p.Builtin, p.Configured)
		}
	}
	if st.Coverage.Lyrics.Total != 4 {
		t.Fatalf("lyrics total = %d, want the 4 music tracks", st.Coverage.Lyrics.Total)
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
