package service

import (
	"context"
	"crypto/md5"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
	"github.com/colespringer/waxdeck/fixtures"

	"github.com/colespringer/waxdeck/server/internal/auth"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// The migration tests follow the repo's trace-based compatibility
// pattern: a fake source server answers the shapes the real one emits
// (Navidrome's subsonic-response envelope, Audiobookshelf's /api/me and
// /api/items), and the import runs against a real service Library over
// a scanned synthesized catalog.

// migrateFixture is a real Library over synthesized media plus an
// admin user context to import as.
type migrateFixture struct {
	svc *Library
	uc  *UserCtx
}

func newMigrateFixture(t *testing.T) (context.Context, *migrateFixture) {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	log := slog.New(slog.NewTextHandler(io.Discard, nil))

	libDir := t.TempDir()
	if _, err := fixtures.Generate(libDir, fixtures.DemoLibrary()...); err != nil {
		t.Fatalf("generating fixtures: %v", err)
	}
	if _, err := fixtures.GenerateBook(libDir); err != nil {
		t.Fatalf("generating book fixture: %v", err)
	}
	if _, err := fixtures.GenerateChapteredBook(libDir); err != nil {
		t.Fatalf("generating chaptered book fixture: %v", err)
	}

	dataDir := t.TempDir()
	store, err := wdb.Open(ctx, filepath.Join(dataDir, "waxdeck.db"))
	if err != nil {
		t.Fatal(err)
	}
	sealer, err := auth.NewSealer([]byte("0123456789abcdef0123456789abcdef"), "waxdeck-app-password-v1")
	if err != nil {
		t.Fatal(err)
	}
	group := supervise.NewGroup(log)
	svc, err := Open(ctx, Config{
		DataDir: dataDir,
		Roots:   []Root{{Name: "lib", Path: libDir}},
		Sealer:  sealer,
		// The fake source servers listen on loopback, which the SSRF
		// guard would otherwise refuse; the flag is the same LAN opt-in
		// a real household migration would run with.
		AllowPrivateFeedHosts: true,
		Logger:                log,
	}, store, group)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		cancel()
		group.Wait()
		svc.Close()
		store.Close()
	})
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatalf("scanning fixture library: %v", err)
	}

	acct, err := svc.CreateAccount(ctx, AccountCreate{
		Username: "admin", Password: "correct-horse", Roles: []string{"admin"},
	})
	if err != nil {
		t.Fatal(err)
	}
	uc, err := svc.UserCtx(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	return ctx, &migrateFixture{svc: svc, uc: uc}
}

// itemPID finds one scanned fixture item by kind and title.
func (f *migrateFixture) itemPID(t *testing.T, ctx context.Context, kind model.Kind, title string) string {
	t.Helper()
	b := query.New(query.EntityItems).
		Where("kind", query.OpIs, string(kind)).
		Where("title", query.OpIs, title).Limit(2)
	items, err := f.svc.lib.Query(ctx, b.Build(), "")
	if err != nil {
		t.Fatalf("querying %q: %v", title, err)
	}
	if len(items) != 1 {
		t.Fatalf("querying %q: %d items, want 1", title, len(items))
	}
	return apiPID(prefixForKind(items[0].Kind), items[0].PID)
}

func (f *migrateFixture) playState(t *testing.T, ctx context.Context, pid string) PlayState {
	t.Helper()
	st, err := f.svc.PlayState(ctx, f.uc, pid)
	if err != nil {
		t.Fatalf("play state for %s: %v", pid, err)
	}
	return st
}

// starredAt reads the catalog's star time for an item, which the API
// play state does not carry.
func (f *migrateFixture) starredAt(t *testing.T, ctx context.Context, apiPID string) time.Time {
	t.Helper()
	_, catalogPID, ok := parseAPIPID(apiPID)
	if !ok {
		t.Fatalf("unparseable pid %q", apiPID)
	}
	st, err := f.svc.lib.Playback().State(ctx, model.PID(f.uc.CatalogPID), catalogPID)
	if err != nil {
		t.Fatalf("catalog state for %s: %v", apiPID, err)
	}
	if st == nil || st.StarredAt == 0 {
		t.Fatalf("%s carries no star time: %+v", apiPID, st)
	}
	return time.Unix(0, st.StarredAt).UTC()
}

