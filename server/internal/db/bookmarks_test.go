package db

import (
	"context"
	"errors"
	"fmt"
	"testing"
)

// openBookmarkTest is a store with the two accounts the marks belong to.
func openBookmarkTest(t *testing.T) *DB {
	t.Helper()
	d := openTest(t)
	for _, id := range []string{"us-1", "us-2"} {
		if err := d.CreateUser(context.Background(), mkUser(id, "user-"+id, nil), false); err != nil {
			t.Fatal(err)
		}
	}
	return d
}

// noCheck passes every new mark.
func noCheck() error { return nil }

func mark(id, user, book string, position int64) Bookmark {
	return Bookmark{ID: id, UserID: user, BookPID: book, PositionMS: position, Note: "note " + id, CreatedAtNS: position}
}

func TestCreateBookmarkReplaysItsOwnID(t *testing.T) {
	d := openBookmarkTest(t)
	ctx := context.Background()
	first := mark("01JZX5N8QW3F4V9T2B7KD3M9R6", "us-1", "bk1", 1500)
	stored, created, err := d.CreateBookmark(ctx, first, noCheck)
	if err != nil || !created || stored != first {
		t.Fatalf("first create = (%+v, %v, %v)", stored, created, err)
	}

	retry := first
	retry.PositionMS, retry.Note = 9, "retried"
	stored, created, err = d.CreateBookmark(ctx, retry, noCheck)
	if err != nil || created || stored != first {
		t.Fatalf("replay = (%+v, %v, %v), want the stored row", stored, created, err)
	}
	if rows, _ := d.BookmarksFor(ctx, "us-1", "bk1"); len(rows) != 1 {
		t.Fatalf("a replay stored %d rows", len(rows))
	}
}

func TestCreateBookmarkRefusesAnIDThatIsNotTheCallers(t *testing.T) {
	d := openBookmarkTest(t)
	ctx := context.Background()
	if _, _, err := d.CreateBookmark(ctx, mark("01JZX5N8QW3F4V9T2B7KD3M9R6", "us-1", "bk1", 1), noCheck); err != nil {
		t.Fatal(err)
	}
	for _, other := range []Bookmark{
		mark("01JZX5N8QW3F4V9T2B7KD3M9R6", "us-2", "bk1", 1),
		mark("01JZX5N8QW3F4V9T2B7KD3M9R6", "us-1", "bk2", 1),
	} {
		if _, _, err := d.CreateBookmark(ctx, other, noCheck); !errors.Is(err, ErrConflict) {
			t.Errorf("create under %s/%s = %v, want ErrConflict", other.UserID, other.BookPID, err)
		}
	}
}

func TestCreateBookmarkCapsABook(t *testing.T) {
	d := openBookmarkTest(t)
	ctx := context.Background()
	id := func(i int) string { return fmt.Sprintf("01JZX5N8QW3F4V9T2B7KD3%04d", i) }
	for i := range bookmarkCap {
		if _, _, err := d.CreateBookmark(ctx, mark(id(i), "us-1", "bk1", int64(i)), noCheck); err != nil {
			t.Fatalf("mark %d: %v", i, err)
		}
	}
	if _, _, err := d.CreateBookmark(ctx, mark(id(bookmarkCap), "us-1", "bk1", 1), noCheck); !errors.Is(err, ErrBookmarkFull) {
		t.Fatalf("mark past the cap = %v, want ErrBookmarkFull", err)
	}
	// A full book still answers a replay, and another user's book is not full.
	if _, created, err := d.CreateBookmark(ctx, mark(id(0), "us-1", "bk1", 0), noCheck); err != nil || created {
		t.Fatalf("replay into a full book = (%v, %v)", created, err)
	}
	if _, _, err := d.CreateBookmark(ctx, mark(id(bookmarkCap), "us-2", "bk1", 1), noCheck); err != nil {
		t.Fatalf("another user's mark = %v", err)
	}
}

func TestDeleteBookmarkReportsWhetherItRemovedOne(t *testing.T) {
	d := openBookmarkTest(t)
	ctx := context.Background()
	if _, _, err := d.CreateBookmark(ctx, mark("01JZX5N8QW3F4V9T2B7KD3M9R6", "us-1", "bk1", 1), noCheck); err != nil {
		t.Fatal(err)
	}
	for _, c := range []struct {
		book string
		want bool
	}{{"bk2", false}, {"bk1", true}, {"bk1", false}} {
		removed, err := d.DeleteBookmark(ctx, "us-1", c.book, "01JZX5N8QW3F4V9T2B7KD3M9R6")
		if err != nil || removed != c.want {
			t.Errorf("delete under %s = (%v, %v), want %v", c.book, removed, err, c.want)
		}
	}
}

