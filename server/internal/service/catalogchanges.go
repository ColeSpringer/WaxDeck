package service

import (
	"context"
	"maps"
	"slices"
	"sync"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
)

// maxCatalogChangePIDs is the most entities one catalog invalidation
// names, the contract's bound.
const maxCatalogChangePIDs = 64

// catalogChangeReadTimeout bounds what a named invalidation may wait on
// the catalog: the drain's reads together, of the changed items and of
// the changed albums' and shows' members, on the hub's own loop, where
// every topic's frames wait behind them; the account's reads, on a
// socket's writer; and a subscribe's walk of the log after its cursor
// and its drain together, on that socket's own goroutine. Two of the
// hub's coalesce windows. Each drain read returns at most a frame's
// worth, and a wait that runs out sends a frame that names nothing
// instead.
const catalogChangeReadTimeout = 500 * time.Millisecond

// catalogChangePrefixes is the API prefix of each change-log entity type
// that has one of its own. An item's is its kind's, read at the drain; a
// genre has none and is not named.
var catalogChangePrefixes = map[string]string{
	"artist":        PrefixArtist,
	"album":         PrefixAlbum,
	"release_group": PrefixReleaseGroup,
	"series":        PrefixSeries,
	"podcast":       PrefixPodcast,
}

// catalogChanges is what the catalog wakes since the last drain stand
// for: the entities the feed saw move, bounded, and none of them once it
// cannot name them all, so that what a drain names is complete. It keeps
// apart entities it could not name, a wake no row stood behind, and
// rows that have no pid. mu is a leaf: nothing is called with it held,
// and it is never taken under feed.mu.
type catalogChanges struct {
	mu sync.Mutex
	// named holds the rows that carry their own prefix, as API pids.
	named map[string]struct{}
	// items holds item rows by bare pid, true for one whose last row
	// deleted it.
	items map[model.PID]bool
	// albums holds the album rows in named the same way, and shows the
	// shows in named whose cover moved: their members draw their cover.
	albums, shows map[model.PID]bool
	// unknown says a wake had no row behind it: the catalog may be
	// another one, and this drain names nothing.
	unknown bool
	// unnamed says an entity that has a pid moved and will not be named,
	// and this drain names nothing.
	unnamed bool
}

// record notes the entity a change row names, if the API has a pid for it.
func (c *catalogChanges) record(ch model.Change) { c.note(ch, false) }

// recordShowCover notes that a show's cover moved: its episodes are
// named beside it. No row says so; the show's is logged for much else.
func (c *catalogChanges) recordShowCover(pid model.PID) {
	c.note(model.Change{EntityType: "podcast", EntityPID: pid, Op: model.OpUpdate}, true)
}

func (c *catalogChanges) note(ch model.Change, showCover bool) {
	prefix, entity := catalogChangePrefixes[ch.EntityType]
	if ch.EntityPID == "" || (!entity && ch.EntityType != "item") {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.unknown || c.unnamed {
		c.unnamed = true
		return
	}
	if entity {
		if c.named == nil {
			c.named = make(map[string]struct{})
		}
		c.named[apiPID(prefix, ch.EntityPID)] = struct{}{}
		switch ch.EntityType {
		case "album":
			if c.albums == nil {
				c.albums = make(map[model.PID]bool)
			}
			c.albums[ch.EntityPID] = ch.Op == model.OpDelete
		case "podcast":
			// A show's row is logged for every episode a refresh adds, so
			// it names no episodes; a deleted show has none to read.
			switch {
			case ch.Op == model.OpDelete:
				delete(c.shows, ch.EntityPID)
			case showCover:
				if c.shows == nil {
					c.shows = make(map[model.PID]bool)
				}
				c.shows[ch.EntityPID] = false
			}
		}
	} else {
		if c.items == nil {
			c.items = make(map[model.PID]bool)
		}
		c.items[ch.EntityPID] = ch.Op == model.OpDelete
	}
	if len(c.named)+len(c.items) > maxCatalogChangePIDs {
		c.forget()
		c.unnamed = true
	}
}

// forget drops what was recorded. c.mu is held.
func (c *catalogChanges) forget() {
	c.named, c.items, c.albums, c.shows = nil, nil, nil, nil
}

// spent reports whether what was recorded will be unnamed.
func (c *catalogChanges) spent() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.unnamed || c.unknown
}

