package main

import (
	"flag"
	"fmt"
	"math"
	"path/filepath"
	"strings"
	"time"

	"github.com/colespringer/waxdeck/server/internal/auth"
	"github.com/colespringer/waxdeck/server/internal/envflag"
)

// config is the server's settings: flags whose defaults come from their
// WAXDECK_* variables.
type config struct {
	core        coreConfig
	streaming   streamingConfig
	podcasts    podcastsConfig
	radio       radioConfig
	scrobble    scrobbleConfig
	acquisition acquisitionConfig
	casting     castingConfig
	roots       rootsConfig
	matching    matchingConfig
	oidc        oidcConfig
	similarity  similarityConfig

	// The modes that answer and exit instead of serving.
	showVersion, ping, showNotices bool
}

type coreConfig struct {
	addr           string
	webDir         string
	dataDir        string
	libraryRoots   []root
	scanOnStart    bool
	resetCatalog   bool
	cookieSecure   bool
	sessionCap     int
	publicBase     string
	trustedProxies string
	corsOrigins    string
	metricsToken   string
}

type streamingConfig struct {
	flowURL    string
	flowAPIKey string
	flowConfig string
}

type podcastsConfig struct {
	// dir is the episode download directory; empty turns podcasts off.
	dir                string
	rootName           string
	feedRefreshMinutes int
	retentionKeep      int64
	allowPrivateHosts  bool
	podping            podpingConfig
	directoryBase      string
}

type podpingConfig struct {
	on      bool
	node    string
	writers string
}

type radioConfig struct {
	allowPrivateHosts bool
	directoryBase     string
}

type scrobbleConfig struct {
	allowPrivateScrobbleHosts bool
	allowPrivateNotifyHosts   bool
	lastfmKey                 string
	lastfmSecret              string
}

type acquisitionConfig struct {
	youtube      bool
	sealURL      string
	sealKey      string
	sponsorBlock []string
	ytThumbnail  bool
	stubSource   string
}

type castingConfig struct {
	advertiseBase string
	discovery     bool
	devices       string
	dlnaDevices   string
	jukebox       bool
	jukeboxCmd    string
	jukeboxName   string
}

type rootsConfig struct {
	managed       string
	audiobook     string
	watch         bool
	uploadFormats string
}

type matchingConfig struct {
	on              bool
	musicBrainzBase string
	coverArtBase    string
	acoustIDKey     string
	fanartTVKey     string
	discogsToken    string
	hardcoverKey    string
	googleBooksKey  string
	enrichURLs      string
	enrichAuth      string
	artistArt       bool
	enrichContact   string
	enrichMatch     bool
	enrichRetryDays *int
}

type oidcConfig struct {
	issuer       string
	id           string
	name         string
	clientID     string
	clientSecret string
	groupsClaim  string
	adminGroup   string
}

type similarityConfig struct {
	sonicAnalysis    bool
	workerTokens     []string
	workerLocalPaths bool
}

