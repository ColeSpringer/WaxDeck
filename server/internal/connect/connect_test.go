package connect

import (
	"context"
	"encoding/json"
	"errors"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// fakeDriver records calls and lets tests push events.
type fakeDriver struct {
	mu       sync.Mutex
	loads    []fakeLoad
	verbs    []string
	seeks    []int64
	vols     []float64
	events   chan DriverEvent
	closed   bool
	failLoad bool
}

type fakeLoad struct {
	items      []MediaItem
	index      int
	positionMS int64
	play       bool
}

// formatDriver is a fakeDriver that also declares what its endpoint
// plays, the way the DLNA driver does after reading ProtocolInfo.
type formatDriver struct {
	*fakeDriver
	accepts []string
}

func (d *formatDriver) AcceptedFormats() []string { return d.accepts }

func newFakeDriver() *fakeDriver {
	return &fakeDriver{events: make(chan DriverEvent, 32)}
}

func (d *fakeDriver) Load(_ context.Context, items []MediaItem, index int, positionMS int64, play bool) error {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.failLoad {
		return errors.New("device refused the load")
	}
	d.loads = append(d.loads, fakeLoad{items: items, index: index, positionMS: positionMS, play: play})
	return nil
}
func (d *fakeDriver) Play(context.Context) error  { return d.verb("play") }
func (d *fakeDriver) Pause(context.Context) error { return d.verb("pause") }
func (d *fakeDriver) Stop(context.Context) error  { return d.verb("stop") }
func (d *fakeDriver) SeekTo(_ context.Context, positionMS int64) error {
	d.mu.Lock()
	defer d.mu.Unlock()
	d.seeks = append(d.seeks, positionMS)
	return nil
}
func (d *fakeDriver) SetVolume(_ context.Context, v float64) error {
	d.mu.Lock()
	defer d.mu.Unlock()
	d.vols = append(d.vols, v)
	return nil
}
func (d *fakeDriver) SetRate(context.Context, float64) error { return errors.New("no rate") }
func (d *fakeDriver) Events() <-chan DriverEvent             { return d.events }
func (d *fakeDriver) Close() error {
	d.mu.Lock()
	defer d.mu.Unlock()
	d.closed = true
	return nil
}
func (d *fakeDriver) verb(v string) error {
	d.mu.Lock()
	defer d.mu.Unlock()
	d.verbs = append(d.verbs, v)
	return nil
}
func (d *fakeDriver) lastLoad(t *testing.T) fakeLoad {
	t.Helper()
	d.mu.Lock()
	defer d.mu.Unlock()
	if len(d.loads) == 0 {
		t.Fatal("no load recorded")
	}
	return d.loads[len(d.loads)-1]
}

// fakeResolver serves a fixed catalog of entries and records the
// endpoint target each load resolved against.
type fakeResolver struct {
	entries map[string]QueueEntry

	mu      sync.Mutex
	targets []EndpointTarget
}

func (r *fakeResolver) Entries(_ context.Context, _ string, pids []string) ([]QueueEntry, error) {
	out := make([]QueueEntry, 0, len(pids))
	for _, pid := range pids {
		e, ok := r.entries[pid]
		if !ok {
			return nil, ErrNotFound
		}
		out = append(out, e)
	}
	return out, nil
}

func (r *fakeResolver) StreamItems(_ context.Context, _ string, entries []QueueEntry, target EndpointTarget, base string, _ time.Duration) ([]MediaItem, error) {
	r.mu.Lock()
	r.targets = append(r.targets, target)
	r.mu.Unlock()
	out := make([]MediaItem, 0, len(entries))
	for _, e := range entries {
		out = append(out, MediaItem{PID: e.PID, URL: base + "/media/" + e.PID, MimeType: "audio/flac", Title: e.Title, DurationMS: e.DurationMS})
	}
	return out, nil
}

// lastTarget reports the target the most recent load resolved against.
func (r *fakeResolver) lastTarget() (EndpointTarget, bool) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if len(r.targets) == 0 {
		return EndpointTarget{}, false
	}
	return r.targets[len(r.targets)-1], true
}

func (r *fakeResolver) Timeline(context.Context, string, []QueueEntry, float64, string) (*TimelineMedia, error) {
	return nil, nil
}

// fakeSink records write-through calls.
type fakeSink struct {
	mu          sync.Mutex
	checkpoints []string
	queues      [][]string
	listens     []string
}

