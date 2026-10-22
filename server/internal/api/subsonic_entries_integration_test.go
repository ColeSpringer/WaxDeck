package api

import (
	"context"
	"net/http"
	"net/url"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/cast/castv2/testreceiver"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// A book is a song entry wherever the surface hands one out, so getSong
// resolves its id as it resolves a track's.
func TestSubsonicGetSongAnswersABook(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	secret := newSubsonicSecret(t, h)
	book, _ := subsonicBook(t, h)
	env := mustOK(t, h, secret, "test", "getSong", "&id="+book)
	if s := jmap(env["song"]); s["id"] != book || s["type"] != "audiobook" || s["title"] == nil {
		t.Fatalf("getSong of a book = %v, want its song entry", s)
	}
}

// A folder-mode directory carries its own star and rating, as the
// entries inside it do.
func TestSubsonicDirectoryCarriesItsMarks(t *testing.T) {
	t.Parallel()
	h, secret := albumListHarness(t)
	st := seedAlbumListState(t, h, secret)
	dir := func(id string) map[string]any {
		t.Helper()
		return jmap(mustOK(t, h, secret, "test", "getMusicDirectory", "&id="+url.QueryEscape(id))["directory"])
	}
	if d := dir(st.id("Old Record")); !recentStamp(d["starred"]) {
		t.Errorf("the starred album's directory = %v, want its star", d)
	}
	if d := dir(st.id("Mid Record")); d["userRating"] != float64(4) {
		t.Errorf("the rated album's directory = %v, want rating 4", d)
	}
	artist := st.albums["Old Record"]["artistId"].(string)
	mustOK(t, h, secret, "test", "star", "&artistId="+url.QueryEscape(artist))
	if d := dir(artist); !recentStamp(d["starred"]) {
		t.Errorf("the starred artist's directory = %v, want its star", d)
	}
}

// getNowPlaying answers the playback sessions the caller can see, each
// the item it is on with who plays it and where; another account sees
// none of them.
func TestSubsonicNowPlayingListsTheCallersSessions(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	secret := newSubsonicSecret(t, h)
	pid := subsonicSongID(t, h, secret, "Alpha")
	player := dialWS(t, h, loginAs(t, h.ts, "admin", testPassword).Token)
	player.register("Phone")
	player.send(map[string]any{
		"type": "session-report", "playing": true, "positionMs": 5000, "index": 0,
		"itemPids": []string{pid}, "queueVersion": 1,
	})
	player.expect("session")

	env := mustOK(t, h, secret, "test", "getNowPlaying", "")
	entries := jlist(jmap(env["nowPlaying"])["entry"])
	if len(entries) != 1 {
		t.Fatalf("now playing = %v, want the one session", env["nowPlaying"])
	}
	if e := jmap(entries[0]); e["id"] != pid || e["username"] != "admin" || e["playerName"] != "Phone" ||
		e["minutesAgo"] != float64(0) || e["title"] != "Alpha Song" {
		t.Fatalf("now playing entry = %v, want Alpha Song by admin on Phone, just now", e)
	}
	other := otherSubsonicAccount(t, h, "nowplaying-other")
	if got := jlist(jmap(clientCallAs(t, h, other, "getNowPlaying", "")["nowPlaying"])["entry"]); len(got) != 0 {
		t.Fatalf("another account's now playing = %v, want none", got)
	}
}

// What an account may not be offered stays out of getSong and
// getNowPlaying however it is named: a book in a library it was not
// granted, and a shared speaker's session playing a track from one.
func TestSubsonicSongsOutsideTheCallersLibrariesStayHidden(t *testing.T) {
	t.Parallel()
	h := newHarness(t, service.Root{Name: "other", Path: t.TempDir()})
	secret := newSubsonicSecret(t, h)
	book, _ := subsonicBook(t, h)
	track := subsonicSongID(t, h, secret, "Alpha")
	who := subsonicAccountWithGrants(t, h, "other-only", "other")

	if s := jmap(mustOK(t, h, secret, "test", "getSong", "&id="+book)["song"]); s["id"] != book {
		t.Fatalf("the admin's getSong of the book = %v", s)
	}
	env := clientCallAs(t, h, who, "getSong", "&id="+book)
	if env["status"] != "failed" || jmap(env["error"])["code"] != float64(70) {
		t.Errorf("getSong of a book outside the account's libraries = %v, want error 70", env)
	}

	recv := testreceiver.Start(t)
	dev := recv.Device()
	ep, err := h.connect.EndpointOnline(context.Background(), "cast", dev.Key(), "Kitchen speaker", recv.Addr(), true, false,
		dev.Dial(h.group, nil))
	if err != nil {
		t.Fatal(err)
	}
	pPost(t, h, "/api/v1/player/sessions", h.token, map[string]any{
		"endpointId": ep.ID, "itemPids": []string{track},
	}, http.StatusCreated, nil)
	if got := jlist(jmap(mustOK(t, h, secret, "test", "getNowPlaying", "")["nowPlaying"])["entry"]); len(got) != 1 {
		t.Fatalf("the admin's now playing = %v, want the speaker's session", got)
	}
	// The speaker is shared, so the account sees its session; the track
	// on it is not the account's to see.
	var live struct{ Sessions []struct{ Id string } }
	pGet(t, h, "/api/v1/player/sessions", loginAs(t, h.ts, "other-only", "other-only-pass").Token, &live)
	if len(live.Sessions) != 1 {
		t.Fatalf("the account's sessions = %+v, want the speaker's", live)
	}
	if got := jlist(jmap(clientCallAs(t, h, who, "getNowPlaying", "")["nowPlaying"])["entry"]); len(got) != 0 {
		t.Errorf("now playing for an account without the track's library = %v, want none", got)
	}
}
