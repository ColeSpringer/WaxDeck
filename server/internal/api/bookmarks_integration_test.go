package api

import (
	"context"
	"crypto/rand"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/oklog/ulid/v2"

	"github.com/colespringer/waxdeck/fixtures"
)

// TestBookmarksEndToEnd is the acceptance for API item 1: a listener
// marks places in a book, reads them back in timeline order, and
// removes one. The marks belong to the account, not to the book.
func TestBookmarksEndToEnd(t *testing.T) {
	t.Parallel()
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

	// A delete is the caller's own mark going, book or no book: refused,
	// a mark on a book out of sight would come back with it.
	wantStatus(t, h.deleteReq(t, missing+"/"+later.Id), 204, "delete under a missing book")
}

// A mark made offline carries the id the client minted, so replaying
// its create after a lost answer lands on the same bookmark.
func TestBookmarkCreateTakesTheClientsID(t *testing.T) {
	t.Parallel()
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
	const id = "bm-01JZX5N8QW3F4V9T2B7KD3M9R6"

	resp := h.postJSON(t, base, map[string]any{"id": id, "positionMs": 1500, "note": "offline"})
	if resp.StatusCode != 201 {
		resp.Body.Close()
		t.Fatalf("create with an id = %d, want 201", resp.StatusCode)
	}
	if got := decode[Bookmark](t, resp); got.Id != id || got.PositionMs != 1500 {
		t.Fatalf("created %+v, want the minted id", got)
	}

	// The replay answers the stored row, whatever the retry carried.
	resp = h.postJSON(t, base, map[string]any{"id": id, "positionMs": 9})
	if resp.StatusCode != 201 {
		resp.Body.Close()
		t.Fatalf("replay = %d, want 201", resp.StatusCode)
	}
	if got := decode[Bookmark](t, resp); got.Id != id || got.PositionMs != 1500 || deref(got.Note) != "offline" {
		t.Fatalf("replay answered %+v, want the stored bookmark", got)
	}
	// Crockford's alphabet reads either case, so one id is one bookmark.
	resp = h.postJSON(t, base, map[string]any{"id": strings.ToLower(id), "positionMs": 9})
	if resp.StatusCode != 201 {
		resp.Body.Close()
		t.Fatalf("lowercase replay = %d, want 201", resp.StatusCode)
	}
	if got := decode[Bookmark](t, resp); got.Id != id {
		t.Fatalf("lowercase replay answered %s, want the stored %s", got.Id, id)
	}
	if list := decode[BookmarkList](t, get(t, h.ts, base, h.token)); len(list.Bookmarks) != 1 {
		t.Fatalf("a replay left %d bookmarks", len(list.Bookmarks))
	}

	// The same id under another book, or another account, is a conflict.
	resp = h.postJSON(t, "/api/v1/books/"+otherBook+"/bookmarks", map[string]any{"id": id, "positionMs": 1})
	if resp.StatusCode != 409 {
		resp.Body.Close()
		t.Fatalf("id reused under another book = %d, want 409", resp.StatusCode)
	}
	if code := decode[Error](t, resp).Code; code != "conflict" {
		t.Fatalf("code = %q, want conflict", code)
	}
	resp = h.postJSON(t, "/api/v1/users", map[string]any{"username": "sam", "password": testPassword})
	resp.Body.Close()
	sam := loginAs(t, h.ts, "sam", testPassword)
	resp = reqAs(t, h, "POST", base, sam.Token, map[string]any{"id": id, "positionMs": 1})
	if resp.StatusCode != 409 {
		resp.Body.Close()
		t.Fatalf("id reused by another account = %d, want 409", resp.StatusCode)
	}
	resp.Body.Close()

	// An id that is not a bookmark pid is refused as the request's fault.
	for _, bad := range []string{"tr-01JZX5N8QW3F4V9T2B7KD3M9R6", "bm-nope", "bm-81JZX5N8QW3F4V9T2B7KD3M9R6"} {
		wantStatus(t, h.postJSON(t, base, map[string]any{"id": bad, "positionMs": 1}), 400, "malformed id "+bad)
	}

	// And a removal spelled in lowercase removes it.
	wantStatus(t, reqAs(t, h, "DELETE", base+"/"+strings.ToLower(id), h.token, nil), 204, "lowercase delete")
	if list := decode[BookmarkList](t, get(t, h.ts, base, h.token)); len(list.Bookmarks) != 0 {
		t.Fatalf("a lowercase delete left %d bookmarks", len(list.Bookmarks))
	}
}

