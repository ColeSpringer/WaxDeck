package service

import (
	"context"
	"encoding/base64"
	"fmt"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
	"github.com/colespringer/waxbin/read"
	"github.com/oklog/ulid/v2"
)

// The sync surface: snapshot and changed-since mirroring of the catalog
// (WaxBin's change feed, item-granular) and of per-user server state
// (the event_log stream). Cursors handed to clients are opaque and bind
// a stream generation, so a rebuilt catalog or restored database
// invalidates stale cursors instead of silently serving diverged
// history; catalog cursors additionally bind the user's grant epoch, so
// a visibility change forces a clean re-mirror.

// CatalogSyncEntry is one mirror instruction. Item is set for upserts.
type CatalogSyncEntry struct {
	Op   string
	PID  string
	Item *ItemSummary
}

// CatalogDelta is one page of catalog changes.
type CatalogDelta struct {
	Entries   []CatalogSyncEntry
	NextSince string
	More      bool
}

// CatalogSnapshotPage is one keyset page of the full-mirror snapshot.
type CatalogSnapshotPage struct {
	Entries    []CatalogSyncEntry
	NextCursor string
	NextSince  string
}

// ServerSyncEvent is one user-scoped state change, hydrated fresh.
type ServerSyncEvent struct {
	Kind      string
	PID       string
	PlayState *PlayState
	Prefs     *Prefs
}

// ServerDelta is one page of the caller's server-state changes.
type ServerDelta struct {
	Events    []ServerSyncEvent
	NextSince string
	More      bool
}

// Server event kinds on the event_log stream.
const (
	eventPlayState = "play-state"
	eventPrefs     = "prefs"
)

// ErrSyncReset marks a cursor the stream can no longer serve
// contiguously; the API layer maps it to 410 sync-reset.
var ErrSyncReset = &Error{Kind: KindGone, Msg: "sync cursor is no longer serviceable; re-mirror from a fresh snapshot"}

// syncFeed is the catalog stream's identity and position, guarded by
// its own mutex (request goroutines read it, the feed consumer writes
// it).
type syncFeed struct {
	mu    sync.Mutex
	gen   string
	floor int64
	tail  int64
	// tailTS is the change timestamp at tail; persisted beside it so the
	// next boot can confirm continuity (seqs alone cannot: AUTOINCREMENT
	// has gaps and a rebuilt catalog reuses low seqs).
	tailTS      int64
	lastPersist time.Time
}

// Sync-state keys in waxdeck.db.
const (
	syncKeyCatalogGen    = "catalog_gen"
	syncKeyCatalogCursor = "catalog_cursor"
	syncKeyServerGen     = "server_gen"
	syncKeyGrantEpoch    = "grant_epoch:" // + user id
)

// initSync loads or establishes the stream identities. The catalog
// generation survives only when the persisted (seq, ts) pair still
// matches a retained change row: anything else (fresh install, rebuilt
// catalog, pruned-past-cursor history) mints a new generation, which
// retires every outstanding client cursor at its next use.
func (l *Library) initSync(ctx context.Context) error {
	sg, err := l.db.SyncStateGet(ctx, syncKeyServerGen)
	if err != nil {
		return err
	}
	if sg == "" {
		sg = ulid.Make().String()
		if err := l.db.SyncStateSet(ctx, syncKeyServerGen, sg); err != nil {
			return err
		}
	}
	l.serverGen = sg

	gen, err := l.db.SyncStateGet(ctx, syncKeyCatalogGen)
	if err != nil {
		return err
	}
	cur, err := l.db.SyncStateGet(ctx, syncKeyCatalogCursor)
	if err != nil {
		return err
	}
	seq, ts := parseFeedCursor(cur)

	first, err := l.lib.Changes(ctx, 0)
	if err != nil {
		return classify(err)
	}
	var minSurviving int64
	if len(first) > 0 {
		minSurviving = first[0].Seq
	}

	continuous := false
	if gen != "" && seq > 0 {
		probe, err := l.lib.Changes(ctx, seq-1)
		if err != nil {
			return classify(err)
		}
		continuous = len(probe) > 0 && probe[0].Seq == seq && probe[0].TS == ts
	}
	if !continuous {
		gen = ulid.Make().String()
		if err := l.db.SyncStateSet(ctx, syncKeyCatalogGen, gen); err != nil {
			return err
		}
		seq, ts = 0, 0
		if minSurviving > 0 {
			seq = minSurviving - 1
		}
	}
	l.feed.mu.Lock()
	l.feed.gen = gen
	l.feed.tail = seq
	l.feed.tailTS = ts
	if minSurviving > 0 {
		l.feed.floor = minSurviving - 1
	}
	l.feed.mu.Unlock()
	return nil
}

