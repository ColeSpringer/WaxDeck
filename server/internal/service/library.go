// Package service is the application core: everything between the API
// surface and the WaxBin facade. Handlers call services; services call
// the facade; nothing above this package imports waxbin.
package service

import (
	"cmp"
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
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
	"github.com/colespringer/waxdeck/server/internal/providers"
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
	// Media, PID, Profile and ReadOnly are the catalog's, filled when the
	// table is rebuilt from it.
	Media    string
	PID      string
	Profile  string
	ReadOnly bool
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
	// WatchSettle is how long a directory must stay event-quiet before
	// its scoped rescan fires; zero means the ten-second default. Tests
	// set it short.
	WatchSettle time.Duration
	// ResetStaleCatalog moves a catalog built on a different schema
	// baseline aside at startup instead of refusing to start. See
	// staleBaseline for what it does and does not distinguish.
	ResetStaleCatalog bool
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
// socket the waxbin CLI proxies through.
type Library struct {
	lib   *waxbin.Library
	paths *pidpath.Cache
	db    *wdb.DB
	// socketDir is the private directory the IPC socket lives in when the
	// data dir's path is too long for one; Close removes it.
	socketDir string
	// catalogUsers maps an account whose stored catalog user a reset or
	// restore dropped to the one the catalog holds for it; read through
	// catalogPID.
	catalogUsers   map[string]model.PID
	catalogUsersMu sync.RWMutex
	// usersUnmapped is an account the last mapping could not place,
	// which the settle after a reopen retries.
	usersUnmapped atomic.Bool
	// roots is the root table, rebuilt from the catalog and swapped under
	// rootsMu (read it through libraryRoots); refreshMu keeps an older read
	// from landing after a newer one. configRoots are the configured ones.
	roots       []Root
	rootsBuilt  bool
	rootsMu     sync.RWMutex
	refreshMu   sync.Mutex
	configRoots []Root
	// rootsLeftOut are configured roots the catalog refused, warned of once.
	rootsLeftOut sync.Map
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
	// resetMu serializes a replaced catalog's reset between the reopen
	// hook and the feed; profilesMu a saved profile's round trip.
	resetMu    sync.Mutex
	profilesMu sync.Mutex
	// catalogResync tells every client to re-mirror the catalog. Set by
	// SetCatalogResyncer; unset is a no-op.
	catalogResync atomic.Pointer[func()]
	log           *slog.Logger
	// libDirs caches path-to-library attribution for visibility checks.
	libDirs libraryDirs
	// procCtx outlives any one request: async catalog jobs launch on it
	// so a scan survives the 202 that reported it started.
	procCtx context.Context
	// feed is the catalog change stream's identity and position;
	// serverGen names the event_log stream's generation.
	feed      syncFeed
	serverGen string
	// jobs follows the catalog's jobs off the feed; jobWake is the feed's
	// lossy nudge to the follower when a job row changes.
	jobs    jobWatch
	jobWake chan struct{}
	// sweeping is a health sweep in progress.
	sweeping atomic.Bool
	// sweepFailed is the last sweep having failed, until one lands.
	sweepFailed atomic.Bool
	// catalogWake and userWake are the lossy wakeup hints the event hub
	// fans out as invalidation frames.
	catalogWake chan struct{}
	userWake    chan string
	// sealer and appSecrets back the app-password credential store.
	sealer     *auth.Sealer
	appSecrets appSecretCache
	// trackFacts caches the compatibility surface's track sweep.
	trackFacts trackFactsCache
	// genres holds the built genre vocabulary; facets caches the
	// full-visibility browse-dimension enumerations.
	genres genreVocabulary
	facets facetCache
	// tagValues holds the stored spellings of each custom-tag field, for
	// compiling a caller's tag rules into a query. Same generation as
	// facets, since both are functions of the catalog's contents.
	tagValues tagValueCache
	// podcastDir and podcastRootName locate the episode download
	// library; defaultRetentionKeep is the unset-subscriber policy;
	// retentionInUseWindow gates the sweep's in-use deferral.
	podcastDir           string
	podcastRootName      string
	defaultRetentionKeep int64
	retentionInUseWindow time.Duration
	// flowJobs is the streaming sidecar's analysis surface, wired after
	// construction (the bridge needs this service as its resolver);
	// flowRoots is its runtime-root surface, wired the same way.
	flowJobs  FlowJobs
	flowRoots atomic.Pointer[FlowRootSync]
	// flowSyncMu serializes teaching the bridge: WaxFlow refuses a root
	// name it already maps, and two teachers could both see one as new.
	// flowRefused holds the paths it refused by name, not offered again.
	flowSyncMu  sync.Mutex
	flowRefused map[string]string
	// coverSyncing single-flights playlist cover generation per playlist,
	// so concurrent readers of one shared list do not each composite it.
	coverSyncing map[model.PID]bool
	coverSyncMu  sync.Mutex
	// playedLocks serializes the played decide-act per (user, item);
	// see lockPlayed.
	playedLocks [playedStripes]sync.Mutex
	// transcriptHTTP is the guarded client for transcript pointers,
	// built on first use; allowPrivateFeedHosts relaxes its SSRF guard.
	transcriptHTTP        *http.Client
	transcriptHTTPOnce    sync.Once
	allowPrivateFeedHosts bool
	// enclosureHTTP is the guarded client the podcast enclosure
	// passthrough relays through, built on first use and sharing
	// allowPrivateFeedHosts with transcript fetches. It carries no
	// overall timeout: an episode relay lasts as long as the listening
	// session, so the request context is its only bound.
	enclosureHTTP     *http.Client
	enclosureHTTPOnce sync.Once
	// radioHTTP is the guarded client for radio streams and the
	// station directory, built on first use; allowPrivateRadioHosts
	// relaxes its SSRF guard. It carries no overall timeout (radio
	// streams are unbounded); bounded calls pass a request context.
	radioHTTP              *http.Client
	radioHTTPOnce          sync.Once
	allowPrivateRadioHosts bool
	// radioTitleFresh is how long an observed title outlives the last
	// metadata block; radioTitleFreshFor is its default.
	radioTitleFresh time.Duration
	// radioArtBudget bounds one external artwork lookup;
	// radioArtLookupBudget is its default and its only production value.
	// Tests set it short to reach the deadline without waiting a minute.
	radioArtBudget time.Duration
	// radioWake wakes the clients tuned to one station when its face has
	// something new. Set by SetRadioInvalidator; unset is a no-op.
	radioWake          atomic.Pointer[func(stationPID string)]
	radioDirectoryBase string
	// radioDirectoryMirrorList overrides mirror discovery, and
	// radioMirrors caches what discovery found. radioMirrorCold holds
	// the mirrors that just failed, which sort last for a few minutes
	// rather than being dropped: on an afternoon where the whole
	// directory is unwell, dropping them would leave nothing to ask.
	radioDirectoryMirrorList []string
	radioMirrors             []string
	radioMirrorsAt           time.Time
	radioMirrorCold          map[string]time.Time
	radioMirrorsMu           sync.Mutex
	// podcastDirectory answers show name searches, built on first use
	// so an install that never searches never allocates its cache.
	podcastDirectoryBase string
	podcastDirectory     *providers.PodcastDirectory
	podcastDirectoryOnce sync.Once
	// nowPlayingMemos caches the last ICY-title-to-track resolution per
	// listener and station, so a poll that changes nothing costs no FTS.
	nowPlayingMemos  map[string]nowPlayingMemo
	nowPlayingMemoMu sync.Mutex
	// radioTitles holds each station's last proxy-observed in-stream
	// title; process-local on purpose (a title only exists while this
	// process is proxying the stream).
	radioTitles   map[string]radioTitle
	radioTitlesMu sync.Mutex
	// radioLogos caches fetched station logos, and the stations found to
	// have none, so a household browsing the dial does not re-fetch the
	// same favicons once per device. Memory only and bounded by bytes:
	// logos are decoration, and losing them at restart costs one fetch
	// each. radioLogosOrder is insertion order, for eviction.
	// radioLogoFlights are the fetches in progress, keyed by station pid,
	// so two callers asking for one logo at the same moment cost one
	// request to the station host rather than two. A dial and a grid draw
	// the same station on one paint and two devices paint at once, and
	// against a dead host each of those is a ten-second wait.
	// radioLogoHints are logo URLs tried ahead of discovery: a station's
	// Icy-Logo, or a picture it repeated song after song. radioIcyLogos
	// and radioDirectoryLogos are only the logos stations declared.
	// radioWarmSlots bounds concurrent warm lookups: a client restoring
	// a whole station list creates in a burst, and an unbounded fan-out
	// of discovery flights (each up to the 12s budget) is a lot of
	// sockets for pictures. Queued warms hold only their claim; paints
	// join the flight and wait the same either way.
	radioLogos          map[string]radioLogo
	radioLogosOrder     []string
	radioLogosBytes     int
	radioLogoFlights    map[string]chan struct{}
	radioLogoHints      map[string]string
	radioIcyLogos       map[string]string
	radioDirectoryLogos map[string]string
	radioLogosMu        sync.Mutex
	radioWarmSlots      chan struct{}
	// batchFinalizeMu serializes upload-batch finalization (the flip,
	// entry opening, and member linking as one unit): two concurrent
	// finalizes of one batch would otherwise both gather the same
	// still-unlinked members and open duplicate review entries.
	// Process-wide is fine - finalizes are rare and database-only.
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
	// publicBase is where this server's web app answers, trailing slash
	// trimmed; empty leaves every notification link out.
	publicBase string
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
	// extension set (uploadFormatsList the sorted health-payload form,
	// deny-list subtracted); uploadRetention bounds staged-byte
	// lifetime.
	stagingDir        string
	uploadFormats     map[string]bool
	uploadFormatsList []string
	uploadRetention   time.Duration
	// stagingFree answers how much room the staging volume has left,
	// for the check a new session runs. A field rather than a direct
	// call so a test can hand it a full disk; nothing configures it.
	stagingFree func(string) (int64, bool)
	// catalogFile reads a file row for the similarity sweep; a field so
	// a test can hand it a read that fails.
	catalogFile func(context.Context, model.PID) (*model.File, error)
	// admitUpload serializes the allowance checks a new session runs
	// against the insert that spends them.
	admitUpload sync.Mutex
	// fpcalcPath is the fingerprint binary, empty when absent (matching
	// then runs on tag and search evidence only).
	fpcalcPath string
	// sources are the server-registered enrichment providers in the
	// operator's order, and what the catalog's pass runs on.
	sources *enrichSources
	// openedAtNS is when this process opened the library: a job's end
	// taken in hand before it was cut short by a stop.
	openedAtNS int64
	// jobFollowEvery is how often the job follower reads the running jobs;
	// zero is jobFollowInterval.
	jobFollowEvery time.Duration
	// matchWake nudges the identify worker; lossy, ticker-backstopped.
	matchWake chan struct{}
	// toggles is the hot-path settings cache (the server's read-only flag,
	// transcode limits), swapped whole on every write.
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
	// musicbrainzConfigured mirrors whether Config.EnrichmentContact was
	// set, which is what decides whether the enrichment pass's identity
	// phases can run. The provider-gated phases run without it, so this
	// is not "enrichment is configured" - see enrichmentPhases.
	musicbrainzConfigured bool
	// enrichmentMatchReleases mirrors Config.EnrichmentMatchReleases,
	// which with the contact gates the release-match phase.
	enrichmentMatchReleases bool
	// sonicAnalysisDefault and workerAPIConfigured mirror their Config
	// fields.
	sonicAnalysisDefault bool
	workerAPIConfigured  bool
	// workers is the supervised group Open was handed, kept so work a
	// request starts but does not wait on (radio's external artwork
	// lookup) still runs under the recover boundary every WaxDeck
	// goroutine goes through. Nothing here may spawn a bare one.
	workers *supervise.Group
	// radioListenFloor mirrors Config.RadioListenMinListen, resolved.
	radioListenFloor time.Duration
	// radioArtResolver mirrors Config.RadioArtResolver, and
	// radioArtCache holds what it has answered.
	radioArtResolver RadioArtResolver
	radioArtCache    radioArt
	// radioWrites hands radio bookkeeping from the goroutine relaying a
	// listener's audio to the writer Open starts. Everything the relay
	// loop does that touches SQLite goes through here, and nothing else
	// in that loop does.
	radioWrites chan radioWrite
	// radioWriteDone, when set, is called after each queued piece of
	// bookkeeping has been written, so a test can wait for the writer
	// instead of sleeping; nothing in the server sets it. Atomic because
	// the writer is already running by the time a test can install one.
	radioWriteDone atomic.Pointer[func()]
	// podping holds the feed-URL index a chain notification resolves
	// against, and the per-show floor between two podping-driven syncs.
	podping podpingIndex
	// watchQueue holds the event-touched directories waiting out their
	// settle window; watchScans carries settled batches to the scan
	// worker, so scans never run on the event loop; watchNudge wakes
	// the library watcher to re-arm over a fresh root table after a
	// runtime library create; watchReady closes once the first arm
	// pass finishes, so a test can order its drop after the watches
	// exist.
	watchQueue     *watchPending
	watchScans     chan []string
	watchNudge     chan struct{}
	watchReady     chan struct{}
	watchReadyOnce sync.Once
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
			return nil, fmt.Errorf("service: opening catalog: the catalog was built from a "+
				"different schema baseline and this build will not open it. Pre-1.0 the catalog "+
				"schema is edited in place rather than migrated, so there is no upgrade to run: "+
				"restart with -reset-catalog (WAXDECK_RESET_CATALOG=true) to move %s aside and "+
				"start fresh. That discards every play position, rating, star, playlist, curation "+
				"edit, podcast subscription and trash entry -- the media on disk is untouched and "+
				"is re-indexed by the startup scan. The previous catalog is renamed, not deleted: %w",
				opts.DBPath, err)
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

	l = &Library{
		sources: sources,
		lib:     lib, paths: paths, db: store, configRoots: cfg.Roots, log: log, procCtx: ctx,
		catalogPath:              opts.DBPath,
		socketDir:                socketDir,
		catalogWake:              make(chan struct{}, 1),
		userWake:                 make(chan string, 64),
		jobWake:                  make(chan struct{}, 1),
		openedAtNS:               time.Now().UnixNano(),
		matchWake:                make(chan struct{}, 1),
		radioWrites:              make(chan radioWrite, radioWriteQueue),
		sealer:                   cfg.Sealer,
		podcastDir:               cfg.PodcastDir,
		podcastRootName:          cfg.PodcastRootName,
		defaultRetentionKeep:     cfg.DefaultRetentionKeep,
		retentionInUseWindow:     cfg.RetentionInUseWindow,
		allowPrivateFeedHosts:    cfg.AllowPrivateFeedHosts,
		allowPrivateRadioHosts:   cfg.AllowPrivateRadioHosts,
		radioListenFloor:         cmp.Or(cfg.RadioListenMinListen, RadioListenMinListen),
		radioTitleFresh:          cfg.RadioTitleFreshFor,
		radioDirectoryBase:       cfg.RadioDirectoryBase,
		radioDirectoryMirrorList: cfg.RadioDirectoryMirrors,
		podcastDirectoryBase:     cfg.PodcastDirectoryBase,
		radioTitles:              map[string]radioTitle{},
		radioLogos:               map[string]radioLogo{},
		radioWarmSlots:           make(chan struct{}, 4),
		radioLogoFlights:         map[string]chan struct{}{},
		listenbrainz:             scrobble.NewListenBrainz(),
		sim:                      similarity.New(),
		workerLocalPaths:         cfg.WorkerLocalPaths,
		isrcResolver:             cfg.ISRCResolver,
		sonicAnalysisDefault:     cfg.SonicAnalysisDefault,
		workerAPIConfigured:      cfg.WorkerAPIConfigured,
		workers:                  group,
		radioArtResolver:         cfg.RadioArtResolver,
		watchQueue:               newWatchPending(cfg.WatchSettle),
		watchScans:               make(chan []string, 1),
		watchNudge:               make(chan struct{}, 1),
		watchReady:               make(chan struct{}),
	}
	if reset != nil {
		l.logCatalogReset(reset)
	}
	// Before anything reads as an account: a reset drops the catalog user
	// each one is mapped to.
	if err := l.reconcileCatalogUsers(ctx); err != nil {
		paths.Close()
		lib.Close()
		return nil, fmt.Errorf("service: catalog users: %w", err)
	}
	if err := l.settleRoots(ctx); err != nil {
		paths.Close()
		lib.Close()
		return nil, fmt.Errorf("service: library roots: %w", err)
	}
	// The ListenBrainz API base is caller-supplied, so its deliveries
	// ride a dial-guarded client like every other user-pointed fetch;
	// the flag opts LAN instances back in. The connection's write-time
	// check gives the friendly error, this guard is the boundary.
	l.allowPrivateScrobbleHosts = cfg.AllowPrivateScrobbleHosts
	l.listenbrainz.HTTP = scrobbleHTTPClient(cfg.AllowPrivateScrobbleHosts)
	l.allowPrivateNotifyHosts = cfg.AllowPrivateNotifyHosts
	l.publicBase = strings.TrimRight(cfg.PublicBase, "/")
	l.dropLegacyNotifySetting(ctx)
	l.loadRuntimeToggles(ctx)
	l.envLastfmKey, l.envLastfmSecret = cfg.LastfmAPIKey, cfg.LastfmSecret
	l.loadLastfmClient(ctx)
	if l.retentionInUseWindow == 0 {
		l.retentionInUseWindow = 2 * time.Minute
	}
	if l.radioTitleFresh == 0 {
		l.radioTitleFresh = radioTitleFreshFor
	}
	if l.radioArtBudget == 0 {
		l.radioArtBudget = radioArtLookupBudget
	}
	if cfg.MatchSource != nil {
		l.engine = match.NewEngine(cfg.MatchSource, cfg.MatchConfig)
	}
	l.stagingDir = cfg.StagingDir
	if l.stagingDir == "" {
		l.stagingDir = filepath.Join(cfg.DataDir, "staging")
	}
	// Made here rather than by the first writer, so the free-space
	// probe a new session runs has a directory on the staging volume to
	// ask about. A server nobody uploads to carries an empty directory,
	// which the janitor already expects to find.
	if err := os.MkdirAll(l.stagingDir, 0o755); err != nil {
		paths.Close()
		lib.Close()
		return nil, fmt.Errorf("service: staging directory: %w", err)
	}
	l.stagingFree = diskspace.Free
	l.catalogFile = lib.File
	l.setUploadFormats(cfg.UploadFormats)
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
	l.musicbrainzConfigured = cfg.EnrichmentContact != ""
	l.enrichmentMatchReleases = cfg.EnrichmentMatchReleases
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

	// The catalog's jobs, announced as they move and settled as they end.
	group.Go(ctx, "job-follow", l.runJobFollower)

	// The radio bookkeeping writer. Started here rather than on the
	// first segment a listener produces: spawning it from a request
	// goroutine would add to the group's wait counter while shutdown may
	// already be waiting on it, which is a panic rather than a late
	// worker.
	group.Go(ctx, "radio-writes", l.writeRadioBookkeeping)

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
	group.GoOnce(ctx, "starter-playlists", l.reconcileStarterPlaylists)

	if cfg.ScanOnStart {
		group.GoOnce(ctx, "startup-scan", func(ctx context.Context) error {
			pid, err := l.lib.StartScan(ctx, waxbin.ScanRequest{})
			if err != nil {
				return err
			}
			l.followJob(pid)
			log.Info("startup scan launched", "job", string(pid))
			return nil
		})
	}

	// Files placed into the roots by hand reach the catalog through the
	// watcher; the discovery sweeper then opens their review entries.
	// Spawned even with no roots yet: a console-managed install adds
	// its first library at runtime, and the watcher holds for the nudge.
	if cfg.WatchLibraries {
		group.Go(ctx, "library-watch", l.watchLibraries)
		group.Go(ctx, "library-watch-scan", l.watchScanWorker)
	}
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
	l.drainRadioWrites()
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
	pid, err := l.lib.StartScan(l.procCtx, waxbin.ScanRequest{Force: force})
	if err != nil {
		return Job{}, classify(err)
	}
	l.followStarted(ctx, pid, userID)
	return l.JobStatus(ctx, apiPID(PrefixJob, pid))
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
	l.followStarted(ctx, pid, userID)
	return l.JobStatus(ctx, apiPID(PrefixJob, pid))
}

// followStarted hands a job this server started to the follower, which
// the feed alone may never tell of it, recording who asked when a person
// did (userID, empty for the server's own).
func (l *Library) followStarted(ctx context.Context, pid model.PID, userID string) {
	if userID != "" {
		l.adoptJob(ctx, pid, userID, "")
		return
	}
	l.followJob(pid)
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
	out := []Job{jobDTO(job)}
	l.nameJobTargets(ctx, out)
	return out[0], nil
}

// Jobs lists recent catalog jobs, newest first, after any still running
// that newer ones pushed out. A finished targeted job is left out (read by
// pid): a burst of them would push the passes out. Administrators only.
func (l *Library) Jobs(ctx context.Context, uc *UserCtx, limit int) ([]Job, error) {
	if !uc.Admin {
		return nil, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	jobs, err := l.lib.Jobs(ctx, min(limit*jobsOverfetch, jobsFetchCap))
	if err != nil {
		return nil, classify(err)
	}
	jobs = slices.DeleteFunc(jobs, func(j *model.Job) bool { return j.TargetType != "" && j.State != model.JobRunning })
	jobs = jobs[:min(len(jobs), limit)]
	listed := make(map[model.PID]bool, len(jobs))
	for _, job := range jobs {
		listed[job.PID] = true
	}
	var out []Job
	running, err := l.followedRunning(ctx)
	if err != nil {
		l.log.Warn("jobs: reading the followed jobs", "err", err)
	}
	for _, pid := range running {
		if listed[pid] {
			continue
		}
		if job, err := l.lib.Job(ctx, pid); err == nil && job.State == model.JobRunning {
			out = append(out, jobDTO(job))
		}
	}
	sortJobsNewestFirst(out)
	for _, job := range jobs {
		out = append(out, jobDTO(job))
	}
	l.nameJobTargets(ctx, out)
	return out, nil
}

// summary converts an item view to the list-row DTO.
func summary(it *model.ItemView) ItemSummary {
	return ItemSummary{
		PID:             itemAPIPID(it),
		MediaType:       mediaTypeForKind(it.Kind),
		Title:           it.Title,
		Artist:          it.Artist,
		Album:           it.Album,
		ArtistPID:       entityAPIPID(PrefixArtist, it.ArtistPID),
		AlbumPID:        entityAPIPID(PrefixAlbum, it.AlbumPID),
		TrackNo:         it.TrackNo,
		DiscNo:          it.DiscNo,
		DurationMS:      it.DurationMS,
		Virtual:         it.Virtual,
		AdvisoryFlagged: it.AdvisoryFlagged(),
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
