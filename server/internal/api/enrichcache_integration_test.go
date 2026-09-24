package api

import (
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// The enrichment cache's admin surface on the empty cache a test stack
// holds: the census reads zero, the prune keeps the thumbnail pair's
// refusals and is audited as asked, and both are for administrators.
func TestEnrichmentCacheCensusAndPrune(t *testing.T) {
	t.Parallel()
	h := newHarness(t)

	resp := get(t, h.ts, "/api/v1/admin/enrichment-cache", h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("census status = %d", resp.StatusCode)
	}
	rep := decode[EnrichmentCacheReport](t, resp)
	if rep.Rows != 0 || rep.Bytes != 0 || rep.OldestAt != nil || rep.NewestAt != nil || len(rep.Kinds) != 0 {
		t.Errorf("census of an empty cache = %+v", rep)
	}

	resp = h.postJSON(t, "/api/v1/admin/enrichment-cache/prune", map[string]any{})
	wantStatus(t, resp, 400, "a prune with neither bound")
	resp = h.postJSON(t, "/api/v1/admin/enrichment-cache/prune",
		map[string]any{"olderThanSeconds": int64(20_000_000_000)})
	wantStatus(t, resp, 400, "an age that would overflow a Duration")
	resp = h.postJSON(t, "/api/v1/admin/enrichment-cache/prune", map[string]any{"maxBytes": 0})
	if resp.StatusCode != 200 {
		t.Fatalf("prune status = %d", resp.StatusCode)
	}
	if pruned := decode[EnrichmentCachePruneResult](t, resp); pruned.Removed != 0 || pruned.FreedBytes != 0 {
		t.Errorf("prune of an empty cache = %+v", pruned)
	}

	audit := decode[AuditEventPage](t, get(t, h.ts, "/api/v1/admin/audit?action=enrichment-cache.prune", h.token))
	if len(audit.Events) != 1 || audit.Events[0].Detail == nil {
		t.Fatalf("audit = %+v, want the one prune", audit.Events)
	}
	detail := *audit.Events[0].Detail
	if _, ok := detail["maxBytes"]; !ok {
		t.Errorf("audit detail %v lacks the budget that was asked for", detail)
	}
	if _, ok := detail["olderThanSeconds"]; ok {
		t.Errorf("audit detail %v carries an age nobody asked for", detail)
	}

	resp = h.postJSON(t, "/api/v1/users", map[string]any{"username": "listener", "password": "long-enough-pw"})
	wantStatus(t, resp, 201, "create non-admin user")
	userToken := loginAs(t, h.ts, "listener", "long-enough-pw").Token
	wantStatus(t, get(t, h.ts, "/api/v1/admin/enrichment-cache", userToken), 403, "a user's census")
	wantStatus(t, reqAs(t, h, "POST", "/api/v1/admin/enrichment-cache/prune", userToken,
		map[string]any{"maxBytes": 0}), 403, "a user's prune")
}

func TestEnrichmentCacheReportCarriesTheKinds(t *testing.T) {
	t.Parallel()
	got := enrichmentCacheReport(service.EnrichCacheDTO{
		Rows: 3, Bytes: 700, OldestAtNS: 0, NewestAtNS: 5e9,
		Kinds: []service.EnrichCacheKindDTO{
			{Kind: "mb:artist", Rows: 2, Bytes: 600},
			{Kind: "caa:rg-front", Rows: 1, Bytes: 100, Exempt: true},
		},
		ExemptRows: 1, ExemptBytes: 100,
	})
	// A stamp of zero is still a stamp: presence follows the rows.
	if got.OldestAt == nil || !got.OldestAt.Equal(time.Unix(0, 0)) || got.NewestAt == nil || got.NewestAt.Unix() != 5 {
		t.Errorf("stamps = %v, %v", got.OldestAt, got.NewestAt)
	}
	if len(got.Kinds) != 2 || got.Kinds[0] != (EnrichmentCacheKind{Kind: "mb:artist", Rows: 2, Bytes: 600}) ||
		got.Kinds[1] != (EnrichmentCacheKind{Kind: "caa:rg-front", Rows: 1, Bytes: 100, Exempt: true}) {
		t.Errorf("kinds = %+v", got.Kinds)
	}
	if got.Rows != 3 || got.Bytes != 700 || got.ExemptRows != 1 || got.ExemptBytes != 100 {
		t.Errorf("report = %+v", got)
	}
}
