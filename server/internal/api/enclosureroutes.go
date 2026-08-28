package api

import (
	"net/url"
	"strings"
	"sync"
	"time"
)

const (
	// How long a resolved chain is worth trying again. Short on
	// purpose: the far end of an ad-fronted enclosure chain is
	// routinely a signed, expiring CDN URL, so an entry is a shortcut
	// worth attempting rather than an address worth trusting.
	enclosureRouteTTL = 5 * time.Minute

	// A ceiling on remembered chains, so a server that has relayed
	// thousands of episodes inside one TTL still holds a bounded map.
	// Reached only by a listening population far larger than the relay
	// gate allows at once.
	maxEnclosureRoutes = 1024

	// A ceiling on chains being walked at once. The relay itself is
	// capped per account (`relayStreams`, eight); nothing caps how many
	// times a client may ask for play-info, and a listener skipping
	// through a queue of unfetched episodes asks once per tap. Without
	// this that is one goroutine and one upstream socket per tap. Past
	// the ceiling the warm is simply declined, which leaves the relay
	// to walk the chain itself - the behaviour before any of this
	// existed.
	maxEnclosureWarms = 16
)

// enclosureRoute is where one episode's enclosure chain ended, and
// until when that is worth believing.
type enclosureRoute struct {
	// from is the feed's own enclosure URL the walk started at. An
	// entry answers only for the URL that produced it: a feed that
	// repoints an episode at different audio would otherwise be served
	// the old end for the rest of the TTL.
	from    string
	url     string
	expires time.Time
}

// enclosureRoutes remembers the far end of each episode's redirect
// chain, so a listener's second range does not walk it again.
//
// A real enclosure is fronted by measurement prefixes - a verified
// example walks podtrac, claritas, pdst, mgln, and pscrb before art19
// and its CDN answer, seven hops - and a media element re-ranges on
// every seek and every refill. Each of those paid the whole walk, which
// is what a listener felt as a slow first play and a slow scrub.
//
// Correctness rests on one rule rather than on the entries being right:
// anything that goes wrong with a remembered URL drops it and falls
// back to the full chain, once. So a signed URL that expired early, a
// host that rotated its edge, and a chain that now ends somewhere else
// all cost one wasted request and then behave exactly as they did
// before this existed.
//
// Usable at its zero value; the maps are made under the lock.
type enclosureRoutes struct {
	mu      sync.Mutex
	entries map[string]enclosureRoute
	// warming holds the pids a background resolve is already walking,
	// so a queue of five taps on one show does not walk one chain five
	// times over.
	warming map[string]struct{}
}

// lookup answers the remembered end of pid's chain, if it is still
// worth trying and still describes the enclosure the feed names now.
func (c *enclosureRoutes) lookup(pid, from string) (string, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	entry, ok := c.entries[pid]
	if !ok || entry.from != from || time.Now().After(entry.expires) {
		return "", false
	}
	return entry.url, true
}

// remember records where pid's chain ended. Only a walk of the full
// chain may call this: re-recording a cached URL would let one entry
// live past every expiry the far end signed it for, and every renewal
// would be paid for by a listener whose range failed first.
func (c *enclosureRoutes) remember(pid, from, resolved string) {
	if from == "" || resolved == "" {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.entries == nil {
		c.entries = map[string]enclosureRoute{}
	}
	if len(c.entries) >= maxEnclosureRoutes {
		now := time.Now()
		for key, entry := range c.entries {
			if now.After(entry.expires) {
				delete(c.entries, key)
			}
		}
		// Still full of live entries: the map is the optimisation, not
		// the truth, so dropping it costs round trips and nothing else.
		if len(c.entries) >= maxEnclosureRoutes {
			clear(c.entries)
		}
	}
	c.entries[pid] = enclosureRoute{
		from:    from,
		url:     resolved,
		expires: time.Now().Add(enclosureRouteTTL),
	}
}

// forget drops pid's remembered chain, which is what every failure
// against it does.
func (c *enclosureRoutes) forget(pid string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	delete(c.entries, pid)
}

// claimWarm reserves pid for one background resolve, answering false
// when another is already walking it, the answer is already known, or
// too many chains are being walked at once.
func (c *enclosureRoutes) claimWarm(pid, from string) bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	if entry, ok := c.entries[pid]; ok && entry.from == from && time.Now().Before(entry.expires) {
		return false
	}
	if _, ok := c.warming[pid]; ok {
		return false
	}
	if len(c.warming) >= maxEnclosureWarms {
		return false
	}
	if c.warming == nil {
		c.warming = map[string]struct{}{}
	}
	c.warming[pid] = struct{}{}
	return true
}

func (c *enclosureRoutes) releaseWarm(pid string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	delete(c.warming, pid)
}

// sameEnclosureOrigin reports whether a resolved URL ends on the same
// scheme and host the feed named.
//
// The rule the feed's stored credentials are spent under, and stricter
// than Go's own redirect forwarding, which keeps an Authorization
// header across a subdomain hop. A remembered URL is used without the
// chain that produced it, so there is no evidence here that the far end
// is still the same party the feed pointed at; the origin matching is
// the only evidence available. Getting it wrong the safe way costs a
// 401, which invalidates the entry and walks the chain properly.
//
// The scheme is half of it, not a detail: an https feed whose chain
// ends at a same-host http rewrite would otherwise have this server
// open a plaintext connection of its own carrying the show's basic-auth
// in a base64 header, and go on doing it for the whole TTL. That is not
// what Go's rule permits either - there the credentials ride a request
// the client chose to follow, rather than a connection this server
// originates.
func sameEnclosureOrigin(resolved, original string) bool {
	a, err := url.Parse(resolved)
	if err != nil {
		return false
	}
	b, err := url.Parse(original)
	if err != nil {
		return false
	}
	return a.Host != "" && strings.EqualFold(a.Host, b.Host) &&
		strings.EqualFold(a.Scheme, b.Scheme)
}
