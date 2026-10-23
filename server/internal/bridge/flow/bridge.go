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
	"slices"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/colespringer/waxflow/client"
	"github.com/colespringer/waxflow/waxerr"

	"github.com/colespringer/waxdeck/server/internal/auth"
)

// The engine connection's schedule: an ask that fails is repeated after
// retryMin, doubling to retryMax; an engine that answers is asked again
// every probeEvery; one ask waits probeTimeout at most, which is what
// finds an engine that accepts connections and answers nothing.
const (
	defaultRetryMin     = time.Second
	defaultRetryMax     = 30 * time.Second
	defaultProbeEvery   = 15 * time.Second
	defaultProbeTimeout = 5 * time.Second
	defaultStallLimit   = 30 * time.Second
)

// ErrEngineDown is a request that needs the streaming engine while it
// is not answering.
var ErrEngineDown = errors.New("the streaming engine is not reachable right now")

// FeatureStreamingEngine is the feature-unavailable param that names the
// engine, and EngineRetrySeconds is when its refusal says to ask again:
// the probe interval, as a hint. An engine away for a while is asked
// less often than that (Run backs off to retryMax), so a client asking
// again on time may meet the same refusal.
const (
	FeatureStreamingEngine = "streaming-engine"
	EngineRetrySeconds     = 15
)

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

// Bridge is the live bridge, holding the sidecar's capabilities while
// it answers.
type Bridge struct {
	base   *url.URL
	apiKey string
	// roots is read by srcRef on every stream mint and grown by AddRoot
	// when a library is created at runtime; rootsMu guards the swap.
	roots   []Root
	rootsMu sync.RWMutex
	// configPath is the sidecar's config file; reloadMu serializes the
	// rewrite-then-reconcile against it, and guards pending, a change made
	// while the engine was away that its next answer reloads.
	configPath string
	reloadMu   sync.Mutex
	pending    *rootsPending
	tokens     *auth.MediaTokens
	resolver   SourceResolver
	// caps is the engine's last answer, nil while it is not answering.
	// Every reader takes it once per call (Caps) and reads nil as no
	// engine.
	caps   atomic.Pointer[client.Caps]
	client *client.Client
	proxy  *httputil.ReverseProxy
	log    *slog.Logger
	// engineHTTP carries the requests a stream makes of the engine outside
	// the proxy (an HLS rendering's, a joined book's parts), with the
	// proxy's own stall-bounded transport.
	engineHTTP *http.Client
	// gate admits engine-backed stream sessions; nil admits everything.
	gate TranscodeGate

	// link is what the bridge last said about the engine, which is what
	// keeps the log and the hooks to one word per crossing, and why is the
	// reason it is down, which is said apart. linkMu serializes the
	// crossings and queues each one's hooks in told, which runHooks tells
	// outside it, one crossing at a time (hookMu). kick asks Run to probe
	// now.
	linkMu sync.Mutex
	link   linkState
	why    downWhy
	told   []func()
	hookMu sync.Mutex
	onUp   []func(context.Context, Status)
	onDown []func()
	// onHeld runs on an answer that crosses nothing while root adds are
	// held for one (OnHeld).
	onHeld []func(held []string)
	kick   chan struct{}

	retryMin, retryMax, probeEvery, probeTimeout time.Duration
	// stallLimit bounds one wait on the engine during a stream: for its
	// headers, and for each read of its body (stallTransport).
	stallLimit time.Duration
	// reloadTimeout bounds a root reload; zero leaves the client's own
	// bound on a call.
	reloadTimeout time.Duration

	// Timeline bookkeeping, built lazily on first use; tlStore persists
	// the stash half of it and is nil when nothing was configured.
	tlOnce  sync.Once
	tl      *timelineState
	tlStore TimelineStore
}

// CheckBaseURL refuses an engine address New cannot use, for a start that
// checks its settings before it opens anything.
func CheckBaseURL(raw string) error {
	if u, err := url.Parse(raw); err != nil || u.Scheme == "" || u.Host == "" {
		return fmt.Errorf("flow: bad base URL %q", raw)
	}
	return nil
}

