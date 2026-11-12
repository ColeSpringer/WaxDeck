package service

import (
	"context"
	"sort"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
)

// members answers a playlist's members as its owner evaluates
// them, before the caller's own filtering.
//
// A smart list goes through the unpaged evaluator rather than
// Playlists().Items, because Items evaluates the stored rule in SQL and
// leaves the state predicate to be applied in Go afterwards - so the
// rule's own Limit and LimitMode were spent on rows that the archived
// filter then dropped, and a `limit: 25` list holding five trashed rows
// came back with 20. evaluableRule conjoins the predicate
// into the query, so the limit is applied to what survives it.
//
// The user pid is the owner's, not the caller's: a shared smart list
// evaluates against its owner's user state, which is the contract
// Playlists.Items documents. PreviewRule passes the caller's pid because
// a preview is stateless and belongs to whoever is typing; copying that
// argument here would silently evaluate a shared `played = false` rule
// against each reader.
func (l *Playlists) members(ctx context.Context, pl *model.Playlist) ([]*model.ItemView, error) {
	if l.memberReadHook != nil {
		l.memberReadHook(pl)
	}
	if pl.Kind != model.PlaylistStatic && pl.Rule != nil {
		items, err := l.lib.Query(ctx, evaluableRule(*pl.Rule), pl.OwnerPID)
		if err != nil {
			return nil, classify(err)
		}
		return items, nil
	}
	items, err := l.lib.Playlists().Items(ctx, pl.PID, pl.OwnerPID)
	if err != nil {
		return nil, classify(err)
	}
	return items, nil
}

// memberFilter is the caller's own view of a playlist's membership:
// what the owner's evaluation holds, narrowed to what this reader is
// offered. One spelling, because the owner's listing, the share page,
// and the count all have to agree.
type memberFilter struct {
	uc   *UserCtx
	subs *subscriptionFilter
	// keepArchived honours a rule that names `state` for itself rather
	// than guessing which arm it meant. A smart list's query already
	// applied the predicate, so this only matters for the exempt case;
	// a static list has no rule and always filters.
	keepArchived bool
	// tagsAllowed, when set, is the tag-rule verdict for the members,
	// read in one pass beforehand (withTagVerdicts); nil asks per item.
	tagsAllowed map[model.PID]bool
}

func (l *Playlists) newMemberFilter(uc *UserCtx, pl *model.Playlist) memberFilter {
	return memberFilter{
		uc:           uc,
		subs:         l.Podcasts.newSubscriptionFilter(uc),
		keepArchived: pl.Rule != nil && ruleNamesState(pl.Rule.Where),
	}
}

// memberVisible reports whether one stored member is offered to this
// caller.
//
// viewVisible, not itemVisible: the members are fresh item views, so the
// library handle is a field already in hand. itemVisible takes a pid and
// resolves it through the located-path cache, which on a listing page
// meant one cache lookup per member per playlist - a page of fifty
// three-hundred-member lists is fifteen thousand of them, for an answer
// sitting in the row. It is also the more correct of the two for the
// same reason the sync paths prefer it.
func (l *Playlists) memberVisible(ctx context.Context, f memberFilter, it *model.ItemView) bool {
	if archived(it) && !f.keepArchived {
		return false
	}
	if !l.Grants.viewVisible(ctx, f.uc, it) {
		return false
	}
	if !f.subs.allowsItem(ctx, l.Podcasts, it) {
		return false
	}
	return l.Grants.contentAllows(ctx, f.uc, f.tagsAllowed, it)
}

// withTagVerdicts reads the tag-rule verdict for every member at once,
// one query per 400, for a caller tag rules narrow: allowedByContent
// asks the catalog for each member's tags, a read per member of every
// list such a caller counts, opens or exports. contentRuleNode is the
// structural mirror of the per-item rule, so the verdicts agree with it.
// Episodes and trashed members stay per item (the advisory flags are a
// field on the view; a trashed member is rare and outside the query).
func (l *Playlists) withTagVerdicts(ctx context.Context, f memberFilter, members []*model.ItemView) (memberFilter, error) {
	allowed, err := l.Grants.tagVerdicts(ctx, f.uc, members)
	if err != nil {
		return f, err
	}
	f.tagsAllowed = allowed
	return f, nil
}

// staticMemberNarrow is memberVisible as a query node: the clauses that
// decide whether a static list's member is offered to this caller, in
// the form CountItems takes.
//
// It tracks memberVisible clause for clause, which is the invariant that
// keeps a count and its listing from disagreeing. A static list carries
// no rule, so keepArchived is never set and the state predicate always
// applies; the grants and the episode rule are callerScopeNode; and the
// content rules are contentRuleNode plus the advisory flags, which
// contentRuleNode leaves to the per-item pass (both read 0 off a
// non-episode).
func (l *Playlists) staticMemberNarrow(ctx context.Context, uc *UserCtx) query.Node {
	return query.And{Nodes: []query.Node{
		query.Cond{Field: "state", Op: query.OpIsNot, Value: string(model.StateArchived)},
		l.readerNarrow(ctx, uc),
	}}
}

