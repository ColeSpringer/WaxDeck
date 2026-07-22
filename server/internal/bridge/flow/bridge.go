// Package flow is the WaxFlow bridge: play-info resolution, media
// tokens on the way out, and the reverse proxy that carries stream
// bytes through WaxDeck's single origin. WaxFlow never faces clients;
// per-user policy is enforced at mint and again at every fetch.
package flow

import (
	"context"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httputil"
	"net/url"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/colespringer/waxflow/client"

	"github.com/colespringer/waxdeck/server/internal/auth"
)

// capsStartupWait bounds how long New waits for the sidecar's /caps
// before giving up.
const capsStartupWait = 30 * time.Second

// Root maps one library directory to the WaxFlow root name the same
// directory is mounted under in the sidecar.
type Root struct {
	Name string
	Path string
}

// SourceResolver is what the service layer provides: API item PID to
// stream source, re-resolved on every call. filePID selects one part
// of a multi-file item; empty means the item's own (or first) file.
type SourceResolver interface {
	StreamSource(ctx context.Context, apiItemPID, filePID string) (Source, error)
}

// Config configures the bridge.
type Config struct {
	// BaseURL is the sidecar's internal address (http://waxflow:4418).
	BaseURL string
	// APIKey authenticates WaxDeck to the sidecar.
	APIKey string
	// Roots is the library-path to root-name map.
	Roots []Root
	// Tokens mints and verifies media tokens.
	Tokens *auth.MediaTokens
	// Resolver resolves item PIDs to stream sources.
	Resolver SourceResolver
	Logger   *slog.Logger
}

// Bridge is the live bridge, holding the sidecar's capabilities as
// fetched at startup.
type Bridge struct {
	base     *url.URL
	apiKey   string
	roots    []Root
	tokens   *auth.MediaTokens
	resolver SourceResolver
	caps     *client.Caps
	client   *client.Client
	proxy    *httputil.ReverseProxy
	log      *slog.Logger
	// gate admits engine-backed stream sessions; nil admits everything.
	gate TranscodeGate

	// Timeline bookkeeping, built lazily on first use.
	tlOnce sync.Once
	tl     *timelineState
}

// New validates the configuration against the live sidecar (fail fast:
// a bridge that cannot see /caps serves nothing but confusion) and
// returns the bridge.
func New(ctx context.Context, cfg Config) (*Bridge, error) {
	base, err := url.Parse(cfg.BaseURL)
	if err != nil || base.Scheme == "" || base.Host == "" {
		return nil, fmt.Errorf("flow: bad base URL %q", cfg.BaseURL)
	}
	log := cfg.Logger
	if log == nil {
		log = slog.New(slog.DiscardHandler)
	}
	c, err := client.New(cfg.BaseURL, cfg.APIKey)
	if err != nil {
		return nil, fmt.Errorf("flow: %w", err)
	}
	// The sidecar and this server start together under compose and test
	// harnesses; give it a bounded window to come up, then fail fast.
	var caps *client.Caps
	deadline := time.Now().Add(capsStartupWait)
	for {
		caps, err = c.Caps(ctx)
		if err == nil {
			break
		}
		if ctx.Err() != nil || time.Now().After(deadline) {
			return nil, fmt.Errorf("flow: fetching /caps from %s (is the waxflow sidecar up?): %w", cfg.BaseURL, err)
		}
		log.Info("waiting for waxflow sidecar", "base", cfg.BaseURL)
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(time.Second):
		}
	}
	if !caps.Delivery.Progressive {
		return nil, fmt.Errorf("flow: sidecar at %s does not serve progressive streams", cfg.BaseURL)
	}
	// Longest path first so nested roots resolve to the most specific name.
	roots := append([]Root(nil), cfg.Roots...)
	sort.Slice(roots, func(i, j int) bool { return len(roots[i].Path) > len(roots[j].Path) })

	b := &Bridge{
		base:     base,
		apiKey:   cfg.APIKey,
		roots:    roots,
		tokens:   cfg.Tokens,
		resolver: cfg.Resolver,
		caps:     caps,
		client:   c,
		log:      log,
	}
	b.proxy = &httputil.ReverseProxy{
		Rewrite:        b.rewrite,
		ModifyResponse: b.modifyResponse,
		ErrorHandler: func(w http.ResponseWriter, r *http.Request, err error) {
			log.Error("stream proxy", "err", err)
			writeJSONError(w, http.StatusBadGateway, "internal", "stream backend unavailable")
		},
		// Audio is latency-sensitive: flush as bytes arrive, never buffer.
		FlushInterval: -1,
	}
	log.Info("waxflow bridge up",
		"base", cfg.BaseURL,
		"outputs", len(caps.Outputs),
		"cutFormats", caps.Delivery.CutFormats,
		"hls", caps.Delivery.HLS)
	return b, nil
}

