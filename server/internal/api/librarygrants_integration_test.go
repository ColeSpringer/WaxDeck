package api

import (
	"bytes"
	"context"
	"io"
	"math"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxdeck/server/internal/connect"
	"github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// grantsScene is a server holding two music libraries and an account
// granted the first alone: the shape every library-grant pin reads from.
type grantsScene struct {
	h *harness
	// extra is the second library's root, holding hidden.
	extra      string
	libA, libB string
	// token is the account granted libA.
	token  string
	hidden ItemSummary
}

func newGrantsScene(t *testing.T) grantsScene {
	t.Helper()
	extra := t.TempDir()
	if _, err := fixtures.Generate(extra, fixtures.Spec{
		Name: "hidden", Codec: fixtures.CodecFLAC, Duration: 6 * time.Second,
		Tags: map[string]string{
			"TITLE": "Hidden Song", "ARTIST": "Hidden Artist", "ALBUM": "Hidden Album",
			"ALBUMARTIST": "Hidden Artist", "GENRE": "Hidden Genre",
		},
	}); err != nil {
		t.Fatal(err)
	}
	s := grantsScene{h: newHarness(t, service.Root{Name: "hidden", Path: extra}), extra: extra}
	for _, lib := range decode[Libraries](t, get(t, s.h.ts, "/api/v1/libraries", s.h.token)).Libraries {
		switch {
		case lib.Path != nil && *lib.Path == s.h.library:
			s.libA = lib.Pid
		case lib.Path != nil && *lib.Path == extra:
			s.libB = lib.Pid
		}
	}
	if s.libA == "" || s.libB == "" {
		t.Fatalf("libraries A=%q B=%q, want both", s.libA, s.libB)
	}
	s.token = s.account(t, "aonly", s.libA)
	s.hidden = s.h.itemTitled(t, s.h.token, "Hidden Song")
	wantStatus(t, reqAs(t, s.h, http.MethodGet, "/api/v1/items/"+s.hidden.Pid, s.token, nil), 404,
		"the second library's track, read by the account granted the first")
	return s
}

// account creates an account granted exactly libs and answers its token.
func (s grantsScene) account(t *testing.T, name string, libs ...string) string {
	t.Helper()
	wantStatus(t, s.h.postJSON(t, "/api/v1/users", map[string]any{
		"username": name, "password": testPassword,
		"libraryAccess": map[string]any{"mode": "granted", "libraryPids": libs},
	}), 201, "create "+name)
	return loginAs(t, s.h.ts, name, testPassword).Token
}

// items answers what token's listing offers.
func (s grantsScene) items(t *testing.T, token, query string) []ItemSummary {
	t.Helper()
	return decodeStatus[ItemPage](t, reqAs(t, s.h, http.MethodGet, "/api/v1/library/items?limit=500"+query, token, nil),
		200, "the item listing").Items
}

// own is a music track the granted account may see.
func (s grantsScene) own(t *testing.T) ItemSummary {
	t.Helper()
	own := s.items(t, s.token, "&mediaType=music")
	if len(own) < 2 {
		t.Fatalf("the granted account sees %d tracks, want at least 2", len(own))
	}
	return own[0]
}

// jukebox brings a shared device endpoint online, one that takes
// whatever it is sent, and answers its id.
func (s grantsScene) jukebox(t *testing.T) string {
	t.Helper()
	ep, err := s.h.connect.EndpointOnline(context.Background(), connect.KindJukebox, "grants-jukebox", "Living room", "", true, false,
		func(context.Context) (connect.Driver, error) {
			return quietDriver{events: make(chan connect.DriverEvent)}, nil
		})
	if err != nil {
		t.Fatal(err)
	}
	return ep.ID
}

// The health summary counts what its reader may see: an administrator
// reads the whole catalog, an account granted every library the same
// numbers, and an account granted one library that library's totals and
// per-rule failures, the ones its own issues list adds up to.
func TestHealthSummaryCountsTheCallersReach(t *testing.T) {
	t.Parallel()
	s := newGrantsScene(t)
	if err := s.h.svc.RunHealthSweep(context.Background()); err != nil {
		t.Fatalf("sweeping: %v", err)
	}
	summary := func(token string) HealthSummary {
		t.Helper()
		return decodeStatus[HealthSummary](t, reqAs(t, s.h, http.MethodGet, "/api/v1/library/health", token, nil), 200, "the health summary")
	}
	failing := func(token string) map[string]int {
		t.Helper()
		out := map[string]int{}
		page := decodeStatus[HealthIssuePage](t, reqAs(t, s.h, http.MethodGet, "/api/v1/library/health/issues?limit=500", token, nil), 200, "the issues")
		for _, it := range page.Items {
			for _, rule := range it.Rules {
				out[rule]++
			}
		}
		return out
	}
	both := s.account(t, "both", s.libA, s.libB)
	admin := summary(s.h.token)
	for _, who := range []struct {
		name, token string
	}{
		{"the administrator", s.h.token},
		{"an account granted every library", both},
		{"the account granted one library", s.token},
	} {
		sum := summary(who.token)
		items := len(s.items(t, who.token, ""))
		if sum.TotalItems != items || sum.EvaluatedItems != items {
			t.Errorf("%s reads %d items, %d evaluated; its listing offers %d", who.name, sum.TotalItems, sum.EvaluatedItems, items)
		}
		want := failing(who.token)
		for _, r := range sum.Rules {
			if r.Failing != want[r.Rule] {
				t.Errorf("%s reads %d items failing %s; its issues list %d", who.name, r.Failing, r.Rule, want[r.Rule])
			}
		}
		if who.token == both && math.Abs(sum.Score-admin.Score) > 1e-9 {
			t.Errorf("%s reads a score of %v, the administrator %v", who.name, sum.Score, admin.Score)
		}
	}
}

// The rule vocabulary names only the custom tag keys the caller's items
// carry, counted over those items: a key only the other library holds is
// not listed, and one both hold counts the caller's share.
func TestRuleFieldsCountTheCallersReach(t *testing.T) {
	t.Parallel()
	s := newGrantsScene(t)
	own := s.own(t)
	for _, tag := range []struct{ pid, key string }{
		{s.hidden.Pid, "ONLYB"}, {s.hidden.Pid, "BOTH"}, {own.Pid, "BOTH"},
	} {
		wantStatus(t, putJSON(t, s.h.ts, "/api/v1/items/"+tag.pid+"/tags/"+tag.key, s.h.token,
			map[string]any{"values": []string{"secret"}}), 200, "tag "+tag.key)
	}
	keys := func(token string) map[string]int {
		t.Helper()
		out := map[string]int{}
		for _, k := range decodeStatus[RuleFields](t, reqAs(t, s.h, http.MethodGet, "/api/v1/playlists/rule-fields", token, nil), 200, "rule fields").TagKeys {
			out[k.Key] = k.ItemCount
		}
		return out
	}
	if got := keys(s.h.token); got["ONLYB"] != 1 || got["BOTH"] != 2 {
		t.Errorf("the administrator reads %v, want ONLYB on 1 item and BOTH on 2", got)
	}
	got := keys(s.token)
	if _, listed := got["ONLYB"]; listed {
		t.Errorf("the granted account reads ONLYB, a key only the other library carries: %v", got)
	}
	if got["BOTH"] != 1 {
		t.Errorf("the granted account reads BOTH on %d items, want its own 1", got["BOTH"])
	}
}

// An entity's curation answers what its detail answers: not-found for an
// album, artist or genre whose members are all outside the caller's
// grants, and the curated fields for one inside them.
func TestEntityCurationFollowsEntityVisibility(t *testing.T) {
	t.Parallel()
	s := newGrantsScene(t)
	album, artist := deref(s.hidden.AlbumPid), deref(s.hidden.ArtistPid)
	if album == "" || artist == "" {
		t.Fatalf("the hidden track has album %q, artist %q", album, artist)
	}
	wantStatus(t, s.h.patchJSON(t, "/api/v1/entities/album/"+album, map[string]any{
		"edits": map[string]string{"label": "Secret Label"},
	}), 200, "label the second library's album")
	wantStatus(t, reqAs(t, s.h, http.MethodGet, "/api/v1/albums/"+album, s.token, nil), 404,
		"the album's detail for the granted account")
	genre := ""
	for _, b := range decodeStatus[FacetPage](t, get(t, s.h.ts, "/api/v1/library/facets?dimension=genre", s.h.token), 200, "genres").Buckets {
		if b.Label == "Hidden Genre" {
			genre = b.Key
		}
	}
	if genre == "" {
		t.Fatal("no genre bucket for the hidden track")
	}
	for _, path := range []string{
		"/api/v1/entities/album/" + album + "/curation",
		"/api/v1/entities/artist/" + artist + "/curation",
	} {
		wantStatus(t, reqAs(t, s.h, http.MethodGet, path, s.token, nil), 404, "the granted account's "+path)
		wantStatus(t, reqAs(t, s.h, http.MethodGet, path, s.h.token, nil), 200, "the administrator's "+path)
	}
	// The catalog reads no genre curation and tells the administrator so;
	// the granted account is answered not-found first.
	wantStatus(t, reqAs(t, s.h, http.MethodGet, "/api/v1/entities/genre/gn-"+genre+"/curation", s.token, nil), 404,
		"the granted account's genre curation")
	own := deref(s.own(t).AlbumPid)
	wantStatus(t, reqAs(t, s.h, http.MethodGet, "/api/v1/entities/album/"+own+"/curation", s.token, nil), 200,
		"the curation of the granted account's own album")
}

// The recap's arrivals count what joined the caller's reach this year,
// never the libraries it is not granted.
func TestYearInReviewCountsArrivalsInTheCallersReach(t *testing.T) {
	t.Parallel()
	s := newGrantsScene(t)
	arrivals := func(token string) int {
		t.Helper()
		return decodeStatus[YearInReview](t, reqAs(t, s.h, http.MethodGet, "/api/v1/stats/year-in-review", token, nil), 200, "the recap").NewInLibrary
	}
	for _, who := range []struct{ name, token string }{
		{"the administrator", s.h.token},
		{"the granted account", s.token},
	} {
		if got, want := arrivals(who.token), len(s.items(t, who.token, "")); got != want {
			t.Errorf("%s reads %d arrivals, its listing offers %d", who.name, got, want)
		}
	}
}

// The similarity status counts the caller's own tracks: how many there
// are, how many carry a vector, and how many wait for one.
func TestSimilarityStatusCountsTheCallersReach(t *testing.T) {
	t.Parallel()
	s := newGrantsScene(t)
	tracks := s.items(t, s.token, "&mediaType=music")
	if len(tracks) < 2 {
		t.Fatalf("the granted account sees %d tracks, want at least 2", len(tracks))
	}
	bare := func(pid string) string { return pid[strings.Index(pid, "-")+1:] }
	ctx := context.Background()
	for key, pid := range map[string]string{"embedded-hidden": s.hidden.Pid, "embedded-own": tracks[0].Pid} {
		if _, err := s.h.store.UpsertEmbedding(ctx, db.Embedding{
			Essence: key, ItemPID: bare(pid), Model: "test-model", Dims: 2,
			Vector: make([]byte, 8), CreatedAt: time.Now(),
		}); err != nil {
			t.Fatal(err)
		}
	}
	for key, pid := range map[string]string{"queued-hidden": s.hidden.Pid, "queued-own": tracks[1].Pid} {
		if err := s.h.store.EnqueueSimilarity(ctx, key, bare(pid)); err != nil {
			t.Fatal(err)
		}
	}
	status := func(token string) SimilarityStatus {
		t.Helper()
		return decodeStatus[SimilarityStatus](t, reqAs(t, s.h, http.MethodGet, "/api/v1/similarity/status", token, nil), 200, "the similarity status")
	}
	all := len(s.items(t, s.h.token, "&mediaType=music"))
	if got := status(s.h.token); got.TotalTracks != all || got.EmbeddedTracks != 2 || got.QueueDepth != 2 {
		t.Errorf("the administrator reads %d tracks, %d embedded, %d queued; want %d, 2, 2",
			got.TotalTracks, got.EmbeddedTracks, got.QueueDepth, all)
	}
	got := status(s.token)
	if got.TotalTracks != len(tracks) || got.EmbeddedTracks != 1 || got.QueueDepth != 1 {
		t.Errorf("the granted account reads %d tracks, %d embedded, %d queued; want %d, 1, 1",
			got.TotalTracks, got.EmbeddedTracks, got.QueueDepth, len(tracks))
	}
	if want := float32(100) / float32(len(tracks)); math.Abs(float64(got.CoveragePct-want)) > 0.01 {
		t.Errorf("the granted account reads %v%% coverage, want %v", got.CoveragePct, want)
	}
}

// wantSlots checks a session's queue as a receiver granted the first
// library reads it: the hidden track's slot kept and emptied, the rest
// as they are.
func wantSlots(t *testing.T, what string, got []PlaybackSessionEntry, hidden, own ItemSummary, ownFirst bool) {
	t.Helper()
	if len(got) != 2 {
		t.Fatalf("%s: %d entries, want both slots: %+v", what, len(got), got)
	}
	blank, kept := got[0], got[1]
	if ownFirst {
		kept, blank = got[0], got[1]
	}
	if blank.Pid != "" || blank.Title != "" || blank.Artist != nil || blank.DurationMs != nil {
		t.Errorf("%s: the hidden track's slot reads %+v, want it empty", what, blank)
	}
	if kept.Pid != own.Pid || kept.Title != own.Title {
		t.Errorf("%s: the visible slot reads %+v, want %s", what, kept, own.Title)
	}
	if strings.Contains(blank.Title+kept.Title, hidden.Title) {
		t.Errorf("%s names the hidden track", what)
	}
}

// wireEntries reads a socket frame's session entries.
func wireEntries(t *testing.T, frame map[string]any) []PlaybackSessionEntry {
	t.Helper()
	sess, _ := frame["session"].(map[string]any)
	raw, _ := sess["entries"].([]any)
	out := make([]PlaybackSessionEntry, 0, len(raw))
	for _, r := range raw {
		e, _ := r.(map[string]any)
		entry := PlaybackSessionEntry{}
		entry.Pid, _ = e["pid"].(string)
		entry.Title, _ = e["title"].(string)
		if a, ok := e["artist"].(string); ok {
			entry.Artist = &a
		}
		if d, ok := e["durationMs"].(float64); ok {
			ms := int64(d)
			entry.DurationMs = &ms
		}
		out = append(out, entry)
	}
	return out
}

// A session somebody else owns on a shared device shows a receiver an
// empty slot for an entry it cannot see, keeping the slot so the index
// still lines up: over REST, in a watch's first frame and in the frame a
// queue change pushes. The owner reads the whole queue.
func TestASharedSessionShowsAReceiverOnlyWhatItMaySee(t *testing.T) {
	t.Parallel()
	s := newGrantsScene(t)
	own := s.own(t)
	sess := decodeStatus[PlaybackSession](t, s.h.postJSON(t, "/api/v1/player/sessions", map[string]any{
		"endpointId": s.jukebox(t), "itemPids": []string{s.hidden.Pid, own.Pid}, "index": 1,
	}), 201, "the administrator plays on the shared device")

	var listed *PlaybackSession
	for _, got := range decodeStatus[PlaybackSessionList](t, reqAs(t, s.h, http.MethodGet, "/api/v1/player/sessions", s.token, nil), 200, "list sessions").Sessions {
		if got.Id == sess.Id {
			listed = &got
		}
	}
	if listed == nil || listed.Entries == nil {
		t.Fatalf("the granted account does not list the shared session with its entries")
	}
	if listed.Mine || listed.Index != 1 {
		t.Errorf("the listed session reads mine %v, index %d; want somebody else's at 1", listed.Mine, listed.Index)
	}
	wantSlots(t, "the session listing", *listed.Entries, s.hidden, own, false)
	detail := decodeStatus[PlaybackSession](t, reqAs(t, s.h, http.MethodGet, "/api/v1/player/sessions/"+sess.Id, s.token, nil), 200, "the session")
	wantSlots(t, "the session detail", deref2(detail.Entries), s.hidden, own, false)
	mine := decodeStatus[PlaybackSession](t, get(t, s.h.ts, "/api/v1/player/sessions/"+sess.Id, s.h.token), 200, "the owner's session")
	if entries := deref2(mine.Entries); len(entries) != 2 || entries[0].Pid != s.hidden.Pid {
		t.Errorf("the owner reads %+v, want the whole queue", entries)
	}

	watcher := dialWS(t, s.h, s.token)
	watcher.send(map[string]any{"type": "watch", "id": "w1", "sessionId": sess.Id})
	wantSlots(t, "the watch's first frame", wireEntries(t, watcher.expect("session")), s.hidden, own, false)

	owner := dialWS(t, s.h, s.h.token)
	owner.send(map[string]any{"type": "cmd", "id": "q1", "sessionId": sess.Id, "verb": "set-queue",
		"itemPids": []string{own.Pid, s.hidden.Pid}})
	if ack := owner.expect("ack"); len(wireEntries(t, ack)) != 2 || wireEntries(t, ack)[1].Pid != s.hidden.Pid {
		t.Errorf("the owner's ack reads %v, want the whole queue", ack["session"])
	}
	// Frames without entries tick by while playing; the change is the
	// first one carrying the queue.
	for {
		frame := watcher.expect("session")
		if entries := wireEntries(t, frame); len(entries) > 0 {
			wantSlots(t, "the frame the queue change pushed", entries, s.hidden, own, true)
			break
		}
	}
}

// A set-queue resolves for the account sending it before anything
// resolves for the session's owner: naming a track that account cannot
// see is refused not-found, and the queue stays as it was.
func TestSetQueueResolvesForTheCommandingAccount(t *testing.T) {
	t.Parallel()
	s := newGrantsScene(t)
	own := s.own(t)
	sess := decodeStatus[PlaybackSession](t, s.h.postJSON(t, "/api/v1/player/sessions", map[string]any{
		"endpointId": s.jukebox(t), "itemPids": []string{own.Pid},
	}), 201, "the administrator plays something everyone can see")

	client := dialWS(t, s.h, s.token)
	client.send(map[string]any{"type": "cmd", "id": "c1", "sessionId": sess.Id, "verb": "set-queue",
		"itemPids": []string{s.hidden.Pid}})
	var answer map[string]any
	for answer == nil {
		select {
		case f, ok := <-client.recv:
			if !ok {
				t.Fatal("the socket closed before the command was answered")
			}
			if f["type"] == "ack" || f["type"] == "error" {
				answer = f
			}
		case <-time.After(10 * time.Second):
			t.Fatal("the command was not answered")
		}
	}
	if answer["type"] != "error" || answer["code"] != "not-found" {
		t.Errorf("the set-queue was answered %v, want a not-found error", answer)
	}
	after := decodeStatus[PlaybackSession](t, get(t, s.h.ts, "/api/v1/player/sessions/"+sess.Id, s.h.token), 200, "the session afterwards")
	if entries := deref2(after.Entries); len(entries) != 1 || entries[0].Pid != own.Pid || after.QueueVersion != sess.QueueVersion {
		t.Errorf("the queue afterwards reads %+v at version %d, want %s at %d", entries, after.QueueVersion, own.Title, sess.QueueVersion)
	}
}

// The catalog delta sends no tombstone for an item the caller cannot have
// held: one created since its cursor in a library it is not granted, and
// one trashed out of such a library. Its own trashed track is still owed
// one.
func TestCatalogDeltaSendsNothingTheCallerCouldNotHold(t *testing.T) {
	t.Parallel()
	s := newGrantsScene(t)
	since, cursor := "", ""
	for {
		q := "?limit=500"
		if cursor != "" {
			q += "&cursor=" + url.QueryEscape(cursor)
		}
		page := decodeStatus[CatalogSyncPage](t, reqAs(t, s.h, http.MethodGet, "/api/v1/sync/catalog"+q, s.token, nil), 200, "the snapshot")
		since = page.NextSince
		if page.NextCursor == nil {
			break
		}
		cursor = *page.NextCursor
	}
	if _, err := fixtures.Generate(s.extra, fixtures.Spec{
		Name: "hidden2", Codec: fixtures.CodecFLAC, Duration: 6 * time.Second,
		Tags: map[string]string{"TITLE": "Second Hidden Song", "ARTIST": "Hidden Artist", "ALBUM": "Hidden Album"},
	}); err != nil {
		t.Fatal(err)
	}
	s.h.rescanAndWait(t)
	second := s.h.itemTitled(t, s.h.token, "Second Hidden Song")
	own := s.own(t)
	wantStatus(t, s.h.postJSON(t, "/api/v1/library/items/delete", map[string]any{
		"pids": []string{s.hidden.Pid, own.Pid}, "mode": "trash",
	}), 200, "trash a track of each library")

	ulid := func(pid string) string { return pid[strings.Index(pid, "-")+1:] }
	reasons := map[string]string{}
	for {
		page := decodeStatus[CatalogSyncPage](t, reqAs(t, s.h, http.MethodGet, "/api/v1/sync/catalog?since="+url.QueryEscape(since), s.token, nil), 200, "the delta")
		for _, e := range page.Entries {
			reasons[ulid(e.Pid)] = e.Op + " " + deref(e.Reason)
		}
		since = page.NextSince
		if page.More == nil || !*page.More {
			break
		}
	}
	for what, pid := range map[string]string{"the track created": second.Pid, "the track trashed": s.hidden.Pid} {
		if got, sent := reasons[ulid(pid)]; sent {
			t.Errorf("the delta names %s in the other library (%s)", what, got)
		}
	}
	if got := reasons[ulid(own.Pid)]; got != "delete hidden" {
		t.Errorf("the account's own trashed track reads %q, want a hidden tombstone", got)
	}
}

// artBytes reads one art response's body.
func artBytes(t *testing.T, h *harness, path, token string) []byte {
	t.Helper()
	resp := reqAs(t, h, http.MethodGet, path, token, nil)
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 {
		t.Fatalf("%s = %d: %s", path, resp.StatusCode, body)
	}
	return body
}

// A shared playlist read by somebody who cannot see all of it shows that
// reader no cover built from a member it cannot see, and no stored
// positions; the owner keeps both.
func TestASharedPlaylistShowsAReaderOnlyWhatItMaySee(t *testing.T) {
	t.Parallel()
	s := newGrantsScene(t)
	own := s.own(t)
	wantStatus(t, putArtwork(t, s.h, "/api/v1/items/"+s.hidden.Pid+"/artwork", coverBytes(t, 250)), 200, "the hidden track's cover")
	wantStatus(t, putArtwork(t, s.h, "/api/v1/items/"+own.Pid+"/artwork", coverBytes(t, 20)), 200, "the visible track's cover")
	pl := decodeStatus[Playlist](t, s.h.postJSON(t, "/api/v1/playlists", map[string]any{
		"name": "Shared mix", "kind": "static", "visibility": "shared",
		"itemPids": []string{s.hidden.Pid, own.Pid},
	}), 201, "the administrator shares a list")

	// The owner's read is what composes the cover.
	owner := decodeStatus[PlaylistItemsPage](t, get(t, s.h.ts, "/api/v1/playlists/"+pl.Pid+"/items", s.h.token), 200, "the owner's read")
	if len(owner.Entries) != 2 || owner.Entries[1].Position == nil || *owner.Entries[1].Position != 1 {
		t.Fatalf("the owner reads %+v, want both members with their positions", owner.Entries)
	}
	reader := decodeStatus[PlaylistItemsPage](t, reqAs(t, s.h, http.MethodGet, "/api/v1/playlists/"+pl.Pid+"/items", s.token, nil), 200, "the reader's read")
	if len(reader.Entries) != 1 || reader.Entries[0].Item.Pid != own.Pid {
		t.Fatalf("the reader reads %+v, want the member it can see", reader.Entries)
	}
	if p := reader.Entries[0].Position; p != nil {
		t.Errorf("the reader is sent position %d, which counts a member it cannot see", *p)
	}

	art := "/api/v1/items/" + pl.Pid + "/art"
	ownerArt, readerArt := artBytes(t, s.h, art, s.h.token), artBytes(t, s.h, art, s.token)
	if bytes.Equal(readerArt, ownerArt) {
		t.Error("the reader is served the cover built from a member it cannot see")
	}
	if !bytes.Equal(readerArt, artBytes(t, s.h, "/api/v1/items/"+own.Pid+"/art", s.token)) {
		t.Error("the reader's cover is not the cover of the member it can see")
	}
}

// Album and artist artwork answers what the entity's detail answers: an
// album or artist whose members are all outside the caller's grants has
// no artwork for it and no artwork slots.
func TestEntityArtFollowsEntityVisibility(t *testing.T) {
	t.Parallel()
	s := newGrantsScene(t)
	wantStatus(t, putArtwork(t, s.h, "/api/v1/items/"+s.hidden.Pid+"/artwork", coverBytes(t, 250)), 200, "the hidden track's cover")
	album, artist := deref(s.hidden.AlbumPid), deref(s.hidden.ArtistPid)
	wantStatus(t, reqAs(t, s.h, http.MethodGet, "/api/v1/albums/"+album, s.token, nil), 404, "the album's detail for the granted account")
	for _, path := range []string{
		"/api/v1/items/" + album + "/art",
		"/api/v1/items/" + album + "/art-roles",
		"/api/v1/items/" + artist + "/art-roles",
	} {
		wantStatus(t, reqAs(t, s.h, http.MethodGet, path, s.token, nil), 404, "the granted account's "+path)
		wantStatus(t, reqAs(t, s.h, http.MethodGet, path, s.h.token, nil), 200, "the administrator's "+path)
	}
	wantStatus(t, reqAs(t, s.h, http.MethodGet, "/api/v1/items/"+deref(s.own(t).AlbumPid)+"/art-roles", s.token, nil), 200,
		"the artwork slots of the granted account's own album")
}

// The artist gate reads every way a track names an artist: a guest
// credited on a track the account may see is no track's primary artist,
// and its portrait still answers to that account.
func TestAFeaturedArtistsPortraitFollowsTheCreditedTrack(t *testing.T) {
	t.Parallel()
	s := newGrantsScene(t)
	own := s.own(t)
	wantStatus(t, putJSON(t, s.h.ts, "/api/v1/items/"+own.Pid+"/credits", s.h.token, map[string]any{
		"role": "artist", "names": []string{deref(own.Artist), "Guest Voice"},
	}), 200, "credit a guest on the granted account's track")
	guest := ""
	for _, b := range decodeStatus[FacetPage](t, get(t, s.h.ts, "/api/v1/library/facets?dimension=credit-artist", s.h.token), 200, "credited artists").Buckets {
		if b.Label == "Guest Voice" {
			guest = deref(b.EntityPid)
		}
	}
	if guest == "" {
		t.Fatal("no credited-artist bucket for the guest")
	}
	wantStatus(t, metadataPutBytes(t, s.h.ts, "/api/v1/entities/artist/"+guest+"/artwork", s.h.token, coverBytes(t, 120)), 200,
		"the guest's portrait")
	wantStatus(t, reqAs(t, s.h, http.MethodGet, "/api/v1/items/"+guest+"/art", s.token, nil), 200,
		"the guest's portrait for the granted account")
}

// A show's artwork needs the podcast library in the caller's grants, read
// or written: an account that may manage podcasts but is granted other
// libraries only is answered not-found by every artwork door, while one
// granted the podcast library sets, pins and clears the cover.
func TestShowArtworkHoldsThePodcastGrant(t *testing.T) {
	t.Parallel()
	g := newPodcastGrants(t)
	_, musicOnly := g.account(t, "musiconly", g.musicLib)
	_, podcaster := g.account(t, "podcaster", g.musicLib, g.podcastLib)
	cover := coverBytes(t, 90)
	doors := []struct {
		method, path string
		body         any
	}{
		{http.MethodGet, "/api/v1/items/" + g.show + "/art-roles", nil},
		{http.MethodPut, "/api/v1/entities/podcast/" + g.show + "/artwork", cover},
		{http.MethodGet, "/api/v1/items/" + g.show + "/art", nil},
		{http.MethodGet, "/api/v1/entities/podcast/" + g.show + "/artwork/lock", nil},
		{http.MethodPut, "/api/v1/entities/podcast/" + g.show + "/artwork/lock", map[string]any{"locked": false}},
		{http.MethodDelete, "/api/v1/entities/podcast/" + g.show + "/artwork", nil},
	}
	open := func(door struct {
		method, path string
		body         any
	}, token string) int {
		t.Helper()
		var resp *http.Response
		if raw, ok := door.body.([]byte); ok {
			resp = metadataPutBytes(t, g.h.ts, door.path, token, raw)
		} else {
			resp = reqAs(t, g.h, door.method, door.path, token, door.body)
		}
		resp.Body.Close()
		return resp.StatusCode
	}
	for _, door := range doors {
		if code := open(door, musicOnly); code != 404 {
			t.Errorf("%s %s by an account without the podcast grant = %d, want 404", door.method, door.path, code)
		}
	}
	for _, door := range doors {
		if code := open(door, podcaster); code >= 300 {
			t.Errorf("%s %s by an account granted the podcast library = %d, want it done", door.method, door.path, code)
		}
	}
}

// snapshot mirrors the catalog as the granted account, limit entries a
// page, running between once the first page is in, and answers the
// cursor its deltas start from and the titles it mirrored by pid.
func (s grantsScene) snapshot(t *testing.T, limit int, between func()) (string, map[string]string) {
	t.Helper()
	since, cursor := "", ""
	mirrored := map[string]string{}
	for first := true; ; first = false {
		q := "?limit=" + strconv.Itoa(limit)
		if cursor != "" {
			q += "&cursor=" + url.QueryEscape(cursor)
		}
		page := decodeStatus[CatalogSyncPage](t, reqAs(t, s.h, http.MethodGet, "/api/v1/sync/catalog"+q, s.token, nil), 200, "a snapshot page")
		for _, e := range page.Entries {
			if e.Item != nil {
				mirrored[e.Pid] = e.Item.Title
			}
		}
		since = page.NextSince
		if first && between != nil {
			between()
		}
		if page.NextCursor == nil {
			return since, mirrored
		}
		cursor = *page.NextCursor
	}
}

// delta reads the granted account's catalog changes since a cursor, to
// the end, and answers each entry's op and reason by its pid's ULID.
func (s grantsScene) delta(t *testing.T, since string) map[string]string {
	t.Helper()
	reasons := map[string]string{}
	for {
		page := decodeStatus[CatalogSyncPage](t, reqAs(t, s.h, http.MethodGet, "/api/v1/sync/catalog?since="+url.QueryEscape(since), s.token, nil), 200, "the delta")
		for _, e := range page.Entries {
			reasons[bareULID(e.Pid)] = e.Op + " " + deref(e.Reason)
		}
		since = page.NextSince
		if page.More == nil || !*page.More {
			return reasons
		}
	}
}

// bareULID is a pid without its type prefix: a tombstone for an item the
// catalog no longer holds carries the track prefix whatever its kind.
func bareULID(pid string) string { return pid[strings.Index(pid, "-")+1:] }

// A track the account holds is still owed its tombstone when it is
// trashed from the library it is granted and from one it is not: the
// copy stands in when the account's file goes, so the item's trash rows
// name both libraries, the newest the one the account is not granted.
func TestATrackTrashedFromBothLibrariesIsTombstonedToItsHolder(t *testing.T) {
	t.Parallel()
	s := newGrantsScene(t)
	copyFixture(t, s.h.library, "alpha", s.extra)
	s.h.rescanAndWait(t)
	alpha := s.h.itemTitled(t, s.h.token, "Alpha Song")
	primary := ""
	for _, f := range s.h.itemFiles(t, s.h.token, alpha.Pid) {
		if f.Role == "primary" && deref(f.LibraryPid) == s.libA {
			primary = f.FilePid
		}
	}
	if primary == "" {
		t.Fatal("alpha's primary file is not in the granted library")
	}
	wantStatus(t, reqAs(t, s.h, http.MethodGet, "/api/v1/items/"+alpha.Pid, s.token, nil), 200, "the granted account reads alpha")
	since, _ := s.snapshot(t, 500, nil)

	wantStatus(t, s.h.postJSON(t, "/api/v1/items/"+alpha.Pid+"/files/delete",
		map[string]any{"filePids": []string{primary}}), 200, "trash the granted library's file")
	wantStatus(t, s.h.postJSON(t, "/api/v1/library/items/delete", map[string]any{
		"pids": []string{alpha.Pid}, "mode": "trash",
	}), 200, "trash the item")
	if got := s.delta(t, since)[bareULID(alpha.Pid)]; got != "delete hidden" {
		t.Errorf("the delta reads %q for the track the account held, want a hidden tombstone", got)
	}
}

// A change to an item that was never inside the account's grants sends
// that account nothing: the second library's track retagged reaches no
// delta of an account granted the first, while its own track's change
// does.
func TestCatalogDeltaSendsNothingForAChangeOutsideTheGrants(t *testing.T) {
	t.Parallel()
	s := newGrantsScene(t)
	own := s.own(t)
	since, _ := s.snapshot(t, 500, nil)
	for _, pid := range []string{s.hidden.Pid, own.Pid} {
		wantStatus(t, putJSON(t, s.h.ts, "/api/v1/items/"+pid+"/tags/MOOD", s.h.token,
			map[string]any{"values": []string{"calm"}}), 200, "tag "+pid)
	}
	reasons := s.delta(t, since)
	if got, sent := reasons[bareULID(s.hidden.Pid)]; sent {
		t.Errorf("the delta names the other library's track (%s)", got)
	}
	if got := reasons[bareULID(own.Pid)]; got != "upsert " {
		t.Errorf("the account's own track reads %q, want an upsert", got)
	}
}

// An item that was only ever in libraries outside the account's grants
// reaches none of its deltas however it goes: deleted outright, purged
// from the trash, or archived with its library's removal. The account's
// own track deleted outright is still sent.
func TestCatalogDeltaSendsNothingForAnItemGoneOutsideTheGrants(t *testing.T) {
	t.Parallel()
	s := newGrantsScene(t)
	if _, err := fixtures.Generate(s.extra, fixtures.Spec{
		Name: "hidden2", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
		Tags: map[string]string{"TITLE": "Second Hidden Song", "ARTIST": "Hidden Artist", "ALBUM": "Hidden Album"},
	}); err != nil {
		t.Fatal(err)
	}
	s.h.rescanAndWait(t)
	second := s.h.itemTitled(t, s.h.token, "Second Hidden Song")
	spareDir := t.TempDir()
	if _, err := fixtures.Generate(spareDir, fixtures.Spec{
		Name: "spare", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
		Tags: map[string]string{"TITLE": "Spare Song", "ARTIST": "Spare Artist", "ALBUM": "Spare Album"},
	}); err != nil {
		t.Fatal(err)
	}
	spare := decodeStatus[LibraryCreated](t, s.h.postJSON(t, "/api/v1/libraries", map[string]any{"name": "spare", "path": spareDir}),
		201, "add a library")
	spareSong := waitTitled(t, s.h, "Spare Song")
	own := s.own(t)
	since, _ := s.snapshot(t, 500, nil)

	wantStatus(t, s.h.postJSON(t, "/api/v1/library/items/delete", map[string]any{
		"pids": []string{s.hidden.Pid, own.Pid}, "mode": "permanent",
	}), 200, "delete a track of each library outright")
	wantStatus(t, s.h.postJSON(t, "/api/v1/library/items/delete", map[string]any{
		"pids": []string{second.Pid}, "mode": "trash",
	}), 200, "trash the second library's other track")
	entry := ""
	for _, e := range decode[TrashList](t, get(t, s.h.ts, "/api/v1/admin/trash", s.h.token)).Entries {
		if e.ItemPid != nil && bareULID(*e.ItemPid) == bareULID(second.Pid) {
			entry = e.Id
		}
	}
	if entry == "" {
		t.Fatal("no trash entry for the trashed track")
	}
	wantStatus(t, s.h.deleteReq(t, "/api/v1/admin/trash/"+entry), 200, "purge it")
	removeLibrary(t, s.h, spare.Pid)

	reasons := s.delta(t, since)
	for what, pid := range map[string]string{
		"deleted outright": s.hidden.Pid, "purged": second.Pid, "removed with its library": spareSong.Pid,
	} {
		if got, sent := reasons[bareULID(pid)]; sent {
			t.Errorf("the delta names the track %s outside the grants (%s)", what, got)
		}
	}
	if got := reasons[bareULID(own.Pid)]; got != "delete removed" {
		t.Errorf("the account's own track deleted outright reads %q, want a removed tombstone", got)
	}
}

// waitTitled answers the administrator's item with title, waiting out a
// scan still running.
func waitTitled(t *testing.T, h *harness, title string) ItemSummary {
	t.Helper()
	for deadline := time.Now().Add(30 * time.Second); ; time.Sleep(25 * time.Millisecond) {
		for _, it := range h.items(t, "?limit=500").Items {
			if it.Title == title {
				return it
			}
		}
		if time.Now().After(deadline) {
			t.Fatalf("no item titled %q", title)
		}
	}
}

// removeLibrary removes a library added at runtime and waits for the job
// doing it, past the catalog-busy answers a scan still running gives.
func removeLibrary(t *testing.T, h *harness, pid string) {
	t.Helper()
	for deadline := time.Now().Add(time.Minute); ; time.Sleep(20 * time.Millisecond) {
		resp := reqAs(t, h, http.MethodDelete, "/api/v1/libraries/"+pid, h.token, nil)
		if resp.StatusCode == 202 {
			if j := waitForJobDone(t, h, h.token, decode[Job](t, resp).Pid); j.State != "done" {
				t.Fatalf("the removal ended %s: %s", j.State, deref(j.Error))
			}
			return
		}
		e := decode[Error](t, resp)
		if resp.StatusCode != 409 || e.Code != "catalog-busy" || time.Now().After(deadline) {
			t.Fatalf("remove status = %d (%+v), want 202", resp.StatusCode, e)
		}
	}
}

// An item a later snapshot page carried is owed its tombstone when it
// leaves the account's grants before the first delta: made after the
// snapshot's cursor, inside the grants, it is a change the first delta
// covers.
func TestAnItemMirroredMidSnapshotIsTombstonedWhenItLeavesTheGrants(t *testing.T) {
	t.Parallel()
	s := newGrantsScene(t)
	since, mirrored := s.snapshot(t, 1, func() {
		if _, err := fixtures.Generate(s.h.library, fixtures.Spec{
			Name: "arrival", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
			Tags: map[string]string{"TITLE": "Zulu Arrival", "ARTIST": "Zulu Artist", "ALBUM": "Zulu Album"},
		}); err != nil {
			t.Fatal(err)
		}
		s.h.rescanAndWait(t)
	})
	arrival := s.h.itemTitled(t, s.h.token, "Zulu Arrival")
	if mirrored[arrival.Pid] != "Zulu Arrival" {
		t.Fatalf("the snapshot did not carry the track made after its first page: %v", mirrored)
	}
	// The re-home: the same bytes under the other library's root.
	data, err := os.ReadFile(filepath.Join(s.h.library, "arrival.flac"))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(s.extra, "arrival.flac"), data, 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(filepath.Join(s.h.library, "arrival.flac")); err != nil {
		t.Fatal(err)
	}
	s.h.rescanAndWait(t)
	wantStatus(t, reqAs(t, s.h, http.MethodGet, "/api/v1/items/"+arrival.Pid, s.h.token, nil), 200, "the moved track for the administrator")
	wantStatus(t, reqAs(t, s.h, http.MethodGet, "/api/v1/items/"+arrival.Pid, s.token, nil), 404, "the moved track for the granted account")
	if got := s.delta(t, since)[bareULID(arrival.Pid)]; got != "delete hidden" {
		t.Errorf("the first delta reads %q for the track the snapshot carried, want a hidden tombstone", got)
	}
}

// What the delta knows of the libraries an item sat in is cut back with
// the change history a cursor is still served from, keeping what the
// cursors left standing need: after a prune and a fresh snapshot, a
// change to the second library's track still reaches no delta of the
// account granted the first.
func TestALibraryHistoryPrunedWithTheChangesStillServesTheDelta(t *testing.T) {
	t.Parallel()
	s := newGrantsScene(t)
	stale, _ := s.snapshot(t, 500, nil)
	for _, key := range []string{"MOOD", "ENERGY"} {
		wantStatus(t, putJSON(t, s.h.ts, "/api/v1/items/"+s.own(t).Pid+"/tags/"+key, s.h.token,
			map[string]any{"values": []string{"calm"}}), 200, "a change to prune behind")
	}
	if _, err := s.h.svc.PruneCatalogChanges(context.Background(), 1); err != nil {
		t.Fatal(err)
	}
	wantStatus(t, reqAs(t, s.h, http.MethodGet, "/api/v1/sync/catalog?since="+url.QueryEscape(stale), s.token, nil), 410,
		"a cursor behind the pruned history")
	since, _ := s.snapshot(t, 500, nil)
	wantStatus(t, putJSON(t, s.h.ts, "/api/v1/items/"+s.hidden.Pid+"/tags/MOOD", s.h.token,
		map[string]any{"values": []string{"calm"}}), 200, "tag the other library's track")
	if got, sent := s.delta(t, since)[bareULID(s.hidden.Pid)]; sent {
		t.Errorf("after the prune the delta names the other library's track (%s)", got)
	}
}

// A shared smart list's stored cover goes to a reader who cannot see all
// of it only while every member the cover was drawn from is one the
// reader sees: once the rule's match moves from a track the reader cannot
// see to one it can, the reader is shown that track's cover, nobody
// having reopened the list, and for a random draw, which is never drawn
// again, after the owner reopens it too.
func TestASharedSmartListsCoverFollowsTheMembersItWasDrawnFrom(t *testing.T) {
	t.Parallel()
	s := newGrantsScene(t)
	own := s.own(t)
	wantStatus(t, putArtwork(t, s.h, "/api/v1/items/"+s.hidden.Pid+"/artwork", coverBytes(t, 250)), 200, "the hidden track's cover")
	wantStatus(t, putArtwork(t, s.h, "/api/v1/items/"+own.Pid+"/artwork", coverBytes(t, 20)), 200, "the visible track's cover")
	wantStatus(t, putJSON(t, s.h.ts, "/api/v1/items/"+s.hidden.Pid+"/tags/MIX", s.h.token,
		map[string]any{"values": []string{"yes"}}), 200, "tag the hidden track")
	var lists []Playlist
	for _, mode := range []string{"random", "count"} {
		pl := decodeStatus[Playlist](t, s.h.postJSON(t, "/api/v1/playlists", map[string]any{
			"name": "Mix " + mode, "kind": "smart", "visibility": "shared",
			"rule": map[string]any{
				"root":  map[string]any{"type": "condition", "field": "tag.MIX", "op": "is", "value": "yes"},
				"limit": 1, "limitMode": mode,
			},
		}), 201, "the shared smart list drawing by "+mode)
		wantStatus(t, get(t, s.h.ts, "/api/v1/playlists/"+pl.Pid+"/items", s.h.token), 200, "the owner opens it")
		wantStatus(t, reqAs(t, s.h, http.MethodGet, "/api/v1/items/"+pl.Pid+"/art", s.token, nil), 404,
			"the reader's cover while the list holds only the hidden track")
		lists = append(lists, pl)
	}
	wantStatus(t, s.h.deleteReq(t, "/api/v1/items/"+s.hidden.Pid+"/tags/MIX"), 204, "untag the hidden track")
	wantStatus(t, putJSON(t, s.h.ts, "/api/v1/items/"+own.Pid+"/tags/MIX", s.h.token,
		map[string]any{"values": []string{"yes"}}), 200, "tag the visible track")
	ownArt := artBytes(t, s.h, "/api/v1/items/"+own.Pid+"/art", s.token)
	for _, pl := range lists {
		if !bytes.Equal(artBytes(t, s.h, "/api/v1/items/"+pl.Pid+"/art", s.token), ownArt) {
			t.Errorf("%s: with nobody reopening it, the reader's cover is not the member it sees", pl.Name)
		}
	}
	for _, pl := range lists {
		wantStatus(t, get(t, s.h.ts, "/api/v1/playlists/"+pl.Pid+"/items", s.h.token), 200, "the owner reopens it")
		if !bytes.Equal(artBytes(t, s.h, "/api/v1/items/"+pl.Pid+"/art", s.token), ownArt) {
			t.Errorf("%s: after the owner reopens it, the reader's cover is not the member it sees", pl.Name)
		}
	}
}

// An explicit show's artwork answers an account without explicit content
// what the show's detail answers: not-found at every door, read or
// written. An account with explicit content goes through each.
func TestAnExplicitShowsArtworkFollowsItsDetail(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	feed := newCountsFeedAs(t, countsChannel{explicit: true}, []countsEpisode{{title: "One"}})
	show := decodeStatus[Subscription](t, h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()}), 201, "subscribe").Show.Pid
	_, withheld := listenerAccount(t, h, "noexplicit", false)
	_, allowed := listenerAccount(t, h, "explicit", true)
	doors := []struct {
		method, path string
		body         any
	}{
		{http.MethodGet, "/api/v1/podcasts/" + show, nil},
		{http.MethodGet, "/api/v1/items/" + show + "/art-roles", nil},
		{http.MethodPut, "/api/v1/entities/podcast/" + show + "/artwork", coverBytes(t, 70)},
		{http.MethodGet, "/api/v1/items/" + show + "/art", nil},
		{http.MethodGet, "/api/v1/entities/podcast/" + show + "/artwork/lock", nil},
		{http.MethodPut, "/api/v1/entities/podcast/" + show + "/artwork/lock", map[string]any{"locked": false}},
		{http.MethodDelete, "/api/v1/entities/podcast/" + show + "/artwork", nil},
	}
	open := func(method, path string, body any, token string) int {
		t.Helper()
		var resp *http.Response
		if raw, ok := body.([]byte); ok {
			resp = metadataPutBytes(t, h.ts, path, token, raw)
		} else {
			resp = reqAs(t, h, method, path, token, body)
		}
		resp.Body.Close()
		return resp.StatusCode
	}
	for _, d := range doors {
		if code := open(d.method, d.path, d.body, withheld); code != 404 {
			t.Errorf("%s %s by an account without explicit content = %d, want 404", d.method, d.path, code)
		}
	}
	for _, d := range doors {
		if code := open(d.method, d.path, d.body, allowed); code >= 300 {
			t.Errorf("%s %s by an account with explicit content = %d, want it done", d.method, d.path, code)
		}
	}
}

