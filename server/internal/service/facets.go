package service

// First-party faceted browse: enumerating a browse dimension's buckets
// with counts, and the matching filter that drills one bucket into an
// item list.
//
// The catalog answers the aggregation; WaxDeck owns the paging, the
// visibility scope, and the labels. Three things are worth knowing
// before changing this file.
//
// Paging is in memory, permanently: upstream declined facet paging, so
// a page is a window over a sorted slice and the cache below keeps that
// affordable. EntityPage is not a substitute; ADR-0040 says why, since
// the next agent looking at a large artist index will find it first.
//
// Caching is narrow on purpose. Only the unfiltered enumeration, only
// per dimension and order, only for full-visibility callers, keyed on
// the catalog feed position - the same restriction TrackFacts applies,
// for the same reason: Facet takes a user pid and a query, so a
// restricted caller's answer is not a function of the tail alone. A
// restricted caller's enumeration is computed live every time.
//
// Bucket counts are library-scoped, not fully visibility-scoped. The
// enumeration narrows to the caller's granted libraries, which is the
// axis that actually hides content; the per-item podcast-subscription
// and content-rule filters the drill list applies are per-item decisions
// no aggregation can express. The drill list stays exact, so a bucket
// can read higher than the list it opens, the same way every restricted
// listing in this service can return a short page.

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"sort"
	"strconv"
	"strings"
	"sync"
	"unicode"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
	"github.com/colespringer/waxbin/read"

	"github.com/colespringer/waxdeck/server/internal/genre"
)

// Browse dimension names as the API spells them, mapped onto the
// catalog's faceting groups. A custom-tag dimension ("tag.<KEY>") is not
// enumerated here: tag keys are open-ended, so it is validated by the
// catalog's own tag-key rules instead.
//
// credit-artist is the second many-per-item dimension after genre: a
// track lands in a bucket for every artist its credit names, so the
// bucket counts sum to more than the item count. That is what makes it
// the dimension an artist's "Appears on" reads, where `artist` buckets
// the same track once under its primary and never mentions the feature.
var browseDimensions = map[string]read.GroupBy{
	"genre":         read.GroupGenre,
	"artist":        read.GroupArtist,
	"credit-artist": read.GroupCreditArtist,
	"album-artist":  read.GroupAlbumArtist,
	"album":         read.GroupAlbum,
	"release-group": read.GroupReleaseGroup,
	"year":          read.GroupYear,
	"kind":          read.GroupKind,
}

// facetFilterField is the query field a dimension's bucket key filters
// on. Every one of them is the same expression the facet groups by, so a
// bucket's count and the list it opens can never disagree about what
// belongs in it.
var facetFilterField = map[string]string{
	"genre":         "genre_pid",
	"artist":        "artist_pid",
	"credit-artist": "credit_artist_pid",
	"album-artist":  "album_artist_pid",
	"album":         "album_pid",
	"release-group": "release_group_pid",
	"year":          "year",
	"kind":          "kind",
}

// facetTagPrefix marks a custom-tag browse dimension.
const facetTagPrefix = "tag."

// facetDimensionGenre is the one dimension whose labels come from
// WaxDeck's own genre vocabulary rather than from the catalog alone, so
// it is the one an edit to that vocabulary has to evict.
const facetDimensionGenre = "genre"

// facetDefaultLimit matches the spec's default page size.
const facetDefaultLimit = 100

// FacetSort is the order a dimension's buckets come back in.
type FacetSort string

const (
	// FacetSortCount leads with the biggest buckets: what a hub wants.
	FacetSortCount FacetSort = "count"
	// FacetSortLabel is A to Z by display label: what an index with an
	// alphabet rail scrolls through.
	FacetSortLabel FacetSort = "label"
)

// validFacetSorts is the closed set a stored sort may hold, unlike
// ParseFacetSort's input, where "" is the absent query parameter.
var validFacetSorts = map[FacetSort]bool{FacetSortCount: true, FacetSortLabel: true}

// ParseFacetSort validates a sort name, treating the empty string as the
// default rather than as an error: the parameter is optional. Exported
// so the handler parses at the edge and Facets takes the type, which is
// what keeps a dimension, a sort, and a cursor from being three adjacent
// strings a call site can transpose in silence.
func ParseFacetSort(s string) (FacetSort, error) {
	switch FacetSort(s) {
	case "", FacetSortCount:
		return FacetSortCount, nil
	case FacetSortLabel:
		return FacetSortLabel, nil
	default:
		return "", errInvalid("unknown facet sort " + s)
	}
}

