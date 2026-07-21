// Command waxdeck runs the WaxDeck server: the /api/v1 REST surface,
// the /media streaming surface, and the embedded web UI, on one origin
// (default :4420). It embeds the WaxBin catalog read-write, owning its
// write lock for the process lifetime, and reverse-proxies streams
// through the WaxFlow sidecar.
package main

import (
	"context"
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

	"github.com/colespringer/waxbin/source"

	"github.com/colespringer/waxdeck/server/internal/adapter/gpodder"
	"github.com/colespringer/waxdeck/server/internal/adapter/subsonic"
	"github.com/colespringer/waxdeck/server/internal/api"
	"github.com/colespringer/waxdeck/server/internal/auth"
	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
	"github.com/colespringer/waxdeck/server/internal/cast/castv2"
	"github.com/colespringer/waxdeck/server/internal/cast/dlna"
	"github.com/colespringer/waxdeck/server/internal/cast/jukebox"
	"github.com/colespringer/waxdeck/server/internal/connect"
	"github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/events"
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
		radioDirBase         = flag.String("radio-directory-base", envOr("WAXDECK_RADIO_DIRECTORY_BASE", ""), "radio-browser directory API base URL (empty selects the public instance)")
		lastfmKey            = flag.String("lastfm-api-key", envOr("WAXDECK_LASTFM_API_KEY", ""), "Last.fm API key for outbound scrobbling (empty leaves Last.fm unavailable)")
		lastfmSecret         = flag.String("lastfm-secret", envOr("WAXDECK_LASTFM_SECRET", ""), "Last.fm API shared secret")

		youtubeOn    = flag.Bool("youtube", envOr("WAXDECK_YOUTUBE", "false") == "true", "enable the YouTube acquisition bridge (channels and playlists as shows)")
		sealURL      = flag.String("seal-url", envOr("WAXDECK_SEAL_URL", ""), "WaxSeal attestation sidecar base URL (optional; full-quality YouTube path)")
		sealKey      = flag.String("seal-api-key", envOr("WAXDECK_SEAL_API_KEY", ""), "API key for the WaxSeal sidecar")
		sponsorBlock = flag.String("youtube-sponsorblock", envOr("WAXDECK_YOUTUBE_SPONSORBLOCK", ""), "SponsorBlock categories to cut from acquired audio, comma separated (empty disables)")

		advertiseBase = flag.String("advertise-base", envOr("WAXDECK_ADVERTISE_BASE", ""), "plain-HTTP LAN base URL cast devices fetch media from (empty auto-detects the LAN address)")
		castDiscovery = flag.Bool("cast-discovery", envOr("WAXDECK_CAST_DISCOVERY", "true") == "true", "discover Chromecast and DLNA devices on the LAN (mDNS and SSDP)")
		castDevices   = flag.String("cast-devices", envOr("WAXDECK_CAST_DEVICES", ""), "static cast devices as name=host:port pairs, comma separated (networks without multicast)")
		dlnaDevices   = flag.String("dlna-devices", envOr("WAXDECK_DLNA_DEVICES", ""), "static DLNA renderer description URLs, comma separated")
		jukeboxOn     = flag.Bool("jukebox", envOr("WAXDECK_JUKEBOX", "false") == "true", "play out the server's own audio device as a selectable endpoint (needs the streaming engine)")
		jukeboxCmd    = flag.String("jukebox-cmd", envOr("WAXDECK_JUKEBOX_CMD", ""), "player command the jukebox pipes WAV into (default aplay; PipeWire hosts use pw-cat -p -)")
		jukeboxName   = flag.String("jukebox-name", envOr("WAXDECK_JUKEBOX_NAME", "Server audio"), "display name of the jukebox endpoint")

		oidcIssuer  = flag.String("oidc-issuer", envOr("WAXDECK_OIDC_ISSUER", ""), "OIDC issuer URL (empty disables single sign-on)")
		oidcID      = flag.String("oidc-id", envOr("WAXDECK_OIDC_ID", "sso"), "OIDC provider id shown in start URLs")
		oidcName    = flag.String("oidc-name", envOr("WAXDECK_OIDC_NAME", ""), "OIDC provider display name for login buttons")
		oidcClient  = flag.String("oidc-client-id", envOr("WAXDECK_OIDC_CLIENT_ID", ""), "OIDC client id")
		oidcSecret  = flag.String("oidc-client-secret", envOr("WAXDECK_OIDC_CLIENT_SECRET", ""), "OIDC client secret")
		oidcGroups  = flag.String("oidc-groups-claim", envOr("WAXDECK_OIDC_GROUPS_CLAIM", ""), "ID-token claim holding groups (empty disables role mapping)")
		oidcAdminGr = flag.String("oidc-admin-group", envOr("WAXDECK_OIDC_ADMIN_GROUP", ""), "group granting the admin role via the groups claim")

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

	svcRoots := make([]service.Root, len(roots))
	for i, r := range roots {
		svcRoots[i] = service.Root{Name: r.Name, Path: r.Path}
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
		if *podcastDir == "" {
			return errors.New("WAXDECK_YOUTUBE requires WAXDECK_PODCAST_DIR (acquired audio lands in the podcast library)")
		}
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
			EmbedThumbnail: true,
			EmbedMetadata:  true,
			Logger:         log,
		})
		if err != nil {
			return fmt.Errorf("youtube bridge: %w", err)
		}
		providers = append(providers, yt)
		log.Info("youtube acquisition bridge enabled", "seal", *sealURL != "")
	}

	svc, err := service.Open(ctx, service.Config{
		DataDir:                   *dataDir,
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
		RadioDirectoryBase:        *radioDirBase,
		LastfmAPIKey:              *lastfmKey,
		LastfmSecret:              *lastfmSecret,
		Logger:                    log,
	}, store, group)
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
			BaseURL:  *flowURL,
			APIKey:   *flowAPIKey,
			Roots:    flowRoots,
			Tokens:   media,
			Resolver: svc,
			Logger:   log,
		})
		if err != nil {
			return err
		}
		svc.SetFlowJobs(bridge)
	} else {
		log.Warn("WAXDECK_FLOW_URL is not set; playing original files directly (no transcoding, gapless timelines, or voice boost)")
	}

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
		Store:            store,
		Group:            group,
		Resolver:         &api.ConnectResolver{Svc: svc, Bridge: bridge, Media: media},
		Sink:             &api.ConnectSink{Svc: svc},
		Bases:            bases,
		InvalidatePlayer: hub.MarkPlayerAll,
		Logger:           log,
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
