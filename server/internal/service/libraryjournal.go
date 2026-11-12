package service

import (
	"context"
	"errors"
	"math"
	"slices"
	"sync"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/read"
	"github.com/colespringer/waxbin/waxerr"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// The library journal follows the catalog's change log and records which
// library each item sat in, which a change row does not say: it names an
// entity, an op and a position. The catalog delta reads it to tell an
// item a restricted caller may hold from one only ever in libraries
// outside its grants. The library is read from the item when the journal
// reaches a change to it, so an item is placed where it sits at each
// read; a library it passed through between two reads is not recorded.

// Journal markers beside library pids. An episode sits in the podcast
// library fetched or not (viewVisible's rule), so it is recorded under
// that library whatever its file says; an item with no file and nothing
// in the trash sits in no library; and an item the journal cannot place
// (a trash row naming no library the server can place) is marked not
// known, and sent.
const (
	journalPodcast = "podcast"
	journalNowhere = "-"
	journalUnsure  = "?"
)

// libraryJournal is where the journal stands, behind its own lock: its
// follower, the delta and the snapshot all bring it up, and the follower
// alone starts it over.
type libraryJournal struct {
	mu sync.Mutex
	// through is the change read up to, and throughTS that change's time;
	// start is the log's head once the journal last finished starting
	// over, before which a cursor is reset: the walk reads an item where
	// it sits, so a change landing during it is folded into the walk's
	// placements; generation is the catalog generation it was built
	// under. stale starts it over before it reads on.
	through, throughTS int64
	start, generation  int64
	stale              bool
	// lastErr is how the follower's last read ended, nil for well: a
	// reader finding the journal stale fails on it rather than wait out
	// the follower's backoff. turned is closed, and made anew, when a
	// follower's read ends, for a reader waiting on one.
	lastErr error
	turned  chan struct{}
}

// waiter is what a reader waits on for the follower's next read to end.
func (j *libraryJournal) waiter() <-chan struct{} {
	if j.turned == nil {
		j.turned = make(chan struct{})
	}
	return j.turned
}

// turn tells the readers waiting on the follower that its read ended.
func (j *libraryJournal) turn() {
	if j.turned != nil {
		close(j.turned)
	}
	j.turned = make(chan struct{})
}

// journalToHead asks journalLibraries for the change log's head.
const journalToHead = math.MaxInt64

// errJournalMoved is a change log that moved under the journal twice in
// one read; the next read starts over again.
var errJournalMoved = errors.New("service: the change log moved under the library journal")

// openLibraryJournal loads where the journal stands at startup: a catalog
// generation that carried over keeps it, pruned to the log's floor, and
// anything else, a walk cut short included, starts it over at its first
// read.
func (l *Library) openLibraryJournal(ctx context.Context, continuous bool, floor int64) error {
	j := &l.libJournal
	j.mu.Lock()
	defer j.mu.Unlock()
	j.stale = true
	if !continuous {
		return nil
	}
	state, ok, err := l.db.LibraryJournalStateFor(ctx)
	if err != nil || !ok || state.Generation != l.catalogGeneration() {
		return err
	}
	if _, err := l.db.PruneItemLibraries(ctx, floor); err != nil {
		return err
	}
	j.through, j.throughTS, j.start, j.generation = state.Through, state.ThroughTS, state.Start, state.Generation
	j.stale = false
	return nil
}

// runLibraryJournal keeps the journal up with the change log, woken by
// the feed when an item changes and on a slow tick, and alone starts it
// over when it is stale. A read that fails is tried again after a
// backoff, nudges ignored, so a walk that keeps failing runs at that
// pace whatever the clients retrying on it do.
func (l *Library) runLibraryJournal(ctx context.Context) error {
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()
	var backoff time.Duration
	for {
		_, err := l.journalCatchUp(ctx)
		if err != nil && ctx.Err() == nil && !l.Maintenance() {
			l.log.Warn("library journal: reading the change log", "err", err)
		}
		if err != nil {
			backoff = min(max(2*backoff, time.Second), 30*time.Second)
			select {
			case <-ctx.Done():
				return nil
			case <-time.After(backoff):
			}
			continue
		}
		backoff = 0
		select {
		case <-ctx.Done():
			return nil
		case <-l.journalWake:
		case <-ticker.C:
		}
	}
}

// wakeLibraryJournal nudges the journal's follower; lossy, as a nudge
// already waiting covers this one.
func (l *Library) wakeLibraryJournal() {
	select {
	case l.journalWake <- struct{}{}:
	default:
	}
}

// journalPlace is where the journal stands for a caller handing out a
// cursor: the change it has read up to with that change's time, and the
// change it last started over at.
type journalPlace struct {
	through, throughTS, start int64
}

// journalLibraries reads the change log on from where the journal stands
// to upto, or to the head for journalToHead, and answers where it stands
// then. The lock is taken a batch at a time, so a delta waiting on the
// follower through a long scan waits one batch, not the scan. A stale
// journal is the follower's to start over: the read waits for its walk,
// or fails as the follower's last read did, so a walk that cannot go
// through runs at the follower's pace, not once per client retry.
func (l *Library) journalLibraries(ctx context.Context, upto int64) (journalPlace, error) {
	return l.journalRead(ctx, upto, false)
}

// journalCatchUp is the follower's read: on to the log's head, starting
// the journal over first when it is stale, and how it ended published for
// the readers waiting on it.
func (l *Library) journalCatchUp(ctx context.Context) (journalPlace, error) {
	place, err := l.journalRead(ctx, journalToHead, true)
	j := &l.libJournal
	j.mu.Lock()
	j.lastErr = err
	j.turn()
	j.mu.Unlock()
	return place, err
}

// journalRead takes the journal batch by batch to upto; a reader that is
// not the follower waits for the follower where a walk is due.
func (l *Library) journalRead(ctx context.Context, upto int64, follower bool) (journalPlace, error) {
	restarted := false
	for {
		place, wait, done, err := l.journalBatch(ctx, upto, follower, &restarted)
		if done || err != nil {
			return place, err
		}
		if wait != nil {
			l.wakeLibraryJournal()
			select {
			case <-wait:
			case <-ctx.Done():
				return place, &Error{Kind: KindInternal, Err: ctx.Err()}
			}
		}
	}
}

// journalBatch takes the journal one step toward upto: a start over when
// it is stale or the catalog's generation moved under it (the follower's
// alone, once per read; another reader is handed the follower's last
// failure, or what to wait on), or one batch of change rows.
func (l *Library) journalBatch(ctx context.Context, upto int64, follower bool, restarted *bool) (place journalPlace, wait <-chan struct{}, done bool, err error) {
	j := &l.libJournal
	j.mu.Lock()
	defer j.mu.Unlock()
	// A restore that lands at exactly the journal's place gives its read
	// nothing to see; the generation it moved is what tells.
	if j.generation != l.catalogGeneration() {
		j.stale = true
	}
	at := func() journalPlace { return journalPlace{j.through, j.throughTS, j.start} }
	if j.stale {
		switch {
		case !follower && j.lastErr != nil:
			return at(), nil, true, j.lastErr
		case !follower:
			return at(), j.waiter(), false, nil
		case *restarted:
			return at(), nil, true, errJournalMoved
		}
		*restarted = true
		err := l.restartLibraryJournal(ctx)
		return at(), nil, err != nil, err
	}
	if j.through >= upto {
		return at(), nil, true, nil
	}
	rows, err := l.lib.Changes(ctx, j.through)
	if waxerr.CodeOf(err) == waxerr.CodeNotFound {
		// Behind a prune, or past the head of a catalog put in place of the
		// one it read: what it holds no longer lines up with the log.
		j.stale = true
		return at(), nil, false, nil
	}
	if err != nil {
		return at(), nil, true, classify(err)
	}
	if len(rows) == 0 {
		return at(), nil, true, nil
	}
	err = l.journalRows(ctx, rows)
	return at(), nil, err != nil, err
}

// restartLibraryJournal starts the journal over from the catalog as it
// stands, every item placed at the log's head, which is read first so a
// change landing during the walk is read again after it: a present item
// in its library, an item in the trash in the libraries its trash rows
// name (no library when it has none). The journal starts at the head read
// once the walk is done: a change landing during it may have been read
// into the walk's placements (an item moved out of a library the walk
// then found elsewhere), so a cursor from before it is reset. Where it
// stands is stored only once the walk is done, so a walk cut short starts
// over at the next boot.
func (l *Library) restartLibraryJournal(ctx context.Context) error {
	gen := l.catalogGeneration()
	head, err := l.lib.LatestChangeSeq(ctx)
	if err != nil {
		return classify(err)
	}
	headTS := l.tsOf(ctx, head)
	if err := l.db.ResetItemLibraries(ctx); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	for _, trash := range []bool{false, true} {
		q := visibleItems().Build()
		if trash {
			q = trashedItems().Build()
		}
		cursor := read.Cursor("")
		for {
			if l.journalWalkHook != nil {
				if err := l.journalWalkHook(); err != nil {
					return err
				}
			}
			page, err := l.lib.QueryPage(ctx, q, cursor, 1000, false, "")
			if err != nil {
				return classify(err)
			}
			rows, err := l.placeWalked(ctx, page.Items, head)
			if err != nil {
				return err
			}
			if err := l.db.RecordItemLibraries(ctx, rows, nil); err != nil {
				return &Error{Kind: KindInternal, Err: err}
			}
			if !page.HasMore {
				break
			}
			cursor = page.Next
		}
	}
	start, err := l.lib.LatestChangeSeq(ctx)
	if err != nil {
		return classify(err)
	}
	state := wdb.LibraryJournalState{Through: head, ThroughTS: headTS, Start: start, Generation: gen}
	if err := l.db.RecordItemLibraries(ctx, nil, &state); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	j := &l.libJournal
	j.through, j.throughTS, j.start, j.generation, j.stale = head, headTS, start, gen, false
	return nil
}

// placeWalked answers the journal rows placing one page of the walk's
// items at seq: an item in the trash from its trash rows, read for the
// page at once.
func (l *Library) placeWalked(ctx context.Context, items []*model.ItemView, seq int64) ([]wdb.ItemLibrary, error) {
	var trashed []model.PID
	for _, it := range items {
		if archived(it) && it.Kind != model.KindEpisode {
			trashed = append(trashed, it.PID)
		}
	}
	var rows map[model.PID][]model.TrashEntry
	if len(trashed) > 0 {
		var err error
		if rows, err = l.lib.RestorableTrash(ctx, trashed); err != nil {
			return nil, classify(err)
		}
	}
	out := make([]wdb.ItemLibrary, 0, len(items))
	for _, it := range items {
		place := func(lib string) {
			out = append(out, wdb.ItemLibrary{ItemPID: string(it.PID), Seq: seq, LibraryPID: lib})
		}
		switch lib := journalPlaceOf(it); {
		case lib != "":
			place(lib)
		case !archived(it) || len(rows[it.PID]) == 0:
			place(journalNowhere)
		default:
			for _, row := range rows[it.PID] {
				lib := string(row.LibraryPID)
				if lib == "" {
					if found, err := l.Grants.libraryForPath(ctx, row.OrigDisplay); err == nil {
						lib = found
					}
				}
				if lib == "" {
					lib = journalUnsure
				}
				place(lib)
			}
		}
	}
	return out, nil
}

// journalPlaceOf is where the journal places an item from its view: an
// episode in the podcast library, anything else in its primary file's
// library, empty for a fileless item, whose place the journal keeps.
func journalPlaceOf(it *model.ItemView) string {
	if it.Kind == model.KindEpisode {
		return journalPodcast
	}
	return string(it.LibraryPID)
}

// journalRows records what one batch of change rows moved: each changed
// item placed, at the first of its rows the batch holds, in the library
// it sits in now, where that is not where the journal has it (a file
// re-homed between libraries writes several rows in one scan, and is one
// placement); an episode always in the podcast library; the drop of an
// item whose row the catalog deleted. A replaced catalog's row starts the
// journal over instead.
func (l *Library) journalRows(ctx context.Context, rows []model.Change) error {
	first := map[model.PID]int64{}
	dropped := map[model.PID]int64{}
	var pids []model.PID
	j := &l.libJournal
	through, throughTS := j.through, j.throughTS
	for _, ch := range rows {
		if ch.EntityType == model.ChangeCatalog {
			j.stale = true
			return nil
		}
		through, throughTS = ch.Seq, ch.TS
		if ch.EntityType != "item" {
			continue
		}
		if _, seen := first[ch.EntityPID]; !seen {
			first[ch.EntityPID] = ch.Seq
			pids = append(pids, ch.EntityPID)
		}
		if ch.Op == model.OpDelete {
			dropped[ch.EntityPID] = ch.Seq
		}
	}
	var moves []wdb.ItemLibrary
	if len(pids) > 0 {
		views, err := l.lib.GetMany(ctx, pids)
		if err != nil {
			return classify(err)
		}
		byPID := make(map[model.PID]*model.ItemView, len(views))
		for _, v := range views {
			byPID[v.PID] = v
		}
		keys := make([]string, len(pids))
		for i, pid := range pids {
			keys[i] = string(pid)
		}
		latest, err := l.db.LatestItemLibraries(ctx, keys)
		if err != nil {
			return &Error{Kind: KindInternal, Err: err}
		}
		for _, pid := range pids {
			if row, ok := journalMove(pid, byPID[pid], latest[string(pid)], first[pid], dropped); ok {
				moves = append(moves, row)
			}
		}
	}
	if err := l.db.RecordItemLibraries(ctx, moves, &wdb.LibraryJournalState{
		Through: through, ThroughTS: throughTS, Start: j.start, Generation: j.generation,
	}); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	j.through, j.throughTS = through, throughTS
	return nil
}

// journalMove is the row one item's changes in a batch record, if any,
// against the libraries the journal has it in now (latest). See
// journalRows.
func journalMove(pid model.PID, v *model.ItemView, latest []string, first int64, dropped map[model.PID]int64) (wdb.ItemLibrary, bool) {
	is := func(lib string) bool { return len(latest) == 1 && latest[0] == lib }
	if v == nil {
		// Gone: the drop where this batch holds the change deleting it,
		// and nothing where it does not, which that change's batch does.
		seq, ok := dropped[pid]
		if !ok || len(latest) == 0 || is("") {
			return wdb.ItemLibrary{}, false
		}
		return wdb.ItemLibrary{ItemPID: string(pid), Seq: seq}, true
	}
	lib := journalPlaceOf(v)
	if lib == "" && len(latest) == 0 {
		// Never placed and fileless now: in the trash, it was placed by
		// nothing the journal saw; otherwise it sits in no library.
		lib = journalNowhere
		if archived(v) {
			lib = journalUnsure
		}
	}
	if lib == "" || is(lib) {
		// A fileless item keeps the library it left.
		return wdb.ItemLibrary{}, false
	}
	return wdb.ItemLibrary{ItemPID: string(pid), Seq: first, LibraryPID: lib}, true
}

// viewLibrary is where the journal would place an item from its view, for
// a request deciding a tombstone: the podcast library for an episode,
// fetched or not.
func viewLibrary(it *model.ItemView) string {
	return journalPlaceOf(it)
}

// deltaReach decides, for one delta page of a caller who does not see
// every library, whether a tombstone may go to it: whether the caller's
// grants covered a library the item sat in at the page's cursor or since,
// or the journal cannot say. Where the journal cannot say, the tombstone
// goes.
type deltaReach struct {
	uc *UserCtx
	// podcasts says the caller sees the podcast library; history is what
	// the journal says of the page's items.
	podcasts bool
	history  map[string]wdb.ItemLibraries
}

// mayHold reports whether the caller may hold the item: its grants covered
// a library the journal places it in at the cursor, one it moved to
// since, or one of libs, or the journal could not place it. created says
// the page saw the item made, so it sat nowhere at the cursor.
func (r *deltaReach) mayHold(pid model.PID, created bool, libs ...string) bool {
	if r == nil {
		return true
	}
	h := r.history[string(pid)]
	if !h.Placed && !created {
		return true
	}
	held := func(lib string) bool {
		switch lib {
		case journalUnsure:
			return true
		case journalPodcast:
			return r.podcasts
		case "", journalNowhere:
			return false
		}
		return r.uc.Libraries[lib]
	}
	return slices.ContainsFunc(h.AtCursor, held) || slices.ContainsFunc(libs, held) || slices.ContainsFunc(h.Since, held)
}
