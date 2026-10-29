package service

import (
	"cmp"
	"context"
	"crypto/sha256"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/colespringer/waxbin/playlist"
)

// The catalog's resolutions of M3U8 documents are held a short while, so
// the preview the app asks for before an import and the import itself
// resolve a document once: a relative path line is a scan of every file's
// path, half a minute for a long document on a large catalog.
const (
	// m3uHeld is how many documents are held, and m3uHeldLines how many
	// path lines across them: two documents as long as one may be.
	m3uHeld      = 4
	m3uHeldLines = 2 * maxM3ULines
	// m3uHeldFor is how long one is held: time to read a preview and import.
	m3uHeldFor = 5 * time.Minute
)

// m3uKey names one resolution: the document, and the catalog position it
// was resolved at.
type m3uKey struct {
	doc [sha256.Size]byte
	pos int64
}

// m3uResolutions holds the latest resolutions, oldest first. A resolution
// is the catalog's, whoever asked for it, so every use filters it through
// its own caller's reach. The zero value works; the bounds and the clock
// are test seams, zero for the constants and the system's.
type m3uResolutions struct {
	mu      sync.Mutex
	entries []m3uResolution
	lines   int

	held, heldLines int
	heldFor         time.Duration
	now             func() time.Time
}

type m3uResolution struct {
	key     m3uKey
	matches []playlist.M3UMatch
	at      time.Time
}

func (c *m3uResolutions) clock() time.Time {
	if c.now != nil {
		return c.now()
	}
	return time.Now()
}

// get answers a held resolution.
func (c *m3uResolutions) get(key m3uKey) ([]playlist.M3UMatch, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.expireLocked()
	for _, e := range c.entries {
		if e.key == key {
			return e.matches, true
		}
	}
	return nil, false
}

// put holds a resolution, letting the oldest go until the bounds hold. One
// longer than the line bound is not held.
func (c *m3uResolutions) put(key m3uKey, matches []playlist.M3UMatch) {
	held, heldLines := cmp.Or(c.held, m3uHeld), cmp.Or(c.heldLines, m3uHeldLines)
	if len(matches) > heldLines {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	c.expireLocked()
	c.entries = slices.DeleteFunc(c.entries, func(e m3uResolution) bool {
		if e.key == key {
			c.lines -= len(e.matches)
			return true
		}
		return false
	})
	c.entries = append(c.entries, m3uResolution{key: key, matches: matches, at: c.clock()})
	c.lines += len(matches)
	for len(c.entries) > held || c.lines > heldLines {
		c.lines -= len(c.entries[0].matches)
		c.entries = slices.Delete(c.entries, 0, 1)
	}
}

// expireLocked lets go of what was held past its time, the oldest first.
func (c *m3uResolutions) expireLocked() {
	life, now := cmp.Or(c.heldFor, m3uHeldFor), c.clock()
	n := 0
	for n < len(c.entries) && now.Sub(c.entries[n].at) >= life {
		c.lines -= len(c.entries[n].matches)
		n++
	}
	c.entries = slices.Delete(c.entries, 0, n)
}

// m3uMatches is the catalog's resolution of an M3U8 document: the one held
// for this document at the catalog's current position, else a fresh one,
// held for the next caller.
func (l *Library) m3uMatches(ctx context.Context, content string) ([]playlist.M3UMatch, error) {
	// Read before the resolve: a change landing during it moves the
	// position past the one this resolution is held under.
	pos, ok := l.m3uPosition(ctx)
	key := m3uKey{doc: sha256.Sum256([]byte(content)), pos: pos}
	if ok {
		if matches, held := l.m3us.get(key); held {
			return matches, nil
		}
	}
	if l.m3uResolveHook != nil {
		l.m3uResolveHook()
	}
	matches, err := l.lib.Playlists().ResolveM3U8(ctx, strings.NewReader(content))
	if err == nil && ok {
		l.m3us.put(key, matches)
	}
	return matches, err
}

// m3uPosition is the catalog position a resolution is held under: the
// last change to the catalog's content, its generation included. False
// when the change log could not be read; nothing is then reused or held.
func (l *Library) m3uPosition(ctx context.Context) (int64, bool) {
	st, ok := l.watchLook(ctx)
	return st.gen<<40 | st.content, ok
}
