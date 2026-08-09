package api

import (
	"encoding/base64"
	"net/url"
	"strings"
	"testing"
)

// Entity stars and ratings across the surfaces that carry them: the
// first-party endpoints, the Subsonic compatibility surface, and the
// independence rule that makes an entity star its own fact rather than
// a rollup of its members'.

// fixtureEntityPIDs returns the demo library's artist and album entity
// pids, read through the Subsonic index (the only surface that
// enumerates entities today).
func fixtureEntityPIDs(t *testing.T, h *harness, secret string) (artistPID, albumPID string) {
	t.Helper()
	const c = "test"
	env := mustOK(t, h, secret, c, "getArtists", "")
	for _, sec := range jlist(jmap(env["artists"])["index"]) {
		for _, a := range jlist(jmap(sec)["artist"]) {
			if id, _ := jmap(a)["id"].(string); strings.HasPrefix(id, "ar-") {
				artistPID = id
			}
		}
	}
	if artistPID == "" {
		t.Fatal("no artist entity pid in getArtists")
	}
	env = mustOK(t, h, secret, c, "getArtist", "&id="+url.QueryEscape(artistPID))
	albumPID, _ = jmap(jlist(jmap(env["artist"])["album"])[0])["id"].(string)
	if !strings.HasPrefix(albumPID, "al-") {
		t.Fatalf("album id = %q, want an entity pid", albumPID)
	}
	return artistPID, albumPID
}

func TestEntityStarAndRatingRoundTrip(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	secret := newSubsonicSecret(t, h)
	artistPID, albumPID := fixtureEntityPIDs(t, h, secret)

	for _, c := range []struct{ kind, pid, path string }{
		{"artist", artistPID, "/api/v1/artists/"},
		{"album", albumPID, "/api/v1/albums/"},
	} {
		// Untouched entities read back zero, not a 404.
		st := decode[EntityPlayState](t, get(t, h.ts, c.path+c.pid+"/play-state", h.token))
		if st.Pid != c.pid || st.Starred || st.Rating != nil {
			t.Fatalf("%s initial state = %+v, want zero", c.kind, st)
		}

		resp := h.putJSON(t, c.path+c.pid+"/star", map[string]any{"starred": true})
		if resp.StatusCode != 200 {
			t.Fatalf("%s star status = %d", c.kind, resp.StatusCode)
		}
		if st := decode[EntityPlayState](t, resp); !st.Starred {
			t.Fatalf("%s star response = %+v, want starred", c.kind, st)
		}

		resp = h.putJSON(t, c.path+c.pid+"/rating", map[string]any{"rating": 80})
		if resp.StatusCode != 200 {
			t.Fatalf("%s rating status = %d", c.kind, resp.StatusCode)
		}

		st = decode[EntityPlayState](t, get(t, h.ts, c.path+c.pid+"/play-state", h.token))
		if !st.Starred || st.Rating == nil || *st.Rating != 80 {
			t.Fatalf("%s read-back = %+v, want starred and rated 80", c.kind, st)
		}
		if st.StarredAt == nil {
			t.Errorf("%s carries no star time, which is what orders the starred list", c.kind)
		}

		// Clearing the rating is a null, and leaves the star alone.
		resp = h.putJSON(t, c.path+c.pid+"/rating", map[string]any{"rating": nil})
		if resp.StatusCode != 200 {
			t.Fatalf("%s rating clear status = %d", c.kind, resp.StatusCode)
		}
		if st := decode[EntityPlayState](t, resp); st.Rating != nil || !st.Starred {
			t.Fatalf("%s after clear = %+v, want unrated and still starred", c.kind, st)
		}

		// An out-of-range rating is a rejection, not a clamp.
		if resp := h.putJSON(t, c.path+c.pid+"/rating", map[string]any{"rating": 500}); resp.StatusCode != 400 {
			t.Errorf("%s rating 500 status = %d, want 400", c.kind, resp.StatusCode)
		}
	}

	// Both starred entities come back on the list surface.
	list := decode[StarredEntities](t, get(t, h.ts, "/api/v1/starred-entities", h.token))
	if len(list.Artists) != 1 || list.Artists[0].Pid != artistPID {
		t.Errorf("starred artists = %+v, want just %s", list.Artists, artistPID)
	}
	if len(list.Albums) != 1 || list.Albums[0].Pid != albumPID {
		t.Errorf("starred albums = %+v, want just %s", list.Albums, albumPID)
	}
	if list.Artists[0].Title == "" || list.Albums[0].Title == "" {
		t.Error("starred entities carry no display names")
	}

	// An unknown entity is a plain not-found on every path.
	const ghost = "al-01JZX5N8QW3F4V9T2B7KD3M9R6"
	if resp := get(t, h.ts, "/api/v1/albums/"+ghost+"/play-state", h.token); resp.StatusCode != 404 {
		t.Errorf("unknown album read status = %d, want 404", resp.StatusCode)
	}
	if resp := h.putJSON(t, "/api/v1/albums/"+ghost+"/star", map[string]any{"starred": true}); resp.StatusCode != 404 {
		t.Errorf("unknown album star status = %d, want 404", resp.StatusCode)
	}
}

