package db

import (
	"context"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func openTest(t *testing.T) *DB {
	t.Helper()
	d, err := Open(context.Background(), filepath.Join(t.TempDir(), "waxdeck.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { d.Close() })
	return d
}

func TestInsertListenDeduplicates(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	s := ListenSession{
		UserID:    "us-1",
		SessionID: "sess-1",
		ItemPID:   "01JZX5N8QW3F4V9T2B7KDEXAMPLE",
		MediaType: "music",
		StartedAt: time.Now(),
		MsPlayed:  900,
	}
	ins, err := d.InsertListens(ctx, []ListenSession{s})
	if err != nil || !ins[0] {
		t.Fatalf("first insert = (%v, %v), want ([true], nil)", ins, err)
	}
	ins, err = d.InsertListens(ctx, []ListenSession{s})
	if err != nil || ins[0] {
		t.Fatalf("replay insert = (%v, %v), want ([false], nil)", ins, err)
	}

	// The same session ID under another user is a distinct session.
	s2 := s
	s2.UserID = "us-2"
	if ins, err = d.InsertListens(ctx, []ListenSession{s2}); err != nil || !ins[0] {
		t.Fatalf("other-user insert = (%v, %v), want ([true], nil)", ins, err)
	}

	n, err := d.ListenCount(ctx, "us-1", s.ItemPID)
	if err != nil || n != 1 {
		t.Fatalf("ListenCount = (%d, %v), want (1, nil)", n, err)
	}
}

// A batch is deduplicated against itself as well as against what is
// stored: a client flushing an offline queue that already holds a
// session it is also reporting live sends both in one call.
func TestInsertListensDeduplicatesWithinABatch(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	s := ListenSession{
		UserID:    "us-1",
		SessionID: "sess-twice",
		ItemPID:   "01JZX5N8QW3F4V9T2B7KDEXAMPLE",
		MediaType: "music",
		StartedAt: time.Now(),
		MsPlayed:  900,
	}
	ins, err := d.InsertListens(ctx, []ListenSession{s, s})
	if err != nil || !ins[0] || ins[1] {
		t.Fatalf("same-batch replay = (%v, %v), want ([true false], nil)", ins, err)
	}
	n, err := d.ListenCount(ctx, "us-1", s.ItemPID)
	if err != nil || n != 1 {
		t.Fatalf("ListenCount = (%d, %v), want (1, nil)", n, err)
	}
}

func TestMigrationVersionGuard(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	if _, err := d.Writer().ExecContext(ctx, "PRAGMA user_version = 99"); err != nil {
		t.Fatal(err)
	}
	// While the schema is one in-place-edited baseline, any higher
	// version is a database from the old migration chain: the refusal
	// must steer to delete-and-restart, not claim a newer build wrote
	// it.
	err := d.migrate(ctx)
	if err == nil {
		t.Fatal("migrate accepted an over-version database")
	}
	if !strings.Contains(err.Error(), "delete the waxdeck.db file") {
		t.Fatalf("over-version refusal = %v, want the delete-and-recreate message", err)
	}
}

func TestBaselineFingerprintGuard(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()

	// A database stamped by the current baseline re-migrates cleanly.
	if err := d.migrate(ctx); err != nil {
		t.Fatalf("re-migrate on a current database: %v", err)
	}

	// A missing hash row is adopted, not refused, and the row is
	// restored for the next boot.
	if _, err := d.Writer().ExecContext(ctx,
		"DELETE FROM sync_state WHERE key = ?", baselineFingerprintKey); err != nil {
		t.Fatal(err)
	}
	if err := d.migrate(ctx); err != nil {
		t.Fatalf("re-migrate with a missing fingerprint: %v", err)
	}
	var stored string
	if err := d.Writer().QueryRowContext(ctx,
		"SELECT value FROM sync_state WHERE key = ?", baselineFingerprintKey).Scan(&stored); err != nil {
		t.Fatalf("fingerprint not re-adopted: %v", err)
	}

	// A hash from a different baseline refuses with the delete-the-file
	// message instead of no-opping into latent query failures.
	if _, err := d.Writer().ExecContext(ctx,
		"UPDATE sync_state SET value = 'stale' WHERE key = ?", baselineFingerprintKey); err != nil {
		t.Fatal(err)
	}
	err := d.migrate(ctx)
	if err == nil || !strings.Contains(err.Error(), "delete the waxdeck.db file") {
		t.Fatalf("stale fingerprint = %v, want the delete-and-recreate refusal", err)
	}
}

func TestDeleteListenReopensTheIdempotencySlot(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	s := ListenSession{
		UserID:    "us-1",
		SessionID: "sess-del",
		ItemPID:   "01JZX5N8QW3F4V9T2B7KDEXAMPLE",
		MediaType: "music",
		StartedAt: time.Now(),
		MsPlayed:  900,
	}
	other := s
	other.SessionID = "sess-del-2"
	if ins, err := d.InsertListens(ctx, []ListenSession{s, other}); err != nil || !ins[0] || !ins[1] {
		t.Fatalf("insert = (%v, %v), want ([true true], nil)", ins, err)
	}
	// A fatal mark takes back the whole unmarked tail, so the delete is
	// the same shape as the claim it undoes.
	if err := d.DeleteListens(ctx, s.UserID, []string{s.SessionID, other.SessionID}); err != nil {
		t.Fatal(err)
	}
	// The compensating delete must let a retry insert the rows again.
	if ins, err := d.InsertListens(ctx, []ListenSession{s, other}); err != nil || !ins[0] || !ins[1] {
		t.Fatalf("reinsert = (%v, %v), want ([true true], nil)", ins, err)
	}
	// Deleting a session that is not there is not an error, and neither
	// is deleting nothing.
	if err := d.DeleteListens(ctx, s.UserID, []string{"sess-absent"}); err != nil {
		t.Fatal(err)
	}
	if err := d.DeleteListens(ctx, s.UserID, nil); err != nil {
		t.Fatal(err)
	}
}

func TestInsertListenStoresSkippedMs(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	s := ListenSession{
		UserID:    "us-1",
		SessionID: "sess-skip",
		ItemPID:   "01JZX5N8QW3F4V9T2B7KDEXAMPLE",
		MediaType: "podcast",
		StartedAt: time.Now(),
		MsPlayed:  900,
		SkippedMs: 1234,
		Finished:  true,
		Client:    "phone",
		Source:    "live",
	}
	if ins, err := d.InsertListens(ctx, []ListenSession{s}); err != nil || !ins[0] {
		t.Fatalf("insert = (%v, %v), want ([true], nil)", ins, err)
	}
	var got []ListenRow
	err := d.ListensInRange(ctx, "us-1", time.Time{}, time.Now().Add(time.Hour), func(r ListenRow) {
		got = append(got, r)
	})
	if err != nil || len(got) != 1 {
		t.Fatalf("range read = (%d rows, %v), want 1", len(got), err)
	}
	r := got[0]
	if r.SkippedMs != 1234 || !r.Finished || r.Client != "phone" || r.MediaType != "podcast" {
		t.Fatalf("row = %+v", r)
	}
}

// insertListenAt records one session at a fixed instant. The range and
// log readers do not select session_id (the log keys on the row id), so
// the item pid doubles as the row marker assertions match on.
func insertListenAt(t *testing.T, d *DB, user, item, client string, at time.Time) {
	t.Helper()
	ins, err := d.InsertListens(context.Background(), []ListenSession{{
		UserID:    user,
		SessionID: "sess-" + item,
		ItemPID:   item,
		MediaType: "music",
		StartedAt: at,
		MsPlayed:  1000,
		Client:    client,
	}})
	if err != nil || !ins[0] {
		t.Fatalf("insert %s = (%v, %v), want ([true], nil)", item, ins, err)
	}
}

func TestListensInRangeBoundsAndOrder(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	base := time.Date(2026, 7, 1, 12, 0, 0, 0, time.UTC)
	insertListenAt(t, d, "us-1", "it-early", "", base.Add(-time.Hour))
	insertListenAt(t, d, "us-1", "it-mid", "", base)
	insertListenAt(t, d, "us-1", "it-late", "", base.Add(time.Hour))
	insertListenAt(t, d, "us-2", "it-other", "", base)

	// [from, to): the from instant is included, the to instant is not.
	var got []string
	err := d.ListensInRange(ctx, "us-1", base, base.Add(time.Hour), func(r ListenRow) {
		got = append(got, r.ItemPID)
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got[0] != "it-mid" {
		t.Fatalf("half-open window = %v, want just it-mid", got)
	}
	// The full window streams oldest first, one user only.
	got = nil
	err = d.ListensInRange(ctx, "us-1", base.Add(-2*time.Hour), base.Add(2*time.Hour), func(r ListenRow) {
		got = append(got, r.ItemPID)
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 3 || got[0] != "it-early" || got[1] != "it-mid" || got[2] != "it-late" {
		t.Fatalf("ordered window = %v, want oldest first", got)
	}
	// The empty user id streams everyone (the server-wide recap).
	n := 0
	err = d.ListensInRange(ctx, "", base.Add(-2*time.Hour), base.Add(2*time.Hour), func(ListenRow) { n++ })
	if err != nil || n != 4 {
		t.Fatalf("all-users window = (%d, %v), want 4", n, err)
	}
}

func TestListenLogPagesNewestFirstAndFiltersClient(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	base := time.Date(2026, 7, 1, 12, 0, 0, 0, time.UTC)
	insertListenAt(t, d, "us-1", "it-1", "phone", base)
	insertListenAt(t, d, "us-1", "it-2", "desk", base.Add(time.Minute))
	insertListenAt(t, d, "us-1", "it-3", "phone", base.Add(2*time.Minute))
	insertListenAt(t, d, "us-2", "it-foreign", "phone", base.Add(3*time.Minute))

	page, err := d.ListenLog(ctx, "us-1", "", 0, 0, 2)
	if err != nil {
		t.Fatal(err)
	}
	if len(page) != 2 || page[0].ItemPID != "it-3" || page[1].ItemPID != "it-2" {
		t.Fatalf("first page = %+v, want it-3 then it-2", page)
	}
	// The (started_at_ns, id) cursor resumes exactly after the last row.
	last := page[len(page)-1]
	page, err = d.ListenLog(ctx, "us-1", "", last.StartedAt.UnixNano(), last.RowID, 2)
	if err != nil {
		t.Fatal(err)
	}
	if len(page) != 1 || page[0].ItemPID != "it-1" {
		t.Fatalf("second page = %+v, want just it-1", page)
	}
	// The client filter narrows to one device's sessions.
	page, err = d.ListenLog(ctx, "us-1", "phone", 0, 0, 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(page) != 2 || page[0].ItemPID != "it-3" || page[1].ItemPID != "it-1" {
		t.Fatalf("phone page = %+v, want it-3 then it-1", page)
	}
}

// TestListenMarkStatesTrackWhatTheMarkDid pins the safety net's own
// bookkeeping: a fresh claim is pending, and a recorded outcome takes
// it out of the sweep's reach.
func TestListenMarkStatesTrackWhatTheMarkDid(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	old := time.Now().Add(-time.Hour)
	sessions := []ListenSession{
		{UserID: "us-1", SessionID: "a", ItemPID: "01A", MediaType: "music", StartedAt: old, MsPlayed: 900},
		{UserID: "us-1", SessionID: "b", ItemPID: "01B", MediaType: "music", StartedAt: old, MsPlayed: 900},
	}
	if _, err := d.InsertListens(ctx, sessions); err != nil {
		t.Fatal(err)
	}

	ahead := time.Now().Add(time.Minute).UnixNano()
	pending, err := d.PendingListenMarks(ctx, ahead, 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(pending) != 2 {
		t.Fatalf("pending = %d rows, want both claims", len(pending))
	}
	for _, r := range pending {
		if r.StartedAt.IsZero() || r.MediaType == "" || r.SessionID == "" {
			t.Fatalf("pending row is missing what the re-mark needs: %+v", r)
		}
	}

	if err := d.SetListenMarkStates(ctx, "us-1", []string{"a"}, ListenMarkLanded); err != nil {
		t.Fatal(err)
	}
	if err := d.SetListenMarkStates(ctx, "us-1", []string{"b"}, ListenMarkNotOwed); err != nil {
		t.Fatal(err)
	}
	pending, err = d.PendingListenMarks(ctx, ahead, 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(pending) != 0 {
		t.Fatalf("pending = %+v, want nothing left once both outcomes are recorded", pending)
	}

	// Another user's identically named session is not this one's.
	if err := d.SetListenMarkStates(ctx, "us-2", []string{"a"}, ListenMarkLanded); err != nil {
		t.Fatal(err)
	}
}

// The age bound is on arrival, not on the play's own time. A backdated
// listen - an offline queue flushing yesterday's plays, or a history
// import - is claimed now and marked moments later, so bounding on
// started_at would hand exactly those rows to a sweep running beside
// the ingest that is about to mark them.
func TestPendingListenMarksBoundsOnArrival(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	if _, err := d.InsertListens(ctx, []ListenSession{{
		UserID: "us-1", SessionID: "backdated", ItemPID: "01A", MediaType: "music",
		StartedAt: time.Now().AddDate(-1, 0, 0), MsPlayed: 900,
	}}); err != nil {
		t.Fatal(err)
	}
	cutoff := time.Now().Add(-time.Minute).UnixNano()
	pending, err := d.PendingListenMarks(ctx, cutoff, 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(pending) != 0 {
		t.Fatalf("pending = %+v, want a just-arrived backdated listen left alone", pending)
	}
	// And once its arrival is past the bound, it is the sweep's.
	if pending, err = d.PendingListenMarks(ctx, time.Now().Add(time.Minute).UnixNano(), 10); err != nil {
		t.Fatal(err)
	}
	if len(pending) != 1 {
		t.Fatalf("pending = %+v, want the stranded claim", pending)
	}
}

// A radio tune-in names a station rather than an item, so it owes no
// played mark and must never reach the sweep, which would resolve the
// station as an item and fail forever.
func TestRadioListenOwesNoMark(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	s := ListenSession{
		UserID:    "us-1",
		SessionID: "radio-1",
		ItemPID:   "01JZX5N8QW3F4V9T2B7KDEXAMPLE",
		MediaType: "radio",
		StartedAt: time.Now().Add(-time.Hour),
		MsPlayed:  60_000,
		Client:    "web",
		Source:    "live",
	}
	if err := d.UpsertRadioListen(ctx, s); err != nil {
		t.Fatal(err)
	}
	// The extending upsert must not reopen the claim either.
	s.MsPlayed = 120_000
	if err := d.UpsertRadioListen(ctx, s); err != nil {
		t.Fatal(err)
	}
	pending, err := d.PendingListenMarks(ctx, time.Now().UnixNano(), 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(pending) != 0 {
		t.Fatalf("pending = %+v, want a radio row to owe nothing", pending)
	}
}
