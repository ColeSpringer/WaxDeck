package main

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"math"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"

	"github.com/colespringer/waxdeck/server/internal/analyzer"
)

func testWorker(t *testing.T, baseURL, token string) *worker {
	t.Helper()
	w, err := newWorker(workerConfig{
		BaseURL: baseURL,
		Token:   token,
		Format:  "wav",
		Poll:    time.Minute,
		Batch:   10,
		Logger:  slog.New(slog.NewTextHandler(io.Discard, nil)),
	})
	if err != nil {
		t.Fatalf("newWorker: %v", err)
	}
	return w
}

// TestWorkerHappyPath drives one full cycle against a fake server:
// pull one work item, fetch its WAV, post the embedding, then observe
// the idle backoff once the queue drains.
func TestWorkerHappyPath(t *testing.T) {
	const (
		token   = "test-worker-token"
		pid     = "tr-01JZX5N8QW3F4V9T2B7KD3M9R6"
		essence = "essence-abc123"
	)
	audio := wavPCM16(toneInt16(440, 3, analyzer.Rate), analyzer.Rate, 1)

	var pulls, posted atomic.Int32
	var reportBody []byte
	mux := http.NewServeMux()
	authed := func(next http.HandlerFunc) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			if r.Header.Get("Authorization") != "Bearer "+token {
				w.WriteHeader(http.StatusUnauthorized)
				return
			}
			next(w, r)
		}
	}
	mux.HandleFunc("GET /api/v1/similarity/work", authed(func(w http.ResponseWriter, r *http.Request) {
		if got := r.URL.Query().Get("limit"); got != "10" {
			t.Errorf("work pull limit = %q, want 10", got)
		}
		page := workPage{Items: []workItem{}, RetryAfterSeconds: 7}
		if pulls.Add(1) == 1 {
			page.Items = []workItem{{
				Pid:        pid,
				Essence:    essence,
				AudioURL:   "/media/analysis/" + pid,
				DurationMs: 3000,
				MediaType:  "music",
			}}
		}
		json.NewEncoder(w).Encode(page)
	}))
	mux.HandleFunc("GET /media/analysis/"+pid, authed(func(w http.ResponseWriter, r *http.Request) {
		if got := r.URL.Query().Get("format"); got != "wav" {
			t.Errorf("audio pull format = %q, want wav", got)
		}
		w.Write(audio)
	}))
	mux.HandleFunc("POST /api/v1/similarity/embeddings", authed(func(w http.ResponseWriter, r *http.Request) {
		posted.Add(1)
		reportBody, _ = io.ReadAll(r.Body)
		json.NewEncoder(w).Encode(ingestResult{Accepted: 1})
	}))
	srv := httptest.NewServer(mux)
	defer srv.Close()

	w := testWorker(t, srv.URL, token)

	idle, err := w.runOnce(t.Context())
	if err != nil {
		t.Fatalf("first cycle: %v", err)
	}
	if idle != 0 {
		t.Fatalf("productive cycle asked to sleep %v, want 0", idle)
	}
	if posted.Load() != 1 {
		t.Fatalf("posted %d reports, want 1", posted.Load())
	}

	// The posted JSON shape, asserted on raw keys so a struct-tag
	// regression cannot hide behind symmetric encode/decode.
	var report map[string]any
	if err := json.Unmarshal(reportBody, &report); err != nil {
		t.Fatalf("report is not JSON: %v", err)
	}
	if got, _ := report["model"].(string); got != analyzer.Model {
		t.Fatalf("model = %q, want %q", got, analyzer.Model)
	}
	if got, _ := report["dims"].(float64); int(got) != analyzer.Dims {
		t.Fatalf("dims = %v, want %d", report["dims"], analyzer.Dims)
	}
	embeds, _ := report["embeddings"].([]any)
	if len(embeds) != 1 {
		t.Fatalf("embeddings carries %d entries, want 1", len(embeds))
	}
	entry, _ := embeds[0].(map[string]any)
	if got, _ := entry["pid"].(string); got != pid {
		t.Fatalf("embedding pid = %q, want %q", got, pid)
	}
	if got, _ := entry["essence"].(string); got != essence {
		t.Fatalf("embedding essence = %q, want %q", got, essence)
	}
	vector, _ := entry["vector"].([]any)
	if len(vector) != analyzer.Dims {
		t.Fatalf("vector carries %d values, want %d", len(vector), analyzer.Dims)
	}
	var norm float64
	for _, v := range vector {
		f, ok := v.(float64)
		if !ok {
			t.Fatalf("vector value %v is not a number", v)
		}
		norm += f * f
	}
	if norm = math.Sqrt(norm); math.Abs(norm-1) > 1e-3 {
		t.Fatalf("posted vector norm = %v, want about 1", norm)
	}

	// Queue drained: the second cycle reports the server's suggested
	// idle sleep and posts nothing new.
	idle, err = w.runOnce(t.Context())
	if err != nil {
		t.Fatalf("second cycle: %v", err)
	}
	if idle != 7*time.Second {
		t.Fatalf("idle cycle asked to sleep %v, want 7s (the server's retryAfterSeconds)", idle)
	}
	if posted.Load() != 1 {
		t.Fatalf("idle cycle posted a report; total %d, want 1", posted.Load())
	}
}

