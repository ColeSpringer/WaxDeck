package service

// First-party faceted browse: enumerating a browse dimension's buckets
// with counts, and the matching filter that drills one bucket into an
// item list.
//
// The catalog answers the aggregation; WaxDeck owns the paging, the
// visibility scope, and the labels. Three things are worth knowing
// before changing this file.
//
// Paging is in memory. The facade's Facet takes no cursor and returns
// every bucket of a dimension in one result, so a page is a window over
// a sorted slice using the same opaque offset cursor the smart-playlist
// listings page with. Keyset pagination on Facet is filed upstream
// (docs/upstream-requests.md); when it lands, this becomes a passthrough
// like every other listing and the cache below can go.
//
// Caching is narrow on purpose. Only the unfiltered enumeration, only
// per dimension, only for full-visibility callers, keyed on the catalog
// feed position — the same restriction TrackFacts applies, for the same
// reason: Facet takes a user pid and a query, so a restricted caller's
// answer is not a function of the tail alone. A restricted caller's
// enumeration is computed live every time.
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

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
	"github.com/colespringer/waxbin/read"

	"github.com/colespringer/waxdeck/server/internal/genre"
)

// Browse dimension names as the API spells them, mapped onto the
// catalog's faceting groups. A custom-tag dimension ("tag.<KEY>") is not
// enumerated here: tag keys are open-ended, so it is validated by the
// catalog's own tag-key rules instead.
var browseDimensions = map[string]read.GroupBy{
	"genre":        read.GroupGenre,
	"artist":       read.GroupArtist,
	"album-artist": read.GroupAlbumArtist,
	"album":        read.GroupAlbum,
	"year":         read.GroupYear,
	"kind":         read.GroupKind,
}

// facetFilterField is the query field a dimension's bucket key filters
// on. Every one of them is the same expression the facet groups by, so a
// bucket's count and the list it opens can never disagree about what
// belongs in it.
var facetFilterField = map[string]string{
	"genre":        "genre_pid",
	"artist":       "artist_pid",
	"album-artist": "album_artist_pid",
	"album":        "album_pid",
	"year":         "year",
	"kind":         "kind",
}

// facetTagPrefix marks a custom-tag browse dimension.
const facetTagPrefix = "tag."

// facetDimensionGenre is the one dimension whose labels come from
// WaxDeck's own genre vocabulary rather than from the catalog alone, so
// it is the one an edit to that vocabulary has to evict.
const facetDimensionGenre = "genre"

// facetDefaultLimit matches the spec's default page size.
const facetDefaultLimit = 100

// facetNoEpisodes names the dimensions the catalog computes with podcast
// episodes excluded (they carry no artist, album, genre, or year in the
// music sense, so including them would pile every episode into one
// unknown bucket). The drill filter mirrors it so the item set matches
// the bucket count.
var facetNoEpisodes = map[string]bool{
	"genre": true, "artist": true, "album-artist": true, "album": true, "year": true,
}

// facetHasUnknownBucket names the dimensions that enumerate a bucket for
// the items they are absent from ("[No Genre]", "[Non-Album]"), which is
// what an empty bucket key drills. `kind` has none because an item's
// kind is never absent, and a custom tag has none because only items
// carrying the key contribute to it at all. The membership happens to
// match facetNoEpisodes today; they answer different questions, so they
// stay separate lists.
var facetHasUnknownBucket = map[string]bool{
	"genre": true, "artist": true, "album-artist": true, "album": true, "year": true,
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
}

// FacetPage is one keyset-paginated page of a dimension's buckets.
type FacetPage struct {
	Dimension string
	Buckets   []FacetBucket
	Next      string
}

// facetCache holds the full-visibility enumerations, keyed by dimension
// within one generation of the inputs they were computed from.
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
	byDimension map[string][]FacetBucket
}

// facetGeneration identifies the inputs an enumeration was computed
// from. Both components only ever increase.
type facetGeneration struct {
	tail  int64
	vocab int64
}

// Facets enumerates one browse dimension's buckets, most items first
// within the catalog's own collation order, paged.
func (l *Library) Facets(ctx context.Context, uc *UserCtx, dimension, cursor string, limit int) (FacetPage, error) {
	group, canonical, err := facetGroupFor(dimension)
	if err != nil {
		return FacetPage{}, err
	}
	after, err := decodeFacetCursor(cursor)
	if err != nil {
		return FacetPage{}, err
	}
	if limit <= 0 {
		// The handler bounds this, but a limit of zero would emit an empty
		// page carrying a cursor to the same place: a caller paging on it
		// would never advance.
		limit = facetDefaultLimit
	}
	// A restricted caller with no granted libraries can see nothing, and
	// an empty disjunction would compile to a match-nothing predicate
	// anyway; answer without touching the catalog.
	if !uc.AllLibraries && len(uc.Libraries) == 0 {
		return FacetPage{Dimension: canonical, Buckets: []FacetBucket{}}, nil
	}

	buckets, err := l.facetBuckets(ctx, uc, canonical, group)
	if err != nil {
		return FacetPage{}, err
	}
	out := FacetPage{Dimension: canonical, Buckets: []FacetBucket{}}
	for i := facetSeek(buckets, after); i < len(buckets); i++ {
		if len(out.Buckets) == limit {
			out.Next = encodeFacetCursor(buckets[i-1])
			break
		}
		out.Buckets = append(out.Buckets, buckets[i])
	}
	return out, nil
}

