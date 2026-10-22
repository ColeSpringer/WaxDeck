package api

import (
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
)

// A server whose podcast directory is off refuses a subscribe and an OPML
// import as a feature it is not running, naming podcasts as the feature,
// and never asks the feed's host.
func TestAServerWithPodcastsOffRefusesSubscribing(t *testing.T) {
	t.Parallel()
	var hits atomic.Int32
	host := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits.Add(1)
		w.Header().Set("Content-Type", "application/rss+xml")
		_, _ = w.Write([]byte(`<?xml version="1.0"?><rss version="2.0"><channel><title>Off</title></channel></rss>`))
	}))
	t.Cleanup(host.Close)
	h := newHarness(t)
	feed := host.URL + "/feed.xml"
	for _, door := range []struct {
		what, path string
		body       map[string]any
	}{
		{"a subscribe", "/api/v1/podcasts", map[string]any{"url": feed}},
		{"an OPML import", "/api/v1/podcasts/opml", map[string]any{
			"opml": `<opml version="2.0"><body><outline type="rss" text="Off" xmlUrl="` + feed + `"/></body></opml>`}},
	} {
		resp := h.postJSON(t, door.path, door.body)
		if resp.StatusCode != http.StatusNotImplemented {
			t.Errorf("%s status = %d, want 501", door.what, resp.StatusCode)
			resp.Body.Close()
			continue
		}
		e := decode[Error](t, resp)
		if e.Code != "feature-unavailable" || e.Message != "podcasts are turned off on this server" ||
			e.Params == nil || (*e.Params)["feature"] != "podcasts" {
			t.Errorf("%s answered %+v, want feature-unavailable naming podcasts", door.what, e)
		}
	}
	if n := hits.Load(); n != 0 {
		t.Errorf("the feed's host was asked %d times, want never", n)
	}
}
