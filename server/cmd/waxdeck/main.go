// Command waxdeck runs the WaxDeck server: the /api/v1 REST surface,
// the /media streaming surface, and the embedded web UI, on one origin
// (default :4420). It embeds the WaxBin catalog read-write, owning its
// write lock for the process lifetime, and reverse-proxies streams
// through the WaxFlow sidecar.
package main

import (
	"context"
	"crypto/subtle"
	"database/sql"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
	// Timezone validation for user preferences must work in scratch
	// containers with no zoneinfo on disk.
	_ "time/tzdata"

	"github.com/colespringer/waxbin/enrich"
	"github.com/colespringer/waxbin/source"

	"github.com/colespringer/waxdeck/server/internal/adapter/gpodder"
	"github.com/colespringer/waxdeck/server/internal/adapter/subsonic"
	"github.com/colespringer/waxdeck/server/internal/analyzer"
	"github.com/colespringer/waxdeck/server/internal/api"
	"github.com/colespringer/waxdeck/server/internal/auth"
	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
	"github.com/colespringer/waxdeck/server/internal/cast/castv2"
	"github.com/colespringer/waxdeck/server/internal/cast/dlna"
	"github.com/colespringer/waxdeck/server/internal/cast/jukebox"
	"github.com/colespringer/waxdeck/server/internal/connect"
	"github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/events"
	"github.com/colespringer/waxdeck/server/internal/metrics"
	waxproviders "github.com/colespringer/waxdeck/server/internal/providers"
	"github.com/colespringer/waxdeck/server/internal/restore"
	"github.com/colespringer/waxdeck/server/internal/service"
	"github.com/colespringer/waxdeck/server/internal/supervise"
	"github.com/colespringer/waxdeck/server/internal/waxtapsource"
	"github.com/colespringer/waxdeck/server/internal/web"
)

// version is stamped by the release build (-ldflags "-X main.version=x.y.z").
var version = "0.1.0-dev"

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "waxdeck:", err)
		os.Exit(1)
	}
}

