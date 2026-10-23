package db

import (
	"context"
	"errors"
	"slices"
	"testing"
	"time"
)

const (
	oldPlaylist = "pl-01JZX5N8QW3F4V9T2B7KDAAAAA"
	newPlaylist = "pl-01JZX5N8QW3F4V9T2B7KDBBBBB"
)

// The home pins that named a replaced playlist are rewritten in place for
// every account that held one, and nothing else in any document moves.
func TestRepointPlaylistPinsFollowsThePlaylistToItsNewPid(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	shareUser(t, d, "us-B", "bob")
	shareUser(t, d, "us-C", "carol")
	pinned := `{"pinned":["al-01JZX5N8QW3F4V9T2B7KDDDDD","` + oldPlaylist + `"]}`
	untouched := `{"pinned":["al-01JZX5N8QW3F4V9T2B7KDDDDD"]}`
	if err := d.PutPrefsJSON(ctx, "us-B", pinned); err != nil {
		t.Fatal(err)
	}
	if err := d.PutPrefsJSON(ctx, "us-C", untouched); err != nil {
		t.Fatal(err)
	}

	who, err := d.RepointPlaylistPins(ctx, oldPlaylist, newPlaylist)
	if err != nil {
		t.Fatal(err)
	}
	if !slices.Equal(who, []string{"us-B"}) {
		t.Fatalf("pinners = %v, want bob alone", who)
	}
	if doc, err := d.PrefsJSON(ctx, "us-B"); err != nil || doc != `{"pinned":["al-01JZX5N8QW3F4V9T2B7KDDDDD","`+newPlaylist+`"]}` {
		t.Errorf("bob's prefs = %s (%v), want the pin rewritten and the rest kept", doc, err)
	}
	if doc, _ := d.PrefsJSON(ctx, "us-C"); doc != untouched {
		t.Errorf("carol's prefs = %s, want them untouched", doc)
	}

	// Run again, as a retry does: nothing names the old pid any more.
	if who, err := d.RepointPlaylistPins(ctx, oldPlaylist, newPlaylist); err != nil || len(who) != 0 {
		t.Errorf("a second run = %v (%v), want no one to tell", who, err)
	}
	// And back, as a rollback does.
	if who, err := d.RepointPlaylistPins(ctx, newPlaylist, oldPlaylist); err != nil || !slices.Equal(who, []string{"us-B"}) {
		t.Errorf("the way back = %v (%v), want bob's pin again", who, err)
	}
	if doc, _ := d.PrefsJSON(ctx, "us-B"); doc != pinned {
		t.Errorf("bob's prefs after the way back = %s, want %s", doc, pinned)
	}
}

