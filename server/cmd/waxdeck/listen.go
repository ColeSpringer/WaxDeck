package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"

	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// listen binds the server's address. A bind that fails is the start
// failing, said before anything claims to listen.
func listen(addr string) (net.Listener, error) {
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		return nil, fmt.Errorf("listening on %s: %w", addr, err)
	}
	return ln, nil
}

// serve runs srv on ln from the group. A serve that fails stops the
// process through stop, and served, read once the group has ended,
// answers that failure; a shutdown is no failure.
func serve(ctx context.Context, group *supervise.Group, log *slog.Logger, srv *http.Server, ln net.Listener, stop func()) (served func() error) {
	var failed error
	addr := ln.Addr().String()
	started := group.GoOnce(ctx, "http", func(context.Context) error {
		log.Info("waxdeck listening", "addr", addr, "version", version)
		if err := srv.Serve(ln); err != nil && !errors.Is(err, http.ErrServerClosed) {
			failed = fmt.Errorf("serving on %s: %w", addr, err)
			// The process cannot serve anything without its listener;
			// unwind through the signal context.
			stop()
			return err
		}
		return nil
	})
	if !started {
		ln.Close()
	}
	return func() error { return failed }
}