// markUnknown says the catalog moved in a way no row names. What was
// recorded is no longer named, and is owed as unnamed.
func (c *catalogChanges) markUnknown() {
	c.mu.Lock()
	if len(c.named)+len(c.items) > 0 {
		c.unnamed = true
	}
	c.forget()
	c.unknown = true
	c.mu.Unlock()
}

// drain takes what was recorded, as sorted API pids; unnamed says
// entities moved that it does not name, unknown that a wake had no row
// behind it, and none of the three is rows that have no pid. views reads the items still there, in
// one call and outside the lock: each gives its kind's prefix and its
// album, which draws a member's cover when it has none of its own, so a
// track's new art moves the album's. An item with no view carries the
// track prefix, as the tombstone of a deleted one does. members reads,
// in one call too, the items of the albums whose own rows are here and
// still stand and of the shows whose cover moved: a track or an episode
// with no cover of its own draws its album's or its show's. An album
// named only by a track's row, and a show named only by its own, have
// their members left out.
func (c *catalogChanges) drain(
	views func([]model.PID) ([]*model.ItemView, error),
	members func(albums, shows []model.PID) ([]*model.ItemView, error),
) (pids []string, unnamed, unknown bool) {
	c.mu.Lock()
	named, items, albums, shows := c.named, c.items, c.albums, c.shows
	unnamed, unknown = c.unnamed, c.unknown
	c.forget()
	c.unnamed, c.unknown = false, false
	c.mu.Unlock()
	if unnamed || unknown {
		return nil, unnamed, unknown
	}
	var ask []model.PID
	for pid, deleted := range items {
		if !deleted {
			ask = append(ask, pid)
		}
	}
	found := make(map[model.PID]*model.ItemView, len(ask))
	if len(ask) > 0 {
		got, err := views(ask)
		if err != nil {
			return nil, true, false
		}
		for _, v := range got {
			found[v.PID] = v
		}
	}
	if named == nil {
		named = make(map[string]struct{}, 2*len(items))
	}
	for pid := range items {
		v := found[pid]
		if v == nil {
			named[apiPID(PrefixTrack, pid)] = struct{}{}
			continue
		}
		named[itemAPIPID(v)] = struct{}{}
		if v.AlbumPID != "" {
			named[apiPID(PrefixAlbum, v.AlbumPID)] = struct{}{}
		}
	}
	if len(named) > maxCatalogChangePIDs {
		return nil, true, false
	}
	if askAlbums, askShows := standing(albums), standing(shows); len(askAlbums)+len(askShows) > 0 {
		got, err := members(askAlbums, askShows)
		if err != nil {
			return nil, true, false
		}
		for _, v := range got {
			named[itemAPIPID(v)] = struct{}{}
		}
		if len(named) > maxCatalogChangePIDs {
			return nil, true, false
		}
	}
	pids = make([]string, 0, len(named))
	for pid := range named {
		pids = append(pids, pid)
	}
	slices.Sort(pids)
	return pids, false, false
}

// standing is the recorded entities whose last row did not delete them,
// sorted.
func standing(recorded map[model.PID]bool) []model.PID {
	var out []model.PID
	for pid, deleted := range recorded {
		if !deleted {
			out = append(out, pid)
		}
	}
	slices.Sort(out)
	return out
}

// wakesCatalog reports whether a change row of the type wakes the hub:
// items feed summary mirrors, podcast rows show lists, and entity rows,
// though in no mirror, are drawn (a portrait, a cover, a name) and some
// of their writes log no item row. These are the rows a catalog
// invalidation names, those that have a pid.
func wakesCatalog(entityType string) bool {
	switch entityType {
	case "item", "podcast", "artist", "album", "release_group", "genre", "series":
		return true
	}
	return false
}