// parseConfig reads the settings from args on fs, each flag's default
// coming from its variable through lookupEnv, the only environment it
// reads, and refuses the values the server cannot run with.
func parseConfig(fs *flag.FlagSet, args []string, lookupEnv func(string) (string, bool)) (*config, error) {
	envOr := func(key, def string) string {
		if v, _ := lookupEnv(key); v != "" {
			return v
		}
		return def
	}
	env := envflag.New(fs, lookupEnv)
	var (
		addr       = fs.String("addr", envOr("WAXDECK_ADDR", ":4420"), "listen address")
		webDir     = fs.String("web-dir", envOr("WAXDECK_WEB_DIR", ""), "serve the web UI from this directory instead of the embedded build (dev)")
		dataDir    = fs.String("data-dir", envOr("WAXDECK_DATA_DIR", "./data"), "data directory (waxbin.db + waxdeck.db)")
		rootsFlag  = fs.String("library-roots", envOr("WAXDECK_LIBRARY_ROOTS", ""), "library roots as name=path pairs, comma separated; names must match the WaxFlow roots serving the same directories")
		flowURL    = fs.String("flow-url", envOr("WAXDECK_FLOW_URL", ""), "WaxFlow sidecar base URL; one that is not answering is retried in the background while originals play directly, and /health reports it (empty serves originals directly: no transcoding, gapless timelines or voice boost)")
		flowAPIKey = fs.String("flow-api-key", envOr("WAXDECK_FLOW_API_KEY", ""), "API key WaxDeck presents to the WaxFlow sidecar")
		flowConfig = fs.String("flow-config", envOr("WAXDECK_FLOW_CONFIG", ""), "the WaxFlow sidecar's JSON config file, as WaxDeck sees it; set it (and point the sidecar at the same file) so a library created at runtime streams without a sidecar restart")
		scanStart  = env.Bool("scan-on-start", "WAXDECK_SCAN_ON_START", true, "launch a library scan at startup")
		resetStale = env.Bool("reset-catalog", "WAXDECK_RESET_CATALOG", false, "when the catalog was built from a different schema baseline (which pre-1.0 is edited in place rather than migrated), move it aside and start on a fresh one instead of refusing to start. Discards play positions, ratings, stars, playlists, curation edits, podcast subscriptions and trash; media on disk is untouched and re-indexed by the startup scan. It fires only on that refusal, never on a catalog this build can open -- but it cannot tell a baseline that moved forward from one that moved back, so a rollback across a baseline edit discards rather than refuses")
		cookieSec  = env.Bool("cookie-secure", "WAXDECK_COOKIE_SECURE", false, "mark session cookies Secure (set whenever the origin is HTTPS)")
		sessionCap = env.Int("session-cap", "WAXDECK_SESSION_CAP", auth.DefaultSessionCap, "live sign-in sessions one account may hold; signing in past it ends the least recently used")
		publicBase = fs.String("public-base", envOr("WAXDECK_PUBLIC_BASE", ""), "externally reachable base URL (needed for OIDC callbacks), e.g. https://wax.example.com")

		podcastDir      = fs.String("podcast-dir", envOr("WAXDECK_PODCAST_DIR", ""), "episode download directory (its own library, never inside a library root; defaults to <data-dir>/podcasts; an explicit empty, -podcast-dir=\"\" or WAXDECK_PODCAST_DIR set and empty, disables podcasts)")
		podcastRoot     = fs.String("podcast-root-name", envOr("WAXDECK_PODCAST_ROOT_NAME", "podcasts"), "WaxFlow root name the podcast dir is mounted under")
		feedRefreshMin  = env.Int("feed-refresh-minutes", "WAXDECK_FEED_REFRESH_MINUTES", 30, "minutes between scheduled feed refreshes")
		retentionKeep   = env.Int64("podcast-retention-default", "WAXDECK_PODCAST_RETENTION_DEFAULT", 0, "default keep-newest-N downloaded episodes for subscribers who leave retention unset (0 keeps all)")
		allowPrivateNet = env.Bool("allow-private-feed-hosts", "WAXDECK_ALLOW_PRIVATE_FEED_HOSTS", false, "allow feeds and enclosures on private addresses (LAN-hosted feeds)")

		podpingOn      = env.Bool("podping", "WAXDECK_PODPING", false, "watch the Hive blockchain for Podping notifications, so a subscribed show whose host publishes them refreshes within seconds of a new episode instead of at the next scheduled refresh. Off by default: it is a standing outbound connection to a third-party public node. Scheduled refresh stays the floor either way")
		podpingNode    = fs.String("podping-node", envOr("WAXDECK_PODPING_NODE", ""), "Hive API node the Podping watcher reads (empty selects a public node)")
		podpingWriters = fs.String("podping-writers", envOr("WAXDECK_PODPING_WRITERS", ""), "trusted Podping writer accounts, comma separated. Empty (the default) resolves the published podping.cloud writer set from the chain, which is how it is meant to be read; a list here pins it instead")

		allowPrivateRadio    = env.Bool("allow-private-radio-hosts", "WAXDECK_ALLOW_PRIVATE_RADIO_HOSTS", false, "allow radio stream URLs on private addresses (LAN icecast)")
		allowPrivateScrobble = env.Bool("allow-private-scrobble-hosts", "WAXDECK_ALLOW_PRIVATE_SCROBBLE_HOSTS", false, "allow ListenBrainz-compatible API bases on private addresses (LAN Maloja)")
		allowPrivateNotify   = env.Bool("allow-private-notify-hosts", "WAXDECK_ALLOW_PRIVATE_NOTIFY_HOSTS", false, "allow user-pointed notification destinations on private addresses (LAN ntfy or Gotify)")
		radioDirBase         = fs.String("radio-directory-base", envOr("WAXDECK_RADIO_DIRECTORY_BASE", ""), "radio-browser directory API base URL (empty selects the public instance)")
		podcastDirBase       = fs.String("podcast-directory-base", envOr("WAXDECK_PODCAST_DIRECTORY_BASE", ""), "podcast name-search API base URL (empty selects the public iTunes search endpoint)")
		lastfmKey            = fs.String("lastfm-api-key", envOr("WAXDECK_LASTFM_API_KEY", ""), "Last.fm API key for outbound scrobbling (empty leaves Last.fm unavailable)")
		lastfmSecret         = fs.String("lastfm-secret", envOr("WAXDECK_LASTFM_SECRET", ""), "Last.fm API shared secret")

		youtubeOn    = env.Bool("youtube", "WAXDECK_YOUTUBE", true, "the YouTube acquisition bridge (download videos, playlists, and channels; subscribe to channels as podcasts). On by default; set WAXDECK_YOUTUBE=false to disable")
		sealURL      = fs.String("seal-url", envOr("WAXDECK_SEAL_URL", ""), "WaxSeal attestation sidecar base URL (optional; full-quality YouTube path)")
		sealKey      = fs.String("seal-api-key", envOr("WAXDECK_SEAL_API_KEY", ""), "API key for the WaxSeal sidecar")
		sponsorBlock = fs.String("youtube-sponsorblock", envOr("WAXDECK_YOUTUBE_SPONSORBLOCK", ""), "SponsorBlock categories to cut from acquired audio, comma separated (default sponsor,music_offtopic; empty disables)")
		ytThumbnail  = env.Bool("youtube-thumbnail", "WAXDECK_YOUTUBE_THUMBNAIL", true, "embed the source thumbnail as cover art on acquired audio, cropped to its square where the source is letterboxed release art, until enrichment finds official artwork. On by default; set WAXDECK_YOUTUBE_THUMBNAIL=false to disable")
		sourceStub   = fs.String("source-stub-url", envOr("WAXDECK_SOURCE_STUB_URL", ""), "base URL of a sourceserv fixture host to use as the acquisition source (test stacks only; never production)")

		advertiseBase = fs.String("advertise-base", envOr("WAXDECK_ADVERTISE_BASE", ""), "plain-HTTP LAN base URL cast devices fetch media from (empty auto-detects the LAN address)")
		castDiscovery = env.Bool("cast-discovery", "WAXDECK_CAST_DISCOVERY", true, "discover Chromecast and DLNA devices on the LAN (mDNS and SSDP)")
		castDevices   = fs.String("cast-devices", envOr("WAXDECK_CAST_DEVICES", ""), "static cast devices as name=host:port pairs, comma separated (networks without multicast)")
		dlnaDevices   = fs.String("dlna-devices", envOr("WAXDECK_DLNA_DEVICES", ""), "static DLNA renderer description URLs, comma separated")
		jukeboxOn     = env.Bool("jukebox", "WAXDECK_JUKEBOX", false, "play out the server's own audio device as a selectable endpoint (needs the streaming engine)")
		jukeboxCmd    = fs.String("jukebox-cmd", envOr("WAXDECK_JUKEBOX_CMD", ""), "player command the jukebox pipes WAV into (default aplay; PipeWire hosts use pw-cat -p -)")
		jukeboxName   = fs.String("jukebox-name", envOr("WAXDECK_JUKEBOX_NAME", "Server audio"), "display name of the jukebox endpoint")

		managedRoots = fs.String("managed-roots", envOr("WAXDECK_MANAGED_ROOTS", ""), "library root names (comma separated) the catalog may place files into: uploads import there and the organizer may move files there; unlisted roots stay strictly in place")
		bookRoots    = fs.String("audiobook-roots", envOr("WAXDECK_AUDIOBOOK_ROOTS", ""), "library root names (comma separated) that hold audiobooks: every audio file in them is cataloged as a book; unlisted roots hold whatever they were set to, mixed when new")
		watchRoots   = env.Bool("library-watch", "WAXDECK_LIBRARY_WATCH", true, "watch the library roots and catalog files placed there by hand without waiting for a rescan. On by default; set WAXDECK_LIBRARY_WATCH=false to disable. Network mounts (NFS, SMB, 9p) rarely deliver change events; enable the scan schedule there instead")

		uploadFormats = fs.String("upload-formats", envOr("WAXDECK_UPLOAD_FORMATS", ""), "file extensions uploads accept, comma separated. Replaces the default set rather than extending it; empty keeps the default (every format the catalog scans and the decode stack reads). DRM containers (aax, aaxc) are refused regardless")

		matchingOn   = env.Bool("matching", "WAXDECK_MATCHING", true, "identify new and uploaded music against MusicBrainz (paced background lookups)")
		mbBase       = fs.String("musicbrainz-base", envOr("WAXDECK_MUSICBRAINZ_BASE", ""), "MusicBrainz API base override for matching, the ISRC upgrade and radio artwork (a local mirror, or a stub in tests); the enrichment pass always asks the public service")
		coverArtBase = fs.String("coverart-base", envOr("WAXDECK_COVERART_BASE", ""), "Cover Art Archive base override for radio artwork (a mirror, or a stub in tests); that rung only exists when matching is on, and the enrichment pass always asks the public archive")
		trustedProxy = fs.String("trusted-proxies", envOr("WAXDECK_TRUSTED_PROXIES", ""), "comma-separated CIDRs or addresses of reverse proxies whose X-Forwarded-For may be believed; empty counts the socket address")
		corsOrigins  = fs.String("cors-origins", envOr("WAXDECK_CORS_ORIGINS", ""), "comma-separated origins allowed to call this server from a browser on another origin (a self-hosted Feishin, say); empty serves same-origin only")
		acoustidKey  = fs.String("acoustid-key", envOr("WAXDECK_ACOUSTID_KEY", ""), "AcoustID API key; empty disables fingerprint evidence in matching")
		fanartKey    = fs.String("fanarttv-key", envOr("WAXDECK_FANARTTV_KEY", ""), "fanart.tv API key; empty leaves that artwork provider unconfigured")

		discogsToken   = fs.String("discogs-token", envOr("WAXDECK_DISCOGS_TOKEN", ""), "Discogs personal access token; empty leaves that artwork and genre provider unconfigured")
		hardcoverKey   = fs.String("hardcover-key", envOr("WAXDECK_HARDCOVER_KEY", ""), "Hardcover API token; empty leaves that audiobook provider unconfigured")
		googleBooksKey = fs.String("google-books-key", envOr("WAXDECK_GOOGLE_BOOKS_KEY", ""), "Google Books API key; optional - the provider works keyless and a key only raises the quota")

		enrichURLs = fs.String("enrich-provider-urls", envOr("WAXDECK_ENRICH_PROVIDER_URLS", ""), "custom enrichment providers as name=url pairs, comma separated, each implementing the contract in docs/custom-provider-api/. Validated at startup (the capabilities document must answer and advertise a name) and asked first, ahead of the providers WaxDeck ships; once an administrator has saved an order, one wired later joins its end until it is moved")
		enrichAuth = fs.String("enrich-provider-auth", envOr("WAXDECK_ENRICH_PROVIDER_AUTH", ""), "bearer tokens for custom enrichment providers as name=token pairs, comma separated; names must match -enrich-provider-urls")

		artistArtOn = env.Bool("artist-art", "WAXDECK_ARTIST_ART", true, "fill missing artist portraits during enrichment. The catalog's artist walk asks fanart.tv by MusicBrainz id where its key is set, and Deezer by name for every artist including the ones MusicBrainz never matched. On by default; set WAXDECK_ARTIST_ART=false and the providers stop advertising artist art, so the walk never asks either service for one")

		enrichContact = fs.String("enrichment-contact", envOr("WAXDECK_ENRICHMENT_CONTACT", ""), "MusicBrainz contact (an email or a URL) the catalog's enrichment pass identifies itself with. MusicBrainz requires an identifying agent, so empty leaves the identity phases and the catalog's key-free sources (the Cover Art Archive, MusicBrainz and ListenBrainz genres, LRCLIB lyrics) off; the phases WaxDeck's own providers serve still run")
		enrichMatch   = env.Bool("enrichment-match-releases", "WAXDECK_ENRICHMENT_MATCH_RELEASES", true, "during enrichment, resolve which pressing of a record the library holds from its barcode or catalog number, deciding ties on medium and country. On by default; needs -enrichment-contact to have any effect")
		enrichRetry   = env.Int("enrichment-retry-misses-days", "WAXDECK_ENRICHMENT_RETRY_MISSES_DAYS", 30, "days a target nothing answered for waits before an enrichment pass asks about it again, so a source that has since learned it is reached; 0 never asks again. A match is never re-asked")

		oidcIssuer  = fs.String("oidc-issuer", envOr("WAXDECK_OIDC_ISSUER", ""), "OIDC issuer URL (empty disables single sign-on)")
		oidcID      = fs.String("oidc-id", envOr("WAXDECK_OIDC_ID", "sso"), "OIDC provider id shown in start URLs")
		oidcName    = fs.String("oidc-name", envOr("WAXDECK_OIDC_NAME", ""), "OIDC provider display name for login buttons")
		oidcClient  = fs.String("oidc-client-id", envOr("WAXDECK_OIDC_CLIENT_ID", ""), "OIDC client id")
		oidcSecret  = fs.String("oidc-client-secret", envOr("WAXDECK_OIDC_CLIENT_SECRET", ""), "OIDC client secret")
		oidcGroups  = fs.String("oidc-groups-claim", envOr("WAXDECK_OIDC_GROUPS_CLAIM", ""), "ID-token claim holding groups (empty disables role mapping)")
		oidcAdminGr = fs.String("oidc-admin-group", envOr("WAXDECK_OIDC_ADMIN_GROUP", ""), "group granting the admin role via the groups claim")

		metricsToken = fs.String("metrics-token", envOr("WAXDECK_METRICS_TOKEN", ""), "bearer token protecting GET /metrics (empty leaves the endpoint disabled)")

		sonicAnalysis    = env.Bool("sonic-analysis", "WAXDECK_SONIC_ANALYSIS", true, "boot default for background sonic-similarity analysis (embedded analyzer; powers instant mixes, similar tracks, and sonic paths). On by default; administrators toggle it at runtime in the server settings")
		workerTokens     = fs.String("worker-tokens", envOr("WAXDECK_WORKER_TOKENS", ""), "external similarity worker tokens, comma separated (optional; offloads analysis to another machine through the worker API)")
		workerLocalPaths = env.Bool("worker-local-paths", "WAXDECK_WORKER_LOCAL_PATHS", false, "expose library-relative source paths to similarity workers that mount the library read-only (single-root libraries)")

		showVer     = fs.Bool("version", false, "print version and exit")
		showNotices = fs.Bool("third-party-notices", false, "print the third-party license notices bundled in this binary and exit")
		ping        = fs.Bool("ping", false, "probe the health endpoint of the server listening on -addr and exit 0 when it answers (the container HEALTHCHECK)")
	)
	if err := fs.Parse(args); err != nil {
		return nil, err
	}

	cfg := &config{
		core: coreConfig{
			addr:           *addr,
			webDir:         *webDir,
			dataDir:        *dataDir,
			scanOnStart:    *scanStart,
			resetCatalog:   *resetStale,
			cookieSecure:   *cookieSec,
			publicBase:     *publicBase,
			trustedProxies: *trustedProxy,
			corsOrigins:    *corsOrigins,
			metricsToken:   *metricsToken,
		},
		streaming: streamingConfig{
			flowURL:    *flowURL,
			flowAPIKey: *flowAPIKey,
			flowConfig: *flowConfig,
		},
		podcasts: podcastsConfig{
			dir:                podcastDirFrom(*podcastDir, flagWasSet(fs, "podcast-dir"), lookupEnv, *dataDir),
			rootName:           *podcastRoot,
			feedRefreshMinutes: *feedRefreshMin,
			retentionKeep:      *retentionKeep,
			allowPrivateHosts:  *allowPrivateNet,
			podping: podpingConfig{
				on:      *podpingOn,
				node:    *podpingNode,
				writers: *podpingWriters,
			},
			directoryBase: *podcastDirBase,
		},
		radio: radioConfig{
			allowPrivateHosts: *allowPrivateRadio,
			directoryBase:     *radioDirBase,
		},
		scrobble: scrobbleConfig{
			allowPrivateScrobbleHosts: *allowPrivateScrobble,
			allowPrivateNotifyHosts:   *allowPrivateNotify,
			lastfmKey:                 *lastfmKey,
			lastfmSecret:              *lastfmSecret,
		},
		acquisition: acquisitionConfig{
			youtube:      *youtubeOn,
			sealURL:      *sealURL,
			sealKey:      *sealKey,
			sponsorBlock: sponsorBlockFrom(*sponsorBlock, flagWasSet(fs, "youtube-sponsorblock"), lookupEnv),
			ytThumbnail:  *ytThumbnail,
			stubSource:   *sourceStub,
		},
		casting: castingConfig{
			advertiseBase: *advertiseBase,
			discovery:     *castDiscovery,
			devices:       *castDevices,
			dlnaDevices:   *dlnaDevices,
			jukebox:       *jukeboxOn,
			jukeboxCmd:    *jukeboxCmd,
			jukeboxName:   *jukeboxName,
		},
		roots: rootsConfig{
			managed:       *managedRoots,
			audiobook:     *bookRoots,
			watch:         *watchRoots,
			uploadFormats: *uploadFormats,
		},
		matching: matchingConfig{
			on:              *matchingOn,
			musicBrainzBase: *mbBase,
			coverArtBase:    *coverArtBase,
			acoustIDKey:     *acoustidKey,
			fanartTVKey:     *fanartKey,
			discogsToken:    *discogsToken,
			hardcoverKey:    *hardcoverKey,
			googleBooksKey:  *googleBooksKey,
			enrichURLs:      *enrichURLs,
			enrichAuth:      *enrichAuth,
			artistArt:       *artistArtOn,
			enrichContact:   *enrichContact,
			enrichMatch:     *enrichMatch,
		},
		oidc: oidcConfig{
			issuer:       *oidcIssuer,
			id:           *oidcID,
			name:         *oidcName,
			clientID:     *oidcClient,
			clientSecret: *oidcSecret,
			groupsClaim:  *oidcGroups,
			adminGroup:   *oidcAdminGr,
		},
		similarity: similarityConfig{
			sonicAnalysis:    *sonicAnalysis,
			workerTokens:     splitNonEmpty(*workerTokens, ","),
			workerLocalPaths: *workerLocalPaths,
		},
		showVersion: *showVer,
		ping:        *ping,
		showNotices: *showNotices,
	}
	// A mode answers whatever the rest of the settings say.
	if cfg.showVersion || cfg.ping || cfg.showNotices {
		return cfg, nil
	}
	if err := env.Err(); err != nil {
		return nil, err
	}
	var err error
	if cfg.matching.enrichRetryDays, err = enrichRetryWindow(*enrichRetry); err != nil {
		return nil, err
	}
	if cfg.core.sessionCap, err = sessionCapFrom(*sessionCap); err != nil {
		return nil, err
	}
	if cfg.core.libraryRoots, err = parseRoots(*rootsFlag); err != nil {
		return nil, err
	}
	return cfg, nil
}

