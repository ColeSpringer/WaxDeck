// Package service is the application core: everything between the API
// surface and the WaxBin facade. Handlers call services; services call
// the facade; nothing above this package imports waxbin.
package service

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"os/exec"
	"path/filepath"
	"sync"
	"sync/atomic"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/config"
	"github.com/colespringer/waxbin/enrich"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/pidpath"
	"github.com/colespringer/waxbin/source"

	"github.com/colespringer/waxdeck/server/internal/auth"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/match"
	"github.com/colespringer/waxdeck/server/internal/scrobble"
	"github.com/colespringer/waxdeck/server/internal/similarity"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// Root is one library root: the path WaxBin scans and the WaxFlow root
// name the same directory is mounted under for streaming.
type Root struct {
	Name string
	Path string
	// Managed opts the root into catalog-managed file placement: the
	// import planner will move files into it (uploads, merges) and the
	// organizer may rename within it. The conservative default is
	// in-place: the catalog never moves files it did not place.
	Managed bool
}

// Config configures the library service.
type Config struct {
	// DataDir holds waxbin.db (and its lockfile and IPC socket).
	DataDir string
	// Roots are the library roots, indexed in place (never moved).
	Roots []Root
	// ScanOnStart launches a scan as soon as the service is up.
	ScanOnStart bool
	// Sealer encrypts recoverable secrets (app passwords) at rest.
	Sealer *auth.Sealer
	// SecretCipher seals catalog-held secrets (private-feed passwords)
	// at rest; the catalog binds each secret's key as AAD. Removing an
	// adopted cipher bricks sealed rows, so this is wired once and kept.
	SecretCipher *auth.AADSealer
	// PodcastDir is the episode download directory: its own catalog
	// library, never inside a user root (the catalog refuses overlap),
	// and mounted for the streaming sidecar under PodcastRootName.
	PodcastDir string
	// PodcastRootName is the streaming root name PodcastDir is served
	// under; the bridge maps episode paths through it.
	PodcastRootName string
	// AllowPrivateFeedHosts disables the private-address guard on feed
	// and enclosure fetches, for feeds hosted on the caller's own LAN.
	AllowPrivateFeedHosts bool
	// DefaultRetentionKeep applies to subscribers who leave retention
	// unset: keep the newest N downloaded episode files, 0 keeps all.
	DefaultRetentionKeep int64
	// RetentionInUseWindow is how recently a subscriber's position must
	// have moved for an episode to count as in use (deferring its
	// show's sweep). Zero means the default of two minutes; a negative
	// value disables the guard (tests).
	RetentionInUseWindow time.Duration
	// SourceProviders are injected acquisition providers (the YouTube
	// bridge); the catalog dispatches shows to them by source type.
	SourceProviders []source.Provider
	// AllowPrivateRadioHosts disables the private-address guard on
	// radio stream URLs, for households running their own LAN icecast.
	AllowPrivateRadioHosts bool
	// AllowPrivateScrobbleHosts disables the private-address guard on
	// caller-supplied ListenBrainz API bases, for self-hosted LAN
	// instances (Maloja and friends).
	AllowPrivateScrobbleHosts bool
	// AllowPrivateNotifyHosts disables the private-address guard on
	// user-pointed notification destinations (ntfy, Gotify, webhooks,
	// Apprise), for households running them on the LAN.
	AllowPrivateNotifyHosts bool
	// RadioDirectoryBase is the radio-browser directory API base;
	// empty selects the public instance.
	RadioDirectoryBase string
	// LastfmAPIKey and LastfmSecret are the server's Last.fm API
	// credentials; empty leaves the Last.fm connection unavailable.
	LastfmAPIKey string
	LastfmSecret string
	// StagingDir holds upload sessions and their staged files before
	// they enter the library; empty defaults to DataDir/staging.
	StagingDir string
	// UploadFormats are the accepted upload extensions (lowercase, no
	// dot); empty selects the default audio set.
	UploadFormats []string
	// UploadRetention is how long an unfinished or undecided upload
	// keeps its staged bytes; zero means seven days.
	UploadRetention time.Duration
	// MatchSource supplies release candidates to the matching engine;
	// nil disables matching (entries decide manually with no
	// candidates).
	MatchSource match.CandidateSource
	// MatchConfig tunes the engine; the zero value uses the calibrated
	// defaults.
	MatchConfig match.Config
	// EnrichmentProviders are the server's own providers, registered
	// ahead of the catalog's built-ins and reused for per-item
	// enrichment.
	EnrichmentProviders []enrich.Provider
	// FpcalcPath locates the fingerprint binary; empty looks it up on
	// PATH, and a missing binary just disables fingerprint evidence.
	FpcalcPath string
	// WorkerLocalPaths adds library-relative source paths to similarity
	// work items, for same-host workers that mount the library read-only
	// and decode locally instead of pulling audio over HTTP. Only
	// meaningful for single-root libraries; multi-root setups use the
	// HTTP pull regardless.
	WorkerLocalPaths bool
	// ISRCResolver upgrades playlist-import ISRCs to recording MBIDs;
	// nil disables the upgrade (imports still match descriptively).
	ISRCResolver ISRCResolver
	// SonicAnalysisDefault is the embedded analyzer's boot default
	// (WAXDECK_SONIC_ANALYSIS); the runtime admin setting overrides it
	// once saved.
	SonicAnalysisDefault bool
	// WorkerAPIConfigured reports whether external worker tokens are
	// set; with the runtime analysis toggle it gates the sweep and the
	// similarity status.
	WorkerAPIConfigured bool
	Logger              *slog.Logger
}