// facetNoEpisodes names the dimensions the catalog computes with podcast
// episodes excluded (they carry no artist, album, genre, or year in the
// music sense, so including them would pile every episode into one
// unknown bucket). The drill filter mirrors it so the item set matches
// the bucket count.
var facetNoEpisodes = map[string]bool{
	"genre": true, "artist": true, "credit-artist": true, "album-artist": true,
	"album": true, "release-group": true, "year": true,
}

// facetHasUnknownBucket names the dimensions that enumerate a bucket for
// the items they are absent from ("[No Genre]", "[Non-Album]"), which is
// what an empty bucket key drills. `kind` has none because an item's
// kind is never absent, and a custom tag has none because only items
// carrying the key contribute to it at all. The membership happens to
// match facetNoEpisodes today; they answer different questions, so they
// stay separate lists.
var facetHasUnknownBucket = map[string]bool{
	"genre": true, "artist": true, "credit-artist": true, "album-artist": true,
	"album": true, "release-group": true, "year": true,
}

// FacetBucket is one bucket of a browse dimension.
type FacetBucket struct {
	// Key is the stable machine handle to drill on: an entity pid for the
	// entity dimensions, a year, a kind, or a tag value. It is empty for
	// the unknown bucket, which is a real bucket ("[Non-Album]") holding
	// the items the dimension is absent from.
	Key   string
	Label string
	Count int
	// EntityPID is the API-form pid of the catalog entity behind the
	// bucket, when there is one. The unknown bucket carries none, and
	// neither do the year, kind, and tag dimensions.
	EntityPID string
	Unknown   bool
	// fold is Label case-folded, held rather than recomputed because the
	// A-to-Z sort compares it across every pair of a dimension's buckets.
	fold string
}

// facetFolded returns a bucket with its case-folded sort key filled in.
//
// Folding is what makes the A-to-Z order read as an alphabet rather than
// as ASCII: without it "Zebra" sorts ahead of "abba", and an index whose
// rail says Z would be showing the a's. It is a fold and not a collation
// scripts outside ASCII still land after z, the same way the catalog's
// own tie-break does - and a proper locale collation is a bigger change
// than an index screen justifies.
//
// Left-trimmed because fastScrollLetter takes the rail letter after a
// trim: untrimmed, " Weeknd" sorts before every A while the rail files
// it under W. One fold decides the sort, the seek, and the letter.
func facetFolded(b FacetBucket) FacetBucket {
	b.fold = strings.ToLower(strings.TrimLeftFunc(b.Label, unicode.IsSpace))
	return b
}

// FacetPage is one keyset-paginated page of a dimension's buckets.
type FacetPage struct {
	Dimension string
	Buckets   []FacetBucket
	Next      string
}

// facetCache holds the full-visibility enumerations, keyed by dimension
// and order within one generation of the inputs they were computed from.
//
// The generation is the pair (catalog feed position, genre vocabulary
// version), because a bucket list is a function of both: the catalog
// supplies the buckets and counts, and WaxDeck's vocabulary supplies the
// genre labels. Keying on the feed position alone would leave a
// vocabulary edit invisible to the cache, since such an edit writes no
// catalog state and so never moves the feed.
type facetCache struct {
	mu          sync.Mutex
	gen         facetGeneration
	byDimension map[facetCacheKey][]FacetBucket
}

// facetCacheKey names one cached enumeration. The order is part of the
// key rather than applied on read: paging walks a sorted slice, so the
// slice has to already be in the order the cursor was issued for.
type facetCacheKey struct {
	dimension string
	sort      FacetSort
}

// facetGeneration identifies the inputs an enumeration was computed
// from. Both components only ever increase.
type facetGeneration struct {
	tail  int64
	vocab int64
}

// FacetQuery is one request for a dimension's buckets. A struct because
// Cursor and StartsAt are two strings naming two different positions,
// and a transposed pair would fail silently.
type FacetQuery struct {
	Dimension string
	Order     FacetSort
	Cursor    string
	// StartsAt seeks the first bucket at or after a display-label
	// prefix, which is what an alphabet rail taps. Requires
	// FacetSortLabel and refuses a Cursor.
	StartsAt string
	// Facet and FacetKey scope the enumeration to one bucket of a second
	// dimension: album buckets counted over one artist's credits. Absent
	// Facet is the whole-library enumeration.
	Facet    string
	FacetKey string
	Limit    int
}

