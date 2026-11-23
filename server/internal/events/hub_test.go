package events

import (
	"context"
	"fmt"
	"reflect"
	"slices"
	"sync"
	"testing"
	"time"
)

// framesAre reports whether got is exactly the frames wanted, in order.
func framesAre(got []Frame, want ...Frame) bool {
	return reflect.DeepEqual(got, want)
}

// The frames a test compares against.
var (
	resyncAll = Frame{Type: TypeResync}
	// bareCatalog says nothing about entities; unnamedCatalog says some
	// changed that it does not name.
	bareCatalog    = Frame{Type: TypeInvalidate, Topic: TopicCatalog}
	unnamedCatalog = Frame{Type: TypeInvalidate, Topic: TopicCatalog, Unnamed: true}
	radioMoved     = Frame{Type: TypeInvalidate, Topic: TopicRadio}
)

// namedCatalog is the catalog invalidation naming pids.
func namedCatalog(pids ...string) Frame {
	return Frame{Type: TypeInvalidate, Topic: TopicCatalog, Pids: pids}
}

// The subscribe-frame topic list is client input: unknown names are
// ignored, and a list left with no recognized names falls back to every
// topic rather than silently subscribing to nothing.
func TestRegisterTopicFiltering(t *testing.T) {
	h := New(nil)
	cases := []struct {
		name          string
		topics        []string
		catalog, user bool
	}{
		{"empty list means everything", nil, true, true},
		{"catalog only", []string{TopicCatalog}, true, false},
		{"unknown names are dropped", []string{TopicUser, "bogus"}, false, true},
		{"only unknown names fall back to everything", []string{"bogus", "custom"}, true, true},
	}
	for _, tc := range cases {
		c := h.Register("u1", "se-u1", tc.topics)
		if got := c.wants(TopicCatalog); got != tc.catalog {
			t.Errorf("%s: wants(catalog) = %v, want %v", tc.name, got, tc.catalog)
		}
		if got := c.wants(TopicUser); got != tc.user {
			t.Errorf("%s: wants(user) = %v, want %v", tc.name, got, tc.user)
		}
		h.Unregister(c)
	}
}

// Invalidations for unsubscribed topics are dropped at Mark time; a
// resync always queues.
func TestMarkRespectsSubscription(t *testing.T) {
	h := New(nil)
	c := h.Register("u1", "se-u1", []string{TopicCatalog})
	c.Mark(TypeInvalidate, TopicUser)
	if frames := c.TakePending(); len(frames) != 0 {
		t.Fatalf("unsubscribed invalidate queued: %+v", frames)
	}
	c.Mark(TypeInvalidate, TopicCatalog)
	c.Mark(TypeResync, "")
	frames := c.TakePending()
	if !framesAre(frames, resyncAll, bareCatalog) {
		t.Fatalf("frames = %+v, want resync then catalog invalidate", frames)
	}
}

// A replaced catalog asks every connection to re-mirror both streams,
// ahead of its invalidations: what the user stream hydrates moved too.
func TestMarkCatalogReplacedReachesEveryConnection(t *testing.T) {
	h := New(nil)
	a := h.Register("u1", "se-u1", nil)
	b := h.Register("u2", "se-u2", []string{TopicUser})
	a.Mark(TypeInvalidate, TopicCatalog)
	h.MarkCatalogReplaced()
	frames := a.TakePending()
	if !framesAre(frames, resyncAll, bareCatalog) {
		t.Fatalf("frames = %+v, want the resync of every stream then the invalidate", frames)
	}
	if frames := b.TakePending(); !framesAre(frames, resyncAll) {
		t.Fatalf("frames = %+v, want the resync of every stream", frames)
	}
	b.Mark(TypeResync, TopicCatalog)
	b.Mark(TypeResync, "")
	if frames := b.TakePending(); !framesAre(frames, resyncAll) {
		t.Fatalf("frames = %+v, want the one resync of every stream", frames)
	}
}

// idleSource is a wakeSource that never wakes, so a test can run the
// coalescer without catalog or user traffic crossing it.
type idleSource struct{}

func (idleSource) CatalogWakeups() <-chan struct{}             { return nil }
func (idleSource) UserEventWakeups() <-chan string             { return nil }
func (idleSource) DrainCatalogChanges() ([]string, bool, bool) { return nil, false, false }
func (idleSource) CatalogPosition() (int64, int64, string)     { return 0, 0, "" }
func (idleSource) CatalogFrameFor(_, _ string, pids []string) (string, []string, bool) {
	return "", pids, false
}
func (idleSource) CatalogChangesSince(string, string) ([]string, bool, bool, int64, int64, string) {
	return nil, false, false, 0, 0, ""
}

