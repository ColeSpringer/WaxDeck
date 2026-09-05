package service

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"
	"unicode/utf8"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

func TestClipHealthMessageKeepsRuneBoundaries(t *testing.T) {
	t.Parallel()
	// A short message passes through untouched.
	if got := clipHealthMessage("boom"); got != "boom" {
		t.Fatalf("short clip = %q", got)
	}
	// A long ASCII message clips at the byte budget exactly.
	long := strings.Repeat("x", 400)
	if got := clipHealthMessage(long); len(got) != 300 {
		t.Fatalf("ascii clip = %d bytes, want 300", len(got))
	}
	// A multi-byte message never clips mid-rune: byte 300 lands inside
	// a euro sign (3 bytes each), and the stored string must stay
	// valid UTF-8 instead of rendering a replacement character in the
	// settings surface.
	multi := strings.Repeat("€", 200)
	got := clipHealthMessage(multi)
	if len(got) > 300 {
		t.Fatalf("multi-byte clip = %d bytes, want at most 300", len(got))
	}
	if !utf8.ValidString(got) {
		t.Fatalf("multi-byte clip is not valid UTF-8: %q", got[len(got)-6:])
	}
	if !strings.HasSuffix(got, "€") {
		t.Fatalf("multi-byte clip ends %q, want a whole rune", got[len(got)-3:])
	}
}

// A muted target keeps its configuration and its event selection and
// delivers nothing but its own test, which is how somebody checks a
// destination they have just silenced.
func TestMutedTargetTakesTestsAndNothingElse(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newAdminFixture(t)

	target, err := svc.CreateMyNotificationTarget(ctx, uc, NotificationTargetInput{
		Kind:          "webhook",
		Config:        []byte(`{"url":"https://hook.example.com/x"}`),
		EnabledEvents: []string{"review-ready"},
		Muted:         ptrTo(true),
	})
	if err != nil {
		t.Fatalf("creating the target: %v", err)
	}
	if !target.Muted {
		t.Fatalf("target = %+v, want muted", target)
	}

	svc.EmitNotification(ctx, "review-ready", "Ready", "entry", []string{uc.ID})
	if n := takeQueuedNotifies(t, ctx, svc); n != 0 {
		t.Fatalf("a muted target queued %d deliveries, want none", n)
	}

	if err := svc.TestMyNotificationTarget(ctx, uc, target.PID); err != nil {
		t.Fatalf("testing the target: %v", err)
	}
	if n := takeQueuedNotifies(t, ctx, svc); n != 1 {
		t.Fatalf("the test queued %d deliveries, want one", n)
	}

	// An update that says nothing about mute keeps it: a client written
	// before the flag existed renames a target, it does not wake it.
	if _, err := svc.UpdateMyNotificationTarget(ctx, uc, target.PID, NotificationTargetInput{
		Config:        []byte(`{"url":"https://hook.example.com/x"}`),
		EnabledEvents: []string{"review-ready"},
		Label:         "renamed",
	}); err != nil {
		t.Fatalf("renaming: %v", err)
	}
	svc.EmitNotification(ctx, "review-ready", "Ready", "entry", []string{uc.ID})
	if n := takeQueuedNotifies(t, ctx, svc); n != 0 {
		t.Fatalf("a rename woke a muted target: %d deliveries queued", n)
	}

	// Unmuted on purpose, the same event goes through: nothing about the
	// selection changed while it was paused.
	if _, err := svc.UpdateMyNotificationTarget(ctx, uc, target.PID, NotificationTargetInput{
		Config:        []byte(`{"url":"https://hook.example.com/x"}`),
		EnabledEvents: []string{"review-ready"},
		Muted:         ptrTo(false),
	}); err != nil {
		t.Fatalf("unmuting: %v", err)
	}
	svc.EmitNotification(ctx, "review-ready", "Ready", "entry", []string{uc.ID})
	if n := takeQueuedNotifies(t, ctx, svc); n != 1 {
		t.Fatalf("after unmuting the emit queued %d deliveries, want one", n)
	}
}