// facetScope is the canonical form of the scope pair, carried separately
// from FacetQuery because everything below the validator works in
// canonical dimension names.
//
// The zero value is "no scope", which is what every caller before this
// asked for and what keeps the cache path unchanged for them.
type facetScope struct {
	Facet string
	Key   string
}

// scoped reports whether an enumeration is narrowed to a bucket, which is
// what decides both cache participation and cursor compatibility.
func (s facetScope) scoped() bool { return s.Facet != "" }

// Facets enumerates one browse dimension's buckets, paged: most items
// first by default, A to Z under FacetSortLabel.
func (l *Library) Facets(ctx context.Context, uc *UserCtx, q FacetQuery) (FacetPage, error) {
	group, canonical, err := facetGroupFor(q.Dimension)
	if err != nil {
		return FacetPage{}, err
	}
	// Validated here as well as at the edge: the type narrows what a call
	// site can transpose, not what it can invent, and an order nothing
	// serves must not fall through to the default - answering
	// biggest-first to a caller who asked for A to Z puts the wrong
	// letters under the rail.
	order, err := ParseFacetSort(string(q.Order))
	if err != nil {
		return FacetPage{}, err
	}
	scope, err := facetScopeFor(q.Facet, q.FacetKey, canonical)
	if err != nil {
		return FacetPage{}, err
	}
	after, err := decodeFacetCursor(q.Cursor)
	if err != nil {
		return FacetPage{}, err
	}
	// The two orders interleave differently, so resuming one from the
	// other's boundary would skip or repeat buckets rather than fail. A
	// client that flips the sort toggle starts the listing over, which is
	// what the toggle means; a mismatched pair is a bug, and saying so is
	// cheaper than the page it would otherwise get.
	if after != nil && after.order() != order {
		return FacetPage{}, errInvalid("cursor was issued for sort " + string(after.order()))
	}
	if after != nil && after.Dim != "" && after.Dim != canonical {
		return FacetPage{}, errInvalid("cursor was issued for dimension " + after.Dim)
	}
	// A scope change is a different bucket list, not a different window
	// onto one, so a cursor minted under another scope names no position
	// here. Refused for the reason the dimension mismatch is: an empty
	// page with no error is the silent wrong window.
	if after != nil && (after.Facet != scope.Facet || after.FacetKey != scope.Key) {
		return FacetPage{}, errInvalid("cursor was issued for a different scope")
	}
	if q.StartsAt != "" {
		if order != FacetSortLabel {
			return FacetPage{}, errInvalid("startsAt needs sort=label")
		}
		if after != nil {
			return FacetPage{}, errInvalid("startsAt and cursor both name a position")
		}
	}
	limit := q.Limit
	if limit <= 0 {
		// The handler bounds this, but a limit of zero would emit an empty
		// page carrying a cursor to the same place: a caller paging on it
		// would never advance.
		limit = facetDefaultLimit
	}
	// Built once, here, rather than once to validate and again to run.
	// Before the empty-grant short-circuit below, because a malformed
	// scope is a request error for every caller: answering an ungranted
	// one with an empty page instead would make the refusal depend on who
	// asked.
	scoped, err := l.facetScopeQuery(uc, scope)
	if err != nil {
		return FacetPage{}, err
	}
	// A restricted caller with no granted libraries can see nothing, and
	// an empty disjunction would compile to a match-nothing predicate
	// anyway; answer without touching the catalog.
	if !uc.AllLibraries && len(uc.Libraries) == 0 {
		return FacetPage{Dimension: canonical, Buckets: []FacetBucket{}}, nil
	}

	buckets, err := l.facetBuckets(ctx, uc, canonical, group, order, scope, scoped)
	if err != nil {
		return FacetPage{}, err
	}
	from := facetSeek(buckets, after, order)
	if q.StartsAt != "" {
		from = facetSeekPrefix(buckets, q.StartsAt)
	}
	out := FacetPage{Dimension: canonical, Buckets: []FacetBucket{}}
	for i := from; i < len(buckets); i++ {
		if len(out.Buckets) == limit {
			out.Next = encodeFacetCursor(buckets[i-1], canonical, order, scope)
			break
		}
		out.Buckets = append(out.Buckets, buckets[i])
	}
	return out, nil
}

