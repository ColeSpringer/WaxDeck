package api

import (
	"context"
	"encoding/json"
	"net/http"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"
)

// catalogFrameNames reports a catalog invalidation and the pids it names,
// nil for one that names none, bare or unnamed.
func catalogFrameNames(f map[string]any) (names []string, ok bool) {
	if f["type"] != "invalidate" || f["topic"] != "catalog" {
		return nil, false
	}
	raw, _ := f["pids"].([]any)
	for _, v := range raw {
		if s, isString := v.(string); isString {
			names = append(names, s)
		}
	}
	return names, true
}

// leftUnnamed reports whether the frame carries the marker for entities
// it does not name, which on the wire is the literal true or no key.
func leftUnnamed(t *testing.T, f map[string]any) bool {
	t.Helper()
	v, has := f["unnamed"]
	if has && v != true {
		t.Fatalf("a frame carries unnamed as %v, want true or no key: %v", v, f)
	}
	return has
}

// returningCatalogFrame subscribes as a client that presents a catalog
// cursor does and answers the invalidation it is sent for that.
func returningCatalogFrame(t *testing.T, h *harness, token, cursor string) map[string]any {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	conn, _, err := websocket.Dial(ctx, "ws"+strings.TrimPrefix(h.ts.URL, "http")+"/api/v1/ws", &websocket.DialOptions{
		HTTPHeader: http.Header{"Authorization": []string{"Bearer " + token}},
	})
	if err != nil {
		t.Fatalf("dialing ws: %v", err)
	}
	defer conn.Close(websocket.StatusNormalClosure, "")
	sub, _ := json.Marshal(map[string]any{"topics": []string{"catalog"}, "catalogSince": cursor})
	if err := conn.Write(ctx, websocket.MessageText, sub); err != nil {
		t.Fatalf("subscribing: %v", err)
	}
	for {
		_, msg, err := conn.Read(ctx)
		if err != nil {
			t.Fatalf("waiting for the subscribe-time invalidation: %v", err)
		}
		var f map[string]any
		if err := json.Unmarshal(msg, &f); err != nil {
			t.Fatalf("frame %s: %v", msg, err)
		}
		if _, catalog := catalogFrameNames(f); catalog {
			return f
		}
	}
}

// catalogCursorOf is the cursor the account's pull is handed now.
func catalogCursorOf(t *testing.T, h *harness, token string) string {
	t.Helper()
	page := decode[CatalogSyncPage](t, get(t, h.ts, "/api/v1/sync/catalog?limit=1", token))
	if page.NextSince == "" {
		t.Fatal("the snapshot handed no cursor")
	}
	return page.NextSince
}

// frameSince is the position a catalog frame carries, failing a frame
// that carries none.
func frameSince(t *testing.T, f map[string]any) string {
	t.Helper()
	since, _ := f["since"].(string)
	if since == "" {
		t.Fatalf("a catalog frame carries no since: %v", f)
	}
	return since
}

// atTheHead reports whether the frame says nothing in the catalog moved
// and nothing else: type, topic, since and unchanged alone.
func atTheHead(t *testing.T, f map[string]any) bool {
	t.Helper()
	frameSince(t, f)
	return f["unchanged"] == true && len(f) == 4
}

// bareCatalogFrame reports whether the frame carries type, topic and
// since alone: it says nothing of which entities changed.
func bareCatalogFrame(t *testing.T, f map[string]any) bool {
	t.Helper()
	frameSince(t, f)
	return len(f) == 3
}

