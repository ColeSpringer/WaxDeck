// Package flow is the WaxFlow bridge: play-info resolution, media
// tokens on the way out, and the reverse proxy that carries stream
// bytes through WaxDeck's single origin. WaxFlow never faces clients;
// per-user policy is enforced at mint and again at every fetch.
package flow

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"math"
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
	// StartOffsetMS is where in the item (the part, for a multi-file
	// book) the served audio begins; positive only when the mint cut a
	// stream that cannot be range-seeked.
	StartOffsetMS int64
}

// PlayOptions select a part of a multi-file item and request DSP.
type PlayOptions struct {
	// Cred is the credential the mint runs under (auth.MediaClaims.Cred):
	// the stream URL dies with it.
	Cred string
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
	// CapFormat is the lossy format a capped encode should land in when
	// the caller named one it can decode. Only a preference, and only
	// where a cap applies at all: the ladder decides otherwise. A client
	// that asks for a cap in mp3 and is handed Ogg gets silence with
	// nothing to explain it, which is what this exists to prevent.
	CapFormat string
	// StartMS asks for the stream to begin this far into the item (the
	// part). Only a stream that cannot be range-seeked is cut, at the
	// whole second at or before it; a seekable one is the client's to
	// seek.
	StartMS int64
	// CutOriginal lets StartMS cut an original that would otherwise play
	// directly, for a client that can only ask for an offset (Subsonic's
	// timeOffset). The cut is a real encode, admitted like any other.
	CutOriginal bool
	// HLS says the caller plays HLS. A stream the engine would encode is
	// then minted as that one item's HLS presentation, which the player
	// seeks itself, wherever the sidecar renders one; StartMS cuts
	// nothing there.
	HLS bool
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
// binds the user, the item, the credential the mint ran under and the
// stream parameters the mint chose (part, boost, format, bitrate), so a
// URL with any of them edited, added or dropped fails at fetch.
func (b *Bridge) PlayInfoFor(ctx context.Context, user, apiItemPID string, opts PlayOptions) (PlayInfo, error) {
	src, err := b.resolver.StreamSource(ctx, apiItemPID, opts.FilePID)
	if err != nil {
		return PlayInfo{}, err
	}
	return b.PlayInfoForSource(ctx, user, apiItemPID, src, opts)
}

// PlayInfoForSource is PlayInfoFor with the source already in hand.
//
// Everything the mint decides - the format policy, voice boost, the
// bitrate cap, the URL - reads the source and nothing else, so a
// caller that resolved a batch of them in one pass mints from those
// rather than asking for each one back. A multi-file audiobook loaded
// onto a device is the case: resolving its parts one at a time re-reads
// the item and the book for every one of them.
//
// The source must be the one apiItemPID and opts.FilePID resolve to.
// Nothing here re-checks that for a stream, because the fetch side does:
// the URL carries the pid and the part, and /media/stream resolves both
// again against the token before it serves a byte. An HLS rendering
// pins the source it was minted from, so only a caller holding what its
// own resolution just answered asks for one.
func (b *Bridge) PlayInfoForSource(ctx context.Context, user, apiItemPID string, src Source, opts PlayOptions) (PlayInfo, error) {
	gainDB, boost := VoiceBoostParams(src, b.caps, opts.VoiceBoost)
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
		capped := b.gate != nil && b.gate.MaxBitrateKbps(ctx, user) > 0
		force, advertise = DeviceFormat(src, shape, b.caps, opts.DeviceFormats, opts.ForceFormat, capped)
	}
	mime, forced := forceFormats[force]
	// The fetch side gates on the live caps too, so a format this daemon
	// cannot produce must not reach the URL either: the two decisions
	// have to agree or the mime advertised here would describe bytes the
	// stream never serves.
	forced = forced && hasOutput(b.caps, force)
	// Forcing the source's own format is not a transcode: the fetch side
	// keeps the auto shape for it, so the URL must not carry the hint
	// either, and the client is told the container's own media type -
	// which is what the untouched shape already carries.
	if forced && shape.Seekable && SameAsSource(src, force) {
		forced = false
	}
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
	// The cut is clamped into the item, since the engine reads one past
	// the end as an empty stream, and floored to whole seconds: each
	// distinct cut is a separate encode of the whole remainder in the
	// engine, so repeats near one spot share one.
	cutSecs := int64(0)
	if opts.StartMS > 0 {
		start := opts.StartMS
		if src.DurationMS > 0 {
			start = min(start, src.DurationMS-1)
		}
		cutSecs = start / 1000
	}
	wantsCut := opts.CutOriginal && cutSecs > 0
	// A bitrate cap resolves at mint time like voice boost: clamped to
	// the caller's own transcode ceiling, then applied only when the
	// source does not already satisfy it. A capped account's engine
	// render is held to its ceiling even when the client asked for no
	// cap, since the engine would otherwise pick its own rate (a carved
	// lossless track renders as FLAC); an original played directly is
	// the file itself and is left alone. Device endpoints never pass a
	// cap: a capped account's device answer above is already lossy (WAV
	// aside, the last resort of a renderer that plays nothing else), and
	// the fetch holds that encode to the ceiling. A cut of an original is
	// an encode too, so it reads the ceiling as well.
	capKbps := 0
	ceiling := 0
	if b.gate != nil && !forced && (opts.MaxBitrateKbps > 0 || !shape.Seekable || wantsCut) {
		ceiling = b.gate.MaxBitrateKbps(ctx, user)
	}
	want := opts.MaxBitrateKbps
	if want == 0 {
		want = ceiling
	}
	if want > 0 && !forced {
		// Clamped here, so "a minted br is a bitrate this engine can
		// speak" is the mint's own invariant rather than something each
		// caller is trusted to have applied first. The REST surface
		// still refuses an out-of-range field outright - that is its
		// contract - and the fetch side re-validates what it is handed
		// like every other stream parameter.
		capKbps = min(max(want, MinStreamBitrateKbps), MaxStreamBitrateKbps)
		if ceiling > 0 {
			capKbps = min(capKbps, ceiling)
		}
		capped, applied := CappedShape(src, b.caps, shape, capKbps)
		if applied {
			// The caller's own target wins over the ladder's when it is
			// one the closed hint set carries and this engine produces:
			// the fetch side gates on the same two, so anything else
			// would advertise a type the stream never serves.
			if f := opts.CapFormat; lossyBitrateFormats[f] && hasOutput(b.caps, f) {
				if mime, closed := forceFormats[f]; closed {
					capped.Format, capped.MimeType = f, mime
				}
			}
			shape = capped
		} else {
			capKbps = 0
		}
	}
	// A player that seeks HLS itself gets the encode as one item's HLS
	// presentation rather than a live stream it could only move inside
	// by minting a cut; failing that, the live stream as ever.
	if opts.HLS && !forced && !opts.CutOriginal && !shape.Seekable {
		if format := hlsFormatFor(shape, b.caps); format != "" {
			if info, ok := b.itemRenderingFor(ctx, user, apiItemPID, src, opts, format, capKbps, gainDB, boost); ok {
				return info, nil
			}
		}
	}
	params := url.Values{}
	if opts.FilePID != "" {
		params.Set("f", opts.FilePID)
	}
	if boost {
		params.Set("vb", "1")
	}
	if forced {
		params.Set("fmt", force)
	}
	// An original is the client's to seek, so a cut never touches one,
	// unless the caller can ask for nothing but an offset. Then what is
	// still a direct play after the cap is encoded as a cap at its own
	// bitrate would encode it, lossless kept lossless: a lossy encode at
	// the original's own rate, or the top of the range where it has none.
	br, encode := capKbps, capKbps > 0
	if wantsCut && shape.Seekable && !forced {
		shape, encode, br = originalCutShape(src, b.caps), true, 0
		if lossyBitrateFormats[shape.Format] {
			br = MaxStreamBitrateKbps
			if !lossless(src.Codec) && src.BitrateKbps > 0 {
				br = min(max(src.BitrateKbps, MinStreamBitrateKbps), MaxStreamBitrateKbps)
			}
		}
	}
	if encode {
		// An encode the mint chose rides the same closed format hint the
		// device paths use, marked as one (enc): a format naming what the
		// file holds is otherwise a copy of it. The rate rides beside it
		// where it has one. All of it is bound into the token, and the
		// fetch holds a lossy encode to the live ceiling.
		params.Set("fmt", shape.Format)
		params.Set("enc", "1")
		if br > 0 {
			params.Set("br", strconv.Itoa(br))
		}
	}
	shapeKey := streamShape(params)
	token, exp := b.tokens.MintFor(auth.MediaClaims{
		User: user, Cred: opts.Cred, Purpose: auth.PurposeStream, PID: apiItemPID, Shape: shapeKey,
	}, opts.TTL)
	streamURL := "/media/stream?pid=" + url.QueryEscape(apiItemPID) + "&mt=" + url.QueryEscape(token)
	if shapeKey != "" {
		streamURL += "&" + shapeKey
	}
	var offset int64
	if cutSecs > 0 && !shape.Seekable {
		// Outside the token on purpose: moving the cut costs the client
		// what minting again would.
		streamURL += "&t=" + strconv.FormatInt(cutSecs, 10)
		offset = cutSecs * 1000
	}
	return PlayInfo{
		URL:                streamURL,
		MimeType:           shape.MimeType,
		DurationMS:         src.DurationMS,
		Seekable:           shape.Seekable,
		ExpiresAt:          exp,
		VoiceBoost:         boost,
		AppliedBitrateKbps: capKbps,
		StartOffsetMS:      offset,
	}, nil
}

