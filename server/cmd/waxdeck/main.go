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
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"
	// Timezone validation for user preferences must work in scratch
	// containers with no zoneinfo on disk.
	_ "time/tzdata"

	"github.com/colespringer/waxdeck/server/internal/api"
	"github.com/colespringer/waxdeck/server/internal/auth"
	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
	"github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/service"
	"github.com/colespringer/waxdeck/server/internal/supervise"
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

	svcRoots := make([]service.Root, len(roots))
	for i, r := range roots {
		svcRoots[i] = service.Root{Name: r.Name, Path: r.Path}
	}
	svc, err := service.Open(ctx, service.Config{
		DataDir:     *dataDir,
		Roots:       svcRoots,
		ScanOnStart: *scanStart && len(roots) > 0,
		Logger:      log,
	}, store, group)
	if err != nil {
		return err
	}
	defer svc.Close()

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
		bridge, err = flow.New(ctx, flow.Config{
			BaseURL:  *flowURL,
			APIKey:   *flowAPIKey,
			Roots:    flowRoots,
			Tokens:   auth.NewMediaTokens(secret, 0),
			Resolver: svc,
			Logger:   log,
		})
		if err != nil {
			return err
		}
	} else {
		log.Warn("WAXDECK_FLOW_URL is not set; streaming is disabled")
	}

	sessions := auth.NewSessions(store)

	// Expired sessions, spent OIDC state, and stale one-time codes are
	// swept on a coarse timer; correctness never depends on the sweep
	// (lookups check expiry themselves), it just keeps the tables lean.
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

	srv := api.NewServer(version, api.Options{
		Service:      svc,
		Bridge:       bridge,
		Sessions:     sessions,
		OIDC:         oidc,
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
	if bridge != nil {
		mux.HandleFunc("/media/stream", bridge.ServeStream)
	} else {
		mux.HandleFunc("/media/stream", func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusNotImplemented)
			fmt.Fprintln(w, `{"code":"internal","message":"streaming is not configured on this server"}`)
		})
	}
	mux.Handle("/", web.Handler(*webDir))

	httpSrv := &http.Server{
		Addr:              *addr,
		Handler:           mux,
		ReadHeaderTimeout: 10 * time.Second,
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
