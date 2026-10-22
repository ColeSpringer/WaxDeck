package api

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"

	"github.com/oklog/ulid/v2"

	"github.com/colespringer/waxdeck/server/internal/db"
)

// Subsonic bookmarks hold for every kind of item. A track's is its own,
// and leaves the track's resume position alone; an episode's is the
// episode's resume position, the one the WaxDeck apps resume from. The
// comment rides along, the username is the account that asked (apiKey
// auth names no user on the request), and an id the caller cannot see is
// error 70.
func TestSubsonicBookmarksForEveryKind(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	feed := newFeedServer(t, 1)
	decodeStatus[Subscription](t, h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()}), 201, "subscribe")
	secret := newSubsonicSecret(t, h)
	const c = "Symfonium"

	track := subsonicSongID(t, h, secret, "Alpha")
	env := mustOK(t, h, secret, c, "getPodcasts", "&includeEpisodes=true")
	var episode string
	for _, ch := range jlist(jmap(env["podcasts"])["channel"]) {
		for _, ep := range jlist(jmap(ch)["episode"]) {
			episode = fmt.Sprint(jmap(ep)["id"])
		}
	}
	if episode == "" {
		t.Fatal("no episode to bookmark")
	}

	apiKey := func(view, extra string) map[string]any {
		t.Helper()
		return clientCallAs(t, h, subsonicAccount{username: "admin", secret: secret}, view, extra)
	}
	for _, q := range []string{
		"&id=" + track + "&position=5000&comment=" + url.QueryEscape("the chorus"),
		"&id=" + episode + "&position=9000&comment=" + url.QueryEscape("after the ads"),
	} {
		if env := apiKey("createBookmark", q); env["status"] != "ok" {
			t.Fatalf("createBookmark%s = %v", q, env)
		}
	}

	env = apiKey("getBookmarks", "")
	got := map[string]map[string]any{}
	for _, b := range jlist(jmap(env["bookmarks"])["bookmark"]) {
		got[fmt.Sprint(jmap(jmap(b)["entry"])["id"])] = jmap(b)
	}
	if b := got[track]; len(got) != 2 || b["position"] != float64(5000) || b["comment"] != "the chorus" || b["username"] != "admin" {
		t.Fatalf("getBookmarks = %v, want the track at 5000 with its comment, as admin", env["bookmarks"])
	}
	if b := got[episode]; b["position"] != float64(9000) || b["comment"] != "after the ads" || b["created"] == nil || b["changed"] == nil {
		t.Fatalf("episode bookmark = %v", b)
	}

	// The entries themselves carry the bookmark, which is where DSub and
	// Ultrasonic seek from when the item is played from a listing.
	if s := jmap(apiKey("getSong", "&id="+track)["song"]); s["bookmarkPosition"] != float64(5000) {
		t.Errorf("the bookmarked track's song = %v, want bookmarkPosition 5000", s)
	}
	for _, ch := range jlist(jmap(apiKey("getPodcasts", "&includeEpisodes=true")["podcasts"])["channel"]) {
		for _, ep := range jlist(jmap(ch)["episode"]) {
			if m := jmap(ep); m["id"] == episode && m["bookmarkPosition"] != float64(9000) {
				t.Errorf("the bookmarked episode = %v, want bookmarkPosition 9000", m)
			}
		}
	}
	for id, b := range got {
		if e := jmap(b["entry"]); e["bookmarkPosition"] != b["position"] {
			t.Errorf("bookmark entry %s = %v, want bookmarkPosition %v", id, e, b["position"])
		}
	}

	trackState := decode[PlayState](t, get(t, h.ts, "/api/v1/items/"+track+"/play-state", h.token))
	if trackState.PositionMs != 0 {
		t.Errorf("a track's bookmark moved its resume position to %d", trackState.PositionMs)
	}
	epState := decode[PlayState](t, get(t, h.ts, "/api/v1/items/"+episode+"/play-state", h.token))
	if epState.PositionMs != 9000 {
		t.Errorf("an episode's bookmark left its resume position at %d, want 9000", epState.PositionMs)
	}

	hidden := "tr-" + ulid.Make().String()
	for _, view := range []string{"createBookmark", "deleteBookmark"} {
		env := apiKey(view, "&id="+hidden+"&position=1")
		if env["status"] != "failed" || jmap(env["error"])["code"] != float64(70) {
			t.Errorf("%s of an unknown id = %v, want error 70", view, env)
		}
	}
	for _, q := range []string{"", "&id=" + track, "&id=" + track + "&position=-1"} {
		env := apiKey("createBookmark", q)
		if env["status"] != "failed" || jmap(env["error"])["code"] != float64(10) {
			t.Errorf("createBookmark%s = %v, want error 10", q, env)
		}
	}

	for _, id := range []string{track, episode} {
		if env := apiKey("deleteBookmark", "&id="+id); env["status"] != "ok" {
			t.Fatalf("deleteBookmark %s = %v", id, env)
		}
	}
	if b := jlist(jmap(apiKey("getBookmarks", "")["bookmarks"])["bookmark"]); len(b) != 0 {
		t.Fatalf("getBookmarks after deleting both = %v", b)
	}
	epState = decode[PlayState](t, get(t, h.ts, "/api/v1/items/"+episode+"/play-state", h.token))
	if epState.PositionMs != 0 {
		t.Errorf("deleting an episode's bookmark left its resume position at %d", epState.PositionMs)
	}
}

