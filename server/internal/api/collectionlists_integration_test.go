package api

import (
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
)

// browsePage reads one page of a discovery list.
func browsePage(t *testing.T, h *harness, query string) ItemPage {
	t.Helper()
	resp := get(t, h.ts, "/api/v1/library/browse"+query, h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("browse%s status = %d", query, resp.StatusCode)
	}
	return decode[ItemPage](t, resp)
}

func pids(page ItemPage) map[string]bool {
	out := map[string]bool{}
	for _, it := range page.Items {
		out[it.Pid] = true
	}
	return out
}

// reportListen counts one full play of an item, which is what moves an
// item between the collection lists.
func reportListen(t *testing.T, h *harness, sessionID, pid string, durationMS int64) {
	t.Helper()
	resp := h.postJSON(t, "/api/v1/listens", map[string]any{
		"sessions": []map[string]any{{
			"sessionId": sessionID,
			"pid":       pid,
			"startedAt": time.Now().UTC().Format(time.RFC3339),
			"msPlayed":  durationMS,
			"finished":  true,
		}},
	})
	wantStatus(t, resp, 200, "report a listen")
}

// TestCollectionBrowseListsOverHTTP drives the two lists the home
// shelves are built on. Both are selections over the caller's own play
// state rather than orderings, and both are per-user, which is the half
// a shared instance gets wrong: one listener's untouched album is
// another's most played.
func TestCollectionBrowseListsOverHTTP(t *testing.T) {
	t.Parallel()
	h := newHarness(t)

	all := h.items(t, "?mediaType=music")
	if len(all.Items) < 3 {
		t.Fatalf("the demo library listed %d tracks; this needs several", len(all.Items))
	}

	// Nothing has been played, so everything is never-played.
	sealed := browsePage(t, h, "?list=never-played")
	if len(sealed.Items) != len(all.Items) {
		t.Fatalf("never-played holds %d of %d untouched items", len(sealed.Items), len(all.Items))
	}
	// And nothing is starred or rated, so nothing is worth rediscovering.
	if forgotten := browsePage(t, h, "?list=rediscover"); len(forgotten.Items) != 0 {
		t.Fatalf("rediscover holds %d items in a library nobody has marked", len(forgotten.Items))
	}

	// Playing one item through takes it off the sealed shelf. A reported
	// listen rather than a checkpoint: a resume position is not a play,
	// and the shelf counts plays, which is what the contract says.
	played := all.Items[0].Pid
	reportListen(t, h, "sealed-a", played, all.Items[0].DurationMs)
	sealed = browsePage(t, h, "?list=never-played")
	if pids(sealed)[played] {
		t.Fatal("never-played still holds the item that was just played")
	}
	if len(sealed.Items) != len(all.Items)-1 {
		t.Fatalf("never-played holds %d, want %d", len(sealed.Items), len(all.Items)-1)
	}

	// Starring something never played puts it on the rediscover shelf:
	// "not played in the last six months" covers never, which is exactly
	// what a listener who starred an album and never got to it means.
	starred := all.Items[1].Pid
	resp := putJSON(t, h.ts, "/api/v1/items/"+starred+"/star", h.token, map[string]any{"starred": true})
	wantStatus(t, resp, 200, "star")
	forgotten := browsePage(t, h, "?list=rediscover")
	if len(forgotten.Items) != 1 || forgotten.Items[0].Pid != starred {
		t.Fatalf("rediscover = %+v, want just the starred item", forgotten.Items)
	}

	// A high rating counts as a star does; a low one does not.
	rated := all.Items[2].Pid
	resp = putJSON(t, h.ts, "/api/v1/items/"+rated+"/rating", h.token, map[string]any{"rating": 100})
	wantStatus(t, resp, 200, "rate high")
	if got := pids(browsePage(t, h, "?list=rediscover")); !got[rated] {
		t.Fatal("a well-rated, long-unplayed item is not on the rediscover shelf")
	}
	resp = putJSON(t, h.ts, "/api/v1/items/"+rated+"/rating", h.token, map[string]any{"rating": 20})
	wantStatus(t, resp, 200, "rate low")
	if got := pids(browsePage(t, h, "?list=rediscover")); got[rated] {
		t.Fatal("a poorly rated item is on the rediscover shelf")
	}

	// Playing the starred item now takes it off: recent listening is what
	// rediscover is the complement of.
	reportListen(t, h, "rediscover-a", starred, all.Items[1].DurationMs)
	if got := pids(browsePage(t, h, "?list=rediscover")); got[starred] {
		t.Fatal("rediscover still holds an item played moments ago")
	}

	// Per user, like every other play-derived list: a second listener has
	// touched none of it.
	resp = h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "sealed-listener", "password": "long-enough-pw",
	})
	wantStatus(t, resp, 201, "create the second listener")
	other := loginAs(t, h.ts, "sealed-listener", "long-enough-pw").Token
	resp = get(t, h.ts, "/api/v1/library/browse?list=never-played", other)
	if page := decode[ItemPage](t, resp); len(page.Items) != len(all.Items) {
		t.Fatalf("the second listener's never-played holds %d of %d", len(page.Items), len(all.Items))
	}

	// Authenticated like the rest of the browse surface.
	wantStatus(t, get(t, h.ts, "/api/v1/library/browse?list=never-played", ""), 401, "unauthenticated")
	// And still a closed vocabulary.
	wantStatus(t, get(t, h.ts, "/api/v1/library/browse?list=forgotten", h.token), 400, "unknown list")
}

