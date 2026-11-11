package service

import (
	"context"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// silenceJobs is a jobs surface whose silence analysis runs measure.
type silenceJobs struct {
	stubFlowJobs
	measure func(ctx context.Context, path string) (flow.SilenceAnalysis, error)
}

func (j silenceJobs) AnalyzeSilence(ctx context.Context, path string) (flow.SilenceAnalysis, error) {
	return j.measure(ctx, path)
}

// oneSpan is a measurement finding one silence span.
func oneSpan(context.Context, string) (flow.SilenceAnalysis, error) {
	return mappingJobs{}.AnalyzeSilence(context.Background(), "")
}

// queueSilence queues silence analysis of the track's audio on a jobs
// surface whose runs measure, and answers the essence it is queued under.
func (s rewrittenTrack) queueSilence(t *testing.T, measure func(context.Context, string) (flow.SilenceAnalysis, error)) string {
	t.Helper()
	s.svc.SetFlowJobs(silenceJobs{stubFlowJobs{jobs: true, version: "v1"}, measure})
	essence := s.key(t)
	if err := s.svc.db.EnqueueAnalysis(s.ctx, essence, string(s.bare), 1); err != nil {
		t.Fatal(err)
	}
	return essence
}

// silenceRowFree answers the queued analysis a drain could lease now.
func silenceRowFree(t *testing.T, ctx context.Context, svc *Library) (wdb.QueueRow, error) {
	t.Helper()
	return svc.db.LeaseAnalysis(ctx, time.Now().UnixNano(), 1, analysisMaxAttempts)
}

// A hand-off that begins after the drain's check fails its catalog reads,
// which is no verdict on the audio: the entry keeps its attempts and waits
// for the catalog, not for a failure's backoff.
func TestAHandOffBeginningMidDrainSpendsNoSilenceAttempt(t *testing.T) {
	t.Parallel()
	s := newRewrittenTrack(t)
	s.queueSilence(t, oneSpan)
	handOff(t, s.ctx, s.svc, true)

	if s.svc.DrainAnalysisQueue(s.ctx) {
		t.Error("the drain went on through a hand-off")
	}
	if row, err := silenceRowFree(t, s.ctx, s.svc); err != nil || row.Attempts != 0 {
		t.Errorf("queued analysis = %+v (%v), want it free to lease and unattempted", row, err)
	}
	if logs := s.logs.String(); strings.Contains(logs, "silence analysis failed") {
		t.Errorf("the hand-off was logged as a failed analysis:\n%s", logs)
	}
}

// A shutdown cutting a measurement short is no verdict either: the entry
// is free again for the next start, with its attempts.
func TestAShutdownMidAnalysisSpendsNoSilenceAttempt(t *testing.T) {
	t.Parallel()
	s := newRewrittenTrack(t)
	drainCtx, cancel := context.WithCancel(s.ctx)
	defer cancel()
	s.queueSilence(t, func(ctx context.Context, _ string) (flow.SilenceAnalysis, error) {
		cancel()
		return flow.SilenceAnalysis{}, fmt.Errorf("waiting for the job: %w", ctx.Err())
	})

	if s.svc.DrainAnalysisQueue(drainCtx) {
		t.Error("the drain went on after its context ended")
	}
	if row, err := silenceRowFree(t, s.ctx, s.svc); err != nil || row.Attempts != 0 {
		t.Errorf("queued analysis = %+v (%v), want it free to lease and unattempted", row, err)
	}
	if logs := s.logs.String(); strings.Contains(logs, "silence analysis failed") {
		t.Errorf("the shutdown was logged as a failed analysis:\n%s", logs)
	}
}
