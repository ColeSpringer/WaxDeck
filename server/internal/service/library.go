// Package service is the application core: everything between the API
// surface and the WaxBin facade. Handlers call services; services call
// the facade, which belongs to this package alone (cmd/importlint holds
// the whole waxbin import rule).
package service

import (
	"cmp"
	"context"
	"crypto/rand"
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/config"
	"github.com/colespringer/waxbin/enrich"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/pidpath"
	"github.com/colespringer/waxbin/source"
	"github.com/colespringer/waxbin/waxerr"

	"github.com/colespringer/waxdeck/server/internal/auth"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/diskspace"
	"github.com/colespringer/waxdeck/server/internal/match"
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
	// FolderFallback, Media, PID, Profile and ReadOnly are the catalog's,
	// filled when the table is rebuilt from it. On a configured root Media
	// is instead what the configuration declares it holds, empty for
	// "whatever it holds".
	FolderFallback bool
	Media          string
	PID            string
	Profile        string
	ReadOnly       bool
	// Unwritable is a managed root refusing the server's write probe.
	Unwritable bool
}

// Config configures the library service.
type Config struct {
	// DataDir holds waxbin.db and its lockfile, and the IPC socket unless
	// its path would be too long for one.
	DataDir string
	// PathPollInterval is the pid path cache's background poll; zero is
	// its default, negative none (a test driving its own hand-offs).
	PathPollInterval time.Duration
	// Roots are the library roots, indexed in place (never moved).
	Roots []Root
	// ScanOnStart launches a scan as soon as the service is up.
	ScanOnStart bool
	// WatchLibraries arms a live filesystem watcher on the roots, so
	// files placed there by hand are cataloged without waiting for a
	// manual rescan or the scan schedule.
	WatchLibraries bool
	// WatchRecheck is how often the watcher looks again for a root folder
	// that was not there; zero is a minute.
	WatchRecheck time.Duration
	// WatchSettle is how long a directory must stay event-quiet before
	// its scoped rescan fires; zero means the ten-second default. Tests
	// set it short.
	WatchSettle time.Duration
	// RootProbeEvery is how often the managed roots are probed for writes
	// again; zero is rootProbeEvery. Tests set it short.
	RootProbeEvery time.Duration
	// ResetStaleCatalog moves a catalog built on a different schema
	// baseline aside at startup instead of refusing to start. See
	// staleBaseline for what it does and does not distinguish.
	ResetStaleCatalog bool
	// Sealer encrypts recoverable secrets at rest: app passwords,
	// notification targets, scrobbling credentials and migration secrets.
	Sealer *auth.Sealer
	// SecretCipher seals catalog-held secrets (private-feed passwords)
	// at rest; the catalog binds each secret's key as AAD. Removing an
	// adopted cipher bricks sealed rows, so this is wired once and kept.
	SecretCipher *auth.AADSealer
	// CursorSealer seals a listing cursor that stands on a row the caller
	// may not see, so the position travels and the row's fields do not.
	// Nil seals under a key minted for the process, whose cursors stop
	// opening at a restart.
	CursorSealer *auth.Sealer
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
	// RetentionInUseWindow is how recently anyone's position must have
	// moved for an episode to count as in use (deferring its show's
	// sweep). Zero means the default of two minutes; a negative value
	// disables the guard (tests).
	RetentionInUseWindow time.Duration
	// SourceProviders are injected acquisition providers (the YouTube
	// bridge); the catalog dispatches shows to them by source type.
	SourceProviders []source.Provider
	// AllowPrivateRadioHosts disables the private-address guard on
	// radio stream URLs, for households running their own LAN icecast.
	AllowPrivateRadioHosts bool
	// RadioTitleFreshFor is how long a station's observed title outlives
	// the last metadata block of any kind. Zero means the default of two
	// minutes; tests set it short to cross the bound without waiting.
	RadioTitleFreshFor time.Duration
	// RadioListenMinListen is how long a tune-in must run before it is
	// recorded as listening. Zero means the default of
	// [RadioListenMinListen]; tests set it short to cross the bound
	// without waiting half a minute per relay.
	RadioListenMinListen time.Duration
	// AllowPrivateScrobbleHosts disables the private-address guard on
	// caller-supplied ListenBrainz API bases, for self-hosted LAN
	// instances (Maloja and friends).
	AllowPrivateScrobbleHosts bool
	// AllowPrivateNotifyHosts disables the private-address guard on
	// user-pointed notification destinations (ntfy, Gotify, webhooks,
	// Apprise), for households running them on the LAN.
	AllowPrivateNotifyHosts bool
	// PublicBase is the externally reachable base URL of the web app.
	// Notification deliveries carry a link to what they are about only
	// when it is set: without it the server does not know a URL anybody
	// outside its own network could follow.
	PublicBase string
	// Version is the build's version, which UserAgent names.
	Version string
	// RadioDirectoryBase is the radio-browser directory API base;
	// empty selects the public instance. Set, it is the only host the
	// directory search talks to.
	RadioDirectoryBase string
	// RadioDirectoryMirrors overrides radio-browser mirror discovery
	// with a fixed list to rotate through. Empty (the normal case)
	// discovers mirrors over SRV. It exists so rotation can be driven
	// against local servers in tests; a deployment that wants one
	// instance sets RadioDirectoryBase instead.
	RadioDirectoryMirrors []string
	// PodcastDirectoryBase is the podcast name-search API base; empty
	// selects the public iTunes search endpoint.
	PodcastDirectoryBase string
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
	// EnrichmentContact is the MusicBrainz contact the enrichment pass
	// identifies itself with. Empty leaves that pass disabled: MusicBrainz
	// requires an identifying agent before anything is sent.
	EnrichmentContact string
	// EnrichmentMatchReleases resolves which pressing the library holds
	// from a barcode or catalog number. On by default; open-time, because
	// the catalog reads it when it opens.
	EnrichmentMatchReleases bool
	// EnrichmentRetryMissesDays is how many days a miss stands before a
	// pass asks again; 0 never does, nil takes the catalog's default.
	EnrichmentRetryMissesDays *int
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
	// RadioArtResolver looks a station's announced title up against
	// MusicBrainz and the Cover Art Archive. Nil leaves the external
	// rung unavailable whatever the admin toggle says, so a build with
	// no providers wired cannot reach out by accident.
	RadioArtResolver RadioArtResolver
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
// socket the waxbin CLI proxies through. It is also the root the domain
// types hang from (svc.Radio, svc.Playlists and the rest), and keeps the
// catalog's lifecycle.
type Library struct {
	*core
	// socketDir is the private directory the IPC socket lives in when the
	// data dir's path is too long for one; Close removes it.
	socketDir string
	// maintenance is a catalog hand-off in progress, between the suspend
	// and reopen hooks; suspendGen numbers the suspends. watchMu keeps a
	// suspend out of a watchdog's reopen.
	maintenance   atomic.Bool
	suspendGen    atomic.Uint64
	maintenanceMu sync.Mutex
	watchMu       sync.Mutex
	// The watchdog's interval and how many quiet passes it waits before
	// reopening an abandoned catalog (zero is each constant), and its count
	// of those passes, under watchMu.
	maintenanceWatchEvery  time.Duration
	maintenanceStuckPasses int
	unownedPasses          int
	// catalogPath is waxbin.db, whose lockfile names a hand-off's holder.
	catalogPath string
	// suspendHook runs inside the suspend hook for a test; nothing in the
	// server sets it.
	suspendHook func(context.Context)
	// catalogRepairHook runs before each step of a catalog repair, and an
	// error it answers is that step's, in a test; nothing in the server
	// sets it.
	catalogRepairHook func(step string) error
	// catalogRepairEndHook runs once a catalog repair's end is recorded,
	// before anything follows it, and answering true stops there, as the
	// process stopping would, in a test; nothing in the server sets it.
	catalogRepairEndHook func() bool
	// scanStartHook stands in for the catalog's answer to a whole scan's
	// start in a test, a busy catalog say; nil lets the start through.
	// Nothing in the server sets it.
	scanStartHook func() error
	// resetMu serializes a replaced catalog's reset between the reopen
	// hook and the feed, and a repair's new generation with both.
	resetMu sync.Mutex
	// catalogResync tells every client to re-mirror the catalog. Set by
	// SetCatalogResyncer; unset is a no-op.
	catalogResync atomic.Pointer[func()]
	// feed is the catalog change stream's identity and position;
	// serverGen names the event_log stream's generation.
	feed      syncFeed
	serverGen string
	// libJournal records which library each item sat in, followed off the
	// change log; journalWake is the feed's lossy nudge when an item moves.
	libJournal  libraryJournal
	journalWake chan struct{}
	// catalogWake is the lossy wakeup hint the event hub fans out as
	// invalidation frames.
	catalogWake chan struct{}
	// journalWalkHook runs before each page of the library journal's walk,
	// in a test, failing what follows; nothing in the server sets it.
	journalWalkHook func() error
}

// SocketFileName names the IPC socket, beside the catalog DB unless that
// path is too long for one (ipcSocket). It is a local admin plane: 0600,
// same user, full catalog access.
const SocketFileName = "waxbin.sock"

// Open opens the catalog read-write, wires the pidpath cache, starts
// the IPC server and (optionally) a startup scan on the supervised
// group, and returns the service.
func Open(ctx context.Context, cfg Config, store *wdb.DB, group *supervise.Group) (*Library, error) {
	log := cfg.Logger
	if log == nil {
		log = slog.New(slog.DiscardHandler)
	}
	log = HostOnlyLogger(log)
	if a, b, ok := overlappingRoots(cfg.Roots); ok {
		return nil, fmt.Errorf("service: the configured library roots %s and %s overlap", a, b)
	}
	socket, socketDir, madeDir := ipcSocket(cfg.DataDir)
	opened := false
	defer func() {
		if !opened && madeDir {
			os.RemoveAll(socketDir)
		}
	}()
	if socketDir != "" {
		log.Info("the waxbin CLI's socket is outside the data directory, whose path is too long for one",
			"socket", socket)
	}
	cursorSealer := cfg.CursorSealer
	if cursorSealer == nil {
		key := make([]byte, 32)
		if _, err := rand.Read(key); err != nil {
			return nil, fmt.Errorf("service: minting the cursor key: %w", err)
		}
		var err error
		if cursorSealer, err = auth.NewSealer(key, "waxdeck-cursor-v1"); err != nil {
			return nil, err
		}
	}
	sources := newEnrichSources(namedEnrichProviders(cfg.EnrichmentProviders, log))
	profiles, err := savedProfileDefs(ctx, store, log)
	if err != nil {
		return nil, fmt.Errorf("service: organize profiles: %w", err)
	}
	// The catalog owns each root's policy, so the configured roots are
	// registered once it is open rather than ensured from the options.
	opts := waxbin.Options{
		DBPath:                 filepath.Join(cfg.DataDir, "waxbin.db"),
		Profiles:               profiles,
		Logger:                 log,
		IPCSocket:              socket,
		SourceProviders:        cfg.SourceProviders,
		EnrichmentProviders:    sources.injected(),
		EnrichmentProviderList: sources.providerList,
	}
	if cfg.SecretCipher != nil {
		opts.SecretCipher = cfg.SecretCipher
		opts.SecretKeyID = "1"
	}
	var l *Library // assigned below; a hand-off cannot start before Serve does
	opts.OnSuspend = func(ctx context.Context) { l.onSuspend(ctx) }
	opts.OnReopen = func(ctx context.Context, ev waxbin.ReopenEvent) {
		l.onReopen(context.WithoutCancel(ctx), ev)
	}
	if cfg.PodcastDir != "" {
		opts.Podcasts = config.PodcastConfig{
			Dir:             cfg.PodcastDir,
			UserAgent:       UserAgentFor(cfg.Version),
			BlockPrivateIPs: !cfg.AllowPrivateFeedHosts,
		}
	}
	// The window governs the provider-gated phases too, so it is set with
	// or without a contact.
	opts.Enrichment.RetryMissesAfterDays = cfg.EnrichmentRetryMissesDays
	if cfg.EnrichmentContact != "" {
		// Only with a contact: the rest of the block without one would look
		// configured while still refusing every run.
		matchReleases := cfg.EnrichmentMatchReleases
		opts.Enrichment.Contact = cfg.EnrichmentContact
		opts.Enrichment.MatchReleases = &matchReleases
		opts.Enrichment.BlockPrivateIPs = !cfg.AllowPrivateFeedHosts
	}
	// Set when the open below had to discard a stale-baseline catalog, so
	// the service can say so once it has a logger on it.
	var reset *CatalogResetReport
	lib, err := waxbin.Open(ctx, opts)
	if err != nil {
		// A stale-baseline refusal is the one open failure with a recovery
		// WaxDeck can perform, so it is the one that gets translated: the
		// catalog's own message names `waxbin db reset`, a CLI a WaxDeck
		// operator does not have.
		//
		// Both halves are required. The fingerprint says the catalog is
		// one this build will not open; the refusal's own code says that
		// is why the open failed. Without the second, a catalog held by
		// another process on the same data dir -- an overlapping compose
		// restart -- would fail on the write lock and then be renamed out
		// from under the live owner's handles.
		if !waxerr.Is(err, waxerr.CodeUnsupported) || !staleBaseline(ctx, opts.DBPath) {
			return nil, fmt.Errorf("service: opening catalog: %w", err)
		}
		if !cfg.ResetStaleCatalog {
			// The catalog's own wording ends in its CLI's cure, so it goes to
			// the log for diagnosis rather than into the instruction.
			log.Error("the catalog refused to open", "err", err)
			return nil, fmt.Errorf("service: opening catalog: the catalog was built from a "+
				"different schema baseline and this build will not open it. Pre-1.0 the catalog "+
				"schema is edited in place rather than migrated, so there is no upgrade to run: "+
				"restart with -reset-catalog (WAXDECK_RESET_CATALOG=true) to move %s aside and "+
				"start fresh. That discards every play position, rating, star, playlist, curation "+
				"edit, podcast subscription and trash entry -- the media on disk is untouched and "+
				"is re-indexed by the startup scan. The previous catalog is renamed, not deleted.",
				opts.DBPath)
		}
		rep, rerr := resetStaleCatalog(ctx, opts.DBPath, cfg.Roots)
		if rerr != nil {
			return nil, fmt.Errorf("service: resetting stale catalog: %w", rerr)
		}
		reset = rep
		if lib, err = waxbin.Open(ctx, opts); err != nil {
			// The catalog is already aside, so this failure has to name it:
			// without the path, the backup that makes a mis-fire recoverable
			// is the one thing nobody knows to look for.
			if reset.SavedTo != "" {
				return nil, fmt.Errorf("service: opening catalog: the previous catalog was saved "+
					"to %s but the replacement could not be created; fix the cause and rename it "+
					"back: %w", reset.SavedTo, err)
			}
			return nil, fmt.Errorf("service: opening catalog: %w", err)
		}
	}

	sources.builtins = lib.EnrichmentBuiltins()

	paths, err := pidpath.New(ctx, lib, pidpath.Options{Logger: log, PollInterval: cfg.PathPollInterval})
	if err != nil {
		lib.Close()
		return nil, fmt.Errorf("service: pid path cache: %w", err)
	}

	c := &core{
		db:          store,
		lib:         lib,
		log:         log,
		workers:     group,
		paths:       paths,
		procCtx:     ctx,
		catalogFile: lib.File,
		catalogItem: lib.Get,
		userWake:    make(chan string, 64),
		sealer:      cfg.Sealer,
	}
	l = &Library{
		core:        c,
		catalogPath: opts.DBPath,
		socketDir:   socketDir,
		catalogWake: make(chan struct{}, 1),
		journalWake: make(chan struct{}, 1),
	}
	c.library = l
	c.wire(cfg)
	l.Enrichment.sources = sources
	l.Health.cursorSealer = cursorSealer
	l.Jobs.openedAtNS = time.Now().UnixNano()
	// Before anything settles a job: an end still in hand was cut short
	// by the stop before this start.
	if err := store.ReleaseJobOriginClaims(ctx); err != nil {
		log.Warn("releasing job ends cut short by a stop", "err", err)
	}
	if reset != nil {
		l.recordCatalogReset(ctx, reset)
	}
	// Before anything reads as an account: a reset drops the catalog user
	// each one is mapped to.
	if err := l.Identity.reconcileCatalogUsers(ctx); err != nil {
		paths.Close()
		lib.Close()
		return nil, fmt.Errorf("service: catalog users: %w", err)
	}
	if err := l.Roots.settleRoots(ctx); err != nil {
		paths.Close()
		lib.Close()
		return nil, fmt.Errorf("service: library roots: %w", err)
	}
	l.Roots.reconcileRemovedLibraries(ctx)
	l.Integrations.allowPrivateNotifyHosts = cfg.AllowPrivateNotifyHosts
	l.Integrations.publicBase = strings.TrimRight(cfg.PublicBase, "/")
	l.version = cfg.Version
	l.Integrations.dropLegacyNotifySetting(ctx)
	l.Settings.loadRuntimeToggles(ctx)
	l.Integrations.envLastfmKey, l.Integrations.envLastfmSecret = cfg.LastfmAPIKey, cfg.LastfmSecret
	l.Integrations.loadLastfmClient(ctx)
	if cfg.MatchSource != nil {
		l.Ingest.engine = match.NewEngine(cfg.MatchSource, cfg.MatchConfig)
	}
	l.Ingest.stagingDir = cfg.StagingDir
	if l.Ingest.stagingDir == "" {
		l.Ingest.stagingDir = filepath.Join(cfg.DataDir, "staging")
	}
	// Made here rather than by the first writer, so the free-space
	// probe a new session runs has a directory on the staging volume to
	// ask about. A server nobody uploads to carries an empty directory,
	// which the janitor already expects to find.
	if err := os.MkdirAll(l.Ingest.stagingDir, 0o755); err != nil {
		paths.Close()
		lib.Close()
		return nil, fmt.Errorf("service: staging directory: %w", err)
	}
	l.Ingest.stagingFree = diskspace.Free
	l.Ingest.setUploadFormats(cfg.UploadFormats)
	l.Ingest.fpcalcPath = cfg.FpcalcPath
	if l.Ingest.fpcalcPath == "" {
		if p, err := exec.LookPath("fpcalc"); err == nil {
			l.Ingest.fpcalcPath = p
		}
	}
	l.Enrichment.musicbrainzConfigured = cfg.EnrichmentContact != ""
	l.Ingest.sourceProviders = cfg.SourceProviders
	if err := l.initSync(ctx); err != nil {
		paths.Close()
		lib.Close()
		return nil, fmt.Errorf("service: sync state: %w", err)
	}
	l.settleOwedResync(ctx)

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

	// The catalog's jobs, announced as they move and settled as they end.
	group.Go(ctx, "job-follow", l.Jobs.runJobFollower)

	// Which library each item sat in, for the catalog delta's tombstones.
	group.Go(ctx, "library-journal", l.runLibraryJournal)

	// The radio bookkeeping writer. Started here rather than on the
	// first segment a listener produces: spawning it from a request
	// goroutine would add to the group's wait counter while shutdown may
	// already be waiting on it, which is a panic rather than a late
	// worker.
	group.Go(ctx, "radio-writes", l.Radio.writeRadioBookkeeping)

	// A waxbin upgrade can change the sort-key fold, and no scan rewrites
	// an existing key, so every boot sweeps the stale ones; rewritten rows
	// ride the change feed, so caches and clients invalidate themselves.
	// It streams every name-bearing row even when none have moved, which
	// is why it rides a worker and not the startup path. Boot is when the
	// fewest page cursors are outstanding, not when none are (read.Cursor
	// embeds the key); one held across it skips or repeats rows --
	// bounded, not worth machinery.
	group.GoOnce(ctx, "sortkey-refresh", func(ctx context.Context) error {
		n, err := l.lib.RefreshSortKeys(ctx)
		if err != nil {
			return err // supervise logs it; startup is unaffected.
		}
		if n > 0 {
			log.Info("refreshed stale sort keys", "rows", n)
		}
		return nil
	})

	// The starter playlists every account should hold. A boot pass
	// rather than a read: it is what covers accounts made before the
	// starters existed, and a catalog reset or rebuild, which drops the
	// playlist while the row naming it survives. Both only ever take
	// effect at a start.
	group.GoOnce(ctx, "starter-playlists", l.Playlists.reconcileStarterPlaylists)

	if cfg.ScanOnStart {
		group.GoOnce(ctx, "startup-scan", func(ctx context.Context) error {
			pid, err := l.lib.StartScan(ctx, waxbin.ScanRequest{})
			if err != nil {
				return err
			}
			l.Jobs.followJob(pid)
			log.Info("startup scan launched", "job", string(pid))
			return nil
		})
	}

	// Files placed into the roots by hand reach the catalog through the
	// watcher; the discovery sweeper then opens their review entries.
	// Spawned even with no roots yet: a console-managed install adds
	// its first library at runtime, and the watcher holds for the nudge.
	if cfg.WatchLibraries {
		group.Go(ctx, "library-watch", l.Roots.watchLibraries)
		group.Go(ctx, "library-watch-scan", l.Roots.watchScanWorker)
	}

	// The managed roots' write probe, once the server's read-only switch
	// is read: now, then on a slow timer (and after a refused write).
	l.Roots.probeRoots()
	group.Go(ctx, "root-probe-timer", l.Roots.probeRootsEvery)
	opened = true
	return l, nil
}

// Close releases the catalog (flushing playback state), the path cache,
// and a socket directory Open made.
func (l *Library) Close() error {
	// The radio queue's last word, and this is the only place it can be
	// had. A tune-in writes its closing checkpoint as the relay unwinds,
	// which happens when requests are cancelled - after the signal that
	// stopped the writer, and after the wait that would otherwise be the
	// obvious place to flush. Close runs behind both, so by here nothing
	// can be relaying and nothing more can arrive.
	l.Radio.drainRadioWrites()
	if err := l.paths.Close(); err != nil {
		l.log.Warn("closing pid path cache", "err", err)
	}
	err := l.lib.Close()
	if l.socketDir != "" {
		os.RemoveAll(l.socketDir)
	}
	return err
}

// Rescan starts an asynchronous scan of every root and returns the
// job. The scan runs on the process context, not the request's: it
// must survive the response that reported it started. Force bypasses
// the incremental fast-path so unchanged files are re-read (the repair
// pass); locks are never ignored, so curated fields survive either way.
// Nobody hears of its end; RescanFor is an administrator's.
func (l *Library) Rescan(ctx context.Context, force bool) (Job, error) {
	return l.startScan(ctx, "", force)
}

// RescanFor is Rescan started by an administrator, whose inbox hears when
// the scan ends.
func (l *Library) RescanFor(ctx context.Context, uc *UserCtx, force bool) (Job, error) {
	if !uc.Admin {
		return Job{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	return l.startScan(ctx, uc.ID, force)
}

func (l *Library) startScan(ctx context.Context, userID string, force bool) (Job, error) {
	if l.scanStartHook != nil {
		if err := l.scanStartHook(); err != nil {
			return Job{}, err
		}
	}
	pid, err := l.lib.StartScan(l.procCtx, waxbin.ScanRequest{Force: force})
	if err != nil {
		return Job{}, classify(err)
	}
	l.Jobs.followStarted(ctx, pid, userID)
	return l.Jobs.Status(ctx, apiPID(PrefixJob, pid))
}

// Analyze starts the asynchronous analyze pass and returns the job.
// Like Rescan it runs on the process context so it outlives the
// response, and StartAnalyze is the async sibling: the plain Analyze
// runs the whole decode inline and only names its job once it is
// finished, which is no use to an endpoint that must answer now.
//
// AnalyzeOptions.WriteReplayGainTags stays false. Upstream ORs it with
// the library's own configured toggle, so leaving it unset means "do
// whatever this library is configured to do" rather than "never write
// tags"; opting in here would override the deployment's choice.
func (l *Library) Analyze(ctx context.Context) (Job, error) {
	return l.startAnalyze(ctx, "")
}

// AnalyzeFor is Analyze started by an administrator, whose inbox hears
// when the pass ends.
func (l *Library) AnalyzeFor(ctx context.Context, uc *UserCtx) (Job, error) {
	if !uc.Admin {
		return Job{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	return l.startAnalyze(ctx, uc.ID)
}

func (l *Library) startAnalyze(ctx context.Context, userID string) (Job, error) {
	pid, err := l.lib.StartAnalyze(l.procCtx, waxbin.AnalyzeOptions{})
	if err != nil {
		return Job{}, classify(err)
	}
	l.Jobs.followStarted(ctx, pid, userID)
	return l.Jobs.Status(ctx, apiPID(PrefixJob, pid))
}

// summary converts an item view to the list-row DTO.
func summary(it *model.ItemView) ItemSummary {
	title, artist, album := itemNames(it)
	return ItemSummary{
		PID:             itemAPIPID(it),
		MediaType:       mediaTypeForKind(it.Kind),
		Title:           title,
		Artist:          artist,
		Album:           album,
		ArtistPID:       entityAPIPID(PrefixArtist, it.ArtistPID),
		AlbumPID:        entityAPIPID(PrefixAlbum, it.AlbumPID),
		TrackNo:         it.TrackNo,
		DiscNo:          it.DiscNo,
		SortKey:         model.SortKey(it.Title),
		ArtistSort:      artistSort(it),
		DurationMS:      it.DurationMS,
		Virtual:         it.Virtual,
		AdvisoryFlagged: it.AdvisoryFlagged(),
		ArtistSortKey:   artistSortKey(it),
	}
}

// artistSort is the sort spelling a file or an edit states for an
// item's artist: a book's author's, since a book names its author as its
// artist. An episode states none.
func artistSort(it *model.ItemView) string {
	if it.Kind == model.KindBook {
		return it.AuthorSort
	}
	return it.ArtistSort
}

// artistSortKey is the key the catalog files an item's artist under,
// made as it makes the stored one: of the stated sort spelling, else of
// the artist, else of a track's album artist, and of a book's author in
// the same way. An episode is filed by no artist.
func artistSortKey(it *model.ItemView) string {
	switch it.Kind {
	case model.KindTrack:
		return model.SortKey(cmp.Or(it.ArtistSort, it.Artist, it.AlbumArtist))
	case model.KindBook:
		return model.SortKey(cmp.Or(it.AuthorSort, it.Artist))
	}
	return ""
}

// itemNames are an item view's title, artist and album as WaxDeck names
// them: an episode's come from its feed, its own title and its show's, and
// are clipped as every feed title is.
func itemNames(it *model.ItemView) (title, artist, album string) {
	if it.Kind != model.KindEpisode {
		return it.Title, it.Artist, it.Album
	}
	return clipFeedTitle(it.Title), clipFeedTitle(it.Artist), clipFeedTitle(it.Album)
}
