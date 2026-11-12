package api

import (
	"context"
	"testing"
)

// A catalog repair rewrites values client mirrors hold with no change row
// for each, so every catalog cursor from before it answers 410 sync-reset
// once it ends, and the documented recovery, a fresh snapshot, serves.
func TestACatalogRepairSendsMirrorsBackToASnapshot(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	_, before := h.mirror(t, 100)
	decodeStatus[ToolTask](t, h.postJSON(t, "/api/v1/admin/catalog/repair", nil), 202, "repair")
	for h.svc.Tools.DrainLongToolTasks(context.Background()) {
	}
	e := decodeStatus[Error](t, get(t, h.ts, "/api/v1/sync/catalog?since="+before, h.token), 410, "a cursor from before the repair")
	if e.Code != "sync-reset" {
		t.Fatalf("a cursor from before the repair = %+v, want sync-reset", e)
	}
	_, after := h.mirror(t, 100)
	wantStatus(t, get(t, h.ts, "/api/v1/sync/catalog?since="+after, h.token), 200, "a cursor from after the repair")
}