// Pacing is a wait, not a failure: a row held back must not spend one of
// its ten attempts, or a target paced slower than its traffic would drop
// deliveries for being patient.
func TestPacingWaitsWithoutSpendingAnAttempt(t *testing.T) {
	t.Parallel()
	now := time.Now()
	within := wdb.NotificationTarget{MinIntervalS: 300, LastPacedNS: now.Add(-time.Minute).UnixNano()}
	if wait := pacingWait(within, "review-ready", now); wait <= 0 {
		t.Fatalf("a target one minute into a five-minute gap waits %v, want a positive wait", wait)
	}
	if wait := pacingWait(within, notifyTestEvent, now); wait != 0 {
		t.Fatalf("a test waited %v, want the exemption", wait)
	}
	past := wdb.NotificationTarget{MinIntervalS: 300, LastPacedNS: now.Add(-time.Hour).UnixNano()}
	if wait := pacingWait(past, "review-ready", now); wait != 0 {
		t.Fatalf("a target past its gap waited %v", wait)
	}
	unpaced := wdb.NotificationTarget{LastPacedNS: now.UnixNano()}
	if wait := pacingWait(unpaced, "review-ready", now); wait != 0 {
		t.Fatalf("an unpaced target waited %v", wait)
	}
	fresh := wdb.NotificationTarget{MinIntervalS: 300}
	if wait := pacingWait(fresh, "review-ready", now); wait != 0 {
		t.Fatalf("a target that has never delivered waited %v, want its first through", wait)
	}
	// A per-target test is exempt from the interval, so it must not
	// start the clock either: pacing reads its own column, and a target
	// whose only success was a test is still on its first real delivery.
	tested := wdb.NotificationTarget{MinIntervalS: 300, LastSuccessNS: now.UnixNano()}
	if wait := pacingWait(tested, "review-ready", now); wait != 0 {
		t.Fatalf("a test parked a real delivery for %v", wait)
	}
}

func ptrTo[T any](v T) *T { return &v }

// The interval is capped where the API caps it, so a target cannot be
// paced past the outbox horizon that would prune its backlog.
func TestPacingIntervalIsBounded(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newAdminFixture(t)
	_, err := svc.CreateMyNotificationTarget(ctx, uc, NotificationTargetInput{
		Kind:               "webhook",
		Config:             []byte(`{"url":"https://hook.example.com/x"}`),
		EnabledEvents:      []string{},
		MinIntervalSeconds: ptrTo(notifyMaxInterval + 1),
	})
	wantKind(t, err, KindInvalid)
}

// The link table is what makes a delivery openable, and it is empty
// without a public base rather than pointing at a host nobody outside
// this network can resolve.
func TestNotificationLinks(t *testing.T) {
	t.Parallel()
	_, svc, _ := newAdminFixture(t)

	if got := svc.notificationLink("review-ready", ""); got != "" {
		t.Fatalf("link with no public base = %q, want none", got)
	}
	svc.publicBase = "https://wax.example.com"
	for _, c := range []struct{ event, pid, want string }{
		{"review-ready", "", "https://wax.example.com/review"},
		{"signup-requested", "", "https://wax.example.com/admin/users"},
		{"backup-completed", "", "https://wax.example.com/admin/backups"},
		{"backup-failed", "", "https://wax.example.com/admin/backups"},
		{"import-completed", "rv-1", "https://wax.example.com/review/rv-1"},
		{"import-completed", "", "https://wax.example.com/review"},
		{"feed-disabled", "pc-1", "https://wax.example.com/podcasts/pc-1"},
		{"feed-disabled", "", "https://wax.example.com/podcasts"},
		{"episode-downloaded", "ep-1", "https://wax.example.com/episodes/ep-1"},
		{"playlist-synced", "pl-1", "https://wax.example.com/playlists/pl-1"},
		{notifyTestEvent, "", ""},
		{"invented-by-a-newer-server", "", ""},
	} {
		if got := svc.notificationLink(c.event, c.pid); got != c.want {
			t.Errorf("link(%s, %s) = %q, want %q", c.event, c.pid, got, c.want)
		}
	}
}

