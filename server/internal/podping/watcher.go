package podping

import (
	"context"
	"log/slog"
	"time"
)

const (
	// blockInterval is Hive's own: one block every three seconds. The
	// watcher paces on it rather than on a timer of its own, so a run of
	// empty blocks costs one small request per cycle.
	blockInterval = 3 * time.Second
	// blocksPerRange bounds one `get_block_range` call. The API's own cap
	// is 1000; this is the polite fraction of it, and at three seconds a
	// block it is a minute of chain per request.
	blocksPerRange = 20
	// maxLagBlocks is how far behind irreversible the watcher will walk
	// before it gives up on the backlog and jumps to the front. Roughly
	// fifteen minutes of chain. A watcher that was off for an hour has
	// nothing to gain from replaying it: the scheduled refresh already
	// covered every feed in that window, and the pings would each cost a
	// request to somebody else's server for news it already has.
	maxLagBlocks = 300
	// writersEvery is how often the trusted-writer set is re-resolved.
	// Writers are added and retired rarely; the cost of being an hour
	// stale is ignoring a brand new writer's pings for an hour, which
	// polling covers.
	writersEvery = time.Hour
	// writersRetry is how long a failed re-resolve waits before trying
	// again. It exists because the walk keeps running on the stale set:
	// without a next-attempt time of its own, a failing refresh is due
	// on every cycle forever, which turns one deprecated endpoint into
	// a request every three seconds against a donated public node.
	writersRetry = 5 * time.Minute
	// nodeBackoff is the pause after a node error. Long enough not to
	// hammer a public node that is having an afternoon, short enough
	// that a blip costs one cycle.
	nodeBackoff = 30 * time.Second
)

// Watcher walks the chain and hands each trusted ping to a callback.
//
// Never fatal, by construction: every node error is logged and backed
// off, and the worker returns only when its context ends. Podping is a
// floor-lowering signal riding on somebody else's public infrastructure,
// so a watcher that could take a subsystem down with it would be a worse
// trade than not having the feature.
type Watcher struct {
	client *Client
	log    *slog.Logger

	// Notify receives one trusted ping, on the watcher's own goroutine
	// and inline: the walk waits for it.
	//
	// That is deliberate rather than an oversight. A ping naming a feed
	// this server subscribes to is rare - the chain carries the whole
	// podcast internet and a catalog holds a handful of feeds - so the
	// callback is a map lookup that returns almost every time, and the
	// rare slow one is the feed sync the ping existed to cause. A queue
	// between the two would buy nothing and could hold work past the
	// point the scheduled refresh had already done it. The pathological
	// case, a callback slow enough to fall behind the chain, is what the
	// lag guard below is for.
	Notify func(ctx context.Context, ping Ping)

	// pinned is an operator-named writer set, which stands in for the
	// chain-resolved one and is never refreshed.
	pinned map[string]bool

	// sleep exists for the tests, which drive a fixed chain against an
	// httptest node and cannot wait three real seconds a block.
	sleep func(ctx context.Context, d time.Duration) bool
}

// PinWriters fixes the trusted writer set instead of resolving it from
// the chain, for an operator who would rather name it than take
// podping.cloud's. Pinned, it is never refreshed: an operator who typed
// a list meant that list.
func (w *Watcher) PinWriters(accounts []string) {
	if len(accounts) == 0 {
		return
	}
	pinned := make(map[string]bool, len(accounts))
	for _, account := range accounts {
		pinned[account] = true
	}
	w.pinned = pinned
}

// NewWatcher builds a watcher over client.
func NewWatcher(client *Client, log *slog.Logger, notify func(context.Context, Ping)) *Watcher {
	if log == nil {
		log = slog.New(slog.DiscardHandler)
	}
	return &Watcher{client: client, log: log, Notify: notify, sleep: sleepCtx}
}

// sleepCtx waits d, or until ctx ends. It reports whether the wait
// finished rather than the context ending.
func sleepCtx(ctx context.Context, d time.Duration) bool {
	timer := time.NewTimer(d)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return false
	case <-timer.C:
		return true
	}
}