// runCatalogFeed is the change-feed consumer: it subscribes before
// priming (the documented order, so nothing lands in the gap), drains
// to the tail, then follows live changes, waking the event hub on
// item-granular ones and persisting its position coarsely.
func (l *Library) runCatalogFeed(ctx context.Context) error {
	sub, cancel := l.lib.Subscribe()
	defer cancel()
	if err := l.drainCatalog(ctx); err != nil {
		return err
	}
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			l.persistFeedCursor(context.WithoutCancel(ctx), true)
			return nil
		case ch, ok := <-sub:
			if !ok {
				return nil
			}
			l.advanceFeed(ch)
		case <-ticker.C:
			l.persistFeedCursor(ctx, false)
		}
	}
}

// drainCatalog pulls the change log from the feed's position to the
// tail. The subscription buffer is lossy under backpressure, so the
// consumer also re-drains whenever it might have fallen behind.
func (l *Library) drainCatalog(ctx context.Context) error {
	for {
		l.feed.mu.Lock()
		since := l.feed.tail
		l.feed.mu.Unlock()
		rows, err := l.lib.Changes(ctx, since)
		if err != nil {
			return classify(err)
		}
		if len(rows) == 0 {
			return nil
		}
		for _, ch := range rows {
			l.advanceFeed(ch)
		}
	}
}

// advanceFeed tracks one change row and wakes the hub when a summary
// mirror could care.
func (l *Library) advanceFeed(ch model.Change) {
	l.feed.mu.Lock()
	if ch.Seq > l.feed.tail {
		l.feed.tail = ch.Seq
		l.feed.tailTS = ch.TS
	}
	l.feed.mu.Unlock()
	if ch.EntityType == "item" {
		select {
		case l.catalogWake <- struct{}{}:
		default:
		}
	}
}

// persistFeedCursor stores the feed position; force writes even inside
// the coarse cadence (shutdown).
func (l *Library) persistFeedCursor(ctx context.Context, force bool) {
	l.feed.mu.Lock()
	if !force && time.Since(l.feed.lastPersist) < 2*time.Second {
		l.feed.mu.Unlock()
		return
	}
	cur := fmt.Sprintf("%d|%d", l.feed.tail, l.feed.tailTS)
	l.feed.lastPersist = time.Now()
	l.feed.mu.Unlock()
	if err := l.db.SyncStateSet(ctx, syncKeyCatalogCursor, cur); err != nil {
		l.log.Warn("persisting catalog cursor", "err", err)
	}
}

func parseFeedCursor(s string) (seq, ts int64) {
	a, b, ok := strings.Cut(s, "|")
	if !ok {
		return 0, 0
	}
	seq, _ = strconv.ParseInt(a, 10, 64)
	ts, _ = strconv.ParseInt(b, 10, 64)
	return seq, ts
}

// CatalogWakeups signals when item-granular catalog changes landed. It
// is a coalesced hint, not a delivery guarantee; the sync endpoints are
// the authoritative path.
func (l *Library) CatalogWakeups() <-chan struct{} { return l.catalogWake }

