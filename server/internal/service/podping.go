package service

import (
	"context"
	"net/url"
	"strings"
	"sync"
	"time"

	"github.com/colespringer/waxbin/model"
)

const (
	// podpingIndexTTL is how long the feed-URL index stands before it is
	// rebuilt from the catalog. A subscription change invalidates it
	// directly, so this is the backstop for the paths that change the
	// catalog without going through the subscribe verbs (an OPML import
	// on another process, a restore).
	podpingIndexTTL = 5 * time.Minute
	// podpingMinInterval is the floor between two podping-driven syncs of
	// one show. Podping is a per-episode signal and a busy network puts
	// several notifications on the chain for one publish - a writer
	// retrying, a host pinging its live and update states together, two
	// writers relaying one iri - so without a floor a single episode
	// costs several requests to the host. Well under the scheduled
	// refresh, which is the point of the feature; no tighter than the
	// floor a subscriber's own manual refresh keeps, because a stranger
	// on a public chain should not be able to make this server fetch a
	// feed more often than its own listener can.
	//
	// It is enforced against feed_state, not only against the in-process
	// map: the map dies with the process, and a restart loop under a
	// busy writer would otherwise have no floor at all.
	podpingMinInterval = time.Minute
)

// podpingIndex maps feed URLs to the shows that hold them, so a chain
// notification naming a feed resolves without a catalog scan per ping.
type podpingIndex struct {
	mu     sync.Mutex
	byFeed map[string]model.PID
	built  time.Time
	// gen counts invalidations. A rebuild reads it before it starts and
	// commits only if it has not moved, so a subscription landing
	// mid-rebuild is not overwritten by the snapshot taken before it -
	// which would leave the new show unreachable, and marked fresh, for
	// a whole TTL.
	gen uint64
	// synced is the last podping-driven sync per show, which is what the
	// in-process half of the floor is measured from.
	synced map[model.PID]time.Time
}

// NotePodping acts on one chain notification: if the iri names a feed
// this catalog holds, sync that show now.
//
// It drives the same syncShow the scheduled refresh does rather than a
// second sync path, so a podping-driven arrival is indistinguishable
// from a scheduled one - the same auto-download, the same retention
// pass, the same feed-state bookkeeping, the same failure handling.
//
// A feed nobody here subscribes to is the overwhelmingly common case:
// the chain carries every host's pings, and this catalog holds a
// handful of feeds. That path is a map lookup and nothing else.
func (l *Library) NotePodping(ctx context.Context, iri string) {
	key := normalizeFeedURL(iri)
	if key == "" {
		return
	}
	index, err := l.podpingFeeds(ctx)
	if err != nil {
		l.log.Debug("podping: reading subscribed feeds", "err", err)
		return
	}
	show, ok := index[key]
	if !ok {
		return
	}
	st, err := l.db.FeedStateFor(ctx, string(show))
	if err != nil {
		l.log.Debug("podping: reading feed state", "show", string(show), "err", err)
		return
	}
	// The same skip the scheduler applies. A feed disabled after
	// repeated failures is disabled until somebody asks for it by hand;
	// a stranger's chain notification is not somebody asking, and
	// honouring it would undo the backoff the disable exists to impose.
	if st.Disabled {
		return
	}
	// The durable half of the floor. Every other refresh path keeps one
	// - the scheduler against LastAttemptNS, a manual refresh against
	// LastSyncedNS - and podping is driven by third parties, so it is
	// the path that most needs a floor that outlives the process.
	if recent(st.LastAttemptNS, podpingMinInterval) || recent(st.LastSyncedNS, podpingMinInterval) {
		return
	}
	if !l.claimPodpingSync(show) {
		return
	}
	added, err := l.syncShow(ctx, show, syncPinged)
	if err != nil {
		// The attempt is stamped and the failure deliberately uncounted
		// (see syncPinged); a feed that cannot be reached is not this
		// watcher failing.
		l.log.Debug("podping: sync failed", "show", string(show), "err", err)
		return
	}
	if added > 0 {
		l.log.Info("podping: new episodes", "show", string(show), "added", added)
	}
}