// quietCatalog waits for the change feed to stand still and for the
// frames that answered it to have reached the sockets, then forgets
// them: the startup scan's invalidation can land after a connect, and a
// late row of its own would ride the frame a test is about to read.
func quietCatalog(t *testing.T, h *harness, sockets ...*wsClient) {
	t.Helper()
	deadline := time.Now().Add(15 * time.Second)
	last, stable := h.svc.CatalogTailSeq(), 0
	for stable < 10 {
		if time.Now().After(deadline) {
			t.Fatal("the catalog change feed never settled")
		}
		time.Sleep(50 * time.Millisecond)
		if now := h.svc.CatalogTailSeq(); now == last {
			stable++
		} else {
			last, stable = now, 0
		}
	}
	for _, c := range sockets {
		for drained := false; !drained; {
			select {
			case <-c.recv:
			default:
				drained = true
			}
		}
	}
}

// catalogFramesUntilQuiet reads the catalog invalidations the socket is
// sent, waiting for the first and then until none has come for a while.
func catalogFramesUntilQuiet(t *testing.T, c *wsClient) []map[string]any {
	t.Helper()
	const quiet = time.Second
	var frames []map[string]any
	wait := time.After(10 * time.Second)
	for {
		select {
		case f, ok := <-c.recv:
			if !ok {
				t.Fatal("socket closed while its catalog frames were read")
			}
			if _, catalog := catalogFrameNames(f); catalog {
				frames = append(frames, f)
				wait = time.After(quiet)
			}
		case <-wait:
			if len(frames) == 0 {
				t.Fatal("no catalog frame arrived")
			}
			return frames
		}
	}
}

// newestSince reads the socket's catalog frames until none has come for
// a while and returns the position of the last, or of first when none
// came after it.
func newestSince(t *testing.T, c *wsClient, first map[string]any) string {
	t.Helper()
	since := frameSince(t, first)
	for {
		select {
		case f, ok := <-c.recv:
			if !ok {
				t.Fatal("socket closed while its catalog frames were read")
			}
			if _, catalog := catalogFrameNames(f); catalog {
				since = frameSince(t, f)
			}
		case <-time.After(time.Second):
			return since
		}
	}
}