// showCoverMoved has the next catalog invalidation name a show's episodes
// beside it. Called once the cover is written: named any sooner, a
// client would ask again for the cover it already holds. Stamped after
// the write, so after the row it logged: a cursor before that row is
// told of the move whichever row the walk meets. Stamped after it is
// recorded, so a position that covers the stamp has its drain, or an
// earlier one, name it.
func (l *Library) showCoverMoved(pid model.PID) {
	l.feed.changes.recordShowCover(pid)
	l.feed.showCovers.note(pid, time.Now().UnixNano())
	l.wakeCatalog()
}

// showCoverLog remembers the newest shows whose cover moved through the
// API, and when: a show's row is logged for every refresh too, so a walk
// of the log cannot tell a cover from the rest. It keeps one more than a
// frame names, since more moved after a cursor than that is unnamed
// anyway. A position a frame hands out carries the newest stamp it
// covers, since the stamp falls after the row the move's write logged
// and a cursor at that row could otherwise not tell a client that was
// told of the move from one that was not.
type showCoverLog struct {
	mu sync.Mutex
	// from is the time before which it knows nothing: its start, or the
	// newest move it let go.
	from  int64
	moves []showCoverMove
	// newest is the newest stamp noted since its start.
	newest int64
}

type showCoverMove struct {
	pid model.PID
	at  int64
}

// start forgets every move: it knows nothing from before now.
func (s *showCoverLog) start(now int64) {
	s.mu.Lock()
	s.from, s.moves, s.newest = now, nil, 0
	s.mu.Unlock()
}

func (s *showCoverLog) note(pid model.PID, at int64) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.newest = max(s.newest, at)
	s.moves = append(s.moves, showCoverMove{pid, at})
	if len(s.moves) > maxCatalogChangePIDs+1 {
		s.from = max(s.from, s.moves[0].at)
		s.moves = slices.Delete(s.moves, 0, 1)
	}
}

// stamp is the newest move noted, zero for none: every move up to it has
// been recorded for a drain.
func (s *showCoverLog) stamp() int64 {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.newest
}

// after names the shows whose cover moved after the change-log time ts
// and after cover, the newest move a cursor covers, and whether it knows
// them all: it does from a time no earlier than what it knows from, and
// never for a ts of zero, which stands on no row. A move stamped after
// ts whose row was not is named too. newest is the newest move noted:
// those named and those the cursor covers are every one up to it.
func (s *showCoverLog) after(ts, cover int64) (moved map[model.PID]bool, newest int64, known bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	from := max(ts, cover)
	moved = make(map[model.PID]bool)
	for _, m := range s.moves {
		if m.at > from {
			moved[m.pid] = true
		}
	}
	return moved, s.newest, ts != 0 && s.from != 0 && from >= s.from
}

// wakeCatalog hints the hub that the catalog moved. Lossy: a hint already
// waiting covers this one.
func (l *Library) wakeCatalog() {
	select {
	case l.catalogWake <- struct{}{}:
	default:
	}
}

// DrainCatalogChanges takes the API pids of the entities behind the
// catalog wakes since it was last asked, for the invalidation that
// answers them to name. unnamed says entities moved that it does not
// name: more than a frame holds, a wake with no row behind it landed
// beside their rows, or a read, for the items' albums or for the members
// of the albums and shows, failed, timed out or was cut short by a
// shutdown. unknown says a wake had no row behind it (a new catalog
// generation, a replaced catalog), so the catalog may be another one.
// None of the three is a wake for rows that have no pid.
func (l *Library) DrainCatalogChanges() (pids []string, unnamed, unknown bool) {
	return l.drainCatalogChanges(l.lib.GetMany, l.changedMembers)
}