// Run walks the chain until ctx ends. It always returns nil: a watcher
// that reported an error would be restarted by the supervisor with the
// backoff it is already applying itself, and a node outage is not this
// subsystem failing.
func (w *Watcher) Run(ctx context.Context) error {
	var (
		cursor  int64
		writers map[string]bool
		// writersDue is when the set may next be resolved, stamped on
		// every attempt rather than every success. Stamping only
		// successes would leave a failing refresh permanently due.
		writersDue time.Time
		// nodeWarned keeps a node that is failing to one warning per
		// outage instead of one per cycle, while still saying it once:
		// a mistyped --podping-node otherwise fails only at Debug, and
		// is silently dead for as long as the server runs.
		nodeWarned bool
	)
	for ctx.Err() == nil {
		// The writer set first: with none, every operation on the chain
		// is untrusted and the walk would read blocks to reach no
		// conclusion. Better to wait for the list than to spend the
		// requests.
		if len(w.pinned) > 0 {
			writers = w.pinned
		} else if len(writers) == 0 || !time.Now().Before(writersDue) {
			got, err := w.client.Writers(ctx)
			switch {
			case err == nil:
				writers, writersDue = got, time.Now().Add(writersEvery)
			case len(writers) == 0:
				w.log.Warn("podping: reading the writer set", "err", err)
				if !w.sleep(ctx, nodeBackoff) {
					return nil
				}
				continue
			default:
				// A refresh that failed leaves the set that was working
				// in place; it is stale, not wrong. The walk carries on
				// with it, so the retry is on its own slow cadence
				// rather than on the block loop's.
				w.log.Warn("podping: refreshing the writer set; carrying on with the last one",
					"err", err, "retryIn", writersRetry)
				writersDue = time.Now().Add(writersRetry)
			}
		}

		irreversible, err := w.client.LastIrreversible(ctx)
		if err != nil {
			if !nodeWarned {
				w.log.Warn("podping: reading the chain head", "node", w.client.Node(), "err", err)
				nodeWarned = true
			} else {
				w.log.Debug("podping: reading the chain head", "err", err)
			}
			if !w.sleep(ctx, nodeBackoff) {
				return nil
			}
			continue
		}
		nodeWarned = false
		// First cycle: start at the front. Everything before this moment
		// is either already in the catalog or is about to be found by the
		// scheduled refresh, and replaying it would spend a request per
		// feed to learn that.
		if cursor == 0 {
			cursor = irreversible
		}
		if lag := irreversible - cursor; lag > maxLagBlocks {
			w.log.Info("podping: skipping forward", "behind", lag, "to", irreversible-maxLagBlocks)
			cursor = irreversible - maxLagBlocks
		}
		if cursor > irreversible {
			// Caught up: nothing final has been written since the last
			// pass. One block time is the shortest useful wait.
			if !w.sleep(ctx, blockInterval) {
				return nil
			}
			continue
		}
		count := min(int(irreversible-cursor+1), blocksPerRange)
		pings, next, err := w.client.Pings(ctx, cursor, count, writers)
		if err != nil {
			w.log.Debug("podping: reading blocks", "from", cursor, "count", count, "err", err)
			if !w.sleep(ctx, nodeBackoff) {
				return nil
			}
			continue
		}
		if next <= cursor {
			// A node that answered no blocks at all has nothing to give
			// this cycle; advancing anyway would skip a block that
			// exists.
			if !w.sleep(ctx, blockInterval) {
				return nil
			}
			continue
		}
		cursor = next
		for _, ping := range pings {
			if ctx.Err() != nil {
				return nil
			}
			if w.Notify != nil {
				w.Notify(ctx, ping)
			}
		}
		// A full range means there is more chain waiting, so the next
		// pass goes straight on rather than pausing for a block.
		if count < blocksPerRange {
			if !w.sleep(ctx, blockInterval) {
				return nil
			}
		}
	}
	return nil
}