// UserEventWakeups carries the WaxDeck user id whose server state just
// changed. Lossy by design (a dropped hint is covered by the next one
// or a poll).
func (l *Library) UserEventWakeups() <-chan string { return l.userWake }

// emitUserEvent appends to the server stream and wakes the hub. Event
// loss here must never fail the mutation that caused it: the stream is
// an invalidation signal over authoritative state, not the state.
func (l *Library) emitUserEvent(ctx context.Context, userID, kind, itemPID string) {
	if _, err := l.db.AppendEvent(ctx, userID, kind, itemPID); err != nil {
		l.log.Warn("appending server event", "kind", kind, "err", err)
		return
	}
	select {
	case l.userWake <- userID:
	default:
	}
}

// --- cursors -----------------------------------------------------------------

// encodeCatalogCursor binds generation, grant epoch, and position.
func encodeCatalogCursor(gen string, epoch, seq int64) string {
	raw := fmt.Sprintf("c1|%s|%d|%d", gen, epoch, seq)
	return base64.RawURLEncoding.EncodeToString([]byte(raw))
}

func decodeCatalogCursor(s string) (gen string, epoch, seq int64, ok bool) {
	raw, err := base64.RawURLEncoding.DecodeString(s)
	if err != nil {
		return "", 0, 0, false
	}
	parts := strings.Split(string(raw), "|")
	if len(parts) != 4 || parts[0] != "c1" {
		return "", 0, 0, false
	}
	epoch, err = strconv.ParseInt(parts[2], 10, 64)
	if err != nil {
		return "", 0, 0, false
	}
	seq, err = strconv.ParseInt(parts[3], 10, 64)
	if err != nil {
		return "", 0, 0, false
	}
	return parts[1], epoch, seq, true
}

// encodeSnapshotCursor wraps a snapshot page cursor: the change cursor
// frozen before the first page's read rides inside every keyset cursor,
// so later pages repeat it instead of re-reading a moving tail (a
// mid-snapshot edit must fall inside the first delta, not vanish
// between two pages' cursors).
func encodeSnapshotCursor(since string, next read.Cursor) string {
	raw := "n1|" + since + "|" + string(next)
	return base64.RawURLEncoding.EncodeToString([]byte(raw))
}

func decodeSnapshotCursor(s string) (since string, next read.Cursor, ok bool) {
	raw, err := base64.RawURLEncoding.DecodeString(s)
	if err != nil {
		return "", "", false
	}
	rest, found := strings.CutPrefix(string(raw), "n1|")
	if !found {
		return "", "", false
	}
	// The frozen cursor is base64url and cannot contain the separator;
	// the keyset remainder may contain anything.
	i := strings.IndexByte(rest, '|')
	if i < 0 {
		return "", "", false
	}
	since, next = rest[:i], read.Cursor(rest[i+1:])
	if _, _, _, valid := decodeCatalogCursor(since); !valid {
		return "", "", false
	}
	return since, next, true
}

func encodeServerCursor(gen string, id int64) string {
	raw := fmt.Sprintf("s1|%s|%d", gen, id)
	return base64.RawURLEncoding.EncodeToString([]byte(raw))
}

func decodeServerCursor(s string) (gen string, id int64, ok bool) {
	raw, err := base64.RawURLEncoding.DecodeString(s)
	if err != nil {
		return "", 0, false
	}
	parts := strings.Split(string(raw), "|")
	if len(parts) != 3 || parts[0] != "s1" {
		return "", 0, false
	}
	id, err = strconv.ParseInt(parts[2], 10, 64)
	if err != nil {
		return "", 0, false
	}
	return parts[1], id, true
}

