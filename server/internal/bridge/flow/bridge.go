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
	// ConfigPath is the sidecar's JSON config file, as WaxDeck sees it.
	// Set it and a runtime-added library root reaches the sidecar
	// without a restart: WaxDeck rewrites the file's roots array and
	// posts /roots/reload. Empty leaves root reload unavailable, which
	// is right for an env-configured sidecar (WAXFLOW_ROOTS is read
	// once at process start, so no reload could reflect an edit).
	ConfigPath string
	// Tokens mints and verifies media tokens.
	Tokens *auth.MediaTokens
	// Resolver resolves item PIDs to stream sources.
	Resolver SourceResolver
	// Timelines persists minted timelines so their proxied URLs survive
	// a restart. Nil keeps them in memory only.
	Timelines TimelineStore
	Logger    *slog.Logger
}

// Bridge is the live bridge, holding the sidecar's capabilities as
// fetched at startup.
type Bridge struct {
	base   *url.URL
	apiKey string
	// roots is read by srcRef on every stream mint and grown by AddRoot
	// when a library is created at runtime; rootsMu guards the swap.
	roots   []Root
	rootsMu sync.RWMutex
	// configPath is the sidecar's config file; reloadMu serializes the
	// rewrite-then-reconcile against it.
	configPath string
	reloadMu   sync.Mutex
	tokens     *auth.MediaTokens
	resolver   SourceResolver
	caps       *client.Caps
	client     *client.Client
	proxy      *httputil.ReverseProxy
	log        *slog.Logger
	// gate admits engine-backed stream sessions; nil admits everything.
	gate TranscodeGate

	// Timeline bookkeeping, built lazily on first use; tlStore persists
	// the stash half of it and is nil when nothing was configured.
	tlOnce  sync.Once
	tl      *timelineState
	tlStore TimelineStore
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
	// No client options: the only calls made through c are JSON (Caps here,
	// Sign and CreateTimeline on the stream path), and the client self-bounds
	// each at its 30s per-call default when ctx carries no deadline. That
	// preserves the effective bound the removed client-wide 30s timeout gave
	// these calls, so nothing here depended on it. Streaming rides b.proxy, not
	// these methods, so unbounded stream bodies never reach c.
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
	roots := append([]Root(nil), cfg.Roots...)
	sortRoots(roots)

	b := &Bridge{
		base:       base,
		apiKey:     cfg.APIKey,
		roots:      roots,
		configPath: cfg.ConfigPath,
		tokens:     cfg.Tokens,
		resolver:   cfg.Resolver,
		caps:       caps,
		client:     c,
		log:        log,
		tlStore:    cfg.Timelines,
	}
	if b.tlStore != nil {
		if err := b.loadTimelineStash(ctx); err != nil {
			// A stash that cannot be read is not fatal: every live
			// timeline URL re-mints, which is what a restart cost
			// unconditionally before the stash was persisted at all.
			log.Warn("loading the timeline stash", "err", err)
		}
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
		"hls", caps.Delivery.HLS,
		"rootsReload", b.RootsReloadSupported())
	return b, nil
}

// sortRoots orders roots longest path first, so a root nested inside
// another resolves to the most specific name.
func sortRoots(roots []Root) {
	sort.SliceStable(roots, func(i, j int) bool { return len(roots[i].Path) > len(roots[j].Path) })
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
	// AppliedBitrateKbps is the bitrate cap the minted stream carries
	// (the request clamped to the caller's ceiling); zero when the cap
	// did not re-encode the stream.
	AppliedBitrateKbps int
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
	// DeviceFormats are the media types a device endpoint said it
	// accepts. Non-empty replaces ForceFormat with the source-aware
	// answer from DeviceFormat, which may be the original bytes;
	// ForceFormat stays the floor that answer falls back to. Empty
	// leaves ForceFormat alone, which is every caller that is not a
	// device endpoint.
	DeviceFormats []string
	// TTL sizes the media token for long deliveries (whole-queue
	// casts); zero selects the default.
	TTL time.Duration
	// MaxBitrateKbps caps the stream's bitrate. It only ever narrows:
	// the mint clamps it to the caller's transcode ceiling, and a lossy
	// source already inside the cap streams unchanged. Zero (every
	// caller but the client play-info surface) changes nothing.
	MaxBitrateKbps int
}