// facetScopeFor validates the scope pair and returns it canonicalized.
// An empty facet is no scope, whatever facetKey says: the pair is keyed
// on the dimension, exactly as it is on the drill list.
func facetScopeFor(facet, key, dimension string) (facetScope, error) {
	if facet == "" {
		return facetScope{}, nil
	}
	_, canonical, err := facetGroupFor(facet)
	if err != nil {
		return facetScope{}, err
	}
	// Compared in canonical form, so `tag.mood` cannot scope `tag.MOOD`.
	// Scoping a dimension by itself would answer the one bucket it was
	// handed, which is a question the caller has already answered.
	if canonical == dimension {
		return facetScope{}, errInvalid("cannot scope the " + dimension + " enumeration by itself")
	}
	// The key itself is not checked here. Building the real query is what
	// checks it, and doing it twice would be two builders that can drift:
	// a validation applyFacetFilter grew from the incoming builder (a
	// library predicate, a media narrowing) would be asked of a bare
	// visibleItems() here and of the caller's own scope there, and one
	// would accept what the other refused.
	return facetScope{Facet: canonical, Key: key}, nil
}

// facetSeekPrefix returns the first bucket sorting at or after the
// folded prefix, or len(buckets) when it sorts past every real one.
//
// At-or-after, not equality, so startsAt=m lands on the first N when a
// library jumps L to N. Real buckets only: the unknown bucket sorts
// last whatever its sentinel spells and the rail has no row for it.
func facetSeekPrefix(buckets []FacetBucket, prefix string) int {
	real := sort.Search(len(buckets), func(i int) bool { return buckets[i].Unknown })
	fold := facetFolded(FacetBucket{Label: prefix}).fold
	at := sort.Search(real, func(i int) bool { return buckets[i].fold >= fold })
	if at == real {
		return len(buckets)
	}
	return at
}

// facetBuckets computes (or serves from cache) a dimension's whole
// bucket list for the caller, in the requested order.
func (l *Library) facetBuckets(ctx context.Context, uc *UserCtx, dimension string, group read.GroupBy, order FacetSort, scope facetScope, scoped query.Query) ([]FacetBucket, error) {
	gen := l.facetGeneration()
	// A scoped enumeration takes part in the cache in neither direction.
	// Not read, because the cached entry is the whole library's and
	// answering it here would hand an artist page every album there is.
	// Not published either, and that is the load-bearing half: the key
	// names a dimension and an order, so a scoped result published under
	// it would poison the unscoped read for everyone until the catalog
	// moved. Keying the scope in instead would mint an unbounded number
	// of entries, one per entity, which is what the bound on the scoped
	// read makes unnecessary - it is cheap because it is scoped.
	cacheable := uc.AllLibraries && !scope.scoped()
	if cacheable {
		l.facets.mu.Lock()
		if l.facets.gen == gen {
			if cached, ok := l.facets.byDimension[facetCacheKey{dimension, order}]; ok {
				l.facets.mu.Unlock()
				return cached, nil
			}
		}
		l.facets.mu.Unlock()
	}

	// No top-N: paging a window needs the whole enumeration. The order
	// is applied here because facetFolded folds the display label while
	// FacetOrderLabel collates sort_key, so "The Beatles" files under B
	// there and T here, and the rail follows this file.
	res, err := l.lib.Facet(ctx, scoped, group, read.FacetOrderLabel, 0, model.PID(uc.CatalogPID))
	if err != nil {
		return nil, classify(err)
	}
	// The genre dimension's labels come from catalog rows whose display
	// name is whichever spelling was scanned first and which cannot be
	// renamed, so the canonical spelling is applied here. Two rows that
	// resolve to one canonical name stay two buckets: they are distinct
	// catalog entities, and merging their counts would hand out a count
	// no single drill-down could reproduce. The normalization sweeper is
	// what actually collapses them, by moving items onto one row.
	var norm *genre.Normalizer
	if dimension == facetDimensionGenre {
		if norm, err = l.genreNormalizer(ctx); err != nil {
			l.log.Warn("facets: genre vocabulary unavailable; showing stored labels", "err", err)
			norm = nil
		}
	}
	out := make([]FacetBucket, 0, len(res.Buckets))
	for _, b := range res.Buckets {
		label := b.Display
		if norm != nil && !b.IsUnknown {
			label = canonicalGenreLabel(norm, label)
		}
		bucket := FacetBucket{
			Key:     b.Key,
			Label:   label,
			Count:   b.Count,
			Unknown: b.IsUnknown,
		}
		// entityAPIPID guards the empty handle an unknown bucket carries;
		// the prefix guard is for the dimensions whose buckets are catalog
		// entities the first-party API has no pid surface for.
		if prefix := facetEntityPrefix(dimension); prefix != "" {
			bucket.EntityPID = entityAPIPID(prefix, b.EntityPID)
		}
		out = append(out, facetFolded(bucket))
	}

	sortFacetBuckets(out, order)
	if !cacheable {
		// Nothing a restricted caller or a scoped read computes is
		// published, so the other order would be sorted for a cache it can
		// never reach.
		return out, nil
	}
	l.publishFacetBuckets(gen, dimension, order, out)

	// Both orders come out of the one aggregation. The catalog call is the
	// expensive half and the answers differ only in arrangement, so
	// sorting a copy costs a fraction of a second aggregation and leaves
	// the other order warm for the toggle that is about to ask for it.
	other := FacetSortCount
	if order == FacetSortCount {
		other = FacetSortLabel
	}
	alternate := append([]FacetBucket(nil), out...)
	sortFacetBuckets(alternate, other)
	l.publishFacetBuckets(gen, dimension, other, alternate)
	return out, nil
}

