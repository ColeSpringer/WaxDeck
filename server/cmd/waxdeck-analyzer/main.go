// Command waxdeck-analyzer is the reference sonic-similarity worker.
// It polls a WaxDeck server for analysis work, pulls decode-ready
// audio (or decodes straight from a read-only library mount), computes
// the waxdeck-melstat-v1 embedding per track, and posts the vectors
// back. All state lives on the server: the worker can be stopped,
// restarted, or scaled out at any time, and leases it abandons simply
// expire and re-queue.
//
// The worker is strictly sequential by design: one item decodes and
// embeds at a time, so a single instance never competes with playback
// for the server's transcode slots, and running more instances is the
// sanctioned way to scale.
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/colespringer/waxflow/container"

	"github.com/colespringer/waxdeck/server/internal/analyzer"
)

// version is stamped by the release build (-ldflags "-X main.version=x.y.z").
var version = "0.1.0-dev"

const (
	// maxBatch mirrors the work endpoint's limit ceiling.
	maxBatch = 50
	// maxAudioBytes caps one audio pull; at the analysis rate this is
	// far beyond any real track and exists only to bound memory
	// against a misbehaving server.
	maxAudioBytes = int64(2) << 30
)

// errUnauthorized marks a 401 from any worker endpoint. A bad token
// never fixes itself, so the worker exits with a clear message rather
// than polling forever.
var errUnauthorized = errors.New("unauthorized")

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "waxdeck-analyzer:", err)
		os.Exit(1)
	}
}

