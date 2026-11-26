package api

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/service"
	"github.com/colespringer/waxdeck/server/internal/syncsource"
)

// An acquisition refused for its address answers invalid-request naming
// why, so a client can place it under the link.
func TestAnAcquisitionRefusedForItsAddressSaysWhy(t *testing.T) {
	t.Parallel()
	src := &fakeAcquireSource{playlistURL: "https://tube.example/watch?v=one"}
	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.SourceProviders = append(cfg.SourceProviders, src)
		for i := range cfg.Roots {
			cfg.Roots[i].Managed = true
		}
	})
	for link, reason := range map[string]string{
		"http://127.0.0.1/watch?v=one":   "blocked-address",
		"ftp://tube.example/watch?v=one": "invalid-address",
	} {
		resp := h.postJSON(t, "/api/v1/acquisitions", map[string]any{"url": link, "mediaType": "music"})
		body := decodeStatus[Error](t, resp, 400, "acquire "+link)
		if body.Code != "invalid-request" || body.Params == nil || (*body.Params)["reason"] != reason {
			t.Errorf("acquiring %s = %+v, want invalid-request for %s", link, body, reason)
		}
	}
}

// leavingProbeSource is a source whose link check waits for the request to
// end, saying when it started.
type leavingProbeSource struct {
	*fakeAcquireSource
	probing chan struct{}
}

func (s *leavingProbeSource) Probe(ctx context.Context, _ string, _ bool) (syncsource.AcquireTarget, error) {
	close(s.probing)
	<-ctx.Done()
	return syncsource.AcquireTarget{}, ctx.Err()
}

// A client that leaves during the link check is gone, not a fault: the
// answer is torn down as for any request whose client went away, never
// written as internal.
func TestAClientLeavingDuringTheLinkCheckIsNoInternalFault(t *testing.T) {
	t.Parallel()
	src := &leavingProbeSource{fakeAcquireSource: &fakeAcquireSource{playlistURL: "https://tube.example/watch?v=one"}, probing: make(chan struct{})}
	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.SourceProviders = append(cfg.SourceProviders, src)
		cfg.AllowPrivateFeedHosts = true
		for i := range cfg.Roots {
			cfg.Roots[i].Managed = true
		}
	})
	ctx, leave := context.WithCancel(context.Background())
	raw, _ := json.Marshal(map[string]any{"url": "https://tube.example/watch?v=one", "mediaType": "music"})
	req := httptest.NewRequestWithContext(ctx, "POST", "/api/v1/acquisitions", bytes.NewReader(raw))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+h.token)
	rec := httptest.NewRecorder()
	go func() {
		<-src.probing
		leave()
	}()
	var aborted any
	func() {
		defer func() { aborted = recover() }()
		h.ts.Config.Handler.ServeHTTP(rec, req)
	}()
	if err, _ := aborted.(error); !errors.Is(err, http.ErrAbortHandler) {
		t.Errorf("the handler ended with %v (answered %d %s), want the answer torn down", aborted, rec.Code, rec.Body.String())
	}
	if rec.Code == http.StatusInternalServerError || bytes.Contains(rec.Body.Bytes(), []byte(`"internal"`)) {
		t.Errorf("a client that left was answered %d %s", rec.Code, rec.Body.String())
	}
}
