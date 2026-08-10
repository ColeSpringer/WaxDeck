package service

import (
	"context"
	"math"
	"math/rand"
	"sort"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
	"github.com/colespringer/waxbin/read"

	"github.com/colespringer/waxdeck/server/internal/similarity"
)

// Discovery: similar tracks, instant mixes, and sonic paths. Sonic
// answers ride the embedding engine; every surface except paths
// degrades to metadata heuristics (genre and artist neighborhoods) so
// discovery works with zero setup. All results honor the caller's
// library visibility and content rules.

// BasisSonic and BasisMetadata name which engine answered.
const (
	BasisSonic    = "sonic"
	BasisMetadata = "metadata"
)

// SimilarTracksResult is the similar-tracks answer.
type SimilarTracksResult struct {
	Basis string
	Items []ItemSummary
}

// InstantMixInput is a mix request.
type InstantMixInput struct {
	SeedPID         string
	Genre           string
	Adventurousness float64
	Size            int
	ExcludePIDs     []string
}

// InstantMixResult is a computed mix.
type InstantMixResult struct {
	Basis string
	Items []ItemSummary
}

// SonicPathResult is a sonic path between two tracks.
type SonicPathResult struct {
	Complete bool
	Items    []ItemSummary
}

// itemEssence resolves an item's audio essence for similarity queries;
// empty for virtual tracks (they share the backing file's essence) and
// for items whose file cannot be read.
func (l *Library) itemEssence(ctx context.Context, it *model.ItemView) string {
	if it.Virtual {
		return ""
	}
	f, err := l.lib.File(ctx, it.FilePID)
	if err != nil {
		return ""
	}
	return f.EssenceHash
}

// SimilarTracksFor answers tracks similar to a seed track.
func (l *Library) SimilarTracksFor(ctx context.Context, uc *UserCtx, apiItemPID string, limit int) (SimilarTracksResult, error) {
	it, err := l.getVisibleItem(ctx, uc, apiItemPID)
	if err != nil {
		return SimilarTracksResult{}, err
	}
	if it.Kind != model.KindTrack {
		return SimilarTracksResult{}, errInvalid("similar tracks needs a music track seed")
	}
	if err := l.warmSimilarity(ctx); err != nil {
		return SimilarTracksResult{}, err
	}
	exclude := map[string]bool{string(it.PID): true}
	if essence := l.itemEssence(ctx, it); essence != "" && l.sim.Has(essence) {
		edges := l.sim.Similar(essence, limit*4, nil)
		items, err := l.edgesToSummaries(ctx, uc, edges, limit, exclude)
		if err != nil {
			return SimilarTracksResult{}, err
		}
		if len(items) > 0 {
			return SimilarTracksResult{Basis: BasisSonic, Items: items}, nil
		}
	}
	items, err := l.metadataMix(ctx, uc, it.Genre, it.Artist, 0.3, limit, exclude)
	if err != nil {
		return SimilarTracksResult{}, err
	}
	return SimilarTracksResult{Basis: BasisMetadata, Items: items}, nil
}

// InstantMix builds a mix from a track pid, an artist pid, or a genre.
func (l *Library) InstantMix(ctx context.Context, uc *UserCtx, in InstantMixInput) (InstantMixResult, error) {
	if (in.SeedPID == "") == (in.Genre == "") {
		return InstantMixResult{}, errInvalid("exactly one of seedPid and genre must be set")
	}
	adv := math.Min(1, math.Max(0, in.Adventurousness))
	size := in.Size
	if size <= 0 {
		size = 50
	}
	if size > 200 {
		size = 200
	}
	if err := l.warmSimilarity(ctx); err != nil {
		return InstantMixResult{}, err
	}
	exclude := map[string]bool{}
	for _, ex := range in.ExcludePIDs {
		if _, pid, ok := parseAPIPID(ex); ok {
			exclude[string(pid)] = true
		}
	}
	switch {
	case in.Genre != "":
		return l.genreMix(ctx, uc, in.Genre, adv, size, exclude)
	default:
		prefix, _, ok := parseAPIPID(in.SeedPID)
		if !ok {
			return InstantMixResult{}, errInvalid("malformed seedPid")
		}
		switch prefix {
		case PrefixTrack:
			return l.trackMix(ctx, uc, in.SeedPID, adv, size, exclude)
		case PrefixArtist:
			return l.artistMix(ctx, uc, in.SeedPID, adv, size, exclude)
		case PrefixAlbum:
			return l.albumMix(ctx, uc, in.SeedPID, adv, size, exclude)
		default:
			return InstantMixResult{}, errInvalid("seedPid must be a track, artist, or album pid")
		}
	}
}