// The catalog invalidation a socket is sent names what moved, a track
// and the album that may draw its cover, for an account nothing narrows
// and for one granted the library that holds them. A frame carries names
// or the marker, never both, and every one carries the position it covers
// up to. A client that subscribes presenting a cursor is told what
// changed after it: nothing at the head, the track and its album behind
// the change, and nothing again for the position a live frame carried;
// one presenting what is not a cursor is told the marker. Once the
// account sees every library, the socket it already holds is still sent
// names.
func TestTheCatalogFrameNamesWhatMovedOnTheSocket(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	type track struct{ pid, album string }
	var tracks []track
	for _, it := range h.items(t, "").Items {
		if it.AlbumPid != nil && *it.AlbumPid != "" {
			tracks = append(tracks, track{it.Pid, *it.AlbumPid})
		}
	}
	if len(tracks) < 2 {
		t.Fatalf("the demo library has %d tracks in albums, want two", len(tracks))
	}
	var music string
	for _, lib := range decode[Libraries](t, get(t, h.ts, "/api/v1/libraries", h.token)).Libraries {
		if lib.Path != nil && *lib.Path == h.library {
			music = lib.Pid
		}
	}
	if music == "" {
		t.Fatal("no library at the music root")
	}
	created := decode[struct {
		ID string `json:"id"`
	}](t, h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "music-only", "password": testPassword,
		"libraryAccess": map[string]any{"mode": "granted", "libraryPids": []string{music}},
	}))
	if created.ID == "" {
		t.Fatal("the library-restricted account was not created")
	}

	whole := dialWS(t, h, h.token, "catalog")
	narrowed := dialWS(t, h, loginAs(t, h.ts, "music-only", testPassword).Token, "catalog")
	names := func(f map[string]any, tr track) bool {
		t.Helper()
		names, ok := catalogFrameNames(f)
		if ok && len(names) > 0 && leftUnnamed(t, f) {
			t.Fatalf("a frame carries names and the unnamed marker: %v", f)
		}
		return ok && slices.Contains(names, tr.pid) && slices.Contains(names, tr.album)
	}
	named := func(c *wsClient, what string, tr track) map[string]any {
		t.Helper()
		return c.expectWhere(what, func(f map[string]any) bool { return names(f, tr) })
	}

	quietCatalog(t, h, whole, narrowed)
	narrowedToken := loginAs(t, h.ts, "music-only", testPassword).Token
	cursors := map[string]string{}
	for _, token := range []string{h.token, narrowedToken} {
		// A row landing after the cursor is named by the contract, so only
		// a frame that is never bare is a failure.
		var f map[string]any
		for range 5 {
			cursors[token] = catalogCursorOf(t, h, token)
			if f = returningCatalogFrame(t, h, token, cursors[token]); atTheHead(t, f) {
				break
			}
			quietCatalog(t, h, whole, narrowed)
		}
		if !atTheHead(t, f) {
			t.Fatalf("the subscribe-time invalidation at the head = %v every time, want type, topic, since and unchanged alone", f)
		}
	}
	wantStatus(t, metadataPutBytes(t, h.ts, "/api/v1/items/"+tracks[0].pid+"/artwork", h.token, tinyPNG(t)),
		200, "set the first track's cover")
	live := newestSince(t, whole, named(whole, "a catalog frame naming the track and its album", tracks[0]))
	frameSince(t, named(narrowed, "a catalog frame naming the track and its album for the granted account", tracks[0]))

	if f := returningCatalogFrame(t, h, h.token, cursors[h.token]); !names(f, tracks[0]) {
		t.Fatalf("subscribing behind the cover = %v, want the track %s and its album %s named", f, tracks[0].pid, tracks[0].album)
	}
	if f := returningCatalogFrame(t, h, narrowedToken, cursors[narrowedToken]); !names(f, tracks[0]) {
		t.Fatalf("the granted account subscribing behind the cover = %v, want the track %s and its album %s named", f, tracks[0].pid, tracks[0].album)
	}
	if f := returningCatalogFrame(t, h, h.token, live); !atTheHead(t, f) {
		t.Fatalf("subscribing at the live frame's since = %v, want type, topic, since and unchanged alone", f)
	}
	if f := returningCatalogFrame(t, h, h.token, "1|1"); !leftUnnamed(t, f) || frameSince(t, f) == "" {
		t.Fatalf("subscribing with what is not a cursor = %v, want the unnamed marker", f)
	}

	wantStatus(t, h.patchJSON(t, "/api/v1/users/"+created.ID, map[string]any{
		"libraryAccess": map[string]any{"mode": "all"},
	}), http.StatusOK, "open every library to the account")
	quietCatalog(t, h, whole, narrowed)
	wantStatus(t, metadataPutBytes(t, h.ts, "/api/v1/items/"+tracks[1].pid+"/artwork", h.token, tinyPNG(t)),
		200, "set the second track's cover")
	named(narrowed, "a catalog frame naming the track for the account that now sees everything", tracks[1])
}