// Library is the catalog service over an embedded WaxBin library. It
// owns the write lock for the process lifetime and hosts the IPC
// socket the waxbin CLI proxies through.
type Library struct {
	lib   *waxbin.Library
	paths *pidpath.Cache
	db    *wdb.DB
	roots []Root
	log   *slog.Logger
	// libDirs caches path-to-library attribution for visibility checks.
	libDirs libraryDirs
	// procCtx outlives any one request: async catalog jobs launch on it
	// so a scan survives the 202 that reported it started.
	procCtx context.Context
	// feed is the catalog change stream's identity and position;
	// serverGen names the event_log stream's generation.
	feed      syncFeed
	serverGen string
	// catalogWake and userWake are the lossy wakeup hints the event hub
	// fans out as invalidation frames.
	catalogWake chan struct{}
	userWake    chan string
	// sealer and appSecrets back the app-password credential store.
	sealer     *auth.Sealer
	appSecrets appSecretCache
	// trackFacts caches the compatibility surface's track sweep.
	trackFacts trackFactsCache
	// podcastDir and podcastRootName locate the episode download
	// library; defaultRetentionKeep is the unset-subscriber policy;
	// retentionInUseWindow gates the sweep's in-use deferral.
	podcastDir           string
	podcastRootName      string
	defaultRetentionKeep int64
	retentionInUseWindow time.Duration
	// flowJobs is the streaming sidecar's analysis surface, wired after
	// construction (the bridge needs this service as its resolver).
	flowJobs FlowJobs
	// transcriptHTTP is the guarded client for transcript pointers,
	// built on first use; allowPrivateFeedHosts relaxes its SSRF guard.
	transcriptHTTP        *http.Client
	transcriptHTTPOnce    sync.Once
	allowPrivateFeedHosts bool
	// radioHTTP is the guarded client for radio streams and the
	// station directory, built on first use; allowPrivateRadioHosts
	// relaxes its SSRF guard. It carries no overall timeout (radio
	// streams are unbounded); bounded calls pass a request context.
	radioHTTP              *http.Client
	radioHTTPOnce          sync.Once
	allowPrivateRadioHosts bool
	radioDirectoryBase     string
	// radioTitles holds each station's last proxy-observed in-stream
	// title; process-local on purpose (a title only exists while this
	// process is proxying the stream).
	radioTitles   map[string]radioTitle
	radioTitlesMu sync.Mutex
	// batchFinalizeMu serializes upload-batch finalization (the flip,
	// entry opening, and member linking as one unit): two concurrent
	// finalizes of one batch would otherwise both gather the same
	// still-unlinked members and open duplicate review entries.
	// Process-wide is fine — finalizes are rare and database-only.
	batchFinalizeMu sync.Mutex
	// lastfmPtr holds the swappable outbound Last.fm client (admin
	// credential changes rebuild it at runtime); envLastfmKey/Secret
	// keep the environment pair as the fallback when no runtime pair is
	// stored. listenbrainz needs no server credentials.
	lastfmPtr       atomic.Value
	envLastfmKey    string
	envLastfmSecret string

	listenbrainz              *scrobble.ListenBrainz
	allowPrivateScrobbleHosts bool
	// notifyGuardedHTTP is the dial-guarded client for user-pointed
	// notification destinations, built on first use;
	// allowPrivateNotifyHosts relaxes its SSRF guard.
	notifyGuardedHTTP       *http.Client
	notifyGuardedOnce       sync.Once
	allowPrivateNotifyHosts bool
	// engine is the release matching engine; nil when no candidate
	// source is configured (review entries then hold no candidates).
	engine *match.Engine
	// stagingDir holds upload staging; uploadFormats is the accepted
	// extension set; uploadRetention bounds staged-byte lifetime.
	stagingDir      string
	uploadFormats   map[string]bool
	uploadRetention time.Duration
	// fpcalcPath is the fingerprint binary, empty when absent (matching
	// then runs on tag and search evidence only).
	fpcalcPath string
	// enrichProviders are the server-registered providers, kept for the
	// per-item enrichment path and the status surface.
	enrichProviders []enrich.Provider
	// matchWake nudges the identify worker; lossy, ticker-backstopped.
	matchWake chan struct{}
	// toggles is the hot-path settings cache (read-only flags, transcode
	// limits), swapped whole on every settings write.
	toggles atomic.Value
	// gate is the single transcode session gate, built on first use.
	gate     *transcodeGate
	gateOnce sync.Once
	// sourceProviders are the injected acquisition providers, kept for
	// the acquire-from-URL surface (the catalog holds its own copy for
	// show dispatch).
	sourceProviders []source.Provider
	// sim is the in-memory sonic-similarity engine, warmed lazily from
	// waxdeck.db on first use (it only holds data when a worker has
	// posted embeddings). simSweepVersion remembers the catalog data
	// version the last analysis sweep covered, so an unchanged catalog
	// never re-walks. workerLocalPaths mirrors Config.WorkerLocalPaths.
	sim              *similarity.Engine
	simWarm          sync.Once
	simWarmErr       error
	simSweepVersion  atomic.Int64
	workerLocalPaths bool
	// isrcResolver mirrors Config.ISRCResolver.
	isrcResolver ISRCResolver
	// sonicAnalysisDefault and workerAPIConfigured mirror their Config
	// fields.
	sonicAnalysisDefault bool
	workerAPIConfigured  bool
}