// facetGeneration reads the inputs a cached enumeration is valid for.
func (l *Library) facetGeneration() facetGeneration {
	return facetGeneration{tail: l.CatalogTailSeq(), vocab: l.genres.version.Load()}
}

// publishFacetBuckets stores an enumeration under the generation it was
// computed from, and only while that generation is still the current
// one.
//
// The computation runs unlocked and can take a while, so by the time it
// finishes the catalog may have moved or the vocabulary may have been
// edited -- either of which makes these buckets stale before anyone
// reads them. Publishing anyway would be worse than not caching at all:
// the entry would carry old labels stamped with the live generation, and
// nothing would dislodge it, because the vocabulary edit that
// invalidated it is exactly the kind of change that moves nothing else.
// A result from an older generation is dropped for the mirror-image
// reason: letting it land would roll the cache back and evict a newer
// dimension's entry, turning every later read into a miss.
func (l *Library) publishFacetBuckets(gen facetGeneration, dimension string, order FacetSort, buckets []FacetBucket) {
	l.facets.mu.Lock()
	defer l.facets.mu.Unlock()
	if l.facetGeneration() != gen {
		return
	}
	if l.facets.gen != gen || l.facets.byDimension == nil {
		l.facets.gen, l.facets.byDimension = gen, map[facetCacheKey][]FacetBucket{}
	}
	l.facets.byDimension[facetCacheKey{dimension, order}] = buckets
}

// sortFacetBuckets arranges buckets in one of the two orders, stably, so
// paging is reproducible across the cache boundary.
func sortFacetBuckets(buckets []FacetBucket, order FacetSort) {
	less := facetLess
	if order == FacetSortLabel {
		less = facetLabelLess
	}
	sort.SliceStable(buckets, func(i, j int) bool { return less(buckets[i], buckets[j]) })
}

// facetCursor is a page boundary: the sort position of the last bucket
// of the previous page, and the order that position was taken in.
// Paging resumes strictly after it.
//
// This is a keyset over a computed slice, not an offset into one, for
// the same reason every other listing here is keyset: bucket counts move
// as the library changes, and counts are the leading sort term of the
// default order, so an offset would skip or repeat buckets whenever a
// count shifted between two pages. Resuming after a remembered position
// degrades to at worst re-showing or missing the buckets that actually
// moved.
type facetCursor struct {
	Count int    `json:"c"`
	Label string `json:"l"`
	Key   string `json:"k"`
	// Unknown is part of the position because the label order sorts the
	// sentinel bucket last rather than by its label; without it the
	// boundary would be compared as an ordinary bucket and the seek would
	// land in the wrong place at exactly that edge.
	Unknown bool `json:"u,omitempty"`
	// Sort is absent on a count-ordered cursor, which is the default, so
	// the encoding of the order this endpoint has always served does not
	// change.
	Sort string `json:"s,omitempty"`
	// Dim is the canonical dimension. Without it a genre cursor replayed
	// on artist seeks among the wrong buckets and answers an empty page
	// with no error, which is the silent wrong window every other cursor
	// in this service refuses.
	Dim string `json:"d,omitempty"`
	// Facet and FacetKey are the scope the cursor was issued under, for
	// Dim's reason: a scoped page and an unscoped one are two bucket
	// lists, not two windows onto one. Both absent on an unscoped cursor,
	// so the encoding this endpoint has always served does not change.
	Facet    string `json:"f,omitempty"`
	FacetKey string `json:"fk,omitempty"`
}