// starredEntities reads back the caller's starred artists and albums.
func (f *migrateFixture) starredEntities(t *testing.T, ctx context.Context) StarredEntities {
	t.Helper()
	res, err := f.svc.StarredEntities(ctx, f.uc)
	if err != nil {
		t.Fatalf("StarredEntities: %v", err)
	}
	return res
}

// runMigration queues the task through the public entry, asserts the
// credential never lands in params plaintext, then drives the row
// through the dispatch seam directly (standing in for the runToolTask
// case that wires migrations into the drain worker) and returns the
// parsed summary.
func (f *migrateFixture) runMigration(t *testing.T, ctx context.Context, req MigrationRequest) migrationSummary {
	t.Helper()
	dto, err := f.svc.StartMigration(ctx, f.uc, req)
	if err != nil {
		t.Fatalf("StartMigration: %v", err)
	}
	if dto.Type != taskTypeMigratePrefix+strings.ToLower(req.Source) {
		t.Fatalf("task type = %q", dto.Type)
	}
	row, err := f.svc.db.ToolTaskByID(ctx, dto.ID)
	if err != nil {
		t.Fatal(err)
	}
	if req.Password != "" && strings.Contains(row.Params, req.Password) {
		t.Fatalf("params carry the plaintext password: %s", row.Params)
	}
	if req.Token != "" && strings.Contains(row.Params, req.Token) {
		t.Fatalf("params carry the plaintext token: %s", row.Params)
	}
	if err := f.svc.runMigrationTask(ctx, &row); err != nil {
		t.Fatalf("runMigrationTask: %v", err)
	}
	var sum migrationSummary
	if err := json.Unmarshal([]byte(row.Summary), &sum); err != nil {
		t.Fatalf("summary %q: %v", row.Summary, err)
	}
	return sum
}

// navStarredAt is the star time Alpha carries on the source, which the
// import must preserve rather than restamping at import time.
var navStarredAt = time.Date(2025, 11, 5, 10, 20, 30, 0, time.UTC)

// Canned Navidrome songs. Alpha matches the fixture catalog and
// carries an MBID, a star with its set time, plus play history; Bravo
// matches by descriptive metadata alone; Charlie appears only as a
// bookmark entry; Nowhere matches nothing local.
const (
	navSongAlpha   = `{"id":"s-alpha","title":"Alpha Song","artist":"Fixture Artist","album":"Fixture Album","duration":2,"playCount":3,"played":"2026-01-02T03:04:05.000Z","starred":"2025-11-05T10:20:30.000Z","musicBrainzId":"5f2ab3d1-6f70-4d67-9028-53144d5f2f9c"}`
	navSongBravo   = `{"id":"s-bravo","title":"Bravo Song","artist":"Fixture Artist","album":"Fixture Album","duration":3,"userRating":4}`
	navSongCharlie = `{"id":"s-charlie","title":"Charlie Song","artist":"Fixture Artist","album":"Fixture Album","duration":3}`
	navSongNowhere = `{"id":"s-nowhere","title":"Nowhere Song","artist":"Unknown Artist","album":"Ghost Album","duration":3,"playCount":1}`
)

func writeSubsonic(w http.ResponseWriter, payload string, ok bool) {
	status := "ok"
	if !ok {
		status = "failed"
	}
	w.Header().Set("Content-Type", "application/json")
	fmt.Fprintf(w, `{"subsonic-response":{"status":%q,"version":"1.16.1",%s}}`, status, payload)
}

