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
	"syscall"
	"time"
	// Timezone validation for user preferences must work in scratch
	// containers with no zoneinfo on disk.
	_ "time/tzdata"

	"github.com/colespringer/waxdeck/server/internal/api"
	"github.com/colespringer/waxdeck/server/internal/auth"
	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
	"github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/notices"
	"github.com/colespringer/waxdeck/server/internal/service"
	"github.com/colespringer/waxdeck/server/internal/supervise"
	"github.com/colespringer/waxdeck/server/internal/web"
)

// version is stamped by the release build (-ldflags "-X main.version=x.y.z").
var version = "0.1.0-dev"

func main() {
	if err := run(flag.CommandLine, os.Args[1:], os.LookupEnv); err != nil {
		fmt.Fprintln(os.Stderr, "waxdeck:", err)
		os.Exit(1)
	}
}

// run serves with the settings in args and lookupEnv until the first
// termination signal, or answers the mode they ask for.
func run(fs *flag.FlagSet, args []string, lookupEnv func(string) (string, bool)) error {
	cfg, err := parseConfig(fs, args, lookupEnv)
	if err != nil {
		return err
	}
	switch {
	case cfg.showVersion:
		fmt.Println(version)
		return nil
	case cfg.ping:
		return pingServer(cfg.core.addr)
	case cfg.showNotices:
		fmt.Print(notices.Text)
		return nil
	}

	log := slog.New(slog.NewTextHandler(os.Stderr, nil))
	// Settings the server cannot run with fail the start here, before
	// anything is opened or started, as a held port does below: found once
	// the catalog's workers run, they would wait those out (and hold the
	// port) before saying so.
	front, err := checkStart(cfg)
	if err != nil {
		return err
	}
	// Bound before anything is opened or started: a port another process
	// holds fails the start here, with nothing to unwind and nothing yet
	// saying it listens. Connections that arrive while the rest starts
	// wait in the backlog for the server.
	ln, err := listen(cfg.core.addr)
	if err != nil {
		return err
	}
	defer ln.Close()
	log.Info("serving the web UI", "source", front.webSource)
	if err := os.MkdirAll(cfg.core.dataDir, 0o755); err != nil {
		return fmt.Errorf("creating data dir: %w", err)
	}

	staged, err := applyStagedRestore(cfg.core.dataDir, log)
	if err != nil {
		return err
	}

	// Root context: canceled on the first termination signal; workers and
	// the IPC server unwind from it.
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	group := supervise.NewGroup(log)

	secret, err := auth.LoadOrCreateSecret(cfg.core.dataDir)
	if err != nil {
		return err
	}

	store, err := db.Open(ctx, filepath.Join(cfg.core.dataDir, "waxdeck.db"))
	if err != nil {
		return err
	}
	defer store.Close()
	if err := settleStore(ctx, store, staged, log); err != nil {
		return err
	}

	agent := service.UserAgentFor(version)
	svcCfg, err := newServiceConfig(ctx, cfg, secret, store, agent, log)
	if err != nil {
		return err
	}
	// The identity provider is asked before the service opens: one that
	// cannot be reached fails the start with nothing running yet.
	oidc, err := newOIDC(ctx, cfg.oidc, store, log)
	if err != nil {
		return err
	}
	svc, err := service.Open(ctx, svcCfg, store, group)
	if err != nil {
		return err
	}
	defer svc.Close()
	// Deferred after the close, so it runs before it on every way out,
	// a failure found while the rest starts as much as the shutdown: the
	// workers end before what they use is closed, and a startup scan on
	// a context nobody canceled cannot hold the close, and the exit, for
	// as long as it runs.
	defer func() {
		stop()
		group.Wait()
	}()

	hub := startEventHub(ctx, group, svc)

	// One media-token instance signs both streaming and download URLs.
	media := auth.NewMediaTokens(secret, 0)

	// Share capability tokens derive from the same server secret;
	// nothing share-secret is stored at rest.
	shareTokens := auth.NewShareTokens(secret)

	startSweeps(ctx, group, svc, log)
	bridge, err := startFlow(ctx, group, cfg.streaming, cfg.core.libraryRoots, cfg.podcasts.rootName, svcCfg.PodcastDir,
		svc, store, media, log)
	if err != nil {
		return err
	}
	backups, backupWake := startBackups(ctx, group, svc, cfg.core.dataDir, svcCfg.Sealer, staged, log)
	startCron(ctx, group, svc, backups, log)
	if svcCfg.PodcastDir != "" {
		startPodcastWorkers(ctx, group, svc, cfg.podcasts, agent, log)
	}
	startDrains(ctx, group, svc, bridge)

	sessions := auth.NewSessions(store)
	sessions.LimitPerAccount(cfg.core.sessionCap)
	startJanitor(ctx, group, store, svc, log)
	startCurationWorkers(ctx, group, svc, log)

	connectSvc, bases, err := startConnect(ctx, group, cfg.casting, cfg.core.addr, cfg.core.publicBase,
		store, svc, bridge, media, hub, log)
	if err != nil {
		return err
	}

	mux := newMux(ctx, group, cfg.core, muxDeps{
		front: front, svc: svc, store: store, bridge: bridge, hub: hub,
		sessions: sessions, oidc: oidc, media: media, shareTokens: shareTokens,
		connectSvc: connectSvc, bases: bases, backups: backups, backupWake: backupWake,
		workerTokens: cfg.similarity.workerTokens, log: log,
	})

	// Streaming handlers (the radio proxy, any long response body) hold
	// their connections active for as long as both sides stay open, and
	// Shutdown waits for active connections, so without a cancel signal
	// one live stream rides out the entire shutdown deadline. Every
	// request context derives from this base; canceling it at shutdown
	// ends the streams so the drain can finish.
	reqCtx, reqCancel := context.WithCancel(context.Background())
	defer reqCancel()
	httpSrv := newHTTPServer(reqCtx, cfg.core.addr, front.origins, mux, log)

	served := serve(ctx, group, log, httpSrv, ln, stop)

	<-ctx.Done()

	reqCancel()
	shutCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := httpSrv.Shutdown(shutCtx); err != nil {
		log.Error("shutdown", "err", err)
	}
	group.Wait()
	log.Info("bye")
	return served()
}