// forceFormats is the closed set of client-visible format hints. The
// hint rides the URL, so it must never widen what a token authorizes:
// forcing a transcode of an item the user can already stream is the
// entire attack surface, which is none. Every entry is an engine output
// and is served only when the live caps carry it. Opus is here for the
// bitrate-capped streams play-info mints.
var forceFormats = map[string]string{
	"mp3":  "audio/mpeg",
	"wav":  "audio/wav",
	"flac": "audio/flac",
	"aac":  "audio/mp4",
	"opus": "audio/ogg",
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
	force := opts.ForceFormat
	advertise := ""
	if len(opts.DeviceFormats) > 0 {
		// A device that named what it plays gets the source-aware answer,
		// which needs the source and the shape and so cannot be decided
		// by the caller. It may be "serve the original bytes", which is
		// why this can clear a floor the caller set rather than only
		// narrowing it, and it may name a spelling of the media type
		// that differs from ours, which is what the device has to see.
		force, advertise = DeviceFormat(src, shape, b.caps, opts.DeviceFormats, opts.ForceFormat)
	}
	mime, forced := forceFormats[force]
	// The fetch side gates on the live caps too, so a format this daemon
	// cannot produce must not reach the URL either: the two decisions
	// have to agree or the mime advertised here would describe bytes the
	// stream never serves.
	forced = forced && hasOutput(b.caps, force)
	if forced {
		// Proxy mode carries the forced format on the URL (&fmt= below), so the
		// shape's Format is never read here; only the client-facing MimeType and
		// Seekable come off the shape.
		shape.MimeType = mime
		shape.Seekable = true
	}
	if advertise != "" {
		// The device's own spelling of the type it is about to receive.
		// It wins over both branches above, including the passthrough
		// one, because a resource declaring a type absent from the
		// device's sink is one the strict renderers refuse.
		shape.MimeType = advertise
	}
	// A bitrate cap resolves at mint time like voice boost: clamped to
	// the caller's own transcode ceiling, then applied only when the
	// source does not already satisfy it. Device endpoints never pass
	// one, so a forced format and a cap cannot meet.
	capKbps := 0
	if opts.MaxBitrateKbps > 0 && !forced {
		capKbps = opts.MaxBitrateKbps
		if b.gate != nil {
			if ceiling := b.gate.MaxBitrateKbps(ctx, user); ceiling > 0 {
				capKbps = min(capKbps, ceiling)
			}
		}
		capped, applied := CappedShape(src, b.caps, shape, capKbps)
		if applied {
			shape = capped
		} else {
			capKbps = 0
		}
	}
	token, exp := b.tokens.MintFor(user, apiItemPID, opts.TTL)
	streamURL := "/media/stream?pid=" + url.QueryEscape(apiItemPID) + "&mt=" + url.QueryEscape(token)
	if opts.FilePID != "" {
		streamURL += "&f=" + url.QueryEscape(opts.FilePID)
	}
	if boost {
		streamURL += "&vb=1"
	}
	if forced {
		streamURL += "&fmt=" + url.QueryEscape(force)
	}
	if capKbps > 0 {
		// The capped encode rides the same closed format hint the device
		// paths use, plus the cap itself; the fetch side re-validates
		// both and re-clamps against the ceiling.
		streamURL += "&fmt=" + url.QueryEscape(shape.Format) + "&br=" + strconv.Itoa(capKbps)
	}
	return PlayInfo{
		URL:                streamURL,
		MimeType:           shape.MimeType,
		DurationMS:         src.DurationMS,
		Seekable:           shape.Seekable,
		ExpiresAt:          exp,
		VoiceBoost:         boost,
		AppliedBitrateKbps: capKbps,
	}, nil
}

// srcRef maps an absolute file path onto a WaxFlow root reference
// (name/relpath, forward slashes).
func (b *Bridge) srcRef(path string) (string, error) {
	b.rootsMu.RLock()
	defer b.rootsMu.RUnlock()
	for _, r := range b.roots {
		rel, err := filepath.Rel(r.Path, path)
		if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
			continue
		}
		return r.Name + "/" + filepath.ToSlash(rel), nil
	}
	return "", fmt.Errorf("flow: %s is under no configured root", path)
}