// facetBuckets computes (or serves from cache) a dimension's whole
// bucket list for the caller.
func (l *Library) facetBuckets(ctx context.Context, uc *UserCtx, dimension string, group read.GroupBy) ([]FacetBucket, error) {
	gen := l.facetGeneration()
	if uc.AllLibraries {
		l.facets.mu.Lock()
		if l.facets.gen == gen {
			if cached, ok := l.facets.byDimension[dimension]; ok {
				l.facets.mu.Unlock()
				return cached, nil
			}
		}
		l.facets.mu.Unlock()
	}

	res, err := l.lib.Facet(ctx, l.facetScopeQuery(uc), group, model.PID(uc.CatalogPID))
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
		out = append(out, bucket)
	}
	sortFacetBuckets(out)

	if uc.AllLibraries {
		l.publishFacetBuckets(gen, dimension, out)
	}
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
func (l *Library) publishFacetBuckets(gen facetGeneration, dimension string, buckets []FacetBucket) {
	l.facets.mu.Lock()
	defer l.facets.mu.Unlock()
	if l.facetGeneration() != gen {
		return
	}
	if l.facets.gen != gen || l.facets.byDimension == nil {
		l.facets.gen, l.facets.byDimension = gen, map[string][]FacetBucket{}
	}
	l.facets.byDimension[dimension] = buckets
}

// sortFacetBuckets orders buckets biggest first, ties broken by label
// then key so paging is stable across the cache boundary: a browse tab
// leads with the buckets worth opening, and equal-count buckets never
// swap places between one page and the next.
func sortFacetBuckets(buckets []FacetBucket) {
	sort.SliceStable(buckets, func(i, j int) bool { return facetLess(buckets[i], buckets[j]) })
}

// facetCursor is a page boundary: the sort position of the last bucket
// of the previous page. Paging resumes strictly after it.
//
// This is a keyset over a computed slice, not an offset into one, for
// the same reason every other listing here is keyset: bucket counts move
// as the library changes, and counts are the leading sort term, so an
// offset would skip or repeat buckets whenever a count shifted between
// two pages. Resuming after a remembered position degrades to at worst
// re-showing or missing the buckets that actually moved.
type facetCursor struct {
	Count int    `json:"c"`
	Label string `json:"l"`
	Key   string `json:"k"`
}

func encodeFacetCursor(b FacetBucket) string {
	raw, err := json.Marshal(facetCursor{Count: b.Count, Label: b.Label, Key: b.Key})
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
// the cursor, or 0 for the first page. The slice is already in
// facetLess order, so this is a binary search.
func facetSeek(buckets []FacetBucket, after *facetCursor) int {
	if after == nil {
		return 0
	}
	boundary := FacetBucket{Count: after.Count, Label: after.Label, Key: after.Key}
	return sort.Search(len(buckets), func(i int) bool {
		return facetLess(boundary, buckets[i])
	})
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

// facetScopeQuery is the enumeration's base query: everything for a
// full-visibility caller, and the caller's granted libraries otherwise.
func (l *Library) facetScopeQuery(uc *UserCtx) query.Query {
	b := query.New(query.EntityItems)
	if uc.AllLibraries {
		return b.Build()
	}
	libs := make([]string, 0, len(uc.Libraries))
	for lib := range uc.Libraries {
		libs = append(libs, lib)
	}
	// Sorted so the compiled SQL is stable across map iteration orders.
	sort.Strings(libs)
	nodes := make([]query.Node, 0, len(libs))
	for _, lib := range libs {
		nodes = append(nodes, query.Cond{Field: "library", Op: query.OpIs, Value: lib})
	}
	return b.WhereNode(query.Or{Nodes: nodes}).Build()
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
// buckets. Only the artist-shaped and album-shaped dimensions have one;
// a genre entity has no first-party pid surface, and year, kind, and tag
// buckets are not entities at all.
func facetEntityPrefix(dimension string) string {
	switch dimension {
	case "artist", "album-artist":
		return PrefixArtist
	case "album":
		return PrefixAlbum
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
