package flow

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"

	"github.com/colespringer/waxflow/client"
	"github.com/colespringer/waxflow/waxerr"
)

// The sidecar's async jobs surface, spoken through the published
// client's typed jobs methods. WaxDeck runs the silence and loudness
// analysis behind skip maps and voice-boost leveling here, plus the
// file-tooling jobs (audiobook merge, chapter split, CUE rip split).

// PermanentJobErr reports whether a jobs-surface failure is one the same
// input will always reproduce (the engine refused the request) rather
// than transport trouble or an overloaded daemon worth a retry. It keeps
// the retry decision keyed on the engine's own error taxonomy now that
// the surface is spoken through the typed client, which decodes the
// response envelope into a waxerr code. An unclassified error (transport
// trouble, a context cancel) reads as internal and is not permanent.
func PermanentJobErr(err error) bool {
	switch waxerr.CodeOf(err) {
	case waxerr.CodeInvalidRequest, waxerr.CodePayloadTooLarge,
		waxerr.CodeNotFound, waxerr.CodeUnsupportedFormat,
		waxerr.CodeUnsupportedSource, waxerr.CodeUnauthorized,
		waxerr.CodeSignatureInvalid, waxerr.CodeSignatureExpired,
		waxerr.CodeSourceChanged:
		return true
	}
	return false
}

// JobsSupported reports whether the sidecar runs the jobs surface.
func (b *Bridge) JobsSupported() bool { return b.caps.Delivery.Jobs }

// SilenceDetectorVersion is the sidecar's silence-detector revision, the
// same value a cached silence map stamps in its version field. An empty
// string means a sidecar too old to advertise it: callers treat that as
// "unknown" and never as every cached map being stale.
func (b *Bridge) SilenceDetectorVersion() string { return b.caps.DSP.SilenceDetector }

// SilenceAnalysis is the finished analysis for one file: the loudness
// numbers from the job document and the span map from its result file.
type SilenceAnalysis struct {
	// Version is the upstream detector revision.
	Version     string
	ThresholdDB float64
	MinSeconds  float64
	// Rate converts span samples to time.
	Rate int
	// DurationSeconds is the analyzed audio's length.
	DurationSeconds float64
	Spans           []SilenceSpan
	// IntegratedLUFS and TruePeakDB are null for digital silence.
	IntegratedLUFS *float64
	TruePeakDB     *float64
}

// SilenceSpan is one half-open silence span.
type SilenceSpan struct {
	FromSample int64
	ToSample   int64
}

// silenceDoc mirrors the silence.json result file an analyze job writes.
// The typed client's SilenceSummary carries the headline inline on the
// job but not the spans, so the full map is decoded from the result body.
type silenceDoc struct {
	Version         string  `json:"version"`
	ThresholdDb     float64 `json:"thresholdDb"`
	MinSeconds      float64 `json:"minSeconds"`
	Rate            int     `json:"rate"`
	DurationSeconds float64 `json:"durationSeconds"`
	Spans           []struct {
		FromSample int64 `json:"fromSample"`
		ToSample   int64 `json:"toSample"`
	} `json:"spans"`
}

// AnalyzeSilence runs one silence and loudness analysis to completion:
// creates the job, polls it, and fetches the span map. The caller
// bounds the wait through ctx; polling backs off to two seconds.
func (b *Bridge) AnalyzeSilence(ctx context.Context, path string) (SilenceAnalysis, error) {
	if !b.JobsSupported() {
		return SilenceAnalysis{}, fmt.Errorf("flow: sidecar runs no jobs surface")
	}
	ref, err := b.srcRef(path)
	if err != nil {
		return SilenceAnalysis{}, err
	}
	job, err := b.client.CreateJob(ctx, client.JobRequest{Type: "analyze", Src: ref, Silence: true})
	if err != nil {
		return SilenceAnalysis{}, fmt.Errorf("flow: creating analyze job: %w", err)
	}

	for job.State == "queued" || job.State == "running" {
		select {
		case <-ctx.Done():
			return SilenceAnalysis{}, ctx.Err()
		case <-time.After(2 * time.Second):
		}
		job, err = b.client.Job(ctx, job.ID)
		if err != nil {
			return SilenceAnalysis{}, fmt.Errorf("flow: polling analyze job: %w", err)
		}
	}
	if job.State != "done" {
		msg := job.State
		if job.Error != nil {
			msg = job.Error.Code + ": " + job.Error.Message
		}
		return SilenceAnalysis{}, fmt.Errorf("flow: analyze job %s failed: %s", job.ID, msg)
	}

	// The bare result form (-1) answers an analyze job's one output, the
	// silence map document, whose spans SilenceSummary does not carry.
	resp, err := b.client.JobResult(ctx, job.ID, -1)
	if err != nil {
		return SilenceAnalysis{}, fmt.Errorf("flow: fetching silence map: %w", err)
	}
	defer resp.Body.Close()
	var sil silenceDoc
	if err := json.NewDecoder(resp.Body).Decode(&sil); err != nil {
		return SilenceAnalysis{}, fmt.Errorf("flow: decoding silence map: %w", err)
	}
	out := SilenceAnalysis{
		Version:         sil.Version,
		ThresholdDB:     sil.ThresholdDb,
		MinSeconds:      sil.MinSeconds,
		Rate:            sil.Rate,
		DurationSeconds: sil.DurationSeconds,
	}
	for _, s := range sil.Spans {
		out.Spans = append(out.Spans, SilenceSpan{FromSample: s.FromSample, ToSample: s.ToSample})
	}
	if job.Analysis != nil {
		out.IntegratedLUFS = job.Analysis.IntegratedLUFS
		out.TruePeakDB = job.Analysis.TruePeakDB
		if out.Rate == 0 {
			out.Rate = job.Analysis.Rate
		}
	}
	return out, nil
}