// drainCatalogChanges is DrainCatalogChanges over the two reads it is
// handed.
func (l *Library) drainCatalogChanges(
	views func(context.Context, []model.PID) ([]*model.ItemView, error),
	members func(ctx context.Context, albums, shows []model.PID) ([]*model.ItemView, error),
) (pids []string, unnamed, unknown bool) {
	// One bound for both reads: the hub's loop waits on the drain.
	ctx, cancel := context.WithTimeout(l.procCtx, catalogChangeReadTimeout)
	defer cancel()
	return l.drainWithin(ctx, &l.feed.changes, views, members)
}

// drainWithin drains c with both reads under ctx.
func (l *Library) drainWithin(
	ctx context.Context,
	c *catalogChanges,
	views func(context.Context, []model.PID) ([]*model.ItemView, error),
	members func(ctx context.Context, albums, shows []model.PID) ([]*model.ItemView, error),
) (pids []string, unnamed, unknown bool) {
	failed := func(what string, err error) {
		if err != nil && l.procCtx.Err() == nil && !l.Maintenance() {
			l.log.Warn("reading "+what+" for a catalog invalidation", "err", err)
		}
	}
	return c.drain(func(items []model.PID) ([]*model.ItemView, error) {
		got, err := views(ctx, items)
		failed("the changed items", err)
		return got, err
	}, func(albums, shows []model.PID) ([]*model.ItemView, error) {
		got, err := members(ctx, albums, shows)
		failed("the changed albums' and shows' members", err)
		return got, err
	})
}

// changedMembers reads the items of the albums and shows, those in the
// trash left out. A frame's worth is enough: that many beside a parent
// is past the bound, so the limit may not be lower.
func (l *Library) changedMembers(ctx context.Context, albums, shows []model.PID) ([]*model.ItemView, error) {
	var of []query.Node
	if len(albums) > 0 {
		of = append(of, inSet("album_pid", pidStrings(albums)))
	}
	if len(shows) > 0 {
		of = append(of, inSet("podcast_pid", pidStrings(shows)))
	}
	return l.lib.Query(ctx, visibleItems().WhereNode(query.Or{Nodes: of}).
		Limit(maxCatalogChangePIDs).Build(), "")
}

func pidStrings(pids []model.PID) []string {
	out := make([]string, len(pids))
	for i, pid := range pids {
		out[i] = string(pid)
	}
	return out
}

// CatalogPosition is where the catalog stream stands for the drain that
// follows: the feed records a row before its position moves past it, so
// every change up to it is in that drain or an earlier one. order sorts
// positions across generations, as CatalogTailSeq does; cover is the
// newest show cover move it covers; pos is a cursor at it under no
// account's epoch yet, carrying both.
func (l *Library) CatalogPosition() (order, cover int64, pos string) {
	cover = l.feed.showCovers.stamp()
	l.feed.mu.Lock()
	defer l.feed.mu.Unlock()
	return l.feed.mints<<40 | l.feed.tail, cover, encodeCatalogPosition(l.feed.gen, 0, l.feed.tail, l.feed.tailTS, cover)
}

// CatalogFrameFor reads the account as a catalog invalidation is built:
// the cursor at pos under its grant epoch, "" when pos is none or the
// epoch could not be read, and, for a frame with names, those of pids the
// account may be told; unnamed says it could not decide them all. The
// epoch is read before the rules, so a change to them in between retires
// the cursor. An account that cannot sign in, and a read that failed or
// that a shutdown cut short, decide none.
func (l *Library) CatalogFrameFor(userID, pos string, pids []string) (since string, named []string, unnamed bool) {
	ctx, cancel := context.WithTimeout(l.procCtx, catalogChangeReadTimeout)
	defer cancel()
	if at, ok := decodeCatalogCursor(pos); ok {
		if epoch, err := l.Grants.grantEpoch(ctx, userID); err == nil {
			since = encodeCatalogPosition(at.gen, epoch, at.seq, at.ts, at.cover)
		}
	}
	if len(pids) == 0 {
		return since, nil, false
	}
	uc, err := l.Grants.UserCtxByID(ctx, userID)
	if err != nil {
		return since, nil, true
	}
	named, ok := l.Grants.catalogNamesFor(ctx, uc, pids, l.lib.GetMany)
	return since, named, !ok
}