// order is the sort the cursor was issued under.
func (c *facetCursor) order() FacetSort {
	if c.Sort == "" {
		return FacetSortCount
	}
	return FacetSort(c.Sort)
}

func encodeFacetCursor(b FacetBucket, dimension string, order FacetSort, scope facetScope) string {
	cur := facetCursor{
		Count: b.Count, Label: b.Label, Key: b.Key, Unknown: b.Unknown, Dim: dimension,
		Facet: scope.Facet, FacetKey: scope.Key,
	}
	if order != FacetSortCount {
		cur.Sort = string(order)
	}
	raw, err := json.Marshal(cur)
	if err != nil {
		return ""
	}
	return base64.RawURLEncoding.EncodeToString(raw)
}

// decodeFacetCursor parses a page boundary; a nil result means the first
// page. A non-empty but malformed cursor is rejected rather than
// silently restarting, matching the catalog's own cursor contract.
func decodeFacetCursor(c string) (*facetCursor, error) {
	if c == "" {
		return nil, nil
	}
	raw, err := base64.RawURLEncoding.DecodeString(c)
	if err != nil {
		return nil, errInvalid("malformed cursor")
	}
	var cur facetCursor
	if err := json.Unmarshal(raw, &cur); err != nil {
		return nil, errInvalid("malformed cursor")
	}
	return &cur, nil
}

// facetSeek returns the index of the first bucket sorting strictly after
// the cursor, or 0 for the first page. The slice is already in the
// requested order, so this is a binary search.
func facetSeek(buckets []FacetBucket, after *facetCursor, order FacetSort) int {
	if after == nil {
		return 0
	}
	less := facetLess
	if order == FacetSortLabel {
		less = facetLabelLess
	}
	boundary := facetFolded(FacetBucket{
		Count:   after.Count,
		Label:   after.Label,
		Key:     after.Key,
		Unknown: after.Unknown,
	})
	return sort.Search(len(buckets), func(i int) bool {
		return less(boundary, buckets[i])
	})
}

// facetLabelLess is the A-to-Z order: by display label, ties broken by
// key so equal-label buckets (two catalog rows that normalize to one
// genre name) never swap places between one page and the next.
//
// The unknown bucket sorts last whatever its sentinel spells. "[No
// Genre]" would otherwise lead every genre index on its bracket, which
// puts the one bucket nobody is looking for where the A's belong.
func facetLabelLess(a, b FacetBucket) bool {
	if a.Unknown != b.Unknown {
		return b.Unknown
	}
	if a.fold != b.fold {
		return a.fold < b.fold
	}
	// Two labels differing only in case are one rail letter apart from
	// nobody, but the order still has to be total for the keyset to
	// resume on it.
	if a.Label != b.Label {
		return a.Label < b.Label
	}
	return a.Key < b.Key
}

// facetLess is the bucket sort order: biggest first, ties broken by
// label then key so equal-count buckets never swap places between one
// page and the next.
func facetLess(a, b FacetBucket) bool {
	if a.Count != b.Count {
		return a.Count > b.Count
	}
	if a.Label != b.Label {
		return a.Label < b.Label
	}
	return a.Key < b.Key
}

// facetScopeBuilder is the enumeration's base query: everything for a
// full-visibility caller, and the caller's granted libraries otherwise.
// A different builder from the drill's, so it has to carry the same
// state predicate or a bucket's count and the listing it opens disagree
// (TestFacetDimensionsDrillToTheirCount).
//
// A builder rather than a finished query so applyFacetFilter can narrow
// it further: the two never met before this, and composing them is what
// answers "the albums this artist is credited on" as album buckets
// rather than as a download of item rows.
func (l *Library) facetScopeBuilder(uc *UserCtx) *query.Builder {
	b := visibleItems()
	if uc.AllLibraries {
		return b
	}
	libs := make([]string, 0, len(uc.Libraries))
	for lib := range uc.Libraries {
		libs = append(libs, lib)
	}
	// Sorted so the compiled SQL is stable across map iteration orders.
	sort.Strings(libs)
	// An allow-list, so `in`: it seeks the index and an empty grant
	// compiles to `1=0`. Deliberately not `notIn` over the complement -
	// that is an anti-join scanning the catalog, and it keeps fileless
	// items, which ADR-0051 attributes to no library.
	return b.WhereValues("library", query.OpIn, query.Values(libs)...)
}

