package api

import (
	"testing"

	"github.com/colespringer/waxbin/model"
)

// An organize request or a health fix naming more items than the contract
// allows answers invalid-request.
func TestAnOrganizeOrAFixPastTheItemCapIsAnInvalidRequest(t *testing.T) {
	t.Parallel()
	h := newManagedHarness(t)
	pids := make([]string, 1001)
	for i := range pids {
		pids[i] = "tr-" + string(model.NewPID())
	}
	for _, c := range []struct {
		path string
		body map[string]any
	}{
		{"/api/v1/organize/preview", map[string]any{"itemPids": pids}},
		{"/api/v1/organize/apply", map[string]any{"itemPids": pids}},
		{"/api/v1/library/health/fix", map[string]any{"rule": "path-mismatch", "itemPids": pids}},
	} {
		resp := h.postJSON(t, c.path, c.body)
		if resp.StatusCode != 400 {
			t.Fatalf("%s with %d items = %d, want 400", c.path, len(pids), resp.StatusCode)
		}
		if e := decode[Error](t, resp); e.Code != "invalid-request" {
			t.Fatalf("%s with %d items: code %q, want invalid-request", c.path, len(pids), e.Code)
		}
	}
}