func (l *Library) trackMix(ctx context.Context, uc *UserCtx, apiItemPID string, adv float64, size int, exclude map[string]bool) (InstantMixResult, error) {
	it, err := l.getVisibleItem(ctx, uc, apiItemPID)
	if err != nil {
		return InstantMixResult{}, err
	}
	if it.Kind != model.KindTrack {
		return InstantMixResult{}, errInvalid("instant mix needs a music seed")
	}
	exclude[string(it.PID)] = true
	if essence := l.itemEssence(ctx, it); essence != "" && l.sim.Has(essence) {
		if vec, ok := l.sim.Vector(essence); ok {
			items, err := l.sonicSample(ctx, uc, vec, map[string]bool{essence: true}, adv, size, exclude)
			if err != nil {
				return InstantMixResult{}, err
			}
			if len(items) > 0 {
				return InstantMixResult{Basis: BasisSonic, Items: items}, nil
			}
		}
	}
	items, err := l.metadataMix(ctx, uc, it.Genre, it.Artist, adv, size, exclude)
	if err != nil {
		return InstantMixResult{}, err
	}
	return InstantMixResult{Basis: BasisMetadata, Items: items}, nil
}

func (l *Library) artistMix(ctx context.Context, uc *UserCtx, apiArtistPID string, adv float64, size int, exclude map[string]bool) (InstantMixResult, error) {
	_, pid, _ := parseAPIPID(apiArtistPID)
	// The entity lookup validates the pid and gives the canonical name
	// for the metadata fallback; the artist_pid facet field resolves the
	// members directly, retiring the old full-facet scan that mapped pid
	// to display name.
	info, err := l.lib.EntityByPID(ctx, read.EntityArtist, pid)
	if err != nil {
		return InstantMixResult{}, classify(err)
	}
	name := info.Name
	tracks, err := l.tracksWhere(ctx, uc, "artist_pid", string(pid), 200)
	if err != nil {
		return InstantMixResult{}, err
	}
	if len(tracks) == 0 {
		return InstantMixResult{}, errNotFound("no tracks for artist " + apiArtistPID)
	}
	// The artist's own tracks stay eligible simply by not being in the
	// exclude set; writing false entries for them would clobber pids
	// the caller explicitly excluded (already played this session).
	var essences []string
	genre := ""
	for _, t := range tracks {
		if genre == "" && t.Genre != "" {
			genre = t.Genre
		}
		if es := l.itemEssence(ctx, t); es != "" {
			essences = append(essences, es)
		}
	}
	if vec, ok := l.sim.Centroid(essences); ok {
		// No essence exclusions: the centroid's seed tracks are valid
		// members of their own artist's mix.
		items, err := l.sonicSample(ctx, uc, vec, map[string]bool{}, adv, size, exclude)
		if err != nil {
			return InstantMixResult{}, err
		}
		if len(items) > 0 {
			return InstantMixResult{Basis: BasisSonic, Items: items}, nil
		}
	}
	items, err := l.metadataMix(ctx, uc, genre, name, adv, size, exclude)
	if err != nil {
		return InstantMixResult{}, err
	}
	return InstantMixResult{Basis: BasisMetadata, Items: items}, nil
}