// waitForFrames drains the connection until it has something, so a test
// asserts on the coalescer's tick rather than racing it.
func waitForFrames(t *testing.T, c *Conn) []Frame {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if frames := c.TakePending(); len(frames) > 0 {
			return frames
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatal("no frames arrived before the deadline")
	return nil
}

// The radio topic rides the same registry as the rest - subscribable by
// name, filtered when a connection asked for other topics only - and the
// same coalescer, so a burst of covers landing is one frame per socket.
func TestHubFansRadioOutAndRespectsTheSubscription(t *testing.T) {
	t.Parallel()
	h := New(idleSource{})
	all := h.Register("u1", "se-u1", nil)
	radioOnly := h.Register("u1", "se-u1", []string{TopicRadio})
	catalogOnly := h.Register("u2", "se-u2", []string{TopicCatalog})

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go h.Run(ctx)

	// Three covers landing inside one window, which is what a household
	// on three stations does after a restart. Nobody here has tuned, so
	// every one of them keeps the topic's older contract and hears all
	// three as one frame.
	h.MarkRadio("rs-jazz")
	h.MarkRadio("rs-talk")
	h.MarkRadio("rs-jazz")

	for _, tc := range []struct {
		name string
		conn *Conn
	}{
		{"subscribed to everything", all},
		{"subscribed to radio", radioOnly},
	} {
		if got := waitForFrames(t, tc.conn); !framesAre(got, radioMoved) {
			t.Fatalf("%s: frames = %v, want %v", tc.name, got, radioMoved)
		}
	}
	if got := catalogOnly.TakePending(); got != nil {
		t.Fatalf("subscribed elsewhere: frames = %v, want none", got)
	}
	// Taken once: the flag clears with the frame, so a listener does not
	// re-poll on every later wake.
	if got := all.TakePending(); got != nil {
		t.Fatalf("frames after taking = %v, want none", got)
	}
}

// A cover lands for one station, and only the sockets listening to that
// station hear about it: the frame names no station, so a broadcast was
// harmless but told every connection in the house to re-read a
// play-info endpoint for a station it is not on.
func TestHubMarksOnlyTheTunedConnections(t *testing.T) {
	t.Parallel()
	h := New(idleSource{})
	tuned := h.Register("u1", "se-u1", []string{TopicRadio})
	tuned.Tune("rs-jazz")
	elsewhere := h.Register("u1", "se-u1", []string{TopicRadio})
	elsewhere.Tune("rs-talk")
	// Tuned to nothing, deliberately: a client that walked away from the
	// dial and said so.
	untuned := h.Register("u2", "se-u2", nil)
	untuned.Tune("")
	// Never tuned: a client from before the frame, or one that does not
	// send it, which the topic still owes every landing.
	legacy := h.Register("u3", "se-u3", nil)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go h.Run(ctx)

	h.MarkRadio("rs-jazz")

	want := radioMoved
	if got := waitForFrames(t, tuned); !framesAre(got, want) {
		t.Fatalf("tuned connection: frames = %v, want %v", got, want)
	}
	if got := elsewhere.TakePending(); got != nil {
		t.Fatalf("a connection on another station: frames = %v, want none", got)
	}
	// Tuned to nothing is a statement: there is no station to re-read.
	if got := untuned.TakePending(); got != nil {
		t.Fatalf("a connection tuned to nothing: frames = %v, want none", got)
	}
	// Never tuned is not: the subscription it made asked for the topic,
	// and a landing it cannot be told apart from is still its business.
	if got := waitForFrames(t, legacy); !framesAre(got, want) {
		t.Fatalf("a connection that never tuned: frames = %v, want %v", got, want)
	}

	// Retuning replaces, so the old station stops reaching it and the
	// new one starts.
	tuned.Tune("rs-talk")
	h.MarkRadio("rs-talk")
	if got := waitForFrames(t, tuned); !framesAre(got, want) {
		t.Fatalf("after retuning: frames = %v, want %v", got, want)
	}
	if got := waitForFrames(t, elsewhere); !framesAre(got, want) {
		t.Fatalf("the station's other listener: frames = %v, want %v", got, want)
	}

	// And tuning to nothing stops it.
	tuned.Tune("")
	h.MarkRadio("rs-talk")
	waitForFrames(t, elsewhere)
	if got := tuned.TakePending(); got != nil {
		t.Fatalf("after tuning to nothing: frames = %v, want none", got)
	}
}

// ended reports whether the connection has been told to end.
func ended(c *Conn) bool {
	select {
	case <-c.Ended():
		return true
	default:
		return false
	}
}

// Ending sessions reaches the connections those sessions opened and no
// others, whoever they belong to.
func TestEndSessionsClosesOnlyThoseConnections(t *testing.T) {
	h := New(nil)
	a := h.Register("u1", "se-a", nil)
	b := h.Register("u1", "se-b", nil)
	c := h.Register("u2", "se-c", nil)
	h.EndSessions("se-a", "se-c")
	if !ended(a) || !ended(c) {
		t.Errorf("the named sessions' connections are still open: a=%v c=%v", ended(a), ended(c))
	}
	if ended(b) {
		t.Error("a connection of another session ended")
	}
}

// Signing out everywhere else keeps the session that asked.
func TestEndUserKeepsTheNamedSession(t *testing.T) {
	h := New(nil)
	kept := h.Register("u1", "se-keep", nil)
	other := h.Register("u1", "se-other", nil)
	stranger := h.Register("u2", "se-stranger", nil)
	h.EndUser("u1", "se-keep")
	if ended(kept) || ended(stranger) {
		t.Errorf("kept=%v stranger=%v, want both open", ended(kept), ended(stranger))
	}
	if !ended(other) {
		t.Error("the account's other session is still open")
	}
	h.EndUser("u1", "")
	if !ended(kept) {
		t.Error("ending every session of the account left one open")
	}
}

// A connection ended twice (a revoke racing the disable that caused it)
// is ended once, not a panic on a closed channel.
func TestEndIsIdempotent(t *testing.T) {
	h := New(nil)
	c := h.Register("u1", "se-a", nil)
	h.EndSessions("se-a")
	h.EndSessions("se-a")
	h.EndUser("u1", "")
	if !ended(c) {
		t.Fatal("the connection did not end")
	}
}

// movingSource is a wakeSource whose catalog wakes carry what a test
// says moved, and whose accounts a test can narrow.
type movingSource struct {
	wake chan struct{}

	mu      sync.Mutex
	pids    []string
	unnamed bool
	unknown bool
	// narrowed accounts decide none of a frame's names; one in sees is
	// told those of them it holds.
	narrowed map[string]bool
	sees     map[string][]string
	// order, cover and pos are where the stream stands; unreadable
	// accounts answer no cursor.
	order      int64
	cover      int64
	pos        string
	unreadable map[string]bool
	// since answers a subscribing cursor; asked records who asked.
	since sinceAnswer
	asked []string
	// accountReads counts the frames the account was read for.
	accountReads int
}

// sinceAnswer is what the source tells a subscribe presenting a cursor.
type sinceAnswer struct {
	pids      []string
	unnamed   bool
	unchanged bool
	order     int64
	cover     int64
	pos       string
}

func newMovingSource() *movingSource {
	return &movingSource{wake: make(chan struct{}, 1), narrowed: map[string]bool{}, sees: map[string][]string{},
		unreadable: map[string]bool{}}
}

func (s *movingSource) CatalogWakeups() <-chan struct{} { return s.wake }
func (s *movingSource) UserEventWakeups() <-chan string { return nil }

func (s *movingSource) DrainCatalogChanges() ([]string, bool, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	pids, unnamed, unknown := s.pids, s.unnamed, s.unknown
	s.pids, s.unnamed, s.unknown = nil, false, false
	return pids, unnamed, unknown
}

func (s *movingSource) CatalogPosition() (int64, int64, string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.order, s.cover, s.pos
}

// CatalogFrameFor answers the cursor as the account and position joined,
// and the names as the account decides them, counting the account reads
// it was asked for.
func (s *movingSource) CatalogFrameFor(userID, pos string, pids []string) (string, []string, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(pids) > 0 {
		s.accountReads++
	}
	if s.unreadable[userID] {
		return "", nil, len(pids) > 0
	}
	since := ""
	if pos != "" {
		since = userID + "@" + pos
	}
	if s.narrowed[userID] && len(pids) > 0 {
		return since, nil, true
	}
	if seen, ok := s.sees[userID]; ok {
		var told []string
		for _, pid := range pids {
			if slices.Contains(seen, pid) {
				told = append(told, pid)
			}
		}
		return since, told, false
	}
	return since, pids, false
}

func (s *movingSource) CatalogChangesSince(userID, cursor string) ([]string, bool, bool, int64, int64, string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.asked = append(s.asked, userID+"@"+cursor)
	a := s.since
	return a.pids, a.unnamed, a.unchanged, a.order, a.cover, a.pos
}

// at moves the stream's position.
func (s *movingSource) at(order int64, pos string) {
	s.mu.Lock()
	s.order, s.pos = order, pos
	s.mu.Unlock()
}

// coverAt moves the newest show cover move the stream's position covers.
func (s *movingSource) coverAt(stamp int64) {
	s.mu.Lock()
	s.cover = stamp
	s.mu.Unlock()
}

// narrow says whether something narrows what the account reads.
func (s *movingSource) narrow(userID string, narrowed bool) {
	s.mu.Lock()
	s.narrowed[userID] = narrowed
	s.mu.Unlock()
}

// moved records the entities as changed and wakes the hub, as the feed
// does: the record first. No pids is a wake with nothing to name, a
// genre's or a spare one.
func (s *movingSource) moved(pids ...string) {
	s.mu.Lock()
	s.pids = append(s.pids, pids...)
	s.mu.Unlock()
	s.wakeHub()
}

// couldNotName wakes the hub for entities the source cannot name: more
// than it holds, or a read that failed. Any pids come back beside the
// flag, which is what says not to send them.
func (s *movingSource) couldNotName(pids ...string) {
	s.mu.Lock()
	s.pids, s.unnamed = append(s.pids, pids...), true
	s.mu.Unlock()
	s.wakeHub()
}

// replaced wakes the hub with no row behind the wake: the catalog may be
// another one.
func (s *movingSource) replaced() {
	s.mu.Lock()
	s.unknown = true
	s.mu.Unlock()
	s.wakeHub()
}

func (s *movingSource) wakeHub() {
	select {
	case s.wake <- struct{}{}:
	default:
	}
}

// tick is the coalescer's tick for a dirty catalog, without the wait.
func tick(h *Hub) {
	h.flush(true, h.catalogMoved(), nil, nil)
}

// names is the move that names pids and nothing else.
func names(pids ...string) catalogMove { return catalogMove{pids: pids} }

// somePIDs mints n distinct pids from a seed.
func somePIDs(seed string, n int) []string {
	out := make([]string, n)
	for i := range out {
		out[i] = fmt.Sprintf("ar-%s%03d", seed, i)
	}
	return out
}

// A catalog wake whose entities the source can name reaches a connection
// as one frame naming them, sorted, and a wake with nothing to name
// still reaches it, as the bare frame.
func TestACatalogFrameNamesWhatMoved(t *testing.T) {
	t.Parallel()
	src := newMovingSource()
	h := New(src)
	c := h.Register("u1", "se-u1", nil)
	elsewhere := h.Register("u1", "se-u1", []string{TopicUser})

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go h.Run(ctx)

	src.moved("tr-b", "al-a", "tr-b")
	if got := waitForFrames(t, c); !framesAre(got, namedCatalog("al-a", "tr-b")) {
		t.Fatalf("frames = %+v, want the catalog invalidation naming both", got)
	}
	if got := c.TakePending(); got != nil {
		t.Fatalf("frames after taking = %+v, want none", got)
	}

	// A genre moved: it has no pid, and the clients still have to pull.
	src.moved()
	if got := waitForFrames(t, c); !framesAre(got, bareCatalog) {
		t.Fatalf("frames = %+v, want the bare catalog invalidation", got)
	}
	if got := elsewhere.TakePending(); got != nil {
		t.Fatalf("subscribed elsewhere: frames = %+v, want none", got)
	}
}

// What a slow connection has not taken yet adds up into the one frame it
// is owed, and taking it starts over.
func TestCatalogNamesAddUpUntilTaken(t *testing.T) {
	src := newMovingSource()
	h := New(src)
	c := h.Register("u1", "se-u1", nil)
	c.markCatalog(names("ar-b"))
	c.markCatalog(names("al-a", "ar-b"))
	if got := c.TakePending(); !framesAre(got, namedCatalog("al-a", "ar-b")) {
		t.Fatalf("frames = %+v, want one frame naming both", got)
	}
	c.markCatalog(names("tr-c"))
	if got := c.TakePending(); !framesAre(got, namedCatalog("tr-c")) {
		t.Fatalf("frames after a take = %+v, want only what moved since", got)
	}
}

// A connection holds at most a frame's worth of names. One more and the
// frame it is owed says entities went unnamed, whatever arrives before
// it is taken; the next starts over.
func TestMoreNamesThanAConnectionHoldsAreUnnamed(t *testing.T) {
	src := newMovingSource()
	h := New(src)
	c := h.Register("u1", "se-u1", nil)

	full := somePIDs("A", MaxCatalogPIDs)
	c.markCatalog(names(full[:40]...))
	c.markCatalog(names(full[30:]...))
	if got := c.TakePending(); len(got) != 1 || len(got[0].Pids) != MaxCatalogPIDs || got[0].Unnamed {
		t.Fatalf("frames = %+v, want one frame naming all %d", got, MaxCatalogPIDs)
	}

	c.markCatalog(names(full...))
	c.markCatalog(names("ar-one-more"))
	c.markCatalog(names("ar-after"))
	if got := c.TakePending(); !framesAre(got, unnamedCatalog) {
		t.Fatalf("frames = %+v, want the unnamed frame past the bound", got)
	}
	c.mu.Lock()
	held := len(c.pending.catalogPids)
	c.mu.Unlock()
	if held != 0 {
		t.Fatalf("the connection still holds %d names", held)
	}

	c.markCatalog(names("ar-after"))
	if got := c.TakePending(); !framesAre(got, namedCatalog("ar-after")) {
		t.Fatalf("frames after the overflow was taken = %+v, want names again", got)
	}
}

// A source that could not name everything says so, and every connection
// is sent the unnamed frame and no pids, whatever came back beside the
// flag. A failed read is the same answer with no pids beside it.
func TestASourceThatCouldNotNameWhatMovedSendsUnnamed(t *testing.T) {
	t.Parallel()
	src := newMovingSource()
	h := New(src)
	c := h.Register("u1", "se-u1", nil)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go h.Run(ctx)

	src.couldNotName("ar-a", "al-b")
	if got := waitForFrames(t, c); !framesAre(got, unnamedCatalog) {
		t.Fatalf("more than fit: frames = %+v, want the unnamed catalog invalidation", got)
	}
	src.couldNotName()
	if got := waitForFrames(t, c); !framesAre(got, unnamedCatalog) {
		t.Fatalf("a failed read: frames = %+v, want the unnamed catalog invalidation", got)
	}
	// The flag is spent with its frame.
	src.moved("ar-c")
	if got := waitForFrames(t, c); !framesAre(got, namedCatalog("ar-c")) {
		t.Fatalf("frames after = %+v, want names again", got)
	}
}

// The hub holds the frame's bound itself: a source that hands back more
// pids than a frame names, and does not say it left any out, names
// nothing and is unnamed. Asked of the hub's own read, because a
// connection's set would drop the same list one step later and hide a
// missing check here.
func TestMorePIDsThanAFrameNamesFromTheSourceAreUnnamed(t *testing.T) {
	src := newMovingSource()
	h := New(src)

	src.moved(somePIDs("A", MaxCatalogPIDs)...)
	if got := h.catalogMoved(); len(got.pids) != MaxCatalogPIDs || got.unnamed || got.unknown {
		t.Fatalf("a full frame's worth: %+v, want all %d named", got, MaxCatalogPIDs)
	}
	src.moved(somePIDs("B", MaxCatalogPIDs+1)...)
	if got := h.catalogMoved(); !reflect.DeepEqual(got, catalogMove{unnamed: true}) {
		t.Fatalf("one more than a frame names: %+v, want no pids and unnamed", got)
	}
	src.couldNotName("ar-a")
	if got := h.catalogMoved(); !reflect.DeepEqual(got, catalogMove{unnamed: true}) {
		t.Fatalf("pids beside the flag: %+v, want no pids and unnamed", got)
	}
	src.moved()
	if got := h.catalogMoved(); !reflect.DeepEqual(got, catalogMove{}) {
		t.Fatalf("nothing to name: %+v, want nothing", got)
	}
	src.replaced()
	if got := h.catalogMoved(); !reflect.DeepEqual(got, catalogMove{unknown: true}) {
		t.Fatalf("a wake with no row: %+v, want unknown alone", got)
	}
}

// A wake still waiting when the hub asks what moved stands for a row the
// source recorded before it woke, so the answer holds that row and the
// wake is spent with it: left waiting, it would send a second frame
// naming nothing. A wake that lands after the answer is kept.
func TestTheDrainSpendsAWakeAlreadyWaiting(t *testing.T) {
	src := newMovingSource()
	h := New(src)

	src.moved("ar-a")
	if got := h.catalogMoved().pids; !reflect.DeepEqual(got, []string{"ar-a"}) {
		t.Fatalf("moved = %v, want the row the waiting wake stood for", got)
	}
	if len(src.wake) != 0 {
		t.Fatal("the wake the answer covered is still waiting")
	}

	src.moved("ar-b")
	select {
	case <-src.CatalogWakeups():
	default:
		t.Fatal("a wake sent after the answer was lost")
	}
	if got := h.catalogMoved().pids; !reflect.DeepEqual(got, []string{"ar-b"}) {
		t.Fatalf("moved = %v, want the later row", got)
	}
}

// A wake with nothing to name says nothing about entities: a genre's or
// a spare one, one no row stood behind, the invalidation a returning
// client is sent as it subscribes, and one beside a resync all send the
// bare frame.
func TestAWakeWithNothingToNameSendsTheBareFrame(t *testing.T) {
	src := newMovingSource()
	src.narrow("u2", true)
	h := New(src)
	whole := h.Register("u1", "se-u1", nil)
	narrowed := h.Register("u2", "se-u2", nil)
	both := func(what string, want ...Frame) {
		t.Helper()
		for _, c := range []*Conn{whole, narrowed} {
			if got := c.TakePending(); !framesAre(got, want...) {
				t.Fatalf("%s, account %s: frames = %+v, want %+v", what, c.userID, got, want)
			}
		}
	}

	src.moved()
	tick(h)
	both("a genre's wake or a spare one", bareCatalog)

	src.replaced()
	tick(h)
	both("a wake with no row", bareCatalog)

	whole.Mark(TypeInvalidate, TopicCatalog)
	narrowed.Mark(TypeInvalidate, TopicCatalog)
	both("the subscribe-time invalidation", bareCatalog)

	h.MarkCatalogReplaced()
	src.moved()
	tick(h)
	both("a wake beside a resync", resyncAll, bareCatalog)
}

// An invalidation with no names of its own says nothing about entities,
// so names it shares a frame with are kept, whichever came first: a
// genre-only tick, a spare wake, the subscribe-time mark.
func TestNamesAreKeptBesideAnInvalidationWithNone(t *testing.T) {
	src := newMovingSource()
	h := New(src)
	c := h.Register("u1", "se-u1", nil)
	kept := func(what string) {
		t.Helper()
		if got := c.TakePending(); !framesAre(got, namedCatalog("ar-a")) {
			t.Fatalf("%s: frames = %+v, want the name kept", what, got)
		}
	}

	src.moved("ar-a")
	tick(h)
	src.moved()
	tick(h)
	kept("names then a genre-only tick")

	src.moved()
	tick(h)
	src.moved("ar-a")
	tick(h)
	kept("a genre-only tick then names")

	// The wake a row sent after the hub took the last one, its row
	// already in that answer: the next tick has nothing behind it.
	src.moved("ar-a")
	<-src.CatalogWakeups()
	src.wakeHub()
	tick(h)
	tick(h)
	kept("names then a spare wake")

	c.markCatalog(names("ar-a"))
	c.Mark(TypeInvalidate, TopicCatalog)
	kept("names then the subscribe-time mark")

	c.Mark(TypeInvalidate, TopicCatalog)
	c.markCatalog(names("ar-a"))
	kept("the subscribe-time mark then names")
}

// A resync, and a wake no row stood behind, say the catalog may be
// another one: names that share a frame with either, whichever came
// first, are dropped, and the frame says entities went unnamed. So does
// the source's own word that it left some out.
func TestNamesAreDroppedBesideAResyncOrAnUnknownCatalog(t *testing.T) {
	src := newMovingSource()
	h := New(src)
	c := h.Register("u1", "se-u1", nil)

	src.moved("ar-a")
	tick(h)
	src.replaced()
	tick(h)
	if got := c.TakePending(); !framesAre(got, unnamedCatalog) {
		t.Fatalf("names then a wake with no row: frames = %+v, want the unnamed frame", got)
	}

	src.replaced()
	tick(h)
	src.moved("ar-a")
	tick(h)
	if got := c.TakePending(); !framesAre(got, unnamedCatalog) {
		t.Fatalf("a wake with no row then names: frames = %+v, want the unnamed frame", got)
	}

	c.markCatalog(names("ar-a"))
	h.MarkCatalogReplaced()
	if got := c.TakePending(); !framesAre(got, resyncAll, unnamedCatalog) {
		t.Fatalf("names then a resync: frames = %+v, want the resync and the unnamed frame", got)
	}

	h.MarkCatalogReplaced()
	c.markCatalog(names("ar-b"))
	if got := c.TakePending(); !framesAre(got, resyncAll, unnamedCatalog) {
		t.Fatalf("a resync then names: frames = %+v, want the resync and the unnamed frame", got)
	}

	c.markCatalog(names("ar-a"))
	c.markCatalog(catalogMove{unnamed: true})
	c.markCatalog(names("ar-b"))
	if got := c.TakePending(); !framesAre(got, unnamedCatalog) {
		t.Fatalf("names around the source's flag: frames = %+v, want the unnamed frame", got)
	}

	c.markCatalog(names("ar-a"))
	if got := c.TakePending(); !framesAre(got, namedCatalog("ar-a")) {
		t.Fatalf("frames once all that was taken = %+v, want names again", got)
	}
}

// An account that cannot decide a frame's names is sent the unnamed
// frame exactly where an account that sees everything is sent names or
// the unnamed frame, and the bare frame where that one is.
func TestAnAccountThatCannotDecideItsNamesIsSentUnnamed(t *testing.T) {
	for _, tc := range []struct {
		name  string
		wake  func(*movingSource)
		whole Frame
		want  Frame
	}{
		{"named", func(s *movingSource) { s.moved("ar-a") }, namedCatalog("ar-a"), unnamedCatalog},
		{"more than fit", func(s *movingSource) { s.couldNotName("ar-a") }, unnamedCatalog, unnamedCatalog},
		{"more than a frame names", func(s *movingSource) { s.moved(somePIDs("A", MaxCatalogPIDs+1)...) }, unnamedCatalog, unnamedCatalog},
		{"a failed read", func(s *movingSource) { s.couldNotName() }, unnamedCatalog, unnamedCatalog},
		{"nothing to name", func(s *movingSource) { s.moved() }, bareCatalog, bareCatalog},
		{"a wake with no row", func(s *movingSource) { s.replaced() }, bareCatalog, bareCatalog},
	} {
		src := newMovingSource()
		src.narrow("u2", true)
		h := New(src)
		whole := h.Register("u1", "se-u1", nil)
		narrowed := h.Register("u2", "se-u2", nil)
		tc.wake(src)
		tick(h)
		if got := whole.TakePending(); !framesAre(got, tc.whole) {
			t.Errorf("%s, an account that sees everything: frames = %+v, want %+v", tc.name, got, tc.whole)
		}
		if got := narrowed.TakePending(); !framesAre(got, tc.want) {
			t.Errorf("%s, a narrowed account: frames = %+v, want %+v", tc.name, got, tc.want)
		}
	}
}

// An account told only some of a frame's names is sent those, beside its
// cursor; told none of them, the bare frame, which says nothing of
// entities and is not unchanged, live and in answer to a subscribe
// alike. An account that sees everything is sent them all.
func TestAnAccountIsSentTheNamesItMayBeTold(t *testing.T) {
	src := newMovingSource()
	src.sees["u2"] = []string{"al-a", "tr-a"}
	h := New(src)
	whole := h.Register("u1", "se-u1", nil)
	narrowed := h.Register("u2", "se-u2", nil)
	src.at(1, "p1")

	src.moved("tr-a", "al-a", "tr-b", "al-b")
	tick(h)
	if got := whole.TakePending(); !framesAre(got, sinceCatalog(namedCatalog("al-a", "al-b", "tr-a", "tr-b"), "u1@p1")) {
		t.Fatalf("an account that sees everything: frames = %+v, want every name", got)
	}
	if got := narrowed.TakePending(); !framesAre(got, sinceCatalog(namedCatalog("al-a", "tr-a"), "u2@p1")) {
		t.Fatalf("a narrowed account: frames = %+v, want the names it sees", got)
	}

	src.moved("tr-b", "al-b")
	tick(h)
	if got := narrowed.TakePending(); !framesAre(got, sinceCatalog(bareCatalog, "u2@p1")) {
		t.Fatalf("names it sees none of: frames = %+v, want the bare frame", got)
	}

	src.since = sinceAnswer{pids: []string{"al-b", "tr-a", "tr-b"}, order: 2, pos: "p2"}
	narrowed.MarkCatalogSince("cur")
	if got := narrowed.TakePending(); !framesAre(got, sinceCatalog(namedCatalog("tr-a"), "u2@p2")) {
		t.Fatalf("a subscribe behind names: frames = %+v, want the one it sees", got)
	}
	src.since = sinceAnswer{pids: []string{"tr-b"}, order: 2, pos: "p2"}
	narrowed.MarkCatalogSince("cur")
	if got := narrowed.TakePending(); !framesAre(got, sinceCatalog(bareCatalog, "u2@p2")) {
		t.Fatalf("a subscribe behind a name it does not see: frames = %+v, want the bare frame", got)
	}
}

// The account is read as the frame is built: narrowing one under a
// connection that already holds names takes them out of its next frame,
// and widening one puts them in.
func TestTheAccountIsAskedAsTheFrameIsBuilt(t *testing.T) {
	src := newMovingSource()
	src.narrow("u2", true)
	h := New(src)
	whole := h.Register("u1", "se-u1", nil)
	narrowed := h.Register("u2", "se-u2", nil)

	whole.markCatalog(names("ar-b"))
	src.narrow("u1", true)
	if got := whole.TakePending(); !framesAre(got, unnamedCatalog) {
		t.Fatalf("narrowed while names were pending: frames = %+v, want the unnamed frame", got)
	}

	src.narrow("u2", false)
	narrowed.markCatalog(names("ar-c"))
	if got := narrowed.TakePending(); !framesAre(got, namedCatalog("ar-c")) {
		t.Fatalf("widened: frames = %+v, want the name", got)
	}
}

// A hub with no source cannot ask who sees what, so it names nothing.
func TestAHubWithNoSourceNamesNothing(t *testing.T) {
	h := New(nil)
	c := h.Register("u1", "se-u1", nil)
	c.markCatalog(names("ar-a"))
	if got := c.TakePending(); !framesAre(got, unnamedCatalog) {
		t.Fatalf("frames = %+v, want the unnamed frame", got)
	}
}

// sinceCatalog is the frame f carrying the cursor since.
func sinceCatalog(f Frame, since string) Frame {
	f.Since = since
	return f
}

// A catalog invalidation carries the position it covers up to, as the
// account's cursor, read as the frame is built: the newest of the moves
// a slow connection holds, whichever order they were queued in, and of
// two at one position the one covering the newer show cover move, or
// the one queued later where they cover the same. A
// narrowed account is sent its cursor beside unnamed, an account that
// could not be read none, and a move with no position leaves the one
// held.
func TestACatalogFrameCarriesTheNewestPositionItCovers(t *testing.T) {
	src := newMovingSource()
	src.narrow("u2", true)
	h := New(src)
	whole := h.Register("u1", "se-u1", nil)
	narrowed := h.Register("u2", "se-u2", nil)
	unread := h.Register("u3", "se-u3", nil)
	src.unreadable["u3"] = true

	src.at(1, "p1")
	src.moved("ar-a")
	tick(h)
	src.at(2, "p2")
	src.moved("ar-b")
	tick(h)
	src.moved()
	src.at(0, "")
	tick(h)
	if got := whole.TakePending(); !framesAre(got, sinceCatalog(namedCatalog("ar-a", "ar-b"), "u1@p2")) {
		t.Fatalf("a slow connection: frames = %+v, want both names and the newest position", got)
	}
	if got := narrowed.TakePending(); !framesAre(got, sinceCatalog(unnamedCatalog, "u2@p2")) {
		t.Fatalf("a narrowed account: frames = %+v, want unnamed and its cursor", got)
	}
	if got := unread.TakePending(); !framesAre(got, unnamedCatalog) {
		t.Fatalf("an account that could not be read: frames = %+v, want unnamed and no cursor", got)
	}

	whole.markCatalog(catalogMove{pids: []string{"ar-c"}, order: 5, pos: "p5"})
	whole.markCatalog(catalogMove{order: 4, pos: "p4"})
	if got := whole.TakePending(); !framesAre(got, sinceCatalog(namedCatalog("ar-c"), "u1@p5")) {
		t.Fatalf("an older position queued after a newer one: frames = %+v, want the newer", got)
	}
	whole.markCatalog(catalogMove{order: 6, pos: "p6a"})
	whole.markCatalog(catalogMove{order: 6, pos: "p6b"})
	if got := whole.TakePending(); !framesAre(got, sinceCatalog(bareCatalog, "u1@p6b")) {
		t.Fatalf("two moves at one position: frames = %+v, want the later's", got)
	}
	src.at(7, "p7-live")
	src.coverAt(9)
	src.moved()
	tick(h)
	src.since = sinceAnswer{order: 7, cover: 8, pos: "p7-answer"}
	whole.MarkCatalogSince("cur")
	if got := whole.TakePending(); !framesAre(got, sinceCatalog(bareCatalog, "u1@p7-live")) {
		t.Fatalf("an answer queued after a live move at its position with a newer cover: frames = %+v, want the live move's", got)
	}
	whole.Mark(TypeInvalidate, TopicCatalog)
	if got := whole.TakePending(); !framesAre(got, bareCatalog) {
		t.Fatalf("after a take, a frame with no position: frames = %+v, want no cursor", got)
	}
}

// A subscribe that presents a catalog cursor is answered on the caller's
// goroutine, before it returns, by what the source says changed after it,
// joined to what the connection is owed by the rules every catalog move
// follows. A connection not subscribed to the catalog asks nothing.
func TestASubscribingCursorIsAnsweredAsAMove(t *testing.T) {
	src := newMovingSource()
	h := New(src)
	c := h.Register("u1", "se-u1", nil)

	src.since = sinceAnswer{pids: []string{"tr-a", "al-a"}, order: 3, pos: "p3"}
	c.MarkCatalogSince("cur")
	if len(src.asked) != 1 || src.asked[0] != "u1@cur" {
		t.Fatalf("the source was asked %v, want the account's cursor once, before the call returned", src.asked)
	}
	if got := c.TakePending(); !framesAre(got, sinceCatalog(namedCatalog("al-a", "tr-a"), "u1@p3")) {
		t.Fatalf("behind two changes: frames = %+v, want them named with the answer's position", got)
	}

	src.since = sinceAnswer{order: 3, pos: "p3"}
	c.MarkCatalogSince("u1@p3")
	if got := c.TakePending(); !framesAre(got, sinceCatalog(bareCatalog, "u1@p3")) {
		t.Fatalf("at the head: frames = %+v, want the bare frame and its position", got)
	}

	src.since = sinceAnswer{unnamed: true, order: 3, pos: "p3"}
	c.markCatalog(catalogMove{pids: []string{"ar-x"}, order: 4, pos: "p4"})
	c.MarkCatalogSince("stale")
	if got := c.TakePending(); !framesAre(got, sinceCatalog(unnamedCatalog, "u1@p4")) {
		t.Fatalf("an unservable cursor beside a live move: frames = %+v, want unnamed and the live position", got)
	}

	src.since = sinceAnswer{pids: somePIDs("s", MaxCatalogPIDs+1), order: 3, pos: "p3"}
	c.MarkCatalogSince("far")
	if got := c.TakePending(); !framesAre(got, sinceCatalog(unnamedCatalog, "u1@p3")) {
		t.Fatalf("more names than a frame holds: frames = %+v, want unnamed", got)
	}

	other := h.Register("u2", "se-u2", []string{TopicUser})
	src.asked = nil
	other.MarkCatalogSince("cur")
	if len(src.asked) != 0 || other.TakePending() != nil {
		t.Fatalf("a connection not subscribed to the catalog asked %v or was sent a frame", src.asked)
	}

	bare := New(nil).Register("u1", "se-u1", nil)
	bare.MarkCatalogSince("cur")
	if got := bare.TakePending(); !framesAre(got, bareCatalog) {
		t.Fatalf("a hub with no source: frames = %+v, want the bare frame", got)
	}
}

// The account's rules are read only for a frame that has names to decide
// on: a bare or unnamed frame asks for its cursor alone.
func TestTheAccountIsReadOnlyForAFrameWithNames(t *testing.T) {
	src := newMovingSource()
	h := New(src)
	c := h.Register("u1", "se-u1", nil)

	c.markCatalog(catalogMove{order: 1, pos: "p1"})
	if got := c.TakePending(); !framesAre(got, sinceCatalog(bareCatalog, "u1@p1")) || src.accountReads != 0 {
		t.Fatalf("a bare frame: frames = %+v, %d account reads, want its cursor and none", got, src.accountReads)
	}
	c.markCatalog(catalogMove{unnamed: true, order: 2, pos: "p2"})
	if got := c.TakePending(); !framesAre(got, sinceCatalog(unnamedCatalog, "u1@p2")) || src.accountReads != 0 {
		t.Fatalf("an unnamed frame: frames = %+v, %d account reads, want its cursor and none", got, src.accountReads)
	}
	c.markCatalog(catalogMove{pids: []string{"ar-a"}, order: 3, pos: "p3"})
	if got := c.TakePending(); !framesAre(got, sinceCatalog(namedCatalog("ar-a"), "u1@p3")) || src.accountReads != 1 {
		t.Fatalf("a named frame: frames = %+v, %d account reads, want the name and one", got, src.accountReads)
	}
}

// unchangedCatalog is the answer to a subscribing cursor nothing in the
// catalog moved after, at the account's cursor for p3.
var unchangedCatalog = Frame{Type: TypeInvalidate, Topic: TopicCatalog, Unchanged: true, Since: "u1@p3"}

// The frame says nothing changed only when all it holds is answers that
// each said so. Anything else coalesced with one, in either order, takes
// that away and leaves the frame as it would be without the answer: a
// live move naming nothing, a plain mark, a named move, an unnamed one,
// or a resync.
func TestOnlyAnswersThatSayNothingChangedMakeAnUnchangedFrame(t *testing.T) {
	src := newMovingSource()
	h := New(src)
	c := h.Register("u1", "se-u1", nil)
	src.since = sinceAnswer{unchanged: true, order: 3, pos: "p3"}
	answered := sinceCatalog(bareCatalog, "u1@p3")

	c.MarkCatalogSince("cur")
	if got := c.TakePending(); !framesAre(got, unchangedCatalog) {
		t.Fatalf("the answer alone: frames = %+v, want it unchanged", got)
	}
	c.MarkCatalogSince("cur")
	c.MarkCatalogSince("cur")
	if got := c.TakePending(); !framesAre(got, unchangedCatalog) {
		t.Fatalf("two answers: frames = %+v, want them unchanged", got)
	}

	for _, tc := range []struct {
		name  string
		other func()
		want  []Frame
	}{
		{"a live move naming nothing", func() { src.moved(); tick(h) }, []Frame{answered}},
		{"a plain mark", func() { c.Mark(TypeInvalidate, TopicCatalog) }, []Frame{answered}},
		{"a named move", func() { c.markCatalog(names("ar-a")) }, []Frame{sinceCatalog(namedCatalog("ar-a"), "u1@p3")}},
		{"an unnamed move", func() { c.markCatalog(catalogMove{unnamed: true}) }, []Frame{sinceCatalog(unnamedCatalog, "u1@p3")}},
		{"a resync of the catalog", func() { c.Mark(TypeResync, TopicCatalog) }, []Frame{{Type: TypeResync, Topic: TopicCatalog}, answered}},
		{"a resync of every stream", func() { h.MarkCatalogReplaced() }, []Frame{resyncAll, answered}},
	} {
		tc.other()
		c.MarkCatalogSince("cur")
		if got := c.TakePending(); !framesAre(got, tc.want...) {
			t.Errorf("%s, then the answer: frames = %+v, want %+v", tc.name, got, tc.want)
		}
		c.MarkCatalogSince("cur")
		tc.other()
		if got := c.TakePending(); !framesAre(got, tc.want...) {
			t.Errorf("the answer, then %s: frames = %+v, want %+v", tc.name, got, tc.want)
		}
	}

	c.Mark(TypeInvalidate, TopicUser)
	c.MarkCatalogSince("cur")
	if got := c.TakePending(); !framesAre(got, unchangedCatalog, Frame{Type: TypeInvalidate, Topic: TopicUser}) {
		t.Fatalf("beside another topic: frames = %+v, want the catalog's unchanged", got)
	}
	c.MarkCatalogSince("cur")
	c.TakePending()
	c.Mark(TypeInvalidate, TopicCatalog)
	if got := c.TakePending(); !framesAre(got, bareCatalog) {
		t.Fatalf("a mark after the answer was taken: frames = %+v, want the bare frame", got)
	}
}