// Caps exposes the sidecar capabilities fetched at startup.
func (b *Bridge) Caps() *client.Caps { return b.caps }

// PlayInfo is everything play-info hands a client for one item.
type PlayInfo struct {
	URL        string
	MimeType   string
	DurationMS int64
	Seekable   bool
	ExpiresAt  time.Time
	// VoiceBoost reports whether the minted stream applies server-side
	// spoken-word loudness normalization.
	VoiceBoost bool
}

// PlayOptions select a part of a multi-file item and request DSP.
type PlayOptions struct {
	// FilePID selects the backing file (multi-file books); empty means
	// the item's own file.
	FilePID string
	// VoiceBoost asks for server-side spoken-word normalization; the
	// mint reports whether it actually engages.
	VoiceBoost bool
	// ForceFormat pins the served format for endpoints with narrow
	// codec support (mp3 for renderers, wav for the jukebox output).
	// Only formats in forceFormats are honored; anything else falls
	// back to the derived shape.
	ForceFormat string
	// TTL sizes the media token for long deliveries (whole-queue
	// casts); zero selects the default.
	TTL time.Duration
}

// forceFormats is the closed set of client-visible format hints. The
// hint rides the URL, so it must never widen what a token authorizes:
// forcing a transcode of an item the user can already stream is the
// entire attack surface, which is none.
var forceFormats = map[string]string{
	"mp3": "audio/mpeg",
	"wav": "audio/wav",
}

// PlayInfoFor resolves an item into a tokenized stream URL. The token
// binds user and item; the part and boost selections ride the URL as
// plain parameters and are validated again at fetch, like every other
// stream parameter.
func (b *Bridge) PlayInfoFor(ctx context.Context, user, apiItemPID string, opts PlayOptions) (PlayInfo, error) {
	src, err := b.resolver.StreamSource(ctx, apiItemPID, opts.FilePID)
	if err != nil {
		return PlayInfo{}, err
	}
	_, boost := VoiceBoostParams(src, b.caps, opts.VoiceBoost)
	shape := ShapeFor(src, b.caps, boost)
	if mime, ok := forceFormats[opts.ForceFormat]; ok && hasOutput(b.caps, opts.ForceFormat) {
		shape.Format = opts.ForceFormat
		shape.MimeType = mime
		shape.Seekable = true
	}
	token, exp := b.tokens.MintFor(user, apiItemPID, opts.TTL)
	streamURL := "/media/stream?pid=" + url.QueryEscape(apiItemPID) + "&mt=" + url.QueryEscape(token)
	if opts.FilePID != "" {
		streamURL += "&f=" + url.QueryEscape(opts.FilePID)
	}
	if boost {
		streamURL += "&vb=1"
	}
	if _, ok := forceFormats[opts.ForceFormat]; ok {
		streamURL += "&fmt=" + url.QueryEscape(opts.ForceFormat)
	}
	return PlayInfo{
		URL:        streamURL,
		MimeType:   shape.MimeType,
		DurationMS: src.DurationMS,
		Seekable:   shape.Seekable,
		ExpiresAt:  exp,
		VoiceBoost: boost,
	}, nil
}

// srcRef maps an absolute file path onto a WaxFlow root reference
// (name/relpath, forward slashes).
func (b *Bridge) srcRef(path string) (string, error) {
	for _, r := range b.roots {
		rel, err := filepath.Rel(r.Path, path)
		if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
			continue
		}
		return r.Name + "/" + filepath.ToSlash(rel), nil
	}
	return "", fmt.Errorf("flow: %s is under no configured root", path)
}