// New builds the bridge without asking anything of the sidecar: until
// Run (or Connect) hears it answer, the bridge reads as no engine and
// originals serve directly, so a server starts whether or not its
// engine is up.
func New(ctx context.Context, cfg Config) (*Bridge, error) {
	if err := CheckBaseURL(cfg.BaseURL); err != nil {
		return nil, err
	}
	base, _ := url.Parse(cfg.BaseURL)
	log := cfg.Logger
	if log == nil {
		log = slog.New(slog.DiscardHandler)
	}
	// No client options: the only calls made through c are JSON (Caps,
	// Sign and CreateTimeline), and the client self-bounds each at its 30s
	// per-call default when ctx carries no deadline; the probe sets its own.
	// Streaming rides b.proxy, not these methods, so unbounded stream
	// bodies never reach c.
	c, err := client.New(cfg.BaseURL, cfg.APIKey)
	if err != nil {
		return nil, fmt.Errorf("flow: %w", err)
	}
	roots := append([]Root(nil), cfg.Roots...)
	sortRoots(roots)

	b := &Bridge{
		base:         base,
		apiKey:       cfg.APIKey,
		roots:        roots,
		configPath:   cfg.ConfigPath,
		tokens:       cfg.Tokens,
		resolver:     cfg.Resolver,
		client:       c,
		log:          log,
		tlStore:      cfg.Timelines,
		kick:         make(chan struct{}, 1),
		retryMin:     defaultRetryMin,
		retryMax:     defaultRetryMax,
		probeEvery:   defaultProbeEvery,
		probeTimeout: defaultProbeTimeout,
		stallLimit:   defaultStallLimit,
	}
	if b.tlStore != nil {
		if err := b.loadTimelineStash(ctx); err != nil {
			// A stash that cannot be read is not fatal: every live
			// timeline URL re-mints, which is what a restart cost
			// unconditionally before the stash was persisted at all.
			log.Warn("loading the timeline stash", "err", err)
		}
	}
	b.engineHTTP = &http.Client{Transport: b.engineTransport()}
	b.proxy = &httputil.ReverseProxy{
		Transport:      b.engineHTTP.Transport,
		Rewrite:        b.rewrite,
		ModifyResponse: b.modifyResponse,
		ErrorHandler: func(w http.ResponseWriter, r *http.Request, err error) {
			log.Error("stream proxy", "err", err)
			b.unreachable(r.Context(), err)
			writeJSONError(w, http.StatusBadGateway, "internal", "stream backend unavailable")
		},
		// Audio is latency-sensitive: flush as bytes arrive, never buffer.
		FlushInterval: -1,
	}
	return b, nil
}

// linkState is what the bridge has said about the engine so far.
type linkState int

const (
	linkUnknown linkState = iota
	linkUp
	linkDown
)

// downWhy is why the engine is down, as the bridge last said: not
// answering, refusing this server's key, or answering without what this
// server needs of it (lacks).
type downWhy struct {
	refused bool
	lacks   string
}

// downWhyOf reads why a failed ask left the engine down.
func downWhyOf(err error) downWhy {
	var cannot *cannotServeError
	if errors.As(err, &cannot) {
		return downWhy{lacks: cannot.lacks}
	}
	return downWhy{refused: credentialsRefused(err)}
}

// cannotServeError is an engine that answers without something this
// server needs of it.
type cannotServeError struct{ lacks string }

func (e *cannotServeError) Error() string {
	return "the streaming engine does not offer " + e.lacks
}

// lacking names what this server needs of an engine that caps does not
// offer, empty when it offers it all: progressive streams, which every
// stream the bridge mints is.
func lacking(caps *client.Caps) string {
	if !caps.Delivery.Progressive {
		return "progressive streams"
	}
	return ""
}

// OnUp registers fn to run each time the engine answers after not
// answering: its first answer, and its return from every outage. st is
// what it offers in the answer that crossed, which a request finding the
// engine gone a moment later cannot change under fn. The hooks run on
// the probe, never on a request, one crossing at a time and in the order
// of the crossings. Register before Run.
func (b *Bridge) OnUp(fn func(ctx context.Context, st Status)) {
	b.linkMu.Lock()
	defer b.linkMu.Unlock()
	b.onUp = append(b.onUp, fn)
}

// OnDown registers fn to run each time the engine stops answering (a
// probe that fails, or a request that finds it gone, at the probe it asks
// for), and once at startup when its first ask fails. Register before
// Run.
func (b *Bridge) OnDown(fn func()) {
	b.linkMu.Lock()
	defer b.linkMu.Unlock()
	b.onDown = append(b.onDown, fn)
}

// OnHeld registers fn to run on an answer that crosses nothing while root
// adds are held for the engine (an add whose reload got no answer while it
// stayed up), with their names, so they are offered again now rather than
// at the next crossing, whose OnUp offers them anyway. Register before
// Run.
func (b *Bridge) OnHeld(fn func(held []string)) {
	b.linkMu.Lock()
	defer b.linkMu.Unlock()
	b.onHeld = append(b.onHeld, fn)
}

