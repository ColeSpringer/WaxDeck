package service

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"slices"
	"strconv"
	"strings"
	"time"

	waxart "github.com/colespringer/waxbin/art"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
	"github.com/colespringer/waxbin/read"
)

// ItemFilter narrows a library listing. Facet and FacetKey together
// drill one bucket of a browse dimension (the enumeration answers both
// values); FacetKey is legitimately empty for a dimension's unknown
// bucket, so the pair is applied whenever Facet is set.
type ItemFilter struct {
	MediaType string
	Facet     string
	FacetKey  string
}

// applyItemFilter narrows an item query by media type and facet bucket,
// and answers the canonical scope the pair names.
func applyItemFilter(b *query.Builder, filter ItemFilter) (*query.Builder, []string, error) {
	scope := []string{filter.MediaType}
	if filter.MediaType != "" {
		kind, ok := kindForMediaType(filter.MediaType)
		if !ok {
			return nil, nil, errInvalid("unknown mediaType " + filter.MediaType)
		}
		b = b.Where("kind", query.OpIs, string(kind))
	}
	if filter.Facet == "" {
		return b, append(scope, "", ""), nil
	}
	// Canonical, not what the caller typed: tag.mood and tag.MOOD are
	// one dimension and must name one scope.
	_, canonical, err := facetGroupFor(filter.Facet)
	if err != nil {
		return nil, nil, err
	}
	if b, err = applyFacetFilter(b, canonical, filter.FacetKey); err != nil {
		return nil, nil, err
	}
	return b, append(scope, canonical, filter.FacetKey), nil
}

// Items pages the whole library (optionally one media type, optionally
// one browse-dimension bucket) in stable (title, pid) order for the
// acting user. The cursor is WaxBin's token inside a scope envelope.
func (l *Library) Items(ctx context.Context, uc *UserCtx, filter ItemFilter, cursor string, limit int) (Page, error) {
	b, scope, err := applyItemFilter(
		visibleItems().WhereNode(l.contentRuleNode(ctx, uc)).OrderBy("title", false), filter)
	if err != nil {
		return Page{}, err
	}
	key := cursorScope(append([]string{"items"}, scope...)...)
	token, err := decodeScopedCursor(cursor, key)
	if err != nil {
		return Page{}, err
	}
	page, err := l.lib.QueryPage(ctx, b.Build(), read.Cursor(token), limit, false, model.PID(uc.CatalogPID))
	if err != nil {
		return Page{}, classify(err)
	}
	return l.pageDTO(ctx, uc, page, key), nil
}

// browseLists maps API discovery-list names onto WaxBin's. The names
// match one-to-one for the lists the API exposes.
var browseLists = map[string]read.DiscoveryList{
	"newest":          read.ListNewest,
	"recently-added":  read.ListRecentlyAdded,
	"most-played":     read.ListMostPlayed,
	"recently-played": read.ListRecentlyPlayed,
	"random":          read.ListRandom,
	"starred":         read.ListStarred,
	"alphabetical":    read.ListAlphabetical,
}

// rediscoverAfter is how long an item has to have gone unplayed to count
// as forgotten. Six months, so a shelf redrawn in the spring does not
// offer back what was on it in the winter.
const rediscoverAfter = 182 * 24 * time.Hour

// rediscoverRating is the rating that stands in for a star. The contract
// runs ratings 0..100, so this is four stars out of five.
const rediscoverRating = 80

// collectionLists are the two discovery lists WaxBin has no name for.
// They are selections rather than orderings, so they are expressed as
// queries over the same per-user play state every other play-derived
// list reads, and paged by the same keyset the item listing uses. Both
// come back A to Z, which is what QueryPage orders by; the contract
// says so, and says why neither has a more meaningful order.
var collectionLists = map[string]func() query.Node{
	// Owned and never opened. play_count coalesces to 0, so an item with
	// no play_state row at all matches, which is the whole population
	// this list is about.
	"never-played": func() query.Node {
		return query.Cond{Field: "play_count", Op: query.OpIs, Value: 0}
	},
	// Starred or rated well, and not heard in months. notInTheLast
	// matches NULL by contract, so something starred and never played
	// belongs here too - which is right: it is exactly what a listener
	// meant to get back to.
	"rediscover": func() query.Node {
		return query.And{Nodes: []query.Node{
			query.Or{Nodes: []query.Node{
				query.Cond{Field: "starred", Op: query.OpIs, Value: 1},
				query.Cond{Field: "rating", Op: query.OpGte, Value: rediscoverRating},
			}},
			query.Cond{
				Field: "last_played",
				Op:    query.OpNotInTheLast,
				Value: int64(rediscoverAfter),
			},
		}}
	},
}

