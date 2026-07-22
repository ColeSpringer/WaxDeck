package db

import (
	"context"
	"errors"
	"testing"
	"time"
)

// shareUser satisfies the shares table's user foreign key.
func shareUser(t *testing.T, d *DB, id, username string) {
	t.Helper()
	if err := d.CreateUser(context.Background(), mkUser(id, username, []string{"user"}), false); err != nil {
		t.Fatal(err)
	}
}

func mkShare(id, userID string, createdAt time.Time) Share {
	return Share{
		ID:         id,
		UserID:     userID,
		TargetPID:  "tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE",
		TargetKind: "track",
		CreatedAt:  createdAt,
	}
}

func TestShareInsertAndLoadRoundTrip(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	shareUser(t, d, "us-A", "alice")
	created := time.Date(2026, 7, 1, 12, 0, 0, 0, time.UTC)
	s := mkShare("01SHARE0000000000000000000A", "us-A", created)
	s.AllowDownload = true
	s.PositionMs = 90000
	s.ExpiresAt = created.Add(48 * time.Hour)
	if err := d.InsertShare(ctx, s); err != nil {
		t.Fatal(err)
	}
	got, err := d.ShareByID(ctx, s.ID)
	if err != nil {
		t.Fatal(err)
	}
	if got.UserID != "us-A" || got.TargetPID != s.TargetPID || got.TargetKind != "track" ||
		!got.AllowDownload || got.PositionMs != 90000 || got.Plays != 0 || got.Revoked {
		t.Fatalf("loaded share = %+v", got)
	}
	if !got.CreatedAt.Equal(created) || !got.ExpiresAt.Equal(s.ExpiresAt) {
		t.Fatalf("timestamps = (%v, %v), want (%v, %v)", got.CreatedAt, got.ExpiresAt, created, s.ExpiresAt)
	}
	// The zero expiry stays zero (never expires).
	forever := mkShare("01SHARE0000000000000000000B", "us-A", created.Add(time.Minute))
	if err := d.InsertShare(ctx, forever); err != nil {
		t.Fatal(err)
	}
	got, err = d.ShareByID(ctx, forever.ID)
	if err != nil || !got.ExpiresAt.IsZero() {
		t.Fatalf("no-expiry share = (%+v, %v), want zero ExpiresAt", got, err)
	}
	if _, err := d.ShareByID(ctx, "01SHAREMISSING000000000000"); err != ErrNotFound {
		t.Fatalf("missing share = %v, want ErrNotFound", err)
	}
}

func TestSharesPaginationAndScope(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	shareUser(t, d, "us-A", "alice")
	shareUser(t, d, "us-B", "bob")
	t1 := time.Date(2026, 7, 1, 12, 0, 0, 0, time.UTC)
	t2 := t1.Add(time.Hour)
	// Two rows share t2 so the id half of the cursor has to break the tie.
	rows := []Share{
		mkShare("01SHARE0000000000000000000A", "us-A", t1),
		mkShare("01SHARE0000000000000000000B", "us-A", t2),
		mkShare("01SHARE0000000000000000000C", "us-A", t2),
		mkShare("01SHARE0000000000000000000D", "us-B", t2),
	}
	for _, s := range rows {
		if err := d.InsertShare(ctx, s); err != nil {
			t.Fatal(err)
		}
	}

	// First page, newest first, scoped to one user.
	page, err := d.Shares(ctx, "us-A", 0, "", 2)
	if err != nil {
		t.Fatal(err)
	}
	if len(page) != 2 || page[0].ID != rows[2].ID || page[1].ID != rows[1].ID {
		t.Fatalf("first page = %+v, want C then B", page)
	}
	// The (created_at, id) cursor resumes exactly after the last row.
	last := page[len(page)-1]
	page, err = d.Shares(ctx, "us-A", last.CreatedAt.UnixNano(), last.ID, 2)
	if err != nil {
		t.Fatal(err)
	}
	if len(page) != 1 || page[0].ID != rows[0].ID {
		t.Fatalf("second page = %+v, want just A", page)
	}
	// The empty user id is the admin listing: everyone's shares.
	all, err := d.Shares(ctx, "", 0, "", 10)
	if err != nil || len(all) != 4 {
		t.Fatalf("admin listing = (%d rows, %v), want 4", len(all), err)
	}
}

func TestRevokeShare(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	shareUser(t, d, "us-A", "alice")
	s := mkShare("01SHARE0000000000000000000A", "us-A", time.Date(2026, 7, 1, 12, 0, 0, 0, time.UTC))
	if err := d.InsertShare(ctx, s); err != nil {
		t.Fatal(err)
	}
	if err := d.RevokeShare(ctx, s.ID); err != nil {
		t.Fatal(err)
	}
	// Revoked shares vanish from the listing but still load by id (the
	// caller decides what revocation means for its surface).
	page, err := d.Shares(ctx, "us-A", 0, "", 10)
	if err != nil || len(page) != 0 {
		t.Fatalf("listing after revoke = (%d rows, %v), want 0", len(page), err)
	}
	got, err := d.ShareByID(ctx, s.ID)
	if err != nil || !got.Revoked {
		t.Fatalf("revoked load = (%+v, %v), want Revoked", got, err)
	}
	// A second revocation reports not found, as does an unknown id.
	if err := d.RevokeShare(ctx, s.ID); !errors.Is(err, ErrNotFound) {
		t.Fatalf("double revoke = %v, want ErrNotFound", err)
	}
	if err := d.RevokeShare(ctx, "01SHAREMISSING000000000000"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("unknown revoke = %v, want ErrNotFound", err)
	}
}

func TestCountSharePlay(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	shareUser(t, d, "us-A", "alice")
	s := mkShare("01SHARE0000000000000000000A", "us-A", time.Date(2026, 7, 1, 12, 0, 0, 0, time.UTC))
	if err := d.InsertShare(ctx, s); err != nil {
		t.Fatal(err)
	}
	for range 2 {
		if err := d.CountSharePlay(ctx, s.ID); err != nil {
			t.Fatal(err)
		}
	}
	got, err := d.ShareByID(ctx, s.ID)
	if err != nil || got.Plays != 2 {
		t.Fatalf("plays = (%d, %v), want 2", got.Plays, err)
	}
	// Counting against an unknown id is a silent no-op (best effort).
	if err := d.CountSharePlay(ctx, "01SHAREMISSING000000000000"); err != nil {
		t.Fatal(err)
	}
}
