// Command waxflow-catalog is the WaxFlow build WaxDeck ships as its
// streaming sidecar: the stock CLI plus a catalog resolver that answers
// pid: sources against a WaxBin catalog database. The stock build
// resolves no pid: references at all; this flavor is what makes
// src=pid:<ULID> (and with it, direct mode) work.
//
// Configure the catalog with catalogDB (or WAXFLOW_CATALOG_DB) pointing
// at waxbin.db. Everything else is stock WaxFlow configuration.
package main

import (
	"context"
	"io"
	"os"
	"strings"
	"sync/atomic"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/pidpath"
	"github.com/colespringer/waxflow/cli"
	"github.com/colespringer/waxflow/source"
	"github.com/colespringer/waxflow/waxerr"
)

// version is stamped by the release build (-ldflags "-X main.version=x.y.z").
var version = "0.1.0-dev"

func main() {
	os.Exit(cli.ExecuteFlavor(version, os.Args[1:], os.Stdout, os.Stderr, cli.Flavor{
		Name:         "catalog",
		OpenResolver: openResolver,
	}))
}

// openResolver wires the pidpath-backed catalog when one is configured.
// Present but unconfigured, it still owns the pid: scheme: the refusal
// names the missing configuration instead of pretending the scheme is
// unknown.
func openResolver(ctx context.Context, opts cli.ResolverOptions) (source.Resolver, io.Closer, error) {
	if opts.CatalogDB == "" {
		return noCatalog{next: opts.Next}, nil, nil
	}
	popts := pidpath.Options{DBPath: opts.CatalogDB, Logger: opts.Logger}
	if !opts.Daemon {
		// One-shot commands must not start background goroutines.
		popts.PollInterval = -1
	}
	cache, err := pidpath.Open(ctx, popts)
	if err != nil {
		return nil, nil, waxerr.Wrap(waxerr.CodeCatalogUnavailable, "opening catalog", err)
	}
	cat := &catalog{cache: cache, next: opts.Next}
	cat.ReloadSourceMaxBytes(opts.MaxBytes)
	return cat, cache, nil
}

// catalog resolves pid: references through the pidpath cache and
// delegates everything else to the configured roots.
type catalog struct {
	cache *pidpath.Cache
	next  source.Resolver
	// maxBytes caps the pid: sources this resolver opens itself. A root
	// reload rewrites it while Resolve reads it, so it is atomic; root
	// references delegate to next, whose roots enforce their own
	// reconciled cap.
	maxBytes atomic.Int64
}

func (c *catalog) Resolve(ctx context.Context, ref string) (*source.File, error) {
	pid, ok := strings.CutPrefix(ref, "pid:")
	if !ok {
		return c.next.Resolve(ctx, ref)
	}
	if !model.PID(pid).Valid() {
		return nil, waxerr.New(waxerr.CodeInvalidRequest, "malformed pid reference")
	}
	loc, err := c.cache.Locate(ctx, model.PID(pid))
	if err != nil {
		return nil, err
	}
	f, err := source.OpenLocal(ref, loc.Path, loc.Path)
	if err != nil {
		return nil, err
	}
	if f.ID.Size > c.maxBytes.Load() {
		f.Close()
		return nil, waxerr.New(waxerr.CodePayloadTooLarge, "source exceeds the size cap")
	}
	return f, nil
}

// PIDSources reports pid capability for /caps.delivery.pid.
func (c *catalog) PIDSources() bool { return true }

// ReloadSourceMaxBytes implements cli.ReloadableResolver: a root reload
// hands back the re-read source cap, so the pid: files this resolver
// opens itself track a changed sourceMaxBytes instead of holding the
// value snapshotted at open. Root references need nothing here; they
// delegate to next, whose roots the same reload reconciles.
func (c *catalog) ReloadSourceMaxBytes(maxBytes int64) {
	if maxBytes <= 0 {
		maxBytes = source.DefaultMaxBytes
	}
	c.maxBytes.Store(maxBytes)
}

// noCatalog owns the pid: refusal when no catalog is configured.
type noCatalog struct{ next source.Resolver }

func (n noCatalog) Resolve(ctx context.Context, ref string) (*source.File, error) {
	if strings.HasPrefix(ref, "pid:") {
		return nil, waxerr.New(waxerr.CodeUnsupportedSource,
			"pid references need catalogDB configured")
	}
	return n.next.Resolve(ctx, ref)
}

func (n noCatalog) PIDSources() bool { return false }