// Browse pages one discovery list; play-derived lists reflect the acting
// user's own state. The filter narrows the list to one medium, one
// browse-dimension bucket, or both.
//
// Both halves are pushed into the catalog's query, so a narrowed page
// comes back full. It is the same filter the bucket's own listing uses,
// so a count, the list it opens, and a shuffle over it cannot disagree.
func (l *Library) Browse(ctx context.Context, uc *UserCtx, list string, filter ItemFilter, seed int64, cursor string, limit int) (Page, error) {
	b, scope, err := applyItemFilter(visibleItems().WhereNode(l.contentRuleNode(ctx, uc)), filter)
	if err != nil {
		return Page{}, err
	}
	// The seed is part of the scope: a cursor names a position in a
	// seeded permutation, and another seed is another permutation.
	key := cursorScope(append([]string{"browse", list, strconv.FormatInt(seed, 10)}, scope...)...)
	token, err := decodeScopedCursor(cursor, key)
	if err != nil {
		return Page{}, err
	}
	if where, ok := collectionLists[list]; ok {
		b = b.WhereNode(where())
		page, err := l.lib.QueryPage(ctx, b.Build(), read.Cursor(token), limit, false, model.PID(uc.CatalogPID))
		if err != nil {
			return Page{}, classify(err)
		}
		return l.pageDTO(ctx, uc, page, key), nil
	}
	dl, ok := browseLists[list]
	if !ok {
		return Page{}, errInvalid("unknown list " + list)
	}
	if err := browseScopeKindError(dl, list, filter, scope[1], scope[2]); err != nil {
		return Page{}, err
	}
	// Unconditionally: the state predicate is
	// always there now, so there is no longer an unfiltered case to
	// short-circuit. The catalog validates UserPID whenever it compiles a
	// query, so every list resolves the acting user where only a filtered
	// one used to. Nothing an ItemFilter can name is a per-user field, so
	// the join it guards is still never built; the lookup is validation.
	opts := read.BrowseOptions{
		UserPID: model.PID(uc.CatalogPID),
		Seed:    seed,
		Cursor:  read.Cursor(token),
		Limit:   limit,
		Query:   b.Build(),
	}
	page, err := l.lib.Browse(ctx, dl, opts)
	if err != nil {
		return Page{}, classify(err)
	}
	return l.pageDTO(ctx, uc, page, key), nil
}

// browseScopeKindError refuses a browse whose filter names a kind the
// list cannot hold.
//
// A few discovery lists are scoped to the kinds they can order by:
// `newest` orders by release year, which an episode has not got.
// Upstream answers an out-of-scope kind with an empty page, and an empty
// page is an honest-looking lie on a surface whose whole job is saying
// what the library holds. The guard reads the scope off the list rather
// than naming any list, so one scoped later inherits it.
func browseScopeKindError(dl read.DiscoveryList, list string, filter ItemFilter, canonicalFacet, facetKey string) error {
	kinds := dl.Kinds()
	if len(kinds) == 0 {
		return nil
	}
	refuse := func(named string) error {
		return errInvalid("the " + list + " list never contains " + named + " items")
	}
	if filter.MediaType != "" {
		// Already validated by applyItemFilter, so an unknown one cannot
		// reach here.
		if kind, ok := kindForMediaType(filter.MediaType); ok && !slices.Contains(kinds, kind) {
			return refuse(filter.MediaType)
		}
	}
	if canonicalFacet == "kind" && facetKey != "" && !slices.Contains(kinds, model.Kind(facetKey)) {
		return refuse(facetKey)
	}
	return nil
}

// cursorScope names the listing a cursor was issued for. Hashed rather
// than joined so the token leaks no bucket key.
func cursorScope(parts ...string) string {
	sum := sha256.Sum256([]byte(strings.Join(parts, "\x00")))
	return hex.EncodeToString(sum[:8])
}

// cursorVersion stamps every scoped cursor this build mints.
//
// oldCursorVersions lists the versions a previous build minted whose
// scope hash this build no longer computes the same way. It exists
// because the moment it is needed is the moment it is too late: a stored
// queue carries its source cursor, and a change to what a scope hashes
// over turns every one of them into a scope mismatch at once. A mismatch
// is a 400, the pager treats a 400 as no cursor, and no cursor means a
// placement walk of up to forty pages per queue - all of them, on the
// first play after an upgrade.
//
// With the version byte, a token from a retired version is recognizable
// as stale rather than as wrong-scope, so it can be handed to the
// catalog to accept or refuse on its own terms instead of costing a
// walk. Retiring a version is one line here, in the change that alters
// the scope, and the next page a client asks for re-mints at the current
// version, so stored queues upgrade themselves.
//
// s1 is retired and deliberately not listed. Moving Items onto
// visibleItems() and making Browse pass a Query unconditionally changed
// the result set behind an s1 cursor, while the scope covers only the
// list, the seed, and the ItemFilter - not the state predicate.
// A retired version's token is handed straight to the catalog, which
// would accept it and answer a coherent-looking wrong window; refusing
// s1 outright costs one placement walk per stored queue, once, and is
// the only answer that cannot lie.
const cursorVersion = "s2"

var oldCursorVersions = map[string]bool{}

// encodeScopedCursor wraps the catalog's keyset token in an envelope
// carrying the scope it was issued under, so a cursor reused under a
// changed list, seed, or filter is refused rather than answered wrong.
// An empty token stays empty.
func encodeScopedCursor(scope, token string) string {
	if token == "" {
		return ""
	}
	return encodeOpaqueCursor(cursorVersion + "|" + scope + "|" + token)
}

