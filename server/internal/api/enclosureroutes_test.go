package api

import (
	"strconv"
	"testing"
	"time"
)

// The route cache is an optimisation whose whole correctness argument
// is that it gives up easily. These pin the giving up.
func TestEnclosureRoutesLookupAndForget(t *testing.T) {
	t.Parallel()
	var routes enclosureRoutes

	const feedURL = "https://feeds.example/hop/5"

	if _, ok := routes.lookup("tr-one", feedURL); ok {
		t.Fatal("an empty cache answered a lookup")
	}
	routes.remember("tr-one", feedURL, "https://cdn.example/ep.mp3")
	got, ok := routes.lookup("tr-one", feedURL)
	if !ok || got != "https://cdn.example/ep.mp3" {
		t.Fatalf("lookup = %q, %v", got, ok)
	}

	// A feed that repoints the episode is a different chain. Without
	// this the old end would be served for the rest of the TTL, which
	// is the whole episode.
	if _, ok := routes.lookup("tr-one", "https://feeds.example/moved/5"); ok {
		t.Fatal("a route answered for an enclosure it was not walked from")
	}

	routes.forget("tr-one")
	if _, ok := routes.lookup("tr-one", feedURL); ok {
		t.Fatal("a forgotten route came back")
	}

	// Neither half of the pair is a route on its own; recording one
	// would answer later lookups with a URL no request can be built
	// from, or one no lookup can match.
	routes.remember("tr-two", feedURL, "")
	if _, ok := routes.lookup("tr-two", feedURL); ok {
		t.Fatal("an empty resolution was remembered")
	}
	routes.remember("tr-two", "", "https://cdn.example/ep.mp3")
	if _, ok := routes.lookup("tr-two", ""); ok {
		t.Fatal("a route with no origin was remembered")
	}
}

func TestEnclosureRoutesExpire(t *testing.T) {
	t.Parallel()
	var routes enclosureRoutes
	const feedURL = "https://feeds.example/hop/5"
	routes.remember("tr-one", feedURL, "https://cdn.example/ep.mp3")
	// Aged past the TTL in place: the far end of a chain is routinely a
	// signed URL, and what has to hold is that the entry stops being
	// offered rather than that it is swept.
	routes.mu.Lock()
	routes.entries["tr-one"] = enclosureRoute{
		from:    feedURL,
		url:     "https://cdn.example/ep.mp3",
		expires: time.Now().Add(-time.Second),
	}
	routes.mu.Unlock()

	if _, ok := routes.lookup("tr-one", feedURL); ok {
		t.Fatal("an expired route was offered")
	}
	// And an expired entry no longer holds off a warm, which is what
	// refills it.
	if !routes.claimWarm("tr-one", feedURL) {
		t.Fatal("an expired route blocked a warm")
	}
}

func TestEnclosureRoutesWarmIsSingleFlight(t *testing.T) {
	t.Parallel()
	var routes enclosureRoutes
	const feedURL = "https://feeds.example/hop/5"

	if !routes.claimWarm("tr-one", feedURL) {
		t.Fatal("the first warm was refused")
	}
	if routes.claimWarm("tr-one", feedURL) {
		t.Fatal("a second warm walked the same chain")
	}
	// A different episode is a different chain.
	if !routes.claimWarm("tr-two", feedURL) {
		t.Fatal("one warm blocked another episode")
	}
	routes.releaseWarm("tr-one")
	if !routes.claimWarm("tr-one", feedURL) {
		t.Fatal("a released warm stayed claimed")
	}

	// A route already known needs no warm at all.
	routes.releaseWarm("tr-one")
	routes.remember("tr-one", feedURL, "https://cdn.example/ep.mp3")
	if routes.claimWarm("tr-one", feedURL) {
		t.Fatal("a known route was warmed again")
	}
	// But a route known for a different enclosure does.
	if !routes.claimWarm("tr-one", "https://feeds.example/moved/5") {
		t.Fatal("a stale route blocked the warm for the new enclosure")
	}
}

