package flow

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// The sidecar's async jobs surface, spoken directly over HTTP: the
// upstream client package deliberately ships no jobs client, and the
// only job WaxDeck runs today is the silence and loudness analysis
// behind skip maps and voice-boost leveling.

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
		return fmt.Errorf("flow: %s %s: status %d: %s", method, path, resp.StatusCode, string(detail))
	}
	if out == nil {
		return nil
	}
	if err := json.NewDecoder(resp.Body).Decode(out); err != nil {
		return fmt.Errorf("flow: decoding %s response: %w", path, err)
	}
	return nil
}