// TestWorkerDecodesLocalFiles covers the library-mount path: a FLAC
// at a library rate (not the analysis rate) decodes, resamples, and
// downmixes through the generic WaxFlow route without touching HTTP.
func TestWorkerDecodesLocalFiles(t *testing.T) {
	lib := t.TempDir()
	paths, err := fixtures.Generate(lib, fixtures.Spec{
		Name:     "tone",
		Codec:    fixtures.CodecFLAC,
		Duration: 3 * time.Second,
	})
	if err != nil {
		t.Fatalf("generating fixture: %v", err)
	}

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Errorf("unexpected HTTP call %s %s: local decode should not fall back", r.Method, r.URL)
		w.WriteHeader(http.StatusNotFound)
	}))
	defer srv.Close()

	w := testWorker(t, srv.URL, "unused")
	w.library = lib
	vec, err := w.analyze(t.Context(), workItem{
		Pid:        "tr-01JZX5N8QW3F4V9T2B7KD3M9R6",
		Essence:    "essence-local",
		LocalPath:  filepath.Base(paths[0]),
		DurationMs: 3000,
		MediaType:  "music",
	})
	if err != nil {
		t.Fatalf("analyze: %v", err)
	}
	if len(vec) != analyzer.Dims {
		t.Fatalf("vector has %d dims, want %d", len(vec), analyzer.Dims)
	}
}

func TestWorkerTreatsRejectedTokenAsFatal(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
	}))
	defer srv.Close()

	w := testWorker(t, srv.URL, "wrong-token")
	if _, err := w.runOnce(t.Context()); !errors.Is(err, errUnauthorized) {
		t.Fatalf("err = %v, want errUnauthorized", err)
	}
}

// wavPCM16 and toneInt16 mirror the analyzer package's test helpers;
// _test files do not export across packages.
func wavPCM16(interleaved []int16, rate, channels int) []byte {
	dataLen := len(interleaved) * 2
	buf := &bytes.Buffer{}
	buf.WriteString("RIFF")
	binary.Write(buf, binary.LittleEndian, uint32(36+dataLen))
	buf.WriteString("WAVE")
	buf.WriteString("fmt ")
	binary.Write(buf, binary.LittleEndian, uint32(16))
	binary.Write(buf, binary.LittleEndian, uint16(1))
	binary.Write(buf, binary.LittleEndian, uint16(channels))
	binary.Write(buf, binary.LittleEndian, uint32(rate))
	binary.Write(buf, binary.LittleEndian, uint32(rate*channels*2))
	binary.Write(buf, binary.LittleEndian, uint16(channels*2))
	binary.Write(buf, binary.LittleEndian, uint16(16))
	buf.WriteString("data")
	binary.Write(buf, binary.LittleEndian, uint32(dataLen))
	binary.Write(buf, binary.LittleEndian, interleaved)
	return buf.Bytes()
}

func toneInt16(freq float64, seconds float64, rate int) []int16 {
	n := int(seconds * float64(rate))
	out := make([]int16, n)
	step := 2 * math.Pi * freq / float64(rate)
	for i := range out {
		out[i] = int16(math.Round(0.5 * 32767 * math.Sin(step*float64(i))))
	}
	return out
}
