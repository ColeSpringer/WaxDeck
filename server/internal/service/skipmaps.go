package service

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"time"

	"github.com/colespringer/waxbin/model"

	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// Silence skip maps: cached spans clients trim by seeking over. Maps
// key on the audio essence (retags and moves never invalidate) plus
// the upstream detector version; the same analysis measures loudness,
// which voice-boost leveling reads.

// SkipSpan is one silence span in the mapped file's own timeline.
type SkipSpan struct {
	StartMS int64
	EndMS   int64
}

// SkipMapResult is the skip-map endpoint's answer.
type SkipMapResult struct {
	State       string
	EssenceHash string
	PartIndex   *int
	Version     string
	ThresholdDB float64
	MinSeconds  float64
	Spans       []SkipSpan
	CreatedAtNS int64
}

const (
	skipStateReady       = "ready"
	skipStatePending     = "pending"
	skipStateUnavailable = "unavailable"
	// analysisLease bounds one analysis attempt; jobs on big books can
	// legitimately run minutes.
	analysisLease       = 30 * time.Minute
	analysisMaxAttempts = 5
)

// SkipMapFor answers one item's skip map, queuing analysis on a miss
// when the item is mappable. partIndex selects a multi-file book's
// part (ignored elsewhere).
func (l *Library) SkipMapFor(ctx context.Context, uc *UserCtx, apiItemPID string, partIndex int) (SkipMapResult, error) {
	it, err := l.getVisibleItem(ctx, uc, apiItemPID)
	if err != nil {
		return SkipMapResult{}, err
	}
	if it.Kind != model.KindEpisode && it.Kind != model.KindBook {
		return SkipMapResult{State: skipStateUnavailable}, nil
	}
	if it.Kind == model.KindEpisode && it.State != model.StatePresent {
		// Remote episodes have no bytes to analyze; the state may flip
		// after a fetch.
		return SkipMapResult{State: skipStateUnavailable}, nil
	}

	filePID := ""
	var partOut *int
	if it.Kind == model.KindBook {
		bd, err := l.lib.Book(ctx, it.PID)
		if err != nil {
			return SkipMapResult{}, classify(err)
		}
		if len(bd.Files) >= 2 {
			if partIndex < 0 || partIndex >= len(bd.Files) {
				return SkipMapResult{}, errInvalid("partIndex is out of range")
			}
			filePID = string(bd.Files[partIndex].FilePID)
			idx := partIndex
			partOut = &idx
		}
	}

	f, err := l.streamFile(ctx, it, filePID)
	if err != nil {
		return SkipMapResult{}, err
	}
	if f.EssenceHash == "" {
		return SkipMapResult{State: skipStateUnavailable}, nil
	}

	m, err := l.db.SilenceMapFor(ctx, f.EssenceHash)
	if err == nil {
		spans, decodeErr := decodeSkipSpans(m.Spans)
		if decodeErr != nil {
			return SkipMapResult{}, &Error{Kind: KindInternal, Err: decodeErr}
		}
		return SkipMapResult{
			State:       skipStateReady,
			EssenceHash: m.EssenceHash,
			PartIndex:   partOut,
			Version:     m.DetectorVersion,
			ThresholdDB: m.ThresholdDB,
			MinSeconds:  m.MinSeconds,
			Spans:       spans,
			CreatedAtNS: m.CreatedAtNS,
		}, nil
	}
	if !errors.Is(err, wdb.ErrNotFound) {
		return SkipMapResult{}, &Error{Kind: KindInternal, Err: err}
	}
	if l.flowJobs == nil || !l.flowJobs.JobsSupported() {
		return SkipMapResult{State: skipStateUnavailable}, nil
	}
	key := string(it.PID)
	if filePID != "" {
		key = key + "|" + filePID
	}
	if err := l.db.EnqueueAnalysis(ctx, f.EssenceHash, key, time.Now().UnixNano()); err != nil {
		return SkipMapResult{}, &Error{Kind: KindInternal, Err: err}
	}
	return SkipMapResult{State: skipStatePending, EssenceHash: f.EssenceHash, PartIndex: partOut}, nil
}

// streamFile resolves the file a skip map describes: the named part,
// or the item's own backing file.
func (l *Library) streamFile(ctx context.Context, it *model.ItemView, filePID string) (*model.File, error) {
	if filePID != "" {
		return l.fileByPID(ctx, model.PID(filePID))
	}
	loc, err := l.paths.Locate(ctx, it.PID)
	if err != nil {
		return nil, classify(err)
	}
	return l.fileByPID(ctx, loc.FilePID)
}

