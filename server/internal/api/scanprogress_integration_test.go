package api

import (
	"context"
	"log/slog"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// walkHold is a log handler that, once armed, holds whatever logs a
// warning about a file under dir until it is released. The scan warns
// about an unreadable file from inside its walk, so that call is the hook
// that stops a scan halfway.
type walkHold struct{ s *walkHoldState }

type walkHoldState struct {
	dir     string
	armed   atomic.Bool
	once    sync.Once
	held    chan struct{}
	release chan struct{}
}

func (h walkHold) Enabled(context.Context, slog.Level) bool { return true }

func (h walkHold) Handle(_ context.Context, r slog.Record) error {
	if !h.s.armed.Load() || r.Level < slog.LevelWarn {
		return nil
	}
	r.Attrs(func(a slog.Attr) bool {
		if a.Key == "path" && strings.HasPrefix(a.Value.String(), h.s.dir) {
			h.s.once.Do(func() { close(h.s.held) })
			<-h.s.release
			return false
		}
		return true
	})
	return nil
}

func (h walkHold) WithAttrs([]slog.Attr) slog.Handler { return h }
func (h walkHold) WithGroup(string) slog.Handler      { return h }

// A running scan's fraction reaches the job the API answers. A scan of
// two libraries has said it is half done once the first is walked, and
// still says so while the second is.
func TestARunningScanReportsItsFraction(t *testing.T) {
	t.Parallel()
	second := t.TempDir()
	hold := &walkHoldState{dir: second, held: make(chan struct{}), release: make(chan struct{})}
	h := newHarnessWith(t, func(c *service.Config) { c.Logger = slog.New(walkHold{hold}) },
		service.Root{Name: "second", Path: second})
	// Released however the test ends, so the held scan lets the server stop.
	var released sync.Once
	release := func() { released.Do(func() { close(hold.release) }) }
	t.Cleanup(release)

	// Written after the harness's own scan, so the next one reads it whole.
	if _, err := fixtures.Generate(second, fixtures.Spec{
		Name: "static", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
		Corrupt: fixtures.CorruptGarbage,
		Tags:    map[string]string{"TITLE": "Static", "ARTIST": "Static", "ALBUM": "Static"},
	}); err != nil {
		t.Fatal(err)
	}
	hold.armed.Store(true)
	job := decodeStatus[Job](t, h.postJSON(t, "/api/v1/library/rescan", map[string]any{}), 202, "rescan")
	select {
	case <-hold.held:
	case <-time.After(time.Minute):
		t.Fatal("the scan never reached the second library's file")
	}

	running := decode[Job](t, get(t, h.ts, "/api/v1/jobs/"+job.Pid, h.token))
	if running.State != "running" || running.Progress == nil || *running.Progress != 0.5 {
		t.Fatalf("the job while the second library is walked = %+v, want running at 0.5", running)
	}
	var listed *Job
	for _, j := range decode[JobList](t, get(t, h.ts, "/api/v1/jobs", h.token)).Jobs {
		if j.Pid == job.Pid {
			listed = &j
		}
	}
	if listed == nil || listed.Progress == nil || *listed.Progress != 0.5 {
		t.Fatalf("the listing's row for the scan = %+v, want it at 0.5", listed)
	}

	release()
	deadline := time.Now().Add(time.Minute)
	for {
		j := decode[Job](t, get(t, h.ts, "/api/v1/jobs/"+job.Pid, h.token))
		switch {
		case j.State == "done":
			if j.Progress == nil || *j.Progress != 1 {
				t.Errorf("the finished scan's progress = %v, want 1", j.Progress)
			}
			return
		case j.State != "running":
			t.Fatalf("the scan ended %s (%v), want done", j.State, deref(j.Error))
		case time.Now().After(deadline):
			t.Fatal("the released scan did not finish")
		}
		time.Sleep(20 * time.Millisecond)
	}
}