// SocketFileName is the IPC socket beside the catalog DB. It is a local
// admin plane: 0600, same user, full catalog access.
const SocketFileName = "waxbin.sock"

// Open opens the catalog read-write, wires the pidpath cache, starts
// the IPC server and (optionally) a startup scan on the supervised
// group, and returns the service.
func Open(ctx context.Context, cfg Config, store *wdb.DB, group *supervise.Group) (*Library, error) {
	log := cfg.Logger
	if log == nil {
		log = slog.New(slog.DiscardHandler)
	}
	roots := make([]config.Root, 0, len(cfg.Roots))
	for _, r := range cfg.Roots {
		mode := model.ModeInPlace
		if r.Managed {
			mode = model.ModeManaged
		}
		roots = append(roots, config.Root{Path: r.Path, Mode: mode})
	}
	socket := filepath.Join(cfg.DataDir, SocketFileName)
	opts := waxbin.Options{
		DBPath:              filepath.Join(cfg.DataDir, "waxbin.db"),
		Roots:               roots,
		Logger:              log,
		IPCSocket:           socket,
		SourceProviders:     cfg.SourceProviders,
		EnrichmentProviders: cfg.EnrichmentProviders,
	}
	if cfg.SecretCipher != nil {
		opts.SecretCipher = cfg.SecretCipher
		opts.SecretKeyID = "1"
	}
	if cfg.PodcastDir != "" {
		opts.Podcasts = config.PodcastConfig{
			Dir:             cfg.PodcastDir,
			BlockPrivateIPs: !cfg.AllowPrivateFeedHosts,
		}
	}
	lib, err := waxbin.Open(ctx, opts)
	if err != nil {
		return nil, fmt.Errorf("service: opening catalog: %w", err)
	}

	paths, err := pidpath.New(ctx, lib, pidpath.Options{Logger: log})
	if err != nil {
		lib.Close()
		return nil, fmt.Errorf("service: pid path cache: %w", err)
	}

	l := &Library{
		lib: lib, paths: paths, db: store, roots: cfg.Roots, log: log, procCtx: ctx,
		catalogWake:            make(chan struct{}, 1),
		userWake:               make(chan string, 64),
		matchWake:              make(chan struct{}, 1),
		sealer:                 cfg.Sealer,
		podcastDir:             cfg.PodcastDir,
		podcastRootName:        cfg.PodcastRootName,
		defaultRetentionKeep:   cfg.DefaultRetentionKeep,
		retentionInUseWindow:   cfg.RetentionInUseWindow,
		allowPrivateFeedHosts:  cfg.AllowPrivateFeedHosts,
		allowPrivateRadioHosts: cfg.AllowPrivateRadioHosts,
		radioDirectoryBase:     cfg.RadioDirectoryBase,
		radioTitles:            map[string]radioTitle{},
		listenbrainz:           scrobble.NewListenBrainz(),
		sim:                    similarity.New(),
		workerLocalPaths:       cfg.WorkerLocalPaths,
		isrcResolver:           cfg.ISRCResolver,
		sonicAnalysisDefault:   cfg.SonicAnalysisDefault,
		workerAPIConfigured:    cfg.WorkerAPIConfigured,
	}
	// The ListenBrainz API base is caller-supplied, so its deliveries
	// ride a dial-guarded client like every other user-pointed fetch;
	// the flag opts LAN instances back in. The connection's write-time
	// check gives the friendly error, this guard is the boundary.
	l.allowPrivateScrobbleHosts = cfg.AllowPrivateScrobbleHosts
	l.listenbrainz.HTTP = scrobbleHTTPClient(cfg.AllowPrivateScrobbleHosts)
	l.allowPrivateNotifyHosts = cfg.AllowPrivateNotifyHosts
	l.dropLegacyNotifySetting(ctx)
	l.loadRuntimeToggles(ctx)
	l.envLastfmKey, l.envLastfmSecret = cfg.LastfmAPIKey, cfg.LastfmSecret
	l.loadLastfmClient(ctx)
	if l.retentionInUseWindow == 0 {
		l.retentionInUseWindow = 2 * time.Minute
	}
	if cfg.MatchSource != nil {
		l.engine = match.NewEngine(cfg.MatchSource, cfg.MatchConfig)
	}
	l.stagingDir = cfg.StagingDir
	if l.stagingDir == "" {
		l.stagingDir = filepath.Join(cfg.DataDir, "staging")
	}
	l.uploadFormats = uploadFormatSet(cfg.UploadFormats)
	l.uploadRetention = cfg.UploadRetention
	if l.uploadRetention == 0 {
		l.uploadRetention = 7 * 24 * time.Hour
	}
	l.fpcalcPath = cfg.FpcalcPath
	if l.fpcalcPath == "" {
		if p, err := exec.LookPath("fpcalc"); err == nil {
			l.fpcalcPath = p
		}
	}
	l.enrichProviders = cfg.EnrichmentProviders
	l.sourceProviders = cfg.SourceProviders
	if err := l.initSync(ctx); err != nil {
		paths.Close()
		lib.Close()
		return nil, fmt.Errorf("service: sync state: %w", err)
	}

	// Cipher adoption: re-seal any plaintext catalog secrets once. Old
	// rows seal lazily on write anyway; the one-shot closes the gap for
	// rows never rewritten. Never fatal (the catalog stays usable).
	if cfg.SecretCipher != nil {
		if n, err := lib.ReSealSecrets(ctx); err != nil {
			log.Warn("re-sealing catalog secrets", "err", err)
		} else if n > 0 {
			log.Info("sealed catalog secrets", "count", n)
		}
	}

	// The CLI-through-server proxy: host side is one call, alive for the
	// process lifetime. Serve returns nil on ctx cancel.
	group.Go(ctx, "waxbin-serve", func(ctx context.Context) error {
		return l.lib.Serve(ctx, socket)
	})

	// The change-feed consumer: subscribes, primes, follows, and feeds
	// the event hub's invalidation fan-out.
	group.Go(ctx, "catalog-feed", l.runCatalogFeed)

	if cfg.ScanOnStart {
		group.GoOnce(ctx, "startup-scan", func(ctx context.Context) error {
			pid, err := l.lib.StartScan(ctx, waxbin.ScanRequest{})
			if err != nil {
				return err
			}
			log.Info("startup scan launched", "job", string(pid))
			return nil
		})
	}
	return l, nil
}

