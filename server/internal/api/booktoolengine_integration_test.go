package api

import (
	"encoding/json"
	"io"
	"net/http"
	"testing"
)

// The file tools' routes, each with a pid of the shape it takes.
var fileToolRoutes = map[string]string{
	"merge":     "/api/v1/books/bk-01JZX5N8QW3F4V9T2B7KD3M9R6/merge",
	"split":     "/api/v1/books/bk-01JZX5N8QW3F4V9T2B7KD3M9R6/split",
	"cue split": "/api/v1/items/tr-01JZX5N8QW3F4V9T2B7KD3M9R6/split-cue",
}

// A merge, a split or a CUE split asked for while the configured engine
// is away is refused as every engine-only request is then: 503, naming
// the streaming engine, and when to ask again. On a server with no
// engine it is a feature the server lacks: 501, with nothing to wait for.
func TestAFileToolRefusalSaysWhetherTheEngineIsAwayOrMissing(t *testing.T) {
	t.Parallel()
	t.Run("away", func(t *testing.T) {
		t.Parallel()
		h := newHarnessWithDeadSidecar(t)
		for what, path := range fileToolRoutes {
			wantEngineDown(t, h.postJSON(t, path, map[string]any{}), what)
		}
	})
	t.Run("none", func(t *testing.T) {
		t.Parallel()
		h := newHarnessDirect(t)
		for what, path := range fileToolRoutes {
			resp := h.postJSON(t, path, map[string]any{})
			body, _ := io.ReadAll(resp.Body)
			resp.Body.Close()
			var e Error
			if err := json.Unmarshal(body, &e); err != nil {
				t.Fatalf("%s body %q: %v", what, body, err)
			}
			if resp.StatusCode != http.StatusNotImplemented || e.Code != "feature-unavailable" || resp.Header.Get("Retry-After") != "" {
				t.Errorf("%s = %d %s (Retry-After %q), want 501 feature-unavailable with nothing to wait for",
					what, resp.StatusCode, body, resp.Header.Get("Retry-After"))
			}
		}
	})
}