// newFakeNavidrome emulates the slice of Navidrome the import walks:
// token auth verified per request, two albums with three songs, one
// starred song plus a starred album and artist, and one bookmark,
// everything in the standard envelope.
func newFakeNavidrome(t *testing.T, username, password string) *httptest.Server {
	t.Helper()
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		method := strings.TrimSuffix(strings.TrimPrefix(r.URL.Path, "/rest/"), ".view")
		q := r.URL.Query()
		sum := md5.Sum([]byte(password + q.Get("s")))
		if q.Get("u") != username || q.Get("t") != hex.EncodeToString(sum[:]) || q.Get("s") == "" {
			writeSubsonic(w, `"error":{"code":40,"message":"Wrong username or password"}`, false)
			return
		}
		switch method {
		case "getStarred2":
			writeSubsonic(w, `"starred2":{"song":[`+navSongAlpha+`],`+
				`"album":[{"id":"al-1","name":"Fixture Album","artist":"Fixture Artist","starred":"2025-11-05T10:20:30.000Z"}],`+
				`"artist":[{"id":"ar-1","name":"Fixture Artist","starred":"2025-11-05T10:20:30.000Z"}]}`, true)
		case "getArtist":
			if q.Get("id") != "ar-1" {
				writeSubsonic(w, `"error":{"code":70,"message":"not found"}`, false)
				return
			}
			writeSubsonic(w, `"artist":{"id":"ar-1","name":"Fixture Artist","album":[{"id":"al-1","name":"Fixture Album"}]}`, true)
		case "getAlbumList2":
			if q.Get("offset") != "0" {
				writeSubsonic(w, `"albumList2":{"album":[]}`, true)
				return
			}
			writeSubsonic(w, `"albumList2":{"album":[{"id":"al-1","name":"Fixture Album"},{"id":"al-2","name":"Ghost Album"}]}`, true)
		case "getAlbum":
			switch q.Get("id") {
			case "al-1":
				writeSubsonic(w, `"album":{"id":"al-1","name":"Fixture Album","song":[`+navSongAlpha+`,`+navSongBravo+`]}`, true)
			case "al-2":
				writeSubsonic(w, `"album":{"id":"al-2","name":"Ghost Album","song":[`+navSongNowhere+`]}`, true)
			default:
				writeSubsonic(w, `"error":{"code":70,"message":"not found"}`, false)
			}
		case "getBookmarks":
			writeSubsonic(w, `"bookmarks":{"bookmark":[{"position":1500,"entry":`+navSongCharlie+`}]}`, true)
		default:
			writeSubsonic(w, `"error":{"code":0,"message":"unknown method"}`, false)
		}
	}))
	t.Cleanup(ts.Close)
	return ts
}