// decodeScopedCursor unwraps a scoped cursor, refusing one minted for a
// different scope. An empty cursor is the first page.
func decodeScopedCursor(cursor, scope string) (string, error) {
	if cursor == "" {
		return "", nil
	}
	raw, ok := decodeOpaqueCursor(cursor)
	if !ok {
		return "", errInvalid("malformed cursor")
	}
	// SplitN 3: the catalog's token may hold a separator of its own.
	parts := strings.SplitN(raw, "|", 3)
	if len(parts) != 3 {
		return "", errInvalid("malformed cursor")
	}
	if parts[0] != cursorVersion {
		if !oldCursorVersions[parts[0]] {
			return "", errInvalid("malformed cursor")
		}
		// A scope hash from a retired version means nothing to this
		// build, so there is no comparison to make: hand the token
		// through and let the catalog judge it. The worst case is what a
		// client already gets from a stale cursor today, and the ordinary
		// case is a page rather than a walk.
		return parts[2], nil
	}
	if parts[1] != scope {
		return "", errInvalid("cursor was issued for a different list, filter, or seed")
	}
	return parts[2], nil
}

// pageDTO converts a catalog page, dropping items outside the caller's
// visible libraries and podcast episodes of shows the caller does not
// subscribe to (subscriptions are per-user views; unsubscribing removes
// a show's episodes from your listings while the catalog keeps
// everything). Restricted callers may get short pages that still carry
// a cursor; the contract documents that.
//
// Tag rules are not applied here, deliberately: both callers conjoin
// contentRuleNode into the query, so a restricted caller's page comes
// back full rather than short, and pays no ItemTags read per row. What
// stays is the advisory check, which is per-item by nature. A third
// caller has to carry the node too, or it will list what the rules
// hide.
func (l *Library) pageDTO(ctx context.Context, uc *UserCtx, p *read.Page, scope string) Page {
	subs := l.newSubscriptionFilter(uc)
	out := Page{Items: make([]ItemSummary, 0, len(p.Items))}
	for _, it := range p.Items {
		if !uc.AllLibraries && !l.itemVisible(ctx, uc, it.PID) {
			continue
		}
		if !subs.allowsItem(ctx, l, it) {
			continue
		}
		if !advisoryAllows(uc, it) {
			continue
		}
		out.Items = append(out.Items, summary(it))
	}
	if p.HasMore {
		out.Next = encodeScopedCursor(scope, string(p.Next))
	}
	return out
}

// searchMaxCandidates bounds how many full-text matches are ranked
// before the per-group limit is applied. A common term on a large corpus
// can match most of it, and ranking every match is the hundreds-of-
// milliseconds worst case the cap exists to avoid; the newest matches win
// the pool and SearchResults.Truncated reports when it filled.
const searchMaxCandidates = 5000

