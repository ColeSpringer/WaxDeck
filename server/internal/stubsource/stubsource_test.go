package stubsource

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/colespringer/waxbin/source"
	"github.com/colespringer/waxbin/waxerr"
)

// A manifest the stub cannot read fails classed as the source's, as the
// real bridge's failures are, so a sync can tell it from the catalog's.
func TestAnUnreadableManifestIsTheSources(t *testing.T) {
	t.Parallel()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		http.Error(w, "gone", http.StatusServiceUnavailable)
	}))
	t.Cleanup(srv.Close)
	p := New(srv.URL)
	if _, err := p.Enumerate(context.Background(), source.Request{URL: srv.URL + "/playlist/x"}); waxerr.CodeOf(err) != waxerr.CodeIO {
		t.Errorf("enumerate failed with %v (class %q), want io", err, waxerr.CodeOf(err))
	}
	if _, err := p.Resolve(context.Background(), source.Request{URL: srv.URL + "/playlist/x"}); waxerr.CodeOf(err) != waxerr.CodeIO {
		t.Errorf("resolve failed with %v (class %q), want io", err, waxerr.CodeOf(err))
	}
}
