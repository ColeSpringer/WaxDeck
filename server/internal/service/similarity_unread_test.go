package service

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"testing"

	"github.com/colespringer/waxbin/model"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// attemptsOf is how many attempts the queue has charged key.
func attemptsOf(t *testing.T, ctx context.Context, svc *Library, key string) int {
	t.Helper()
	var n int
	if err := svc.db.Writer().QueryRowContext(ctx,
		`SELECT attempts FROM similarity_queue WHERE essence = ?`, key).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n
}

// A catalog read that fails attempted nothing: were it charged, a failure
// lasting eight leases would leave every queued track out of attempts for
// good once the catalog healed.
func TestAFailedReadSpendsNoSonicAttempt(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		name  string
		batch int
		read  func(ctx context.Context, svc *Library) error
	}{
		{"embedded", embeddedAnalysisBatch, func(ctx context.Context, svc *Library) error {
			_, err := svc.Similarity.DrainEmbeddedAnalysis(ctx, &windowAnalyzer{})
			return err
		}},
		{"leased", 50, func(ctx context.Context, svc *Library) error {
			_, err := svc.Similarity.LeaseSimilarityWork(ctx, 50, true)
			return err
		}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			ctx, svc, queued := sonicQueueFixture(t)
			if queued > tc.batch {
				t.Fatalf("%d rows queued, want one batch of %d to lease them all", queued, tc.batch)
			}
			svc.catalogItem = func(context.Context, model.PID) (*model.ItemView, error) {
				return nil, errors.New("database is locked")
			}

			if err := tc.read(ctx, svc); err != nil {
				t.Fatal(err)
			}
			states, err := svc.db.SimilarityQueueStates(ctx)
			if err != nil {
				t.Fatal(err)
			}
			for key := range states {
				if n := attemptsOf(t, ctx, svc, key); n != 0 {
					t.Errorf("%s spent %d attempts on reads that failed", key, n)
				}
			}
			if got := unleased(t, ctx, svc); got != 0 {
				t.Errorf("%d rows free to lease, want them all held until their lease lapses", got)
			}
		})
	}
}

// A hand-off or a shutdown that stops a batch midway is no verdict on the
// rows it left unsettled: each keeps the attempt count it had before the
// lease, and waits out its lease.
func TestAnInterruptedSonicBatchSpendsNoAttempt(t *testing.T) {
	t.Parallel()
	closed := errors.New("database is closed")
	for _, tc := range []struct {
		name string
		stop func(ctx context.Context, svc *Library)
	}{
		{"embedded, a hand-off at a read", func(ctx context.Context, svc *Library) {
			svc.catalogItem = func(context.Context, model.PID) (*model.ItemView, error) { return nil, closed }
			svc.Similarity.DrainEmbeddedAnalysis(ctx, &windowAnalyzer{})
		}},
		{"embedded, a hand-off at the report", func(ctx context.Context, svc *Library) {
			read, reads := svc.catalogItem, map[model.PID]int{}
			svc.catalogItem = func(ctx context.Context, pid model.PID) (*model.ItemView, error) {
				// The track read a second time is read for its report.
				if reads[pid]++; reads[pid] == 2 {
					return nil, closed
				}
				return read(ctx, pid)
			}
			svc.Similarity.DrainEmbeddedAnalysis(ctx, &windowAnalyzer{})
		}},
		{"embedded, a shutdown mid-decode", func(ctx context.Context, svc *Library) {
			ctx, cancel := context.WithCancel(ctx)
			defer cancel()
			svc.Similarity.DrainEmbeddedAnalysis(ctx, &cancellingAnalyzer{cancel: cancel})
		}},
		{"embedded, a shutdown at a read", func(ctx context.Context, svc *Library) {
			ctx, cancel := context.WithCancel(ctx)
			defer cancel()
			svc.catalogItem = func(context.Context, model.PID) (*model.ItemView, error) {
				cancel()
				return nil, ctx.Err()
			}
			svc.Similarity.DrainEmbeddedAnalysis(ctx, &windowAnalyzer{})
		}},
		{"leased, a hand-off at a read", func(ctx context.Context, svc *Library) {
			svc.catalogItem = func(context.Context, model.PID) (*model.ItemView, error) { return nil, closed }
			svc.Similarity.LeaseSimilarityWork(ctx, 50, true)
		}},
		{"leased, a request ending after a row was ready", func(ctx context.Context, svc *Library) {
			ctx, cancel := context.WithCancel(ctx)
			defer cancel()
			read, reads := svc.catalogItem, 0
			svc.catalogItem = func(rctx context.Context, pid model.PID) (*model.ItemView, error) {
				if reads++; reads == 2 {
					cancel()
					return nil, ctx.Err()
				}
				return read(rctx, pid)
			}
			svc.Similarity.LeaseSimilarityWork(ctx, 50, true)
		}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			ctx, svc, queued := sonicQueueFixture(t)
			if queued > embeddedAnalysisBatch {
				t.Fatalf("%d rows queued, want one embedded batch of %d to lease them all", queued, embeddedAnalysisBatch)
			}

			tc.stop(ctx, svc)
			states, err := svc.db.SimilarityQueueStates(ctx)
			if err != nil {
				t.Fatal(err)
			}
			for key := range states {
				if n := attemptsOf(t, ctx, svc, key); n != 0 {
					t.Errorf("%s spent %d attempts in a batch that stopped", key, n)
				}
			}
			if got := unleased(t, ctx, svc); got != 0 {
				t.Errorf("%d rows free to lease, want the batch's rows held until their lease lapses", got)
			}
		})
	}
}