func (s *fakeSink) Progress(string, string, int64) {}
func (s *fakeSink) Checkpoint(_ context.Context, _, pid string, _ int64) {
	s.mu.Lock()
	s.checkpoints = append(s.checkpoints, pid)
	s.mu.Unlock()
}
func (s *fakeSink) SetQueue(_ context.Context, _ string, pids []string) {
	s.mu.Lock()
	s.queues = append(s.queues, pids)
	s.mu.Unlock()
}
func (s *fakeSink) Listen(_ context.Context, _, pid string, _ int64, _ time.Time) {
	s.mu.Lock()
	s.listens = append(s.listens, pid)
	s.mu.Unlock()
}

func newTestService(t *testing.T) (*Service, *fakeSink, *fakeDriver) {
	t.Helper()
	ctx := context.Background()
	store, err := db.Open(ctx, filepath.Join(t.TempDir(), "waxdeck.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { store.Close() })
	// The db package requires user rows for the sessions foreign key.
	seedUser(t, store, "us-alice", "alice")
	seedUser(t, store, "us-bob", "bob")

	sink := &fakeSink{}
	resolver := &fakeResolver{entries: map[string]QueueEntry{
		"tr-one":   {PID: "tr-one", Title: "One", DurationMS: 60000},
		"tr-two":   {PID: "tr-two", Title: "Two", DurationMS: 90000},
		"tr-three": {PID: "tr-three", Title: "Three", DurationMS: 30000},
	}}
	group := supervise.NewGroup(nil)
	svc, err := New(ctx, Config{
		Store:    store,
		Group:    group,
		Resolver: resolver,
		Sink:     sink,
		Bases:    Bases{Public: "http://public.example", LAN: "http://192.0.2.10:4420", Loopback: "http://127.0.0.1:4420"},
	})
	if err != nil {
		t.Fatal(err)
	}
	driver := newFakeDriver()
	if _, err := svc.EndpointOnline(ctx, KindCast, "cast-dev-1", "Kitchen speaker", "192.0.2.50:8009", true, false,
		func(context.Context) (Driver, error) { return driver, nil }); err != nil {
		t.Fatal(err)
	}
	return svc, sink, driver
}

func seedUser(t *testing.T, store *db.DB, id, name string) {
	t.Helper()
	if _, err := store.Writer().Exec(`
		INSERT INTO users (id, username, username_ci, roles, library_access, waxbin_user_pid, created_at_ns, updated_at_ns)
		VALUES (?, ?, ?, 'user', 'all', ?, 1, 1)`, id, name, name, "wb-"+name); err != nil {
		t.Fatal(err)
	}
}

func deviceEndpointID(t *testing.T, svc *Service, userID string) string {
	t.Helper()
	for _, ep := range svc.Endpoints(userID) {
		if ep.Kind == KindCast {
			return ep.ID
		}
	}
	t.Fatal("no cast endpoint registered")
	return ""
}

func TestCreateSessionOnDevice(t *testing.T) {
	svc, sink, driver := newTestService(t)
	ctx := context.Background()
	epID := deviceEndpointID(t, svc, "us-alice")

	snap, err := svc.CreateSession(ctx, "us-alice", "Alice", epID, []string{"tr-one", "tr-two"}, 1, 5000, true)
	if err != nil {
		t.Fatal(err)
	}
	if snap.EndpointID != epID || snap.Index != 1 || !snap.Playing {
		t.Fatalf("unexpected snapshot %+v", snap)
	}
	if len(snap.Entries) != 2 || snap.Entries[0].Title != "One" {
		t.Fatalf("entries not hydrated: %+v", snap.Entries)
	}
	load := driver.lastLoad(t)
	if load.index != 1 || load.positionMS != 5000 || !load.play || len(load.items) != 2 {
		t.Fatalf("driver load %+v", load)
	}
	// The public base is preferred for cast endpoints.
	if got := load.items[0].URL; got != "http://public.example/media/tr-one" {
		t.Fatalf("media URL %q", got)
	}
	sink.mu.Lock()
	queues := len(sink.queues)
	sink.mu.Unlock()
	if queues != 1 {
		t.Fatalf("queue mirror writes = %d, want 1", queues)
	}

	// The session lists for its owner and for another user (shared
	// endpoint), and the endpoint reports it active.
	if got := len(svc.Sessions("us-alice")); got != 1 {
		t.Fatalf("owner sees %d sessions", got)
	}
	if got := len(svc.Sessions("us-bob")); got != 1 {
		t.Fatalf("second user sees %d sessions on the shared endpoint", got)
	}
	if id := svc.ActiveSessionID("us-bob", epID); id != snap.ID {
		t.Fatalf("active session id %q, want %q", id, snap.ID)
	}
}

// TestEndpointTargetCarriesDeclaredFormats covers the plumbing D2 needs:
// what a driver says its endpoint plays has to survive the trip to the
// resolver, which is the only place that can act on it. A driver that
// declares nothing must leave the target's format list empty rather than
// inventing a constraint.
func TestEndpointTargetCarriesDeclaredFormats(t *testing.T) {
	ctx := context.Background()
	store, err := db.Open(ctx, filepath.Join(t.TempDir(), "waxdeck.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { store.Close() })
	seedUser(t, store, "us-alice", "alice")
	resolver := &fakeResolver{entries: map[string]QueueEntry{
		"tr-one": {PID: "tr-one", Title: "One", DurationMS: 60000},
	}}
	svc, err := New(ctx, Config{
		Store:    store,
		Group:    supervise.NewGroup(nil),
		Resolver: resolver,
		Sink:     &fakeSink{},
		Bases:    Bases{LAN: "http://192.0.2.10:4420"},
	})
	if err != nil {
		t.Fatal(err)
	}
	talkative := &formatDriver{fakeDriver: newFakeDriver(), accepts: []string{"audio/x-flac", "audio/mpeg"}}
	if _, err := svc.EndpointOnline(ctx, KindDLNA, "dlna-1", "Talkative renderer", "192.0.2.60:8080", true, false,
		func(context.Context) (Driver, error) { return talkative, nil }); err != nil {
		t.Fatal(err)
	}
	silent := newFakeDriver()
	if _, err := svc.EndpointOnline(ctx, KindDLNA, "dlna-2", "Silent renderer", "192.0.2.61:8080", true, false,
		func(context.Context) (Driver, error) { return silent, nil }); err != nil {
		t.Fatal(err)
	}
	byName := map[string]string{}
	for _, ep := range svc.Endpoints("us-alice") {
		byName[ep.Name] = ep.ID
	}

	if _, err := svc.CreateSession(ctx, "us-alice", "Alice", byName["Talkative renderer"], []string{"tr-one"}, 0, 0, true); err != nil {
		t.Fatal(err)
	}
	target, ok := resolver.lastTarget()
	if !ok {
		t.Fatal("no target recorded")
	}
	if target.Kind != KindDLNA {
		t.Fatalf("target kind = %q, want %q", target.Kind, KindDLNA)
	}
	if len(target.Formats) != 2 || target.Formats[0] != "audio/x-flac" {
		t.Fatalf("declared formats did not reach the resolver: %v", target.Formats)
	}

	if _, err := svc.CreateSession(ctx, "us-alice", "Alice", byName["Silent renderer"], []string{"tr-one"}, 0, 0, true); err != nil {
		t.Fatal(err)
	}
	target, _ = resolver.lastTarget()
	if len(target.Formats) != 0 {
		t.Fatalf("a driver that declares nothing must constrain nothing, got %v", target.Formats)
	}
}

func TestCreateSessionValidation(t *testing.T) {
	svc, _, _ := newTestService(t)
	ctx := context.Background()
	epID := deviceEndpointID(t, svc, "us-alice")

	if _, err := svc.CreateSession(ctx, "us-alice", "Alice", epID, nil, 0, 0, true); err == nil {
		t.Fatal("empty queue accepted")
	}
	if _, err := svc.CreateSession(ctx, "us-alice", "Alice", epID, []string{"tr-one"}, 3, 0, true); err == nil {
		t.Fatal("out-of-range index accepted")
	}
	if _, err := svc.CreateSession(ctx, "us-alice", "Alice", "pe-missing", []string{"tr-one"}, 0, 0, true); !errors.Is(err, ErrNotFound) {
		t.Fatalf("missing endpoint error %v", err)
	}
	if _, err := svc.CreateSession(ctx, "us-alice", "Alice", epID, []string{"tr-unknown"}, 0, 0, true); !errors.Is(err, ErrNotFound) {
		t.Fatalf("invisible item error %v", err)
	}
}

func TestSessionReplacesOnSameEndpoint(t *testing.T) {
	svc, _, _ := newTestService(t)
	ctx := context.Background()
	epID := deviceEndpointID(t, svc, "us-alice")

	first, err := svc.CreateSession(ctx, "us-alice", "Alice", epID, []string{"tr-one"}, 0, 0, true)
	if err != nil {
		t.Fatal(err)
	}
	second, err := svc.CreateSession(ctx, "us-bob", "Bob", epID, []string{"tr-two"}, 0, 0, true)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Session("us-alice", first.ID); !errors.Is(err, ErrNotFound) {
		t.Fatalf("replaced session still resolves: %v", err)
	}
	sessions := svc.Sessions("us-alice")
	if len(sessions) != 1 || sessions[0].ID != second.ID {
		t.Fatalf("sessions after replace: %+v", sessions)
	}
}

func TestDriverEventsAdvanceSession(t *testing.T) {
	svc, sink, driver := newTestService(t)
	ctx := context.Background()
	epID := deviceEndpointID(t, svc, "us-alice")

	snap, err := svc.CreateSession(ctx, "us-alice", "Alice", epID, []string{"tr-one", "tr-two"}, 0, 0, true)
	if err != nil {
		t.Fatal(err)
	}

	// Position advances within the first entry.
	driver.events <- DriverEvent{At: time.Now(), Playing: true, Index: 0, PositionMS: 30000}
	waitFor(t, func() bool {
		s, err := svc.Session("us-alice", snap.ID)
		return err == nil && s.PositionMS >= 30000
	})

	// The device advances to the second entry: index moves and the
	// first entry's position checkpoints.
	driver.events <- DriverEvent{At: time.Now(), Playing: true, Index: 1, PositionMS: 0}
	waitFor(t, func() bool {
		s, err := svc.Session("us-alice", snap.ID)
		return err == nil && s.Index == 1
	})
	waitFor(t, func() bool {
		sink.mu.Lock()
		defer sink.mu.Unlock()
		return len(sink.checkpoints) > 0
	})

	// A fatal event ends the session.
	driver.events <- DriverEvent{At: time.Now(), Fatal: true, Err: errors.New("device gone")}
	waitFor(t, func() bool {
		_, err := svc.Session("us-alice", snap.ID)
		return errors.Is(err, ErrNotFound)
	})
}

func TestRemoteCommands(t *testing.T) {
	svc, _, driver := newTestService(t)
	ctx := context.Background()
	epID := deviceEndpointID(t, svc, "us-alice")

	snap, err := svc.CreateSession(ctx, "us-alice", "Alice", epID, []string{"tr-one", "tr-two"}, 0, 0, true)
	if err != nil {
		t.Fatal(err)
	}
	link := NewClientLink("us-alice", "Alice", "se-controller", "Phone", func(any) bool { return true })

	if _, err := svc.HandleCommand(ctx, link, snap.ID, "pause", CommandArgs{}); err != nil {
		t.Fatal(err)
	}
	pos := int64(42000)
	if _, err := svc.HandleCommand(ctx, link, snap.ID, "seek", CommandArgs{PositionMS: &pos}); err != nil {
		t.Fatal(err)
	}
	vol := 0.5
	if _, err := svc.HandleCommand(ctx, link, snap.ID, "set-volume", CommandArgs{Volume: &vol}); err != nil {
		t.Fatal(err)
	}
	got, err := svc.Session("us-alice", snap.ID)
	if err != nil {
		t.Fatal(err)
	}
	if got.Playing {
		t.Fatal("still playing after pause")
	}
	if got.PositionMS != 42000 {
		t.Fatalf("position %d after seek", got.PositionMS)
	}
	if got.Volume == nil || *got.Volume != 0.5 {
		t.Fatalf("volume %+v", got.Volume)
	}
	driver.mu.Lock()
	verbs := append([]string(nil), driver.verbs...)
	seeks := append([]int64(nil), driver.seeks...)
	vols := append([]float64(nil), driver.vols...)
	driver.mu.Unlock()
	if len(verbs) == 0 || verbs[0] != "pause" || len(seeks) != 1 || seeks[0] != 42000 || len(vols) != 1 {
		t.Fatalf("driver calls verbs=%v seeks=%v vols=%v", verbs, seeks, vols)
	}

	// Rate control is flagged off for this endpoint.
	rate := 1.5
	if _, err := svc.HandleCommand(ctx, link, snap.ID, "set-rate", CommandArgs{Rate: &rate}); err == nil {
		t.Fatal("set-rate accepted on a rateControl=false endpoint")
	}

	// next moves to the second entry via a reload.
	if _, err := svc.HandleCommand(ctx, link, snap.ID, "next", CommandArgs{}); err != nil {
		t.Fatal(err)
	}
	got, _ = svc.Session("us-alice", snap.ID)
	if got.Index != 1 {
		t.Fatalf("index %d after next", got.Index)
	}
	// next past the end refuses with repeat off.
	if _, err := svc.HandleCommand(ctx, link, snap.ID, "next", CommandArgs{}); err == nil {
		t.Fatal("next past the end accepted")
	}
}

func TestRepeatReloadFailureSettlesStopped(t *testing.T) {
	svc, _, driver := newTestService(t)
	ctx := context.Background()
	epID := deviceEndpointID(t, svc, "us-alice")

	snap, err := svc.CreateSession(ctx, "us-alice", "Alice", epID, []string{"tr-one", "tr-two"}, 0, 0, true)
	if err != nil {
		t.Fatal(err)
	}
	link := NewClientLink("us-alice", "Alice", "se-x", "Phone", func(any) bool { return true })
	repeat := "all"
	if _, err := svc.HandleCommand(ctx, link, snap.ID, "set-repeat", CommandArgs{Repeat: repeat}); err != nil {
		t.Fatal(err)
	}

	// The whole load runs out while the device refuses the repeat
	// reload: the session must settle stopped, never read playing.
	driver.mu.Lock()
	driver.failLoad = true
	driver.mu.Unlock()
	driver.events <- DriverEvent{At: time.Now(), Playing: false, Index: 1, PositionMS: 0, Finished: true}
	waitFor(t, func() bool {
		s, err := svc.Session("us-alice", snap.ID)
		return err == nil && !s.Playing
	})
}

func TestCommandVisibility(t *testing.T) {
	svc, _, _ := newTestService(t)
	ctx := context.Background()
	epID := deviceEndpointID(t, svc, "us-alice")

	snap, err := svc.CreateSession(ctx, "us-alice", "Alice", epID, []string{"tr-one"}, 0, 0, true)
	if err != nil {
		t.Fatal(err)
	}
	// Bob can control the session on the shared endpoint.
	bob := NewClientLink("us-bob", "Bob", "se-bob", "Tablet", func(any) bool { return true })
	if _, err := svc.HandleCommand(ctx, bob, snap.ID, "pause", CommandArgs{}); err != nil {
		t.Fatalf("shared-endpoint control refused: %v", err)
	}
	// The other-user snapshot names the owner.
	s, err := svc.Session("us-bob", snap.ID)
	if err != nil {
		t.Fatal(err)
	}
	if s.OwnerName != "Alice" {
		t.Fatalf("owner name %q", s.OwnerName)
	}
}

func TestMirrorSessionLifecycle(t *testing.T) {
	svc, sink, _ := newTestService(t)
	ctx := context.Background()

	var sent []any
	link := NewClientLink("us-alice", "Alice", "se-phone", "Phone", func(v any) bool {
		sent = append(sent, v)
		return true
	})
	svc.HandleRegister(link, "Alice's phone", true, true)

	// A creating report without a queue is ignored.
	if snap, answer := svc.HandleSessionReport(ctx, link, SessionReport{Playing: true, PositionMS: 1000, Index: 0}); answer || snap != nil {
		t.Fatal("queueless creating report was not ignored")
	}

	// A creating report with the queue creates the mirror session and
	// answers with the assigned id.
	snap, answer := svc.HandleSessionReport(ctx, link, SessionReport{
		Playing: true, PositionMS: 1000, Index: 0, ItemPids: []string{"tr-one", "tr-two"},
	})
	if !answer || snap == nil {
		t.Fatal("creating report unanswered")
	}
	if snap.Authority != AuthorityMirror || len(snap.Entries) != 2 {
		t.Fatalf("mirror snapshot %+v", snap)
	}
	if snap.QueueVersion == 0 {
		t.Fatal("server queue version not bumped")
	}

	// Steady reports update position without answering.
	if _, answer := svc.HandleSessionReport(ctx, link, SessionReport{Playing: true, PositionMS: 9000, Index: 0}); answer {
		t.Fatal("steady report answered")
	}
	got, err := svc.Session("us-alice", snap.ID)
	if err != nil {
		t.Fatal(err)
	}
	if got.PositionMS < 9000 {
		t.Fatalf("position %d", got.PositionMS)
	}

	// The mirror session is invisible to other users (private client
	// endpoint), and its queue mirrors into the sink.
	if got := len(svc.Sessions("us-bob")); got != 0 {
		t.Fatalf("second user sees %d private sessions", got)
	}
	sink.mu.Lock()
	queues := len(sink.queues)
	sink.mu.Unlock()
	if queues != 1 {
		t.Fatalf("queue mirror writes = %d", queues)
	}

	// Disconnect ends the session.
	svc.OnDisconnect(ctx, link)
	if _, err := svc.Session("us-alice", snap.ID); !errors.Is(err, ErrNotFound) {
		t.Fatal("mirror session survived disconnect")
	}
}

// A mirror session's row has to keep up with what the client is
// playing, because a crash or a restart never runs the teardown that
// would otherwise write the final position. Without a checkpoint, the
// history entry says whatever the last queue change said — the first
// track at zero — and resuming it starts the album over.
func TestMirrorSessionsCheckpointWhilePlaying(t *testing.T) {
	svc, _, _ := newTestService(t)
	ctx := context.Background()

	link := NewClientLink("us-alice", "Alice", "se-phone", "Phone", func(any) bool { return true })
	svc.HandleRegister(link, "Alice's phone", true, true)
	snap, _ := svc.HandleSessionReport(ctx, link, SessionReport{
		Playing: true, Index: 0, ItemPids: []string{"tr-one", "tr-two"},
	})
	if snap == nil {
		t.Fatal("creating report unanswered")
	}

	// Two tracks in, well past what the creating report persisted. A
	// steady report carries no itemPids, so nothing writes the row.
	svc.HandleSessionReport(ctx, link, SessionReport{Playing: true, PositionMS: 42000, Index: 1})

	// The session is live, so its row is active and history is empty;
	// read the checkpoint straight out of the table.
	position := func() (int64, int) {
		t.Helper()
		var state string
		if err := svc.cfg.Store.Reader().QueryRow(
			`SELECT state FROM playback_sessions WHERE id = ?`, snap.ID).Scan(&state); err != nil {
			t.Fatal(err)
		}
		var ps persistedState
		if err := json.Unmarshal([]byte(state), &ps); err != nil {
			t.Fatal(err)
		}
		return ps.PositionMS, ps.Index
	}

	if pos, idx := position(); pos != 0 || idx != 0 {
		t.Fatalf("before a checkpoint the row is the creating report's, got %d/%d", pos, idx)
	}

	svc.checkpointPlaying(ctx)

	if pos, idx := position(); pos != 42000 || idx != 1 {
		t.Errorf("checkpointed position %d/%d, want 42000/1", pos, idx)
	}

	// A paused session is not checkpointed: nothing is moving, and its
	// row was written by whatever stopped it.
	svc.HandleSessionReport(ctx, link, SessionReport{Playing: false, PositionMS: 51000, Index: 1})
	svc.checkpointPlaying(ctx)
	if pos, _ := position(); pos != 42000 {
		t.Errorf("a paused session was checkpointed: %d", pos)
	}
}

func TestReportGraceAfterServerEnd(t *testing.T) {
	svc, _, _ := newTestService(t)
	ctx := context.Background()

	link := NewClientLink("us-alice", "Alice", "se-phone", "Phone", func(any) bool { return true })
	svc.HandleRegister(link, "Phone", true, true)
	snap, _ := svc.HandleSessionReport(ctx, link, SessionReport{
		Playing: true, PositionMS: 0, Index: 0, ItemPids: []string{"tr-one"},
	})
	if err := svc.End(ctx, "us-alice", snap.ID); err != nil {
		t.Fatal(err)
	}
	// A stale report inside the grace answers the ended id instead of
	// spawning a ghost.
	got, answer := svc.HandleSessionReport(ctx, link, SessionReport{Playing: true, PositionMS: 500, Index: 0, ItemPids: []string{"tr-one"}})
	if !answer || got == nil || !got.Ended || got.ID != snap.ID {
		t.Fatalf("grace answer %+v answer=%v", got, answer)
	}
	if got := len(svc.Sessions("us-alice")); got != 0 {
		t.Fatalf("%d ghost sessions", got)
	}
}

func TestTransferDeviceKeepsPosition(t *testing.T) {
	svc, _, driver := newTestService(t)
	ctx := context.Background()
	epID := deviceEndpointID(t, svc, "us-alice")

	// A second device endpoint to transfer to.
	driver2 := newFakeDriver()
	ep2, err := svc.EndpointOnline(ctx, KindCast, "cast-dev-2", "Bedroom", "192.0.2.51:8009", true, false,
		func(context.Context) (Driver, error) { return driver2, nil })
	if err != nil {
		t.Fatal(err)
	}

	snap, err := svc.CreateSession(ctx, "us-alice", "Alice", epID, []string{"tr-one", "tr-two"}, 0, 10000, true)
	if err != nil {
		t.Fatal(err)
	}
	moved, err := svc.Transfer(ctx, "us-alice", snap.ID, ep2.ID)
	if err != nil {
		t.Fatal(err)
	}
	if moved.ID != snap.ID {
		t.Fatal("transfer changed the session id")
	}
	if moved.EndpointID != ep2.ID {
		t.Fatalf("endpoint after transfer %s", moved.EndpointID)
	}
	if moved.PositionMS < 10000 {
		t.Fatalf("position lost in transfer: %d", moved.PositionMS)
	}
	load := driver2.lastLoad(t)
	if load.positionMS < 10000 || load.index != 0 {
		t.Fatalf("target load %+v", load)
	}
	// The source device was stopped.
	waitFor(t, func() bool {
		driver.mu.Lock()
		defer driver.mu.Unlock()
		for _, v := range driver.verbs {
			if v == "stop" {
				return true
			}
		}
		return false
	})
	// Transfer to the same endpoint is a no-op.
	again, err := svc.Transfer(ctx, "us-alice", snap.ID, ep2.ID)
	if err != nil || again.EndpointID != ep2.ID {
		t.Fatalf("same-endpoint transfer: %+v err=%v", again, err)
	}
}

func TestTransferAuthTightening(t *testing.T) {
	svc, _, _ := newTestService(t)
	ctx := context.Background()
	epID := deviceEndpointID(t, svc, "us-alice")

	// Bob registers a private client endpoint.
	bobLink := NewClientLink("us-bob", "Bob", "se-bob", "Tablet", func(any) bool { return true })
	svc.HandleRegister(bobLink, "Bob's tablet", true, true)
	bobEndpoint := clientEndpointID("se-bob")

	snap, err := svc.CreateSession(ctx, "us-alice", "Alice", epID, []string{"tr-one"}, 0, 0, true)
	if err != nil {
		t.Fatal(err)
	}
	// Bob may not move Alice's session onto his private endpoint.
	if _, err := svc.Transfer(ctx, "us-bob", snap.ID, bobEndpoint); !errors.Is(err, ErrForbidden) {
		t.Fatalf("queue steal allowed: %v", err)
	}
}

func TestWatchSemantics(t *testing.T) {
	svc, _, _ := newTestService(t)
	ctx := context.Background()
	epID := deviceEndpointID(t, svc, "us-alice")

	snap, err := svc.CreateSession(ctx, "us-alice", "Alice", epID, []string{"tr-one"}, 0, 0, true)
	if err != nil {
		t.Fatal(err)
	}
	link := NewClientLink("us-bob", "Bob", "se-bob", "Tablet", func(any) bool { return true })

	got, ok := svc.HandleWatch(link, snap.ID)
	if !ok || got == nil || got.ID != snap.ID {
		t.Fatalf("watch failed: %+v ok=%v", got, ok)
	}
	if _, ok := svc.HandleWatch(link, "ps-01BX5ZZKBKACTAV9WEVGEMMVS0"); ok {
		t.Fatal("watch of unknown session succeeded")
	}
	if got, ok := svc.HandleWatch(link, ""); !ok || got != nil {
		t.Fatal("stop watch misbehaved")
	}
}

func waitFor(t *testing.T, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		if cond() {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("condition never held")
}

// clientLinkAnsweringLoads builds a link that behaves like a real
// player client answering routed loads, optionally firing a racing
// session-report before the command result (the exact interleaving a
// fast client produces).
func clientLinkAnsweringLoads(svc *Service, userID string, raceReport bool) *ClientLink {
	var link *ClientLink
	link = NewClientLink(userID, "User", "se-"+userID, "Phone", func(v any) bool {
		cmd, ok := v.(wireEndpointCommand)
		if !ok || cmd.Verb != "load" {
			return true
		}
		if raceReport {
			svc.HandleSessionReport(context.Background(), link, SessionReport{
				Playing: true, PositionMS: 0, Index: 0, ItemPids: cmd.ItemPids,
			})
		}
		svc.HandleCommandResult(cmd.ID, true, "", "")
		return true
	})
	return link
}

func TestCreateOnClientEndpointNoGhost(t *testing.T) {
	svc, _, _ := newTestService(t)
	ctx := context.Background()

	link := clientLinkAnsweringLoads(svc, "us-alice", true)
	svc.HandleRegister(link, "Phone", true, true)
	epID := clientEndpointID(link.SessionID)

	snap, err := svc.CreateSession(ctx, "us-alice", "Alice", epID, []string{"tr-one"}, 0, 0, true)
	if err != nil {
		t.Fatal(err)
	}
	// The racing first report must not have minted a second session:
	// exactly one exists and it is the one the create returned.
	sessions := svc.Sessions("us-alice")
	if len(sessions) != 1 || sessions[0].ID != snap.ID {
		t.Fatalf("ghost session: %+v (created %s)", sessions, snap.ID)
	}
}

func TestTransferToClientFencesStaleDeviceEvents(t *testing.T) {
	svc, _, driver := newTestService(t)
	ctx := context.Background()
	epID := deviceEndpointID(t, svc, "us-alice")

	snap, err := svc.CreateSession(ctx, "us-alice", "Alice", epID, []string{"tr-one", "tr-two"}, 0, 0, true)
	if err != nil {
		t.Fatal(err)
	}
	link := clientLinkAnsweringLoads(svc, "us-alice", false)
	svc.HandleRegister(link, "Phone", true, true)
	phone := clientEndpointID(link.SessionID)

	moved, err := svc.Transfer(ctx, "us-alice", snap.ID, phone)
	if err != nil {
		t.Fatal(err)
	}
	// A buffered trailing status from the old cast pump must not
	// clobber the transferred session.
	driver.events <- DriverEvent{At: time.Now(), Playing: true, Index: 1, PositionMS: 55000}
	time.Sleep(150 * time.Millisecond)
	got, err := svc.Session("us-alice", snap.ID)
	if err != nil {
		t.Fatal(err)
	}
	if got.Index != moved.Index || got.Authority != AuthorityMirror {
		t.Fatalf("stale device event clobbered the transfer: %+v", got)
	}
	if got.PositionMS >= 55000 {
		t.Fatalf("stale position applied: %d", got.PositionMS)
	}
}

func TestPersistedEndpointsRestoreAtBoot(t *testing.T) {
	svc, _, _ := newTestService(t)
	ctx := context.Background()
	epID := deviceEndpointID(t, svc, "us-alice")

	// A second service over the same store (a restart) lists the
	// device immediately, offline and undialable.
	svc2, err := New(ctx, Config{
		Store:    svc.cfg.Store,
		Group:    supervise.NewGroup(nil),
		Resolver: svc.cfg.Resolver,
		Sink:     svc.cfg.Sink,
		Bases:    svc.cfg.Bases,
	})
	if err != nil {
		t.Fatal(err)
	}
	restored := svc2.Endpoints("us-alice")
	found := false
	for _, ep := range restored {
		if ep.ID == epID {
			found = true
			if ep.Online || ep.Kind != KindCast || ep.Name != "Kitchen speaker" {
				t.Fatalf("restored endpoint shape %+v", ep)
			}
		}
	}
	if !found {
		t.Fatalf("persisted endpoint missing after restart: %+v", restored)
	}
	if _, err := svc2.CreateSession(ctx, "us-alice", "Alice", epID, []string{"tr-one"}, 0, 0, true); !errors.Is(err, ErrEndpointOffline) {
		t.Fatalf("undialable restored endpoint accepted a session: %v", err)
	}
}