func TestMigrateSubsonicImport(t *testing.T) {
	ctx, f := newMigrateFixture(t)
	ts := newFakeNavidrome(t, "demo", "demo-pass")

	alpha := f.itemPID(t, ctx, model.KindTrack, "Alpha Song")
	bravo := f.itemPID(t, ctx, model.KindTrack, "Bravo Song")
	charlie := f.itemPID(t, ctx, model.KindTrack, "Charlie Song")

	req := MigrationRequest{
		Source: "navidrome", ServerURL: ts.URL,
		Username: "demo", Password: "demo-pass",
		Stars: true, Ratings: true, History: true, Progress: true,
		DryRun: true,
	}

	// The entry is admin-gated and validates its inputs.
	member, err := f.svc.CreateAccount(ctx, AccountCreate{Username: "member", Password: "pw"})
	if err != nil {
		t.Fatal(err)
	}
	memberCtx, err := f.svc.UserCtx(ctx, member.User)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.StartMigration(ctx, memberCtx, req); KindOf(err) != KindForbidden {
		t.Fatalf("non-admin start: kind = %v, want forbidden", KindOf(err))
	}
	if _, err := f.svc.StartMigration(ctx, f.uc, MigrationRequest{Source: "plex", ServerURL: ts.URL, Username: "u", Password: "p"}); KindOf(err) != KindInvalid {
		t.Fatalf("unknown source: kind = %v, want invalid", KindOf(err))
	}
	if _, err := f.svc.StartMigration(ctx, f.uc, MigrationRequest{Source: "navidrome", ServerURL: "ftp://old-box", Username: "u", Password: "p"}); KindOf(err) != KindInvalid {
		t.Fatalf("bad scheme: kind = %v, want invalid", KindOf(err))
	}
	if _, err := f.svc.StartMigration(ctx, f.uc, MigrationRequest{Source: "navidrome", ServerURL: ts.URL}); KindOf(err) != KindInvalid {
		t.Fatalf("missing credentials: kind = %v, want invalid", KindOf(err))
	}
	if _, err := f.svc.StartMigration(ctx, f.uc, MigrationRequest{Source: "audiobookshelf", ServerURL: ts.URL}); KindOf(err) != KindInvalid {
		t.Fatalf("missing token: kind = %v, want invalid", KindOf(err))
	}

	// Dry run: the full report, no writes.
	dry := f.runMigration(t, ctx, req)
	if dry.Source != "navidrome" || !dry.DryRun {
		t.Fatalf("dry summary header = %+v", dry)
	}
	if dry.Matched != 3 || dry.Unmatched != 1 {
		t.Fatalf("dry matched/unmatched = %d/%d, want 3/1", dry.Matched, dry.Unmatched)
	}
	if dry.Stars != 1 || dry.Ratings != 1 || dry.Listens != 3 || dry.Progress != 1 {
		t.Fatalf("dry counts = %+v", dry)
	}
	if dry.AlbumStars != 1 || dry.ArtistStars != 1 {
		t.Fatalf("dry entity star counts = %d album / %d artist, want 1 each", dry.AlbumStars, dry.ArtistStars)
	}
	if ents := f.starredEntities(t, ctx); len(ents.Albums) != 0 || len(ents.Artists) != 0 {
		t.Fatalf("dry run wrote entity stars: %+v", ents)
	}
	if st := f.playState(t, ctx, alpha); st.Starred || st.PlayCount != 0 || st.PositionMS != 0 {
		t.Fatalf("dry run wrote state: %+v", st)
	}
	if st := f.playState(t, ctx, bravo); st.Rating != nil {
		t.Fatalf("dry run wrote a rating: %+v", st)
	}

	// The real run replays everything.
	req.DryRun = false
	sum := f.runMigration(t, ctx, req)
	if sum.Matched != 3 || sum.Unmatched != 1 {
		t.Fatalf("matched/unmatched = %d/%d, want 3/1", sum.Matched, sum.Unmatched)
	}
	if sum.Stars != 1 || sum.Ratings != 1 || sum.Listens != 3 || sum.Progress != 1 {
		t.Fatalf("counts = %+v", sum)
	}
	if sum.AlbumStars != 1 || sum.ArtistStars != 1 {
		t.Fatalf("entity star counts = %d album / %d artist, want 1 each", sum.AlbumStars, sum.ArtistStars)
	}
	// getStarred2's albums and artists land as catalog entity stars,
	// resolved through one member song rather than an entity matcher.
	ents := f.starredEntities(t, ctx)
	if len(ents.Albums) != 1 || ents.Albums[0].Title != "Fixture Album" {
		t.Fatalf("starred albums = %+v, want the fixture album", ents.Albums)
	}
	if len(ents.Artists) != 1 || ents.Artists[0].Title != "Fixture Artist" {
		t.Fatalf("starred artists = %+v, want the fixture artist", ents.Artists)
	}
	if len(sum.Samples.Unmatched) != 1 || sum.Samples.Unmatched[0] != "Unknown Artist - Nowhere Song" {
		t.Fatalf("unmatched samples = %v", sum.Samples.Unmatched)
	}
	alphaState := f.playState(t, ctx, alpha)
	if !alphaState.Starred {
		t.Fatal("alpha is not starred after import")
	}
	if alphaState.PlayCount != 3 {
		t.Fatalf("alpha play count = %d, want 3", alphaState.PlayCount)
	}
	// The star landed in the source's recorded time, not import time, so
	// a starred list ordered by star time keeps the user's history.
	if got := f.starredAt(t, ctx, alpha); !got.Equal(navStarredAt) {
		t.Errorf("alpha starred at %v, want the source's %v", got, navStarredAt)
	}
	bravoState := f.playState(t, ctx, bravo)
	if bravoState.Rating == nil || *bravoState.Rating != 80 {
		t.Fatalf("bravo rating = %v, want 80", bravoState.Rating)
	}
	if st := f.playState(t, ctx, charlie); st.PositionMS != 1500 {
		t.Fatalf("charlie position = %d, want 1500", st.PositionMS)
	}
	// The deterministic session ids landed as three distinct listens.
	if n, err := f.svc.db.ListenCount(ctx, f.uc.ID, strings.TrimPrefix(alpha, "tr-")); err != nil || n != 3 {
		t.Fatalf("alpha listens = %d (%v), want 3", n, err)
	}

	// A re-run is a no-op: the deterministic ids dedupe every listen
	// and the summary reports zero new ones.
	again := f.runMigration(t, ctx, req)
	if again.Listens != 0 {
		t.Fatalf("re-run ingested %d listens, want 0", again.Listens)
	}
	if n, err := f.svc.db.ListenCount(ctx, f.uc.ID, strings.TrimPrefix(alpha, "tr-")); err != nil || n != 3 {
		t.Fatalf("alpha listens after re-run = %d (%v), want 3", n, err)
	}
	if st := f.playState(t, ctx, alpha); st.PlayCount != 3 {
		t.Fatalf("alpha play count after re-run = %d, want 3", st.PlayCount)
	}

	// The bulk path the changed flag exists for: every row is
	// value-identical, so nothing is appended and no device is woken.
	// History and progress write unconditionally and are left out.
	tail := eventTail(t, ctx, f.svc, f.uc)
	quiet := f.runMigration(t, ctx, MigrationRequest{
		Source: "navidrome", ServerURL: ts.URL,
		Username: "demo", Password: "demo-pass",
		Stars: true, Ratings: true,
	})
	if quiet.Stars != 1 || quiet.Ratings != 1 {
		t.Fatalf("quiet re-run counts = %+v, want the same rows replayed", quiet)
	}
	var state []wdb.Event
	for _, e := range eventsAfter(t, ctx, f.svc, f.uc, tail) {
		if e.Kind == eventPlayState || e.Kind == eventEntityState {
			state = append(state, e)
		}
	}
	if len(state) != 0 {
		t.Fatalf("re-importing an already-starred set emitted %+v, want nothing", state)
	}
}

