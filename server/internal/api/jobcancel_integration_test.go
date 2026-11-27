package api

import (
	"context"
	"sync"
	"testing"
	"time"

	"github.com/colespringer/waxbin/enrich"
	"github.com/colespringer/waxbin/proxy"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// heldLyrics holds its lookup until the run's context ends, and then
// until it is let go, so the pass reads as winding down for as long as
// the test reads it.
type heldLyrics struct {
	asked, ended, release chan struct{}
	letGo                 func()
}

func newHeldLyrics() *heldLyrics {
	p := &heldLyrics{asked: make(chan struct{}, 1), ended: make(chan struct{}, 1), release: make(chan struct{})}
	p.letGo = sync.OnceFunc(func() { close(p.release) })
	return p
}

func (p *heldLyrics) Name() string                    { return "held" }
func (p *heldLyrics) Capabilities() enrich.Capability { return enrich.CapLyrics }
func (p *heldLyrics) Enrich(ctx context.Context, _ enrich.Request) (*enrich.Candidate, error) {
	select {
	case p.asked <- struct{}{}:
	default:
	}
	select {
	case <-ctx.Done():
	case <-p.release:
		return nil, context.Canceled
	}
	select {
	case p.ended <- struct{}{}:
	default:
	}
	<-p.release
	return nil, ctx.Err()
}

// A pass an administrator started cancels: it answers running with the
// cancel asked for, ends canceled, and a cancel of it then answers it
// unchanged. Nobody else may cancel it, and a pid naming no job is not
// found.
func TestCancelingACatalogPass(t *testing.T) {
	t.Parallel()
	p := newHeldLyrics()
	h := newHarnessWith(t, func(c *service.Config) {
		c.EnrichmentProviders = []enrich.Provider{p}
	})
	defer p.letGo()
	_, tokens, _ := wsAccount(t, h, "listener")
	member := tokens[0]

	run := decodeStatus[EnrichmentRunResult](t, h.postJSON(t, "/api/v1/library/enrichment/run", map[string]any{}), 202, "start the pass")
	<-p.asked
	cancelPath := "/api/v1/jobs/" + run.JobPid + "/cancel"
	if j := decodeStatus[Job](t, get(t, h.ts, "/api/v1/jobs/"+run.JobPid, h.token), 200, "the pass"); !j.Cancelable || j.CancelRequested {
		t.Fatalf("the running pass = %+v, want cancelable", j)
	}

	wantStatus(t, reqAs(t, h, "POST", cancelPath, member, nil), 403, "a member's cancel")
	wantStatus(t, reqAs(t, h, "POST", cancelPath, "", nil), 401, "an unauthenticated cancel")
	wantStatus(t, reqAs(t, h, "POST", "/api/v1/jobs/jb-01JZX5N8QW3F4V9T2B7KDEXAMPL/cancel", h.token, nil), 404, "a cancel of no job")

	asked := decodeStatus[Job](t, reqAs(t, h, "POST", cancelPath, h.token, nil), 200, "the administrator's cancel")
	if asked.Pid != run.JobPid || asked.State != "running" || !asked.CancelRequested || asked.Cancelable {
		t.Fatalf("the cancel's answer = %+v, want running with the cancel asked for", asked)
	}
	<-p.ended
	p.letGo()
	deadline := time.Now().Add(30 * time.Second)
	for {
		j := decodeStatus[Job](t, get(t, h.ts, "/api/v1/jobs/"+run.JobPid, h.token), 200, "the pass")
		if j.State == "canceled" {
			if j.CancelRequested || j.Cancelable {
				t.Fatalf("the canceled pass = %+v, want neither flag", j)
			}
			break
		}
		if j.State != "running" || time.Now().After(deadline) {
			t.Fatalf("the pass = %+v, want it to end canceled", j)
		}
		time.Sleep(20 * time.Millisecond)
	}
	if again := decodeStatus[Job](t, reqAs(t, h, "POST", cancelPath, h.token, nil), 200, "a cancel once ended"); again.State != "canceled" {
		t.Errorf("a cancel of the canceled pass = %+v, want it unchanged", again)
	}

	scan := h.rescanAndWait(t)
	if j := decodeStatus[Job](t, reqAs(t, h, "POST", "/api/v1/jobs/"+scan+"/cancel", h.token, nil), 200, "a cancel of a finished scan"); j.State != "done" || j.Cancelable {
		t.Errorf("a cancel of a finished scan = %+v, want it unchanged", j)
	}
}

// A timeline measurement runs to its end: its minter's cancel is refused
// with that reason while it runs, and anyone else's is not found.
func TestATimelineMeasurementRunsToItsEnd(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	h.pendingTimeline.Store(true)
	items := h.items(t, "").Items
	job := decodeStatus[Job](t, h.postJSON(t, "/api/v1/player/timeline", map[string]any{
		"itemPids": []string{items[0].Pid, items[1].Pid},
	}), 202, "a timeline mint the engine is still measuring")
	refused := decodeStatus[Error](t, reqAs(t, h, "POST", "/api/v1/jobs/"+job.Pid+"/cancel", h.token, nil), 409, "the minter's cancel")
	if refused.Code != "conflict" || refused.Params == nil || (*refused.Params)["reason"] != "job-runs-to-end" {
		t.Errorf("the refusal = %+v, want a conflict naming job-runs-to-end", refused)
	}
	_, tokens, _ := wsAccount(t, h, "bystander")
	wantStatus(t, reqAs(t, h, "POST", "/api/v1/jobs/"+job.Pid+"/cancel", tokens[0], nil), 404, "another account's cancel")
}

// A pass the command line submitted runs under the catalog's own context,
// out of this server's reach: its cancel is refused naming why, and the
// pass runs on.
func TestACancelOfAPassTheServerDoesNotHoldIsRefused(t *testing.T) {
	t.Parallel()
	p := newHeldLyrics()
	var dataDir string
	h := newHarnessWith(t, func(c *service.Config) {
		c.EnrichmentProviders = []enrich.Provider{p}
		dataDir = c.DataDir
	})
	defer p.letGo()
	pid, err := handOffClient(t, dataDir).RunEnrich(context.Background(), proxy.EnrichParams{})
	if err != nil {
		t.Fatal(err)
	}
	<-p.asked
	jobPath := "/api/v1/jobs/" + service.PrefixJob + "-" + string(pid)
	if j := decodeStatus[Job](t, get(t, h.ts, jobPath, h.token), 200, "the pass"); j.State != "running" || j.Cancelable {
		t.Fatalf("the command line's pass = %+v, want running and not cancelable", j)
	}
	refused := decodeStatus[Error](t, reqAs(t, h, "POST", jobPath+"/cancel", h.token, nil), 409, "its cancel")
	if refused.Code != "conflict" || refused.Params == nil || (*refused.Params)["reason"] != "job-not-held" {
		t.Errorf("the refusal = %+v, want a conflict naming job-not-held", refused)
	}
	if j := decodeStatus[Job](t, get(t, h.ts, jobPath, h.token), 200, "the pass"); j.State != "running" {
		t.Errorf("after the refused cancel the pass = %+v, want it running on", j)
	}
}
