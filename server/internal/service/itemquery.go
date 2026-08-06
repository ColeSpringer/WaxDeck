package service

import (
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
)

// The base queries every catalog listing builds on.
//
// ADR-0048: present, remote, and missing items belong in a listing;
// archived ones do not. Archiving is what deleting to trash does, so a
// query without the predicate keeps answering with items the listener
// deleted. Two dozen call sites construct one of these queries, so the
// predicate lives here rather than at each of them, and
// `server/cmd/querylint` fails the build on a bare query.New for either
// entity outside this file and its allowlist. The exception list (the
// audits and sweeps whose job is to see everything the catalog holds)
// is in the ADR and in the linter, not in a comment nobody finds.
//
// pi.state is NOT NULL, so the `isNot` comparison misses nothing.

// visibleItems is the base item query: every playable kind, minus what
// is in the trash.
func visibleItems() *query.Builder {
	return unarchived(query.New(query.EntityItems))
}

// visibleTracks is visibleItems narrowed to music tracks by the
// catalog's own entity, which excludes books and episodes.
func visibleTracks() *query.Builder {
	return unarchived(query.New(query.EntityTracks))
}

// unarchived applies the state predicate to a builder. Exported within
// the package for the two call sites that must build their query some
// other way and still filter.
func unarchived(b *query.Builder) *query.Builder {
	return b.Where("state", query.OpIsNot, string(model.StateArchived))
}

// archived reports whether an item view is in the trash. The hydrated
// counterpart to the predicate, for paths that resolve items by pid and
// filter afterwards.
func archived(it *model.ItemView) bool {
	return it != nil && it.State == model.StateArchived
}