// newFakeNavidromeLateMatch emulates a source whose starred groups only
// reach the local library past their first candidate: the starred
// album's first song matches nothing here, and the starred artist's
// first album matches nothing at all. Stopping at either would silently
// drop a star for a group that is largely present.
func newFakeNavidromeLateMatch(t *testing.T, username, password string) *httptest.Server {
	t.Helper()
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		method := strings.TrimSuffix(strings.TrimPrefix(r.URL.Path, "/rest/"), ".view")
		q := r.URL.Query()
		sum := md5.Sum([]byte(password + q.Get("s")))
		if q.Get("u") != username || q.Get("t") != hex.EncodeToString(sum[:]) {
			writeSubsonic(w, `"error":{"code":40,"message":"Wrong username or password"}`, false)
			return
		}
		switch method {
		case "getStarred2":
			writeSubsonic(w, `"starred2":{"song":[],`+
				`"album":[{"id":"al-late","name":"Fixture Album","artist":"Fixture Artist"}],`+
				`"artist":[{"id":"ar-late","name":"Fixture Artist"}]}`, true)
		case "getArtist":
			// The all-miss album comes first, so a search that stopped at
			// the first candidate album would find nothing.
			writeSubsonic(w, `"artist":{"id":"ar-late","name":"Fixture Artist",`+
				`"album":[{"id":"al-ghost"},{"id":"al-late"}]}`, true)
		case "getAlbum":
			switch q.Get("id") {
			case "al-late":
				// The unmatchable song comes first.
				writeSubsonic(w, `"album":{"id":"al-late","song":[`+navSongNowhere+`,`+navSongAlpha+`]}`, true)
			case "al-ghost":
				writeSubsonic(w, `"album":{"id":"al-ghost","song":[`+navSongNowhere+`]}`, true)
			default:
				writeSubsonic(w, `"error":{"code":70,"message":"not found"}`, false)
			}
		case "getBookmarks":
			writeSubsonic(w, `"bookmarks":{"bookmark":[]}`, true)
		default:
			writeSubsonic(w, `"error":{"code":0,"message":"unknown method"}`, false)
		}
	}))
	t.Cleanup(ts.Close)
	return ts
}