// The map is bounded, so a server that relayed for a large household
// through one TTL still holds a bounded cache.
func TestEnclosureRoutesAreBounded(t *testing.T) {
	t.Parallel()
	var routes enclosureRoutes
	const feedURL = "https://feeds.example/hop/5"
	pidFor := func(i int) string { return "tr-" + strconv.Itoa(i) }
	for i := range maxEnclosureRoutes + 10 {
		routes.remember(pidFor(i), feedURL, "https://cdn.example/ep.mp3")
	}
	routes.mu.Lock()
	size := len(routes.entries)
	routes.mu.Unlock()
	if size > maxEnclosureRoutes {
		t.Fatalf("cache holds %d routes, want at most %d", size, maxEnclosureRoutes)
	}
	// The last write is always the one that survives: it is the route
	// somebody is listening to right now.
	if _, ok := routes.lookup(pidFor(maxEnclosureRoutes+9), feedURL); !ok {
		t.Fatal("the newest route was evicted")
	}
}

// The rule the feed's stored credentials are spent under. A remembered
// URL arrives without the chain that produced it, so the origin
// matching is the only evidence that the far end is still the party the
// feed named.
func TestSameEnclosureOrigin(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name     string
		resolved string
		original string
		want     bool
	}{
		{"the same origin", "https://feeds.example/a.mp3", "https://feeds.example/b.mp3", true},
		{"host case does not matter", "https://FEEDS.example/a.mp3", "https://feeds.example/b.mp3", true},
		{"a plain feed staying plain", "http://feeds.example/a.mp3", "http://feeds.example/b.mp3", true},
		// The one that would send the show's basic-auth over a
		// plaintext connection this server itself opens, and go on
		// doing it for the whole TTL.
		{"a same-host downgrade to http", "http://feeds.example/a.mp3", "https://feeds.example/b.mp3", false},
		{"a port is part of the origin", "https://feeds.example:8443/a.mp3", "https://feeds.example/b.mp3", false},
		// Stricter than Go's own redirect forwarding, deliberately: it
		// keeps Authorization across a subdomain hop and this does not.
		{"a subdomain is a different party", "https://cdn.feeds.example/a.mp3", "https://feeds.example/b.mp3", false},
		{"a CDN is a different party", "https://cdn.other/a.mp3", "https://feeds.example/b.mp3", false},
		{"a hostless resolution matches nothing", "/a.mp3", "https://feeds.example/b.mp3", false},
		{"an unparseable resolution matches nothing", "://nope", "https://feeds.example/b.mp3", false},
	}
	for _, c := range cases {
		if got := sameEnclosureOrigin(c.resolved, c.original); got != c.want {
			t.Errorf("%s: sameEnclosureOrigin(%q, %q) = %v, want %v", c.name, c.resolved, c.original, got, c.want)
		}
	}
}

// The warm is bounded as well as deduplicated: nothing caps how many
// times a client may ask for play-info, and a listener skipping through
// a queue of unfetched episodes asks once per tap.
func TestEnclosureWarmsAreBounded(t *testing.T) {
	t.Parallel()
	var routes enclosureRoutes
	const feedURL = "https://feeds.example/hop/5"
	for i := range maxEnclosureWarms {
		if !routes.claimWarm("tr-"+strconv.Itoa(i), feedURL) {
			t.Fatalf("warm %d was refused below the ceiling", i)
		}
	}
	if routes.claimWarm("tr-over", feedURL) {
		t.Fatal("a warm was claimed past the ceiling")
	}
	// Declining is not losing the chain: the relay walks it, which is
	// what it did before any of this existed. Releasing one makes room
	// again.
	routes.releaseWarm("tr-0")
	if !routes.claimWarm("tr-over", feedURL) {
		t.Fatal("a released slot was not reused")
	}
}