// Search runs grouped full-text search. Restricted callers get item
// hits filtered by library visibility, and artist and album groups
// filtered by entity library attribution: an entity survives when one
// of the libraries holding its members is granted to the caller.
//
// The state rule rides the query now, as `SearchOptions.States`,
// so archived items never enter the ranking. That deleted the widening
// pass this used to carry: the archived filter was the only one that bit
// every caller, so on a single-administrator install - which is most of
// them - a group could not come back short before it, and a whole album
// deleted in one go matched its own name best and took the top of the
// ranking. `MaxCandidates` now bounds the pool to the newest N matches
// *in those states*, which is the pairing that makes one pass enough.
//
// The remaining filters bite only a restricted caller and run after the
// per-group cap, so a group can still come back short of `limit` for
// them. That was true before the widening pass existed and is what it
// deliberately never tried to fix.
func (l *Library) Search(ctx context.Context, uc *UserCtx, q string, limit int) (SearchResults, error) {
	// A restricted caller with no granted libraries can see nothing: every
	// item hit fails the visibility check below and entity groups are
	// omitted, so skip the FTS ranking entirely rather than rank a whole
	// corpus and then discard all of it.
	if !uc.AllLibraries && len(uc.Libraries) == 0 {
		return SearchResults{Query: q}, nil
	}
	opts := read.SearchOptions{
		Limit:         limit,
		MaxCandidates: searchMaxCandidates,
		States:        listableStates,
	}
	// A restricted caller's item hits are filtered by library visibility
	// below; scoping the FTS pool to the same libraries up front shrinks
	// the worst-case ranking set and drops fileless items, which fail
	// closed for these callers anyway. Full-visibility callers scan
	// unscoped. An empty grant leaves the scope open and the post-filter
	// drops everything, the same empty answer a scoped scan would give.
	if !uc.AllLibraries && len(uc.Libraries) > 0 {
		opts.Libraries = make([]model.PID, 0, len(uc.Libraries))
		for lib := range uc.Libraries {
			opts.Libraries = append(opts.Libraries, model.PID(lib))
		}
	}
	res, err := l.lib.Search(ctx, q, opts)
	if err != nil {
		return SearchResults{}, classify(err)
	}
	// truncate cuts a filtered group to the contract's cap. The catalog
	// already capped at the same number, so this only ever bites when a
	// filter below returned everything it was given.
	truncate := func(hits []SearchHit) []SearchHit {
		if len(hits) > limit {
			return hits[:limit]
		}
		return hits
	}
	convEntity := func(hits []read.SearchHit, prefix string, kind read.EntityKind, group read.GroupBy, field string) ([]SearchHit, error) {
		// Entities carry no stored library column, so a restricted caller's
		// hits are attributed through the libraries holding their member
		// items, in one batched lookup per kind. Full-visibility callers
		// see every entity and skip it entirely.
		var infos map[model.PID]*read.EntityInfo
		if !uc.AllLibraries && len(hits) > 0 {
			pids := make([]model.PID, 0, len(hits))
			for _, h := range hits {
				pids = append(pids, h.PID)
			}
			var err error
			if infos, err = l.lib.EntityByPIDs(ctx, kind, pids); err != nil {
				// The batch is the gate, so a failure can neither hand the
				// caller entities it may not see nor pass as an honest
				// empty group: it fails the search.
				return nil, classify(err)
			}
		}
		live, err := l.entitiesWithLiveMembers(ctx, hits, group, field)
		if err != nil {
			return nil, err
		}
		out := make([]SearchHit, 0, len(hits))
		for _, h := range hits {
			if !live[h.PID] {
				continue
			}
			if !uc.AllLibraries && !l.entityInLibraries(infos[h.PID], uc) {
				continue
			}
			out = append(out, SearchHit{
				PID:      apiPID(prefix, h.PID),
				Kind:     h.Kind,
				Title:    h.Title,
				Subtitle: h.Subtitle,
			})
		}
		return truncate(out), nil
	}
	subs := l.newSubscriptionFilter(uc)
	convItem := func(hits []read.SearchHit, prefix string) []SearchHit {
		out := make([]SearchHit, 0, len(hits))
		for _, h := range hits {
			// Every filter here runs after the catalog's per-group cap, and
			// every one of them bites only a restricted caller: the state
			// rule that applied to everybody rides the query now.
			if !uc.AllLibraries && !l.itemVisible(ctx, uc, h.PID) {
				continue
			}
			// Episode hits (title and transcript matches alike) scope to
			// the caller's subscriptions, like every list surface.
			if prefix == PrefixEpisode && !subs.allowsEpisodePID(ctx, l, h.PID) {
				continue
			}
			if !l.contentAllowsPID(ctx, uc, h.PID) {
				continue
			}
			out = append(out, SearchHit{
				PID:      apiPID(prefix, h.PID),
				Kind:     h.Kind,
				Title:    h.Title,
				Subtitle: h.Subtitle,
			})
		}
		return truncate(out)
	}
	artists, err := convEntity(res.Artists, PrefixArtist, read.EntityArtist, read.GroupArtist, "artist_pid")
	if err != nil {
		return SearchResults{}, err
	}
	albums, err := convEntity(res.Albums, PrefixAlbum, read.EntityAlbum, read.GroupAlbum, "album_pid")
	if err != nil {
		return SearchResults{}, err
	}
	return SearchResults{
		Query:     res.Query,
		Artists:   artists,
		Albums:    albums,
		Tracks:    convItem(res.Tracks, PrefixTrack),
		Books:     convItem(res.Books, PrefixBook),
		Episodes:  convItem(res.Episodes, PrefixEpisode),
		Truncated: res.Truncated,
	}, nil
}

// entitiesWithLiveMembers reports which of a search's entity hits still
// hold at least one item a listing would offer: an artist whose every
// track is in the trash must not stay a search hit and open onto an
// empty facet drill, while the browse index has already dropped them
// because facetScopeQuery aggregates over items.
//
// One facet over the hit pids answers the whole group: the same
// dimension the drill pairs with, so search and browse cannot disagree
// about what "this artist has something" means.
//
// This is belt now rather than the only guard. The catalog derives the
// artist and album groups from matched *item* rows, so
// SearchOptions.States carries into them: an entity whose every member
// is archived contributes no matched row and is never a hit in the first
// place. Kept because the two ask subtly different questions - States
// asks whether a listable member *matched the query*, this asks whether
// the entity has a listable member at all - and because it is the half
// that keeps search agreeing with the drill it opens. If it ever shows
// up in a search profile, measure before deleting: it costs one facet
// per entity group per keystroke.
func (l *Library) entitiesWithLiveMembers(ctx context.Context, hits []read.SearchHit, group read.GroupBy, field string) (map[model.PID]bool, error) {
	if len(hits) == 0 {
		return nil, nil
	}
	pids := make([]string, 0, len(hits))
	for _, h := range hits {
		pids = append(pids, string(h.PID))
	}
	q := visibleItems().WhereValues(field, query.OpIn, query.Values(pids)...).Build()
	res, err := l.lib.Facet(ctx, q, group, read.FacetOrderLabel, 0, model.PID(""))
	if err != nil {
		return nil, classify(err)
	}
	out := make(map[model.PID]bool, len(res.Buckets))
	for _, b := range res.Buckets {
		if b.EntityPID != "" && b.Count > 0 {
			out[b.EntityPID] = true
		}
	}
	return out, nil
}