func TestMigrateSubsonicEntityStarsSearchPastFirstCandidate(t *testing.T) {
	ctx, f := newMigrateFixture(t)
	ts := newFakeNavidromeLateMatch(t, "demo", "demo-pass")

	sum := f.runMigration(t, ctx, MigrationRequest{
		Source: "navidrome", ServerURL: ts.URL,
		Username: "demo", Password: "demo-pass",
		Stars: true,
	})
	if sum.AlbumStars != 1 {
		t.Errorf("album stars = %d, want 1: the album's second song matches locally", sum.AlbumStars)
	}
	if sum.ArtistStars != 1 {
		t.Errorf("artist stars = %d, want 1: the artist's second album matches locally", sum.ArtistStars)
	}
	ents := f.starredEntities(t, ctx)
	if len(ents.Albums) != 1 || ents.Albums[0].Title != "Fixture Album" {
		t.Errorf("starred albums = %+v, want the fixture album", ents.Albums)
	}
	if len(ents.Artists) != 1 || ents.Artists[0].Title != "Fixture Artist" {
		t.Errorf("starred artists = %+v, want the fixture artist", ents.Artists)
	}
}

// A starred group with no local member anywhere is still an unmatched
// sample, not a silent skip: exhausting the search must not turn a real
// miss into a success.
func TestMigrateSubsonicEntityStarsUnmatchedGroup(t *testing.T) {
	ctx, f := newMigrateFixture(t)
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch strings.TrimSuffix(strings.TrimPrefix(r.URL.Path, "/rest/"), ".view") {
		case "getStarred2":
			writeSubsonic(w, `"starred2":{"song":[],`+
				`"album":[{"id":"al-ghost","name":"Ghost Album","artist":"Unknown Artist"}],"artist":[]}`, true)
		case "getAlbum":
			writeSubsonic(w, `"album":{"id":"al-ghost","song":[`+navSongNowhere+`]}`, true)
		case "getBookmarks":
			writeSubsonic(w, `"bookmarks":{"bookmark":[]}`, true)
		default:
			writeSubsonic(w, `"error":{"code":0,"message":"unknown method"}`, false)
		}
	}))
	t.Cleanup(ts.Close)

	sum := f.runMigration(t, ctx, MigrationRequest{
		Source: "navidrome", ServerURL: ts.URL,
		Username: "demo", Password: "demo-pass",
		Stars: true,
	})
	if sum.AlbumStars != 0 {
		t.Errorf("album stars = %d, want 0", sum.AlbumStars)
	}
	// The miss is reported as an entity miss, not folded into the
	// per-song counter, which would read as a missing track.
	if sum.UnmatchedEntities != 1 || len(sum.Samples.UnmatchedEntities) != 1 {
		t.Errorf("unmatched entities = %d %v, want the ghost album reported",
			sum.UnmatchedEntities, sum.Samples.UnmatchedEntities)
	}
	if sum.Samples.UnmatchedEntities[0] != "Unknown Artist - Ghost Album" {
		t.Errorf("entity sample = %q", sum.Samples.UnmatchedEntities[0])
	}
	if sum.Unmatched != 0 || len(sum.Samples.Unmatched) != 0 {
		t.Errorf("song-level unmatched = %d %v, want none: no song was imported",
			sum.Unmatched, sum.Samples.Unmatched)
	}
	if ents := f.starredEntities(t, ctx); len(ents.Albums) != 0 {
		t.Errorf("starred albums = %+v, want none", ents.Albums)
	}
}

