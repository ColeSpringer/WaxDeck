package service

import (
	"context"
	"sync/atomic"
)

// Some reads fall back to a partial answer rather than failing: a tag
// spelling read compiles a content rule to match-nothing (contentRuleNode),
// an advisory tag read drops the explicit flags (explicitTrackPIDs), a
// vocabulary read leaves the stored genre labels (facetBuckets), a follow
// set read hides every episode (subscriptionFilter.ensure), a library list
// read hides every episode from a reader with library grants
// (podcastsVisible), and an item's tag read refuses the item
// (allowedByContent). A caller about to cache what it builds watches its
// reads, and serves a build that saw a fallback without keeping it.

type degradedKey struct{}

// degradedNote is one watcher; a fallback marks it and every watcher it
// was opened inside.
type degradedNote struct {
	hit    atomic.Bool
	parent *degradedNote
}

// WatchDegraded returns a context whose reads report a fallback, and a
// func answering whether any read under it fell back.
func WatchDegraded(ctx context.Context) (context.Context, func() bool) {
	parent, _ := ctx.Value(degradedKey{}).(*degradedNote)
	note := &degradedNote{parent: parent}
	return context.WithValue(ctx, degradedKey{}, note), note.hit.Load
}

// noteDegraded marks the watchers ctx carries: a read under it fell back.
func noteDegraded(ctx context.Context) {
	for note, _ := ctx.Value(degradedKey{}).(*degradedNote); note != nil; note = note.parent {
		note.hit.Store(true)
	}
}

// fallbackFault is the failure the test hook injects into a read that
// falls back, named by what it reads; nil outside tests.
func (l *Library) fallbackFault(read string) error {
	if hook := l.trackFacts.fallbackHook; hook != nil {
		return hook(read)
	}
	return nil
}