// A catalog read that fails while a report is checked settles that vector
// alone: it is refused, its work stays leased to come back, and the rest
// of the report is filed.
func TestAnUnreadableTrackInAReportSettlesOnlyItsVector(t *testing.T) {
	t.Parallel()
	ctx, svc, queued := sonicQueueFixture(t)
	var uploads []EmbeddingUpload
	for pid, w := range leaseAll(t, ctx, svc) {
		uploads = append(uploads, EmbeddingUpload{PID: pid, Essence: w.Essence, Vector: []float32{1, 0, 0, 0, 0, 0, 0, 0}})
	}
	read, bad := svc.catalogItem, &failFirst{}
	svc.catalogItem = func(ctx context.Context, pid model.PID) (*model.ItemView, error) {
		if bad.fail(pid) {
			return nil, errors.New("database is locked")
		}
		return read(ctx, pid)
	}

	res, err := svc.Similarity.IngestEmbeddings(ctx, "test", 8, uploads)
	if err != nil {
		t.Fatalf("report with one unreadable track: %v, want the rest filed", err)
	}
	if res.Accepted != len(uploads)-1 || len(res.Rejected) != 1 {
		t.Fatalf("report = %+v, want every vector filed but the unreadable track's", res)
	}
	if rej := res.Rejected[0]; rej.PID != apiPID(PrefixTrack, bad.pid) || rej.Code != string(KindInternal) {
		t.Errorf("refused %+v, want %s refused as %s", rej, apiPID(PrefixTrack, bad.pid), KindInternal)
	}
	if got := embeddingCount(t, ctx, svc); got != queued-1 {
		t.Errorf("%d vectors stored, want %d", got, queued-1)
	}
	if got := queueDepth(t, ctx, svc); got != 1 {
		t.Errorf("%d rows left queued, want only the unreadable track's", got)
	}
	if got := unleased(t, ctx, svc); got != 0 {
		t.Errorf("%d rows free to lease, want the unreadable track's held until its lease lapses", got)
	}
}

// A hand-off ends a report, since every read fails then: nothing more is
// filed, and the work stays queued for the worker that sends it again.
func TestAReportMeetingAHandOffEndsWithItsWorkQueued(t *testing.T) {
	t.Parallel()
	ctx, svc, queued := sonicQueueFixture(t)
	var uploads []EmbeddingUpload
	for pid, w := range leaseAll(t, ctx, svc) {
		uploads = append(uploads, EmbeddingUpload{PID: pid, Essence: w.Essence, Vector: []float32{1, 0, 0, 0, 0, 0, 0, 0}})
	}
	svc.catalogItem = func(context.Context, model.PID) (*model.ItemView, error) {
		return nil, errors.New("database is closed")
	}

	if _, err := svc.Similarity.IngestEmbeddings(ctx, "test", 8, uploads); KindOf(err) != KindMaintenance {
		t.Errorf("report during a hand-off: %v, want a catalog-maintenance failure", err)
	}
	if got := embeddingCount(t, ctx, svc); got != 0 {
		t.Errorf("%d vectors filed during the hand-off", got)
	}
	if got := queueDepth(t, ctx, svc); got != queued {
		t.Errorf("%d of %d queued rows kept, want all of them", got, queued)
	}
}