// facetScopeQuery is facetScopeBuilder narrowed by an optional scope
// bucket and built. An empty scope.Facet is the whole-library
// enumeration this endpoint has always answered.
func (l *Library) facetScopeQuery(uc *UserCtx, scope facetScope) (query.Query, error) {
	b := l.facetScopeBuilder(uc)
	if scope.Facet == "" {
		return b.Build(), nil
	}
	b, err := applyFacetFilter(b, scope.Facet, scope.Key)
	if err != nil {
		return query.Query{}, err
	}
	return b.Build(), nil
}

// facetGroupFor validates a dimension name and returns its catalog
// faceting group.
// It also returns the dimension's canonical spelling, which for a custom
// tag is "tag." plus the catalog's canonical (uppercased, trimmed) key.
// Everything downstream uses that rather than what the caller typed:
// tag keys canonicalize, so `tag.mood` and `tag.MOOD` are one dimension
// answering one bucket list, and keying the cache on the raw string
// instead would let a client mint an unbounded number of entries holding
// identical enumerations while the catalog sat idle.
func facetGroupFor(dimension string) (read.GroupBy, string, error) {
	if g, ok := browseDimensions[dimension]; ok {
		return g, dimension, nil
	}
	if strings.HasPrefix(dimension, facetTagPrefix) {
		key, ok := read.TagGroupKey(read.GroupBy(dimension))
		if !ok {
			return "", "", errInvalid("unknown custom tag key in dimension " + dimension)
		}
		canonical := facetTagPrefix + key
		return read.GroupBy(canonical), canonical, nil
	}
	return "", "", errInvalid("unknown browse dimension " + dimension)
}

// facetEntityPrefix is the API pid prefix for a dimension's entity
// buckets. Only the artist-shaped, album-shaped, and release-group
// dimensions have one; a genre entity has no first-party pid surface,
// and year, kind, and tag buckets are not entities at all.
func facetEntityPrefix(dimension string) string {
	switch dimension {
	case "artist", "credit-artist", "album-artist":
		return PrefixArtist
	case "album":
		return PrefixAlbum
	case "release-group":
		return PrefixReleaseGroup
	default:
		return ""
	}
}

// applyFacetFilter narrows an item query to one bucket of a browse
// dimension. An empty key selects the dimension's unknown bucket (items
// the dimension is absent from), which is a real bucket the enumeration
// returns, so it must be drillable -- but only on the dimensions that
// have one.
func applyFacetFilter(b *query.Builder, dimension, key string) (*query.Builder, error) {
	_, canonical, err := facetGroupFor(dimension)
	if err != nil {
		return nil, err
	}
	dimension = canonical
	field, fixed := facetFilterField[dimension]
	if !fixed {
		// A custom-tag dimension filters on the same tag.<KEY> field the
		// facet groups by.
		field = dimension
	}
	if key == "" && !facetHasUnknownBucket[dimension] {
		// Only items carrying a tag key contribute to that dimension, and
		// an item's kind is never absent, so neither enumerates an unknown
		// bucket and neither has one to drill. Answering an empty page
		// instead would look like a real but empty bucket.
		return nil, errInvalid("the " + dimension + " dimension has no unknown bucket to drill")
	}
	if facetNoEpisodes[dimension] {
		// Mirror the aggregation, which leaves episodes out of the music
		// dimensions entirely; without this the unknown bucket's list
		// would return every episode the count never included.
		b = b.Where("kind", query.OpIsNot, string(model.KindEpisode))
	}
	if key == "" {
		return b.WherePresence(field, query.OpIsMissing), nil
	}
	if dimension == "year" {
		// The year bucket key is the year rendered as text, so it parses
		// back to the integer the query field compares on. Atoi rejects an
		// overflowing value rather than wrapping it into one that would
		// silently match nothing.
		year, err := strconv.Atoi(key)
		if err != nil || year < 0 {
			return nil, errInvalid("year must be a non-negative number, got " + key)
		}
		return b.Where(field, query.OpIs, year), nil
	}
	return b.Where(field, query.OpIs, key), nil
}