// albumMix builds a mix seeded from an album entity: the album's own
// tracks anchor the sonic centroid, with a metadata blend as the
// zero-embedding fallback. The album_pid facet field resolves the
// members by entity identity rather than a display-string match.
func (l *Library) albumMix(ctx context.Context, uc *UserCtx, apiAlbumPID string, adv float64, size int, exclude map[string]bool) (InstantMixResult, error) {
	_, pid, _ := parseAPIPID(apiAlbumPID)
	if _, err := l.lib.EntityByPID(ctx, read.EntityAlbum, pid); err != nil {
		return InstantMixResult{}, classify(err)
	}
	tracks, err := l.tracksWhere(ctx, uc, "album_pid", string(pid), 200)
	if err != nil {
		return InstantMixResult{}, err
	}
	if len(tracks) == 0 {
		return InstantMixResult{}, errNotFound("no tracks for album " + apiAlbumPID)
	}
	var essences []string
	genre, artist := "", ""
	for _, t := range tracks {
		if genre == "" && t.Genre != "" {
			genre = t.Genre
		}
		if artist == "" {
			if t.AlbumArtist != "" {
				artist = t.AlbumArtist
			} else if t.Artist != "" {
				artist = t.Artist
			}
		}
		if es := l.itemEssence(ctx, t); es != "" {
			essences = append(essences, es)
		}
	}
	if vec, ok := l.sim.Centroid(essences); ok {
		// No essence exclusions: the album's own tracks are valid members.
		items, err := l.sonicSample(ctx, uc, vec, map[string]bool{}, adv, size, exclude)
		if err != nil {
			return InstantMixResult{}, err
		}
		if len(items) > 0 {
			return InstantMixResult{Basis: BasisSonic, Items: items}, nil
		}
	}
	items, err := l.metadataMix(ctx, uc, genre, artist, adv, size, exclude)
	if err != nil {
		return InstantMixResult{}, err
	}
	return InstantMixResult{Basis: BasisMetadata, Items: items}, nil
}

func (l *Library) genreMix(ctx context.Context, uc *UserCtx, genre string, adv float64, size int, exclude map[string]bool) (InstantMixResult, error) {
	tracks, err := l.tracksWhere(ctx, uc, "genre", genre, 500)
	if err != nil {
		return InstantMixResult{}, err
	}
	if len(tracks) == 0 {
		return InstantMixResult{}, errNotFound("no tracks in genre " + genre)
	}
	// With embedding coverage a genre mixes sonically around its own
	// centroid, which orders the wander musically instead of purely at
	// random.
	var essences []string
	for _, t := range tracks {
		if es := l.itemEssence(ctx, t); es != "" && l.sim.Has(es) {
			essences = append(essences, es)
			if len(essences) >= 50 {
				break
			}
		}
	}
	if len(essences) >= 10 {
		if vec, ok := l.sim.Centroid(essences); ok {
			items, err := l.sonicSample(ctx, uc, vec, map[string]bool{}, adv, size, exclude)
			if err != nil {
				return InstantMixResult{}, err
			}
			if len(items) > 0 {
				return InstantMixResult{Basis: BasisSonic, Items: items}, nil
			}
		}
	}
	items, err := l.metadataMix(ctx, uc, genre, "", adv, size, exclude)
	if err != nil {
		return InstantMixResult{}, err
	}
	return InstantMixResult{Basis: BasisMetadata, Items: items}, nil
}