// The same read failing after the decode, as the embedded analysis files
// its vector, settles that row alone: it stays leased and unjudged, and
// the rest of the batch is analyzed.
func TestAnUnreadableTrackAfterItsDecodeLeavesTheBatchServed(t *testing.T) {
	t.Parallel()
	ctx, svc, queued := sonicQueueFixture(t)
	read := svc.catalogItem
	reads := map[model.PID]int{}
	var bad model.PID
	svc.catalogItem = func(ctx context.Context, pid model.PID) (*model.ItemView, error) {
		reads[pid]++
		// The first track read a second time is read for its report.
		if bad == "" && reads[pid] == 2 {
			bad = pid
			return nil, errors.New("database is locked")
		}
		return read(ctx, pid)
	}

	if worked, err := svc.Similarity.DrainEmbeddedAnalysis(ctx, &windowAnalyzer{}); !worked || err != nil {
		t.Fatalf("drain = %v, %v; want the batch served", worked, err)
	}
	if bad == "" {
		t.Fatal("no track was read for its report")
	}
	if got := embeddingCount(t, ctx, svc); got != queued-1 {
		t.Errorf("%d vectors stored, want %d: every row but the one whose report was unreadable", got, queued-1)
	}
	if got := queueDepth(t, ctx, svc); got != 1 {
		t.Errorf("%d rows left queued, want only the unreadable one, unjudged", got)
	}
	if got := unleased(t, ctx, svc); got != 0 {
		t.Errorf("%d rows free to lease, want the unreadable one held until its lease lapses", got)
	}
}

// cancellingAnalyzer ends its drain mid-decode, as a shutdown does, and
// fails the way a decode cut short does.
type cancellingAnalyzer struct {
	windowAnalyzer
	cancel context.CancelFunc
}

func (a *cancellingAnalyzer) AnalyzeFileWindow(ctx context.Context, _ string, _, _ int64) ([]float32, error) {
	a.cancel()
	return nil, fmt.Errorf("decoding: %w", ctx.Err())
}

// A shutdown cutting a decode short is no verdict on the audio: the track
// is neither rested as unreadable nor said to be.
func TestAShutdownMidDecodeRestsNothing(t *testing.T) {
	t.Parallel()
	logs := &syncBuffer{}
	ctx, svc, uc := newCatalogFixtureWith(t, catalogFixtureOptions{logs: logs})
	enableSonicAnalysis(t, ctx, svc, uc)
	if _, err := svc.Similarity.Sweep(ctx); err != nil {
		t.Fatal(err)
	}
	drainCtx, cancel := context.WithCancel(ctx)
	defer cancel()

	if _, err := svc.Similarity.DrainEmbeddedAnalysis(drainCtx, &cancellingAnalyzer{cancel: cancel}); err != nil {
		t.Fatal(err)
	}
	if strings.Contains(logs.String(), "it rests until its audio changes") {
		t.Errorf("a shutdown was logged as a verdict on the audio:\n%s", logs)
	}
	states, err := svc.db.SimilarityQueueStates(ctx)
	if err != nil {
		t.Fatal(err)
	}
	for key, st := range states {
		if st == wdb.QueueRetired {
			t.Errorf("%s rests after a shutdown cut its decode short", key)
		}
	}
}

// A shutdown that stops the drain before it leases is no failure either:
// the worker loop logs every error the drain returns, and this one would
// say only that the server was stopping.
func TestAShutdownBeforeTheLeaseIsNoFailure(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixtureWith(t, catalogFixtureOptions{logs: &syncBuffer{}})
	enableSonicAnalysis(t, ctx, svc, uc)
	if _, err := svc.Similarity.Sweep(ctx); err != nil {
		t.Fatal(err)
	}
	drainCtx, cancel := context.WithCancel(ctx)
	cancel()

	worked, err := svc.Similarity.DrainEmbeddedAnalysis(drainCtx, &cancellingAnalyzer{cancel: cancel})
	if err != nil || worked {
		t.Errorf("a drain stopped before its lease = %v, %v; want no work and no error", worked, err)
	}
}