// catalogNamesFor is what of a catalog invalidation's names uc may be
// told, in their order; ok is false when it could not decide them all.
// An account that sees everything is told every name for no read; any
// other costs one read of the named items, and a tag read for each it
// sees where it has a tag rule. An item is told where the account sees
// it. An album or release group is told where an item at hand that the
// account is offered belongs to it, and not where items at hand belong
// to it and none is offered; an artist only where one offered is by it,
// since credits are on no view. A show is told as the podcast library's
// visibility says and, for an account without explicit content, its
// flag on an episode of it at hand. Anything else, and a read that fell
// back, is undecided.
func (l *Grants) catalogNamesFor(ctx context.Context, uc *UserCtx, pids []string,
	views func(context.Context, []model.PID) ([]*model.ItemView, error)) (named []string, ok bool) {
	if seesEverything(uc) {
		return pids, true
	}
	var items []model.PID
	for _, pid := range pids {
		if prefix, bare, ok := parseAPIPID(pid); ok && itemPrefix(prefix) {
			items = append(items, bare)
		}
	}
	ctx, fell := WatchDegraded(ctx)
	var got []*model.ItemView
	if len(items) > 0 {
		var err error
		if got, err = views(ctx, items); err != nil {
			return nil, false
		}
	}
	// seen holds the items the account sees; held the entities an item at
	// hand belongs to, true where one it is offered does; plain the shows
	// an episode at hand says are not explicit as a whole.
	seen := make(map[model.PID]bool, len(got))
	held, plain := map[string]bool{}, map[string]bool{}
	for _, v := range got {
		sees := l.viewVisible(ctx, uc, v) && l.allowedByContent(ctx, uc, v)
		seen[v.PID] = sees
		for _, e := range []string{
			entityAPIPID(PrefixAlbum, v.AlbumPID), entityAPIPID(PrefixReleaseGroup, v.ReleaseGroupPID),
			entityAPIPID(PrefixArtist, v.ArtistPID), entityAPIPID(PrefixArtist, v.AlbumArtistPID),
		} {
			if e != "" {
				held[e] = held[e] || (sees && !archived(v))
			}
		}
		if v.PodcastPID != "" {
			plain[apiPID(PrefixPodcast, v.PodcastPID)] = !v.PodcastExplicit
		}
	}
	for _, pid := range pids {
		prefix, bare, ok := parseAPIPID(pid)
		if !ok {
			return nil, false
		}
		offered, at := held[pid]
		var tell bool
		switch {
		case itemPrefix(prefix):
			tell = seen[bare]
		case prefix == PrefixAlbum || prefix == PrefixReleaseGroup:
			if !at {
				return nil, false
			}
			tell = offered
		case prefix == PrefixArtist:
			if !offered {
				return nil, false
			}
			tell = true
		case prefix == PrefixPodcast:
			if !l.podcastsVisible(ctx, uc) {
				break
			}
			clean, at := plain[pid]
			if !uc.Explicit && !at {
				return nil, false
			}
			tell = uc.Explicit || clean
		default:
			return nil, false
		}
		if tell {
			named = append(named, pid)
		}
	}
	if fell() {
		return nil, false
	}
	return named, true
}

// CatalogChangesSince answers a subscribe that presented a catalog
// cursor: what changed after it, named as a drain names it, for the frame
// to tell the account what of it it may be told, and the position the
// answer covers up to. It is unnamed, covering up to where the stream
// stands, for more entities than a frame names, for a read that failed
// or ran out of the one bound every read here shares, and for a cursor
// the stream cannot serve, one a pull answers sync-reset or refuses. A
// cursor nothing with a pid moved after is answered with no names.
// unchanged says no row after a cursor it serves wakes the catalog: only
// rows that leave it as it was, a user's own state among them, followed.
func (l *Library) CatalogChangesSince(userID, cursor string) (pids []string, unnamed, unchanged bool, order, cover int64, pos string) {
	return l.catalogChangesSince(userID, cursor, l.lib.Changes, l.lib.GetMany, l.changedMembers)
}

