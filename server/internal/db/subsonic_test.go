package db

import (
	"context"
	"errors"
	"fmt"
	"testing"
)

// A folder id is assigned the first time its library is asked for and
// never moves: a library listed later, or another removed, leaves every
// id a client already holds naming the library it named.
func TestMusicFolderIDsAreAssignedOnceAndKept(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()

	first, err := d.MusicFolderIDs(ctx, []string{"lb-A", "lb-B"})
	if err != nil {
		t.Fatal(err)
	}
	if len(first) != 2 || first["lb-A"] == first["lb-B"] || first["lb-A"] <= 0 {
		t.Fatalf("ids = %v, want two distinct positive ids", first)
	}
	again, err := d.MusicFolderIDs(ctx, []string{"lb-C", "lb-B"})
	if err != nil {
		t.Fatal(err)
	}
	if again["lb-B"] != first["lb-B"] {
		t.Fatalf("lb-B moved from %d to %d", first["lb-B"], again["lb-B"])
	}
	if again["lb-C"] == first["lb-A"] || again["lb-C"] == first["lb-B"] {
		t.Fatalf("lb-C reused an id: %v vs %v", again, first)
	}
	if _, ok := again["lb-A"]; ok {
		t.Fatalf("an id for a library not asked about: %v", again)
	}

	lib, ok, err := d.MusicFolderLibrary(ctx, first["lb-A"])
	if err != nil || !ok || lib != "lb-A" {
		t.Fatalf("folder %d = %q %v (%v), want lb-A", first["lb-A"], lib, ok, err)
	}
	if _, ok, err := d.MusicFolderLibrary(ctx, 9999); err != nil || ok {
		t.Fatalf("an unassigned id resolved: %v (%v)", ok, err)
	}
}

func TestSubsonicBookmarksPerUser(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	for _, u := range []*User{mkUser("us-1", "u1", nil), mkUser("us-2", "u2", nil)} {
		if err := d.CreateUser(ctx, u, false); err != nil {
			t.Fatal(err)
		}
	}

	put := func(b SubsonicBookmark) {
		t.Helper()
		if err := d.PutSubsonicBookmark(ctx, b); err != nil {
			t.Fatal(err)
		}
	}
	put(SubsonicBookmark{UserID: "us-1", ItemPID: "tr-1", PositionMS: 5000, Comment: "chorus", CreatedAtNS: 10, UpdatedAtNS: 10})
	put(SubsonicBookmark{UserID: "us-1", ItemPID: "ep-1", PositionMS: 9000, CreatedAtNS: 20, UpdatedAtNS: 20})
	put(SubsonicBookmark{UserID: "us-2", ItemPID: "tr-1", PositionMS: 100, CreatedAtNS: 30, UpdatedAtNS: 30})
	// An update keeps the row's creation time and takes everything else.
	put(SubsonicBookmark{UserID: "us-1", ItemPID: "tr-1", PositionMS: 6000, Comment: "bridge", CreatedAtNS: 40, UpdatedAtNS: 40})

	rows, err := d.SubsonicBookmarks(ctx, "us-1")
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 2 || rows[0].ItemPID != "tr-1" || rows[1].ItemPID != "ep-1" {
		t.Fatalf("rows = %+v, want tr-1 then ep-1, most recently changed first", rows)
	}
	if b := rows[0]; b.PositionMS != 6000 || b.Comment != "bridge" || b.CreatedAtNS != 10 || b.UpdatedAtNS != 40 {
		t.Fatalf("updated row = %+v", b)
	}

	if err := d.DeleteSubsonicBookmarks(ctx, "us-1", "tr-1", "no-such"); err != nil {
		t.Fatal(err)
	}
	rows, _ = d.SubsonicBookmarks(ctx, "us-1")
	if len(rows) != 1 || rows[0].ItemPID != "ep-1" {
		t.Fatalf("rows after delete = %+v, want ep-1 alone", rows)
	}
	theirs, _ := d.SubsonicBookmarks(ctx, "us-2")
	if len(theirs) != 1 || theirs[0].PositionMS != 100 {
		t.Fatalf("another account's rows = %+v, want its own untouched", theirs)
	}
}

// The listing is unpaginated, so one account's rows are capped; an
// update to a held row is never refused.
func TestSubsonicBookmarksAreCapped(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	if err := d.CreateUser(ctx, mkUser("us-1", "u1", nil), false); err != nil {
		t.Fatal(err)
	}
	for i := range SubsonicBookmarkCap {
		if err := d.PutSubsonicBookmark(ctx, SubsonicBookmark{UserID: "us-1", ItemPID: fmt.Sprintf("tr-%d", i), PositionMS: 1, CreatedAtNS: 1, UpdatedAtNS: 1}); err != nil {
			t.Fatal(err)
		}
	}
	err := d.PutSubsonicBookmark(ctx, SubsonicBookmark{UserID: "us-1", ItemPID: "tr-new", PositionMS: 1, CreatedAtNS: 2, UpdatedAtNS: 2})
	if !errors.Is(err, ErrSubsonicBookmarksFull) {
		t.Fatalf("a bookmark past the cap = %v, want ErrSubsonicBookmarksFull", err)
	}
	if err := d.PutSubsonicBookmark(ctx, SubsonicBookmark{UserID: "us-1", ItemPID: "tr-0", PositionMS: 2, CreatedAtNS: 3, UpdatedAtNS: 3}); err != nil {
		t.Fatalf("updating a held bookmark at the cap: %v", err)
	}
	// The rows the caller says are not to count leave room for a new one.
	if err := d.PutSubsonicBookmark(ctx, SubsonicBookmark{UserID: "us-1", ItemPID: "tr-new", PositionMS: 1, CreatedAtNS: 4, UpdatedAtNS: 4},
		"tr-1"); err != nil {
		t.Fatalf("a bookmark beside an uncounted row = %v, want it saved", err)
	}
	if err := d.PutSubsonicBookmark(ctx, SubsonicBookmark{UserID: "us-1", ItemPID: "tr-newer", PositionMS: 1, CreatedAtNS: 5, UpdatedAtNS: 5},
		"tr-1"); !errors.Is(err, ErrSubsonicBookmarksFull) {
		t.Fatalf("a second bookmark beside the one uncounted row = %v, want ErrSubsonicBookmarksFull", err)
	}
}