// enqueueAnalysisForItem queues silence analysis for an item's backing
// file, best effort (a fetch that lands without a map gets one on the
// first skip-map request instead).
func (l *Library) enqueueAnalysisForItem(ctx context.Context, pid model.PID) {
	if l.flowJobs == nil || !l.flowJobs.JobsSupported() {
		return
	}
	loc, err := l.paths.Locate(ctx, pid)
	if err != nil {
		return
	}
	f, err := l.lib.File(ctx, loc.FilePID)
	if err != nil || f.EssenceHash == "" {
		return
	}
	if err := l.db.EnqueueAnalysis(ctx, f.EssenceHash, string(pid), time.Now().UnixNano()); err != nil {
		l.log.Warn("queuing analysis", "item", string(pid), "err", err)
	}
}

// FlowJobs is the analysis surface the bridge provides; a nil bridge
// (no sidecar configured) disables skip maps.
type FlowJobs interface {
	JobsSupported() bool
	AnalyzeSilence(ctx context.Context, path string) (flow.SilenceAnalysis, error)
}

// SetFlowJobs wires the bridge's jobs surface after both sides exist
// (the bridge needs the service as its resolver, so construction is
// two-phase).
func (l *Library) SetFlowJobs(j FlowJobs) { l.flowJobs = j }

// DrainAnalysisQueue works one queued analysis; returns false when the
// queue is idle so the caller can sleep.
func (l *Library) DrainAnalysisQueue(ctx context.Context) bool {
	if l.flowJobs == nil || !l.flowJobs.JobsSupported() {
		return false
	}
	row, err := l.db.LeaseAnalysis(ctx, time.Now().UnixNano(), analysisLease.Nanoseconds(), analysisMaxAttempts)
	if err != nil {
		if !errors.Is(err, wdb.ErrNotFound) {
			l.log.Warn("leasing analysis work", "err", err)
		}
		return false
	}
	if err := l.runAnalysis(ctx, row); err != nil {
		l.log.Warn("silence analysis failed", "key", row.Key, "attempt", row.Attempts+1, "err", err)
		retryAt := time.Now().Add(queueRetryDelay(row.Attempts)).UnixNano()
		if dbErr := l.db.FailAnalysis(ctx, row.Key, err.Error(), retryAt); dbErr != nil {
			l.log.Warn("recording analysis failure", "key", row.Key, "err", dbErr)
		}
		return true
	}
	if err := l.db.CompleteAnalysis(ctx, row.Key); err != nil {
		l.log.Warn("completing analysis", "key", row.Key, "err", err)
	}
	return true
}

func (l *Library) runAnalysis(ctx context.Context, row wdb.QueueRow) error {
	itemPID, filePID, _ := strings.Cut(row.ItemPID, "|")
	var path string
	if filePID != "" {
		f, err := l.fileByPID(ctx, model.PID(filePID))
		if err != nil {
			return err
		}
		path = string(f.Path)
	} else {
		loc, err := l.paths.Locate(ctx, model.PID(itemPID))
		if err != nil {
			return classify(err)
		}
		path = loc.Path
	}

	// One analysis is bounded well under the lease so a wedged job
	// cannot pin the worker.
	runCtx, cancel := context.WithTimeout(ctx, 20*time.Minute)
	defer cancel()
	res, err := l.flowJobs.AnalyzeSilence(runCtx, path)
	if err != nil {
		return err
	}
	if res.Rate <= 0 {
		return errors.New("analysis reported no sample rate")
	}
	spans := make([]SkipSpan, 0, len(res.Spans))
	for _, s := range res.Spans {
		spans = append(spans, SkipSpan{
			StartMS: s.FromSample * 1000 / int64(res.Rate),
			EndMS:   s.ToSample * 1000 / int64(res.Rate),
		})
	}
	encoded, err := encodeSkipSpans(spans)
	if err != nil {
		return err
	}
	return l.db.PutSilenceMap(ctx, wdb.SilenceMap{
		EssenceHash:     row.Key,
		DetectorVersion: res.Version,
		ThresholdDB:     res.ThresholdDB,
		MinSeconds:      res.MinSeconds,
		Spans:           encoded,
		DurationMS:      int64(res.DurationSeconds * 1000),
		IntegratedLUFS:  res.IntegratedLUFS,
		TruePeakDB:      res.TruePeakDB,
		CreatedAtNS:     time.Now().UnixNano(),
	})
}

// Spans persist as a compact JSON array of [startMs, endMs] pairs.
func encodeSkipSpans(spans []SkipSpan) (string, error) {
	pairs := make([][2]int64, len(spans))
	for i, s := range spans {
		pairs[i] = [2]int64{s.StartMS, s.EndMS}
	}
	b, err := json.Marshal(pairs)
	if err != nil {
		return "", err
	}
	return string(b), nil
}

func decodeSkipSpans(encoded string) ([]SkipSpan, error) {
	if encoded == "" {
		return nil, nil
	}
	var pairs [][2]int64
	if err := json.Unmarshal([]byte(encoded), &pairs); err != nil {
		return nil, err
	}
	out := make([]SkipSpan, len(pairs))
	for i, p := range pairs {
		out[i] = SkipSpan{StartMS: p[0], EndMS: p[1]}
	}
	return out, nil
}
