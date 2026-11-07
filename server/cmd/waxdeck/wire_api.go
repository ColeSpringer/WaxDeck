package main

import (
	"context"
	"crypto/subtle"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"time"

	"github.com/colespringer/waxdeck/server/internal/adapter/gpodder"
	"github.com/colespringer/waxdeck/server/internal/adapter/subsonic"
	"github.com/colespringer/waxdeck/server/internal/api"
	"github.com/colespringer/waxdeck/server/internal/auth"
	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
	"github.com/colespringer/waxdeck/server/internal/connect"
	"github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/events"
	"github.com/colespringer/waxdeck/server/internal/metrics"
	"github.com/colespringer/waxdeck/server/internal/service"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// muxDeps are what the HTTP surface serves from.
type muxDeps struct {
	front        httpFront
	svc          *service.Library
	store        *db.DB
	bridge       *flow.Bridge
	hub          *events.Hub
	sessions     *auth.Sessions
	oidc         *auth.OIDC
	media        *auth.MediaTokens
	shareTokens  *auth.ShareTokens
	connectSvc   *connect.Service
	bases        connect.Bases
	backups      *service.Backups
	backupWake   chan string
	workerTokens []string
	log          *slog.Logger
}

// newMux builds the API server and the metrics registry, mounts every
// surface the server answers, and starts the gpodder-pending retry.
func newMux(ctx context.Context, group *supervise.Group, cfg coreConfig, deps muxDeps) http.Handler {
	if cfg.trustedProxies != "" {
		deps.log.Info("trusting forwarded client addresses", "proxies", cfg.trustedProxies)
	}

	srv := api.NewServer(version, api.Options{
		Service:        deps.svc,
		Bridge:         deps.bridge,
		Sessions:       deps.sessions,
		OIDC:           deps.oidc,
		Media:          deps.media,
		Connect:        deps.connectSvc,
		Group:          group,
		Bases:          deps.bases,
		Logger:         deps.log,
		CookieSecure:   cfg.cookieSecure,
		PublicBase:     cfg.publicBase,
		Backups:        deps.backups,
		BackupWake:     deps.backupWake,
		Shares:         deps.shareTokens,
		WorkerTokens:   deps.workerTokens,
		TrustedProxies: deps.front.proxies,
		// The signal context, not the request one: background work the
		// API starts has to outlive the request that asked for it and
		// still end when the process is asked to stop, or Group.Wait
		// holds the shutdown open for the worker's whole budget.
		ProcCtx: ctx,
	})
	apiHandler := srv.Handler()

	// Request metrics ride the same registry the endpoint exposes, so a
	// server with no metrics token instruments nothing at all: there is
	// no scraper, and the series would only accumulate unread.
	var reg *metrics.Registry
	var httpm *httpMetrics
	if cfg.metricsToken != "" {
		reg = newMetricsRegistry(version, deps.store, deps.svc)
		httpm = newHTTPMetrics(reg)
	} else {
		deps.log.Info("metrics endpoint disabled; set WAXDECK_METRICS_TOKEN to enable GET /metrics")
	}

	mux := http.NewServeMux()
	mux.Handle("/api/v1/", httpm.instrument("api", apiHandler.ServeHTTP))
	// The event channel and the download endpoint live outside the
	// generated router: a WebSocket upgrade and a ranged file server do
	// not fit the strict-handler shape. The event channel runs behind
	// the same auth middleware as the rest of the API; downloads
	// authenticate by media token like /media/stream. It is also the one
	// route with no request metrics: the upgrade hijacks the connection,
	// so nothing is written through an instrumented writer, and what it
	// opens is a session rather than a request.
	mux.Handle("GET /api/v1/ws", srv.AuthMiddleware(srv.ServeWS(deps.hub)))
	// Backup archives are ranged and resumable, which the generated
	// whole-body shape cannot be; the exact pattern wins over the
	// /api/v1/ prefix above, and the same auth middleware still runs.
	mux.Handle(api.BackupArchiveRoute,
		httpm.instrumentStream("download", srv.AuthMiddleware(http.HandlerFunc(srv.ServeBackupArchive)).ServeHTTP))
	// The tool-task event stream stays on the generated handler and is
	// registered here only to be classed apart: it is open for as long as
	// someone watches a task, so timing it as request duration is the
	// poisoning the api class exists to avoid. Bulk request bodies under
	// /api/v1/ (artwork, upload chunks, a backup import) deliberately stay
	// in the api class: they are bounded transfers, and a slow one reads
	// as a slow request, which is true.
	mux.Handle(api.TaskEventsRoute, httpm.instrumentStream("api-events", apiHandler.ServeHTTP))
	mux.Handle("GET /media/download", httpm.instrumentStream("download", srv.ServeDownload))
	// A podcast episode whose audio is not on this server relays from
	// the feed's own host, media-token authenticated like the rest of
	// /media/*. The target comes from the episode in the catalog, never
	// from the query, which is what keeps it from being an open proxy.
	mux.Handle("GET /media/enclosure", httpm.instrumentStream("media-stream", srv.ServeEnclosure))
	// Artwork for endpoints that cannot present a session: a cast
	// receiver or a DLNA renderer fetches the URL it was handed, and the
	// only credential it can carry is the one in that URL.
	mux.Handle("GET /media/art", httpm.instrument("media-art", srv.ServeMediaArt))
	// A second of silence for the device half of the cast connection
	// check, fetched by the device under the token in its URL like the
	// art beside it.
	mux.Handle("GET /media/probe.wav", httpm.instrument("media-probe", srv.ServeProbeAudio))
	// Radio streams proxy through this origin under a media token,
	// like /media/stream; the guarded client owns the URL policy.
	mux.Handle("GET /media/radio/{pid}", httpm.instrumentStream("media-stream", srv.ServeRadio))
	// Public share pages: server-rendered plain HTML plus their media,
	// authenticated by the capability token in the path.
	mux.Handle("GET /s/{token}", httpm.instrument("share", srv.ServeSharePage))
	mux.Handle("GET /s/{token}/stream", httpm.instrumentStream("media-stream", srv.ServeShareStream))
	mux.Handle("GET /s/{token}/art", httpm.instrument("share", srv.ServeShareArt))
	mux.Handle("GET /s/{token}/download", httpm.instrumentStream("download", srv.ServeShareDownload))
	// The similarity worker's audio pull; worker-token authenticated.
	mux.Handle("GET /media/analysis/{pid}", httpm.instrumentStream("media-stream", srv.ServeAnalysisAudio))
	// The read-only OpenSubsonic compatibility surface. App-password
	// authenticated; third-party clients browse and stream while the
	// first-party clients mature.
	mux.Handle("/rest/", httpm.instrument("subsonic", subsonic.New(deps.svc, deps.bridge, deps.media, version, deps.log).WithSessions(deps.connectSvc).ServeHTTP))
	// The gpodder.net-compatible sync surface (AntennaPod and friends):
	// app passwords over Basic plus its own stored session cookie.
	gp := gpodder.New(deps.svc, cfg.cookieSecure, deps.log)
	mountGpodder(ctx, mux, group, httpm.instrument("gpodder", gp.ServeHTTP), deps.svc.RetryPendingGpodder, time.Minute)
	if deps.bridge != nil {
		mux.Handle("/media/stream", httpm.instrumentStream("media-stream", deps.bridge.ServeStream))
		// HLS fetches are many short requests (a playlist, an init
		// segment, a few seconds of audio each), so total duration is a
		// real latency number here and not a listening session's length.
		mux.Handle("/media/hls/", httpm.instrument("media-hls", deps.bridge.ServeHLS))
	} else {
		mux.Handle("/media/stream", httpm.instrument("media-stream", func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusNotImplemented)
			fmt.Fprintln(w, `{"code":"internal","message":"streaming is not configured on this server"}`)
		}))
	}
	if reg != nil {
		// Exempt from instrumentation: a scrape must not measure itself.
		mux.Handle("GET /metrics", metricsHandler(cfg.metricsToken, reg))
	}
	mux.Handle("/", httpm.instrument("web", deps.front.site.ServeHTTP))
	return mux
}

