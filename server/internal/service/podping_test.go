package service

import (
	"testing"

	"github.com/colespringer/waxbin/model"
)

// TestNormalizeFeedURL pins what the podping index folds and what it
// leaves alone. Folding too little means a host that pings
// `HTTPS://Example.com/feed.xml` never matches the subscription stored
// as `https://example.com/feed.xml`; folding too much collapses two real
// feeds - a tokenized member feed and its free one differ only in a
// query string - onto one row and syncs the wrong show.
func TestNormalizeFeedURL(t *testing.T) {
	t.Parallel()
	same := [][2]string{
		{"https://example.com/feed.xml", "HTTPS://Example.COM/feed.xml"},
		{"https://example.com/feed.xml", "  https://example.com/feed.xml  "},
		{"https://example.com/feed.xml", "https://example.com:443/feed.xml"},
		{"http://example.com/feed.xml", "http://example.com:80/feed.xml"},
		{"https://example.com", "https://example.com/"},
	}
	for _, pair := range same {
		a, b := normalizeFeedURL(pair[0]), normalizeFeedURL(pair[1])
		if a == "" || a != b {
			t.Errorf("normalize(%q)=%q and normalize(%q)=%q, want one key", pair[0], a, pair[1], b)
		}
	}

	distinct := [][2]string{
		// A path's case is the host's business, not this function's.
		{"https://example.com/Feed.xml", "https://example.com/feed.xml"},
		// The member feed and the free one.
		{"https://example.com/feed.xml?token=abc", "https://example.com/feed.xml"},
		// A trailing slash below the root is a different path, and some
		// hosts serve both.
		{"https://example.com/show/", "https://example.com/show"},
		{"https://example.com/feed.xml", "https://other.example.com/feed.xml"},
	}
	for _, pair := range distinct {
		a, b := normalizeFeedURL(pair[0]), normalizeFeedURL(pair[1])
		if a == b {
			t.Errorf("normalize collapsed %q and %q onto %q", pair[0], pair[1], a)
		}
	}

	// Anything that is not an http(s) URL is not a feed this catalog can
	// hold, and an empty key is what keeps a private show's blank feed
	// URL out of the index - where it would otherwise match every
	// unparseable iri on the chain.
	for _, raw := range []string{
		"", "   ", "mailto:someone@example.com", "ipns://example",
		"example.com/feed.xml", "https://", "://nonsense",
	} {
		if got := normalizeFeedURL(raw); got != "" {
			t.Errorf("normalize(%q) = %q, want no key", raw, got)
		}
	}
}

// TestPodpingSyncFloor covers the per-show minimum interval. A busy
// network puts several notifications on the chain for one publish - a
// writer retrying, a host pinging its live and update states together -
// and without a floor each one is a request to the host for the same
// episode.
func TestPodpingSyncFloor(t *testing.T) {
	t.Parallel()
	l := &Library{}
	const show = "pc-01JZX5N8QW3F4V9T2B7KD3M9R6"
	if !l.claimPodpingSync(show) {
		t.Fatal("the first ping for a show was refused")
	}
	if l.claimPodpingSync(show) {
		t.Error("a second ping inside the floor claimed a sync")
	}
	// The floor is per show: one busy feed must not mute another.
	if !l.claimPodpingSync("pc-01JZX5N8QW3F4V9T2B7KD3M9R7") {
		t.Error("a different show was held behind the first one's floor")
	}
}

// TestPodpingIndexInvalidationSurvivesARebuild covers the race the
// generation counter exists for.
//
// The index is built outside the lock, because building it is a catalog
// read and holding the mutex across one would stall every notification
// behind it. That leaves a window: a subscription landing mid-build
// invalidates an index that is about to be replaced by a snapshot taken
// before it. Committing that snapshot unconditionally would hide the
// new show and mark the result fresh for a full TTL, so its first ping
// - and every ping for five minutes - would find nothing, which is
// exactly what invalidating on subscribe was added to prevent.
func TestPodpingIndexInvalidationSurvivesARebuild(t *testing.T) {
	t.Parallel()
	l := &Library{}
	const feed = "https://example.com/feed.xml"

	// A build begins and reads the generation it started from.
	l.podping.mu.Lock()
	gen := l.podping.gen
	l.podping.mu.Unlock()

	// A subscription lands while that build is still reading.
	l.InvalidatePodpingFeeds()

	// The build finishes and offers its pre-subscription snapshot.
	stale := map[string]model.PID{feed: "pc-01JZX5N8QW3F4V9T2B7KD3M9R6"}
	if got := l.commitPodpingIndex(stale, gen); len(got) != 1 {
		t.Fatalf("the caller was not given an index to answer with: %v", got)
	}
	l.podping.mu.Lock()
	cached, built := l.podping.byFeed, l.podping.built
	l.podping.mu.Unlock()
	if cached != nil || !built.IsZero() {
		t.Fatal("a snapshot taken before an invalidation was cached as fresh")
	}

	// A build that started after the invalidation commits normally.
	l.podping.mu.Lock()
	gen = l.podping.gen
	l.podping.mu.Unlock()
	l.commitPodpingIndex(stale, gen)
	l.podping.mu.Lock()
	cached, built = l.podping.byFeed, l.podping.built
	l.podping.mu.Unlock()
	if cached == nil || built.IsZero() {
		t.Fatal("an uncontested rebuild did not cache")
	}
}