// AddRoot teaches the bridge a library root created at runtime. Without
// it a reload the sidecar accepted still leaves streaming broken: srcRef
// walks the startup snapshot, so a path under a root the bridge has
// never heard of maps to no reference at all. The append keeps New's
// longest-path-first ordering, and swaps the slice copy-on-write.
func (b *Bridge) AddRoot(name, path string) {
	b.rootsMu.Lock()
	defer b.rootsMu.Unlock()
	roots := append(append([]Root(nil), b.roots...), Root{Name: name, Path: path})
	sortRoots(roots)
	b.roots = roots
}

// removeRoot drops a root the sidecar refused, so the bridge's table
// stays what the sidecar can actually serve.
func (b *Bridge) removeRoot(name string) {
	b.rootsMu.Lock()
	defer b.rootsMu.Unlock()
	roots := make([]Root, 0, len(b.roots))
	for _, r := range b.roots {
		if r.Name != name {
			roots = append(roots, r)
		}
	}
	b.roots = roots
}

// SyncRoot teaches the bridge a library root created at runtime and
// brings the sidecar to the same set. A nil error means streaming from
// the new root works now; any error names what an administrator still
// has to do.
//
// Either both sides end up knowing the root or neither does. A refused
// reload restores the config file and drops the root back out of the
// bridge, for two reasons: the sidecar opens every root at startup, so
// a path it refused would turn its next restart into a boot failure,
// and a rejected root left in the set would be re-sent with the next
// library and take that one down with it.
func (b *Bridge) SyncRoot(ctx context.Context, name, path string) error {
	if !b.RootsReloadSupported() {
		b.AddRoot(name, path)
		// The root is not written to the sidecar's config either, and the
		// message says so rather than implying a restart alone would find
		// it. Writing it unreloaded would put an unvalidated path in a file
		// the sidecar opens at startup: the reload is what proves the
		// sidecar can see a path, and a config it cannot open is a boot
		// failure, which is the same hazard the refusal rollback below
		// exists to prevent.
		//
		// The bridge keeps the root: its table is WaxDeck's own view, and
		// an operator who configures the root on the sidecar and restarts it
		// then gets streaming without restarting WaxDeck too.
		if b.configPath == "" {
			return fmt.Errorf("no sidecar config file is configured (set --flow-config), so this root has to be added to the sidecar's own configuration and the sidecar restarted before it streams")
		}
		return fmt.Errorf("the sidecar at %s does not accept root reloads, so this root has to be added to its configuration and the sidecar restarted before it streams", b.base)
	}
	// The lock spans the add as well as the reload. Without that, two
	// concurrent library creates cross-contaminate: each adds its root,
	// then the first reload carries both, and one bad path fails the other
	// create's reload and rolls its good root back out.
	b.reloadMu.Lock()
	defer b.reloadMu.Unlock()
	b.AddRoot(name, path)
	if err := b.reloadRootsLocked(ctx); err != nil {
		b.removeRoot(name)
		return err
	}
	return nil
}

// RootNames lists every root name the bridge maps. It is wider than the
// service's library-root table on purpose: the podcast download dir is
// appended here and never enters that table, and the name is the
// sidecar's addressing key, so a library reusing one would make
// stream-ref resolution ambiguous.
func (b *Bridge) RootNames() []string {
	b.rootsMu.RLock()
	defer b.rootsMu.RUnlock()
	names := make([]string, len(b.roots))
	for i, r := range b.roots {
		names[i] = r.Name
	}
	return names
}

// snapshotRoots copies the root table for a caller that ranges outside
// the lock.
func (b *Bridge) snapshotRoots() []Root {
	b.rootsMu.RLock()
	defer b.rootsMu.RUnlock()
	return append([]Root(nil), b.roots...)
}

// RootsReloadSupported reports whether a runtime-added root can reach
// the sidecar without restarting it: the sidecar has to serve the
// reload endpoint, and WaxDeck has to know which config file to rewrite.
func (b *Bridge) RootsReloadSupported() bool {
	return b.configPath != "" && b.caps != nil && b.caps.Delivery.RootsReload
}

