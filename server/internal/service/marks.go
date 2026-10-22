package service

import (
	"context"
	"slices"
	"sync"
	"time"

	"github.com/colespringer/waxbin/model"
)

// The calling user's stars, ratings and play record, read in batches for
// the compatibility surfaces, which annotate whole responses with them.
// None of these reads checks visibility: the pids come from a response
// already scoped to the caller, and every answer is the caller's own
// state.

// ItemMark is the caller's star, rating and play record for one item,
// and its resume position.
type ItemMark struct {
	StarredAt    time.Time // zero when not starred
	Rating       *int      // 0..100; nil when unrated
	PlayCount    int
	LastPlayedAt time.Time // zero when never played
	PositionMS   int64     // zero for a finished item, which has no resume point
}

// EntityMark is the caller's star and rating for one artist or album.
type EntityMark struct {
	StarredAt time.Time // zero when not starred
	Rating    *int      // 0..100; nil when unrated
}

// entityRatingReadCap bounds the entities one EntityMarks call reads
// ratings for: the catalog has no batch rating read, so each is a point
// read. A request naming more gets stars only, for all of them alike.
const entityRatingReadCap = 500

// ItemMarks reads the caller's marks for the items, keyed by API pid, in
// one catalog batch. Untouched items and malformed pids are absent.
func (l *Library) ItemMarks(ctx context.Context, uc *UserCtx, apiItemPIDs []string) (map[string]ItemMark, error) {
	back := make(map[model.PID]string, len(apiItemPIDs))
	pids := make([]model.PID, 0, len(apiItemPIDs))
	for _, api := range apiItemPIDs {
		prefix, pid, ok := parseAPIPID(api)
		if !ok || !itemPrefix(prefix) {
			continue
		}
		if _, dup := back[pid]; dup {
			continue
		}
		back[pid] = api
		pids = append(pids, pid)
	}
	out := make(map[string]ItemMark, len(pids))
	if len(pids) == 0 {
		return out, nil
	}
	states, err := l.lib.PlayStatesForItems(ctx, pids)
	if err != nil {
		return nil, classify(err)
	}
	user := model.PID(uc.CatalogPID)
	for pid, rows := range states {
		st := userPlayState(rows, user)
		if st == nil {
			continue
		}
		m := ItemMark{PlayCount: st.PlayCount}
		if !st.Finished {
			m.PositionMS = st.PositionMS
		}
		if st.Starred {
			m.StarredAt = markStarredAt(st.StarredAt, st.StarredChangedAt, st.UpdatedAt)
		}
		if st.HasRating {
			r := st.Rating
			m.Rating = &r
		}
		if st.LastPlayedAt > 0 {
			m.LastPlayedAt = time.Unix(0, st.LastPlayedAt).UTC()
		}
		if m == (ItemMark{}) {
			continue
		}
		out[back[pid]] = m
	}
	return out, nil
}

// markStarredAt is when a star was set: its own stamp, else the last
// change that could have set it.
func markStarredAt(stamps ...int64) time.Time {
	for _, ns := range stamps {
		if ns > 0 {
			return time.Unix(0, ns).UTC()
		}
	}
	return time.Time{}
}

// entityWant is one artist or album a marks read was asked about.
type entityWant struct {
	kind model.MergeEntity
	pid  model.PID
	api  string
}

// entityWants parses the artist and album pids out of apiEntityPIDs,
// each once; anything else is not an entity with marks and is skipped.
func entityWants(apiEntityPIDs []string) []entityWant {
	seen := make(map[model.PID]bool, len(apiEntityPIDs))
	out := make([]entityWant, 0, len(apiEntityPIDs))
	for _, api := range apiEntityPIDs {
		prefix, pid, ok := parseAPIPID(api)
		if !ok || seen[pid] {
			continue
		}
		kind, ok := mergeEntityForPrefix(prefix)
		if !ok {
			continue
		}
		seen[pid] = true
		out = append(out, entityWant{kind, pid, api})
	}
	return out
}