// newHTTPServer serves mux on addr behind the cross-origin layer, every
// request's context deriving from reqCtx.
func newHTTPServer(reqCtx context.Context, addr string, allowedOrigins []string, mux http.Handler, log *slog.Logger) *http.Server {
	if len(allowedOrigins) > 0 {
		// Logged as parsed, not as written: an exact-match list is the
		// kind of configuration that fails silently on a stray slash, and
		// this is the line that says what the server actually believes.
		log.Info("allowing cross-origin browser clients", "origins", allowedOrigins)
	}
	return &http.Server{
		Addr:              addr,
		Handler:           withCORS(allowedOrigins, mux),
		ReadHeaderTimeout: 10 * time.Second,
		BaseContext:       func(net.Listener) context.Context { return reqCtx },
	}
}

// mountGpodder serves the gpodder surface and runs, every interval, the
// retries of the feeds its devices added that could not be fetched yet.
// On a server whose podcast directory is off every add is refused, so
// nothing parks, and a park left from before is refused at its next try.
func mountGpodder(ctx context.Context, mux *http.ServeMux, group *supervise.Group, h http.Handler,
	retry func(context.Context), every time.Duration) {
	mux.Handle("/api/2/", h)
	mux.Handle("/subscriptions/", h)
	group.Go(ctx, "gpodder-pending", func(ctx context.Context) error {
		tick := time.NewTicker(every)
		defer tick.Stop()
		for {
			select {
			case <-ctx.Done():
				return nil
			case <-tick.C:
				retry(ctx)
			}
		}
	})
}

// newMetricsRegistry builds the registry the /metrics endpoint renders.
// It is separate from the handler because the request-level families
// are registered on it before the mux is wired, and the wiring is what
// names each route's class.
func newMetricsRegistry(version string, store *db.DB, svc *service.Library) *metrics.Registry {
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
	reg.GaugeFunc("waxdeck_transcode_sessions_active", "Engine-backed sessions in flight.",
		func() float64 { return float64(svc.ActiveTranscodeSessions().Sessions) })
	reg.GaugeFunc("waxdeck_transcode_timelines_active", "Listeners playing a queue as one gapless rendering.",
		func() float64 { return float64(svc.ActiveTranscodeSessions().Timelines) })
	return reg
}

// metricsHandler serves the Prometheus endpoint behind its bearer
// token. Gauges sample the database at scrape time; counts here are
// small at self-host scale.
func metricsHandler(token string, reg *metrics.Registry) http.Handler {
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