// grantEpoch reads the user's current visibility epoch (0 until ever
// bumped).
func (l *Library) grantEpoch(ctx context.Context, userID string) (int64, error) {
	v, err := l.db.SyncStateGet(ctx, syncKeyGrantEpoch+userID)
	if err != nil {
		return 0, &Error{Kind: KindInternal, Err: err}
	}
	if v == "" {
		return 0, nil
	}
	n, err := strconv.ParseInt(v, 10, 64)
	if err != nil {
		return 0, nil
	}
	return n, nil
}

// bumpGrantEpoch retires the user's outstanding catalog cursors after a
// visibility change; their next delta answers sync-reset and the
// re-snapshot reflects the new grants.
func (l *Library) bumpGrantEpoch(ctx context.Context, userID string) {
	cur, err := l.grantEpoch(ctx, userID)
	if err != nil {
		l.log.Warn("reading grant epoch", "user", userID, "err", err)
		cur = 0
	}
	if err := l.db.SyncStateSet(ctx, syncKeyGrantEpoch+userID, strconv.FormatInt(cur+1, 10)); err != nil {
		l.log.Warn("bumping grant epoch", "user", userID, "err", err)
	}
}

// --- catalog sync ------------------------------------------------------------

// SyncCatalogSnapshot serves one keyset page of the full mirror. The
// change cursor is captured once, before the first page's read, and
// threaded through the page cursor so every page repeats it per the
// contract; changes landing mid-snapshot fall inside the first delta.
func (l *Library) SyncCatalogSnapshot(ctx context.Context, uc *UserCtx, cursor string, limit int) (CatalogSnapshotPage, error) {
	var since string
	inner := read.Cursor("")
	if cursor == "" {
		epoch, err := l.grantEpoch(ctx, uc.ID)
		if err != nil {
			return CatalogSnapshotPage{}, err
		}
		l.feed.mu.Lock()
		gen, tail := l.feed.gen, l.feed.tail
		l.feed.mu.Unlock()
		since = encodeCatalogCursor(gen, epoch, tail)
	} else {
		var ok bool
		since, inner, ok = decodeSnapshotCursor(cursor)
		if !ok {
			return CatalogSnapshotPage{}, errInvalid("malformed snapshot cursor")
		}
	}

	q := query.New(query.EntityItems).Build()
	page, err := l.lib.QueryPage(ctx, q, inner, limit, false, model.PID(uc.CatalogPID))
	if err != nil {
		return CatalogSnapshotPage{}, classify(err)
	}
	out := CatalogSnapshotPage{
		Entries:   make([]CatalogSyncEntry, 0, len(page.Items)),
		NextSince: since,
	}
	for _, it := range page.Items {
		if !l.viewVisible(ctx, uc, it) {
			continue
		}
		s := summary(it)
		out.Entries = append(out.Entries, CatalogSyncEntry{Op: "upsert", PID: s.PID, Item: &s})
	}
	if page.HasMore {
		out.NextCursor = encodeSnapshotCursor(since, page.Next)
	}
	return out, nil
}

