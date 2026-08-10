package service

import (
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
)

// The base queries every catalog listing builds on.
//
// Present, remote, and missing items belong in a listing;
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

// unarchived applies the state predicate to a builder.
//
// Named rather than inlined so the predicate has one spelling where a
// builder is what is in hand. It is not the only spelling in the tree,
// and that is worth knowing before renaming the field or adding a
// fourth state: playlists.go's withoutArchived conjoins the same
// condition onto a rule's node tree, which is not a builder and cannot
// call this, and `archived` below asks the same question of a hydrated
// view. Three encodings, one meaning.
func unarchived(b *query.Builder) *query.Builder {
	return b.Where("state", query.OpIsNot, string(model.StateArchived))
}

// archived reports whether an item view is in the trash. The hydrated
// counterpart to the predicate, for paths that resolve items by pid and
// filter afterwards.
func archived(it *model.ItemView) bool {
	return it != nil && it.State == model.StateArchived
}

// listableStates is the same rule as an allow-list, for the one
// surface that takes states rather than a predicate:
// read.SearchOptions.States. The fourth encoding named in `unarchived`
// above, and the one that needs watching, because it inverts the others.
//
// The other three say "not archived", so a fifth state would be listable
// by default; this one says "these three", so a fifth would be hidden by
// default. Upstream chose that deliberately - an empty States means no
// narrowing, so a call site forgotten at the next addition reverts to
// today's behavior rather than failing - which is exactly why the set is
// named once here instead of spelled at the call site.
var listableStates = []model.ItemState{
	model.StatePresent, model.StateRemote, model.StateMissing,
}
