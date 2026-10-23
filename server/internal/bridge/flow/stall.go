package flow

import (
	"context"
	"errors"
	"io"
	"net/http"
	"sync/atomic"
	"time"
)

// errEngineStalled is a wait on the engine that ran past the stall limit:
// an engine that stopped answering mid-stream, or never started, which a
// stopped or wedged process does without closing its connections.
var errEngineStalled = errors.New("the streaming engine stopped sending")

// stallTransport bounds every wait on the engine during a stream: for the
// response headers, which the engine writes at once, and for each read of
// the body, which a live encode feeds faster than it plays. Only a wait in
// progress counts: a listener who paused stops the copy at its write, so
// no read of the engine is waiting meanwhile and nothing is cut. A stall
// ends that request and asks for a probe; the probe, not one slow read,
// says whether the engine is gone (unreachable).
type stallTransport struct {
	b    *Bridge
	base http.RoundTripper
}

func (t stallTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	ctx, cancel := context.WithCancelCause(req.Context())
	var stalled atomic.Bool
	timer := time.AfterFunc(t.b.stallLimit, func() {
		stalled.Store(true)
		cancel(errEngineStalled)
	})
	resp, err := t.base.RoundTrip(req.WithContext(ctx))
	timer.Stop()
	if stalled.Load() {
		if resp != nil {
			resp.Body.Close()
		}
		cancel(nil)
		return nil, errEngineStalled
	}
	if err != nil {
		cancel(nil)
		return nil, err
	}
	resp.Body = &stallBody{ReadCloser: resp.Body, b: t.b, cancel: cancel}
	return resp, nil
}

// stallBody is an engine response body whose every read is held to the
// stall limit.
type stallBody struct {
	io.ReadCloser
	b      *Bridge
	cancel context.CancelCauseFunc
}

func (s *stallBody) Read(p []byte) (int, error) {
	var stalled atomic.Bool
	timer := time.AfterFunc(s.b.stallLimit, func() {
		stalled.Store(true)
		s.cancel(errEngineStalled)
	})
	n, err := s.ReadCloser.Read(p)
	timer.Stop()
	if stalled.Load() {
		s.b.probeSoon()
		return n, errEngineStalled
	}
	return n, err
}

func (s *stallBody) Close() error {
	err := s.ReadCloser.Close()
	s.cancel(nil)
	return err
}

// engineTransport is the connection pool every stream request to the
// engine rides, its waits held to the stall limit.
func (b *Bridge) engineTransport() http.RoundTripper {
	return stallTransport{b: b, base: http.DefaultTransport.(*http.Transport).Clone()}
}
