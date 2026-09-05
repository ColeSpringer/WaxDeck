package service

import (
	"context"
	"slices"
	"sort"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestParseRadioTitle(t *testing.T) {
	t.Parallel()
	cases := []struct {
		raw, station  string
		artist, title string
		ok            bool
	}{
		{"Massive Attack - Teardrop", "Groove Salad", "Massive Attack", "Teardrop", true},
		{"A - B - C", "", "A", "B - C", true},
		{"  Boards of Canada -  Roygbiv ", "", "Boards of Canada", "Roygbiv", true},
		{"Groove Salad", "Groove Salad", "", "", false},
		{"Groove Salad - The Chill Hour", "Groove Salad", "", "", false},
		{"Best Mix - Groove Salad", "Groove Salad", "", "", false},
		{"NoSeparatorHere", "", "", "", false},
		{"Visit us at https://station.example - now", "", "", "", false},
		{" - Title only", "", "", "", false},
		{"Artist only - ", "", "", "", false},
		{"", "", "", "", false},
	}
	for _, c := range cases {
		artist, title, ok := parseRadioTitle(c.raw, c.station)
		if ok != c.ok || artist != c.artist || title != c.title {
			t.Errorf("parseRadioTitle(%q, %q) = %q, %q, %v; want %q, %q, %v",
				c.raw, c.station, artist, title, ok, c.artist, c.title, c.ok)
		}
	}
}

// watchRadioScrobbles installs the written hook and returns a function
// that blocks until one more queued segment has been through the
// writer. Reports are handed off now and written on a worker, so every
// assertion below needs the writer to have caught up first - including
// the ones expecting no row, since a segment the writer has not reached
// yet looks exactly like a segment it rejected.
func watchRadioScrobbles(t *testing.T, svc *Library) func() {
	t.Helper()
	written := make(chan struct{}, 16)
	hook := func() { written <- struct{}{} }
	svc.radioWriteDone.Store(&hook)
	return func() {
		t.Helper()
		select {
		case <-written:
		case <-time.After(10 * time.Second):
			t.Fatal("radio scrobble writer never reported")
		}
	}
}

func TestScrobbleRadioPlayEnqueues(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newAdminFixture(t)
	settled := watchRadioScrobbles(t, svc)
	st, err := svc.CreateRadioStation(ctx, admin, RadioStationEdit{
		Name: "Groove Salad", StreamURL: "https://ice.example.net/groove",
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := svc.storeScrobbleConnection(ctx, admin.ID, ScrobblerListenBrainz, "token", "sam", ""); err != nil {
		t.Fatal(err)
	}

	started := time.Now().Add(-2 * time.Minute)
	svc.ScrobbleRadioPlay(ctx, admin.ID, st.PID, "Massive Attack - Teardrop", started)
	settled()

	row, err := svc.db.LeaseScrobble(ctx, time.Now().UnixNano(), int64(time.Minute), 3)
	if err != nil {
		t.Fatalf("expected a queued scrobble: %v", err)
	}
	if row.Artist != "Massive Attack" || row.Title != "Teardrop" ||
		row.ItemPID != st.PID || row.DurationMS != 0 ||
		row.ListenedAtNS != started.UnixNano() {
		t.Fatalf("queued row: %+v", row)
	}

	// Junk titles queue nothing.
	svc.ScrobbleRadioPlay(ctx, admin.ID, st.PID, "Groove Salad", started)
	settled()
	if _, err := svc.db.LeaseScrobble(ctx, time.Now().UnixNano(), int64(time.Minute), 3); err == nil {
		t.Fatal("station-slogan title must not scrobble")
	}

	// Users without connections queue nothing (no error, no row).
	other, err := svc.CreateAccount(ctx, AccountCreate{Username: "quiet", Password: "password123"})
	if err != nil {
		t.Fatal(err)
	}
	svc.ScrobbleRadioPlay(ctx, other.User.ID, st.PID, "Massive Attack - Teardrop", started)
	settled()
	if _, err := svc.db.LeaseScrobble(ctx, time.Now().UnixNano(), int64(time.Minute), 3); err == nil {
		t.Fatal("no-connection listener must not scrobble")
	}

	// Opting out silences radio for a listener who still scrobbles
	// everything else.
	if _, err := svc.PutPrefs(ctx, admin, Prefs{RadioScrobbleOptOut: true}); err != nil {
		t.Fatal(err)
	}
	svc.ScrobbleRadioPlay(ctx, admin.ID, st.PID, "Massive Attack - Teardrop", started)
	settled()
	if _, err := svc.db.LeaseScrobble(ctx, time.Now().UnixNano(), int64(time.Minute), 3); err == nil {
		t.Fatal("opted-out listener must not scrobble radio")
	}
	if _, err := svc.PutPrefs(ctx, admin, Prefs{}); err != nil {
		t.Fatal(err)
	}
	svc.ScrobbleRadioPlay(ctx, admin.ID, st.PID, "Massive Attack - Teardrop", started)
	settled()
	if _, err := svc.db.LeaseScrobble(ctx, time.Now().UnixNano(), int64(time.Minute), 3); err != nil {
		t.Fatalf("opting back in must scrobble again: %v", err)
	}
}

// The whole point of the queue: the goroutine relaying audio hands the
// segment over and returns, however far behind the writer is.
func TestScrobbleRadioPlayNeverBlocks(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newAdminFixture(t)
	st, err := svc.CreateRadioStation(ctx, admin, RadioStationEdit{
		Name: "Groove Salad", StreamURL: "https://ice.example.net/groove",
	})
	if err != nil {
		t.Fatal(err)
	}

	// Wedge the writer on its first segment, so every later one either
	// sits in the buffer or is dropped.
	release := make(chan struct{})
	stuck := make(chan struct{})
	var once sync.Once
	hook := func() {
		once.Do(func() { close(stuck) })
		<-release
	}
	svc.radioWriteDone.Store(&hook)
	defer close(release)

	started := time.Now().Add(-2 * time.Minute)
	svc.ScrobbleRadioPlay(ctx, admin.ID, st.PID, "Massive Attack - Teardrop", started)
	select {
	case <-stuck:
	case <-time.After(10 * time.Second):
		t.Fatal("writer never picked up the first segment")
	}

	// Comfortably past the buffer: the sends that do not fit are dropped,
	// not waited on.
	done := make(chan struct{})
	go func() {
		defer close(done)
		for i := 0; i < radioWriteQueue*2; i++ {
			svc.ScrobbleRadioPlay(ctx, admin.ID, st.PID, "Boards of Canada - Roygbiv", started)
		}
	}()
	select {
	case <-done:
	case <-time.After(10 * time.Second):
		t.Fatal("reporting a segment blocked on the writer")
	}
}

// Shutdown cancels the writer's context and the relay goroutines that
// feed it at the same moment, so a writer that just left would take the
// queue with it. These were synchronous writes before the queue existed.
func TestRadioScrobbleWriterDrainsAtShutdown(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newAdminFixture(t)
	st, err := svc.CreateRadioStation(ctx, admin, RadioStationEdit{
		Name: "Groove Salad", StreamURL: "https://ice.example.net/groove",
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := svc.storeScrobbleConnection(ctx, admin.ID, ScrobblerListenBrainz, "token", "sam", ""); err != nil {
		t.Fatal(err)
	}

	// Wedge the writer Open started on one segment, so the two below
	// stay in the buffer where a shutdown would find them.
	release := make(chan struct{})
	stuck := make(chan struct{})
	var once sync.Once
	hook := func() {
		held := false
		once.Do(func() { held = true; close(stuck) })
		if held {
			<-release
		}
	}
	svc.radioWriteDone.Store(&hook)
	defer close(release)

	started := time.Now().Add(-2 * time.Minute)
	svc.ScrobbleRadioPlay(ctx, admin.ID, st.PID, "Massive Attack - Teardrop", started)
	select {
	case <-stuck:
	case <-time.After(10 * time.Second):
		t.Fatal("writer never picked up the first segment")
	}
	svc.ScrobbleRadioPlay(ctx, admin.ID, st.PID, "Boards of Canada - Roygbiv", started)
	svc.ScrobbleRadioPlay(ctx, admin.ID, st.PID, "Aphex Twin - Xtal", started)

	// What shutdown does: the context the writer runs on ends while the
	// queue still holds segments.
	dead, cancel := context.WithCancel(context.Background())
	cancel()
	if err := svc.writeRadioBookkeeping(dead); err != nil {
		t.Fatalf("writer: %v", err)
	}

	// Every segment written, on a context of the drain's own - the reads
	// would all have failed on the cancelled one. The writer takes the
	// third at random from the same select the cancellation arrives on,
	// so it is the one that proves a segment already in hand is carried
	// into the drain rather than written against a dead context.
	var got []string
	for {
		r, err := svc.db.LeaseScrobble(ctx, time.Now().UnixNano(), int64(time.Minute), 3)
		if err != nil {
			break
		}
		got = append(got, r.Title)
	}
	sort.Strings(got)
	want := []string{"Roygbiv", "Teardrop", "Xtal"}
	if !slices.Equal(got, want) {
		t.Fatalf("segments written at shutdown = %v; want %v", got, want)
	}
}

// A muted station is silent while the rest of the dial still reports.
func TestScrobbleRadioPlayMutedStation(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newAdminFixture(t)
	settled := watchRadioScrobbles(t, svc)
	talk, err := svc.CreateRadioStation(ctx, admin, RadioStationEdit{
		Name: "Talk One", StreamURL: "https://ice.example.net/talk",
	})
	if err != nil {
		t.Fatal(err)
	}
	music, err := svc.CreateRadioStation(ctx, admin, RadioStationEdit{
		Name: "Groove Salad", StreamURL: "https://ice.example.net/groove",
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := svc.storeScrobbleConnection(ctx, admin.ID, ScrobblerListenBrainz, "token", "sam", ""); err != nil {
		t.Fatal(err)
	}
	// Lower case on the way in, canonical in the document: the pid a
	// stream URL carries is not the one the store holds.
	muted := Prefs{RadioScrobbleMutedStations: []string{strings.ToLower(talk.PID)}}
	if _, err := svc.PutPrefs(ctx, admin, muted); err != nil {
		t.Fatal(err)
	}

	started := time.Now().Add(-2 * time.Minute)
	svc.ScrobbleRadioPlay(ctx, admin.ID, talk.PID, "Massive Attack - Teardrop", started)
	settled()
	if _, err := svc.db.LeaseScrobble(ctx, time.Now().UnixNano(), int64(time.Minute), 3); err == nil {
		t.Fatal("a muted station must not scrobble")
	}

	svc.ScrobbleRadioPlay(ctx, admin.ID, music.PID, "Massive Attack - Teardrop", started)
	settled()
	if _, err := svc.db.LeaseScrobble(ctx, time.Now().UnixNano(), int64(time.Minute), 3); err != nil {
		t.Fatalf("an unmuted station must still scrobble: %v", err)
	}

	// The account-wide switch still wins over an empty mute list.
	off := Prefs{RadioScrobbleOptOut: true}
	if _, err := svc.PutPrefs(ctx, admin, off); err != nil {
		t.Fatal(err)
	}
	svc.ScrobbleRadioPlay(ctx, admin.ID, music.PID, "Massive Attack - Teardrop", started)
	settled()
	if _, err := svc.db.LeaseScrobble(ctx, time.Now().UnixNano(), int64(time.Minute), 3); err == nil {
		t.Fatal("the account-wide opt-out must still win")
	}
}
