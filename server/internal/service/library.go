// Package service is the application core: everything between the API
// surface and the WaxBin facade. Handlers call services; services call
// the facade; nothing above this package imports waxbin.
package service

import (
	"context"
	"fmt"
	"log/slog"
	"path/filepath"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/config"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/pidpath"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// Root is one library root: the path WaxBin scans and the WaxFlow root
// name the same directory is mounted under for streaming.
type Root struct {
	Name string
	Path string
}

// Config configures the library service.
type Config struct {
	// DataDir holds waxbin.db (and its lockfile and IPC socket).
	DataDir string
	// Roots are the library roots, indexed in place (never moved).
	Roots []Root
	// ScanOnStart launches a scan as soon as the service is up.
	ScanOnStart bool
	Logger      *slog.Logger
}

// Library is the catalog service over an embedded WaxBin library. It
// owns the write lock for the process lifetime and hosts the IPC
// socket the waxbin CLI proxies through.
type Library struct {
	lib   *waxbin.Library
	paths *pidpath.Cache
	db    *wdb.DB
	roots []Root
	log   *slog.Logger
	// procCtx outlives any one request: async catalog jobs launch on it
	// so a scan survives the 202 that reported it started.
	procCtx context.Context
}

// SocketFileName is the IPC socket beside the catalog DB. It is a local
// admin plane: 0600, same user, full catalog access.
const SocketFileName = "waxbin.sock"

// Open opens the catalog read-write, wires the pidpath cache, starts
// the IPC server and (optionally) a startup scan on the supervised
// group, and returns the service.
func Open(ctx context.Context, cfg Config, store *wdb.DB, group *supervise.Group) (*Library, error) {
	log := cfg.Logger
	if log == nil {
		log = slog.New(slog.DiscardHandler)
	}
	roots := make([]config.Root, 0, len(cfg.Roots))
	for _, r := range cfg.Roots {
		roots = append(roots, config.Root{Path: r.Path, Mode: model.ModeInPlace})
	}
	socket := filepath.Join(cfg.DataDir, SocketFileName)
	lib, err := waxbin.Open(ctx, waxbin.Options{
		DBPath:    filepath.Join(cfg.DataDir, "waxbin.db"),
		Roots:     roots,
		Logger:    log,
		IPCSocket: socket,
	})
	if err != nil {
		return nil, fmt.Errorf("service: opening catalog: %w", err)
	}

	paths, err := pidpath.New(ctx, lib, pidpath.Options{Logger: log})
	if err != nil {
		lib.Close()
		return nil, fmt.Errorf("service: pid path cache: %w", err)
	}

	l := &Library{lib: lib, paths: paths, db: store, roots: cfg.Roots, log: log, procCtx: ctx}

	// The CLI-through-server proxy: host side is one call, alive for the
	// process lifetime. Serve returns nil on ctx cancel.
	group.Go(ctx, "waxbin-serve", func(ctx context.Context) error {
		return l.lib.Serve(ctx, socket)
	})

	if cfg.ScanOnStart {
		group.GoOnce(ctx, "startup-scan", func(ctx context.Context) error {
			pid, err := l.lib.StartScan(ctx, waxbin.ScanRequest{})
			if err != nil {
				return err
			}
			log.Info("startup scan launched", "job", string(pid))
			return nil
		})
	}
	return l, nil
}

// Close releases the catalog (flushing playback state) and the path
// cache.
func (l *Library) Close() error {
	if err := l.paths.Close(); err != nil {
		l.log.Warn("closing pid path cache", "err", err)
	}
	return l.lib.Close()
}

// Rescan starts an asynchronous scan of every root and returns the
// job. The scan runs on the process context, not the request's: it
// must survive the response that reported it started.
func (l *Library) Rescan(ctx context.Context) (Job, error) {
	pid, err := l.lib.StartScan(l.procCtx, waxbin.ScanRequest{})
	if err != nil {
		return Job{}, classify(err)
	}
	return l.JobStatus(ctx, apiPID(PrefixJob, pid))
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
	return Job{
		PID:      apiPID(PrefixJob, job.PID),
		Kind:     job.Kind,
		State:    string(job.State),
		Progress: job.Progress,
		Message:  job.Message,
		Error:    job.Error,
	}, nil
}

// summary converts an item view to the list-row DTO.
func summary(it *model.ItemView) ItemSummary {
	return ItemSummary{
		PID:        itemAPIPID(it),
		MediaType:  mediaTypeForKind(it.Kind),
		Title:      it.Title,
		Artist:     it.Artist,
		Album:      it.Album,
		DurationMS: it.DurationMS,
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
