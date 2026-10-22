package flow

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
)

// refusingResolver answers every source with one error.
type refusingResolver struct{ err error }

func (r refusingResolver) StreamSource(context.Context, string, string) (Source, error) {
	return Source{}, r.err
}

// A share's listener is told the catalog is briefly away rather than that
// the shared item does not exist, which a player would never retry.
func TestAShareStreamSaysWhenTheCatalogIsAway(t *testing.T) {
	t.Parallel()
	for name, c := range map[string]struct {
		err    error
		status int
		code   string
	}{
		"a catalog hand-off":   {fmt.Errorf("reading the item: %w", ErrCatalogMaintenance), http.StatusServiceUnavailable, "catalog-maintenance"},
		"an item that is gone": {errors.New("no item with pid tr-X"), http.StatusNotFound, "not-found"},
	} {
		t.Run(name, func(t *testing.T) {
			b := newTestBridge(t, func(w http.ResponseWriter, r *http.Request) {
				t.Error("the engine was asked for a source that did not resolve")
			}, Source{Path: filepath.Join(t.TempDir(), "song.flac")})
			b.resolver = refusingResolver{c.err}
			rec := httptest.NewRecorder()
			b.ServeShareStream(rec, httptest.NewRequest("GET", "/s/x/stream", nil), "tr-X", "us-1")
			wantEnvelope(t, rec, c.status, c.code)
		})
	}
}