// A client that subscribes behind rows of a user's own state alone is
// told nothing in the catalog moved; one behind a genre's own row, which
// has no pid to name, is sent the bare frame, which asks for a pass.
func TestASubscribeIsToldNothingChangedOnlyWhenTheCatalogDidNot(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	tracks := h.items(t, "").Items
	if len(tracks) == 0 {
		t.Fatal("the demo library has no items")
	}
	wantStatus(t, h.patchJSON(t, "/api/v1/items/"+tracks[0].Pid+"/metadata", map[string]any{
		"fields": map[string]string{"genre": "Ambient"},
	}), 200, "give a track a genre")
	genre := ""
	for _, b := range decode[FacetPage](t, get(t, h.ts, "/api/v1/library/facets?dimension=genre", h.token)).Buckets {
		if b.Label == "Ambient" {
			genre = b.Key
		}
	}
	if genre == "" {
		t.Fatal("no genre bucket for the track's genre")
	}

	// A row of the scan's landing after the cursor is a change by the
	// contract, so only an answer that is never unchanged is a failure.
	var cursor string
	var f map[string]any
	for i := range 5 {
		quietCatalog(t, h)
		cursor = catalogCursorOf(t, h, h.token)
		wantStatus(t, h.putJSON(t, "/api/v1/items/"+tracks[0].Pid+"/star", map[string]any{"starred": i%2 == 0}),
			200, "star a track")
		if f = returningCatalogFrame(t, h, h.token, cursor); atTheHead(t, f) {
			break
		}
	}
	if !atTheHead(t, f) {
		t.Fatalf("subscribing behind a star = %v every time, want type, topic, since and unchanged alone", f)
	}
	if frameSince(t, f) == cursor {
		t.Fatalf("the answer behind a star covers up to the cursor presented, %s: no row followed it", cursor)
	}

	wantStatus(t, metadataPutBytes(t, h.ts, "/api/v1/entities/genre/gn-"+genre+"/artwork", h.token, tinyPNG(t)),
		200, "set a genre's cover")
	if f := returningCatalogFrame(t, h, h.token, cursor); !bareCatalogFrame(t, f) {
		t.Fatalf("subscribing behind a genre's cover = %v, want type, topic and since alone", f)
	}
}

// A socket of an account granted one of two libraries is sent, of what
// moved, the track in its library and that track's album, and never the
// track in the other library or its album, nor the marker for entities
// left unnamed; an administrator's socket is sent both. A subscribe
// behind the same changes is told the same.
func TestARestrictedSocketIsSentOnlyTheNamesItSees(t *testing.T) {
	t.Parallel()
	s := newGrantsScene(t)
	own := s.own(t)
	if own.AlbumPid == nil || s.hidden.AlbumPid == nil {
		t.Fatalf("the tracks have no albums: %v, %v", own.AlbumPid, s.hidden.AlbumPid)
	}
	whole := dialWS(t, s.h, s.h.token, "catalog")
	granted := dialWS(t, s.h, s.token, "catalog")
	quietCatalog(t, s.h, whole, granted)
	cursor := catalogCursorOf(t, s.h, s.token)

	for _, pid := range []string{own.Pid, s.hidden.Pid} {
		wantStatus(t, metadataPutBytes(t, s.h.ts, "/api/v1/items/"+pid+"/artwork", s.h.token, tinyPNG(t)),
			200, "set a track's cover")
	}
	told := func(what string, frames ...map[string]any) []string {
		t.Helper()
		var all []string
		for _, f := range frames {
			if leftUnnamed(t, f) {
				t.Fatalf("%s: a frame carries the unnamed marker: %v", what, f)
			}
			names, _ := catalogFrameNames(f)
			all = append(all, names...)
		}
		return all
	}
	hidden := []string{s.hidden.Pid, *s.hidden.AlbumPid}
	seen := []string{own.Pid, *own.AlbumPid}
	check := func(what string, names []string) {
		t.Helper()
		for _, pid := range seen {
			if !slices.Contains(names, pid) {
				t.Fatalf("%s: told %v, want %s among them", what, names, pid)
			}
		}
		for _, pid := range hidden {
			if slices.Contains(names, pid) {
				t.Fatalf("%s: told %v, which names %s in the library it is not granted", what, names, pid)
			}
		}
	}
	check("the granted account's socket", told("the granted account's socket", catalogFramesUntilQuiet(t, granted)...))
	if names := told("the administrator's socket", catalogFramesUntilQuiet(t, whole)...); !slices.Contains(names, s.hidden.Pid) || !slices.Contains(names, own.Pid) {
		t.Fatalf("the administrator's socket: told %v, want both tracks", names)
	}
	check("a subscribe behind both", told("a subscribe behind both", returningCatalogFrame(t, s.h, s.token, cursor)))
}