// InvalidatePodpingFeeds drops the feed index, so the next notification
// rebuilds it. Called wherever a subscription is added or removed: a
// show subscribed a moment ago must be reachable by its first ping, not
// by the next rebuild.
func (l *Library) InvalidatePodpingFeeds() {
	l.podping.mu.Lock()
	defer l.podping.mu.Unlock()
	l.podping.byFeed = nil
	l.podping.built = time.Time{}
	l.podping.gen++
}

// podpingFeeds answers the feed-URL index, rebuilding it when stale.
func (l *Library) podpingFeeds(ctx context.Context) (map[string]model.PID, error) {
	l.podping.mu.Lock()
	if l.podping.byFeed != nil && time.Since(l.podping.built) < podpingIndexTTL {
		index := l.podping.byFeed
		l.podping.mu.Unlock()
		return index, nil
	}
	gen := l.podping.gen
	l.podping.mu.Unlock()

	// Built outside the lock: it is a catalog read, and holding the
	// mutex across it would stall every notification behind it. Two
	// racing builds produce the same map, and the second one wins
	// harmlessly.
	//
	// Subscribed shows only, which is what the scheduled refresh walks.
	// A show sitting in the catalog that nobody follows is work for
	// nobody, and syncing it on a ping would be a request to somebody
	// else's server on behalf of no listener.
	subscribed, err := l.db.SubscribedShowPIDs(ctx)
	if err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	if len(subscribed) == 0 {
		return l.commitPodpingIndex(map[string]model.PID{}, gen), nil
	}
	followed := make(map[string]bool, len(subscribed))
	for _, pid := range subscribed {
		followed[pid] = true
	}
	shows, err := l.lib.Podcasts().List(ctx)
	if err != nil {
		return nil, classify(err)
	}
	index := make(map[string]model.PID, len(subscribed))
	for _, show := range shows {
		if !followed[string(show.PID)] {
			continue
		}
		key := normalizeFeedURL(show.FeedURL)
		if key == "" {
			continue
		}
		index[key] = show.PID
	}
	return l.commitPodpingIndex(index, gen), nil
}

// commitPodpingIndex caches a freshly built index, unless an
// invalidation arrived while it was being built. It always returns an
// index to use now: the snapshot is good enough to answer the ping in
// hand, it is only unfit to be cached as fresh.
func (l *Library) commitPodpingIndex(index map[string]model.PID, gen uint64) map[string]model.PID {
	l.podping.mu.Lock()
	defer l.podping.mu.Unlock()
	if l.podping.gen != gen {
		return index
	}
	l.podping.byFeed, l.podping.built = index, time.Now()
	return index
}

// recent reports whether a feed_state timestamp is inside d. A zero
// stamp is "never", which is not recent.
func recent(ns int64, d time.Duration) bool {
	return ns > 0 && time.Since(time.Unix(0, ns)) < d
}

// claimPodpingSync reports whether this show may be synced now, and
// records the attempt when it may.
func (l *Library) claimPodpingSync(show model.PID) bool {
	l.podping.mu.Lock()
	defer l.podping.mu.Unlock()
	if l.podping.synced == nil {
		l.podping.synced = map[model.PID]time.Time{}
	}
	if time.Since(l.podping.synced[show]) < podpingMinInterval {
		return false
	}
	l.podping.synced[show] = time.Now()
	return true
}

// normalizeFeedURL folds the differences between two spellings of one
// feed address that neither the host nor the subscriber chose:
// scheme and host case, a default port, and a trailing slash on the
// root. Everything else is left exactly as written, because a feed URL
// is opaque to everyone but the host - a query string, a case-sensitive
// path, a tokenized member feed - and folding more would collapse two
// real feeds onto one.
//
// It returns "" for anything that is not an http(s) URL, which is what
// keeps a private show's empty feed URL out of the index.
func normalizeFeedURL(raw string) string {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return ""
	}
	u, err := url.Parse(trimmed)
	if err != nil {
		return ""
	}
	scheme := strings.ToLower(u.Scheme)
	if scheme != "http" && scheme != "https" {
		return ""
	}
	host := strings.ToLower(u.Host)
	if (scheme == "http" && strings.HasSuffix(host, ":80")) ||
		(scheme == "https" && strings.HasSuffix(host, ":443")) {
		host = host[:strings.LastIndex(host, ":")]
	}
	if host == "" {
		return ""
	}
	u.Scheme, u.Host = scheme, host
	if u.Path == "/" {
		u.Path = ""
	}
	return u.String()
}