// starredStates reads the caller's starred artists or albums for each
// kind wants names, keyed by entity pid: one read per kind. The states
// carry the ratings too, which spares a point read for each.
func (l *Library) starredStates(ctx context.Context, uc *UserCtx, wants []entityWant) (map[model.PID]model.EntityPlayState, error) {
	kinds := map[model.MergeEntity]bool{}
	for _, w := range wants {
		kinds[w.kind] = true
	}
	out := map[model.PID]model.EntityPlayState{}
	for kind := range kinds {
		states, err := l.lib.StarredEntities(ctx, model.PID(uc.CatalogPID), kind)
		if err != nil {
			return nil, classify(err)
		}
		for _, st := range states {
			out[st.EntityPID] = st
		}
	}
	return out, nil
}

// EntityMarks reads the caller's stars and, when the request names at
// most entityRatingReadCap entities, ratings for the artists and albums
// named, keyed by API pid. Stars are one read per kind; ratings go
// through EntityRatings' memo. Entities with neither are absent, as are
// pids that name no artist or album. A rating read that fails still
// answers the stars, beside the error.
func (l *Library) EntityMarks(ctx context.Context, uc *UserCtx, apiEntityPIDs []string) (map[string]EntityMark, error) {
	wants := entityWants(apiEntityPIDs)
	out := make(map[string]EntityMark, len(wants))
	if len(wants) == 0 {
		return out, nil
	}
	starred, err := l.starredStates(ctx, uc, wants)
	if err != nil {
		return nil, err
	}
	for _, w := range wants {
		if st, ok := starred[w.pid]; ok && st.Starred {
			out[w.api] = EntityMark{StarredAt: markStarredAt(st.StarredAt, st.StarredChangedAt, st.UpdatedAt)}
		}
	}
	if len(wants) > entityRatingReadCap {
		return out, nil
	}
	ratings, err := l.ratingsFor(ctx, uc, wants, starred)
	for api, r := range ratings {
		m := out[api]
		m.Rating = &r
		out[api] = m
	}
	return out, err
}

// StarredAlbumMarks lists the caller's starred albums by API pid, in the
// catalog's starred order, each with its marks: one read, which carries
// the ratings too. No visibility check, as the header says; the caller
// shows only the ones its own scoped view holds.
func (l *Library) StarredAlbumMarks(ctx context.Context, uc *UserCtx) ([]string, map[string]EntityMark, error) {
	states, err := l.lib.StarredEntities(ctx, model.PID(uc.CatalogPID), model.MergeAlbum)
	if err != nil {
		return nil, nil, classify(err)
	}
	order := make([]string, 0, len(states))
	marks := make(map[string]EntityMark, len(states))
	for i := range states {
		st := &states[i]
		api := apiPID(PrefixAlbum, st.EntityPID)
		order = append(order, api)
		marks[api] = EntityMark{
			StarredAt: markStarredAt(st.StarredAt, st.StarredChangedAt, st.UpdatedAt),
			Rating:    stateRating(st),
		}
	}
	return order, marks, nil
}

// EntityRatings answers the caller's rating for each named artist or
// album that has one, keyed by API pid. There is no catalog read that
// lists rated entities, so a list ranked by rating reads every candidate:
// the answers are memoized per user, each until that user rates the
// entity again, an artist or album change in the catalog (a merge moves
// every user's ratings), or a replaced catalog, and a list asked for
// again costs no reads while the memo has room for it.
func (l *Library) EntityRatings(ctx context.Context, uc *UserCtx, apiEntityPIDs []string) (map[string]int, error) {
	wants := entityWants(apiEntityPIDs)
	if len(wants) == 0 {
		return map[string]int{}, nil
	}
	starred, err := l.starredStates(ctx, uc, wants)
	if err != nil {
		return nil, err
	}
	return l.ratingsFor(ctx, uc, wants, starred)
}

// ratingMemoFlush is how many point reads a ratings read makes between
// handing what it has to the memo, so a long read cut short by its
// client is not paid again in full.
const ratingMemoFlush = 200