// EntityNames resolves the catalog's display name for a batch of API
// entity pids, keyed by the pid passed in. Every pid must share one
// prefix (the catalog batches within a kind); unknown or unparseable
// pids are omitted rather than erroring, so a caller hydrating labels
// falls back to whatever it already had.
//
// This is the compatibility surface's naming primitive: once a group is
// keyed on an entity rather than on a display string, the label has to
// come from the entity too.
func (l *Library) EntityNames(ctx context.Context, apiPIDs []string) (map[string]string, error) {
	if len(apiPIDs) == 0 {
		return nil, nil
	}
	prefix, _, ok := parseAPIPID(apiPIDs[0])
	if !ok {
		return nil, errInvalid("malformed entity pid " + apiPIDs[0])
	}
	kind, ok := entityKindForPrefix(prefix)
	if !ok {
		return nil, errInvalid("no entity kind for pid " + apiPIDs[0])
	}
	pids := make([]model.PID, 0, len(apiPIDs))
	back := make(map[model.PID]string, len(apiPIDs))
	for _, api := range apiPIDs {
		p, pid, ok := parseAPIPID(api)
		if !ok || p != prefix {
			continue
		}
		pids = append(pids, pid)
		back[pid] = api
	}
	infos, err := l.lib.EntityByPIDs(ctx, kind, pids)
	if err != nil {
		return nil, classify(err)
	}
	out := make(map[string]string, len(infos))
	for pid, info := range infos {
		if info != nil && info.Name != "" {
			out[back[pid]] = info.Name
		}
	}
	return out, nil
}

// entityInLibraries reports whether any library holding the entity's
// members is in the caller's grant. Full-visibility callers never reach
// this (they see every entity). A nil info (which the facade never
// returns alongside a nil error, but the helper stays robust to)
// attributes to no library and reads as not visible.
func (l *Library) entityInLibraries(info *read.EntityInfo, uc *UserCtx) bool {
	if info == nil {
		return false
	}
	for _, lib := range info.LibraryPIDs {
		if uc.Libraries[string(lib)] {
			return true
		}
	}
	return false
}

// Item returns full detail for one item.
// ItemDuration answers how long one visible item is, and nothing else.
//
// It exists so a caller that wants only this does not pay for a detail
// read, and the listen submission path calls it once per id: a client
// flushing fifty offline plays would otherwise run fifty detail reads to
// use one number from each. Same visibility rules and same not-found error
// as Item, so a caller can swap one for the other without changing what it
// reports.
func (l *Library) ItemDuration(ctx context.Context, uc *UserCtx, apiItemPID string) (int64, error) {
	it, err := l.getVisibleItem(ctx, uc, apiItemPID)
	if err != nil {
		return 0, err
	}
	return it.DurationMS, nil
}

func (l *Library) Item(ctx context.Context, uc *UserCtx, apiItemPID string) (ItemDetail, error) {
	it, err := l.getVisibleItem(ctx, uc, apiItemPID)
	if err != nil {
		return ItemDetail{}, err
	}
	d := ItemDetail{
		ItemSummary: summary(it),
		Year:        it.Year,
		Codec:       it.Codec,
		Container:   it.Container,
		SampleRate:  it.SampleRate,
	}
	if it.Genre != "" {
		d.Genres = []string{it.Genre}
	}
	// Bitrate lives on the file row; a miss is fine (remote/missing items).
	if f, err := l.lib.File(ctx, it.FilePID); err == nil {
		d.Bitrate = f.Bitrate
		d.AddedAt = time.Unix(0, f.FirstSeen).UTC()
	}
	entity := model.ArtTrack
	if it.Kind == model.KindEpisode {
		entity = model.ArtEpisode
	}
	d.ArtSource = l.artSourceForRef(ctx, model.EntityRef{Type: entity, PID: it.PID})
	return d, nil
}

// Album returns one album entity's identity: the release facts the
// catalog keeps on the entity rather than on any of its tracks.
//
// A screen deriving an album from its tracks (AlbumFacts, client side)
// can reach the title, the artist, and the year, because every track
// carries them. It cannot reach the barcode, the label, the catalog
// number, the media, or the country, because those describe the edition
// and upstream keeps them off the item row on purpose. This is the read
// half of the editEntity write surface.
func (l *Library) Album(ctx context.Context, uc *UserCtx, apiAlbumPID string) (AlbumDetail, error) {
	prefix, pid, ok := parseAPIPID(apiAlbumPID)
	if !ok || prefix != PrefixAlbum {
		// A track pid presented as an album is a not-found rather than a
		// wrong-shaped answer, the rule getItem applies to its own prefixes.
		return AlbumDetail{}, errNotFound("no album with pid " + apiAlbumPID)
	}
	info, err := l.lib.EntityByPID(ctx, read.EntityAlbum, pid)
	if err != nil {
		return AlbumDetail{}, classify(err)
	}
	if info == nil {
		return AlbumDetail{}, errNotFound("no album with pid " + apiAlbumPID)
	}
	if !uc.AllLibraries && !l.entityInLibraries(info, uc) {
		return AlbumDetail{}, errNotFound("no album with pid " + apiAlbumPID)
	}
	out := AlbumDetail{
		PID:             apiPID(PrefixAlbum, info.PID),
		Title:           info.Name,
		SortKey:         info.SortKey,
		MBID:            info.MBID,
		Year:            info.Year,
		ReleaseGroupPID: entityAPIPID(PrefixReleaseGroup, info.ReleaseGroupPID),
		Barcode:         info.Barcode,
		Label:           info.Label,
		CatalogNumber:   info.CatalogNumber,
		Media:           info.Media,
		Country:         info.Country,
	}
	// The catalog's counts are catalog-wide: EntityByPID takes no library
	// scope, so they describe the release rather than the caller's reach.
	// Handing them to a restricted caller would advertise nine tracks on
	// a screen that can open three, so they are answered only where they
	// are true. Left absent rather than recomputed: nothing draws them
	// today (a header counts the rows it listed), and a per-album scoped
	// count is a read spent on a number nobody reads.
	if uc.AllLibraries {
		out.ItemCount, out.TotalDurationMS = info.ItemCount, info.TotalDurationMS
	}
	out.ArtSource = l.artSourceForRef(ctx, model.EntityRef{Type: model.ArtAlbum, PID: info.PID})
	return out, nil
}