// SyncCatalogDelta serves the changes after the given cursor, coalesced
// per item within the page, hydrated fresh. True deletions and changes
// that carry an item out of the caller's visibility both become
// tombstones; a tombstone for an item never mirrored is a client no-op.
func (l *Library) SyncCatalogDelta(ctx context.Context, uc *UserCtx, since string, limit int) (CatalogDelta, error) {
	gen, epoch, seq, ok := decodeCatalogCursor(since)
	if !ok {
		return CatalogDelta{}, errInvalid("malformed sync cursor")
	}
	curEpoch, err := l.grantEpoch(ctx, uc.ID)
	if err != nil {
		return CatalogDelta{}, err
	}
	l.feed.mu.Lock()
	curGen, floor := l.feed.gen, l.feed.floor
	l.feed.mu.Unlock()
	if gen != curGen || epoch != curEpoch || seq < floor {
		return CatalogDelta{}, ErrSyncReset
	}

	// Collect up to limit distinct items' latest ops, tracking the last
	// consumed seq. The facade caps each pull at 1000 rows; filtered
	// rows (user state, files, entities) advance the cursor for free.
	ops := make(map[model.PID]string)
	order := make([]model.PID, 0, limit)
	budgetHit := false
	for !budgetHit {
		rows, err := l.lib.Changes(ctx, seq)
		if err != nil {
			return CatalogDelta{}, classify(err)
		}
		if len(rows) == 0 {
			break
		}
		for _, ch := range rows {
			if ch.EntityType != "item" {
				seq = ch.Seq
				continue
			}
			if _, seen := ops[ch.EntityPID]; !seen {
				if len(order) == limit {
					budgetHit = true
					break
				}
				order = append(order, ch.EntityPID)
			}
			ops[ch.EntityPID] = string(ch.Op)
			seq = ch.Seq
		}
	}

	out := CatalogDelta{
		Entries:   make([]CatalogSyncEntry, 0, len(order)),
		NextSince: encodeCatalogCursor(curGen, curEpoch, seq),
		More:      budgetHit,
	}
	if len(order) == 0 {
		return out, nil
	}
	views, err := l.lib.GetMany(ctx, order)
	if err != nil {
		return CatalogDelta{}, classify(err)
	}
	byPID := make(map[model.PID]*model.ItemView, len(views))
	for _, v := range views {
		byPID[v.PID] = v
	}
	for _, pid := range order {
		it := byPID[pid]
		if ops[pid] == string(model.OpDelete) || it == nil {
			// The kind is unknowable once the item is gone; tombstones
			// carry the track prefix and mirrors match on the ULID.
			out.Entries = append(out.Entries, CatalogSyncEntry{Op: "delete", PID: apiPID(PrefixTrack, pid)})
			continue
		}
		if !l.viewVisible(ctx, uc, it) {
			// A change can carry an item out of the caller's sight with
			// no grant change to bump the epoch (a file re-homed under
			// an ungranted root keeps its item PID). Skipping would
			// strand the stale row in the client's mirror, so the
			// transition tombstones instead.
			out.Entries = append(out.Entries, CatalogSyncEntry{Op: "delete", PID: apiPID(PrefixTrack, pid)})
			continue
		}
		s := summary(it)
		out.Entries = append(out.Entries, CatalogSyncEntry{Op: "upsert", PID: s.PID, Item: &s})
	}
	return out, nil
}

// PruneCatalogChanges trims the catalog change log to the newest keep
// rows and raises the served floor accordingly. Cursors below the new
// floor answer sync-reset from then on.
func (l *Library) PruneCatalogChanges(ctx context.Context, keep int) (int, error) {
	n, err := l.lib.PruneChangeLog(ctx, keep)
	if err != nil {
		return 0, classify(err)
	}
	rows, err := l.lib.Changes(ctx, 0)
	if err != nil {
		return n, classify(err)
	}
	if len(rows) > 0 {
		l.feed.mu.Lock()
		l.feed.floor = rows[0].Seq - 1
		l.feed.mu.Unlock()
	}
	return n, nil
}

// --- server sync -------------------------------------------------------------

// MintServerCursor returns a fresh cursor at the stream's current tail.
func (l *Library) MintServerCursor(ctx context.Context) (string, error) {
	tail, err := l.db.LatestEventID(ctx)
	if err != nil {
		return "", &Error{Kind: KindInternal, Err: err}
	}
	return encodeServerCursor(l.serverGen, tail), nil
}