func run() error {
	var (
		addr       = flag.String("addr", envOr("WAXDECK_ADDR", ":4420"), "listen address")
		webDir     = flag.String("web-dir", envOr("WAXDECK_WEB_DIR", ""), "serve the web UI from this directory instead of the embedded build (dev)")
		dataDir    = flag.String("data-dir", envOr("WAXDECK_DATA_DIR", "./data"), "data directory (waxbin.db + waxdeck.db)")
		rootsFlag  = flag.String("library-roots", envOr("WAXDECK_LIBRARY_ROOTS", ""), "library roots as name=path pairs, comma separated; names must match the WaxFlow roots serving the same directories")
		flowURL    = flag.String("flow-url", envOr("WAXDECK_FLOW_URL", ""), "WaxFlow sidecar base URL (empty disables streaming)")
		flowAPIKey = flag.String("flow-api-key", envOr("WAXDECK_FLOW_API_KEY", ""), "API key WaxDeck presents to the WaxFlow sidecar")
		flowConfig = flag.String("flow-config", envOr("WAXDECK_FLOW_CONFIG", ""), "the WaxFlow sidecar's JSON config file, as WaxDeck sees it; set it (and point the sidecar at the same file) so a library created at runtime streams without a sidecar restart")
		scanStart  = flag.Bool("scan-on-start", envOr("WAXDECK_SCAN_ON_START", "true") == "true", "launch a library scan at startup")
		cookieSec  = flag.Bool("cookie-secure", envOr("WAXDECK_COOKIE_SECURE", "false") == "true", "mark session cookies Secure (set whenever the origin is HTTPS)")
		publicBase = flag.String("public-base", envOr("WAXDECK_PUBLIC_BASE", ""), "externally reachable base URL (needed for OIDC callbacks), e.g. https://wax.example.com")

		podcastDir      = flag.String("podcast-dir", envOr("WAXDECK_PODCAST_DIR", ""), "episode download directory (its own library, never inside a library root; defaults to <data-dir>/podcasts, explicit empty via -podcast-dir=\"\" disables podcasts)")
		podcastRoot     = flag.String("podcast-root-name", envOr("WAXDECK_PODCAST_ROOT_NAME", "podcasts"), "WaxFlow root name the podcast dir is mounted under")
		feedRefreshMin  = flag.Int("feed-refresh-minutes", envIntOr("WAXDECK_FEED_REFRESH_MINUTES", 30), "minutes between scheduled feed refreshes")
		retentionKeep   = flag.Int64("podcast-retention-default", envInt64Or("WAXDECK_PODCAST_RETENTION_DEFAULT", 0), "default keep-newest-N downloaded episodes for subscribers who leave retention unset (0 keeps all)")
		allowPrivateNet = flag.Bool("allow-private-feed-hosts", envOr("WAXDECK_ALLOW_PRIVATE_FEED_HOSTS", "false") == "true", "allow feeds and enclosures on private addresses (LAN-hosted feeds)")

		allowPrivateRadio    = flag.Bool("allow-private-radio-hosts", envOr("WAXDECK_ALLOW_PRIVATE_RADIO_HOSTS", "false") == "true", "allow radio stream URLs on private addresses (LAN icecast)")
		allowPrivateScrobble = flag.Bool("allow-private-scrobble-hosts", envOr("WAXDECK_ALLOW_PRIVATE_SCROBBLE_HOSTS", "false") == "true", "allow ListenBrainz-compatible API bases on private addresses (LAN Maloja)")
		allowPrivateNotify   = flag.Bool("allow-private-notify-hosts", envOr("WAXDECK_ALLOW_PRIVATE_NOTIFY_HOSTS", "false") == "true", "allow user-pointed notification destinations on private addresses (LAN ntfy or Gotify)")
		radioDirBase         = flag.String("radio-directory-base", envOr("WAXDECK_RADIO_DIRECTORY_BASE", ""), "radio-browser directory API base URL (empty selects the public instance)")
		lastfmKey            = flag.String("lastfm-api-key", envOr("WAXDECK_LASTFM_API_KEY", ""), "Last.fm API key for outbound scrobbling (empty leaves Last.fm unavailable)")
		lastfmSecret         = flag.String("lastfm-secret", envOr("WAXDECK_LASTFM_SECRET", ""), "Last.fm API shared secret")

		youtubeOn    = flag.Bool("youtube", envOr("WAXDECK_YOUTUBE", "true") == "true", "the YouTube acquisition bridge (download videos, playlists, and channels; subscribe to channels as podcasts). On by default; set WAXDECK_YOUTUBE=false to disable")
		sealURL      = flag.String("seal-url", envOr("WAXDECK_SEAL_URL", ""), "WaxSeal attestation sidecar base URL (optional; full-quality YouTube path)")
		sealKey      = flag.String("seal-api-key", envOr("WAXDECK_SEAL_API_KEY", ""), "API key for the WaxSeal sidecar")
		sponsorBlock = flag.String("youtube-sponsorblock", envOr("WAXDECK_YOUTUBE_SPONSORBLOCK", ""), "SponsorBlock categories to cut from acquired audio, comma separated (empty disables)")
		ytThumbnail  = flag.Bool("youtube-thumbnail", envOr("WAXDECK_YOUTUBE_THUMBNAIL", "true") == "true", "embed the source thumbnail as cover art on acquired audio, until enrichment finds official artwork. On by default; set WAXDECK_YOUTUBE_THUMBNAIL=false to disable")

		advertiseBase = flag.String("advertise-base", envOr("WAXDECK_ADVERTISE_BASE", ""), "plain-HTTP LAN base URL cast devices fetch media from (empty auto-detects the LAN address)")
		castDiscovery = flag.Bool("cast-discovery", envOr("WAXDECK_CAST_DISCOVERY", "true") == "true", "discover Chromecast and DLNA devices on the LAN (mDNS and SSDP)")
		castDevices   = flag.String("cast-devices", envOr("WAXDECK_CAST_DEVICES", ""), "static cast devices as name=host:port pairs, comma separated (networks without multicast)")
		dlnaDevices   = flag.String("dlna-devices", envOr("WAXDECK_DLNA_DEVICES", ""), "static DLNA renderer description URLs, comma separated")
		jukeboxOn     = flag.Bool("jukebox", envOr("WAXDECK_JUKEBOX", "false") == "true", "play out the server's own audio device as a selectable endpoint (needs the streaming engine)")
		jukeboxCmd    = flag.String("jukebox-cmd", envOr("WAXDECK_JUKEBOX_CMD", ""), "player command the jukebox pipes WAV into (default aplay; PipeWire hosts use pw-cat -p -)")
		jukeboxName   = flag.String("jukebox-name", envOr("WAXDECK_JUKEBOX_NAME", "Server audio"), "display name of the jukebox endpoint")

		managedRoots = flag.String("managed-roots", envOr("WAXDECK_MANAGED_ROOTS", ""), "library root names (comma separated) the catalog may place files into: uploads import there and the organizer may move files there; unlisted roots stay strictly in place")

		matchingOn  = flag.Bool("matching", envOr("WAXDECK_MATCHING", "true") == "true", "identify new and uploaded music against MusicBrainz (paced background lookups)")
		mbBase      = flag.String("musicbrainz-base", envOr("WAXDECK_MUSICBRAINZ_BASE", ""), "MusicBrainz API base override (a local mirror, or a stub in tests)")
		acoustidKey = flag.String("acoustid-key", envOr("WAXDECK_ACOUSTID_KEY", ""), "AcoustID API key; empty disables fingerprint evidence in matching")
		fanartKey   = flag.String("fanarttv-key", envOr("WAXDECK_FANARTTV_KEY", ""), "fanart.tv API key; empty leaves that artwork provider unconfigured")

		oidcIssuer  = flag.String("oidc-issuer", envOr("WAXDECK_OIDC_ISSUER", ""), "OIDC issuer URL (empty disables single sign-on)")
		oidcID      = flag.String("oidc-id", envOr("WAXDECK_OIDC_ID", "sso"), "OIDC provider id shown in start URLs")
		oidcName    = flag.String("oidc-name", envOr("WAXDECK_OIDC_NAME", ""), "OIDC provider display name for login buttons")
		oidcClient  = flag.String("oidc-client-id", envOr("WAXDECK_OIDC_CLIENT_ID", ""), "OIDC client id")
		oidcSecret  = flag.String("oidc-client-secret", envOr("WAXDECK_OIDC_CLIENT_SECRET", ""), "OIDC client secret")
		oidcGroups  = flag.String("oidc-groups-claim", envOr("WAXDECK_OIDC_GROUPS_CLAIM", ""), "ID-token claim holding groups (empty disables role mapping)")
		oidcAdminGr = flag.String("oidc-admin-group", envOr("WAXDECK_OIDC_ADMIN_GROUP", ""), "group granting the admin role via the groups claim")

		metricsToken = flag.String("metrics-token", envOr("WAXDECK_METRICS_TOKEN", ""), "bearer token protecting GET /metrics (empty leaves the endpoint disabled)")

		sonicAnalysis    = flag.Bool("sonic-analysis", envOr("WAXDECK_SONIC_ANALYSIS", "true") == "true", "boot default for background sonic-similarity analysis (embedded analyzer; powers instant mixes, similar tracks, and sonic paths). On by default; administrators toggle it at runtime in the server settings")
		workerTokens     = flag.String("worker-tokens", envOr("WAXDECK_WORKER_TOKENS", ""), "external similarity worker tokens, comma separated (optional; offloads analysis to another machine through the worker API)")
		workerLocalPaths = flag.Bool("worker-local-paths", envOr("WAXDECK_WORKER_LOCAL_PATHS", "false") == "true", "expose library-relative source paths to similarity workers that mount the library read-only (single-root libraries)")

		showVer = flag.Bool("version", false, "print version and exit")
	)
	flag.Parse()

	if *showVer {
		fmt.Println(version)
		return nil
	}

	log := slog.New(slog.NewTextHandler(os.Stderr, nil))
	roots, err := parseRoots(*rootsFlag)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(*dataDir, 0o755); err != nil {
		return fmt.Errorf("creating data dir: %w", err)
	}

	// A staged restore applies before anything opens a database: the
	// marker survives any failure here, so a crash retries at the next
	// start and a refusing error leaves the operator in charge.
	restoreCasualties := stagedCasualties(*dataDir)
	restoreApplied, restoreReport, err := restore.Apply(*dataDir, log)
	if err != nil {
		return fmt.Errorf("applying staged restore: %w", err)
	}
	if restoreApplied {
		log.Info("restore applied", "backup", restoreReport.BackupID, "archive", restoreReport.FileName)
	}

	// Root context: canceled on the first termination signal; workers and
	// the IPC server unwind from it.
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	group := supervise.NewGroup(log)

	secret, err := auth.LoadOrCreateSecret(*dataDir)
	if err != nil {
		return err
	}

	store, err := db.Open(ctx, filepath.Join(*dataDir, "waxdeck.db"))
	if err != nil {
		return err
	}
	defer store.Close()
	if restoreApplied {
		// Fresh stream generations mint at open; every outstanding
		// client cursor answers sync-reset instead of silently reading
		// the restored history.
		if err := store.ClearSyncState(ctx); err != nil {
			return err
		}
	}
	if n, err := store.FailStaleRunningBackups(ctx, time.Now().UnixNano()); err != nil {
		log.Warn("sweeping stale backups", "err", err)
	} else if n > 0 {
		log.Info("marked interrupted backups failed", "count", n)
	}

	sealer, err := auth.NewSealer(secret, "waxdeck-app-password-v1")
	if err != nil {
		return err
	}
	// Catalog-held secrets (private-feed passwords) seal under their own
	// subkey; the catalog binds each secret's key as AAD.
	catalogCipher, err := auth.NewAADSealer(secret, "waxdeck-catalog-secret-v1")
	if err != nil {
		return err
	}

	managed := map[string]bool{}
	for name := range strings.SplitSeq(*managedRoots, ",") {
		if name = strings.TrimSpace(name); name != "" {
			managed[name] = true
		}
	}
	svcRoots := make([]service.Root, len(roots))
	for i, r := range roots {
		svcRoots[i] = service.Root{Name: r.Name, Path: r.Path, Managed: managed[r.Name]}
		delete(managed, r.Name)
	}
	if len(managed) > 0 {
		for name := range managed {
			return fmt.Errorf("WAXDECK_MANAGED_ROOTS names %q, which is not a configured library root", name)
		}
	}
	// Podcasts work out of the box: an unset dir lands beside the
	// databases. Only an explicit -podcast-dir="" disables the surface
	// (the flag default is empty so the env fallback stays expressible,
	// hence the isSet probe rather than a non-empty flag default).
	if *podcastDir == "" && !flagWasSet("podcast-dir") && os.Getenv("WAXDECK_PODCAST_DIR") == "" {
		*podcastDir = filepath.Join(*dataDir, "podcasts")
	}
	if *podcastDir != "" {
		abs, err := filepath.Abs(*podcastDir)
		if err != nil {
			return fmt.Errorf("bad podcast dir: %w", err)
		}
		*podcastDir = abs
		if err := os.MkdirAll(abs, 0o755); err != nil {
			return fmt.Errorf("creating podcast dir: %w", err)
		}
	}
	var providers []source.Provider
	if *youtubeOn {
		var categories []string
		if strings.TrimSpace(*sponsorBlock) != "" {
			for c := range strings.SplitSeq(*sponsorBlock, ",") {
				categories = append(categories, strings.TrimSpace(c))
			}
		}
		yt, err := waxtapsource.New(waxtapsource.Config{
			WorkDir:        filepath.Join(*dataDir, "waxtap-work"),
			SealBaseURL:    *sealURL,
			SealAPIKey:     *sealKey,
			SponsorBlock:   categories,
			EmbedThumbnail: *ytThumbnail,
			EmbedMetadata:  true,
			Logger:         log,
		})
		if err != nil {
			// The bridge is on by default, so a construction hiccup
			// degrades acquisition rather than downing the server; the
			// rest of the catalog is unaffected. Set WAXDECK_YOUTUBE=false
			// to opt out entirely.
			log.Warn("youtube acquisition bridge unavailable; URL downloads are disabled", "err", err)
		} else {
			providers = append(providers, yt)
			log.Info("youtube acquisition bridge enabled", "seal", *sealURL != "")
		}
		// The bridge serves two independent paths: subscribing a
		// channel or playlist as a podcast (episodes land in the
		// podcast library) and acquiring a video, playlist, or channel
		// into a music or audiobook library by URL. Only the former
		// needs the podcast library, so its absence is a warning, not
		// a refusal: URL acquisition still works.
		if *podcastDir == "" {
			log.Warn("youtube podcast subscriptions are unavailable without a podcast library; URL acquisition to music and audiobook libraries still works")
		}
	}

	// The matching engine's candidate source and the server's own
	// enrichment providers. Key-free providers are always registered;
	// keyed ones only when configured. All are paced and cached.
	var matchSource *waxproviders.Source
	if *matchingOn {
		matchSource = &waxproviders.Source{
			MB: waxproviders.NewMusicBrainz(waxproviders.MusicBrainzConfig{BaseURL: *mbBase}),
			Acoust: waxproviders.NewAcoustID(waxproviders.AcoustIDConfig{
				APIKey: *acoustidKey,
			}),
		}
	}
	enrichProviders := []enrich.Provider{
		waxproviders.NewDeezer(waxproviders.DeezerConfig{}),
		waxproviders.NewITunes(waxproviders.ITunesConfig{}),
		waxproviders.NewAudnexus(waxproviders.AudnexusConfig{}),
	}
	if *fanartKey != "" {
		enrichProviders = append([]enrich.Provider{
			waxproviders.NewFanartTV(waxproviders.FanartTVConfig{APIKey: *fanartKey}),
		}, enrichProviders...)
	}

	workerTokenList := splitNonEmpty(*workerTokens, ",")
	svcCfg := service.Config{
		DataDir:                   *dataDir,
		WorkerLocalPaths:          *workerLocalPaths,
		SonicAnalysisDefault:      *sonicAnalysis,
		WorkerAPIConfigured:       len(workerTokenList) > 0,
		Roots:                     svcRoots,
		ScanOnStart:               *scanStart && len(roots) > 0,
		Sealer:                    sealer,
		SecretCipher:              catalogCipher,
		PodcastDir:                *podcastDir,
		PodcastRootName:           *podcastRoot,
		AllowPrivateFeedHosts:     *allowPrivateNet,
		DefaultRetentionKeep:      *retentionKeep,
		SourceProviders:           providers,
		AllowPrivateRadioHosts:    *allowPrivateRadio,
		AllowPrivateScrobbleHosts: *allowPrivateScrobble,
		AllowPrivateNotifyHosts:   *allowPrivateNotify,
		RadioDirectoryBase:        *radioDirBase,
		LastfmAPIKey:              *lastfmKey,
		LastfmSecret:              *lastfmSecret,
		EnrichmentProviders:       enrichProviders,
		Logger:                    log,
	}
	if matchSource != nil {
		svcCfg.MatchSource = matchSource
		// The playlist importer's ISRC upgrade rides the same paced,
		// cached MusicBrainz client as matching.
		svcCfg.ISRCResolver = matchSource.MB
	}
	svc, err := service.Open(ctx, svcCfg, store, group)
	if err != nil {
		return err
	}
	defer svc.Close()

	// The event hub fans the service's change wakeups out to WebSocket
	// subscribers as coalesced invalidation frames.
	hub := events.New(svc)
	group.Go(ctx, "event-hub", hub.Run)

	// One media-token instance signs both streaming and download URLs.
	media := auth.NewMediaTokens(secret, 0)

	// Share capability tokens derive from the same server secret;
	// nothing share-secret is stored at rest.
	shareTokens := auth.NewShareTokens(secret)

	// The similarity sweep keeps the analysis queue reconciled with the
	// catalog (new tracks enqueue, deleted audio prunes and backfills),
	// and the embedded analyzer drains that queue in process: sonic
	// similarity with zero setup, no second container (the server
	// already links the decoders through the catalog). Both loops
	// self-gate on the runtime admin setting, so administrators flip
	// analysis on and off without a restart; external workers remain
	// the offload path for installs that want analysis off this
	// machine.
	group.Go(ctx, "similarity-sweep", func(ctx context.Context) error {
		first := time.NewTimer(30 * time.Second)
		defer first.Stop()
		tick := time.NewTicker(10 * time.Minute)
		defer tick.Stop()
		for {
			select {
			case <-ctx.Done():
				return nil
			case <-first.C:
			case <-tick.C:
			}
			if _, err := svc.SimilaritySweep(ctx); err != nil {
				log.Warn("similarity sweep", "err", err)
			}
		}
	})
	group.Go(ctx, "embedded-analysis", func(ctx context.Context) error {
		an := analyzer.New()
		first := time.NewTimer(45 * time.Second)
		defer first.Stop()
		tick := time.NewTicker(30 * time.Second)
		defer tick.Stop()
		for {
			select {
			case <-ctx.Done():
				return nil
			case <-first.C:
			case <-tick.C:
			}
			for {
				worked, err := svc.DrainEmbeddedAnalysis(ctx, an)
				if err != nil {
					log.Warn("embedded analysis", "err", err)
					break
				}
				if !worked {
					break
				}
			}
		}
	})

	// Trash retention: purge trashed files older than the configured
	// window (0 disables it). Self-gates on the runtime admin setting so
	// administrators change the policy without a restart, and a slow
	// cadence is plenty for a space-reclaim pass.
	group.Go(ctx, "trash-retention", func(ctx context.Context) error {
		first := time.NewTimer(5 * time.Minute)
		defer first.Stop()
		tick := time.NewTicker(6 * time.Hour)
		defer tick.Stop()
		for {
			select {
			case <-ctx.Done():
				return nil
			case <-first.C:
			case <-tick.C:
			}
			rep, err := svc.SweepTrashRetention(ctx)
			if err != nil {
				log.Warn("trash retention sweep", "err", err)
				continue
			}
			if rep.Purged > 0 || rep.Errored > 0 {
				log.Info("trash retention sweep",
					"purged", rep.Purged, "errored", rep.Errored, "reclaimedBytes", rep.ReclaimedBytes)
			}
		}
	})

	// The WaxFlow bridge is optional in development: without it every
	// catalog surface works and play-info reports streaming unavailable.
	// When configured it validates against the live sidecar and fails
	// fast on a bad setup.
	var bridge *flow.Bridge
	if *flowURL != "" {
		flowRoots := make([]flow.Root, len(roots))
		for i, r := range roots {
			flowRoots[i] = flow.Root{Name: r.Name, Path: r.Path}
		}
		if *podcastDir != "" {
			// The podcast dir is its own root pair: the catalog refuses a
			// download dir inside a user root, and the sidecar streams
			// episodes only from a root it mounts.
			flowRoots = append(flowRoots, flow.Root{Name: *podcastRoot, Path: *podcastDir})
		}
		bridge, err = flow.New(ctx, flow.Config{
			BaseURL:    *flowURL,
			APIKey:     *flowAPIKey,
			Roots:      flowRoots,
			ConfigPath: *flowConfig,
			Tokens:     media,
			Resolver:   svc,
			Logger:     log,
		})
		if err != nil {
			return err
		}
		svc.SetFlowJobs(bridge)
		svc.SetFlowRoots(bridge)
		bridge.SetTranscodeGate(svc.TranscodeGate())
	} else {
		log.Warn("WAXDECK_FLOW_URL is not set; playing original files directly (no transcoding, gapless timelines, or voice boost)")
	}

	backups := service.NewBackups(svc, *dataDir, keyProber(sealer))
	backups.SweepTempFiles()
	if restoreApplied {
		if err := backups.PostRestoreSweep(ctx, service.RestoreReportLike{
			BackupID:   restoreReport.BackupID,
			FileName:   restoreReport.FileName,
			SetAside:   restoreReport.SetAside,
			Casualties: restoreCasualties,
		}); err != nil {
			log.Warn("post-restore sweep", "err", err)
		}
	}
	backupWake := make(chan string, 8)
	group.Go(ctx, "backup-runner", func(ctx context.Context) error {
		sweep := time.NewTicker(time.Minute)
		defer sweep.Stop()
		for {
			select {
			case <-ctx.Done():
				return ctx.Err()
			case id := <-backupWake:
				if err := backups.Run(ctx, id); err != nil && ctx.Err() == nil {
					log.Warn("backup run", "backup", id, "err", err)
				}
			case <-sweep.C:
				// A wake dropped by a full channel leaves a claimed row
				// running with nobody on it; the sweep picks it up.
				rows, err := backups.List(ctx)
				if err != nil {
					continue
				}
				for _, row := range rows {
					if row.State == "running" {
						if err := backups.Run(ctx, row.ID); err != nil && ctx.Err() == nil {
							log.Warn("backup run", "backup", row.ID, "err", err)
						}
					}
				}
			}
		}
	})
	group.Go(ctx, "cron-scheduler", func(ctx context.Context) error {
		tick := time.NewTicker(30 * time.Second)
		defer tick.Stop()
		lastCheck := time.Now()
		for {
			select {
			case <-ctx.Done():
				return ctx.Err()
			case now := <-tick.C:
				// Order matters: prune and scan finish fast (a scan is
				// an async catalog job), so the one long-running kind,
				// backup, goes last and can only delay the next tick,
				// never a sibling due in this one. Delayed firings are
				// caught up, not lost: DueSchedule measures from the
				// last run, not from the tick that should have fired.
				if svc.DueSchedule(ctx, "prune", lastCheck, now) {
					svc.MarkScheduleRun(ctx, "prune", svc.RunPrune(ctx))
				}
				if svc.DueSchedule(ctx, "scan", lastCheck, now) {
					_, err := svc.Rescan(ctx)
					svc.MarkScheduleRun(ctx, "scan", err)
				}
				if svc.DueSchedule(ctx, "backup", lastCheck, now) {
					row, err := backups.Create(ctx, nil, "scheduled")
					if service.KindOf(err) == service.KindConflict {
						// A manual backup holds the slot. Marking the
						// schedule as run would defer it to the NEXT
						// cron firing (a week, on the default); leaving
						// it unmarked retries on the next tick instead.
						log.Info("scheduled backup waiting on a running backup")
					} else {
						if err == nil {
							err = backups.Run(ctx, row.ID)
						}
						svc.MarkScheduleRun(ctx, "backup", err)
					}
				}
				lastCheck = now
			}
		}
	})

	// Podcast background work: the feed refresh scheduler, the retention
	// sweeper, and the queue drainers. All are supervised ticker loops on
	// the process context; each cycle is cheap when idle.
	if *podcastDir != "" {
		refreshEvery := time.Duration(*feedRefreshMin) * time.Minute
		group.Go(ctx, "feed-refresh", func(ctx context.Context) error {
			tick := time.NewTicker(time.Minute)
			defer tick.Stop()
			for {
				select {
				case <-ctx.Done():
					return nil
				case <-tick.C:
					svc.RefreshDueFeeds(ctx, refreshEvery)
				}
			}
		})
		group.Go(ctx, "retention-sweeper", func(ctx context.Context) error {
			tick := time.NewTicker(time.Minute)
			defer tick.Stop()
			for {
				select {
				case <-ctx.Done():
					return nil
				case <-tick.C:
					svc.SweepRetention(ctx)
				}
			}
		})
		group.Go(ctx, "fetch-worker", func(ctx context.Context) error {
			tick := time.NewTicker(5 * time.Second)
			defer tick.Stop()
			for {
				select {
				case <-ctx.Done():
					return nil
				case <-tick.C:
					for svc.DrainFetchQueue(ctx) {
						if ctx.Err() != nil {
							return nil
						}
					}
				}
			}
		})
	}

	// The silence and loudness analysis worker serves audiobooks as
	// much as podcasts (skip maps and voice-boost leveling), so it runs
	// whenever the streaming sidecar does, independent of the podcast
	// surface.
	if bridge != nil {
		group.Go(ctx, "analysis-worker", func(ctx context.Context) error {
			tick := time.NewTicker(10 * time.Second)
			defer tick.Stop()
			for {
				select {
				case <-ctx.Done():
					return nil
				case <-tick.C:
					for svc.DrainAnalysisQueue(ctx) {
						if ctx.Err() != nil {
							return nil
						}
					}
				}
			}
		})
	}

	// The scrobble and notification outboxes drain continuously; both
	// are cheap when idle and their deliveries back off on failure.
	group.Go(ctx, "scrobble-outbox", func(ctx context.Context) error {
		tick := time.NewTicker(5 * time.Second)
		defer tick.Stop()
		for {
			select {
			case <-ctx.Done():
				return nil
			case <-tick.C:
				for svc.DrainScrobbleOutbox(ctx) {
					if ctx.Err() != nil {
						return nil
					}
				}
			}
		}
	})
	group.Go(ctx, "notify-outbox", func(ctx context.Context) error {
		tick := time.NewTicker(5 * time.Second)
		defer tick.Stop()
		for {
			select {
			case <-ctx.Done():
				return nil
			case <-tick.C:
				for svc.DrainNotifyOutbox(ctx) {
					if ctx.Err() != nil {
						return nil
					}
				}
			}
		}
	})

	sessions := auth.NewSessions(store)

	// Expired sessions, spent OIDC state, and stale one-time codes are
	// swept on a coarse timer; correctness never depends on the sweep
	// (lookups check expiry themselves), it just keeps the tables lean.
	// The outbox prunes ride the same coarse timer.
	group.Go(ctx, "session-janitor", func(ctx context.Context) error {
		tick := time.NewTicker(time.Hour)
		defer tick.Stop()
		for {
			select {
			case <-ctx.Done():
				return nil
			case <-tick.C:
				if err := store.SweepExpired(ctx); err != nil {
					log.Warn("sweeping expired auth state", "err", err)
				}
				svc.PruneScrobbleOutbox(ctx)
				svc.PruneNotifyOutbox(ctx)
			}
		}
	})

	// Curation background work: the identify worker (woken by new review
	// entries, ticker as backstop), the health fix drainer, the tool
	// task runner, the upload janitor, and the health sweep scheduler.
	group.Go(ctx, "match-worker", func(ctx context.Context) error {
		tick := time.NewTicker(30 * time.Second)
		defer tick.Stop()
		for {
			select {
			case <-ctx.Done():
				return nil
			case <-svc.MatchWakeups():
			case <-tick.C:
			}
			for svc.DrainMatchQueue(ctx) {
				if ctx.Err() != nil {
					return nil
				}
			}
		}
	})
	group.Go(ctx, "fix-worker", func(ctx context.Context) error {
		tick := time.NewTicker(15 * time.Second)
		defer tick.Stop()
		for {
			select {
			case <-ctx.Done():
				return nil
			case <-tick.C:
				for svc.DrainFixQueue(ctx) {
					if ctx.Err() != nil {
						return nil
					}
				}
			}
		}
	})
	group.Go(ctx, "tool-worker", func(ctx context.Context) error {
		tick := time.NewTicker(10 * time.Second)
		defer tick.Stop()
		for {
			select {
			case <-ctx.Done():
				return nil
			case <-tick.C:
				for svc.DrainToolTasks(ctx) {
					if ctx.Err() != nil {
						return nil
					}
				}
			}
		}
	})
	group.Go(ctx, "upload-janitor", func(ctx context.Context) error {
		tick := time.NewTicker(time.Hour)
		defer tick.Stop()
		for {
			select {
			case <-ctx.Done():
				return nil
			case <-tick.C:
				// Overdue batches finalize first (their members regain
				// normal retention), then expired sessions reclaim.
				for svc.DrainExpiredUploadBatches(ctx) {
					if ctx.Err() != nil {
						return nil
					}
				}
				for svc.DrainExpiredUploads(ctx) {
					if ctx.Err() != nil {
						return nil
					}
				}
			}
		}
	})
	group.Go(ctx, "health-sweep", func(ctx context.Context) error {
		tick := time.NewTicker(time.Minute)
		defer tick.Stop()
		for {
			select {
			case <-ctx.Done():
				return nil
			case <-tick.C:
				if !svc.HealthSweepDue(ctx) {
					continue
				}
				if err := svc.SweepHealth(ctx); err != nil {
					log.Warn("health sweep", "err", err)
				}
			}
		}
	})

	// Genre normalization is continuous rather than an ingest hook:
	// genres read from file tags are resolved and stored by the catalog's
	// own scanner and never pass through WaxDeck, so a library scanned
	// tomorrow would be unnormalized again. This follows the catalog's
	// change log, so newly scanned items fold onto the canonical
	// vocabulary shortly after they land; the full-catalog pass is a tool
	// task for anything older than the log retains.
	group.Go(ctx, "genre-normalize", func(ctx context.Context) error {
		first := time.NewTimer(time.Minute)
		defer first.Stop()
		tick := time.NewTicker(2 * time.Minute)
		defer tick.Stop()
		for {
			select {
			case <-ctx.Done():
				return nil
			case <-first.C:
			case <-tick.C:
			}
			for {
				rep, err := svc.SweepGenres(ctx)
				if err != nil {
					log.Warn("genre normalization sweep", "err", err)
					break
				}
				if rep.Normalized > 0 || rep.Locked > 0 {
					log.Info("genre normalization sweep",
						"scanned", rep.Scanned, "normalized", rep.Normalized,
						"locked", rep.Locked, "offTree", rep.Unmapped)
				}
				if !rep.More || ctx.Err() != nil {
					break
				}
			}
		}
	})

	var oidc *auth.OIDC
	if *oidcIssuer != "" {
		if *publicBase == "" {
			return errors.New("WAXDECK_OIDC_ISSUER requires WAXDECK_PUBLIC_BASE for the callback URL")
		}
		oidc, err = auth.NewOIDC(ctx, auth.OIDCConfig{
			ID:           *oidcID,
			DisplayName:  *oidcName,
			Issuer:       *oidcIssuer,
			ClientID:     *oidcClient,
			ClientSecret: *oidcSecret,
			GroupsClaim:  *oidcGroups,
			AdminGroup:   *oidcAdminGr,
		}, store)
		if err != nil {
			return err
		}
		log.Info("single sign-on enabled", "issuer", *oidcIssuer, "provider", *oidcID)
	}

	// The connect core: endpoint registry, playback sessions, and the
	// command routing between controllers and endpoints. The advertise
	// bases are what cast devices and renderers fetch media from; the
	// LAN base auto-detects so plain-HTTP casting works with zero
	// setup, and the loopback base serves the jukebox.
	port := listenPort(*addr)
	lanBase := *advertiseBase
	if lanBase == "" {
		if ip := detectLANIP(); ip != "" {
			lanBase = "http://" + ip + ":" + port
		}
	}
	bases := connect.Bases{
		Public:   strings.TrimRight(*publicBase, "/"),
		LAN:      strings.TrimRight(lanBase, "/"),
		Loopback: "http://127.0.0.1:" + port,
	}
	connectSvc, err := connect.New(ctx, connect.Config{
		Store:                store,
		Group:                group,
		Resolver:             &api.ConnectResolver{Svc: svc, Bridge: bridge, Media: media},
		Sink:                 &api.ConnectSink{Svc: svc},
		Bases:                bases,
		InvalidatePlayer:     hub.MarkPlayerAll,
		SharedOutputsAllowed: svc.UserSharedOutputsAllowed,
		Logger:               log,
	})
	if err != nil {
		return err
	}
	group.Go(ctx, "connect", connectSvc.Run)

	// Device discovery: multicast on the LAN plus statically configured
	// devices for networks where multicast never arrives (the compose
	// default network among them; the cast profile documents the
	// host-networking answer).
	if *castDiscovery || *castDevices != "" {
		cfg := castv2.DiscoveryConfig{
			Announce:   connectSvc,
			Group:      group,
			Logger:     log,
			Static:     parseCastDevices(*castDevices),
			StaticOnly: !*castDiscovery,
		}
		group.Go(ctx, "cast-discovery", func(c context.Context) error {
			return castv2.RunDiscovery(c, cfg)
		})
	}
	if *castDiscovery || *dlnaDevices != "" {
		cfg := dlna.DiscoveryConfig{
			Announce:   connectSvc,
			Group:      group,
			Logger:     log,
			Static:     parseDLNADevices(*dlnaDevices),
			StaticOnly: !*castDiscovery,
		}
		group.Go(ctx, "dlna-discovery", func(c context.Context) error {
			return dlna.RunDiscovery(c, cfg)
		})
	}
	if *jukeboxOn {
		if bridge == nil {
			log.Warn("jukebox needs the streaming engine for WAV output; not registering the endpoint")
		} else {
			jbCfg := jukebox.Config{Name: *jukeboxName, Log: log}
			if *jukeboxCmd != "" {
				jbCfg.Command = strings.Fields(*jukeboxCmd)
			}
			if _, err := connectSvc.EndpointOnline(ctx, "jukebox", "jukebox", *jukeboxName, "", true, false, jukebox.Dial(jbCfg, group)); err != nil {
				log.Warn("registering jukebox endpoint", "err", err)
			}
		}
	}

	srv := api.NewServer(version, api.Options{
		Service:      svc,
		Bridge:       bridge,
		Sessions:     sessions,
		OIDC:         oidc,
		Media:        media,
		Connect:      connectSvc,
		Group:        group,
		Bases:        bases,
		Logger:       log,
		CookieSecure: *cookieSec,
		PublicBase:   *publicBase,
		Backups:      backups,
		BackupWake:   backupWake,
		Shares:       shareTokens,
		WorkerTokens: workerTokenList,
	})
	apiHandler := api.HandlerWithOptions(
		api.NewStrictHandlerWithOptions(srv, nil, api.StrictHTTPServerOptions{
			RequestErrorHandlerFunc:  api.RequestErrorHandler,
			ResponseErrorHandlerFunc: api.ResponseErrorHandler,
		}),
		api.StdHTTPServerOptions{
			BaseURL:     "/api/v1",
			Middlewares: []api.MiddlewareFunc{srv.AuthMiddleware},
			ErrorHandlerFunc: func(w http.ResponseWriter, r *http.Request, err error) {
				api.RequestErrorHandler(w, r, err)
			},
		},
	)

	mux := http.NewServeMux()
	mux.Handle("/api/v1/", apiHandler)
	// The event channel and the download endpoint live outside the
	// generated router: a WebSocket upgrade and a ranged file server do
	// not fit the strict-handler shape. The event channel runs behind
	// the same auth middleware as the rest of the API; downloads
	// authenticate by media token like /media/stream.
	mux.Handle("GET /api/v1/ws", srv.AuthMiddleware(srv.ServeWS(hub)))
	mux.HandleFunc("GET /media/download", srv.ServeDownload)
	// Radio streams proxy through this origin under a media token,
	// like /media/stream; the guarded client owns the URL policy.
	mux.HandleFunc("GET /media/radio/{pid}", srv.ServeRadio)
	// Public share pages: server-rendered plain HTML plus their media,
	// authenticated by the capability token in the path.
	mux.HandleFunc("GET /s/{token}", srv.ServeSharePage)
	mux.HandleFunc("GET /s/{token}/stream", srv.ServeShareStream)
	mux.HandleFunc("GET /s/{token}/art", srv.ServeShareArt)
	mux.HandleFunc("GET /s/{token}/download", srv.ServeShareDownload)
	// The similarity worker's audio pull; worker-token authenticated.
	mux.HandleFunc("GET /media/analysis/{pid}", srv.ServeAnalysisAudio)
	// The read-only OpenSubsonic compatibility surface. App-password
	// authenticated; third-party clients browse and stream while the
	// first-party clients mature.
	mux.Handle("/rest/", subsonic.New(svc, bridge, media, version))
	// The gpodder.net-compatible sync surface (AntennaPod and friends):
	// app passwords over Basic plus its own stateless session cookie.
	gp := gpodder.New(svc, secret, log)
	mux.Handle("/api/2/", gp)
	mux.Handle("/subscriptions/", gp)
	if bridge != nil {
		mux.HandleFunc("/media/stream", bridge.ServeStream)
		mux.HandleFunc("/media/hls/", bridge.ServeHLS)
	} else {
		mux.HandleFunc("/media/stream", func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusNotImplemented)
			fmt.Fprintln(w, `{"code":"internal","message":"streaming is not configured on this server"}`)
		})
	}
	if *metricsToken != "" {
		mux.Handle("GET /metrics", metricsHandler(*metricsToken, version, store, svc))
	} else {
		log.Info("metrics endpoint disabled; set WAXDECK_METRICS_TOKEN to enable GET /metrics")
	}
	mux.Handle("/", web.Handler(*webDir))

	// Streaming handlers (the radio proxy, any long response body) hold
	// their connections active for as long as both sides stay open, and
	// Shutdown waits for active connections, so without a cancel signal
	// one live stream rides out the entire shutdown deadline. Every
	// request context derives from this base; canceling it at shutdown
	// ends the streams so the drain can finish.
	reqCtx, reqCancel := context.WithCancel(context.Background())
	defer reqCancel()
	httpSrv := &http.Server{
		Addr:              *addr,
		Handler:           mux,
		ReadHeaderTimeout: 10 * time.Second,
		BaseContext:       func(net.Listener) context.Context { return reqCtx },
	}

	group.GoOnce(ctx, "http", func(context.Context) error {
		log.Info("waxdeck listening", "addr", *addr, "version", version)
		if err := httpSrv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			// The process cannot serve anything without its listener;
			// unwind through the signal context.
			stop()
			return err
		}
		return nil
	})

	<-ctx.Done()

	reqCancel()
	shutCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := httpSrv.Shutdown(shutCtx); err != nil {
		log.Error("shutdown", "err", err)
	}
	group.Wait()
	log.Info("bye")
	return nil
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

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
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
func flagWasSet(name string) bool {
	set := false
	flag.Visit(func(f *flag.Flag) {
		if f.Name == name {
			set = true
		}
	})
	return set
}