// A replay answers what is stored, even when the book has since been
// measured shorter than the mark; a replay after the mark was removed
// says so rather than bringing it back.
func TestBookmarkReplaysAnswerWhatHappened(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	if _, err := fixtures.GenerateBook(h.library); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	book := h.items(t, "?mediaType=audiobook").Items[0].Pid
	base := "/api/v1/books/" + book + "/bookmarks"
	made := time.Date(2026, 9, 1, 12, 0, 0, 0, time.UTC)
	id := "bm-" + ulid.MustNew(ulid.Timestamp(made), rand.Reader).String()

	resp := h.postJSON(t, base, map[string]any{"id": id, "positionMs": 1500})
	if resp.StatusCode != 201 {
		resp.Body.Close()
		t.Fatalf("create = %d, want 201", resp.StatusCode)
	}
	// Made offline, it was made when the client minted its id.
	if got := decode[Bookmark](t, resp); !got.CreatedAt.Equal(made) {
		t.Fatalf("createdAt = %v, want the minted %v", got.CreatedAt, made)
	}

	resp = h.postJSON(t, base, map[string]any{"id": id, "positionMs": int64(1) << 40, "note": strings.Repeat("x", 5000)})
	if resp.StatusCode != 201 {
		resp.Body.Close()
		t.Fatalf("replay carrying what a new mark could not = %d, want 201", resp.StatusCode)
	}
	if got := decode[Bookmark](t, resp); got.PositionMs != 1500 {
		t.Fatalf("replay answered %+v, want the stored mark", got)
	}

	wantStatus(t, h.deleteReq(t, base+"/"+id), 204, "delete")
	resp = h.postJSON(t, base, map[string]any{"id": id, "positionMs": 1500})
	if resp.StatusCode != 409 {
		resp.Body.Close()
		t.Fatalf("replay after the removal = %d, want 409", resp.StatusCode)
	}
	if e := decode[Error](t, resp); e.Code != "conflict" || e.Params == nil || (*e.Params)["reason"] != "removed" {
		t.Fatalf("replay after the removal answered %+v, want conflict with reason removed", e)
	}
	if list := decode[BookmarkList](t, get(t, h.ts, base, h.token)); len(list.Bookmarks) != 0 {
		t.Fatalf("the replay brought back %d bookmarks", len(list.Bookmarks))
	}
}

// A mark on a book its owner can no longer see still goes when they ask:
// it is theirs, and a delete refused over the book comes back with it.
func TestABookmarkOnAHiddenBookCanStillBeRemoved(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	if _, err := fixtures.GenerateBook(h.library); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	book := h.items(t, "?mediaType=audiobook").Items[0].Pid
	base := "/api/v1/books/" + book + "/bookmarks"
	resp := h.postJSON(t, base, map[string]any{"positionMs": 1500})
	if resp.StatusCode != 201 {
		resp.Body.Close()
		t.Fatalf("create = %d, want 201", resp.StatusCode)
	}
	mark := decode[Bookmark](t, resp)

	ctx := context.Background()
	uc, err := h.svc.UserCtxByID(ctx, adminUserID(t, h))
	if err != nil {
		t.Fatal(err)
	}
	hidden := *uc
	hidden.AllLibraries, hidden.Libraries = false, map[string]bool{}
	if err := h.svc.DeleteBookmark(ctx, &hidden, book, mark.Id); err != nil {
		t.Fatalf("deleting a mark on a book out of sight = %v, want it gone", err)
	}
	if list := decode[BookmarkList](t, get(t, h.ts, base, h.token)); len(list.Bookmarks) != 0 {
		t.Fatalf("the mark is back with the book: %d bookmarks", len(list.Bookmarks))
	}
}

