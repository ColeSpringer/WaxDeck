package db

import (
	"context"
	"path/filepath"
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
	if err := d.migrate(ctx); err == nil {
		t.Fatal("migrate accepted a future schema version")
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