// A shared playlist's page cursor counts only the entries its reader is
// shown: a list holding a track the reader cannot see around the two it
// can pages that reader as a list holding the two alone does, each entry
// once, with the same cursors.
func TestASharedPlaylistsCursorCountsOnlyWhatItsReaderSees(t *testing.T) {
	t.Parallel()
	s := newGrantsScene(t)
	shown := s.items(t, s.token, "&mediaType=music")[:2]
	pids := []string{shown[0].Pid, shown[1].Pid}
	list := func(name string, members []string) string {
		t.Helper()
		return decodeStatus[Playlist](t, s.h.postJSON(t, "/api/v1/playlists", map[string]any{
			"name": name, "kind": "static", "visibility": "shared", "itemPids": members,
		}), 201, "share "+name).Pid
	}
	pages := func(pl string) (cursors, got []string) {
		t.Helper()
		cursor := ""
		for {
			q := "?limit=1"
			if cursor != "" {
				q += "&cursor=" + url.QueryEscape(cursor)
			}
			page := decodeStatus[PlaylistItemsPage](t, reqAs(t, s.h, http.MethodGet, "/api/v1/playlists/"+pl+"/items"+q, s.token, nil),
				200, "a page of "+pl)
			for _, e := range page.Entries {
				got = append(got, e.Item.Pid)
			}
			if page.NextCursor == nil {
				return cursors, got
			}
			cursor = *page.NextCursor
			cursors = append(cursors, cursor)
			if len(cursors) > 10 {
				t.Fatal("the cursors do not end")
			}
		}
	}
	hiddenCursors, hiddenGot := pages(list("Around the hidden track", []string{s.hidden.Pid, pids[0], pids[1], s.hidden.Pid}))
	plainCursors, plainGot := pages(list("Without it", pids))
	if !slices.Equal(hiddenGot, pids) || !slices.Equal(plainGot, pids) {
		t.Errorf("the reader pages %v and %v, want %v each once", hiddenGot, plainGot, pids)
	}
	if !slices.Equal(hiddenCursors, plainCursors) {
		t.Errorf("the reader's cursors %q around the hidden track differ from %q without it", hiddenCursors, plainCursors)
	}
}