// newFakeABS emulates the slice of Audiobookshelf the import reads:
// bearer auth, the profile's mediaProgress, and expanded items. One
// book in progress, one finished, one that matches nothing local, and
// one podcast-episode row the importer must skip.
func newFakeABS(t *testing.T, token string) *httptest.Server {
	t.Helper()
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer "+token {
			http.Error(w, `{"error":"Unauthorized"}`, http.StatusUnauthorized)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/api/me":
			fmt.Fprint(w, `{"id":"usr1","username":"demo","mediaProgress":[
				{"id":"mp1","libraryItemId":"li-book","currentTime":12.5,"isFinished":false,"lastUpdate":1767322800000},
				{"id":"mp2","libraryItemId":"li-chaptered","currentTime":7.0,"isFinished":true,"lastUpdate":1767322800000},
				{"id":"mp3","libraryItemId":"li-ghost","currentTime":100,"isFinished":false,"lastUpdate":1767322800000},
				{"id":"mp4","libraryItemId":"li-pod","episodeId":"ep-1","currentTime":30,"isFinished":false,"lastUpdate":1767322800000}
			]}`)
		case "/api/items/li-book":
			fmt.Fprint(w, `{"id":"li-book","media":{"duration":15.0,"metadata":{"title":"The Fixture Book","authorName":"Ada Author","asin":"B00FIXTURE"}}}`)
		case "/api/items/li-chaptered":
			fmt.Fprint(w, `{"id":"li-chaptered","media":{"duration":7.0,"metadata":{"title":"The Chaptered Fixture","authors":[{"id":"au1","name":"Ada Author"}]}}}`)
		case "/api/items/li-ghost":
			fmt.Fprint(w, `{"id":"li-ghost","media":{"duration":300.0,"metadata":{"title":"No Such Book","authorName":"Nobody Known"}}}`)
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(ts.Close)
	return ts
}

func TestMigrateAudiobookshelfImport(t *testing.T) {
	ctx, f := newMigrateFixture(t)
	ts := newFakeABS(t, "abs-token")

	book := f.itemPID(t, ctx, model.KindBook, "The Fixture Book")
	chaptered := f.itemPID(t, ctx, model.KindBook, "The Chaptered Fixture")

	req := MigrationRequest{
		Source: "audiobookshelf", ServerURL: ts.URL, Token: "abs-token",
		Stars: true, Ratings: true, History: true, Progress: true,
	}
	sum := f.runMigration(t, ctx, req)
	if sum.Matched != 2 || sum.Unmatched != 1 || sum.Progress != 2 {
		t.Fatalf("summary = %+v, want matched 2, unmatched 1, progress 2", sum)
	}
	if len(sum.Samples.Unmatched) != 1 || sum.Samples.Unmatched[0] != "Nobody Known - No Such Book" {
		t.Fatalf("unmatched samples = %v", sum.Samples.Unmatched)
	}
	if st := f.playState(t, ctx, book); st.PositionMS != 12500 {
		t.Fatalf("book position = %d, want 12500", st.PositionMS)
	}
	fin := f.playState(t, ctx, chaptered)
	if !fin.Played || !fin.Finished {
		t.Fatalf("finished book state = %+v, want played and finished", fin)
	}

	// Re-running is a no-op, and says so: the positions already sit at
	// their source-recorded time, so every replay loses to what the
	// first run wrote and the report counts no new writes. Same shape as
	// the listen queues' idempotency.
	again := f.runMigration(t, ctx, req)
	if again.Matched != 2 {
		t.Fatalf("re-run summary = %+v", again)
	}
	if again.Progress != 0 {
		t.Errorf("re-run progress = %d, want 0: nothing was rewritten", again.Progress)
	}
	if st := f.playState(t, ctx, book); st.PositionMS != 12500 {
		t.Errorf("book position after re-run = %d, want the imported 12500 intact", st.PositionMS)
	}

	// The imported positions feed the resume shelf, which is what the
	// position stamps exist for beyond replay ordering.
	resume, err := f.svc.RecentlyPositionedItems(ctx, f.uc, 10)
	if err != nil {
		t.Fatalf("RecentlyPositionedItems: %v", err)
	}
	found := false
	for _, it := range resume {
		if it.PID == book {
			found = true
		}
	}
	if !found {
		t.Fatalf("imported book missing from the resume shelf: %+v", resume)
	}
}

