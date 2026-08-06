package service

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
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

// errAnalysisMoot marks queued analysis whose audio is gone: dropped
// rather than failed, since the queue is keyed by essence hash and an
// entry that spends its attempts bars that audio for good.
var errAnalysisMoot = errors.New("nothing left to analyze")

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

	filePID, partOut, err := l.resolvePart(ctx, it, partIndex)
	if err != nil {
		return SkipMapResult{}, err
	}

	f, err := l.streamFile(ctx, it, filePID)
	if err != nil {
		return SkipMapResult{}, err
	}
	if f.EssenceHash == "" {
		return SkipMapResult{State: skipStateUnavailable}, nil
	}

	m, err := l.db.SilenceMapFor(ctx, f.EssenceHash)
	if err != nil && !errors.Is(err, wdb.ErrNotFound) {
		return SkipMapResult{}, &Error{Kind: KindInternal, Err: err}
	}
	haveMap := err == nil
	stale := haveMap && l.silenceMapStale(m)

	// A miss, or a map a detector upgrade left stale: (re)queue analysis on the
	// lazy on-access path, so an upgrade re-analyzes one item at a time as it
	// is played rather than sweeping the library at once.
	if !haveMap || stale {
		if l.flowJobs == nil || !l.flowJobs.JobsSupported() {
			// No jobs surface to rebuild with; silenceMapStale already reports
			// false without one, so only a true miss reaches here.
			return SkipMapResult{State: skipStateUnavailable}, nil
		}
		// The catalog can say present while the bytes are gone (deleted
		// behind the server's back), and it exposes no state mutator for
		// WaxDeck to correct that with. Left alone, this queues work the
		// worker drops as moot and answers pending forever, so the same
		// resolution the worker does happens here first and the miss is
		// reported honestly. Resolving the path is also what tells a stale
		// located-path entry from real absence, since analysisSource
		// relocates before writing anything off.
		if _, err := l.analysisSource(ctx, string(it.PID), filePID); err != nil {
			if errors.Is(err, errAnalysisMoot) {
				return SkipMapResult{State: skipStateUnavailable}, nil
			}
			// A root that is not mounted is storage that has not arrived
			// rather than audio that is gone: queue and answer pending, so
			// the map appears once it is back.
			l.log.Warn("resolving audio for skip map", "item", string(it.PID), "err", err)
		}
		key := string(it.PID)
		if filePID != "" {
			key = key + "|" + filePID
		}
		if err := l.db.EnqueueAnalysis(ctx, f.EssenceHash, key, time.Now().UnixNano()); err != nil {
			return SkipMapResult{}, &Error{Kind: KindInternal, Err: err}
		}
		if !stale {
			// A true miss has no spans to serve yet.
			return SkipMapResult{State: skipStatePending, EssenceHash: f.EssenceHash, PartIndex: partOut}, nil
		}
		// Stale: fall through to serve the still-usable spans while re-analysis
		// runs, so a detector upgrade never drops skip data library-wide on
		// first access.
	}

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

// silenceMapStale reports whether a cached silence map was measured by a
// detector version the sidecar has since moved past. It is stale only
// when a jobs surface can re-measure it and the live detector version is
// both known and different: an unknown live version (a sidecar too old
// to advertise dsp.silenceDetector) or an absent jobs surface keeps the
// stored map in service, so a detector upgrade re-analyzes lazily on
// access rather than dropping usable maps it cannot yet rebuild.
func (l *Library) silenceMapStale(m wdb.SilenceMap) bool {
	if l.flowJobs == nil || !l.flowJobs.JobsSupported() {
		return false
	}
	live := l.flowJobs.SilenceDetectorVersion()
	return live != "" && m.DetectorVersion != live
}