// CreateMergeJob posts a merge job over absolute library paths, mapped
// to engine refs here so the service layer never learns root names.
// titles are optional per-member chapter titles, index-aligned to srcs.
//
// Book merges pass format "aac" on purpose: an explicit output codec
// lets any mix of part codecs merge, at the cost of a transcode even
// when every part is already AAC, and aac with no container resolves
// server-side to the flat progressive MP4 form, the only shape that
// carries the QuickTime chapter track the merge exists to write.
func (b *Bridge) CreateMergeJob(ctx context.Context, srcs []string, titles []string, format string) (string, error) {
	if !b.JobsSupported() {
		return "", fmt.Errorf("flow: sidecar runs no jobs surface")
	}
	refs := make([]string, len(srcs))
	for i, p := range srcs {
		ref, err := b.srcRef(p)
		if err != nil {
			return "", err
		}
		refs[i] = ref
	}
	req := client.JobRequest{Type: "merge", Srcs: refs}
	if len(titles) > 0 {
		req.Titles = titles
	}
	if format != "" {
		req.Format = format
	}
	job, err := b.client.CreateJob(ctx, req)
	if err != nil {
		return "", fmt.Errorf("flow: creating merge job: %w", err)
	}
	return job.ID, nil
}

// CreateSplitJob posts a split job for one absolute library path. Cut
// points are source sample offsets (strictly ascending, interior); cue
// names a CUE sheet by absolute path instead, exclusive with cuts, and
// the sidecar resolves the sheet into cut points at creation. The
// sidecar requires an explicit output format for every audio-writing
// job, so callers pass the source codec's format to keep a lossless
// split lossless. The mp4-family formats additionally pin the flat
// progressive container, which is belt: the sidecar now flattens every
// file output that does not ask for a container. Kept because a
// fragmented .m4b piece is a file most players refuse to open, and this
// says so at the call site rather than relying on a sidecar default.
func (b *Bridge) CreateSplitJob(ctx context.Context, src string, cuts []int64, cue string, format string) (string, error) {
	if !b.JobsSupported() {
		return "", fmt.Errorf("flow: sidecar runs no jobs surface")
	}
	ref, err := b.srcRef(src)
	if err != nil {
		return "", err
	}
	req := client.JobRequest{Type: "split", Src: ref, Format: format}
	if format == "aac" || format == "alac" {
		req.Container = "progressive"
	}
	switch {
	case cue != "":
		cueRef, err := b.srcRef(cue)
		if err != nil {
			return "", err
		}
		req.Cue = cueRef
	default:
		req.Cuts = cuts
	}
	job, err := b.client.CreateJob(ctx, req)
	if err != nil {
		return "", fmt.Errorf("flow: creating split job: %w", err)
	}
	return job.ID, nil
}

// JobStatus reads one job's state, progress percent, output count, and
// terminal error message (empty unless failed or canceled).
func (b *Bridge) JobStatus(ctx context.Context, jobID string) (state string, progress float64, outputs int, errMsg string, err error) {
	job, err := b.client.Job(ctx, jobID)
	if err != nil {
		return "", 0, 0, "", fmt.Errorf("flow: reading job %s: %w", jobID, err)
	}
	if job.Progress != nil {
		progress = job.Progress.Percent
	}
	if job.Error != nil {
		errMsg = job.Error.Code + ": " + job.Error.Message
	}
	return job.State, progress, len(job.Outputs), errMsg, nil
}

// DownloadJobResult streams one job output to dst with the repo's
// crash-safe write discipline: temp name in the target directory, size
// check against Content-Length when the sidecar declares one, fsync,
// atomic rename, directory fsync. The typed client verifies the status
// and attaches the API key; this owns the durable placement.
func (b *Bridge) DownloadJobResult(ctx context.Context, jobID string, index int, dst string) error {
	resp, err := b.client.JobResult(ctx, jobID, index)
	if err != nil {
		return fmt.Errorf("flow: fetching job %s result %d: %w", jobID, index, err)
	}
	defer resp.Body.Close()

	tmp, err := os.CreateTemp(filepath.Dir(dst), ".waxdeck-result-*")
	if err != nil {
		return fmt.Errorf("flow: staging job result: %w", err)
	}
	tmpName := tmp.Name()
	cleanup := func() {
		tmp.Close()
		os.Remove(tmpName)
	}
	n, err := io.Copy(tmp, resp.Body)
	if err != nil {
		cleanup()
		return fmt.Errorf("flow: downloading job %s result %d: %w", jobID, index, err)
	}
	if resp.ContentLength >= 0 && n != resp.ContentLength {
		cleanup()
		return fmt.Errorf("flow: job %s result %d: got %d of %d bytes", jobID, index, n, resp.ContentLength)
	}
	if err := tmp.Sync(); err != nil {
		cleanup()
		return fmt.Errorf("flow: syncing job result: %w", err)
	}
	if err := tmp.Close(); err != nil {
		os.Remove(tmpName)
		return fmt.Errorf("flow: closing job result: %w", err)
	}
	if err := os.Rename(tmpName, dst); err != nil {
		os.Remove(tmpName)
		return fmt.Errorf("flow: placing job result: %w", err)
	}
	if dir, err := os.Open(filepath.Dir(dst)); err == nil {
		_ = dir.Sync()
		dir.Close()
	}
	return nil
}