func envIntOr(key string, def int) int {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return def
}

func envInt64Or(key string, def int64) int64 {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.ParseInt(v, 10, 64); err == nil {
			return n
		}
	}
	return def
}

// listenPort extracts the port from a listen address, defaulting to
// the standard port when the address carries none.
func listenPort(addr string) string {
	_, port, err := net.SplitHostPort(addr)
	if err != nil || port == "" {
		return "4420"
	}
	return port
}

// detectLANIP picks the machine's most plausible LAN IPv4: the first
// global unicast address on an up, non-loopback interface. Cast
// devices resolve nothing, so an address beats any name.
func detectLANIP() string {
	ifaces, err := net.Interfaces()
	if err != nil {
		return ""
	}
	for _, iface := range ifaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}
		for _, a := range addrs {
			ipNet, ok := a.(*net.IPNet)
			if !ok {
				continue
			}
			ip := ipNet.IP.To4()
			if ip == nil || !ip.IsGlobalUnicast() {
				continue
			}
			return ip.String()
		}
	}
	return ""
}

// parseCastDevices parses name=host:port pairs into static devices.
func parseCastDevices(s string) []castv2.Device {
	var out []castv2.Device
	for _, part := range strings.Split(s, ",") {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		name, addr, ok := strings.Cut(part, "=")
		if !ok {
			continue
		}
		host, portStr, err := net.SplitHostPort(addr)
		if err != nil {
			continue
		}
		port, err := strconv.Atoi(portStr)
		if err != nil {
			continue
		}
		out = append(out, castv2.Device{Host: host, Port: port, Name: name})
	}
	return out
}