// SonicPathFor answers a listening path between two tracks. Paths have
// no metadata fallback: both endpoints need embeddings.
func (l *Library) SonicPathFor(ctx context.Context, uc *UserCtx, fromPID, toPID string, length int) (SonicPathResult, error) {
	from, err := l.getVisibleItem(ctx, uc, fromPID)
	if err != nil {
		return SonicPathResult{}, err
	}
	to, err := l.getVisibleItem(ctx, uc, toPID)
	if err != nil {
		return SonicPathResult{}, err
	}
	if from.Kind != model.KindTrack || to.Kind != model.KindTrack {
		return SonicPathResult{}, errInvalid("sonic paths connect music tracks")
	}
	if err := l.warmSimilarity(ctx); err != nil {
		return SonicPathResult{}, err
	}
	fromEss, toEss := l.itemEssence(ctx, from), l.itemEssence(ctx, to)
	if fromEss == "" || toEss == "" || !l.sim.Has(fromEss) || !l.sim.Has(toEss) {
		return SonicPathResult{}, &Error{Kind: KindFeature,
			Msg: "no embedding coverage for these tracks; the similarity worker has not analyzed them yet"}
	}
	essences, complete := l.sim.Path(fromEss, toEss, length)
	edges := make([]similarity.Edge, len(essences))
	for i, es := range essences {
		edges[i] = similarity.Edge{Neighbor: es}
	}
	items, err := l.edgesToSummaries(ctx, uc, edges, length+2, map[string]bool{})
	if err != nil {
		return SonicPathResult{}, err
	}
	return SonicPathResult{Complete: complete, Items: items}, nil
}

// sonicSample picks size tracks near a seed vector. Adventurousness
// widens the candidate pool and jitters the ranking: 0 keeps the
// nearest neighbors in order, 1 samples far into the pool.
func (l *Library) sonicSample(ctx context.Context, uc *UserCtx, vec []float32, seedEssences map[string]bool, adv float64, size int, exclude map[string]bool) ([]ItemSummary, error) {
	pool := int(float64(size) * (2 + 8*adv))
	edges := l.sim.SimilarToVector(vec, pool, seedEssences)
	if len(edges) == 0 {
		return nil, nil
	}
	// Jittered rank: each candidate's sort key is its rank plus noise
	// whose amplitude grows with adventurousness.
	type keyed struct {
		e   similarity.Edge
		key float64
	}
	keys := make([]keyed, len(edges))
	for i, e := range edges {
		keys[i] = keyed{e: e, key: float64(i) + rand.Float64()*adv*float64(len(edges))}
	}
	sort.Slice(keys, func(i, j int) bool { return keys[i].key < keys[j].key })
	ordered := make([]similarity.Edge, len(keys))
	for i, k := range keys {
		ordered[i] = k.e
	}
	return l.edgesToSummaries(ctx, uc, ordered, size, exclude)
}

// edgesToSummaries resolves essences to visible items in order, capped
// at limit. Items gone from the catalog, outside the caller's
// visibility, or in the exclude set drop silently.
func (l *Library) edgesToSummaries(ctx context.Context, uc *UserCtx, edges []similarity.Edge, limit int, exclude map[string]bool) ([]ItemSummary, error) {
	essences := make([]string, 0, len(edges))
	for _, e := range edges {
		essences = append(essences, e.Neighbor)
	}
	byEssence, err := l.db.EmbeddingItemPIDs(ctx, essences)
	if err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	pids := make([]model.PID, 0, len(edges))
	order := make([]string, 0, len(edges))
	for _, e := range edges {
		pid, ok := byEssence[e.Neighbor]
		if !ok || exclude[pid] {
			continue
		}
		pids = append(pids, model.PID(pid))
		order = append(order, pid)
	}
	if len(pids) == 0 {
		return nil, nil
	}
	views, err := l.lib.GetMany(ctx, pids)
	if err != nil {
		return nil, classify(err)
	}
	byPID := make(map[string]*model.ItemView, len(views))
	for _, v := range views {
		byPID[string(v.PID)] = v
	}
	out := make([]ItemSummary, 0, limit)
	seen := map[string]bool{}
	for _, pid := range order {
		if len(out) >= limit {
			break
		}
		if seen[pid] {
			continue
		}
		seen[pid] = true
		v := byPID[pid]
		if v == nil || v.Kind != model.KindTrack {
			continue
		}
		// Neighbours arrive as pids from the similarity index, so the mix's
		// other half filters by query and this half has to filter here.
		if archived(v) {
			continue
		}
		if !uc.AllLibraries && !l.itemVisible(ctx, uc, v.PID) {
			continue
		}
		if !l.allowedByContent(ctx, uc, v) {
			continue
		}
		out = append(out, summary(v))
	}
	return out, nil
}