// Run keeps the bridge connected for the life of ctx: it asks the
// engine for its capabilities until it answers, backing off from
// retryMin to retryMax, then asks again every probeEvery, and at once
// when a request finds the engine gone. An engine that answers without
// what this server needs is asked every probeEvery too, so an upgraded
// one is taken on without a restart. It returns nil when ctx ends.
func (b *Bridge) Run(ctx context.Context) error {
	wait := b.retryMin
	for {
		next := b.probeEvery
		var cannot *cannotServeError
		if err := b.Connect(ctx); err == nil || errors.As(err, &cannot) {
			wait = b.retryMin
		} else {
			next = wait
			wait = min(wait*2, b.retryMax)
		}
		if ctx.Err() != nil {
			return nil
		}
		timer := time.NewTimer(next)
		select {
		case <-ctx.Done():
			timer.Stop()
			return nil
		case <-b.kick:
			timer.Stop()
		case <-timer.C:
		}
	}
}

// Connect asks the engine for its capabilities once and settles the
// bridge on the answer: up, with the snapshot every reader takes, or
// down. A crossing is logged once and runs the hooks, after those of the
// crossings requests made since the last ask. Run is this on a schedule;
// a caller that needs the answer now asks directly.
func (b *Bridge) Connect(ctx context.Context) error {
	b.runHooks()
	ask, cancel := context.WithTimeout(ctx, b.probeTimeout)
	caps, err := b.client.Caps(ask)
	cancel()
	if ctx.Err() != nil {
		return ctx.Err()
	}
	if err == nil {
		if lacks := lacking(caps); lacks != "" {
			err = &cannotServeError{lacks: lacks}
		}
	}
	// The removals made while the engine was away are reloaded before the
	// answer is taken, so the crossing's hooks see the table settled; a
	// reload that gets no answer makes this no answer either.
	if err == nil {
		err = b.reloadPending(ctx, caps)
	}
	crossed := b.settle(ctx, caps, err)
	b.runHooks()
	if err == nil {
		// A removal made while the answer was being taken found the engine
		// away; it waits on this answer too, not on the next probe.
		if rerr := b.reloadPending(ctx, caps); rerr != nil {
			b.reloadUnanswered(rerr)
			b.runHooks()
		} else if !crossed {
			// Adds held for an answer (a reload that got none while the
			// engine stayed up) are offered again now; a crossing's OnUp
			// offers them already.
			b.offerHeld()
		}
	}
	return err
}

// settle records one answer of the engine's, queueing the hooks of a
// crossing, and reports whether it crossed up.
func (b *Bridge) settle(ctx context.Context, caps *client.Caps, err error) (crossedUp bool) {
	b.linkMu.Lock()
	defer b.linkMu.Unlock()
	if err != nil {
		b.caps.Store(nil)
		why := downWhyOf(err)
		if b.link == linkDown && b.why == why {
			return
		}
		// A refused key is a setting to fix and an engine that cannot serve
		// this server one to replace, each said whatever came before it; a
		// loss is news; an engine not up yet at startup is the ordinary
		// boot, which under compose starts it once this server is healthy.
		switch {
		case why.refused:
			b.log.Error(keyRefusedLog+"; serving originals directly until it does",
				"base", b.base.String(), "err", err)
		case why.lacks != "":
			b.log.Error("the streaming engine answers but cannot serve this server: upgrade it; serving originals directly until then",
				"base", b.base.String(), "lacks", why.lacks)
		case b.link == linkUnknown:
			b.log.Info("streaming engine not answering yet; serving originals directly until it answers",
				"base", b.base.String(), "err", err)
		default:
			b.log.Warn("streaming engine unreachable; serving originals directly until it answers",
				"base", b.base.String(), "err", err)
		}
		b.why = why
		if b.link == linkDown {
			// Only the reason changed; the hooks were told at the crossing.
			return false
		}
		b.link = linkDown
		hooks := slices.Clone(b.onDown)
		b.told = append(b.told, func() {
			for _, fn := range hooks {
				fn()
			}
		})
		return false
	}
	b.caps.Store(caps)
	b.why = downWhy{}
	if b.link == linkUp {
		return false
	}
	b.link = linkUp
	b.log.Info("waxflow bridge up",
		"base", b.base.String(),
		"outputs", len(caps.Outputs),
		"cutFormats", caps.Delivery.CutFormats,
		"hls", caps.Delivery.HLS,
		"rootsReload", b.RootsReloadSupported())
	st := statusOf(caps)
	hooks := slices.Clone(b.onUp)
	b.told = append(b.told, func() {
		for _, fn := range hooks {
			fn(ctx, st)
		}
	})
	return true
}