// Past the cap a new bookmark is the protocol's generic error with the
// sentence saying why, which a client shows rather than retrying.
func TestSubsonicBookmarkCapOnTheWire(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	secret := newSubsonicSecret(t, h)
	ctx := context.Background()
	admin, err := h.store.UserByUsername(ctx, "admin")
	if err != nil {
		t.Fatal(err)
	}
	uc, err := h.svc.UserCtx(ctx, admin)
	if err != nil {
		t.Fatal(err)
	}
	// Rows count toward the cap only for items the account can list, so
	// the cap is filled with the episodes of a show it follows, none of
	// them fetched: nothing to scan.
	feed := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var items strings.Builder
		for i := range db.SubsonicBookmarkCap {
			fmt.Fprintf(&items, `<item><title>Cap %d</title><guid isPermaLink="false">cap-%d</guid>`+
				`<enclosure url="http://%s/cap-%d.mp3" type="audio/mpeg" length="1000"/></item>`, i, i, r.Host, i)
		}
		w.Header().Set("Content-Type", "application/rss+xml")
		fmt.Fprintf(w, `<?xml version="1.0" encoding="UTF-8"?><rss version="2.0"><channel><title>Cap Show</title>%s</channel></rss>`, items.String())
	}))
	t.Cleanup(feed.Close)
	sub := decodeStatus[Subscription](t, h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.URL + "/feed.xml"}), 201, "subscribe")
	filled := 0
	for cursor := ""; ; {
		eps, next, err := h.svc.Episodes(ctx, uc, sub.Show.Pid, cursor, 100)
		if err != nil {
			t.Fatal(err)
		}
		for _, ep := range eps {
			if err := h.store.PutSubsonicBookmark(ctx, db.SubsonicBookmark{
				UserID: admin.ID, ItemPID: ep.PID, PositionMS: 1, Comment: "kept", CreatedAtNS: 1, UpdatedAtNS: 1,
			}); err != nil {
				t.Fatal(err)
			}
			filled++
		}
		if cursor = next; cursor == "" {
			break
		}
	}
	if filled != db.SubsonicBookmarkCap {
		t.Fatalf("the feed made %d episodes to fill the cap with, want %d", filled, db.SubsonicBookmarkCap)
	}
	track := subsonicSongID(t, h, secret, "Alpha")
	env := clientCall(t, h, secret, "test", "createBookmark", "&id="+track+"&position=1000")
	e := jmap(env["error"])
	if env["status"] != "failed" || e["code"] != float64(0) || !strings.Contains(fmt.Sprint(e["message"]), "delete one first") {
		t.Fatalf("a bookmark past the cap = %v, want error 0 saying to delete one first", env)
	}
}

// A finished book has no resume point, so it is no bookmark and its entry
// carries no bookmarkPosition; a bookmark a client saves on it afterwards
// lists where the client saved it.
func TestSubsonicAFinishedBookIsNoBookmark(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	secret := newSubsonicSecret(t, h)
	book, _ := subsonicBook(t, h)
	ctx := context.Background()
	admin, err := h.store.UserByUsername(ctx, "admin")
	if err != nil {
		t.Fatal(err)
	}
	uc, err := h.svc.UserCtx(ctx, admin)
	if err != nil {
		t.Fatal(err)
	}
	it, err := h.svc.Item(ctx, uc, book)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := h.svc.Checkpoint(ctx, uc, book, it.DurationMS, nil); err != nil {
		t.Fatal(err)
	}
	if st := decode[PlayState](t, get(t, h.ts, "/api/v1/items/"+book+"/play-state", h.token)); !st.Finished {
		t.Fatalf("play state at the end = %+v, want finished", st)
	}
	bookmarked := func() (float64, bool) {
		t.Helper()
		for _, b := range jlist(jmap(mustOK(t, h, secret, "test", "getBookmarks", "")["bookmarks"])["bookmark"]) {
			if jmap(jmap(b)["entry"])["id"] == book {
				return jmap(b)["position"].(float64), true
			}
		}
		return 0, false
	}
	if at, ok := bookmarked(); ok {
		t.Errorf("the finished book is a bookmark at %v", at)
	}
	if s := jmap(mustOK(t, h, secret, "test", "getSong", "&id="+book)["song"]); s["bookmarkPosition"] != nil {
		t.Errorf("the finished book's entry = %v, want no bookmarkPosition", s)
	}
	mustOK(t, h, secret, "test", "createBookmark", "&id="+book+"&position=6500")
	if at, ok := bookmarked(); !ok || at != 6500 {
		t.Errorf("a bookmark saved on the finished book = %v (%v), want it listed at 6500", at, ok)
	}
	if s := jmap(mustOK(t, h, secret, "test", "getSong", "&id="+book)["song"]); s["bookmarkPosition"] != float64(6500) {
		t.Errorf("the entry after the save = %v, want bookmarkPosition 6500", s)
	}
	// Played to the end again: still no resume point, so the bookmark
	// stays where it was saved.
	if _, err := h.svc.Checkpoint(ctx, uc, book, it.DurationMS, nil); err != nil {
		t.Fatal(err)
	}
	if at, ok := bookmarked(); !ok || at != 6500 {
		t.Errorf("the saved bookmark after another finish = %v (%v), want 6500", at, ok)
	}
	if s := jmap(mustOK(t, h, secret, "test", "getSong", "&id="+book)["song"]); s["bookmarkPosition"] != float64(6500) {
		t.Errorf("the entry after another finish = %v, want bookmarkPosition 6500", s)
	}
	// A save at the start clears it, as it does a book in progress.
	mustOK(t, h, secret, "test", "createBookmark", "&id="+book+"&position=0")
	if at, ok := bookmarked(); ok {
		t.Errorf("a bookmark saved at 0 on the finished book is listed at %v, want none", at)
	}
}
