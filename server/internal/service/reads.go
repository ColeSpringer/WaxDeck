package service

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"slices"
	"strconv"
	"strings"
	"time"

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
	b, scope, err := applyItemFilter(visibleItems().OrderBy("title", false), filter)
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
	b, scope, err := applyItemFilter(visibleItems(), filter)
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
	// Unconditionally, unlike before ADR-0048: the state predicate is
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
// scope hash this build no longer computes the same way. It is empty
// because nothing has changed yet, and it exists now because the moment
// it is needed is the moment it is too late: a stored queue carries its
// source cursor, and a change to what a scope hashes over turns every
// one of them into a scope mismatch at once. A mismatch is a 400, the
// pager treats a 400 as no cursor, and no cursor means a placement walk
// of up to forty pages per queue - all of them, on the first play after
// an upgrade.
//
// With the version byte, a token from a retired version is recognizable
// as stale rather than as wrong-scope, so it can be handed to the
// catalog to accept or refuse on its own terms instead of costing a
// walk. Retiring a version is one line here, in the change that alters
// the scope, and the next page a client asks for re-mints at the current
// version, so stored queues upgrade themselves.
const cursorVersion = "s1"

var oldCursorVersions = map[string]bool{}

// encodeScopedCursor wraps the catalog's keyset token in an envelope
// carrying the scope it was issued under, so a cursor reused under a
// changed list, seed, or filter is refused rather than answered wrong.
// ADR-0040 records why items takes it too. An empty token stays empty.
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
		if !l.allowedByContent(ctx, uc, it) {
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
// ADR-0048's state rule rides the query now, as `SearchOptions.States`,
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
	return d, nil
}

// artMimes maps the catalog's stored art formats to media types. An
// unknown format falls back to jpeg, the dominant case.
var artMimes = map[string]string{
	"jpeg": "image/jpeg",
	"jpg":  "image/jpeg",
	"png":  "image/png",
	"webp": "image/webp",
	"gif":  "image/gif",
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
	mime := artMimes[strings.TrimPrefix(blob.Format, "image/")]
	if mime == "" {
		mime = "image/jpeg"
	}
	return ArtBlob{Bytes: blob.Bytes, MimeType: mime, SourceHash: blob.SourceHash}, nil
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

// ArtRoleInfoDTO is one artwork slot an entity holds at its own level.
type ArtRoleInfoDTO struct {
	Role   string
	Format string
	Width  int
	Height int
}

// ItemArtRoles lists the artwork slots an entity holds at its own level
// (not inherited from the album/artist chain), the own-versus-inherited
// signal the front-cover read cannot give. Accepts item, album, and artist
// PIDs like Art.
func (l *Library) ItemArtRoles(ctx context.Context, uc *UserCtx, apiPID string) ([]ArtRoleInfoDTO, error) {
	ref, err := l.artRef(ctx, uc, apiPID)
	if err != nil {
		return nil, err
	}
	infos, err := l.lib.ArtRoles(ctx, ref)
	if err != nil {
		return nil, classify(err)
	}
	out := make([]ArtRoleInfoDTO, 0, len(infos))
	for _, i := range infos {
		out = append(out, ArtRoleInfoDTO{
			Role:   string(i.Role),
			Format: i.Format,
			Width:  i.Width,
			Height: i.Height,
		})
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
	out := Lyrics{PID: apiItemPID, Source: ly.Source, Unsynced: ly.Unsynced}
	for _, line := range ly.Synced {
		out.Synced = append(out.Synced, SyncedLine{TimeMS: line.TimeMS, Text: line.Text})
	}
	return out, nil
}