// runHooks tells the hooks of the crossings queued so far, in the order
// they were made, one crossing at a time and outside linkMu, so a request
// finding the engine gone meanwhile waits on none of them. Each crossing
// leaves the queue as it is told: a hook that panics takes only its own.
func (b *Bridge) runHooks() {
	b.hookMu.Lock()
	defer b.hookMu.Unlock()
	for {
		b.linkMu.Lock()
		if len(b.told) == 0 {
			b.linkMu.Unlock()
			return
		}
		tell := b.told[0]
		b.told[0] = nil
		b.told = b.told[1:]
		b.linkMu.Unlock()
		tell()
	}
}

// lost is a request finding the engine gone: an outage from this moment,
// said and crossed like one a probe finds, so the next answer is a return
// that sets right whatever the window put wrong. Run asks again at once
// rather than at its next probe, and that probe tells the hooks.
func (b *Bridge) lost(err error) {
	b.settle(context.Background(), nil, err)
	b.probeSoon()
}

// probeSoon asks Run to probe now rather than at its next interval.
func (b *Bridge) probeSoon() {
	select {
	case b.kick <- struct{}{}:
	default:
	}
}

// unreachable is a request that failed to reach the engine. A stall is
// that request's own trouble until the probe it asks for says otherwise:
// an engine answering slowly for one source (a disk spinning up, a
// network mount) is not gone, and crossing it down and back would mark
// every account and offer every refused root again. Anything else that
// left the request without an answer is lost. A listener who left is
// neither.
func (b *Bridge) unreachable(ctx context.Context, err error) {
	switch {
	case ctx.Err() != nil:
	case errors.Is(err, errEngineStalled):
		b.probeSoon()
	default:
		b.lost(err)
	}
}

// engineGone reports whether err is one of the bridge's own calls to the
// engine getting no answer at all (a connection refused, dropped or
// reset, or none within the client's own bound on a call) while its
// asker still waited. A call cut off without an answer finds the engine
// gone, as a stream does; one that ran out of time asks for a probe, as a
// stalled stream does. An answer the engine gave, a refusal included, is
// neither.
func (b *Bridge) engineGone(ctx context.Context, err error) bool {
	var transport *url.Error
	if err == nil || ctx.Err() != nil || !errors.As(err, &transport) {
		return false
	}
	if transport.Timeout() {
		b.probeSoon()
	} else {
		b.lost(err)
	}
	return true
}

// RefuseEngineDown answers a request only the engine can serve while it
// is away: the umbrella code with the param a client keys on, and when
// to ask again.
func RefuseEngineDown(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Retry-After", strconv.Itoa(EngineRetrySeconds))
	w.WriteHeader(http.StatusServiceUnavailable)
	fmt.Fprintf(w, `{"code":"feature-unavailable","message":%q,"params":{"feature":%q}}`+"\n",
		ErrEngineDown.Error(), FeatureStreamingEngine)
}

// sortRoots orders roots longest path first, so a root nested inside
// another resolves to the most specific name.
func sortRoots(roots []Root) {
	sort.SliceStable(roots, func(i, j int) bool { return len(roots[i].Path) > len(roots[j].Path) })
}

// Caps is the engine's last answer, nil while it is not answering and
// on a server without one.
func (b *Bridge) Caps() *client.Caps {
	if b == nil {
		return nil
	}
	return b.caps.Load()
}

// Status is what the engine offers this server right now.
type Status struct {
	// Connected says the engine is answering, as far as the bridge knows:
	// it answered its last ask, and no request has found it gone since.
	Connected bool
	// Timelines, VoiceBoost and FileTools are its gapless renderings,
	// spoken-word dynamics and jobs surface, false while it is away;
	// TimelineWindows is whether a timeline takes a window of a file as
	// a member.
	Timelines       bool
	TimelineWindows bool
	VoiceBoost      bool
	FileTools       bool
}

// Status reads one snapshot of the engine; the zero Status while it is
// away and on a server without one.
func (b *Bridge) Status() Status { return statusOf(b.Caps()) }