func run() error {
	var (
		baseURL = flag.String("url", envOr("WAXDECK_ANALYZER_URL", "http://localhost:4420"), "WaxDeck server base URL")
		token   = flag.String("token", envOr("WAXDECK_ANALYZER_TOKEN", ""), "worker token (required; one of the server's WAXDECK_WORKER_TOKENS)")
		format  = flag.String("format", envOr("WAXDECK_ANALYZER_FORMAT", "wav"), "audio pull format: wav (no worker-side decode) or flac (about half the bytes; remote workers)")
		library = flag.String("library", envOr("WAXDECK_ANALYZER_LIBRARY", ""), "read-only library mount; when set, work items carrying a local path decode from disk instead of pulling over HTTP")
		pollSec = flag.Int("poll-seconds", envIntOr("WAXDECK_ANALYZER_POLL_SECONDS", 60), "idle sleep between polls when the server suggests none")
		batch   = flag.Int("batch", envIntOr("WAXDECK_ANALYZER_BATCH", 10), "work items leased and posted per cycle (1 to 50)")
		showVer = flag.Bool("version", false, "print version and exit")
	)
	flag.Parse()

	if *showVer {
		fmt.Println(version)
		return nil
	}
	if *token == "" {
		return errors.New("a worker token is required: set WAXDECK_ANALYZER_TOKEN or -token")
	}
	if *format != "wav" && *format != "flac" {
		return fmt.Errorf("WAXDECK_ANALYZER_FORMAT must be wav or flac, not %q", *format)
	}
	if *batch < 1 || *batch > maxBatch {
		return fmt.Errorf("WAXDECK_ANALYZER_BATCH must be between 1 and %d, not %d", maxBatch, *batch)
	}
	if *pollSec < 1 {
		return fmt.Errorf("WAXDECK_ANALYZER_POLL_SECONDS must be positive, not %d", *pollSec)
	}
	log := slog.New(slog.NewTextHandler(os.Stderr, nil))

	w, err := newWorker(workerConfig{
		BaseURL: *baseURL,
		Token:   *token,
		Format:  *format,
		Library: *library,
		Poll:    time.Duration(*pollSec) * time.Second,
		Batch:   *batch,
		Logger:  log,
	})
	if err != nil {
		return err
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	log.Info("waxdeck-analyzer starting",
		"version", version, "server", w.base.String(), "format", w.format,
		"batch", w.batch, "model", analyzer.Model, "dims", analyzer.Dims,
		"localLibrary", w.library != "")
	for ctx.Err() == nil {
		idle, err := w.runOnce(ctx)
		switch {
		case errors.Is(err, errUnauthorized):
			return errors.New("the server rejected the worker token (401): check WAXDECK_ANALYZER_TOKEN against the server's WAXDECK_WORKER_TOKENS")
		case err != nil && ctx.Err() != nil:
			// Shutdown races surface as canceled requests; exit quietly.
		case err != nil:
			log.Warn("work cycle failed; backing off", "err", err)
			idle = w.poll
		}
		if idle > 0 {
			sleepCtx(ctx, idle)
		}
	}
	log.Info("bye")
	return nil
}

// The wire types, spelled locally so the worker stays a standalone
// client of the public API rather than a consumer of server internals.
// Field names mirror the spec's SimilarityWorkPage, EmbeddingReport,
// and EmbeddingIngestResult schemas exactly.

type workItem struct {
	Pid        string `json:"pid"`
	Essence    string `json:"essence"`
	AudioURL   string `json:"audioUrl"`
	LocalPath  string `json:"localPath,omitempty"`
	DurationMs int64  `json:"durationMs"`
	MediaType  string `json:"mediaType"`
}

type workPage struct {
	Items             []workItem `json:"items"`
	RetryAfterSeconds int        `json:"retryAfterSeconds"`
}

type embeddingUpload struct {
	Pid     string    `json:"pid"`
	Essence string    `json:"essence"`
	Vector  []float32 `json:"vector"`
}

type embeddingReport struct {
	Model      string            `json:"model"`
	Dims       int               `json:"dims"`
	Embeddings []embeddingUpload `json:"embeddings"`
}

type rejectedEmbedding struct {
	Pid     string `json:"pid"`
	Essence string `json:"essence"`
	Code    string `json:"code"`
	Message string `json:"message"`
}

type ingestResult struct {
	Accepted int                 `json:"accepted"`
	Replaced int                 `json:"replaced"`
	Rejected []rejectedEmbedding `json:"rejected"`
}

type workerConfig struct {
	BaseURL string
	Token   string
	Format  string
	Library string
	Poll    time.Duration
	Batch   int
	Logger  *slog.Logger
}

type worker struct {
	client   *http.Client
	base     *url.URL
	token    string
	format   string
	library  string
	poll     time.Duration
	batch    int
	log      *slog.Logger
	analyzer *analyzer.Analyzer
}

func newWorker(cfg workerConfig) (*worker, error) {
	base, err := url.Parse(strings.TrimRight(cfg.BaseURL, "/"))
	if err != nil || base.Scheme == "" || base.Host == "" {
		return nil, fmt.Errorf("bad server URL %q: want http(s)://host[:port]", cfg.BaseURL)
	}
	return &worker{
		// No client-level timeout: audio pulls stream large bodies.
		// The API calls carry their own per-request deadlines, and
		// shutdown cancels everything through the request contexts.
		client:   &http.Client{},
		base:     base,
		token:    cfg.Token,
		format:   cfg.Format,
		library:  cfg.Library,
		poll:     cfg.Poll,
		batch:    cfg.Batch,
		log:      cfg.Logger,
		analyzer: analyzer.New(),
	}, nil
}

// runOnce is one poll-analyze-report cycle. It returns how long the
// caller should sleep before the next: zero after productive work
// (more may be waiting), the server's retryAfterSeconds when the
// queue is empty.
func (w *worker) runOnce(ctx context.Context) (time.Duration, error) {
	page, err := w.pullWork(ctx)
	if err != nil {
		return 0, err
	}
	if len(page.Items) == 0 {
		idle := time.Duration(page.RetryAfterSeconds) * time.Second
		if idle <= 0 {
			idle = w.poll
		}
		return idle, nil
	}
	batch := make([]embeddingUpload, 0, len(page.Items))
	for _, item := range page.Items {
		if ctx.Err() != nil {
			// Shutting down mid-batch: computed vectors are dropped,
			// the leases expire, the items re-queue. Cheap and correct.
			return 0, ctx.Err()
		}
		vec, err := w.analyze(ctx, item)
		if err != nil {
			// The worker API has no negative report, so an undecodable
			// or too-short item is logged and skipped: its lease
			// expires and it re-queues. That bounded churn is the
			// accepted cost of keeping the report surface vectors-only.
			w.log.Warn("skipping work item", "pid", item.Pid, "err", err)
			continue
		}
		batch = append(batch, embeddingUpload{Pid: item.Pid, Essence: item.Essence, Vector: vec})
	}
	if len(batch) == 0 {
		// A full page of skips: pace like an idle poll rather than
		// re-leasing failures in a tight loop.
		return w.poll, nil
	}
	if err := w.report(ctx, batch); err != nil {
		return 0, err
	}
	return 0, nil
}

// analyze turns one work item into its embedding vector.
func (w *worker) analyze(ctx context.Context, item workItem) ([]float32, error) {
	if item.DurationMs > 0 && item.DurationMs < analyzer.MinDurationMs {
		return nil, fmt.Errorf("%d ms is under the %d ms analysis minimum", item.DurationMs, analyzer.MinDurationMs)
	}
	samples, err := w.decode(ctx, item)
	if err != nil {
		return nil, err
	}
	return w.analyzer.EmbedSamples(samples)
}

// decode obtains the item's mono samples at the analysis rate,
// preferring the local library mount when both sides are configured
// for it.
func (w *worker) decode(ctx context.Context, item workItem) ([]float32, error) {
	if w.library != "" && item.LocalPath != "" {
		samples, err := w.decodeLocal(ctx, item.LocalPath)
		if err == nil {
			return samples, nil
		}
		// The HTTP pull serves the same audio, so a failed local
		// decode (a differently mounted root, an exotic codec)
		// degrades to the network path instead of skipping the item.
		w.log.Warn("local decode failed; pulling over HTTP", "path", item.LocalPath, "err", err)
	}
	return w.decodeRemote(ctx, item)
}

// decodeLocal decodes a library-relative source file from the mount.
func (w *worker) decodeLocal(ctx context.Context, localPath string) ([]float32, error) {
	rel := filepath.FromSlash(localPath)
	if filepath.IsAbs(rel) || rel != filepath.Clean(rel) || rel == ".." || strings.HasPrefix(rel, ".."+string(os.PathSeparator)) {
		return nil, fmt.Errorf("refusing library-relative path %q", localPath)
	}
	f, err := os.Open(filepath.Join(w.library, rel))
	if err != nil {
		return nil, err
	}
	defer f.Close()
	src, err := container.FileSource(f)
	if err != nil {
		return nil, err
	}
	hint := strings.TrimPrefix(strings.ToLower(filepath.Ext(rel)), ".")
	return w.transcodeToMono(ctx, src, hint)
}

// decodeRemote pulls decode-ready audio from the server's analysis
// endpoint.
func (w *worker) decodeRemote(ctx context.Context, item workItem) ([]float32, error) {
	data, err := w.fetchAudio(ctx, item.AudioURL)
	if err != nil {
		return nil, err
	}
	if w.format == "wav" {
		// The server already serves 16 kHz mono, so parsing the RIFF
		// container directly is the whole decode. Anything unexpected
		// (another rate, a compressed WAV flavor) falls through to
		// the generic path, which resamples.
		if samples, rate, err := analyzer.ParseWAV(data); err == nil && rate == analyzer.Rate {
			return samples, nil
		}
	}
	return w.transcodeToMono(ctx, container.BytesSource(data), w.format)
}

// transcodeToMono delegates to the shared analyzer package's decode
// path (WaxFlow sniff, resample to the analysis rate, downmix).
func (w *worker) transcodeToMono(ctx context.Context, src container.Source, hint string) ([]float32, error) {
	return w.analyzer.DecodeSource(ctx, src, hint)
}

// fetchAudio pulls one item's audio, resolving the origin-relative
// audioUrl against the server base and selecting the transport format.
func (w *worker) fetchAudio(ctx context.Context, audioURL string) ([]byte, error) {
	ref, err := url.Parse(audioURL)
	if err != nil {
		return nil, fmt.Errorf("bad audio url %q: %w", audioURL, err)
	}
	u := w.base.ResolveReference(ref)
	q := u.Query()
	q.Set("format", w.format)
	u.RawQuery = q.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+w.token)
	resp, err := w.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	switch resp.StatusCode {
	case http.StatusOK:
	case http.StatusUnauthorized:
		return nil, errUnauthorized
	default:
		return nil, fmt.Errorf("audio pull: %s", respError(resp))
	}
	data, err := io.ReadAll(io.LimitReader(resp.Body, maxAudioBytes+1))
	if err != nil {
		return nil, err
	}
	if int64(len(data)) > maxAudioBytes {
		return nil, fmt.Errorf("audio exceeds the %d byte cap", maxAudioBytes)
	}
	return data, nil
}