// A handover's record is one settings row per playlist, read back whole,
// and an account's deletion clears its own.
func TestPlaylistHandoverRecords(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	started := time.Date(2026, 10, 1, 12, 0, 0, 0, time.UTC).UnixNano()

	if _, err := d.PlaylistHandoverFor(ctx, "01JZX5N8QW3F4V9T2B7KDAAAAA"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("a playlist with no record = %v, want not found", err)
	}
	mine := PlaylistHandover{SourcePID: "01JZX5N8QW3F4V9T2B7KDAAAAA", UserID: "us-A", TakerID: "us-T"}
	mineToo := PlaylistHandover{SourcePID: "01JZX5N8QW3F4V9T2B7KDGGGGG", CopyPID: "01JZX5N8QW3F4V9T2B7KDHHHHH", UserID: "us-A", TakerID: "us-T"}
	other := PlaylistHandover{SourcePID: "01JZX5N8QW3F4V9T2B7KDCCCCC", CopyPID: "01JZX5N8QW3F4V9T2B7KDDDDD0", UserID: "us-B", TakerID: "us-T"}
	for _, h := range []PlaylistHandover{mine, mineToo, other} {
		if err := d.PutPlaylistHandover(ctx, h); err != nil {
			t.Fatal(err)
		}
	}
	if got, err := d.PlaylistHandoverFor(ctx, mine.SourcePID); err != nil || got != mine {
		t.Errorf("the record = %+v (%v), want %+v", got, err, mine)
	}

	// Naming the copy replaces the record whole.
	mine.CopyPID = "01JZX5N8QW3F4V9T2B7KDEEEEE"
	if err := d.PutPlaylistHandover(ctx, mine); err != nil {
		t.Fatal(err)
	}
	if got, _ := d.PlaylistHandoverFor(ctx, mine.SourcePID); got.CopyPID != mine.CopyPID {
		t.Errorf("the record after naming the copy = %+v, want copy %s", got, mine.CopyPID)
	}

	// An account's records are listed in order of their playlists, no one
	// else's among them, and a row this build cannot read is no one's.
	if err := d.SettingSet(ctx, playlistHandoverPrefix+"01JZX5N8QW3F4V9T2B7KDFFFFF", "not json", started); err != nil {
		t.Fatal(err)
	}
	if got, err := d.PlaylistHandoversOf(ctx, "us-A"); err != nil || !slices.Equal(got, []PlaylistHandover{mine, mineToo}) {
		t.Errorf("the account's records = %+v (%v), want its two, in order", got, err)
	}

	// An account's deletion clears its records and no one else's, and a
	// row this build cannot read is left alone.
	if err := d.DeletePlaylistHandoversOf(ctx, "us-A"); err != nil {
		t.Fatal(err)
	}
	for _, gone := range []PlaylistHandover{mine, mineToo} {
		if _, err := d.PlaylistHandoverFor(ctx, gone.SourcePID); !errors.Is(err, ErrNotFound) {
			t.Errorf("the deleted account's record of %s = %v, want it gone", gone.SourcePID, err)
		}
	}
	if got, err := d.PlaylistHandoverFor(ctx, other.SourcePID); err != nil || got != other {
		t.Errorf("another account's record = %+v (%v), want it kept", got, err)
	}
	if _, err := d.SettingGet(ctx, playlistHandoverPrefix+"01JZX5N8QW3F4V9T2B7KDFFFFF"); err != nil {
		t.Errorf("an unreadable row = %v, want it left alone", err)
	}

	if err := d.DeletePlaylistHandover(ctx, other.SourcePID); err != nil {
		t.Fatal(err)
	}
	if err := d.DeletePlaylistHandover(ctx, other.SourcePID); err != nil {
		t.Errorf("deleting a record twice = %v, want a no-op", err)
	}
	if _, err := d.PlaylistHandoverFor(ctx, other.SourcePID); !errors.Is(err, ErrNotFound) {
		t.Errorf("the deleted record = %v, want it gone", err)
	}
}

// The links an account's deletion ends are the ones that could still be
// opened: not one it pulled, and not one that has run out.
func TestCountLiveShares(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	shareUser(t, d, "us-A", "alice")
	shareUser(t, d, "us-B", "bob")
	now := time.Date(2026, 10, 1, 12, 0, 0, 0, time.UTC)

	forever := mkShare("01SHARE0000000000000000001", "us-A", now.Add(-time.Hour))
	later := mkShare("01SHARE0000000000000000002", "us-A", now.Add(-time.Hour))
	later.ExpiresAt = now.Add(time.Hour)
	over := mkShare("01SHARE0000000000000000003", "us-A", now.Add(-2*time.Hour))
	over.ExpiresAt = now.Add(-time.Minute)
	pulled := mkShare("01SHARE0000000000000000004", "us-A", now.Add(-time.Hour))
	bobs := mkShare("01SHARE0000000000000000005", "us-B", now.Add(-time.Hour))
	for _, s := range []Share{forever, later, over, pulled, bobs} {
		if err := d.InsertShare(ctx, s); err != nil {
			t.Fatal(err)
		}
	}
	if err := d.RevokeShare(ctx, pulled.ID); err != nil {
		t.Fatal(err)
	}

	if n, err := d.CountLiveShares(ctx, "us-A", now); err != nil || n != 2 {
		t.Errorf("alice's live links = %d (%v), want the two that can still be opened", n, err)
	}
	if n, err := d.CountLiveShares(ctx, "us-B", now); err != nil || n != 1 {
		t.Errorf("bob's live links = %d (%v), want 1", n, err)
	}
	if n, err := d.CountLiveShares(ctx, "us-A", now.Add(2*time.Hour)); err != nil || n != 1 {
		t.Errorf("alice's live links two hours on = %d (%v), want only the one with no expiry", n, err)
	}
}