// originalCutShape is the encode an original takes when it has to be cut
// rather than played as it is: what a cap at its own bitrate would pick,
// except that lossless stays lossless. A lossy source keeps its codec
// where the engine writes it under a format hint, else Opus or the MP3
// floor.
func originalCutShape(src Source, caps *client.Caps) Shape {
	pick := encodeShape
	if lossless(src.Codec) && hasOutput(caps, "flac") {
		return pick("flac")
	}
	if own := strings.ToLower(src.Codec); lossyBitrateFormats[own] && forceFormats[own] != "" && hasOutput(caps, own) {
		return pick(own)
	}
	if hasOutput(caps, "opus") {
		return pick("opus")
	}
	return pick("mp3")
}

// streamShape is the canonical form of the stream parameters a token
// binds: the ones the mint chooses (join only for a book played as one
// stream), sorted and escaped, so a URL with any of them edited, added
// or dropped no longer matches its token. A seek (t) and a Range stay
// free.
func streamShape(q url.Values) string {
	v := url.Values{}
	for _, k := range []string{"f", "vb", "fmt", "br", "enc", "join"} {
		if x := q.Get(k); x != "" {
			v.Set(k, x)
		}
	}
	return v.Encode()
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
	// The token binds the stream parameters as well as the item, so an
	// edited URL is a bad token rather than a different stream.
	claims, err := b.tokens.Verify(q.Get("mt"), auth.MediaWant{
		Purposes: []string{auth.PurposeStream}, PID: pid, Shape: streamShape(q),
	})
	if err != nil {
		writeJSONError(w, http.StatusUnauthorized, "unauthenticated", "invalid or expired media token")
		return
	}
	if !b.authorize(r.Context(), w, claims) {
		return
	}
	if q.Get("join") != "" {
		b.serveJoined(w, r, claims.User, pid, q)
		return
	}
	user := claims.User
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
		_, known := forceFormats[f]
		// A hint naming what the file already holds asks for a copy of
		// the source, so the auto shape stands and the original bytes
		// serve: no engine, no session, no slot. Seekable is exactly
		// "not virtual and not boosted", and either of those means the
		// source is not what would be served.
		//
		// The mint's encode marker (enc) is what says this hint is not
		// that hint: it marks a format the mint chose for a real encode (a
		// cap, a cut of an original), and on a source that happens to
		// already be in that format the name alone is indistinguishable.
		// Reading it as a copy served the original bytes at the source's
		// own bitrate, uncharged, while the client had been told a
		// smaller number.
		copyOfSource := shape.Seekable && q.Get("enc") == "" && SameAsSource(src, f)
		if known && hasOutput(b.caps, f) && !copyOfSource {
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
	// Checked once the shape is final and before admission, so a cut that
	// is refused takes no slot.
	cut, _, err := streamCut(q.Get("t"), shape, src.DurationMS)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid-request", err.Error())
		return
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
	setWindow(params, src)
	if boost {
		params.Set("dynamics", "voice")
		params.Set("gain", strconv.FormatFloat(gainDB, 'f', 1, 64))
	}
	if cut != "" {
		params.Set("t", cut)
	}
	// The bitrate a lossy encode is bounded to. Only for shapes that engage
	// the engine: a seekable shape is a passthrough of the original bytes,
	// and honoring br there would hand out an un-admitted transcode of a
	// stream that was never charged as one - which is also why a direct
	// play reads no ceiling at all.
	if !shape.Seekable && lossyBitrateFormats[shape.Format] {
		if bitrate := b.heldBitrate(r.Context(), user, q.Get("br")); bitrate > 0 {
			params.Set("bitrate", strconv.Itoa(bitrate))
		}
	}

	// Stash the upstream query for the Rewrite hook.
	r = r.WithContext(context.WithValue(r.Context(), upstreamQueryKey{}, params.Encode()))
	b.proxy.ServeHTTP(w, r)
}

// heldBitrate is the bitrate a lossy encode is held to: the smaller of the
// URL's own (raw, the mint's choice, bound into the token, so an edited br
// never got this far) and the account's live ceiling, which may have
// dropped since the mint. Zero leaves the engine its own rate.
func (b *Bridge) heldBitrate(ctx context.Context, user, raw string) int {
	bitrate := 0
	if br, err := strconv.Atoi(raw); err == nil && br >= MinStreamBitrateKbps && br <= MaxStreamBitrateKbps {
		bitrate = br
	}
	if b.gate != nil {
		if ceiling := b.gate.MaxBitrateKbps(ctx, user); ceiling > 0 && (bitrate == 0 || ceiling < bitrate) {
			bitrate = ceiling
		}
	}
	return bitrate
}

// maxCutSeconds is the furthest cut the engine accepts.
const maxCutSeconds = 1e9

// streamCut validates a fetch's t, the seconds into the item at which the
// engine starts the stream, and answers the spelling to forward (empty for
// no cut) and the milliseconds it cuts. A cut is the engine's to make, so t
// rides only a shape that already engages it: on a direct play it would
// turn the original into an unadmitted decode. At or past the end clamps
// to the item's last millisecond, as the mint does, since the engine reads
// the end itself as an empty stream, which a player takes for the item
// ending.
func streamCut(raw string, shape Shape, durationMS int64) (string, int64, error) {
	if raw == "" {
		return "", 0, nil
	}
	if shape.Seekable {
		return "", 0, errors.New("t applies only to a stream the engine cuts; seek this one with a range request")
	}
	secs, err := strconv.ParseFloat(raw, 64)
	if err != nil || math.IsNaN(secs) || math.IsInf(secs, 0) || secs < 0 {
		return "", 0, errors.New("t must be a finite, non-negative number of seconds")
	}
	limit := maxCutSeconds
	if durationMS > 0 {
		limit = float64(durationMS-1) / 1000
	}
	// Whole milliseconds, one spelling per cut: each spelling is its own
	// encode in the engine.
	ms := math.Round(min(secs, limit) * 1000)
	if ms == 0 {
		return "", 0, nil
	}
	return strconv.FormatFloat(ms/1000, 'f', -1, 64), int64(ms), nil
}

// ServeShareStream streams one item for an anonymous share listener.
// The API layer resolved the share token and enforces per-share
// concurrency; this shapes exactly like ServeStream (direct play for
// whole files, a named format for virtual windows) and bills any
// engine session against the share owner, so a public link never
// becomes someone else's CPU.
func (b *Bridge) ServeShareStream(w http.ResponseWriter, r *http.Request, apiItemPID, ownerUserID string) {
	src, err := b.resolver.StreamSource(r.Context(), apiItemPID, r.URL.Query().Get("f"))
	if errors.Is(err, ErrCatalogMaintenance) {
		// Briefly away, which a player retries; not found, it does not.
		writeJSONError(w, http.StatusServiceUnavailable, "catalog-maintenance", "the catalog is in maintenance; retry shortly")
		return
	}
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
	setWindow(params, src)
	if !shape.Seekable && lossyBitrateFormats[shape.Format] {
		if bitrate := b.heldBitrate(r.Context(), ownerUserID, ""); bitrate > 0 {
			params.Set("bitrate", strconv.Itoa(bitrate))
		}
	}
	r = r.WithContext(context.WithValue(r.Context(), upstreamQueryKey{}, params.Encode()))
	b.proxy.ServeHTTP(w, r)
}

// setWindow bounds a virtual source to its window. An end at the end of
// the file is omitted: the sidecar reads to=0 as the empty span.
func setWindow(params url.Values, src Source) {
	if !src.Virtual {
		return
	}
	params.Set("from", strconv.FormatInt(src.FromSample, 10))
	if src.ToSample > 0 {
		params.Set("to", strconv.FormatInt(src.ToSample, 10))
	}
}

// analysisFormats are the transports the worker audio pull serves:
// WAV for loopback workers, FLAC for remote ones (losslessly identical
// input at roughly half the bytes).
var analysisFormats = map[string]bool{"wav": true, "flac": true}

// ServeAnalysisAudio proxies decode-ready audio for the similarity worker:
// 16 kHz mono, gain untouched, a carved track's own window. The API layer
// authenticates the worker; the sidecar's live-slot admission guards playback.
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
	setWindow(params, src)
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

// modifyResponse answers every refusal of the engine's in the API's own
// envelope (engineRefusal): 410 source-changed is stream-stale, the signal
// to re-request play-info, 503 overloaded is transcode-limited, so a
// client has one busy code whichever limit was reached, and the engine's
// body, which names the file it could not open, never passes. Every
// request through here carries this server's key, so a refused one is
// logged: only an administrator can fix it.
func (b *Bridge) modifyResponse(resp *http.Response) error {
	if resp.StatusCode < http.StatusBadRequest {
		return nil
	}
	if keyRefused(resp) {
		b.log.Error("the streaming engine refused this server's API key: --flow-api-key (WAXDECK_FLOW_API_KEY) must be one the engine accepts (WAXFLOW_API_KEYS)",
			"status", resp.StatusCode)
	}
	engine := resp.Header
	status, code, message := engineRefusal(resp, true)
	replaceWithError(resp, status, code, message)
	refusalHeaders(resp.Header, engine, status)
	return nil
}

// engineRefusal is what the API answers for a refusal of the engine's, in
// place of the engine's own body, which names the file it could not open
// and speaks the engine's codes. The status a player acts on stays, save
// three. A credential refused is the URL's to renew, as a lapsed token
// is, where the engine judged the signature the URL carries (an HLS
// child); where it judged this server's key, the server is misconfigured,
// which no fresh URL cures, so it answers as the engine out of reach does
// (keyRefused). And a busy engine is the busy code a stream answers where
// item is set (a stream, or one item's rendering). A timeline's stays a
// 503, which hls.js retries and the web player does not read as the
// session cap.
func engineRefusal(resp *http.Response, item bool) (status int, code, message string) {
	status, code, message = resp.StatusCode, "internal", "the streaming engine could not serve this; retry shortly"
	busy := sidecarBusy(resp)
	switch {
	case busy && item:
		return http.StatusTooManyRequests, "transcode-limited", "the streaming engine is busy; retry shortly"
	case busy:
		message = "the streaming engine is busy; retry shortly"
	case status == http.StatusGone:
		code, message = "stream-stale", "the stream no longer matches the file on disk; re-request it"
	case keyRefused(resp):
		return http.StatusBadGateway, "internal", "the streaming engine refused this server's credentials"
	case status == http.StatusUnauthorized || status == http.StatusForbidden:
		return http.StatusUnauthorized, "unauthenticated", "this stream URL is no longer valid; re-request it"
	case status == http.StatusNotFound:
		code, message = "not-found", "this stream is no longer available; re-request it"
	case status == http.StatusRequestedRangeNotSatisfiable:
		code, message = "invalid-request", "the range is outside the stream"
	case status < http.StatusInternalServerError:
		code, message = "invalid-request", "the streaming engine would not take this request"
	}
	return status, code, message
}

// refusalHeaders carries what an engine refusal says beside its body into
// the API's answer: when to come back, and a range refusal's length.
func refusalHeaders(dst, engine http.Header, status int) {
	if v := engine.Get("Retry-After"); v != "" && (status == http.StatusTooManyRequests || status == http.StatusServiceUnavailable) {
		dst.Set("Retry-After", v)
	}
	if v := engine.Get("Content-Range"); v != "" && status == http.StatusRequestedRangeNotSatisfiable {
		dst.Set("Content-Range", v)
	}
}

// replaceWithError swaps a proxied response for an API error envelope.
func replaceWithError(resp *http.Response, status int, code, message string) {
	if resp.Body != nil {
		resp.Body.Close()
	}
	body := fmt.Sprintf(`{"code":%q,"message":%q}`+"\n", code, message)
	resp.StatusCode = status
	resp.Status = fmt.Sprintf("%d %s", status, http.StatusText(status))
	resp.ContentLength = int64(len(body))
	resp.Header = http.Header{}
	resp.Header.Set("Content-Type", "application/json")
	resp.Header.Set("Content-Length", strconv.Itoa(len(body)))
	resp.Body = io.NopCloser(strings.NewReader(body))
}

// keyRefused reports whether resp is the engine refusing the API key this
// server presented: a credential refused on a request that carried the
// key, since the engine passes any request whose key it holds whatever
// else the URL says.
func keyRefused(resp *http.Response) bool {
	return (resp.StatusCode == http.StatusUnauthorized || resp.StatusCode == http.StatusForbidden) &&
		resp.Request != nil && resp.Request.Header.Get("X-API-Key") != ""
}

// sidecarBusy reports whether resp is the engine refusing for want of a
// live slot: its own 503 overloaded.
func sidecarBusy(resp *http.Response) bool {
	return resp.StatusCode == http.StatusServiceUnavailable && sidecarCode(resp) == "overloaded"
}

// sidecarCode reads the code out of a sidecar error envelope and leaves
// the body readable whole, for a refusal that passes through as it is.
func sidecarCode(resp *http.Response) string {
	if resp.Body == nil {
		return ""
	}
	orig := resp.Body
	head, _ := io.ReadAll(io.LimitReader(orig, 64<<10))
	resp.Body = struct {
		io.Reader
		io.Closer
	}{io.MultiReader(bytes.NewReader(head), orig), orig}
	var e struct {
		Code string `json:"code"`
	}
	if json.Unmarshal(head, &e) != nil {
		return ""
	}
	return e.Code
}

func writeJSONError(w http.ResponseWriter, status int, code, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	fmt.Fprintf(w, `{"code":%q,"message":%q}`+"\n", code, message)
}