// catalogChangesSince is CatalogChangesSince over the reads it is
// handed. It stops at the first row that settles the answer as unnamed,
// and holds no lock the feed takes while it reads.
func (l *Library) catalogChangesSince(
	userID, cursor string,
	changes func(context.Context, int64) ([]model.Change, error),
	views func(context.Context, []model.PID) ([]*model.ItemView, error),
	members func(ctx context.Context, albums, shows []model.PID) ([]*model.ItemView, error),
) (pids []string, unnamed, unchanged bool, order, cover int64, pos string) {
	// An unnamed answer says anything may have changed, so it covers up
	// to where the stream stands.
	order, cover, pos = l.CatalogPosition()
	ctx, cancel := context.WithTimeout(l.procCtx, catalogChangeReadTimeout)
	defer cancel()
	c, ok := decodeCatalogCursor(cursor)
	if !ok || !c.stamped {
		return nil, true, false, order, cover, pos
	}
	epoch, err := l.Grants.grantEpoch(ctx, userID)
	if err != nil {
		return nil, true, false, order, cover, pos
	}
	l.feed.mu.Lock()
	gen, floor, mints := l.feed.gen, l.feed.floor, l.feed.mints
	l.feed.mu.Unlock()
	if c.gen != gen || c.epoch != epoch || c.seq < floor {
		return nil, true, false, order, cover, pos
	}
	// A show's row names its episodes where its cover moved, and where
	// that cannot be told.
	covers, _, known := l.feed.showCovers.after(c.ts, c.cover)

	// The rows after the cursor's, checked as the delta checks them: the
	// row it stands on must still be the row it stood on.
	var found catalogChanges
	woke := false
	seq, ts := c.seq, c.ts
	standing := c.ts != 0 && c.seq > floor
	if standing {
		seq--
	}
	for {
		if ctx.Err() != nil {
			return nil, true, false, order, cover, pos
		}
		rows, err := changes(ctx, seq)
		if err != nil {
			return nil, true, false, order, cover, pos
		}
		if standing {
			standing = false
			if len(rows) == 0 || rows[0].Seq != c.seq || rows[0].TS != c.ts {
				return nil, true, false, order, cover, pos
			}
			// A read may end at that row with more behind it.
			if seq, rows = c.seq, rows[1:]; len(rows) == 0 {
				continue
			}
		}
		if len(rows) == 0 {
			break
		}
		for _, ch := range rows {
			if ch.EntityType == model.ChangeCatalog {
				return nil, true, false, order, cover, pos
			}
			if wakesCatalog(ch.EntityType) {
				woke = true
				found.note(ch, ch.EntityType == "podcast" && (!known || covers[ch.EntityPID]))
				if found.spent() {
					return nil, true, false, order, cover, pos
				}
			}
			seq, ts = ch.Seq, ch.TS
		}
	}
	// A cover stamped after the cursor whose row is not after it: the
	// walk never met that row. Asked again, since one moved during the
	// walk may have met its row as a plain one and gone on past its
	// stamp; one moved after this has a stamp after every row walked.
	later, coverStamp, stillKnown := l.feed.showCovers.after(c.ts, c.cover)
	if known && !stillKnown {
		return nil, true, false, order, cover, pos
	}
	maps.Copy(covers, later)
	for pid := range covers {
		woke = true
		found.recordShowCover(pid)
	}
	if found.spent() {
		return nil, true, false, order, cover, pos
	}
	if pids, unnamed, _ = l.drainWithin(ctx, &found, views, members); unnamed {
		return nil, true, false, order, cover, pos
	}
	cover = max(c.cover, coverStamp)
	return pids, false, !woke, mints<<40 | seq, cover, encodeCatalogPosition(gen, 0, seq, ts, cover)
}
