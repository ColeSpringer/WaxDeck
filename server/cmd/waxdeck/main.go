// Command waxdeck runs the WaxDeck server: the /api/v1 REST surface and the
// embedded web UI, on one origin (default :4420).
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
	"syscall"
	"time"

	"github.com/colespringer/waxdeck/server/internal/api"
	"github.com/colespringer/waxdeck/server/internal/web"
)

// version is stamped by the release build (-ldflags "-X main.version=x.y.z").
var version = "0.1.0-dev"

func main() {
	var (
		addr    = flag.String("addr", envOr("WAXDECK_ADDR", ":4420"), "listen address")
		webDir  = flag.String("web-dir", envOr("WAXDECK_WEB_DIR", ""), "serve the web UI from this directory instead of the embedded build (dev)")
		dataDir = flag.String("data-dir", envOr("WAXDECK_DATA_DIR", "./data"), "data directory (waxbin.db + waxdeck.db; not read yet)")
		showVer = flag.Bool("version", false, "print version and exit")
	)
	flag.Parse()

	if *showVer {
		fmt.Println(version)
		return
	}
	_ = dataDir // reserved: the catalog and app databases are wired in later

	log := slog.New(slog.NewTextHandler(os.Stderr, nil))

	srv := api.NewServer(version)
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
	// Media surface stub: pins the URL shape play-info hands out. The
	// WaxFlow bridge will implement it later.
	mux.HandleFunc("/media/stream", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusNotImplemented)
		fmt.Fprintln(w, `{"code":"not-implemented","message":"media streaming not implemented yet"}`)
	})
	mux.Handle("/", web.Handler(*webDir))

	httpSrv := &http.Server{
		Addr:              *addr,
		Handler:           mux,
		ReadHeaderTimeout: 10 * time.Second,
	}

	go func() {
		log.Info("waxdeck listening", "addr", *addr, "version", version)
		if err := httpSrv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Error("server failed", "err", err)
			os.Exit(1)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	<-stop

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := httpSrv.Shutdown(ctx); err != nil {
		log.Error("shutdown", "err", err)
	}
	log.Info("bye")
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
