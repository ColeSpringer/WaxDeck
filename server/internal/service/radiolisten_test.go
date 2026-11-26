package service

import (
	"context"
	"io"
	"log/slog"
	"path/filepath"
	"testing"
	"time"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// A tune-in becomes a row, that row reaches the totals, and the station
// is nameable in the top list - the three steps that were missing when
// radio time was invisible to stats.
func TestRecordRadioListenReachesStats(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newAdminFixture(t)
	settled := watchRadioScrobbles(t, svc)
	st, err := svc.Radio.CreateRadioStation(ctx, admin, RadioStationEdit{
		Name: "Groove Salad", StreamURL: "https://ice.example.net/groove",
	})
	if err != nil {
		t.Fatal(err)
	}

	started := time.Now().Add(-10 * time.Minute)
	svc.Radio.RecordRadioListen(ctx, admin.ID, "listen-1", st.PID, started, 4*time.Minute, true)
	settled()

	stats, err := svc.Reads.ListeningStats(ctx, admin, "30d", "day", "")
	if err != nil {
		t.Fatal(err)
	}
	if stats.TotalMs != (4 * time.Minute).Milliseconds() {
		t.Fatalf("radio time is missing from the total: %+v", stats)
	}
	var radio *MediaTypeListening
	for i := range stats.ByMediaType {
		if stats.ByMediaType[i].MediaType == "radio" {
			radio = &stats.ByMediaType[i]
		}
	}
	if radio == nil || radio.Sessions != 1 {
		t.Fatalf("radio has no media slice: %+v", stats.ByMediaType)
	}

	top, err := svc.Reads.TopListFor(ctx, admin, "stations", "30d", 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(top.Entries) != 1 {
		t.Fatalf("top stations: %+v", top.Entries)
	}
	e := top.Entries[0]
	if e.Name != "Groove Salad" || e.PID != st.PID || e.ArtPID != st.PID {
		t.Fatalf("top station entry: %+v", e)
	}

	// A second checkpoint of the same connection extends the one row
	// rather than adding a session: the payload carries the elapsed
	// total, which is what makes a dropped checkpoint survivable.
	svc.Radio.RecordRadioListen(ctx, admin.ID, "listen-1", st.PID, started, 9*time.Minute, false)
	settled()
	stats, err = svc.Reads.ListeningStats(ctx, admin, "30d", "day", "")
	if err != nil {
		t.Fatal(err)
	}
	if stats.TotalMs != (9*time.Minute).Milliseconds() || stats.Sessions != 1 {
		t.Fatalf("a checkpoint must supersede, not accumulate: %+v", stats)
	}

	// The log names the station from the station library; the catalog
	// has never heard of it.
	log, err := svc.Reads.ListenLog(ctx, admin, "", "", 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(log.Sessions) != 1 {
		t.Fatalf("listen log: %+v", log.Sessions)
	}
	if got := log.Sessions[0]; got.Title != "Groove Salad" ||
		got.MediaType != "radio" || got.PID != st.PID || got.Source != "radio" {
		t.Fatalf("log entry: %+v", got)
	}

	// A station is not an item, so the recap counts its time without
	// counting it as a different thing listened to.
	recap, err := svc.Reads.UserYearInReview(ctx, admin, time.Now().Year())
	if err != nil {
		t.Fatal(err)
	}
	if recap.TotalMs != (9 * time.Minute).Milliseconds() {
		t.Fatalf("recap total: %+v", recap.TotalMs)
	}
	if recap.DistinctItems != 0 {
		t.Fatalf("a station is not a distinct item: %d", recap.DistinctItems)
	}
}

// The floor keeps a tune-in nobody heard off the record, and it is the
// listening rule rather than the scrobbling one.
func TestRecordRadioListenIgnoresAGlance(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newAdminFixture(t)
	st, err := svc.Radio.CreateRadioStation(ctx, admin, RadioStationEdit{
		Name: "Groove Salad", StreamURL: "https://ice.example.net/groove",
	})
	if err != nil {
		t.Fatal(err)
	}

	svc.Radio.RecordRadioListen(ctx, admin.ID, "listen-1", st.PID, time.Now(), svc.Radio.radioListenFloor-time.Second, true)
	// Nothing was queued, so there is no writer tick to wait for; the
	// assertion is that the row never appears.
	stats, err := svc.Reads.ListeningStats(ctx, admin, "30d", "day", "")
	if err != nil {
		t.Fatal(err)
	}
	if stats.Sessions != 0 {
		t.Fatalf("a glance must not be a listen: %+v", stats)
	}
}

// The closing checkpoint of an open tune-in is written at shutdown
// rather than dropped.
//
// The order here is the process's own, and it is the whole point: the
// signal context stops the bookkeeping writer, requests are cancelled
// *after* that, and the relays unwind then - so every open listener's
// last checkpoint is queued at a moment when nothing is reading the
// queue. It lands in the buffer and is never seen again unless
// something drains it afterwards. [Library.Close] is that something,
// because it runs behind the group's wait.
//
// Without it a restart lost up to a minute of every tune-in in flight,
// and every tune-in younger than one checkpoint interval entirely.
func TestRadioListenSurvivesShutdown(t *testing.T) {
	t.Parallel()
	ctx, cancel := context.WithCancel(context.Background())
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	store, err := wdb.Open(ctx, filepath.Join(t.TempDir(), "waxdeck.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { store.Close() })
	group := supervise.NewGroup(log)
	svc, err := Open(ctx, Config{
		DataDir: t.TempDir(),
		Roots:   []Root{{Name: "lib", Path: t.TempDir()}},
		Sealer:  testSealer(t),
		Logger:  log,
	}, store, group)
	if err != nil {
		t.Fatal(err)
	}
	acct, err := svc.Identity.CreateAccount(ctx, AccountCreate{
		Username: "admin", Password: "correct-horse", Roles: []string{"admin"},
	})
	if err != nil {
		t.Fatal(err)
	}
	admin, err := svc.Grants.UserCtxFor(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	st, err := svc.Radio.CreateRadioStation(ctx, admin, RadioStationEdit{
		Name: "Groove Salad", StreamURL: "https://ice.example.net/groove",
	})
	if err != nil {
		t.Fatal(err)
	}

	// Shutdown begins: the signal context ends and the workers are
	// waited on, exactly as `main` does it.
	cancel()
	group.Wait()

	// And only now do the request contexts end and the relay unwind,
	// which is where the closing checkpoint comes from. Detached from
	// the cancelled context for the reason the proxy detaches it: the
	// listener's context dies at the same instant their last segment is
	// reported.
	started := time.Now().Add(-4 * time.Minute)
	svc.Radio.RecordRadioListen(context.WithoutCancel(ctx), admin.ID, "listen-1", st.PID, started, 4*time.Minute, true)

	if err := svc.Close(); err != nil {
		t.Fatal(err)
	}

	// Read straight from the store: the service is closed, and the row
	// is the only evidence that matters.
	rows, err := store.ListenLog(context.Background(), admin.ID, "", 0, 0, 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 1 {
		t.Fatalf("the closing checkpoint was dropped at shutdown: %+v", rows)
	}
	if got := rows[0]; got.MediaType != "radio" || got.MsPlayed != (4*time.Minute).Milliseconds() {
		t.Fatalf("listen row: %+v", got)
	}
}

// A station deleted after it was listened to keeps its time in the
// ranking, and carries neither a name it no longer has nor an art
// handle nothing will answer.
//
// The time staying is deliberate - a list that claims to total
// listening must not quietly drop some of it - and it is what makes the
// other two matter: the entry is drawn, so an art handle for a row the
// server cannot resolve is a 404 per entry, and an empty name is a
// blank line where a title goes.
func TestTopStationsAfterTheStationIsDeleted(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newAdminFixture(t)
	settled := watchRadioScrobbles(t, svc)
	kept, err := svc.Radio.CreateRadioStation(ctx, admin, RadioStationEdit{
		Name: "Groove Salad", StreamURL: "https://ice.example.net/groove",
	})
	if err != nil {
		t.Fatal(err)
	}
	gone, err := svc.Radio.CreateRadioStation(ctx, admin, RadioStationEdit{
		Name: "Drone Zone", StreamURL: "https://ice.example.net/drone",
	})
	if err != nil {
		t.Fatal(err)
	}

	started := time.Now().Add(-time.Hour)
	svc.Radio.RecordRadioListen(ctx, admin.ID, "listen-1", kept.PID, started, 4*time.Minute, true)
	settled()
	// More time on the one about to go, so its place in the ranking is
	// unambiguous and the assertion is about the entry rather than the
	// order.
	svc.Radio.RecordRadioListen(ctx, admin.ID, "listen-2", gone.PID, started, 9*time.Minute, true)
	settled()

	if err := svc.Radio.DeleteRadioStation(ctx, gone.PID); err != nil {
		t.Fatal(err)
	}

	top, err := svc.Reads.TopListFor(ctx, admin, "stations", "30d", 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(top.Entries) != 2 {
		t.Fatalf("a deleted station must keep its time: %+v", top.Entries)
	}
	first := top.Entries[0]
	if first.PID != gone.PID || first.Ms != (9*time.Minute).Milliseconds() {
		t.Fatalf("the deleted station's time is missing: %+v", first)
	}
	if first.Name != "" {
		t.Fatalf("a deleted station has no name to give: %q", first.Name)
	}
	if first.ArtPID != "" {
		t.Fatalf("a deleted station must carry no art handle: %q", first.ArtPID)
	}
	if second := top.Entries[1]; second.Name != "Groove Salad" || second.ArtPID != kept.PID {
		t.Fatalf("the surviving station lost its name or art: %+v", second)
	}
}

// A tune-in announces the caller's listening record on its first written
// checkpoint and on its closing one, never between, and a glance under
// the floor writes nothing and announces nothing.
func TestRadioListenAnnouncesItsStartAndEnd(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newAdminFixture(t)
	settled := watchRadioScrobbles(t, svc)
	st, err := svc.Radio.CreateRadioStation(ctx, admin, RadioStationEdit{
		Name: "Groove Salad", StreamURL: "https://ice.example.net/groove",
	})
	if err != nil {
		t.Fatal(err)
	}
	announced := func(want int, what string) {
		t.Helper()
		if n := markers(t, ctx, svc, admin.ID, eventListens, ""); n != want {
			t.Fatalf("%s: %d listens markers, want %d", what, n, want)
		}
	}
	started := time.Now().Add(-5 * time.Minute)
	if !svc.Radio.RecordRadioListen(ctx, admin.ID, "listen-1", st.PID, started, time.Minute, true) {
		t.Fatal("a checkpoint over the floor reported no write")
	}
	settled()
	announced(1, "the first checkpoint")
	for _, at := range []time.Duration{2 * time.Minute, 3 * time.Minute} {
		svc.Radio.RecordRadioListen(ctx, admin.ID, "listen-1", st.PID, started, at, false)
		settled()
	}
	announced(1, "the checkpoints between")
	svc.Radio.RecordRadioListen(ctx, admin.ID, "listen-1", st.PID, started, 3*time.Minute+10*time.Second, true)
	settled()
	announced(2, "the closing checkpoint")

	if svc.Radio.RecordRadioListen(ctx, admin.ID, "listen-2", st.PID, time.Now(), svc.Radio.radioListenFloor-time.Second, true) {
		t.Fatal("a glance under the floor reported a write")
	}
	// Queued behind nothing: a later write settling proves the glance
	// was never queued ahead of it.
	svc.Radio.RecordRadioListen(ctx, admin.ID, "listen-1", st.PID, started, 4*time.Minute, false)
	settled()
	announced(2, "a glance under the floor")
}