// parseDLNADevices parses description URLs into static devices.
func parseDLNADevices(s string) []dlna.Device {
	var out []dlna.Device
	for _, part := range strings.Split(s, ",") {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		out = append(out, dlna.Device{Location: part})
	}
	return out
}

// stagedCasualties reads the sealed-credential casualty list out of the
// restore marker before Apply consumes it, so the post-restore sweep
// can record exactly what went pending re-auth.
func stagedCasualties(dataDir string) []service.SealedCasualty {
	raw, err := os.ReadFile(filepath.Join(dataDir, "restore-staged.json"))
	if err != nil {
		return nil
	}
	var doc struct {
		SealedCasualties []service.SealedCasualty `json:"sealedCasualties"`
	}
	if err := json.Unmarshal(raw, &doc); err != nil {
		return nil
	}
	return doc.SealedCasualties
}

// keyProber answers the restore preflight: whether this host's key
// opens the archive's sealed credentials, and which credentials break
// when it does not. It reads the archive's own waxdeck.db snapshot,
// never the live one.
func keyProber(sealer *auth.Sealer) service.KeyProber {
	return func(ctx context.Context, waxdeckDBPath string) (bool, bool, []service.SealedCasualty) {
		conn, err := sql.Open("sqlite", "file:"+waxdeckDBPath+"?mode=ro")
		if err != nil {
			return true, false, nil
		}
		defer conn.Close()
		type sealedRow struct {
			kind, name string
			blob       []byte
		}
		var rows []sealedRow
		if r, err := conn.QueryContext(ctx, `
			SELECT ap.label, u.username, ap.secret_enc
			FROM app_passwords ap LEFT JOIN users u ON u.id = ap.user_id`); err == nil {
			for r.Next() {
				var label, username sql.NullString
				var blob []byte
				if r.Scan(&label, &username, &blob) == nil {
					rows = append(rows, sealedRow{"app-password", username.String + "/" + label.String, blob})
				}
			}
			r.Close()
		}
		if r, err := conn.QueryContext(ctx, `
			SELECT sc.service, u.username, sc.sealed_secret
			FROM scrobble_connections sc LEFT JOIN users u ON u.id = sc.user_id`); err == nil {
			for r.Next() {
				var svcName, username sql.NullString
				var blob []byte
				if r.Scan(&svcName, &username, &blob) == nil {
					rows = append(rows, sealedRow{"scrobble-connection", username.String + "/" + svcName.String, blob})
				}
			}
			r.Close()
		}
		// The err == nil idiom doubles as version tolerance: an archive
		// from before notification targets simply lacks the table and
		// contributes nothing.
		if r, err := conn.QueryContext(ctx, `
			SELECT nt.kind, nt.label, u.username, nt.sealed_config
			FROM notification_targets nt LEFT JOIN users u ON u.id = nt.user_id`); err == nil {
			for r.Next() {
				var kind, label, username sql.NullString
				var blob []byte
				if r.Scan(&kind, &label, &username, &blob) == nil {
					owner := username.String
					if owner == "" {
						owner = "server"
					}
					name := owner + "/" + kind.String
					if label.String != "" {
						name += "/" + label.String
					}
					rows = append(rows, sealedRow{"notification-target", name, blob})
				}
			}
			r.Close()
		}
		if len(rows) == 0 {
			return true, true, nil
		}
		if _, err := sealer.Open(rows[0].blob); err == nil {
			return true, true, nil
		}
		casualties := make([]service.SealedCasualty, 0, len(rows))
		for _, row := range rows {
			casualties = append(casualties, service.SealedCasualty{Kind: row.kind, Name: row.name})
		}
		return true, false, casualties
	}
}