// pullWork leases a batch of analysis work.
func (w *worker) pullWork(ctx context.Context) (*workPage, error) {
	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	u := w.base.String() + "/api/v1/similarity/work?limit=" + strconv.Itoa(w.batch)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+w.token)
	resp, err := w.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	switch resp.StatusCode {
	case http.StatusOK:
	case http.StatusUnauthorized:
		return nil, errUnauthorized
	default:
		return nil, fmt.Errorf("pulling work: %s", respError(resp))
	}
	var page workPage
	if err := json.NewDecoder(resp.Body).Decode(&page); err != nil {
		return nil, fmt.Errorf("decoding work page: %w", err)
	}
	return &page, nil
}

// report posts one batch of embeddings.
func (w *worker) report(ctx context.Context, batch []embeddingUpload) error {
	ctx, cancel := context.WithTimeout(ctx, 60*time.Second)
	defer cancel()
	payload, err := json.Marshal(embeddingReport{Model: analyzer.Model, Dims: analyzer.Dims, Embeddings: batch})
	if err != nil {
		return err
	}
	u := w.base.String() + "/api/v1/similarity/embeddings"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, u, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+w.token)
	req.Header.Set("Content-Type", "application/json")
	resp, err := w.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	switch resp.StatusCode {
	case http.StatusOK:
	case http.StatusUnauthorized:
		return errUnauthorized
	default:
		return fmt.Errorf("posting embeddings: %s", respError(resp))
	}
	var res ingestResult
	if err := json.NewDecoder(resp.Body).Decode(&res); err != nil {
		return fmt.Errorf("decoding ingest result: %w", err)
	}
	w.log.Info("posted embeddings",
		"count", len(batch), "accepted", res.Accepted, "replaced", res.Replaced, "rejected", len(res.Rejected))
	for _, r := range res.Rejected {
		w.log.Warn("embedding rejected", "pid", r.Pid, "code", r.Code, "msg", r.Message)
	}
	return nil
}

// respError summarizes a non-OK response for logs, body snippet included.
func respError(resp *http.Response) string {
	snippet, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
	s := strings.TrimSpace(string(snippet))
	if s == "" {
		return resp.Status
	}
	return resp.Status + ": " + s
}

// sleepCtx sleeps for d or until ctx cancels, whichever comes first.
func sleepCtx(ctx context.Context, d time.Duration) {
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-ctx.Done():
	case <-t.C:
	}
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func envIntOr(key string, def int) int {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return def
}