// ratingsFor is EntityRatings over parsed wants, with the starred states
// already read. Point reads go through the memo; what they read is kept
// as they go and when one fails, so a retry continues where this left
// off. An entity the catalog no longer holds is unrated, and is read
// again next time rather than remembered.
func (l *Library) ratingsFor(ctx context.Context, uc *UserCtx, wants []entityWant, starred map[model.PID]model.EntityPlayState) (map[string]int, error) {
	out := make(map[string]int)
	// A look that could not tell may have missed a merge, so this call
	// reads the catalog itself and keeps nothing.
	epoch, watched := l.entityEpoch(ctx)
	stamp := ratingStamp{gen: l.catalogGeneration(), entities: epoch}
	memo := &l.trackFacts.ratings
	pids := make([]model.PID, len(wants))
	for i, w := range wants {
		pids[i] = w.pid
	}
	var known map[model.PID]*int
	var writes uint64
	if watched {
		known, writes = memo.lookup(uc.ID, stamp, pids)
	}
	read := map[model.PID]*int{}
	keep := func() {
		if watched && len(read) > 0 {
			memo.store(uc.ID, stamp, writes, read)
			read = map[model.PID]*int{}
		}
	}
	defer keep()
	user := model.PID(uc.CatalogPID)
	reads := 0
	for _, w := range wants {
		r, ok := known[w.pid]
		if !ok {
			if st, held := starred[w.pid]; held {
				// Read before the write number was taken, so never kept;
				// the starred read is made on every call anyway.
				r = stateRating(&st)
			} else {
				st, err := l.entityState(ctx, user, w.kind, w.pid)
				if err != nil && KindOf(classify(err)) != KindNotFound {
					return out, classify(err)
				}
				r = stateRating(st)
				if err == nil {
					read[w.pid] = r
				}
				if reads++; reads%ratingMemoFlush == 0 {
					keep()
				}
			}
		}
		if r != nil {
			out[w.api] = *r
		}
	}
	return out, nil
}

// stateRating is a state's rating, nil when unrated or there is no state.
func stateRating(st *model.EntityPlayState) *int {
	if st == nil || !st.HasRating {
		return nil
	}
	r := st.Rating
	return &r
}

// entityState reads one entity's state for the caller.
func (l *Library) entityState(ctx context.Context, user model.PID, kind model.MergeEntity, pid model.PID) (*model.EntityPlayState, error) {
	if hook := l.trackFacts.entityReadHook; hook != nil {
		return hook(ctx, user, kind, pid)
	}
	return l.lib.EntityPlayState(ctx, user, kind, pid)
}

// entityEpoch answers how many artist or album changes the catalog
// watch has seen, and false when its look could not tell.
func (l *Library) entityEpoch(ctx context.Context) (uint64, bool) {
	st, ok := l.watchLook(ctx)
	return st.entities, ok
}

// entityRatingMemo is EntityRatings' memo: each account's answer per
// entity, nil for unrated, stamped with the catalog generation and the
// entity watch's epoch it was read under. seq numbers every forget and
// writes holds each user's last; a user's fill read before that user's
// write lands nowhere, so a rating read across a write never outlives it,
// while another user's write leaves it be. floor stands in for a user
// writes no longer names, once the map was cleared at its bound.
//
// Every account's answers share one budget. A store that would pass it
// first lets go of the answers held under a stamp the catalog has left,
// then of whole accounts idle for longer than ratingMemoIdle, least
// recently used first; an account used since never gives way, and what
// still does not fit is not kept, so only the read that overflows reads
// its overflow again.
type entityRatingMemo struct {
	mu         sync.Mutex
	seq, floor uint64
	writes     map[string]uint64
	users      map[string]*userEntityRatings
	entries    int // answers held, every account's
	// budget and clock stand in for ratingMemoEntries and time.Now in
	// tests; zero values mean those.
	budget int
	clock  func() time.Time
}

// ratingStamp is the catalog state a memo entry holds for.
type ratingStamp struct {
	gen      int64
	entities uint64
}

// before reports whether the catalog has left s for o: both only grow.
func (s ratingStamp) before(o ratingStamp) bool {
	return s.gen < o.gen || (s.gen == o.gen && s.entities < o.entities)
}

type userEntityRatings struct {
	stamp   ratingStamp
	ratings map[model.PID]*int
	used    time.Time // last looked up or stored
}

// Bounds on the memo. An answer is a pid and a pointer, some 90 bytes
// held with the map's share, and refilling one costs a point read.
const (
	ratingMemoEntries = 1_000_000
	ratingMemoIdle    = 10 * time.Minute
	ratingMemoWriters = 4096
)

func (m *entityRatingMemo) limit() int {
	if m.budget > 0 {
		return m.budget
	}
	return ratingMemoEntries
}