// ReloadRoots rewrites the sidecar's config file with the bridge's
// current root set and has the sidecar reconcile against it.
//
// The two steps are strictly ordered. The sidecar re-reads the file
// synchronously inside the request, so a reload racing the rename would
// reconcile the pre-edit config and report a success that changed
// nothing; writeRootsConfig returns only once its fsync and rename have
// landed. The sidecar opens each root with os.Root during reconcile, so
// a path it cannot see fails here with a clear error instead of half
// working -- and a refusal puts the file back as it was, because the
// sidecar opens its roots at startup too and would refuse to boot from
// the config it just rejected.
func (b *Bridge) ReloadRoots(ctx context.Context) error {
	if b.configPath == "" {
		return fmt.Errorf("flow: no sidecar config file is configured (set --flow-config)")
	}
	if b.caps == nil || !b.caps.Delivery.RootsReload {
		return fmt.Errorf("flow: the sidecar at %s does not serve root reloads", b.base)
	}
	// One reload at a time. Two concurrent library creates would
	// otherwise interleave their rewrites, and a rollback from one could
	// undo the other's accepted set. Library creates are rare enough that
	// serializing them costs nothing.
	b.reloadMu.Lock()
	defer b.reloadMu.Unlock()
	return b.reloadRootsLocked(ctx)
}

// reloadRootsLocked is ReloadRoots' body, called with reloadMu held so
// SyncRoot can hold the lock across its own AddRoot too.
func (b *Bridge) reloadRootsLocked(ctx context.Context) error {
	// The reconcile does not inherit the caller's cancellation. SyncRoot runs
	// on the request context, and the rollback below restores the config file
	// on any error, cancellation included, so an administrator whose browser
	// gives up mid-reconcile would put back a root set the sidecar may
	// already have accepted. That leaves the file disagreeing with the
	// running sidecar, and the file is what the sidecar reads at its next
	// boot, which is the failure the rollback exists to prevent. Dropping the
	// caller's deadline with it is deliberate: the client applies its own 30s
	// default to a context carrying none, which is the bound this POST needs.
	ctx = context.WithoutCancel(ctx)
	prev, perm, err := readRootsConfig(b.configPath)
	if err != nil {
		return err
	}
	if err := writeRootsConfig(b.configPath, prev, perm, b.snapshotRoots()); err != nil {
		return err
	}
	// ReloadRoots answers (nil, err) on any failure, so the delta is read
	// only past this branch.
	delta, err := b.client.ReloadRoots(ctx)
	if err != nil {
		if rerr := writeFileCrashSafe(b.configPath, prev, perm); rerr != nil {
			// The sidecar's next start reads whatever is on disk now, so a
			// failed restore is worse than the reload it followed.
			b.log.Error("restoring the sidecar config after a refused reload",
				"path", b.configPath, "err", rerr)
		}
		// %w, not %s: the client decodes the daemon's error envelope into a
		// waxerr code, and re-stringifying here would throw that away.
		return fmt.Errorf("flow: reloading sidecar roots: %w", err)
	}
	b.log.Info("waxflow roots reloaded",
		"added", delta.Added, "removed", delta.Removed, "changed", delta.Changed, "roots", delta.Roots)
	return nil
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
			// Clear Seekable so this stream routes through the admission control
			// below: a forced format engages the engine (a transcode), not a
			// passthrough of the original bytes. PlayInfoFor advertises this same
			// format to the client as Seekable:true - the encoded endpoint is
			// client-seekable - so here the flag doubles as "no engine session",
			// which a forced format is not.
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
	// The bitrate a lossy encode is bounded to: the smaller of the URL's
	// own cap (minted by play-info, re-validated here like every other
	// stream parameter) and the per-user ceiling, which is server-derived
	// - so an edited br can only narrow what the token authorizes. Only
	// for shapes that engage the engine: a seekable shape is a
	// passthrough of the original bytes, and honoring br there would
	// hand out an un-admitted transcode of a stream that was never
	// charged as one.
	if !shape.Seekable && lossyBitrateFormats[shape.Format] {
		bitrate := 0
		if br, err := strconv.Atoi(q.Get("br")); err == nil &&
			br >= MinStreamBitrateKbps && br <= MaxStreamBitrateKbps {
			bitrate = br
		}
		if b.gate != nil {
			if ceiling := b.gate.MaxBitrateKbps(r.Context(), user); ceiling > 0 && (bitrate == 0 || ceiling < bitrate) {
				bitrate = ceiling
			}
		}
		if bitrate > 0 {
			params.Set("bitrate", strconv.Itoa(bitrate))
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
	if b.gate != nil && !shape.Seekable && lossyBitrateFormats[shape.Format] {
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