// root is one parsed name=path pair.
type root struct {
	Name string
	Path string
}

// parseRoots parses "name=path,name2=path2". Names must match the
// WaxFlow roots that mount the same directories, since stream requests
// address sources as name/relpath.
func parseRoots(s string) ([]root, error) {
	if strings.TrimSpace(s) == "" {
		return nil, nil
	}
	var roots []root
	for part := range strings.SplitSeq(s, ",") {
		name, path, ok := strings.Cut(strings.TrimSpace(part), "=")
		if !ok || name == "" || path == "" {
			return nil, fmt.Errorf("bad library root %q: want name=path", part)
		}
		abs, err := filepath.Abs(path)
		if err != nil {
			return nil, fmt.Errorf("bad library root %q: %w", part, err)
		}
		roots = append(roots, root{Name: name, Path: abs})
	}
	return roots, nil
}

// podcastDirFrom resolves the podcast directory. Podcasts work out of
// the box: with nothing said the dir lands beside the databases. Only an
// explicit empty, -podcast-dir="" or WAXDECK_PODCAST_DIR set and empty,
// turns podcasts off; the flag default is empty so the env fallback
// stays expressible, hence asking whether either was set at all.
func podcastDirFrom(value string, flagSet bool, lookupEnv func(string) (string, bool), dataDir string) string {
	if value != "" || flagSet {
		return value
	}
	if _, set := lookupEnv("WAXDECK_PODCAST_DIR"); set {
		return ""
	}
	return filepath.Join(dataDir, "podcasts")
}