// The cap is still the request's fault, answered 400 rather than the
// conflict a reused id is.
func TestBookmarkCapIsStillInvalidRequest(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	if _, err := fixtures.GenerateBook(h.library); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	book := h.items(t, "?mediaType=audiobook").Items[0].Pid
	base := "/api/v1/books/" + book + "/bookmarks"
	for i := range 200 {
		resp := h.postJSON(t, base, map[string]any{"positionMs": i})
		if resp.StatusCode != 201 {
			resp.Body.Close()
			t.Fatalf("mark %d = %d", i, resp.StatusCode)
		}
		resp.Body.Close()
	}
	resp := h.postJSON(t, base, map[string]any{"positionMs": 1})
	if resp.StatusCode != 400 {
		resp.Body.Close()
		t.Fatalf("mark past the cap = %d, want 400", resp.StatusCode)
	}
	if code := decode[Error](t, resp).Code; code != "invalid-request" {
		t.Fatalf("code = %q, want invalid-request", code)
	}
}

// The user delta carries a book's whole bookmark list when one is made
// or removed, so an offline device can mirror it.
func TestBookmarksRideTheUserDelta(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	if _, err := fixtures.GenerateBook(h.library); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	book := h.items(t, "?mediaType=audiobook").Items[0].Pid
	base := "/api/v1/books/" + book + "/bookmarks"
	mint := decode[ServerSyncPage](t, get(t, h.ts, "/api/v1/sync/server", h.token))

	first := decode[Bookmark](t, h.postJSON(t, base, map[string]any{"positionMs": 1000, "note": "one"}))
	second := decode[Bookmark](t, h.postJSON(t, base, map[string]any{"positionMs": 2000}))
	wantStatus(t, h.deleteReq(t, base+"/"+first.Id), 204, "delete")
	// A delete of what is already gone changes nothing and says nothing.
	wantStatus(t, h.deleteReq(t, base+"/"+first.Id), 204, "repeat delete")

	page := decode[ServerSyncPage](t, get(t, h.ts, "/api/v1/sync/server?since="+mint.NextSince, h.token))
	var marks []ServerSyncEvent
	for _, ev := range page.Events {
		if ev.Kind == "bookmarks" {
			marks = append(marks, ev)
		}
	}
	if len(marks) != 1 {
		t.Fatalf("delta carries %d bookmark events, want one per book: %+v", len(marks), page.Events)
	}
	ev := marks[0]
	if ev.Pid == nil || *ev.Pid != book {
		t.Fatalf("bookmark event pid = %v, want %s", ev.Pid, book)
	}
	if ev.Bookmarks == nil || len(*ev.Bookmarks) != 1 || (*ev.Bookmarks)[0].Id != second.Id {
		t.Fatalf("bookmark event list = %+v, want only the surviving mark", ev.Bookmarks)
	}

	// Removing the last one still says so: an empty list, not an absent one.
	wantStatus(t, h.deleteReq(t, base+"/"+second.Id), 204, "delete the last")
	page = decode[ServerSyncPage](t, get(t, h.ts, "/api/v1/sync/server?since="+page.NextSince, h.token))
	for _, ev := range page.Events {
		if ev.Kind == "bookmarks" {
			if ev.Bookmarks == nil || len(*ev.Bookmarks) != 0 {
				t.Fatalf("emptied book's list = %+v, want present and empty", ev.Bookmarks)
			}
			return
		}
	}
	t.Fatalf("deleting the last mark emitted no bookmarks event: %+v", page.Events)
}