// The hardening pair every response carrying a picture from this origin
// sets, wherever it is served from.
//
// These bytes came from a host somebody named - a provider, a feed, a
// station, a file somebody uploaded - and they go out under a URL a
// browser can simply open. artMime already refuses to declare a type a
// browser executes; these two make that hold even if it stops holding.
// `nosniff` stops a browser deciding the body is really markup, and the
// policy neutralizes script and navigation for a document opened
// straight from the URL. Cheap, and exactly the layer that turns a
// future mistake in the type derivation from a stored-XSS hole into a
// broken image.
const (
	ArtNoSniff = "nosniff"
	ArtCSP     = "default-src 'none'; sandbox; style-src 'unsafe-inline'"
)

// artScriptable are the stored formats a browser opens as a document
// rather than paints. SVG is markup, and markup served from this origin
// is script running as the reader; a cover can reach the catalog under
// one, because a provider naming `image/svg+xml` is enough, so the byte
// endpoints answer with a type a browser downloads instead. Nothing
// WaxDeck draws with renders SVG, so no picture is lost.
var artScriptable = map[string]bool{"svg": true, "svg+xml": true}

// artMime names what the resolver actually handed back. Every format the
// catalog can hold spells its media type as `image/` plus the stored
// token - png, webp, gif, bmp and tiff, and every exotic it holds without
// decoding - so the derivation covers more than a table could be kept in
// step with: the resolver serves an unthumbnailable source unscaled,
// which after bmp and tiff became first-class means avif and heic, and
// claiming jpeg for those is a mislabel a client draws a broken image
// for.
//
// The token is normalized before it reaches a header. It is stored data,
// and a stored format ultimately came from a fetched picture's media type
// or a file's own tag; NormalizeFormat is idempotent on anything it
// produced, reads a whole media type as well as a bare token, and turns
// anything it cannot read into the empty answer below.
//
// No format at all is bytes nothing could name. The store refuses to
// hold one, so this is the unreachable case rather than the common one,
// and octet-stream is what it would mean - every client that draws
// artwork decodes from the bytes, so naming them honestly costs nothing.
func artMime(format string) string {
	f := waxart.NormalizeFormat(format)
	if f == "" || artScriptable[f] {
		return "application/octet-stream"
	}
	return "image/" + f
}

// Art resolves artwork: original when size is 0, square-fit thumbnail
// otherwise. Besides item PIDs it accepts album and artist PIDs, so
// search hits render artwork without a second identifier scheme.
// Item artwork honors library visibility; album and artist artwork is
// served without an attribution check (entities span libraries and
// PIDs are unguessable ULIDs; restricted users never discover them
// through listings, which are filtered).
func (l *Library) Art(ctx context.Context, uc *UserCtx, apiPID, role string, size int) (ArtBlob, error) {
	art, ok := model.ParseArtRole(role)
	if !ok {
		return ArtBlob{}, errInvalid("unknown art role " + role)
	}
	ref, err := l.artRef(ctx, uc, apiPID)
	if err != nil {
		return ArtBlob{}, err
	}
	blob, err := l.lib.ResolveArt(ctx, ref, art, size)
	if err != nil {
		return ArtBlob{}, classify(err)
	}
	return ArtBlob{
		Bytes:      blob.Bytes,
		MimeType:   artMime(blob.Format),
		SourceHash: blob.SourceHash,
		Source:     l.artSourceFor(ctx, ref, artSourceFromBlob(blob)),
		Width:      blob.Width,
		Height:     blob.Height,
		Box:        blob.Box,
	}, nil
}

// The two art-source values a producer outside the catalog reports,
// taken from the catalog's own vocabulary so the two cannot drift.
// Radio is that producer: a picture the station announced in its own
// stream is its feed, and one a lookup supplied is enrichment.
const (
	artSourceFeed       = string(model.SourceFeed)
	artSourceEnrichment = string(model.SourceEnrichment)
)

