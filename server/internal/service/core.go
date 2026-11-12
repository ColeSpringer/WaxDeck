package service

import (
	"context"
	"log/slog"
	"net"
	"slices"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/pidpath"
	"github.com/colespringer/waxbin/query"

	"github.com/colespringer/waxdeck/server/internal/auth"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// core is what Library and every domain type share, by pointer: the
// process's dependencies and read-only state, a typed pointer to each
// domain (l.Podcasts.X), and the helpers several domains share (l.getItem).
type core struct {
	db  *wdb.DB
	lib *waxbin.Library
	log *slog.Logger
	// workers is the supervised group Open was handed, kept so work a
	// request starts but does not wait on (radio's external artwork
	// lookup) still runs under the recover boundary every WaxDeck
	// goroutine goes through. Nothing here may spawn a bare one.
	workers *supervise.Group
	paths   *pidpath.Cache
	// sealer seals the secrets kept recoverable at rest: app passwords,
	// notification targets, scrobbling credentials and migration secrets.
	sealer *auth.Sealer
	// catalogFile reads a file row, for fileByPID and the similarity
	// sweep; a field so a test can hand it a read that fails.
	catalogFile func(context.Context, model.PID) (*model.File, error)
	// catalogItem reads an item row for the analysis queues; a field so a
	// test can hand one row a read that fails.
	catalogItem func(context.Context, model.PID) (*model.ItemView, error)
	// lookupHost stands in for the resolver behind the server's own
	// address checks (hostAddrs) in a test; nil asks the system's.
	// Nothing in the server sets it.
	lookupHost func(ctx context.Context, host string) ([]net.IPAddr, error)

	// procCtx outlives any one request: async catalog jobs launch on it
	// so a scan survives the 202 that reported it started.
	procCtx context.Context
	// userWake is the lossy wakeup hint the event hub fans out as
	// invalidation frames.
	userWake chan string
	// version mirrors Config.Version.
	version string

	// library owns the catalog's lifecycle (maintenance, suspend, resync).
	library *Library

	Grants   *Grants
	Settings *Settings
	Audit    *Audit
	Jobs     *Jobs

	Radio        *Radio
	Roots        *Roots
	Similarity   *Similarity
	Podcasts     *Podcasts
	Tools        *Tools
	Playlists    *Playlists
	Ingest       *Ingest
	Editor       *Editor
	Enrichment   *Enrichment
	Health       *Health
	Migrate      *Migrate
	Identity     *Identity
	Integrations *Integrations
	Playback     *Playback
	Reads        *Reads
}

// wire builds every domain over c. It runs once, before any method does.
// Each constructor only allocates, so wire is safe on a core whose
// dependencies are nil.
func (c *core) wire(cfg Config) {
	c.Grants = newGrants(c, cfg)
	c.Settings = newSettings(c, cfg)
	c.Audit = newAudit(c, cfg)
	c.Jobs = newJobs(c, cfg)

	c.Radio = newRadio(c, cfg)
	c.Roots = newRoots(c, cfg)
	c.Similarity = newSimilarity(c, cfg)
	c.Podcasts = newPodcasts(c, cfg)
	c.Tools = newTools(c, cfg)
	c.Playlists = newPlaylists(c, cfg)
	c.Ingest = newIngest(c, cfg)
	c.Editor = newEditor(c, cfg)
	c.Enrichment = newEnrichment(c, cfg)
	c.Health = newHealth(c, cfg)
	c.Migrate = newMigrate(c, cfg)
	c.Identity = newIdentity(c, cfg)
	c.Integrations = newIntegrations(c, cfg)
	c.Playback = newPlayback(c, cfg)
	c.Reads = newReads(c, cfg)
}

// getItem fetches an item and enforces that the API prefix fits its
// kind. Tracks and books answer to either prefix: an item's kind can
// change under it (a kind change, a library made to hold audiobooks, a
// retag), and a queue, a playlist or a shelf holding the old form must
// still reach it, while every answer carries the current one. An
// episode's prefix stays its own.
func (l *core) getItem(ctx context.Context, apiItemPID string) (*model.ItemView, error) {
	prefix, pid, ok := parseAPIPID(apiItemPID)
	if !ok || !itemPrefix(prefix) {
		return nil, errNotFound("no item with pid " + apiItemPID)
	}
	it, err := l.lib.Get(ctx, pid)
	if err != nil {
		if KindOf(err) == KindNotFound {
			return nil, errNotFound("no item with pid " + apiItemPID)
		}
		return nil, classify(err)
	}
	if !prefixFitsKind(prefix, it.Kind) {
		return nil, errNotFound("no item with pid " + apiItemPID)
	}
	return it, nil
}

// untilShutdown is ctx without the caller's cancellation or deadline,
// ended instead by the server stopping: work a client may walk away from
// midway, a decision moving files or writing tags, finishes rather than
// stopping half done, and still stops with the server.
func (l *core) untilShutdown(ctx context.Context) (context.Context, context.CancelFunc) {
	ctx, cancel := context.WithCancel(context.WithoutCancel(ctx))
	stop := context.AfterFunc(l.procCtx, cancel)
	return ctx, func() {
		stop()
		cancel()
	}
}

// emitUserEvent appends to the server stream and wakes the hub, whether
// or not the request that made the change is still there. Event loss never
// fails the mutation: the stream is an invalidation signal, not the state.
func (l *core) emitUserEvent(ctx context.Context, userID, kind, itemPID string) {
	if _, err := l.db.AppendEvent(context.WithoutCancel(ctx), userID, kind, itemPID); err != nil {
		l.log.Warn("appending server event", "kind", kind, "err", err)
		return
	}
	select {
	case l.userWake <- userID:
	default:
	}
}

// hostAddrs is a host's addresses: a literal as itself, a name as the
// resolver answers it under ctx.
func (l *core) hostAddrs(ctx context.Context, host string) ([]net.IP, error) {
	if ip := net.ParseIP(host); ip != nil {
		return []net.IP{ip}, nil
	}
	lookup := net.DefaultResolver.LookupIPAddr
	if l.lookupHost != nil {
		lookup = l.lookupHost
	}
	addrs, err := lookup(ctx, host)
	if err != nil {
		return nil, err
	}
	ips := make([]net.IP, len(addrs))
	for i, a := range addrs {
		ips[i] = a.IP
	}
	return ips, nil
}

// hostResolvesPrivate reports whether a hostname or address literal
// resolves to a private address. An empty one, a URL naming only a
// port, is this machine to a dialer and reads as private. Unresolvable
// names read as not-private: the dial-time guard still stands at fetch,
// this only shapes the write-time error.
func (l *core) hostResolvesPrivate(ctx context.Context, host string) bool {
	if host == "" {
		return true
	}
	ips, err := l.hostAddrs(ctx, host)
	return err == nil && slices.ContainsFunc(ips, privateIP)
}

// itemViewsByPID batch-reads item views by pid, archived items
// included: the reconciler must see a trashed member as "the owner
// removed this", never as "vanished, download it again".
func (l *core) itemViewsByPID(ctx context.Context, pids []model.PID) (map[model.PID]*model.ItemView, error) {
	return l.itemsAmong(ctx, pids, func() *query.Builder { return query.New(query.EntityItems) })
}