// resolvePart maps a requested part onto the file that holds it, for
// the two per-file reads a multi-file book has (silence spans and
// peaks). Single-file items and non-books answer an empty file pid and
// no part, so they read through the item as they always did: two or
// more files is the whole condition, and both callers have to agree on
// it or one would echo a part the other refuses.
func (l *Library) resolvePart(ctx context.Context, it *model.ItemView, partIndex int) (string, *int, error) {
	if it.Kind != model.KindBook {
		return "", nil, nil
	}
	bd, err := l.lib.Book(ctx, it.PID)
	if err != nil {
		return "", nil, classify(err)
	}
	if len(bd.Files) < 2 {
		return "", nil, nil
	}
	if partIndex < 0 || partIndex >= len(bd.Files) {
		return "", nil, errInvalid("partIndex is out of range")
	}
	idx := partIndex
	return string(bd.Files[partIndex].FilePID), &idx, nil
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

// FlowJobs is the jobs surface the bridge provides; a nil bridge (no
// sidecar configured) disables skip maps and the file tooling. Paths
// are absolute; the bridge maps them onto engine root refs itself.
type FlowJobs interface {
	JobsSupported() bool
	SilenceDetectorVersion() string
	AnalyzeSilence(ctx context.Context, path string) (flow.SilenceAnalysis, error)
	CreateMergeJob(ctx context.Context, srcs []string, titles []string, format string) (string, error)
	CreateSplitJob(ctx context.Context, src string, cuts []int64, cue string, format string) (string, error)
	JobStatus(ctx context.Context, jobID string) (state string, progress float64, outputs int, errMsg string, err error)
	DownloadJobResult(ctx context.Context, jobID string, index int, dst string) error
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
		if errors.Is(err, errAnalysisMoot) {
			// Not a failure: no attempt can bring the bytes back, and a
			// re-fetch or a rescan of the same essence queues fresh work.
			if dbErr := l.db.CompleteAnalysis(ctx, row.Key); dbErr != nil {
				l.log.Warn("dropping analysis with no audio", "key", row.Key, "err", dbErr)
			}
			return true
		}
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

// analysisSource resolves the file a queued entry names, errAnalysisMoot
// when there is nothing left to measure.
func (l *Library) analysisSource(ctx context.Context, itemPID, filePID string) (string, error) {
	// A named part reads the catalog directly, so its answer is current.
	if filePID != "" {
		f, err := l.fileByPID(ctx, model.PID(filePID))
		if err != nil {
			if KindOf(err) == KindNotFound {
				return "", errAnalysisMoot
			}
			return "", err
		}
		return l.usableSource(string(f.Path))
	}
	loc, err := l.paths.Locate(ctx, model.PID(itemPID))
	if err != nil {
		if KindOf(classify(err)) == KindNotFound {
			return "", errAnalysisMoot
		}
		return "", classify(err)
	}
	path, err := l.usableSource(loc.Path)
	if !errors.Is(err, errAnalysisMoot) {
		return path, err
	}
	// Locate is cached and invalidates on a poll, so it can be a rename or
	// a fresh landing behind the catalog. Nothing is written off on it.
	fresh, err := l.paths.Relocate(ctx, model.PID(itemPID))
	if err != nil {
		if KindOf(classify(err)) == KindNotFound {
			return "", errAnalysisMoot
		}
		return "", classify(err)
	}
	if fresh.Path == loc.Path {
		return "", errAnalysisMoot
	}
	return l.usableSource(fresh.Path)
}

// usableSource answers a path worth analyzing: errAnalysisMoot when the
// catalog names bytes that are not there, a retryable error when the
// library root itself is missing, which is storage that has not arrived
// rather than audio that is gone.
func (l *Library) usableSource(path string) (string, error) {
	if path == "" {
		return "", errAnalysisMoot
	}
	if _, err := os.Stat(path); errors.Is(err, os.ErrNotExist) {
		if root := l.storageRootFor(path); root != "" {
			if _, err := os.Stat(root); errors.Is(err, os.ErrNotExist) {
				return "", fmt.Errorf("root %s is not mounted", root)
			}
		}
		return "", errAnalysisMoot
	}
	return path, nil
}

// storageRootFor answers the configured root a path sits under, longest
// match, or "" when none does. Read from the roots WaxDeck was given
// rather than the catalog's attribution, which only carries roots the
// catalog records a display path for.
func (l *Library) storageRootFor(path string) string {
	clean := filepath.Clean(path)
	best := ""
	for _, dir := range append([]string{l.podcastDir}, rootPaths(l.roots)...) {
		if dir == "" {
			continue
		}
		root := filepath.Clean(dir)
		if clean != root && !strings.HasPrefix(clean, root+string(filepath.Separator)) {
			continue
		}
		if len(root) > len(best) {
			best = root
		}
	}
	return best
}

func rootPaths(roots []Root) []string {
	out := make([]string, 0, len(roots))
	for _, r := range roots {
		out = append(out, r.Path)
	}
	return out
}

func (l *Library) runAnalysis(ctx context.Context, row wdb.QueueRow) error {
	itemPID, filePID, _ := strings.Cut(row.ItemPID, "|")
	path, err := l.analysisSource(ctx, itemPID, filePID)
	if err != nil {
		return err
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