// ServeStream is the /media/stream handler: verify the media token,
// re-resolve the item, and reverse-proxy the sidecar's answer.
func (b *Bridge) ServeStream(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	pid := q.Get("pid")
	if pid == "" {
		writeJSONError(w, http.StatusBadRequest, "invalid-request", "pid is required")
		return
	}
	// An absent token is the same failure as a bad one: no credential.
	user, err := b.tokens.Verify(q.Get("mt"), pid)
	if err != nil {
		writeJSONError(w, http.StatusUnauthorized, "unauthenticated", "invalid or expired media token")
		return
	}
	src, err := b.resolver.StreamSource(r.Context(), pid, q.Get("f"))
	if err != nil {
		writeJSONError(w, http.StatusNotFound, "not-found", "no streamable item with pid "+pid)
		return
	}
	ref, err := b.srcRef(src.Path)
	if err != nil {
		b.log.Error("stream resolution", "pid", pid, "err", err)
		writeJSONError(w, http.StatusInternalServerError, "internal", "item is not under a streamable root")
		return
	}
	// The boost flag rides the URL, but the gain is derived here from
	// stored loudness and the live capabilities, never from anything
	// client-controlled.
	gainDB, boost := VoiceBoostParams(src, b.caps, q.Get("vb") == "1")
	shape := ShapeFor(src, b.caps, boost)
	// The format hint is client-visible but closed: it can only pick a
	// narrow-endpoint format for an item the token already authorizes.
	if f := q.Get("fmt"); f != "" {
		if _, ok := forceFormats[f]; ok && hasOutput(b.caps, f) {
			shape.Format = f
			shape.Seekable = false
		}
	}
	// Session limits apply only when the stream engages the engine;
	// a seekable shape is a passthrough of the original bytes.
	if !shape.Seekable {
		release, admitted := b.admit(r.Context(), w, user)
		if !admitted {
			return
		}
		defer release()
	}

	params := url.Values{}
	params.Set("src", ref)
	params.Set("format", shape.Format)
	params.Set("id", fmt.Sprintf("%d-%d", src.Size, src.MTimeNS))
	if src.Virtual {
		params.Set("from", strconv.FormatInt(src.FromSample, 10))
		params.Set("to", strconv.FormatInt(src.ToSample, 10))
	}
	if boost {
		params.Set("dynamics", "voice")
		params.Set("gain", strconv.FormatFloat(gainDB, 'f', 1, 64))
	}
	// Time-based seek for non-direct paths: clients pass t= through the
	// tokenized URL and the bridge forwards it.
	if t := q.Get("t"); t != "" {
		params.Set("t", t)
	}
	// The per-user bitrate ceiling applies to lossy encodes only; it is
	// server-derived, never client-controlled.
	if b.gate != nil && lossyBitrateFormats[shape.Format] {
		if cap := b.gate.MaxBitrateKbps(r.Context(), user); cap > 0 {
			params.Set("bitrate", strconv.Itoa(cap))
		}
	}

	// Stash the upstream query for the Rewrite hook.
	r = r.WithContext(context.WithValue(r.Context(), upstreamQueryKey{}, params.Encode()))
	b.proxy.ServeHTTP(w, r)
}

// ServeShareStream streams one item for an anonymous share listener.
// The API layer resolved the share token and enforces per-share
// concurrency; this shapes exactly like ServeStream (direct play for
// whole files, a named format for virtual windows) and bills any
// engine session against the share owner, so a public link never
// becomes someone else's CPU.
func (b *Bridge) ServeShareStream(w http.ResponseWriter, r *http.Request, apiItemPID, ownerUserID string) {
	src, err := b.resolver.StreamSource(r.Context(), apiItemPID, r.URL.Query().Get("f"))
	if err != nil {
		writeJSONError(w, http.StatusNotFound, "not-found", "no streamable item with pid "+apiItemPID)
		return
	}
	ref, err := b.srcRef(src.Path)
	if err != nil {
		b.log.Error("share stream resolution", "pid", apiItemPID, "err", err)
		writeJSONError(w, http.StatusInternalServerError, "internal", "item is not under a streamable root")
		return
	}
	shape := ShapeFor(src, b.caps, false)
	if !shape.Seekable {
		release, admitted := b.admit(r.Context(), w, ownerUserID)
		if !admitted {
			return
		}
		defer release()
	}
	params := url.Values{}
	params.Set("src", ref)
	params.Set("format", shape.Format)
	params.Set("id", fmt.Sprintf("%d-%d", src.Size, src.MTimeNS))
	if src.Virtual {
		params.Set("from", strconv.FormatInt(src.FromSample, 10))
		params.Set("to", strconv.FormatInt(src.ToSample, 10))
	}
	if b.gate != nil && lossyBitrateFormats[shape.Format] {
		if cap := b.gate.MaxBitrateKbps(r.Context(), ownerUserID); cap > 0 {
			params.Set("bitrate", strconv.Itoa(cap))
		}
	}
	r = r.WithContext(context.WithValue(r.Context(), upstreamQueryKey{}, params.Encode()))
	b.proxy.ServeHTTP(w, r)
}