// sponsorBlockFrom resolves the SponsorBlock categories cut from acquired
// audio: the flag when given, else the variable when set (empty turns
// cutting off), else sponsors and non-music sections.
func sponsorBlockFrom(value string, flagSet bool, lookupEnv func(string) (string, bool)) []string {
	if !flagSet {
		if v, set := lookupEnv("WAXDECK_YOUTUBE_SPONSORBLOCK"); set {
			value = v
		} else {
			value = "sponsor,music_offtopic"
		}
	}
	var out []string
	for c := range strings.SplitSeq(value, ",") {
		if c = strings.TrimSpace(c); c != "" {
			out = append(out, c)
		}
	}
	return out
}

// splitNonEmpty splits on sep, trims each part, and drops empties.
func splitNonEmpty(s, sep string) []string {
	var out []string
	for _, part := range strings.Split(s, sep) {
		if part = strings.TrimSpace(part); part != "" {
			out = append(out, part)
		}
	}
	return out
}

// flagWasSet reports whether the named flag appeared on the command
// line (distinguishing an explicit empty value from the default).
func flagWasSet(fs *flag.FlagSet, name string) bool {
	set := false
	fs.Visit(func(f *flag.Flag) {
		if f.Name == name {
			set = true
		}
	})
	return set
}

// maxRetryDays is the longest miss window a Duration holds; past it the
// catalog's day count wraps to a short window.
const maxRetryDays = int(math.MaxInt64 / int64(24*time.Hour))

// enrichRetryWindow refuses a negative miss window, which the catalog
// would silently read as never, and one too long to hold.
func enrichRetryWindow(days int) (*int, error) {
	if days < 0 || days > maxRetryDays {
		return nil, fmt.Errorf("WAXDECK_ENRICHMENT_RETRY_MISSES_DAYS is %d; want at most %d days, or 0 to never ask again", days, maxRetryDays)
	}
	return &days, nil
}

// sessionCapFrom refuses a cap below one, which would otherwise read as
// the default: there is no "no cap", since every sign-in adds a row.
func sessionCapFrom(n int) (int, error) {
	if n < 1 {
		return 0, fmt.Errorf("WAXDECK_SESSION_CAP is %d; want at least 1", n)
	}
	return n, nil
}