// A create replayed after the mark was removed (its first answer lost,
// the removal made on another device) must not bring it back.
func TestARemovedBookmarkIsNotCreatedAgain(t *testing.T) {
	d := openBookmarkTest(t)
	ctx := context.Background()
	m := mark("01JZX5N8QW3F4V9T2B7KD3M9R6", "us-1", "bk1", 1)
	if _, _, err := d.CreateBookmark(ctx, m, noCheck); err != nil {
		t.Fatal(err)
	}
	if _, err := d.DeleteBookmark(ctx, "us-1", "bk1", m.ID); err != nil {
		t.Fatal(err)
	}
	if _, created, err := d.CreateBookmark(ctx, m, noCheck); !errors.Is(err, ErrBookmarkRemoved) || created {
		t.Fatalf("replay after the removal = (%v, %v), want ErrBookmarkRemoved", created, err)
	}
	if rows, _ := d.BookmarksFor(ctx, "us-1", "bk1"); len(rows) != 0 {
		t.Fatalf("the replay brought back %d rows", len(rows))
	}
}

// A tombstone past the horizon goes, and a replay of its mark is a new
// mark again; one inside the horizon still refuses.
func TestTombstonesPastTheHorizonArePruned(t *testing.T) {
	d := openBookmarkTest(t)
	ctx := context.Background()
	old := mark("01JZX5N8QW3F4V9T2B7KD3M9R6", "us-1", "bk1", 1)
	recent := mark("01JZX5N8QW3F4V9T2B7KD3M9R7", "us-1", "bk1", 2)
	for _, m := range []Bookmark{old, recent} {
		if _, _, err := d.CreateBookmark(ctx, m, noCheck); err != nil {
			t.Fatal(err)
		}
		if _, err := d.DeleteBookmark(ctx, "us-1", "bk1", m.ID); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := d.w.ExecContext(ctx,
		`UPDATE book_bookmark_tombstones SET removed_at_ns = 1 WHERE id = ?`, old.ID); err != nil {
		t.Fatal(err)
	}

	if n, err := d.PruneBookmarkTombstones(ctx, 2); err != nil || n != 1 {
		t.Fatalf("pruned %d (%v), want the one past the horizon", n, err)
	}
	if _, created, err := d.CreateBookmark(ctx, old, noCheck); err != nil || !created {
		t.Errorf("replay past the horizon = (%v, %v), want a new mark", created, err)
	}
	if _, _, err := d.CreateBookmark(ctx, recent, noCheck); !errors.Is(err, ErrBookmarkRemoved) {
		t.Errorf("replay inside the horizon = %v, want ErrBookmarkRemoved", err)
	}
}

// A replay racing a removal of the same mark answers one or the other,
// never that the book is full.
func TestAReplayRacingARemovalIsNeverFull(t *testing.T) {
	d := openBookmarkTest(t)
	ctx := context.Background()
	for i := range 100 {
		m := mark(fmt.Sprintf("01JZX5N8QW3F4V9T2B7KD3%04d", i), "us-1", "bk1", 1)
		if _, _, err := d.CreateBookmark(ctx, m, noCheck); err != nil {
			t.Fatal(err)
		}
		start, replayed, removed := make(chan struct{}), make(chan error, 1), make(chan error, 1)
		go func() {
			<-start
			_, err := d.DeleteBookmark(ctx, "us-1", "bk1", m.ID)
			removed <- err
		}()
		go func() {
			<-start
			_, _, err := d.CreateBookmark(ctx, m, noCheck)
			replayed <- err
		}()
		close(start)
		if err := <-removed; err != nil {
			t.Fatal(err)
		}
		if err := <-replayed; err != nil && !errors.Is(err, ErrBookmarkRemoved) {
			t.Fatalf("round %d: replay = %v", i, err)
		}
	}
}

// Only a mark that would be new is put to the caller's check: a replay
// answers what is stored whatever it carries.
func TestCreateBookmarkChecksOnlyANewMark(t *testing.T) {
	d := openBookmarkTest(t)
	ctx := context.Background()
	m := mark("01JZX5N8QW3F4V9T2B7KD3M9R6", "us-1", "bk1", 1)
	refuse := func() error { return errors.New("refused") }
	if _, _, err := d.CreateBookmark(ctx, m, refuse); err == nil || err.Error() != "refused" {
		t.Fatalf("a new mark failing its check = %v, want the check's error", err)
	}
	if rows, _ := d.BookmarksFor(ctx, "us-1", "bk1"); len(rows) != 0 {
		t.Fatalf("a refused mark stored %d rows", len(rows))
	}
	if _, _, err := d.CreateBookmark(ctx, m, noCheck); err != nil {
		t.Fatal(err)
	}
	if _, created, err := d.CreateBookmark(ctx, m, refuse); err != nil || created {
		t.Fatalf("a replay = (%v, %v), want the stored row unchecked", created, err)
	}
}
