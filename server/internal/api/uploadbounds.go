package api

import (
	"sync"
	"time"
)

// The bound on how fast one account may work the upload surface.
//
// Everything under /uploads and /acquisitions needs an upload grant and
// spends real resources per request: opening a session makes a staging
// directory and a row, a chunk writes and fsyncs, a completion hashes
// and parses a whole file. The *bytes* are bounded three ways already -
// the caller's quota, the per-session ceiling, and the room on the
// staging volume - but the request count was not, so a client that
// stopped waiting for its own answers could hold the server in a loop
// none of those three ever notices.
//
// Three things stay outside it, and the reasons differ.
//
// The two listings, because the uploads screen refetches while a
// transfer runs and a limiter counting those would spend the
// transfer's own budget on watching it.
//
// The chunk endpoint, because charging it makes this a throughput
// ceiling rather than a pace. A client sends 1 MiB a chunk and a fast
// link carries hundreds a second, so a token per chunk caps a transfer
// at the refill rate in megabytes - and the answer is a 429 in the
// middle of a folder upload, which the client reports as a failed file
// rather than backing off. Its bytes are bounded three other ways
// already: the per-request chunk cap, the session's declared size, and
// the room on the volume.
//
// And the discard, because it is the call that gives room back. Pacing
// it means a client that spent its bucket pushing a folder cannot
// clear what the failures left behind until the bucket refills, while
// the reservations it is trying to release keep refusing everybody
// else's uploads.
const (
	// uploadBurst is what an account may spend at once. What is left to
	// charge is the durable state: opening a session, sealing one,
	// opening or finalizing a batch, starting an acquisition. A folder
	// of a thousand files spends two of these a file and is nowhere
	// near this once the refill is counted.
	uploadBurst = 600

	// uploadRefill is the sustained ceiling, per second. Sixty sessions
	// a second is far past any transfer that is actually moving bytes;
	// what it stops is the loop that is not.
	uploadRefill = 60
)

// uploadGate is a token bucket per account.
//
// Keyed by account rather than by address, which is why it needs no
// sweep: the key space is the user table, where the sign-in limiter's
// is whatever an attacker dials from. The zero value works.
type uploadGate struct {
	mu      sync.Mutex
	buckets map[string]*uploadBucket
	now     func() time.Time // test seam
}

type uploadBucket struct {
	tokens float64
	last   time.Time
}

// allow spends one token for userID and reports whether there was one.
func (g *uploadGate) allow(userID string) bool {
	g.mu.Lock()
	defer g.mu.Unlock()
	now := time.Now
	if g.now != nil {
		now = g.now
	}
	at := now()
	if g.buckets == nil {
		g.buckets = map[string]*uploadBucket{}
	}
	b, ok := g.buckets[userID]
	if !ok {
		b = &uploadBucket{tokens: uploadBurst, last: at}
		g.buckets[userID] = b
	}
	// Refilled from elapsed time rather than on a ticker, so an idle
	// account costs nothing and a restart starts everyone full.
	if elapsed := at.Sub(b.last); elapsed > 0 {
		b.tokens = min(uploadBurst, b.tokens+elapsed.Seconds()*uploadRefill)
		b.last = at
	}
	if b.tokens < 1 {
		return false
	}
	b.tokens--
	return true
}