// tracksWhere pages music tracks matching one text field exactly
// (case-insensitively, matching the engine's text semantics), capped.
func (l *Library) tracksWhere(ctx context.Context, uc *UserCtx, field, value string, cap int) ([]*model.ItemView, error) {
	q := visibleItems().
		Where("kind", query.OpIs, string(model.KindTrack)).
		Where(field, query.OpIs, value).
		OrderBy("title", false).Build()
	var out []*model.ItemView
	cursor := read.Cursor("")
	for len(out) < cap {
		page, err := l.lib.QueryPage(ctx, q, cursor, 200, false, model.PID(uc.CatalogPID))
		if err != nil {
			return nil, classify(err)
		}
		out = append(out, page.Items...)
		if !page.HasMore {
			break
		}
		cursor = page.Next
	}
	if len(out) > cap {
		out = out[:cap]
	}
	return out, nil
}

// metadataMix is the zero-setup fallback: a shuffled blend of same-
// artist, same-genre, and random-catalog tracks whose proportions
// follow the adventurousness knob.
func (l *Library) metadataMix(ctx context.Context, uc *UserCtx, genre, artist string, adv float64, size int, exclude map[string]bool) ([]ItemSummary, error) {
	var artistPool, genrePool, randomPool []*model.ItemView
	if artist != "" {
		pool, err := l.tracksWhere(ctx, uc, "artist", artist, 100)
		if err != nil {
			return nil, err
		}
		artistPool = pool
	}
	if genre != "" {
		pool, err := l.tracksWhere(ctx, uc, "genre", genre, 400)
		if err != nil {
			return nil, err
		}
		genrePool = pool
	}
	// Random catalog tracks widen the mix; always fetched so a sparse
	// genre still fills the request. Scoped in the draw, so 300 rows are
	// 300 candidates.
	page, err := l.lib.Browse(ctx, read.ListRandom, read.BrowseOptions{
		UserPID: model.PID(uc.CatalogPID),
		Seed:    rand.Int63(),
		Limit:   300,
		Query: visibleItems().
			Where("kind", query.OpIs, string(model.KindTrack)).Build(),
	})
	if err != nil {
		return nil, classify(err)
	}
	randomPool = append(randomPool, page.Items...)
	// Blend proportions: closeness favors the seed artist, wandering
	// favors the random pool, the genre carries the middle.
	pArtist := 0.35 * (1 - adv)
	pRandom := 0.15 + 0.6*adv
	if artist == "" {
		pArtist = 0
	}
	if genre == "" {
		pRandom = 1 - pArtist
	}
	shuffle := func(pool []*model.ItemView) {
		rand.Shuffle(len(pool), func(i, j int) { pool[i], pool[j] = pool[j], pool[i] })
	}
	shuffle(artistPool)
	shuffle(genrePool)
	shuffle(randomPool)
	out := make([]ItemSummary, 0, size)
	seen := map[string]bool{}
	take := func(pool *[]*model.ItemView) bool {
		for len(*pool) > 0 {
			it := (*pool)[0]
			*pool = (*pool)[1:]
			pid := string(it.PID)
			if seen[pid] || exclude[pid] {
				continue
			}
			if !uc.AllLibraries && !l.itemVisible(ctx, uc, it.PID) {
				continue
			}
			if !l.allowedByContent(ctx, uc, it) {
				continue
			}
			seen[pid] = true
			out = append(out, summary(it))
			return true
		}
		return false
	}
	for len(out) < size {
		r := rand.Float64()
		var ok bool
		switch {
		case r < pArtist:
			ok = take(&artistPool)
		case r < pArtist+pRandom:
			ok = take(&randomPool)
		default:
			ok = take(&genrePool)
		}
		if !ok {
			// The chosen pool ran dry; drain the others in preference
			// order before giving up.
			if !take(&genrePool) && !take(&artistPool) && !take(&randomPool) {
				break
			}
		}
	}
	return out, nil
}