// artSourceMark reads the provenance an art resolve carried. The picture
// came from one level of the fallback chain and that level's attachment is
// what a caller marks, so a derived album cover honestly reports the member
// track's answer rather than claiming the album made the choice.
//
// The two reads that answer this question - the byte resolve and the
// metadata-only one - carry the same values under different types, so each
// gets a one-line constructor over this shared body rather than a call site
// spelling the field list out.
func artSourceFromBlob(blob *model.ArtBlob) ArtSourceDTO {
	return artSourceMark(blob.Attribution, blob.Level, blob.Derived, blob.UpdatedAt)
}

func artSourceFromProvenance(prov *model.ArtProvenance) ArtSourceDTO {
	return artSourceMark(prov.Attribution, prov.Level, prov.Derived, prov.UpdatedAt)
}

func artSourceMark(attr model.Attribution, level model.ArtEntity, derived bool, updatedAt int64) ArtSourceDTO {
	out := ArtSourceDTO{
		Source:    string(attr.Source),
		Provider:  attr.Provider,
		SourceURL: attr.SourceURL,
		Level:     string(level),
		Derived:   derived,
	}
	if updatedAt != 0 {
		out.UpdatedAt = time.Unix(0, updatedAt).UTC()
	}
	return out
}

// artSourceForRef answers where an entity's front cover came from, for
// the detail reads that draw one. It resolves rather than reading the
// entity's own slots: an album normally owns no art row and shows a
// member track's cover, so the own-level read would leave almost every
// album header unmarked.
//
// The zero value is the honest answer for an entity with no cover at
// all, and for any failure below - a caption is not worth failing a
// detail read over.
//
// It walks the same chain a front-cover read walks and answers off the row
// alone, so a detail screen that draws a caption does not pay for the
// picture it is not going to show.
func (l *Library) artSourceForRef(ctx context.Context, ref model.EntityRef) ArtSourceDTO {
	prov, err := l.lib.ArtProvenance(ctx, ref, model.ArtRoleFront)
	if err != nil || prov == nil {
		return ArtSourceDTO{}
	}
	return l.artSourceFor(ctx, ref, artSourceFromProvenance(prov))
}

// artSourceFor is the provenance a caller may be shown for one resolved
// cover: what the blob carried, minus a source URL that is somebody's
// credential.
//
// A feed cover's URL is minted from the feed document and lives on the
// feed's host, so for a credentialed show it carries the same token the
// feed URL does - the value showDTO withholds, opml skips, shares
// refuse, and classifyFeedErr keeps out of error text. Every other
// source's URL is a public provider address and is reported as fetched.
//
// It lives here, between the resolve and every DTO, rather than at the
// call sites: the leak this closes was four call sites wide, and a
// fifth would not know the rule either.
func (l *Library) artSourceFor(ctx context.Context, ref model.EntityRef, out ArtSourceDTO) ArtSourceDTO {
	return l.artSourceRedactor(ctx, ref)(out)
}

// artSourceRedactor is artSourceFor bound to one entity, with the show
// lookup taken at most once. The roles read applies the rule to every
// row it returns and an episode holds up to five, so the per-call form
// would pay for the same answer five times.
//
// A URL that survives the show rule still goes out reduced to scheme,
// host and path, for the reason redactedSourceURL gives: these reads
// answer everyone who can see the item, and what the catalog stored is
// verbatim.
func (l *Library) artSourceRedactor(ctx context.Context, ref model.EntityRef) func(ArtSourceDTO) ArtSourceDTO {
	var public, checked bool
	return func(out ArtSourceDTO) ArtSourceDTO {
		if out.SourceURL == "" {
			return out
		}
		if out.Source == artSourceFeed {
			if !checked {
				public, checked = l.feedArtIsPublic(ctx, ref), true
			}
			if !public {
				out.SourceURL = ""
				return out
			}
		}
		out.SourceURL = redactedSourceURL(out.SourceURL)
		return out
	}
}

// feedArtIsPublic reports whether the show a feed-sourced cover came
// from is one whose addresses may be handed out. It fails closed: a ref
// whose show cannot be established withholds the URL, because a chain
// that grew a rung this rule has not been taught must not leak while it
// waits to be taught.
func (l *Library) feedArtIsPublic(ctx context.Context, ref model.EntityRef) bool {
	show := ref.PID
	switch ref.Type {
	case model.ArtPodcast:
	case model.ArtEpisode:
		it, err := l.lib.Get(ctx, ref.PID)
		if err != nil || it == nil || it.PodcastPID == "" {
			return false
		}
		show = it.PodcastPID
	default:
		return false
	}
	pod, err := l.lib.Podcasts().Get(ctx, show)
	if err != nil || pod == nil {
		return false
	}
	return !l.showIsPrivate(ctx, pod)
}