// takeQueuedNotifies counts what the outbox holds and leases it away,
// so each call answers what the step before it queued. The outbox is
// the only observable a delivery-free test has of what an emit decided.
func takeQueuedNotifies(t *testing.T, ctx context.Context, svc *Library) int {
	t.Helper()
	n := 0
	for {
		row, err := svc.db.LeaseNotify(ctx, time.Now().UnixNano(),
			int64(time.Hour), notifyMaxAttempts)
		if errors.Is(err, wdb.ErrNotFound) {
			return n
		}
		if err != nil {
			t.Fatalf("leasing: %v", err)
		}
		n++
		if n > 50 {
			t.Fatal("the outbox never drained")
		}
		_ = row
	}
}

// Enqueue-time gating is not enough: a destination backing off holds
// rows scheduled up to half an hour out, and muting it to make it stop
// has to stop those too.
func TestMuteDropsWhatIsAlreadyQueued(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newAdminFixture(t)

	// Server scope, so the write-time private-address courtesy check
	// does not stand between the test and a port nothing answers on: a
	// delivery that is attempted fails and records why, which is what
	// tells an attempt from a drop.
	target, err := svc.CreateServerNotificationTarget(ctx, NotificationTargetInput{
		Kind:          "webhook",
		Config:        []byte(`{"url":"http://127.0.0.1:1/hook"}`),
		EnabledEvents: []string{"backup-completed"},
	})
	if err != nil {
		t.Fatalf("creating the target: %v", err)
	}
	svc.EmitServerNotification(ctx, "backup-completed", "Backup finished", "12 MB")

	if _, err := svc.UpdateServerNotificationTarget(ctx, target.PID, NotificationTargetInput{
		Config:        []byte(`{"url":"http://127.0.0.1:1/hook"}`),
		EnabledEvents: []string{"backup-completed"},
		Muted:         ptrTo(true),
	}); err != nil {
		t.Fatalf("muting: %v", err)
	}

	if !svc.DrainNotifyOutbox(ctx) {
		t.Fatal("the drain found nothing to do")
	}
	if n := takeQueuedNotifies(t, ctx, svc); n != 0 {
		t.Fatalf("the muted target still holds %d queued deliveries", n)
	}
	rows, err := svc.ListServerNotificationTargets(ctx)
	if err != nil {
		t.Fatalf("re-reading the target: %v", err)
	}
	if rows[0].LastError != "" {
		t.Fatalf("the row was delivered rather than dropped: %q", rows[0].LastError)
	}
}

// Pacing delays; it does not coalesce. A target fed faster than its
// interval loses its tail, and that is decided here with a log line
// rather than by the janitor deleting rows without a word.
func TestPacedRowPastTheHorizonIsShed(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newAdminFixture(t)

	target, err := svc.CreateServerNotificationTarget(ctx, NotificationTargetInput{
		Kind:               "webhook",
		Config:             []byte(`{"url":"http://127.0.0.1:1/hook"}`),
		EnabledEvents:      []string{"backup-completed"},
		MinIntervalSeconds: ptrTo(600),
	})
	if err != nil {
		t.Fatalf("creating the target: %v", err)
	}
	row, err := svc.notificationTargetRow(ctx, target.PID)
	if err != nil {
		t.Fatalf("reading the row: %v", err)
	}
	// A delivery just went out, so the next one waits; the queued row is
	// already a day old, so its turn falls outside the outbox horizon.
	now := time.Now()
	if err := svc.db.MarkNotifyPaced(ctx, row.ID, now.UnixNano()); err != nil {
		t.Fatalf("stamping the pacing clock: %v", err)
	}
	if err := svc.db.EnqueueNotify(ctx, wdb.NotifyRow{
		TargetID: row.ID, Event: "backup-completed", Title: "Backup finished", Body: "12 MB",
	}, now.Add(-notifyHorizon-time.Minute).UnixNano()); err != nil {
		t.Fatalf("queuing: %v", err)
	}

	if !svc.DrainNotifyOutbox(ctx) {
		t.Fatal("the drain found nothing to do")
	}
	if n := takeQueuedNotifies(t, ctx, svc); n != 0 {
		t.Fatalf("the shed row is still queued (%d)", n)
	}
}