// An episode sits in the podcast library whether it was fetched or not, so
// an account not granted that library is sent nothing for an episode's
// change: neither for a feed refresh that moves every enclosure, nor for
// the fetch of the episode not yet fetched. Its own track's change still
// reaches it.
func TestEpisodeChangesReachNoAccountWithoutThePodcastLibrary(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	feed := newFeedServer(t, 2)
	sub := decodeStatus[Subscription](t, h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()}), 201, "subscribe")
	eps := decode[EpisodePage](t, get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)).Items
	if len(eps) != 2 {
		t.Fatalf("episodes = %d, want 2", len(eps))
	}
	wantStatus(t, h.postJSON(t, "/api/v1/episodes/"+eps[0].Pid+"/fetch", nil), 202, "fetching one episode")
	drainFetches(t, h)
	g := podcastGrants{h: h, show: sub.Show.Pid, fetched: eps[0].Pid, unfetched: eps[1].Pid}
	for _, lib := range decode[Libraries](t, get(t, h.ts, "/api/v1/libraries", h.token)).Libraries {
		switch deref(lib.Media) {
		case "podcast":
			g.podcastLib = lib.Pid
		default:
			g.musicLib = lib.Pid
		}
	}
	_, musicOnly := g.account(t, "musiconly", g.musicLib)
	s := grantsScene{h: h, token: musicOnly}
	track := s.items(t, musicOnly, "&mediaType=music")[0]
	since, _ := s.snapshot(t, 500, nil)

	feed.enclosurePrefix = "/hop/1"
	feed.writeFeed(t, 2)
	wantStatus(t, h.postJSON(t, "/api/v1/podcasts/"+g.show+"/refresh", nil), 200, "refresh the show")
	wantStatus(t, h.postJSON(t, "/api/v1/episodes/"+g.unfetched+"/fetch", nil), 202, "fetch the other episode")
	drainFetches(t, h)
	wantStatus(t, putJSON(t, h.ts, "/api/v1/items/"+track.Pid+"/tags/MOOD", h.token,
		map[string]any{"values": []string{"calm"}}), 200, "tag the account's own track")

	got := s.delta(t, since)
	for what, pid := range map[string]string{"fetched before the snapshot": g.fetched, "fetched after it": g.unfetched} {
		if r, sent := got[bareULID(pid)]; sent {
			t.Errorf("the account without the podcast library is sent the episode %s (%s)", what, r)
		}
	}
	if r := got[bareULID(track.Pid)]; r != "upsert " {
		t.Errorf("the account's own track reads %q, want an upsert", r)
	}
}
