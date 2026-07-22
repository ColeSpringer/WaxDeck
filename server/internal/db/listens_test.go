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
	ins, err := d.InsertListen(ctx, s)
	if err != nil || !ins {
		t.Fatalf("first insert = (%v, %v), want (true, nil)", ins, err)
	}
	ins, err = d.InsertListen(ctx, s)
	if err != nil || ins {
		t.Fatalf("replay insert = (%v, %v), want (false, nil)", ins, err)
	}

	// The same session ID under another user is a distinct session.
	s2 := s
	s2.UserID = "us-2"
	if ins, err = d.InsertListen(ctx, s2); err != nil || !ins {
		t.Fatalf("other-user insert = (%v, %v), want (true, nil)", ins, err)
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
	if ins, err := d.InsertListen(ctx, s); err != nil || !ins {
		t.Fatalf("insert = (%v, %v), want (true, nil)", ins, err)
	}
	if err := d.DeleteListen(ctx, s.UserID, s.SessionID); err != nil {
		t.Fatal(err)
	}
	// The compensating delete must let a retry insert the row again.
	if ins, err := d.InsertListen(ctx, s); err != nil || !ins {
		t.Fatalf("reinsert = (%v, %v), want (true, nil)", ins, err)
	}
	// Deleting a session that is not there is not an error.
	if err := d.DeleteListen(ctx, s.UserID, "sess-absent"); err != nil {
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
	if ins, err := d.InsertListen(ctx, s); err != nil || !ins {
		t.Fatalf("insert = (%v, %v), want (true, nil)", ins, err)
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
	ins, err := d.InsertListen(context.Background(), ListenSession{
		UserID:    user,
		SessionID: "sess-" + item,
		ItemPID:   item,
		MediaType: "music",
		StartedAt: at,
		MsPlayed:  1000,
		Client:    client,
	})
	if err != nil || !ins {
		t.Fatalf("insert %s = (%v, %v), want (true, nil)", item, ins, err)
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