// Close releases the catalog (flushing playback state) and the path
// cache.
func (l *Library) Close() error {
	if err := l.paths.Close(); err != nil {
		l.log.Warn("closing pid path cache", "err", err)
	}
	return l.lib.Close()
}

// Rescan starts an asynchronous scan of every root and returns the
// job. The scan runs on the process context, not the request's: it
// must survive the response that reported it started.
func (l *Library) Rescan(ctx context.Context) (Job, error) {
	pid, err := l.lib.StartScan(l.procCtx, waxbin.ScanRequest{})
	if err != nil {
		return Job{}, classify(err)
	}
	return l.JobStatus(ctx, apiPID(PrefixJob, pid))
}

// JobStatus reports one catalog job.
func (l *Library) JobStatus(ctx context.Context, apiJobPID string) (Job, error) {
	prefix, pid, ok := parseAPIPID(apiJobPID)
	if !ok || prefix != PrefixJob {
		return Job{}, errNotFound("no job with pid " + apiJobPID)
	}
	job, err := l.lib.Job(ctx, pid)
	if err != nil {
		return Job{}, classify(err)
	}
	return Job{
		PID:      apiPID(PrefixJob, job.PID),
		Kind:     job.Kind,
		State:    string(job.State),
		Progress: job.Progress,
		Message:  job.Message,
		Error:    job.Error,
	}, nil
}