// metricsHandler serves the Prometheus endpoint behind its bearer
// token. Gauges sample the database at scrape time; counts here are
// small at self-host scale.
func metricsHandler(token, version string, store *db.DB, svc *service.Library) http.Handler {
	reg := metrics.NewRegistry()
	reg.GoRuntime()
	reg.GaugeVec("waxdeck_build_info", "Build metadata; value is always 1.", []string{"version"}).
		With(version).Set(1)
	count := func(query string) func() float64 {
		return func() float64 {
			var n float64
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			if err := store.Reader().QueryRowContext(ctx, query).Scan(&n); err != nil {
				return 0
			}
			return n
		}
	}
	reg.GaugeFunc("waxdeck_users", "Accounts, pending registrations included.",
		count(`SELECT COUNT(*) FROM users`))
	reg.GaugeFunc("waxdeck_signup_requests_pending", "Registrations awaiting approval.",
		count(`SELECT COUNT(*) FROM users WHERE pending = 1`))
	reg.GaugeFunc("waxdeck_sessions", "Live login sessions.",
		count(`SELECT COUNT(*) FROM sessions`))
	reg.GaugeFunc("waxdeck_listen_sessions_total", "Recorded listen sessions.",
		count(`SELECT COUNT(*) FROM listen_sessions`))
	reg.GaugeFunc("waxdeck_tool_tasks_active", "Queued or running background tasks.",
		count(`SELECT COUNT(*) FROM tool_tasks WHERE state IN ('queued','running')`))
	reg.GaugeFunc("waxdeck_scrobble_outbox_depth", "Undelivered scrobbles.",
		count(`SELECT COUNT(*) FROM scrobble_outbox`))
	reg.GaugeFunc("waxdeck_notify_outbox_depth", "Undelivered notifications.",
		count(`SELECT COUNT(*) FROM notify_outbox`))
	reg.GaugeFunc("waxdeck_transcode_sessions_active", "Engine-backed streams in flight.",
		func() float64 { return float64(svc.ActiveTranscodeSessions()) })
	inner := reg.Handler()
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		auth := r.Header.Get("Authorization")
		if subtle.ConstantTimeCompare([]byte(auth), []byte("Bearer "+token)) != 1 {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		inner.ServeHTTP(w, r)
	})
}