// TestSubsonicStarMixedRequestIsAllOrNothing pins that a request naming
// several targets resolves every entity id before writing anything: a
// bad id in the batch must leave the request whole, not half-applied
// with a failure reported on top.
func TestSubsonicStarMixedRequestIsAllOrNothing(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	secret := newSubsonicSecret(t, h)
	const c = "test"
	_, albumPID := fixtureEntityPIDs(t, h, secret)
	songID := h.items(t, "").Items[0].Pid

	env := clientCall(t, h, secret, c, "star",
		"&id="+url.QueryEscape(songID)+"&albumId="+url.QueryEscape(albumPID)+"&albumId=nonsense")
	if env["status"] != "failed" {
		t.Fatalf("mixed request with a bad album id = %v, want failed", env)
	}
	if st := decode[PlayState](t, get(t, h.ts, "/api/v1/items/"+songID+"/play-state", h.token)); st.Starred {
		t.Error("the song was starred even though the request failed")
	}
	st := decode[EntityPlayState](t, get(t, h.ts, "/api/v1/albums/"+albumPID+"/play-state", h.token))
	if st.Starred {
		t.Error("the good album id was applied even though the request failed")
	}
}

// TestEntityStarIsNotAnItemStar pins the independence rule: the two live
// in separate tables upstream, and a client that wants both writes both.
func TestEntityStarIsNotAnItemStar(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	secret := newSubsonicSecret(t, h)
	_, albumPID := fixtureEntityPIDs(t, h, secret)

	if resp := h.putJSON(t, "/api/v1/albums/"+albumPID+"/star", map[string]any{"starred": true}); resp.StatusCode != 200 {
		t.Fatalf("album star status = %d", resp.StatusCode)
	}
	for _, it := range h.items(t, "").Items {
		st := decode[PlayState](t, get(t, h.ts, "/api/v1/items/"+it.Pid+"/play-state", h.token))
		if st.Starred {
			t.Fatalf("starring the album starred its track %s", it.Pid)
		}
	}
}

// TestSubsonicEntityStars drives the compatibility surface: star an
// album and an artist through the protocol's own parameters and read
// them back off getStarred2, then confirm a minted group with no
// catalog entity behind it refuses with a reason rather than claiming
// the server cannot do entity stars at all.
func TestSubsonicEntityStars(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	secret := newSubsonicSecret(t, h)
	const c = "test"
	artistPID, albumPID := fixtureEntityPIDs(t, h, secret)

	mustOK(t, h, secret, c, "star", "&albumId="+url.QueryEscape(albumPID))
	mustOK(t, h, secret, c, "star", "&artistId="+url.QueryEscape(artistPID))

	env := mustOK(t, h, secret, c, "getStarred2", "")
	albums := jlist(jmap(env["starred2"])["album"])
	artists := jlist(jmap(env["starred2"])["artist"])
	if len(albums) != 1 || jmap(albums[0])["id"] != albumPID {
		t.Fatalf("getStarred2 albums = %v, want just %s", albums, albumPID)
	}
	if len(artists) != 1 || jmap(artists[0])["id"] != artistPID {
		t.Fatalf("getStarred2 artists = %v, want just %s", artists, artistPID)
	}
	// The folder-mode twin carries the same three lists.
	env = mustOK(t, h, secret, c, "getStarred", "")
	if len(jlist(jmap(env["starred"])["album"])) != 1 {
		t.Errorf("getStarred albums = %v, want one", jmap(env["starred"])["album"])
	}

	// setRating routes an entity id to the entity surface.
	mustOK(t, h, secret, c, "setRating", "&id="+url.QueryEscape(albumPID)+"&rating=4")
	st := decode[EntityPlayState](t, get(t, h.ts, "/api/v1/albums/"+albumPID+"/play-state", h.token))
	if st.Rating == nil || *st.Rating != 80 {
		t.Fatalf("album rating after setRating=4 = %v, want 80", st.Rating)
	}

	// Unstarring goes back through the same parameters.
	mustOK(t, h, secret, c, "unstar", "&albumId="+url.QueryEscape(albumPID))
	env = mustOK(t, h, secret, c, "getStarred2", "")
	if n := len(jlist(jmap(env["starred2"])["album"])); n != 0 {
		t.Errorf("getStarred2 albums after unstar = %d, want 0", n)
	}

	// Folder mode has no albumId parameter: it stars an album or artist
	// directory through the same `id` it stars a song with, so an id in
	// either entity scheme routes to the entity surface from there too.
	mustOK(t, h, secret, c, "unstar", "&id="+url.QueryEscape(artistPID))
	env = mustOK(t, h, secret, c, "getStarred2", "")
	if n := len(jlist(jmap(env["starred2"])["artist"])); n != 0 {
		t.Errorf("getStarred2 artists after a folder-mode unstar = %d, want 0", n)
	}
	mustOK(t, h, secret, c, "star", "&id="+url.QueryEscape(artistPID))
	env = mustOK(t, h, secret, c, "getStarred2", "")
	if n := len(jlist(jmap(env["starred2"])["artist"])); n != 1 {
		t.Errorf("getStarred2 artists after a folder-mode star = %d, want 1", n)
	}

	// A pre-cutover minted id still stars the entity behind it, so a
	// client that cached one before the identifier change keeps working.
	minted := "L!" + base64.RawURLEncoding.EncodeToString(
		[]byte("Fixture Artist\x1fFixture Album"))
	mustOK(t, h, secret, c, "star", "&albumId="+url.QueryEscape(minted))
	env = mustOK(t, h, secret, c, "getStarred2", "")
	albums = jlist(jmap(env["starred2"])["album"])
	if len(albums) != 1 || jmap(albums[0])["id"] != albumPID {
		t.Fatalf("a cached minted id starred %v, want the %s entity", albums, albumPID)
	}

	// An id in neither scheme is an unknown album, not a claim that the
	// server cannot do entity stars.
	env = clientCall(t, h, secret, c, "star", "&albumId=nonsense")
	if env["status"] != "failed" {
		t.Fatalf("starring an unknown album = %v, want failed", env)
	}
	msg, _ := jmap(env["error"])["message"].(string)
	if msg != "no such album" {
		t.Errorf("refusal message = %q, want a plain not-found", msg)
	}
}