func (m *entityRatingMemo) now() time.Time {
	if m.clock != nil {
		return m.clock()
	}
	return time.Now()
}

// writeOf is the number of a user's last rating write.
func (m *entityRatingMemo) writeOf(userID string) uint64 {
	if w, ok := m.writes[userID]; ok {
		return w
	}
	return m.floor
}

// lookup answers what the memo knows of pids, and the write count a fill
// read after it must still find to be stored.
func (m *entityRatingMemo) lookup(userID string, stamp ratingStamp, pids []model.PID) (map[model.PID]*int, uint64) {
	m.mu.Lock()
	defer m.mu.Unlock()
	u := m.users[userID]
	if u != nil && u.stamp.before(stamp) {
		// Nothing can ask for these again.
		m.release(userID, u)
		u = nil
	}
	if u == nil || u.stamp != stamp {
		return nil, m.writeOf(userID)
	}
	u.used = m.now()
	known := make(map[model.PID]*int, len(pids))
	for _, pid := range pids {
		if r, ok := u.ratings[pid]; ok {
			known[pid] = r
		}
	}
	return known, m.writeOf(userID)
}

// store keeps what a fill read, as much of it as the budget holds, unless
// the account rated something since the read looked.
func (m *entityRatingMemo) store(userID string, stamp ratingStamp, writes uint64, read map[model.PID]*int) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.writeOf(userID) != writes {
		return
	}
	u := m.users[userID]
	if u != nil && u.stamp != stamp {
		if stamp.before(u.stamp) {
			return
		}
		m.release(userID, u)
		u = nil
	}
	fresh := len(read)
	if u != nil {
		fresh = 0
		for pid := range read {
			if _, held := u.ratings[pid]; !held {
				fresh++
			}
		}
	}
	now := m.now()
	if over := m.entries + fresh - m.limit(); over > 0 {
		m.makeRoom(userID, stamp, now, over)
	}
	if u == nil {
		if m.entries >= m.limit() {
			return
		}
		if m.users == nil {
			m.users = map[string]*userEntityRatings{}
		}
		u = &userEntityRatings{stamp: stamp, ratings: make(map[model.PID]*int, len(read))}
		m.users[userID] = u
	}
	u.used = now
	for pid, r := range read {
		if _, held := u.ratings[pid]; !held {
			if m.entries >= m.limit() {
				continue
			}
			m.entries++
		}
		u.ratings[pid] = r
	}
}

// makeRoom lets go of answers for need more, where it may: those held
// under a stamp before stamp, which nothing can ask for again, then the
// accounts idle for longer than ratingMemoIdle, least recently used
// first. userID's own answers stay.
func (m *entityRatingMemo) makeRoom(userID string, stamp ratingStamp, now time.Time, need int) {
	freed := 0
	var idle []string
	for id, u := range m.users {
		switch {
		case id == userID:
		case u.stamp.before(stamp):
			freed += len(u.ratings)
			m.release(id, u)
		case now.Sub(u.used) > ratingMemoIdle:
			idle = append(idle, id)
		}
	}
	slices.SortFunc(idle, func(a, b string) int { return m.users[a].used.Compare(m.users[b].used) })
	for _, id := range idle {
		if freed >= need {
			return
		}
		freed += len(m.users[id].ratings)
		m.release(id, m.users[id])
	}
}

// release lets go of one account's answers.
func (m *entityRatingMemo) release(userID string, u *userEntityRatings) {
	m.entries -= len(u.ratings)
	delete(m.users, userID)
}

// forget drops what one user's memo holds for the entity their rating
// write changed, the only rating such a write changes, and numbers the
// write so none of that user's fills read before it is kept.
func (m *entityRatingMemo) forget(userID string, pid model.PID) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.seq++
	switch {
	case m.writes == nil:
		m.writes = map[string]uint64{}
	case len(m.writes) >= ratingMemoWriters:
		// Past every number handed out, so no fill read before now lands.
		m.writes, m.floor = map[string]uint64{}, m.seq
	}
	m.writes[userID] = m.seq
	if u := m.users[userID]; u != nil {
		if _, ok := u.ratings[pid]; ok {
			delete(u.ratings, pid)
			m.entries--
		}
	}
}
