package api

import (
	"net/http"
	"strings"
	"testing"

	"github.com/colespringer/waxdeck/fixtures"
)

// TestBookmarksEndToEnd is the acceptance for API item 1: a listener
// marks places in a book, reads them back in timeline order, and
// removes one. The marks belong to the account, not to the book.
func TestBookmarksEndToEnd(t *testing.T) {
	h := newHarness(t)
	if _, err := fixtures.GenerateChapteredBook(h.library); err != nil {
		t.Fatal(err)
	}
	if _, err := fixtures.GenerateBook(h.library); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)

	books := h.items(t, "?mediaType=audiobook")
	if len(books.Items) != 2 {
		t.Fatalf("scanned %d books, want 2", len(books.Items))
	}
	book, otherBook := books.Items[0].Pid, books.Items[1].Pid
	base := "/api/v1/books/" + book + "/bookmarks"

	// Nothing marked yet, and the empty answer is a list rather than a
	// null: a client that maps over it must not have to guard.
	list := decode[BookmarkList](t, get(t, h.ts, base, h.token))
	if list.Bookmarks == nil || len(list.Bookmarks) != 0 {
		t.Fatalf("fresh bookmarks = %+v, want an empty list", list.Bookmarks)
	}

	// Made out of order; read back in timeline order.
	mark := func(body map[string]any) Bookmark {
		t.Helper()
		resp := h.postJSON(t, base, body)
		if resp.StatusCode != 201 {
			resp.Body.Close()
			t.Fatalf("create %+v status = %d, want 201", body, resp.StatusCode)
		}
		return decode[Bookmark](t, resp)
	}
	later := mark(map[string]any{"positionMs": 4200, "note": "the turn"})
	earlier := mark(map[string]any{"positionMs": 1500})

	for _, m := range []Bookmark{earlier, later} {
		if len(m.Id) < 4 || m.Id[:3] != "bm-" {
			t.Fatalf("bookmark id = %q, want a bm- prefix", m.Id)
		}
		if m.CreatedAt.IsZero() {
			t.Fatalf("bookmark %q has no createdAt", m.Id)
		}
	}
	if deref(later.Note) != "the turn" {
		t.Fatalf("note = %q, want %q", deref(later.Note), "the turn")
	}
	// An absent note stays absent rather than becoming an empty string
	// the client has to tell from a note somebody wrote.
	if earlier.Note != nil {
		t.Fatalf("noteless bookmark carries note %q", *earlier.Note)
	}

	list = decode[BookmarkList](t, get(t, h.ts, base, h.token))
	if len(list.Bookmarks) != 2 {
		t.Fatalf("bookmarks = %+v, want 2", list.Bookmarks)
	}
	if list.Bookmarks[0].PositionMs != 1500 || list.Bookmarks[1].PositionMs != 4200 {
		t.Fatalf("bookmarks out of timeline order: %+v", list.Bookmarks)
	}

	// A position past the end is refused rather than stored as a mark
	// nothing can seek to.
	wantStatus(t, h.postJSON(t, base, map[string]any{"positionMs": 99_000_000}), 400, "past the end")

	// Another account shares the catalog and none of these marks.
	resp := h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "sam", "password": testPassword,
	})
	if resp.StatusCode != 201 {
		t.Fatalf("create user status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	sam := loginAs(t, h.ts, "sam", testPassword)
	if theirs := decode[BookmarkList](t, get(t, h.ts, base, sam.Token)); len(theirs.Bookmarks) != 0 {
		t.Fatalf("sam sees %d of admin's bookmarks", len(theirs.Bookmarks))
	}
	// And cannot delete one of them by naming its id.
	req, _ := http.NewRequest("DELETE", h.ts.URL+base+"/"+earlier.Id, nil)
	req.Header.Set("Authorization", "Bearer "+sam.Token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if list = decode[BookmarkList](t, get(t, h.ts, base, h.token)); len(list.Bookmarks) != 2 {
		t.Fatalf("after sam's delete, admin has %d bookmarks, want 2", len(list.Bookmarks))
	}

	// A delete under the wrong book takes nothing. The route names the
	// book, so a mark that belongs to another one is not the mark this
	// call asked to remove - and answering 204 while removing it would
	// leave the book that owns it still listing it.
	wantStatus(
		t,
		h.deleteReq(t, "/api/v1/books/"+otherBook+"/bookmarks/"+earlier.Id),
		204,
		"delete under another book",
	)
	if list = decode[BookmarkList](t, get(t, h.ts, base, h.token)); len(list.Bookmarks) != 2 {
		t.Fatalf("a delete under another book took one: %+v", list.Bookmarks)
	}

	// The owner's delete lands, and repeating it is not an error: the
	// outcome asked for holds either way.
	for range 2 {
		wantStatus(t, h.deleteReq(t, base+"/"+earlier.Id), 204, "delete")
	}
	list = decode[BookmarkList](t, get(t, h.ts, base, h.token))
	if len(list.Bookmarks) != 1 || list.Bookmarks[0].Id != later.Id {
		t.Fatalf("after delete: %+v", list.Bookmarks)
	}

	// A malformed bookmark id is a 404 rather than a 500.
	wantStatus(t, h.deleteReq(t, base+"/not-an-id"), 404, "malformed id")

	// A book that does not exist answers 404 on every verb.
	missing := "/api/v1/books/bk-01JZX5N8QW3F4V9T2B7KD3M9R6/bookmarks"
	wantStatus(t, get(t, h.ts, missing, h.token), 404, "missing book list")
	wantStatus(t, h.postJSON(t, missing, map[string]any{"positionMs": 0}), 404, "missing book create")

	// And a delete against a book nobody can see says so, rather than
	// telling the caller the bookmark it named is gone. Two things can
	// be missing on this route and the message has to say which.
	resp = h.deleteReq(t, missing+"/"+later.Id)
	if resp.StatusCode != 404 {
		resp.Body.Close()
		t.Fatalf("delete under a missing book = %d, want 404", resp.StatusCode)
	}
	if msg := decode[Error](t, resp).Message; !strings.Contains(msg, "no book with pid") {
		t.Fatalf("delete under a missing book said %q, want it to name the book", msg)
	}
}