// analysisFormats are the transports the worker audio pull serves:
// WAV for loopback workers, FLAC for remote ones (losslessly identical
// input at roughly half the bytes).
var analysisFormats = map[string]bool{"wav": true, "flac": true}

// ServeAnalysisAudio proxies decode-ready audio for the similarity
// worker: 16 kHz mono, gain untouched. The caller (the API layer)
// authenticates the worker token; this only shapes and proxies. No
// session gate applies: analysis is a server-level integration paced
// by the worker's own concurrency, and the sidecar's live-slot
// admission keeps bulk analysis from starving playback.
func (b *Bridge) ServeAnalysisAudio(w http.ResponseWriter, r *http.Request, apiItemPID string) {
	format := r.URL.Query().Get("format")
	if format == "" {
		format = "wav"
	}
	if !analysisFormats[format] {
		writeJSONError(w, http.StatusBadRequest, "invalid-request", "format must be wav or flac")
		return
	}
	if !hasOutput(b.caps, format) {
		writeJSONError(w, http.StatusServiceUnavailable, "feature-unavailable",
			"the streaming engine does not offer the "+format+" output")
		return
	}
	src, err := b.resolver.StreamSource(r.Context(), apiItemPID, "")
	if err != nil {
		writeJSONError(w, http.StatusNotFound, "not-found", "no streamable item with pid "+apiItemPID)
		return
	}
	if src.Virtual {
		// Virtual tracks share their backing file's essence and are not
		// analyzed per window; work items never name them.
		writeJSONError(w, http.StatusBadRequest, "invalid-request", "virtual tracks are not analyzed")
		return
	}
	ref, err := b.srcRef(src.Path)
	if err != nil {
		b.log.Error("analysis stream resolution", "pid", apiItemPID, "err", err)
		writeJSONError(w, http.StatusInternalServerError, "internal", "item is not under a streamable root")
		return
	}
	params := url.Values{}
	params.Set("src", ref)
	params.Set("format", format)
	params.Set("rate", "16000")
	params.Set("ch", "1")
	params.Set("id", fmt.Sprintf("%d-%d", src.Size, src.MTimeNS))
	r = r.WithContext(context.WithValue(r.Context(), upstreamQueryKey{}, params.Encode()))
	b.proxy.ServeHTTP(w, r)
}

type upstreamQueryKey struct{}

// rewrite points the proxied request at the sidecar's /stream with the
// server-derived parameters and WaxDeck's API key. Client cookies and
// auth never cross; Range headers pass through untouched.
func (b *Bridge) rewrite(pr *httputil.ProxyRequest) {
	pr.Out.URL.Scheme = b.base.Scheme
	pr.Out.URL.Host = b.base.Host
	pr.Out.URL.Path = "/stream"
	pr.Out.URL.RawQuery, _ = pr.In.Context().Value(upstreamQueryKey{}).(string)
	pr.Out.Host = b.base.Host
	pr.Out.Header.Del("Cookie")
	pr.Out.Header.Del("Authorization")
	pr.Out.Header.Set("X-API-Key", b.apiKey)
}

// modifyResponse rewrites the sidecar's 410 source-changed into the
// API's structured stream-stale error, the signal clients re-request
// play-info on.
func (b *Bridge) modifyResponse(resp *http.Response) error {
	if resp.StatusCode != http.StatusGone {
		return nil
	}
	if resp.Body != nil {
		resp.Body.Close()
	}
	body := `{"code":"stream-stale","message":"the stream no longer matches the file on disk; re-request play-info"}` + "\n"
	resp.ContentLength = int64(len(body))
	resp.Header = http.Header{}
	resp.Header.Set("Content-Type", "application/json")
	resp.Header.Set("Content-Length", strconv.Itoa(len(body)))
	resp.Body = io.NopCloser(strings.NewReader(body))
	return nil
}

func writeJSONError(w http.ResponseWriter, status int, code, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	fmt.Fprintf(w, `{"code":%q,"message":%q}`+"\n", code, message)
}