func statusOf(caps *client.Caps) Status {
	if caps == nil {
		return Status{}
	}
	return Status{
		Connected:       true,
		Timelines:       timelinesSupported(caps),
		TimelineWindows: timelinesSupported(caps) && caps.Delivery.TimelineMemberWindows,
		VoiceBoost:      slices.Contains(caps.DSP.Dynamics, "voice"),
		FileTools:       caps.Delivery.Jobs,
	}
}

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
	if !b.Up() {
		return PlayInfo{}, ErrEngineDown
	}
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
//
// While the engine is away it mints nothing and answers ErrEngineDown,
// for the caller to serve the original directly.
func (b *Bridge) PlayInfoForSource(ctx context.Context, user, apiItemPID string, src Source, opts PlayOptions) (PlayInfo, error) {
	caps := b.Caps()
	if caps == nil {
		return PlayInfo{}, ErrEngineDown
	}
	gainDB, boost := VoiceBoostParams(src, caps, opts.VoiceBoost)
	shape := ShapeFor(src, caps, boost)
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
		force, advertise = DeviceFormat(src, shape, caps, opts.DeviceFormats, opts.ForceFormat, capped)
	}
	mime, forced := forceFormats[force]
	// The fetch side gates on the live caps too, so a format this daemon
	// cannot produce must not reach the URL either: the two decisions
	// have to agree or the mime advertised here would describe bytes the
	// stream never serves.
	forced = forced && hasOutput(caps, force)
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
		capped, applied := CappedShape(src, caps, shape, capKbps)
		if applied {
			// The caller's own target wins over the ladder's when it is
			// one the closed hint set carries and this engine produces:
			// the fetch side gates on the same two, so anything else
			// would advertise a type the stream never serves.
			if f := opts.CapFormat; lossyBitrateFormats[f] && hasOutput(caps, f) {
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
		if format := hlsFormatFor(shape, caps); format != "" {
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
		shape, encode, br = originalCutShape(src, caps), true, 0
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

// StreamShape is the canonical form of the stream parameters a stream
// token binds, read off a URL that carries them: what the download route
// checks a stream redirected to it against.
func StreamShape(q url.Values) string { return streamShape(q) }

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
	b.applyRoots(nil, []string{name})
}

// SyncRoot teaches the bridge a library root created at runtime and
// brings the sidecar to the same set (ChangeRoots). A nil error means
// streaming from the new root works now, or, while the engine is away or
// a reload could not reach it, that the root is held until the engine
// answers and the root is offered again; any error names what an
// administrator still has to do.
//
// Either both sides end up knowing the root or neither does. A refused
// reload restores the config file and drops the root back out of the
// bridge, for two reasons: the sidecar opens every root at startup, so
// a path it refused would turn its next restart into a boot failure,
// and a rejected root left in the set would be re-sent with the next
// library and take that one down with it. The lock ChangeRoots holds
// spans the add as well as the reload for the same reason: two library
// creates whose reloads interleaved would each carry the other's root,
// and one bad path would roll the other's good one back out.
func (b *Bridge) SyncRoot(ctx context.Context, name, path string) error {
	return b.ChangeRoots(ctx, []Root{{Name: name, Path: path}}, nil)
}

// RemoveRoot takes a removed library's root off the bridge and the
// sidecar (ChangeRoots): the bridge stops mapping it whatever follows, so
// nothing mints a stream under it again, and the sidecar's config file
// lets it go, which the sidecar takes at its next reload or start. An
// error says what still names the root: a refused reload, or a config
// file that could not be written.
func (b *Bridge) RemoveRoot(ctx context.Context, name string) error {
	return b.ChangeRoots(ctx, nil, []string{name})
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
	caps := b.Caps()
	return b.configPath != "" && caps != nil && caps.Delivery.RootsReload
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
	caps := b.Caps()
	if caps == nil {
		return fmt.Errorf("flow: %w", ErrEngineDown)
	}
	if !caps.Delivery.RootsReload {
		return fmt.Errorf("flow: the sidecar at %s does not serve root reloads", b.base)
	}
	// One reload at a time. Two concurrent library creates would
	// otherwise interleave their rewrites, and a rollback from one could
	// undo the other's accepted set. Library creates are rare enough that
	// serializing them costs nothing.
	b.reloadMu.Lock()
	defer b.reloadMu.Unlock()
	return b.reloadRootsLocked(ctx, nil)
}

// reloadRootsLocked is ReloadRoots' body, called with reloadMu held so
// ChangeRoots can hold the lock across its own change of the table too.
// drop names roots the change let go, which the file loses as well.
func (b *Bridge) reloadRootsLocked(ctx context.Context, drop []string) error {
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
	if b.reloadTimeout > 0 {
		var cancel context.CancelFunc
		ctx, cancel = context.WithTimeout(ctx, b.reloadTimeout)
		defer cancel()
	}
	prev, perm, err := readRootsConfig(b.configPath)
	if err != nil {
		return err
	}
	if err := writeRootSet(b.configPath, prev, perm, b.snapshotRoots(), drop); err != nil {
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
// re-resolve the item, and reverse-proxy the sidecar's answer. While the
// engine is away, an original goes to the download route instead
// (serveWithoutEngine).
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
		// A joined book is an encode of its parts, whatever they hold.
		if !b.Up() {
			RefuseEngineDown(w)
			return
		}
		b.serveJoined(w, r, claims.User, pid, q)
		return
	}
	user := claims.User
	src, err := b.resolver.StreamSource(r.Context(), pid, q.Get("f"))
	if err != nil {
		writeJSONError(w, http.StatusNotFound, "not-found", "no streamable item with pid "+pid)
		return
	}
	caps := b.Caps()
	if caps == nil {
		b.serveWithoutEngine(w, r, q, src)
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
	gainDB, boost := VoiceBoostParams(src, caps, q.Get("vb") == "1")
	shape := ShapeFor(src, caps, boost)
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
		if known && hasOutput(caps, f) && !copyOfSource {
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
	params.Set("id", sourceID(src))
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

// sourceID is a file's validator: the id the engine pins a stream to,
// and the download route's ETag for the same bytes.
func sourceID(src Source) string { return fmt.Sprintf("%d-%d", src.Size, src.MTimeNS) }

// OriginalBytes reports whether the stream parameters q name the
// source's own bytes, which serve with no engine: no voice boost, no
// encode or bitrate the mint chose, no joined book, and no format but a
// copy of the source. A window of a larger file is the engine's to cut,
// which a caller weighs apart (src.Virtual).
func OriginalBytes(q url.Values, src Source) bool {
	if q.Get("vb") != "" || q.Get("enc") != "" || q.Get("br") != "" || q.Get("join") != "" {
		return false
	}
	f := q.Get("fmt")
	return f == "" || SameAsSource(src, f)
}

// serveWithoutEngine answers a stream fetch while the engine is away. A
// URL minted for the original bytes goes to the download route under
// its own token and the file's validator, keeping every parameter its
// token binds, so a stream minted before the outage plays through it.
// A stream only the engine makes (a window, voice boost, a format, a
// bitrate) is refused in words a client keys on.
func (b *Bridge) serveWithoutEngine(w http.ResponseWriter, r *http.Request, q url.Values, src Source) {
	if src.Virtual || !OriginalBytes(q, src) {
		RefuseEngineDown(w)
		return
	}
	if _, _, err := streamCut(q.Get("t"), Shape{Seekable: true}, src.DurationMS); err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid-request", err.Error())
		return
	}
	loc := url.Values{}
	for _, k := range []string{"pid", "mt", "f", "fmt"} {
		if v := q.Get(k); v != "" {
			loc.Set(k, v)
		}
	}
	loc.Set("id", sourceID(src))
	http.Redirect(w, r, "/media/download?"+loc.Encode(), http.StatusFound)
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
	// The API serves the original itself while the engine is away; this
	// is one that went away after that was asked.
	caps := b.Caps()
	if caps == nil {
		RefuseEngineDown(w)
		return
	}
	shape := ShapeFor(src, caps, false)
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
	params.Set("id", sourceID(src))
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
	caps := b.Caps()
	if caps == nil {
		RefuseEngineDown(w)
		return
	}
	if !hasOutput(caps, format) {
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
	params.Set("id", sourceID(src))
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
		b.log.Error(keyRefusedLog, "status", resp.StatusCode)
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

// keyRefusedLog is what the log says when the engine refuses this
// server's API key, wherever that is found: no wait cures it, only an
// administrator can.
const keyRefusedLog = "the streaming engine refused this server's API key: --flow-api-key (WAXDECK_FLOW_API_KEY) must be one the engine accepts (WAXFLOW_API_KEYS)"

// credentialsRefused reports whether err is the engine refusing this
// server's credentials on an ask of its own (a 401 or 403, which the
// client decodes to the unauthorized codes).
func credentialsRefused(err error) bool {
	switch waxerr.CodeOf(err) {
	case waxerr.CodeUnauthorized, waxerr.CodeSignatureInvalid, waxerr.CodeSignatureExpired:
		return true
	}
	return false
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