// TestBrowseMediaTypeFilterOverHTTP covers the domain-scoped shelf: the
// same list, narrowed to one medium. The narrowing is a post-filter on
// the catalog's own window, so the contract promises only that what
// comes back is of the asked-for type and that the cursor still walks
// the whole list; both are asserted here rather than a page length.
func TestBrowseMediaTypeFilterOverHTTP(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	if _, err := fixtures.GenerateBook(h.library); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)

	music := h.items(t, "?mediaType=music")
	books := h.items(t, "?mediaType=audiobook")
	if len(music.Items) == 0 || len(books.Items) == 0 {
		t.Fatalf("this needs both media types: %d music, %d books", len(music.Items), len(books.Items))
	}

	// Every list takes the filter, including the two collection lists,
	// which answer it through the query rather than through the window.
	for _, list := range []string{"recently-added", "alphabetical", "never-played"} {
		page := browsePage(t, h, "?list="+list+"&mediaType=music&limit=500")
		if len(page.Items) == 0 {
			t.Fatalf("%s scoped to music came back empty", list)
		}
		for _, it := range page.Items {
			if it.MediaType != "music" {
				t.Fatalf("%s scoped to music returned a %s item", list, it.MediaType)
			}
		}
		if len(page.Items) != len(music.Items) {
			t.Fatalf("%s scoped to music held %d of %d tracks", list, len(page.Items), len(music.Items))
		}
	}

	// And the other way: the book is what an audiobook-scoped shelf sees.
	shelf := browsePage(t, h, "?list=recently-added&mediaType=audiobook&limit=500")
	if len(shelf.Items) != len(books.Items) {
		t.Fatalf("an audiobook shelf held %d of %d books", len(shelf.Items), len(books.Items))
	}

	// Walking the cursor covers the whole list, short pages and all: the
	// filter never strands an item behind a page that came back empty.
	seen := map[string]bool{}
	cursor := ""
	for range len(music.Items) + len(books.Items) + 2 {
		query := "?list=alphabetical&mediaType=music&limit=1"
		if cursor != "" {
			query += "&cursor=" + cursor
		}
		page := browsePage(t, h, query)
		for _, it := range page.Items {
			seen[it.Pid] = true
		}
		if page.NextCursor == nil {
			break
		}
		cursor = *page.NextCursor
	}
	if len(seen) != len(music.Items) {
		t.Fatalf("paging a filtered list one row at a time found %d of %d tracks", len(seen), len(music.Items))
	}

	// An unknown media type fails closed rather than silently listing
	// everything, the way the item listing already does.
	wantStatus(t, get(t, h.ts, "/api/v1/library/browse?list=newest&mediaType=video", h.token),
		400, "unknown mediaType")
}