// SyncServerDelta serves the caller's state changes after the cursor,
// coalesced per item within the page, hydrated fresh at read time.
func (l *Library) SyncServerDelta(ctx context.Context, uc *UserCtx, since string, limit int) (ServerDelta, error) {
	gen, id, ok := decodeServerCursor(since)
	if !ok {
		return ServerDelta{}, errInvalid("malformed sync cursor")
	}
	floor, err := l.db.EventFloor(ctx)
	if err != nil {
		return ServerDelta{}, &Error{Kind: KindInternal, Err: err}
	}
	tail, err := l.db.LatestEventID(ctx)
	if err != nil {
		return ServerDelta{}, &Error{Kind: KindInternal, Err: err}
	}
	if gen != l.serverGen || id < floor || id > tail {
		return ServerDelta{}, ErrSyncReset
	}
	events, more, err := l.db.EventsSince(ctx, uc.ID, id, limit)
	if err != nil {
		return ServerDelta{}, &Error{Kind: KindInternal, Err: err}
	}
	next := id
	if len(events) > 0 {
		next = events[len(events)-1].ID
	} else {
		// No events for this user past id; the cursor can jump to the
		// stream tail so later reads scan nothing twice.
		next = tail
	}
	out := ServerDelta{NextSince: encodeServerCursor(l.serverGen, next), More: more}

	seenState := make(map[string]bool)
	seenPrefs := false
	for _, e := range events {
		switch e.Kind {
		case eventPlayState:
			if seenState[e.ItemPID] {
				continue
			}
			seenState[e.ItemPID] = true
			apiItem, st, err := l.hydratePlayState(ctx, uc, e.ItemPID)
			if err != nil {
				return ServerDelta{}, err
			}
			if apiItem == "" {
				continue
			}
			out.Events = append(out.Events, ServerSyncEvent{Kind: eventPlayState, PID: apiItem, PlayState: &st})
		case eventPrefs:
			if seenPrefs {
				continue
			}
			seenPrefs = true
			p, err := l.Prefs(ctx, uc)
			if err != nil {
				return ServerDelta{}, err
			}
			out.Events = append(out.Events, ServerSyncEvent{Kind: eventPrefs, Prefs: &p})
		}
	}
	return out, nil
}

// hydratePlayState reads the user's current state for a bare catalog
// pid, returning the API pid ("" when the item vanished or is not
// visible to the caller; the event is then dropped).
func (l *Library) hydratePlayState(ctx context.Context, uc *UserCtx, barePID string) (string, PlayState, error) {
	it, err := l.lib.Get(ctx, model.PID(barePID))
	if err != nil {
		if KindOf(classify(err)) == KindNotFound {
			return "", PlayState{}, nil
		}
		return "", PlayState{}, classify(err)
	}
	if !uc.AllLibraries && !l.itemVisible(ctx, uc, it.PID) {
		return "", PlayState{}, nil
	}
	apiItem := itemAPIPID(it)
	st, err := l.playStateFor(ctx, uc, apiItem, it.PID)
	if err != nil {
		return "", PlayState{}, err
	}
	return apiItem, st, nil
}

// PlayStates reads the caller's state for a batch of items, skipping
// invisible and unknown pids and zero states.
func (l *Library) PlayStates(ctx context.Context, uc *UserCtx, apiPIDs []string) ([]PlayState, error) {
	out := make([]PlayState, 0, len(apiPIDs))
	for _, apiItem := range apiPIDs {
		it, err := l.getVisibleItem(ctx, uc, apiItem)
		if err != nil {
			if KindOf(err) == KindNotFound || KindOf(err) == KindInvalid {
				continue
			}
			return nil, err
		}
		st, err := l.playStateFor(ctx, uc, apiItem, it.PID)
		if err != nil {
			return nil, err
		}
		if st.PositionMS == 0 && !st.Played && !st.Finished && st.PlayCount == 0 &&
			!st.Starred && st.Rating == nil {
			continue
		}
		out = append(out, st)
	}
	return out, nil
}

// PruneServerEvents trims the server event stream to the newest keep
// rows; cursors below the surviving floor answer sync-reset.
func (l *Library) PruneServerEvents(ctx context.Context, keep int) (int64, error) {
	n, err := l.db.PruneEventLog(ctx, keep)
	if err != nil {
		return 0, &Error{Kind: KindInternal, Err: err}
	}
	return n, nil
}