// TestMigrateABSBackdatedProgressLosesToLocal pins the recency guard the
// importer now feeds: mediaProgress carries lastUpdate, so a stale
// source row replays in its own time instead of masquerading as a
// just-now checkpoint and taking the listener's place.
func TestMigrateABSBackdatedProgressLosesToLocal(t *testing.T) {
	ctx, f := newMigrateFixture(t)
	ts := newFakeABS(t, "abs-token")
	book := f.itemPID(t, ctx, model.KindBook, "The Fixture Book")

	// The listener is already further along here, checkpointed live.
	// Books are recency-primary, so only a newer replay may move them.
	if _, err := f.svc.Checkpoint(ctx, f.uc, book, 9000, nil); err != nil {
		t.Fatalf("live checkpoint: %v", err)
	}

	// The source row is stamped 2026-01-02, well behind that live write.
	sum := f.runMigration(t, ctx, MigrationRequest{
		Source: "audiobookshelf", ServerURL: ts.URL, Token: "abs-token",
		Progress: true,
	})
	if sum.Matched != 2 {
		t.Fatalf("summary = %+v, want 2 matched", sum)
	}
	if st := f.playState(t, ctx, book); st.PositionMS != 9000 {
		t.Errorf("book position = %d, want the live 9000 to survive the backdated import", st.PositionMS)
	}
	// The report counts writes, not attempts: the dropped replay must
	// not read as an imported position. Only the second book, which had
	// no local position to lose to, lands.
	if sum.Progress != 1 {
		t.Errorf("progress = %d, want 1: the backdated replay was dropped, not written", sum.Progress)
	}
}

func TestMigrateSessionID(t *testing.T) {
	a := migrateSessionID("navidrome", "song-1", 0)
	if a != "import:navidrome:song-1:0" {
		t.Fatalf("session id = %q", a)
	}
	if b := migrateSessionID("navidrome", "song-1", 0); b != a {
		t.Fatalf("session ids differ across calls: %q vs %q", a, b)
	}
	long := strings.Repeat("x", 100)
	c := migrateSessionID("navidrome", long, 499)
	if len(c) > 64 {
		t.Fatalf("overlong source id yields %d chars: %q", len(c), c)
	}
	if d := migrateSessionID("navidrome", long, 499); d != c {
		t.Fatalf("hashed session ids differ across calls: %q vs %q", c, d)
	}
	if migrateSessionID("navidrome", long, 498) == c {
		t.Fatal("distinct sequence numbers collide")
	}
}

func TestParseSubsonicTime(t *testing.T) {
	if ts := parseSubsonicTime("2026-01-02T03:04:05.000Z"); ts.IsZero() || ts.UTC() != time.Date(2026, 1, 2, 3, 4, 5, 0, time.UTC) {
		t.Fatalf("rfc3339 parse = %v", ts)
	}
	if ts := parseSubsonicTime("2026-01-02 03:04:05"); ts.IsZero() {
		t.Fatalf("legacy parse = %v", ts)
	}
	if ts := parseSubsonicTime("garbage"); !ts.IsZero() {
		t.Fatalf("garbage parse = %v", ts)
	}
	if ts := parseSubsonicTime(""); !ts.IsZero() {
		t.Fatalf("empty parse = %v", ts)
	}
}
