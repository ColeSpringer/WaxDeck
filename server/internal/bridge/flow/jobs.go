package flow

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"time"
)

// The sidecar's async jobs surface, spoken directly over HTTP: the
// upstream client package deliberately ships no jobs client. WaxDeck
// runs the silence and loudness analysis behind skip maps and
// voice-boost leveling here, plus the file-tooling jobs (audiobook
// merge, chapter split, CUE rip split).

// StatusError is a non-2xx answer from the sidecar's jobs surface. It
// lets callers separate a request the sidecar refused (4xx: retrying
// the same input fails the same way) from transport trouble.
type StatusError struct {
	Code int
	Body string
}

func (e *StatusError) Error() string {
	return fmt.Sprintf("status %d: %s", e.Code, e.Body)
}

// JobsSupported reports whether the sidecar runs the jobs surface.
func (b *Bridge) JobsSupported() bool { return b.caps.Delivery.Jobs }

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

// jobDoc mirrors the fields of the sidecar's job document this bridge
// reads (the document carries more).
type jobDoc struct {
	ID       string `json:"id"`
	State    string `json:"state"`
	Progress *struct {
		Percent float64 `json:"percent"`
	} `json:"progress"`
	Outputs []struct {
		File string `json:"file"`
	} `json:"outputs"`
	Analysis *struct {
		IntegratedLufs *float64 `json:"integratedLufs"`
		TruePeakDb     *float64 `json:"truePeakDb"`
		Rate           int      `json:"rate"`
	} `json:"analysis"`
	Error *struct {
		Code    string `json:"code"`
		Message string `json:"message"`
	} `json:"error"`
}

// silenceDoc mirrors the silence.json result file.
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
	body, _ := json.Marshal(map[string]any{
		"type":    "analyze",
		"src":     ref,
		"silence": true,
	})
	var created jobDoc
	if err := b.jobsCall(ctx, http.MethodPost, "/jobs", bytes.NewReader(body), &created); err != nil {
		return SilenceAnalysis{}, err
	}

	doc := created
	for doc.State == "queued" || doc.State == "running" {
		select {
		case <-ctx.Done():
			return SilenceAnalysis{}, ctx.Err()
		case <-time.After(2 * time.Second):
		}
		if err := b.jobsCall(ctx, http.MethodGet, "/jobs/"+doc.ID, nil, &doc); err != nil {
			return SilenceAnalysis{}, err
		}
	}
	if doc.State != "done" {
		msg := doc.State
		if doc.Error != nil {
			msg = doc.Error.Code + ": " + doc.Error.Message
		}
		return SilenceAnalysis{}, fmt.Errorf("flow: analyze job %s failed: %s", doc.ID, msg)
	}

	var sil silenceDoc
	if err := b.jobsCall(ctx, http.MethodGet, "/jobs/"+doc.ID+"/result", nil, &sil); err != nil {
		return SilenceAnalysis{}, fmt.Errorf("flow: fetching silence map: %w", err)
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
	if doc.Analysis != nil {
		out.IntegratedLUFS = doc.Analysis.IntegratedLufs
		out.TruePeakDB = doc.Analysis.TruePeakDb
		if out.Rate == 0 {
			out.Rate = doc.Analysis.Rate
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
	payload := map[string]any{"type": "merge", "srcs": refs}
	if len(titles) > 0 {
		payload["titles"] = titles
	}
	if format != "" {
		payload["format"] = format
	}
	body, _ := json.Marshal(payload)
	var created jobDoc
	if err := b.jobsCall(ctx, http.MethodPost, "/jobs", bytes.NewReader(body), &created); err != nil {
		return "", err
	}
	return created.ID, nil
}

// CreateSplitJob posts a split job for one absolute library path. Cut
// points are source sample offsets (strictly ascending, interior); cue
// names a CUE sheet by absolute path instead, exclusive with cuts, and
// the sidecar resolves the sheet into cut points at creation. The
// sidecar requires an explicit output format for every audio-writing
// job, so callers pass the source codec's format to keep a lossless
// split lossless. The mp4-family formats additionally pin the flat
// progressive container: only merges default to it server-side, and a
// fragmented .m4b piece is a file most players refuse to open.
func (b *Bridge) CreateSplitJob(ctx context.Context, src string, cuts []int64, cue string, format string) (string, error) {
	if !b.JobsSupported() {
		return "", fmt.Errorf("flow: sidecar runs no jobs surface")
	}
	ref, err := b.srcRef(src)
	if err != nil {
		return "", err
	}
	payload := map[string]any{"type": "split", "src": ref, "format": format}
	if format == "aac" || format == "alac" {
		payload["container"] = "progressive"
	}
	switch {
	case cue != "":
		cueRef, err := b.srcRef(cue)
		if err != nil {
			return "", err
		}
		payload["cue"] = cueRef
	default:
		payload["cuts"] = cuts
	}
	body, _ := json.Marshal(payload)
	var created jobDoc
	if err := b.jobsCall(ctx, http.MethodPost, "/jobs", bytes.NewReader(body), &created); err != nil {
		return "", err
	}
	return created.ID, nil
}

// JobStatus reads one job's state, progress percent, output count, and
// terminal error message (empty unless failed or canceled).
func (b *Bridge) JobStatus(ctx context.Context, jobID string) (state string, progress float64, outputs int, errMsg string, err error) {
	var doc jobDoc
	if err := b.jobsCall(ctx, http.MethodGet, "/jobs/"+jobID, nil, &doc); err != nil {
		return "", 0, 0, "", err
	}
	if doc.Progress != nil {
		progress = doc.Progress.Percent
	}
	if doc.Error != nil {
		errMsg = doc.Error.Code + ": " + doc.Error.Message
	}
	return doc.State, progress, len(doc.Outputs), errMsg, nil
}

// DownloadJobResult streams one job output to dst with the repo's
// crash-safe write discipline: temp name in the target directory, size
// check against Content-Length when the sidecar declares one, fsync,
// atomic rename, directory fsync.
func (b *Bridge) DownloadJobResult(ctx context.Context, jobID string, index int, dst string) error {
	u := b.base.JoinPath("/jobs", jobID, "result", strconv.Itoa(index))
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), nil)
	if err != nil {
		return fmt.Errorf("flow: %w", err)
	}
	req.Header.Set("X-API-Key", b.apiKey)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fmt.Errorf("flow: fetching job %s result %d: %w", jobID, index, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		detail, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		return fmt.Errorf("flow: fetching job %s result %d: %w", jobID, index,
			&StatusError{Code: resp.StatusCode, Body: string(detail)})
	}

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

// jobsCall is one authenticated JSON round trip to the sidecar.
func (b *Bridge) jobsCall(ctx context.Context, method, path string, body io.Reader, out any) error {
	req, err := http.NewRequestWithContext(ctx, method, b.base.JoinPath(path).String(), body)
	if err != nil {
		return fmt.Errorf("flow: %w", err)
	}
	req.Header.Set("X-API-Key", b.apiKey)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fmt.Errorf("flow: %s %s: %w", method, path, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		detail, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		return fmt.Errorf("flow: %s %s: %w", method, path,
			&StatusError{Code: resp.StatusCode, Body: string(detail)})
	}
	if out == nil {
		return nil
	}
	if err := json.NewDecoder(resp.Body).Decode(out); err != nil {
		return fmt.Errorf("flow: decoding %s response: %w", path, err)
	}
	return nil
}