// Jobs lists recent catalog jobs, newest first. Administrators only.
func (l *Library) Jobs(ctx context.Context, uc *UserCtx, limit int) ([]Job, error) {
	if !uc.Admin {
		return nil, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	jobs, err := l.lib.Jobs(ctx, limit)
	if err != nil {
		return nil, classify(err)
	}
	out := make([]Job, 0, len(jobs))
	for _, job := range jobs {
		out = append(out, Job{
			PID:      apiPID(PrefixJob, job.PID),
			Kind:     job.Kind,
			State:    string(job.State),
			Progress: job.Progress,
			Message:  job.Message,
			Error:    job.Error,
		})
	}
	return out, nil
}

// summary converts an item view to the list-row DTO.
func summary(it *model.ItemView) ItemSummary {
	return ItemSummary{
		PID:        itemAPIPID(it),
		MediaType:  mediaTypeForKind(it.Kind),
		Title:      it.Title,
		Artist:     it.Artist,
		Album:      it.Album,
		DurationMS: it.DurationMS,
		Virtual:    it.Virtual,
	}
}

// getItem fetches an item and enforces that the API prefix matches its
// kind, so a track PID presented as a book 404s instead of leaking.
func (l *Library) getItem(ctx context.Context, apiItemPID string) (*model.ItemView, error) {
	prefix, pid, ok := parseAPIPID(apiItemPID)
	if !ok || !itemPrefix(prefix) {
		return nil, errNotFound("no item with pid " + apiItemPID)
	}
	it, err := l.lib.Get(ctx, pid)
	if err != nil {
		return nil, classify(err)
	}
	if prefixForKind(it.Kind) != prefix {
		return nil, errNotFound("no item with pid " + apiItemPID)
	}
	return it, nil
}