// httpFront is what the start's checks yield for the HTTP surface: the web
// UI, the origins allowed to call from a browser, and the parsed
// trusted-proxy list.
type httpFront struct {
	site      http.Handler
	webSource string
	origins   []string
	proxies   api.TrustedProxies
}

// checkStart refuses the settings the server cannot run with.
func checkStart(cfg *config) (httpFront, error) {
	// Before anything is opened: a web dir without the app is a typo,
	// which a server answering every navigation with a 404 would hide.
	site, webSource, err := web.Handler(cfg.core.webDir)
	if err != nil {
		return httpFront{}, err
	}
	// A trusted-proxy list or an origin is refused rather than defaulted:
	// a typo that silently trusted nothing, or matched nothing, would look
	// exactly like a working configuration until the day somebody was
	// locked out by it.
	trusted, err := api.ParseTrustedProxies(cfg.core.trustedProxies)
	if err != nil {
		return httpFront{}, fmt.Errorf("trusted proxies: %w", err)
	}
	allowedOrigins, err := normalizeOrigins(splitNonEmpty(cfg.core.corsOrigins, ","))
	if err != nil {
		return httpFront{}, fmt.Errorf("cors origins: %w", err)
	}
	if cfg.oidc.issuer != "" && cfg.core.publicBase == "" {
		return httpFront{}, errors.New("WAXDECK_OIDC_ISSUER requires WAXDECK_PUBLIC_BASE for the callback URL")
	}
	if cfg.streaming.flowURL != "" {
		if err := flow.CheckBaseURL(cfg.streaming.flowURL); err != nil {
			return httpFront{}, err
		}
	}
	return httpFront{site: site, webSource: webSource, origins: allowedOrigins, proxies: trusted}, nil
}