// readerNarrow is staticMemberNarrow without the state clause: what this
// caller may be offered whatever the item's state, for a query that
// decides state itself.
func (l *Playlists) readerNarrow(ctx context.Context, uc *UserCtx) query.Node {
	return l.listingNarrow(ctx, uc, l.Podcasts.newSubscriptionFilter(uc), true)
}

// listingNarrow is readerNarrow reading the follow set through subs, so a
// listing that checks its page's rows against the same filter afterwards
// reads the set once. Without episodes the follow arm, and its read, are
// dropped, for a query that already leaves episodes out.
func (l *Playlists) listingNarrow(ctx context.Context, uc *UserCtx, subs *subscriptionFilter, episodes bool) query.Node {
	return query.And{Nodes: append([]query.Node{l.callerScopeNode(ctx, uc, subs, episodes)}, l.Grants.contentNarrow(ctx, uc)...)}
}

// callerScopeNode is what a listing may offer this caller, as a query
// node: the libraries granted (Grants.node, the form viewVisible asks for
// per item), unless the caller sees every library, and episodes only of
// shows the caller follows, read through subs. Pushed into a listing's
// query, a page comes back full where filtering after the cut left it
// short or empty. Without episodes the follow arm is left off: the query
// it joins already holds none, so the arm would cost a read to say
// nothing.
//
// The two empty cases both fail closed on purpose, matching the per-item
// filters. No grants compiles to `1=0` and offers nothing. No
// subscriptions makes the second arm of the Or `1=0`, leaving "anything
// that is not an episode" - which is what allowsEpisode answers for an
// empty set. A subscription read that fails is the same answer for the
// same reason, logged rather than propagated so a podcast outage costs a
// listing its episodes rather than the listing.
func (l *Playlists) callerScopeNode(ctx context.Context, uc *UserCtx, subs *subscriptionFilter, episodes bool) query.Node {
	var nodes []query.Node
	if grants := l.Grants.node(ctx, uc); grants != nil {
		nodes = append(nodes, grants)
	}
	if !episodes {
		return query.And{Nodes: nodes}
	}
	subs.ensure(ctx, l.Podcasts)
	shows := make([]string, 0, len(subs.set))
	if !subs.failed {
		for show := range subs.set {
			shows = append(shows, show)
		}
		sort.Strings(shows)
	}
	nodes = append(nodes, query.Or{Nodes: []query.Node{
		query.Cond{Field: "kind", Op: query.OpIsNot, Value: string(model.KindEpisode)},
		inSet("podcast_pid", shows),
	}})
	return query.And{Nodes: nodes}
}

// inSet is field membership within the engine's per-condition value cap
// (waxbin's maxInValues, catalogSetCap), chunked into an Or above it -
// its own docs say a caller needing more should chunk. Without this, a
// caller following 500+ shows or granted 500+ libraries would fail the
// count's compile and read null counts forever. An empty set stays one
// empty OpIn, which compiles to match-nothing: both callers fail closed
// on purpose.
func inSet(field string, values []string) query.Node {
	if len(values) <= catalogSetCap {
		return query.Cond{Field: field, Op: query.OpIn, Values: query.Values(values)}
	}
	chunks := make([]query.Node, 0, (len(values)+catalogSetCap-1)/catalogSetCap)
	for start := 0; start < len(values); start += catalogSetCap {
		end := min(start+catalogSetCap, len(values))
		chunks = append(chunks, query.Cond{
			Field: field, Op: query.OpIn, Values: query.Values(values[start:end]),
		})
	}
	return query.Or{Nodes: chunks}
}

// visibleMemberCount counts a playlist's members as this caller sees
// them.
//
// A static list counts in the engine: membership is a query dimension
// now, so the whole thing is one indexed COUNT rather than hydrating
// every member to filter it in Go. It counts entries, not distinct
// items, which is what the listing beside it shows - a list holding a
// track twice reads 2.
//
// A smart list deliberately does not, even though CountItems serves both
// kinds. WaxDeck evaluates a stored rule through evaluableRule, which
// conjoins the archived predicate *before* the rule's own limit;
// CountItems evaluates the rule as stored. For a limited
// rule over a list holding archived members the two disagree, and the
// half that has to be right is the one the member listing uses.
func (l *Playlists) visibleMemberCount(ctx context.Context, uc *UserCtx, pl *model.Playlist, narrow query.Node) (int, error) {
	if pl.Kind == model.PlaylistStatic {
		if narrow == nil {
			narrow = l.staticMemberNarrow(ctx, uc)
		}
		n, err := l.lib.Playlists().CountItems(ctx, pl.PID, pl.OwnerPID, narrow)
		if err != nil {
			return 0, classify(err)
		}
		return n, nil
	}
	members, err := l.members(ctx, pl)
	if err != nil {
		return 0, err
	}
	f, err := l.withTagVerdicts(ctx, l.newMemberFilter(uc, pl), members)
	if err != nil {
		return 0, err
	}
	n := 0
	for _, it := range members {
		if l.memberVisible(ctx, f, it) {
			n++
		}
	}
	return n, nil
}