// artRef resolves an art read/roles pid to its entity ref. Item PIDs honor
// library visibility; album, artist, and podcast-show PIDs resolve without an
// attribution check (entities span libraries, their PIDs are unguessable
// ULIDs, and restricted users never surface them through filtered listings).
func (l *Library) artRef(ctx context.Context, uc *UserCtx, apiPID string) (model.EntityRef, error) {
	prefix, pid, ok := parseAPIPID(apiPID)
	if !ok {
		return model.EntityRef{}, errNotFound("no artwork for pid " + apiPID)
	}
	switch {
	case prefix == PrefixAlbum:
		return model.EntityRef{Type: model.ArtAlbum, PID: pid}, nil
	case prefix == PrefixArtist:
		return model.EntityRef{Type: model.ArtArtist, PID: pid}, nil
	case prefix == PrefixPodcast:
		// A podcast show is not a catalog item, so it resolves to its own art
		// level directly (its feed image), like album and artist entities.
		return model.EntityRef{Type: model.ArtPodcast, PID: pid}, nil
	case prefix == PrefixPlaylist:
		// Unlike the entity cases above, a playlist goes through its
		// visibility check. Those skip attribution because entity pids are
		// unguessable and never surface through a filtered listing; a
		// playlist has explicit user-facing visibility, and resolvePlaylist
		// is the same owner-or-shared gate every other playlist read uses.
		pl, err := l.resolvePlaylist(ctx, uc, apiPID)
		if err != nil {
			return model.EntityRef{}, err
		}
		return model.EntityRef{Type: model.ArtPlaylist, PID: pl.PID}, nil
	case itemPrefix(prefix):
		it, err := l.getVisibleItem(ctx, uc, apiPID)
		if err != nil {
			return model.EntityRef{}, err
		}
		entity := model.ArtTrack
		if it.Kind == model.KindEpisode {
			entity = model.ArtEpisode
		}
		return model.EntityRef{Type: entity, PID: it.PID}, nil
	default:
		return model.EntityRef{}, errNotFound("no artwork for pid " + apiPID)
	}
}

// ArtRoleInfoDTO is one artwork slot an entity holds at its own level,
// with where its image came from and whether it is pinned. An entry with
// Locked set and no Format is a pin with nothing behind it - a cleared
// and pinned cover, which is the state that used to be invisible.
type ArtRoleInfoDTO struct {
	Role      string
	Format    string
	Width     int
	Height    int
	Source    string
	Provider  string
	SourceURL string
	UpdatedAt time.Time
	Locked    bool
}

// ArtRolesDTO is an entity's own artwork slots plus the provenance of
// the cover a front-cover read would answer with, which is the inherited
// one when the entity holds none of its own.
type ArtRolesDTO struct {
	Roles     []ArtRoleInfoDTO
	ArtSource ArtSourceDTO
}

// ItemArtRoles lists the artwork slots an entity holds at its own level
// (not inherited from the album/artist chain), the own-versus-inherited
// signal the front-cover read cannot give. Accepts item, album, and artist
// PIDs like Art.
func (l *Library) ItemArtRoles(ctx context.Context, uc *UserCtx, apiPID string) (ArtRolesDTO, error) {
	ref, err := l.artRef(ctx, uc, apiPID)
	if err != nil {
		return ArtRolesDTO{}, err
	}
	infos, err := l.lib.ArtRoles(ctx, ref)
	if err != nil {
		return ArtRolesDTO{}, classify(err)
	}
	out := ArtRolesDTO{
		Roles:     make([]ArtRoleInfoDTO, 0, len(infos)),
		ArtSource: l.artSourceForRef(ctx, ref),
	}
	// Every row through the same rule the envelope's mark goes through.
	// These are the call sites artSourceFor's comment warned would not
	// know it: they read the slot's own attribution rather than a
	// resolve's, so a private show's cover handed out its credentialed
	// URL here while the mark beside it withheld the same value.
	redact := l.artSourceRedactor(ctx, ref)
	for _, i := range infos {
		mark := redact(ArtSourceDTO{
			Source: string(i.Source), Provider: i.Provider, SourceURL: i.SourceURL,
		})
		role := ArtRoleInfoDTO{
			Role:      string(i.Role),
			Format:    i.Format,
			Width:     i.Width,
			Height:    i.Height,
			Source:    string(i.Source),
			Provider:  i.Provider,
			SourceURL: mark.SourceURL,
			Locked:    i.Locked,
		}
		if i.UpdatedAt != 0 {
			role.UpdatedAt = time.Unix(0, i.UpdatedAt).UTC()
		}
		out.Roles = append(out.Roles, role)
	}
	return out, nil
}

// ItemLyrics returns the item's lyrics; not-found when it has none.
func (l *Library) ItemLyrics(ctx context.Context, uc *UserCtx, apiItemPID string) (Lyrics, error) {
	it, err := l.getVisibleItem(ctx, uc, apiItemPID)
	if err != nil {
		return Lyrics{}, err
	}
	ly, err := l.lib.Lyrics(ctx, it.PID)
	if err != nil {
		return Lyrics{}, classify(err)
	}
	out := Lyrics{PID: apiItemPID, Source: string(ly.Source), Provider: ly.Provider, Unsynced: ly.Unsynced}
	for _, line := range ly.Synced {
		out.Synced = append(out.Synced, SyncedLine{TimeMS: line.TimeMS, Text: line.Text})
	}
	return out, nil
}
