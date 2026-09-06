package service

import (
	"archive/zip"
	"bytes"
	"context"
	"crypto/md5"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"sort"
	"strconv"
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
	f.finishTask(t, ctx, row)
	var sum migrationSummary
	if err := json.Unmarshal([]byte(row.Summary), &sum); err != nil {
		t.Fatalf("summary %q: %v", row.Summary, err)
	}
	return sum
}

// finishTask completes a task the way the drain worker does: the
// terminal state on disk, and then the settle that disposes of any
// upload the run was reading. A test that stopped at the run left the
// import holding its claim on the export, which is exactly what the
// claim exists to refuse to the next one.
func (f *migrateFixture) finishTask(t *testing.T, ctx context.Context, row wdb.ToolTask) {
	t.Helper()
	row.State = taskStateDone
	row.ProgressPct = 100
	row.FinishedAtNS = time.Now().UnixNano()
	if err := f.svc.db.UpdateToolTask(ctx, row); err != nil {
		t.Fatal(err)
	}
	f.svc.settleMigrationExport(ctx, row.ID)
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
	t.Parallel()
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
	t.Parallel()
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
	t.Parallel()
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
	t.Parallel()
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
	t.Parallel()
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
	t.Parallel()
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
	t.Parallel()
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

// An import lands on the account it names, not on the administrator who
// ordered it. That is the whole of moving a household in: one person
// has the old server's credentials, and everybody else's listening has
// to end up under their own login.
func TestMigrateWritesToTheTargetAccount(t *testing.T) {
	t.Parallel()
	ctx, f := newMigrateFixture(t)
	ts := newFakeNavidrome(t, "demo", "demo-pass")
	alpha := f.itemPID(t, ctx, model.KindTrack, "Alpha Song")

	acct, err := f.svc.CreateAccount(ctx, AccountCreate{Username: "housemate", Password: "correct-horse"})
	if err != nil {
		t.Fatal(err)
	}
	memberCtx, err := f.svc.UserCtx(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}

	req := MigrationRequest{
		Source: "navidrome", ServerURL: ts.URL,
		Username: "demo", Password: "demo-pass", AccountID: acct.User.ID,
		Stars: true, Ratings: true, History: true, Progress: true,
	}
	sum := f.runMigration(t, ctx, req)
	if sum.Matched == 0 || sum.Listens == 0 {
		t.Fatalf("summary = %+v, want a real import", sum)
	}

	member, err := f.svc.PlayState(ctx, memberCtx, alpha)
	if err != nil {
		t.Fatal(err)
	}
	if member.PlayCount != 3 || !member.Starred {
		t.Fatalf("target play state = %+v, want the imported history", member)
	}
	// And nothing on the administrator's own account, which is the half
	// that would go unnoticed: an import that wrote to both would read
	// as working.
	if actor := f.playState(t, ctx, alpha); actor.PlayCount != 0 || actor.Starred {
		t.Fatalf("actor play state = %+v, want untouched", actor)
	}
	_, catalogPID, _ := parseAPIPID(alpha)
	listens, err := f.svc.db.ListenCount(ctx, f.uc.ID, string(catalogPID))
	if err != nil {
		t.Fatal(err)
	}
	if listens != 0 {
		t.Fatalf("the actor collected %d listens from somebody else's import", listens)
	}
	if listens, err = f.svc.db.ListenCount(ctx, acct.User.ID, string(catalogPID)); err != nil || listens != 3 {
		t.Fatalf("target listens = %d (%v), want the source's three", listens, err)
	}

	// A target that cannot hold state is refused before anything runs,
	// and again at run time - a task can sit queued while an account is
	// disabled underneath it.
	dto, err := f.svc.StartMigration(ctx, f.uc, req)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.UpdateAccount(ctx, acct.User.ID, AccountUpdate{Disabled: ptrTo(true)}); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.StartMigration(ctx, f.uc, req); KindOf(err) != KindInvalid {
		t.Fatalf("start onto a disabled account: kind = %v, want invalid", KindOf(err))
	}
	row, err := f.svc.db.ToolTaskByID(ctx, dto.ID)
	if err != nil {
		t.Fatal(err)
	}
	if err := f.svc.runMigrationTask(ctx, &row); err == nil || !errors.Is(err, errToolPermanent) {
		t.Fatalf("running onto a disabled account: %v, want a permanent failure", err)
	}

	// An account nobody has is a bad field, not a missing resource.
	req.AccountID = "us-01JZX5N8QW3F4V9T2B7KD3M9R6"
	if _, err := f.svc.StartMigration(ctx, f.uc, req); KindOf(err) != KindInvalid {
		t.Fatalf("start onto an unknown account: kind = %v, want invalid", KindOf(err))
	}
}

// Imported history is never forwarded to a connected scrobbler. The
// household has usually scrobbled it already, and years of it arriving
// again would be a second copy on somebody else's service.
func TestMigrateNeverScrobbles(t *testing.T) {
	t.Parallel()
	ctx, f := newMigrateFixture(t)
	ts := newFakeNavidrome(t, "demo", "demo-pass")

	if err := f.svc.db.UpsertScrobbleConnection(ctx, wdb.ScrobbleConnection{
		UserID: f.uc.ID, Service: "listenbrainz", SealedSecret: []byte("sealed"),
		Username: "demo", CreatedAtNS: time.Now().UnixNano(), UpdatedAtNS: time.Now().UnixNano(),
	}); err != nil {
		t.Fatal(err)
	}

	sum := f.runMigration(t, ctx, MigrationRequest{
		Source: "navidrome", ServerURL: ts.URL,
		Username: "demo", Password: "demo-pass",
		Stars: true, Ratings: true, History: true, Progress: true,
	})
	if sum.Listens == 0 {
		t.Fatalf("summary = %+v, want listens to have been written", sum)
	}

	// Nothing counts the outbox, so the drain's own claim stands in for
	// a count: an idle queue is exactly ErrNotFound.
	if row, err := f.svc.db.LeaseScrobble(ctx, time.Now().UnixNano(), int64(time.Minute), 5); !errors.Is(err, wdb.ErrNotFound) {
		t.Fatalf("an import queued a scrobble: %+v (%v)", row, err)
	}

	// The same listen arriving live still does, so this is the source
	// field doing the work rather than scrobbling being off.
	alpha := f.itemPID(t, ctx, model.KindTrack, "Alpha Song")
	if _, err := f.svc.IngestListens(ctx, f.uc, []ListenSession{{
		SessionID: "live-1", PID: alpha, StartedAt: time.Now().Add(-time.Minute),
		MsPlayed: 2000, Finished: true, Client: "test",
	}}); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.db.LeaseScrobble(ctx, time.Now().UnixNano(), int64(time.Minute), 5); err != nil {
		t.Fatalf("a live listen queued no scrobble (%v), so the import assertion proves nothing", err)
	}
}

// newFakeJellyfin emulates the slice of Jellyfin the import walks:
// login and API-key auth, the paged user-scoped item list with its
// UserData, and the favourites listing for albums and artists.
func newFakeJellyfin(t *testing.T, username, password, apiKey string) *httptest.Server {
	t.Helper()
	const (
		userID = "0f11a5c0e5b34b1e9d2c8f0a1b2c3d4e"
		token  = "jf-access-token"
	)
	songs := []string{
		`{"Id":"jf-alpha","Name":"Alpha Song","Album":"Fixture Album","AlbumArtist":"Fixture Artist",` +
			`"Artists":["Fixture Artist"],"RunTimeTicks":20000000,` +
			`"ProviderIds":{"MusicBrainzTrack":"5f2ab3d1-6f70-4d67-9028-53144d5f2f9c"},` +
			`"UserData":{"IsFavorite":true,"PlayCount":3,"LastPlayedDate":"2026-01-02T03:04:05.0000000Z"}}`,
		`{"Id":"jf-bravo","Name":"Bravo Song","Album":"Fixture Album","AlbumArtist":"Fixture Artist",` +
			`"Artists":["Fixture Artist"],"RunTimeTicks":30000000,"ProviderIds":{},` +
			`"UserData":{"IsFavorite":false,"PlayCount":0,"PlaybackPositionTicks":15000000}}`,
		`{"Id":"jf-nowhere","Name":"Nowhere Song","Album":"Ghost Album","AlbumArtist":"Unknown Artist",` +
			`"Artists":["Unknown Artist"],"RunTimeTicks":30000000,"ProviderIds":{},` +
			`"UserData":{"IsFavorite":true,"PlayCount":1}}`,
		// Carries no state at all, so it must never be matched: a walk
		// that resolved every song in a library would be pure cost.
		`{"Id":"jf-idle","Name":"Charlie Song","Album":"Fixture Album","AlbumArtist":"Fixture Artist",` +
			`"Artists":["Fixture Artist"],"RunTimeTicks":30000000,"ProviderIds":{},"UserData":{}}`,
	}
	favourites := []string{
		`{"Id":"jf-al-1","Type":"MusicAlbum","Name":"Fixture Album","AlbumArtist":"Fixture Artist","UserData":{"IsFavorite":true}}`,
		`{"Id":"jf-ar-1","Type":"MusicArtist","Name":"Fixture Artist","UserData":{"IsFavorite":true}}`,
		// A favourite album nobody has played: none of its tracks
		// carried state, so nothing in the walk names it and the only
		// way to reach it is to ask what is in it.
		`{"Id":"jf-al-2","Type":"MusicAlbum","Name":"Unplayed Album","AlbumArtist":"Fixture Artist","UserData":{"IsFavorite":true}}`,
	}
	// What that album holds, answered only when asked for by parent.
	members := []string{
		`{"Id":"jf-charlie","Name":"Charlie Song","Album":"Unplayed Album","AlbumArtist":"Fixture Artist",` +
			`"Artists":["Fixture Artist"],"RunTimeTicks":30000000,"ProviderIds":{},"UserData":{}}`,
	}
	page := func(w http.ResponseWriter, rows []string) {
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprintf(w, `{"Items":[%s],"TotalRecordCount":%d}`, strings.Join(rows, ","), len(rows))
	}
	// The device id the run in flight identified itself with, so one
	// import reads as one session on the source rather than one per
	// request.
	device := ""
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		auth := r.Header.Get("Authorization")
		if !strings.HasPrefix(auth, "MediaBrowser ") || !strings.Contains(auth, `Device="waxdeck-migrate"`) {
			http.Error(w, "bad auth header", http.StatusUnauthorized)
			return
		}
		_, rest, _ := strings.Cut(auth, `DeviceId="`)
		id, _, _ := strings.Cut(rest, `"`)
		// Every import opens with a login or a user lookup, which is
		// where a new device is expected; every later call in that run
		// has to carry the same one.
		if r.URL.Path == "/Users/AuthenticateByName" || r.URL.Path == "/Users" {
			device = id
		} else if id != device {
			t.Errorf("device id changed mid-import: %q then %q", device, id)
		}
		switch r.URL.Path {
		case "/Users/AuthenticateByName":
			var body struct{ Username, Pw string }
			json.NewDecoder(r.Body).Decode(&body)
			if body.Username != username || body.Pw != password {
				http.Error(w, "wrong password", http.StatusUnauthorized)
				return
			}
			fmt.Fprintf(w, `{"AccessToken":%q,"User":{"Id":%q}}`, token, userID)
		case "/Users":
			// Only an API key reads this; a login already knows who it is.
			if !strings.Contains(auth, fmt.Sprintf("Token=%q", apiKey)) {
				http.Error(w, "not a key", http.StatusForbidden)
				return
			}
			fmt.Fprintf(w, `[{"Id":%q,"Name":%q}]`, userID, username)
		case "/Items":
			if !strings.Contains(auth, fmt.Sprintf("Token=%q", token)) &&
				!strings.Contains(auth, fmt.Sprintf("Token=%q", apiKey)) {
				http.Error(w, "no credential", http.StatusUnauthorized)
				return
			}
			q := r.URL.Query()
			if q.Get("userId") != userID {
				http.Error(w, "the items listing was not user-scoped", http.StatusBadRequest)
				return
			}
			if q.Get("StartIndex") != "0" {
				page(w, nil)
				return
			}
			switch {
			case q.Get("Filters") == "IsFavorite":
				page(w, favourites)
			case q.Get("ParentId") == "jf-al-2":
				page(w, members)
			case q.Get("ParentId") != "" || q.Get("ArtistIds") != "":
				page(w, nil)
			case q.Get("IncludeItemTypes") == "Audio":
				page(w, songs)
			default:
				page(w, nil)
			}
		default:
			http.Error(w, "unknown path "+r.URL.Path, http.StatusNotFound)
		}
	}))
	t.Cleanup(ts.Close)
	return ts
}

func TestMigrateJellyfinImport(t *testing.T) {
	t.Parallel()
	ctx, f := newMigrateFixture(t)
	ts := newFakeJellyfin(t, "demo", "demo-pass", "jf-api-key")

	alpha := f.itemPID(t, ctx, model.KindTrack, "Alpha Song")
	bravo := f.itemPID(t, ctx, model.KindTrack, "Bravo Song")
	charlie := f.itemPID(t, ctx, model.KindTrack, "Charlie Song")

	req := MigrationRequest{
		Source: "jellyfin", ServerURL: ts.URL,
		Username: "demo", Password: "demo-pass",
		Stars: true, Ratings: true, History: true, Progress: true,
		DryRun: true,
	}

	// Jellyfin takes either a login or a server API key, and an API key
	// alone names nobody: without a username there is no per-user data
	// to read.
	if _, err := f.svc.StartMigration(ctx, f.uc, MigrationRequest{Source: "jellyfin", ServerURL: ts.URL}); KindOf(err) != KindInvalid {
		t.Fatalf("jellyfin with nothing: kind = %v, want invalid", KindOf(err))
	}
	if _, err := f.svc.StartMigration(ctx, f.uc, MigrationRequest{Source: "jellyfin", ServerURL: ts.URL, Username: "demo"}); KindOf(err) != KindInvalid {
		t.Fatalf("jellyfin with no secret: kind = %v, want invalid", KindOf(err))
	}

	dry := f.runMigration(t, ctx, req)
	if dry.Matched != 2 || dry.Unmatched != 1 {
		t.Fatalf("dry matched/unmatched = %d/%d, want 2/1", dry.Matched, dry.Unmatched)
	}
	if dry.Stars != 1 || dry.Listens != 3 || dry.Progress != 1 {
		t.Fatalf("dry counts = %+v", dry)
	}
	// Both favourite albums, including the one whose tracks were never
	// played: reporting a present album as missing would tell the
	// administrator to go looking for something that is already here.
	if dry.AlbumStars != 2 || dry.ArtistStars != 1 {
		t.Fatalf("dry entity stars = %d album / %d artist, want 2 and 1", dry.AlbumStars, dry.ArtistStars)
	}
	if dry.UnmatchedEntities != 0 {
		t.Fatalf("dry unmatched entities = %d: %v", dry.UnmatchedEntities, dry.Samples.UnmatchedEntities)
	}
	// Jellyfin has no per-user rating, so an import that reported one
	// would be inventing it.
	if dry.Ratings != 0 {
		t.Fatalf("ratings = %d, want none: jellyfin has none to import", dry.Ratings)
	}
	if st := f.playState(t, ctx, alpha); st.PlayCount != 0 || st.Starred {
		t.Fatalf("dry run wrote %+v", st)
	}

	// The real run, over the API key path rather than the login, which
	// is the half a password-only test never reaches.
	req.DryRun = false
	req.Password = ""
	req.Token = "jf-api-key"
	live := f.runMigration(t, ctx, req)
	if live.Stars != 1 || live.Listens != 3 || live.Progress != 1 {
		t.Fatalf("live summary = %+v", live)
	}

	st := f.playState(t, ctx, alpha)
	if st.PlayCount != 3 || !st.Starred {
		t.Fatalf("alpha state = %+v", st)
	}
	if st := f.playState(t, ctx, bravo); st.PositionMS != 1500 {
		t.Fatalf("bravo position = %d, want the source's 1500ms", st.PositionMS)
	}
	// The song with no state on the source is untouched here, which is
	// what says the walk skipped it rather than matching everything.
	if st := f.playState(t, ctx, charlie); st.PlayCount != 0 || st.Starred || st.PositionMS != 0 {
		t.Fatalf("charlie state = %+v, want untouched", st)
	}
	ents := f.starredEntities(t, ctx)
	if len(ents.Albums) != 1 || len(ents.Artists) != 1 {
		// One album locally: both favourites resolve through the same
		// fixture album, which is what a name that is not in the library
		// under its own title does.
		t.Fatalf("starred entities = %+v", ents)
	}

	// And it is idempotent: the deterministic session ids make a second
	// run add no listens.
	again := f.runMigration(t, ctx, req)
	if again.Listens != 0 {
		t.Fatalf("a second run added %d listens", again.Listens)
	}
	if st := f.playState(t, ctx, alpha); st.PlayCount != 3 {
		t.Fatalf("play count after re-import = %d, want 3", st.PlayCount)
	}
}

// newFakeLastfm answers the two read methods the import walks, in the
// envelopes the real service uses: a two-page scrobble history newest
// first, and one loved track. It also asserts the `to` window is pinned,
// which is what stops a scrobble arriving mid-walk from shifting a page.
func newFakeLastfm(t *testing.T, user string) *httptest.Server {
	t.Helper()
	// Two plays of Alpha and one of a track this library does not hold,
	// plus a now-playing row, which is not a scrobble and must not land.
	page1 := `{"track":[` +
		`{"name":"Alpha Song","mbid":"5f2ab3d1-6f70-4d67-9028-53144d5f2f9c",` +
		`"artist":{"#text":"Fixture Artist","mbid":""},"album":{"#text":"Fixture Album"},` +
		`"@attr":{"nowplaying":"true"}},` +
		`{"name":"Alpha Song","mbid":"5f2ab3d1-6f70-4d67-9028-53144d5f2f9c",` +
		`"artist":{"#text":"Fixture Artist","mbid":""},"album":{"#text":"Fixture Album"},` +
		`"date":{"uts":"1767411845"}},` +
		`{"name":"Alpha Song","mbid":"5f2ab3d1-6f70-4d67-9028-53144d5f2f9c",` +
		`"artist":{"#text":"Fixture Artist","mbid":""},"album":{"#text":"Fixture Album"},` +
		`"date":{"uts":"1767325445"}},` +
		`{"name":"Nowhere Song","mbid":"","artist":{"#text":"Unknown Artist"},` +
		`"album":{"#text":"Ghost Album"},"date":{"uts":"1767239045"}}` +
		`],"@attr":{"totalPages":"2","page":"1"}}`
	// A single-row page, which this API answers as an object rather than
	// a one-element array.
	page2 := `{"track":` +
		`{"name":"Alpha Song","mbid":"","artist":{"#text":"Fixture Artist"},` +
		`"album":{"#text":"Fixture Album"},"date":{"uts":"1767152645"}}` +
		`,"@attr":{"totalPages":"2","page":"2"}}`
	loved := `{"track":[` +
		`{"name":"Bravo Song","mbid":"","artist":{"#text":"Fixture Artist"},` +
		`"album":{"#text":"Fixture Album"},"date":{"uts":"1764560645"}}` +
		`],"@attr":{"totalPages":"1","page":"1"}}`
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		r.ParseForm()
		if r.Form.Get("user") != user || r.Form.Get("api_sig") == "" {
			http.Error(w, `{"error":6,"message":"no such user"}`, http.StatusOK)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		switch r.Form.Get("method") {
		case "user.getRecentTracks":
			if r.Form.Get("to") == "" {
				t.Error("the history walk did not pin its newer end")
			}
			if r.Form.Get("page") == "1" {
				fmt.Fprintf(w, `{"recenttracks":%s}`, page1)
			} else {
				fmt.Fprintf(w, `{"recenttracks":%s}`, page2)
			}
		case "user.getLovedTracks":
			fmt.Fprintf(w, `{"lovedtracks":%s}`, loved)
		default:
			fmt.Fprint(w, `{"error":3,"message":"invalid method"}`)
		}
	}))
	t.Cleanup(ts.Close)
	return ts
}

func TestMigrateLastfmImport(t *testing.T) {
	t.Parallel()
	ctx, f := newMigrateFixture(t)
	alpha := f.itemPID(t, ctx, model.KindTrack, "Alpha Song")
	bravo := f.itemPID(t, ctx, model.KindTrack, "Bravo Song")

	req := MigrationRequest{
		Source: "lastfm", Username: "demo",
		Stars: true, Ratings: true, History: true, Progress: true,
	}
	// Read with the server's own credentials, so an install without them
	// is refused where somebody can act on it rather than in a report.
	if _, err := f.svc.StartMigration(ctx, f.uc, req); KindOf(err) != KindInvalid {
		t.Fatalf("lastfm with no server key: kind = %v, want invalid", KindOf(err))
	}

	ts := newFakeLastfm(t, "demo")
	if _, err := f.svc.LastfmConfigPut(ctx, f.uc, "test-key", "test-secret"); err != nil {
		t.Fatal(err)
	}
	f.svc.lastfmClient().BaseURL = ts.URL + "/2.0/"

	// A source that carries no server URL takes none: pointing this one
	// somewhere would be a field with no meaning.
	if _, err := f.svc.StartMigration(ctx, f.uc,
		MigrationRequest{Source: "lastfm", Username: "demo", ServerURL: ts.URL}); KindOf(err) != KindInvalid {
		t.Fatalf("lastfm with a server URL: kind = %v, want invalid", KindOf(err))
	}

	sum := f.runMigration(t, ctx, req)
	// Three scrobbles of Alpha across two pages, one loved Bravo, one
	// play of a track nothing here holds. The now-playing row is not a
	// scrobble and must not be one of them.
	if sum.Listens != 3 {
		t.Fatalf("listens = %d, want the three real scrobbles: %+v", sum.Listens, sum)
	}
	if sum.Stars != 1 || sum.Unmatched != 1 {
		t.Fatalf("summary = %+v", sum)
	}

	st := f.playState(t, ctx, alpha)
	if st.PlayCount != 3 {
		t.Fatalf("alpha play count = %d, want 3", st.PlayCount)
	}
	// Upstream stamps last-played at the write, so the catalog's own
	// time is the import instant; the real times are on the listen rows,
	// which is what a history import is for.
	rows, err := f.svc.db.ListenLog(ctx, f.uc.ID, "", 0, 0, 10)
	if err != nil {
		t.Fatal(err)
	}
	var at []int64
	for _, r := range rows {
		at = append(at, r.StartedAt.Unix())
	}
	sort.Slice(at, func(i, j int) bool { return at[i] < at[j] })
	if !slices.Equal(at, []int64{1767152645, 1767325445, 1767411845}) {
		t.Fatalf("listen times = %v, want the source's own", at)
	}
	if got := f.playState(t, ctx, bravo); !got.Starred {
		t.Fatalf("bravo state = %+v, want the loved track starred", got)
	}
	if at := f.starredAt(t, ctx, bravo); at.Unix() != 1764560645 {
		t.Fatalf("bravo starred at %v, want the source's own time", at)
	}

	// Idempotent: the deterministic ids make a second run add nothing.
	if again := f.runMigration(t, ctx, req); again.Listens != 0 {
		t.Fatalf("a second run added %d listens", again.Listens)
	}
}

// newFakeListenBrainz answers the two surfaces the import walks: the
// listens log, filtered the way the real one is (listened_at strictly
// below max_ts, newest first, capped at the server's own page size),
// and the loved-recording feedback.
//
// The page size is two so a walk takes several pages, and two listens
// share one second across a page boundary - the shape that a cursor
// stepping below the oldest row would silently skip.
func newFakeListenBrainz(t *testing.T, user, token string) *httptest.Server {
	t.Helper()
	const (
		newest = 1767411845
		middle = 1767325445
		oldest = 1767152645
	)
	listen := func(at int64, msid, mbid, artist, title, album string, ms int64) string {
		info := fmt.Sprintf(`{"recording_mbid":%q,"duration_ms":%d}`, mbid, ms)
		return fmt.Sprintf(`{"listened_at":%d,"recording_msid":%q,"track_metadata":`+
			`{"artist_name":%q,"track_name":%q,"release_name":%q,"additional_info":%s}}`,
			at, msid, artist, title, album, info)
	}
	// Ordered newest first, with the last two sharing one second so a
	// three-row page ends between them.
	rows := []struct {
		at   int64
		body string
	}{
		{newest, listen(newest, "msid-1", "5f2ab3d1-6f70-4d67-9028-53144d5f2f9c",
			"Fixture Artist", "Alpha Song", "Fixture Album", 2000)},
		{middle, listen(middle, "msid-2", "", "Unknown Artist", "Nowhere Song", "Ghost Album", 0)},
		{oldest, listen(oldest, "msid-3", "", "Fixture Artist", "Alpha Song", "Fixture Album", 0)},
		{oldest, listen(oldest, "msid-4", "", "Fixture Artist", "Charlie Song", "Fixture Album", 0)},
	}
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if token != "" && r.Header.Get("Authorization") != "Token "+token {
			http.Error(w, "bad token", http.StatusUnauthorized)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		q := r.URL.Query()
		switch r.URL.Path {
		case "/1/user/" + user + "/listens":
			maxTS := int64(0)
			if v := q.Get("max_ts"); v != "" {
				parsed, err := strconv.ParseInt(v, 10, 64)
				if err != nil {
					http.Error(w, "bad max_ts", http.StatusBadRequest)
					return
				}
				maxTS = parsed
			}
			count, err := strconv.Atoi(q.Get("count"))
			if err != nil || count <= 0 {
				http.Error(w, "bad count", http.StatusBadRequest)
				return
			}
			var out []string
			for _, row := range rows {
				if maxTS != 0 && row.at >= maxTS {
					continue
				}
				out = append(out, row.body)
				if len(out) == count {
					break
				}
			}
			fmt.Fprintf(w, `{"payload":{"listens":[%s]}}`, strings.Join(out, ","))
		case "/1/feedback/user/" + user + "/get-feedback":
			if q.Get("score") != "1" || q.Get("offset") != "0" {
				fmt.Fprint(w, `{"feedback":[]}`)
				return
			}
			fmt.Fprint(w, `{"feedback":[{"recording_mbid":"","track_metadata":`+
				`{"artist_name":"Fixture Artist","track_name":"Bravo Song","release_name":"Fixture Album"}}]}`)
		default:
			http.Error(w, "unknown path "+r.URL.Path, http.StatusNotFound)
		}
	}))
	t.Cleanup(ts.Close)
	return ts
}

func TestMigrateListenBrainzImport(t *testing.T) {
	t.Parallel()
	ctx, f := newMigrateFixture(t)
	ts := newFakeListenBrainz(t, "demo", "lb-token")
	alpha := f.itemPID(t, ctx, model.KindTrack, "Alpha Song")
	bravo := f.itemPID(t, ctx, model.KindTrack, "Bravo Song")
	charlie := f.itemPID(t, ctx, model.KindTrack, "Charlie Song")

	// A page that ends between the two listens sharing one second, which
	// is where a cursor stepping below the oldest row it saw loses the
	// rest of that second for good.
	was := migrateLBPageSize
	t.Cleanup(func() { migrateLBPageSize = was })
	migrateLBPageSize = 3

	req := MigrationRequest{
		Source: "listenbrainz", ServerURL: ts.URL, Username: "demo", Token: "lb-token",
		Stars: true, Ratings: true, History: true, Progress: true,
	}
	sum := f.runMigration(t, ctx, req)
	if sum.Listens != 3 || sum.Stars != 1 || sum.Unmatched != 1 {
		t.Fatalf("summary = %+v, want three plays, one love, one miss", sum)
	}
	if sum.HistoryTruncated {
		t.Fatalf("summary = %+v, want a history that finished", sum)
	}
	if st := f.playState(t, ctx, alpha); st.PlayCount != 2 {
		t.Fatalf("alpha play count = %d, want 2", st.PlayCount)
	}
	// The listen that shares its second with Alpha's older play, on the
	// far side of a page boundary: a cursor stepping below the oldest
	// row it saw would never ask for it again.
	if st := f.playState(t, ctx, charlie); st.PlayCount != 1 {
		t.Fatalf("charlie play count = %d, want the listen that tied at one second", st.PlayCount)
	}
	if st := f.playState(t, ctx, bravo); !st.Starred {
		t.Fatalf("bravo state = %+v, want the loved recording starred", st)
	}
	rows, err := f.svc.db.ListenLog(ctx, f.uc.ID, "", 0, 0, 10)
	if err != nil {
		t.Fatal(err)
	}
	var at []int64
	for _, r := range rows {
		at = append(at, r.StartedAt.Unix())
	}
	sort.Slice(at, func(i, j int) bool { return at[i] < at[j] })
	if !slices.Equal(at, []int64{1767152645, 1767152645, 1767411845}) {
		t.Fatalf("listen times = %v, want the source's own", at)
	}

	if again := f.runMigration(t, ctx, req); again.Listens != 0 {
		t.Fatalf("a second run added %d listens", again.Listens)
	}

	// A compatible server that takes submissions but serves no history
	// fails permanently, saying which half is missing rather than
	// retrying a 404 forever.
	silent := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "not found", http.StatusNotFound)
	}))
	t.Cleanup(silent.Close)
	dto, err := f.svc.StartMigration(ctx, f.uc, MigrationRequest{
		Source: "listenbrainz", ServerURL: silent.URL, Username: "demo", History: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	row, err := f.svc.db.ToolTaskByID(ctx, dto.ID)
	if err != nil {
		t.Fatal(err)
	}
	err = f.svc.runMigrationTask(ctx, &row)
	if err == nil || !errors.Is(err, errToolPermanent) || !strings.Contains(err.Error(), "listen history") {
		t.Fatalf("a submit-only server answered %v, want a permanent refusal naming the missing half", err)
	}
}

// spotifyExportZip builds an account data export in memory, nested
// under the folder name a real one uses, with both history shapes, a
// podcast sibling that must not be read, and the saved-tracks file.
func spotifyExportZip(t *testing.T) []byte {
	t.Helper()
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	add := func(name, body string) {
		w, err := zw.Create(name)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := io.WriteString(w, body); err != nil {
			t.Fatal(err)
		}
	}
	const root = "Spotify Account Data/"
	// The basic export: end time to the minute, so the start is derived
	// from what was played.
	add(root+"StreamingHistory_music_0.json", `[
		{"endTime":"2026-01-02 03:04","artistName":"Fixture Artist","trackName":"Alpha Song","msPlayed":2000},
		{"endTime":"2026-01-03 07:08","artistName":"Unknown Artist","trackName":"Nowhere Song","msPlayed":1000}
	]`)
	// The extended export, which carries the album and a real timestamp.
	add(root+"Streaming_History_Audio_2026_1.json", `[
		{"ts":"2026-02-01T10:00:00Z","ms_played":2000,
		 "master_metadata_track_name":"Alpha Song",
		 "master_metadata_album_artist_name":"Fixture Artist",
		 "master_metadata_album_album_name":"Fixture Album"},
		{"ts":"2026-02-02T10:00:00Z","ms_played":900000,
		 "master_metadata_track_name":null,
		 "master_metadata_album_artist_name":null}
	]`)
	// A sibling of the music file, and not one this import reads.
	add(root+"Streaming_History_Audio_podcast_2026.json", `[{"ts":"2026-02-03T10:00:00Z"}]`)
	add(root+"YourLibrary.json",
		`{"tracks":[{"artist":"Fixture Artist","album":"Fixture Album","track":"Bravo Song"}]}`)
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func TestMigrateSpotifyExport(t *testing.T) {
	t.Parallel()
	ctx, f := newMigrateFixture(t)
	alpha := f.itemPID(t, ctx, model.KindTrack, "Alpha Song")
	bravo := f.itemPID(t, ctx, model.KindTrack, "Bravo Song")

	// Something that is not an export at all is refused at the upload
	// rather than staged for a task nobody is watching to fail on.
	if _, err := f.svc.StageMigrationExport(ctx, f.uc, strings.NewReader("not a zip"), 0); KindOf(err) != KindInvalid {
		t.Fatalf("a non-zip upload: kind = %v, want invalid", KindOf(err))
	}
	var empty bytes.Buffer
	zip.NewWriter(&empty).Close()
	if _, err := f.svc.StageMigrationExport(ctx, f.uc, bytes.NewReader(empty.Bytes()), 0); KindOf(err) != KindInvalid {
		t.Fatalf("a zip holding nothing readable: kind = %v, want invalid", KindOf(err))
	}

	archive := spotifyExportZip(t)
	staged, err := f.svc.StageMigrationExport(ctx, f.uc, bytes.NewReader(archive), int64(len(archive)))
	if err != nil {
		t.Fatal(err)
	}
	if staged.Source != "spotify" || !strings.HasPrefix(staged.PID, "mx-") {
		t.Fatalf("staged = %+v", staged)
	}
	// The podcast sibling shares the music file's prefix and must not be
	// read; the basic history is dropped because the extended one covers
	// the same listening at a finer time, and reading both would count
	// every overlapping play twice.
	if len(staged.Files) != 2 {
		t.Fatalf("staged files = %v, want the extended history and the library", staged.Files)
	}
	for _, name := range staged.Files {
		if strings.Contains(name, "podcast") {
			t.Fatalf("the podcast history was staged for reading: %v", staged.Files)
		}
		if strings.Contains(name, "StreamingHistory_music_") {
			t.Fatalf("the basic history was read beside the extended one: %v", staged.Files)
		}
	}

	// An export id is required for spotify and refused for a source that
	// reads a server.
	if _, err := f.svc.StartMigration(ctx, f.uc, MigrationRequest{Source: "spotify"}); KindOf(err) != KindInvalid {
		t.Fatalf("spotify with no export: kind = %v, want invalid", KindOf(err))
	}
	if _, err := f.svc.StartMigration(ctx, f.uc, MigrationRequest{
		Source: "lastfm", Username: "demo", ExportID: staged.PID,
	}); KindOf(err) != KindInvalid {
		t.Fatalf("lastfm with an export: kind = %v, want invalid", KindOf(err))
	}

	req := MigrationRequest{
		Source: "spotify", ExportID: staged.PID,
		Stars: true, Ratings: true, History: true, Progress: true,
		DryRun: true,
	}
	dry := f.runMigration(t, ctx, req)
	if dry.Listens != 1 || dry.Stars != 1 || dry.Unmatched != 0 {
		t.Fatalf("dry summary = %+v, want the extended history's one play and one save", dry)
	}
	if dry.Files != 2 {
		t.Fatalf("dry files = %d, want the two read", dry.Files)
	}
	if st := f.playState(t, ctx, alpha); st.PlayCount != 0 {
		t.Fatalf("a dry run wrote %+v", st)
	}
	// The dry run keeps the export: running the real import afterwards
	// is the whole point of one.
	if _, err := f.svc.db.MigrationExportByID(ctx, staged.PID); err != nil {
		t.Fatalf("the dry run discarded the export: %v", err)
	}

	req.DryRun = false
	dto, err := f.svc.StartMigration(ctx, f.uc, req)
	if err != nil {
		t.Fatal(err)
	}
	row, err := f.svc.db.ToolTaskByID(ctx, dto.ID)
	if err != nil {
		t.Fatal(err)
	}
	if err := f.svc.runMigrationTask(ctx, &row); err != nil {
		t.Fatal(err)
	}
	f.finishTask(t, ctx, row)
	var sum migrationSummary
	if err := json.Unmarshal([]byte(row.Summary), &sum); err != nil {
		t.Fatal(err)
	}
	if sum.Listens != 1 || sum.Stars != 1 {
		t.Fatalf("live summary = %+v", sum)
	}

	// The play lands at the time it happened. Both shapes record when
	// the play stopped, so the start is derived: a play that ends at
	// 10:00:00 having run two seconds began at 09:59:58, and a stop time
	// stored as a start would land every play up to a track length late.
	rows, err := f.svc.db.ListenLog(ctx, f.uc.ID, "", 0, 0, 10)
	if err != nil {
		t.Fatal(err)
	}
	var at []int64
	for _, r := range rows {
		at = append(at, r.StartedAt.Unix())
	}
	want := []int64{time.Date(2026, 2, 1, 9, 59, 58, 0, time.UTC).Unix()}
	if !slices.Equal(at, want) {
		t.Fatalf("listen times = %v, want %v", at, want)
	}
	if st := f.playState(t, ctx, bravo); !st.Starred {
		t.Fatalf("bravo state = %+v, want the saved track starred", st)
	}

	// The archive is deleted once it has been read, and the finished
	// task no longer names a file that is gone.
	if _, err := f.svc.db.MigrationExportByID(ctx, staged.PID); err == nil {
		t.Fatal("the export outlived the import that read it")
	}
	f.svc.scrubTaskSecrets(ctx, dto.ID)
	after, err := f.svc.db.ToolTaskByID(ctx, dto.ID)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(after.Params, staged.PID) {
		t.Fatalf("the finished task still names the deleted export: %s", after.Params)
	}

	// An export id that names nothing is refused where somebody can act
	// on it, rather than accepted and failed in a task report.
	req.ExportID = "mx-01JZX5N8QW3F4V9T2B7KD3M9R6"
	if _, err := f.svc.StartMigration(ctx, f.uc, req); KindOf(err) != KindInvalid {
		t.Fatalf("an unknown export: kind = %v, want invalid", KindOf(err))
	}
}

// A staged export belongs to the administrator who uploaded it. It is
// one person's listening history, and the import that reads it deletes
// the file, so a second administrator naming the id would both read it
// and take it away.
func TestMigrationExportIsNotSharedBetweenAdmins(t *testing.T) {
	t.Parallel()
	ctx, f := newMigrateFixture(t)
	archive := spotifyExportZip(t)
	staged, err := f.svc.StageMigrationExport(ctx, f.uc, bytes.NewReader(archive), 0)
	if err != nil {
		t.Fatal(err)
	}

	other, err := f.svc.CreateAccount(ctx, AccountCreate{
		Username: "second-admin", Password: "correct-horse", Roles: []string{"admin"},
	})
	if err != nil {
		t.Fatal(err)
	}
	otherCtx, err := f.svc.UserCtx(ctx, other.User)
	if err != nil {
		t.Fatal(err)
	}

	order := MigrationRequest{Source: "spotify", ExportID: staged.PID, History: true}
	if _, err := f.svc.StartMigration(ctx, otherCtx, order); KindOf(err) != KindInvalid {
		t.Fatalf("another administrator's export: kind = %v, want invalid", KindOf(err))
	}
	if err := f.svc.DiscardMigrationExport(ctx, otherCtx, staged.PID); KindOf(err) != KindNotFound {
		t.Fatalf("discarding another administrator's export: kind = %v, want not-found", KindOf(err))
	}
	// Untouched, so the administrator who uploaded it can still use it.
	if _, err := f.svc.db.MigrationExportByID(ctx, staged.PID); err != nil {
		t.Fatalf("the upload was destroyed by somebody else's order: %v", err)
	}
	if _, err := f.svc.StartMigration(ctx, f.uc, order); err != nil {
		t.Fatalf("the uploader's own order: %v", err)
	}

	// An expired row is refused rather than waiting for the sweep, and
	// an export of one service is not an order for another.
	row, err := f.svc.db.MigrationExportByID(ctx, staged.PID)
	if err != nil {
		t.Fatal(err)
	}
	expired := row
	expired.ExpiresAtNS = time.Now().Add(-time.Minute).UnixNano()
	if err := f.svc.db.DeleteMigrationExport(ctx, row.ID); err != nil {
		t.Fatal(err)
	}
	if err := f.svc.db.InsertMigrationExport(ctx, expired); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.StartMigration(ctx, f.uc, order); KindOf(err) != KindInvalid {
		t.Fatalf("an expired export: kind = %v, want invalid", KindOf(err))
	}
}

// The older export package on its own, which is what an account that
// asked for its data years ago holds: minute-resolution stop times, no
// album, and the start derived from what was played.
func TestMigrateSpotifyBasicExport(t *testing.T) {
	t.Parallel()
	ctx, f := newMigrateFixture(t)
	alpha := f.itemPID(t, ctx, model.KindTrack, "Alpha Song")

	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	w, err := zw.Create("Spotify Account Data/StreamingHistory_music_0.json")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := io.WriteString(w, `[
		{"endTime":"2026-01-02 03:04","artistName":"Fixture Artist","trackName":"Alpha Song","msPlayed":2000},
		{"endTime":"2026-01-03 07:08","artistName":"Unknown Artist","trackName":"Nowhere Song","msPlayed":1000}
	]`); err != nil {
		t.Fatal(err)
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	staged, err := f.svc.StageMigrationExport(ctx, f.uc, bytes.NewReader(buf.Bytes()), 0)
	if err != nil {
		t.Fatal(err)
	}
	if len(staged.Files) != 1 {
		t.Fatalf("staged files = %v, want the basic history", staged.Files)
	}

	sum := f.runMigration(t, ctx, MigrationRequest{
		Source: "spotify", ExportID: staged.PID,
		Stars: true, Ratings: true, History: true, Progress: true,
	})
	if sum.Listens != 1 || sum.Unmatched != 1 {
		t.Fatalf("summary = %+v, want one play and one miss", sum)
	}
	if st := f.playState(t, ctx, alpha); st.PlayCount != 1 {
		t.Fatalf("alpha play count = %d, want the imported play", st.PlayCount)
	}
	rows, err := f.svc.db.ListenLog(ctx, f.uc.ID, "", 0, 0, 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 1 || rows[0].StartedAt.UTC() != time.Date(2026, 1, 2, 3, 3, 58, 0, time.UTC) {
		t.Fatalf("listen rows = %+v, want the start derived from the stop time", rows)
	}
}

// The two refusals an upload can meet: a body over the cap, and a
// volume with no room for it. Both are decided here, and the handler
// maps them onto the 413 and 507 the contract declares.
func TestMigrationExportRefusals(t *testing.T) {
	ctx, f := newMigrateFixture(t)
	archive := spotifyExportZip(t)

	// The cap is a variable for exactly this: half a gigabyte of test
	// upload proves the same thing and costs a minute.
	was := migrateExportMaxBytes
	t.Cleanup(func() { migrateExportMaxBytes = was })
	migrateExportMaxBytes = int64(len(archive)) - 1
	if _, err := f.svc.StageMigrationExport(ctx, f.uc, bytes.NewReader(archive), 0); KindOf(err) != KindQuota {
		t.Fatalf("an over-cap body: kind = %v, want quota", KindOf(err))
	}
	// Declared as well as measured: a client that says how big the body
	// is is refused before a byte of it is read.
	if _, err := f.svc.StageMigrationExport(ctx, f.uc, bytes.NewReader(nil), int64(len(archive))); KindOf(err) != KindQuota {
		t.Fatalf("an over-cap content length: kind = %v, want quota", KindOf(err))
	}
	migrateExportMaxBytes = was

	f.svc.stagingFree = func(string) (int64, bool) { return 1 << 10, true }
	if _, err := f.svc.StageMigrationExport(ctx, f.uc, bytes.NewReader(archive), int64(len(archive))); KindOf(err) != KindStorageFull {
		t.Fatalf("a full volume: kind = %v, want storage-full", KindOf(err))
	}
	f.svc.stagingFree = nil

	// Administrators only, like every other surface in this file.
	acct, err := f.svc.CreateAccount(ctx, AccountCreate{Username: "member", Password: "correct-horse"})
	if err != nil {
		t.Fatal(err)
	}
	memberCtx, err := f.svc.UserCtx(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.StageMigrationExport(ctx, memberCtx, bytes.NewReader(archive), 0); KindOf(err) != KindForbidden {
		t.Fatalf("a non-admin upload: kind = %v, want forbidden", KindOf(err))
	}
}

// A staged export is swept once it expires, file and row together.
func TestMigrationExportSweep(t *testing.T) {
	t.Parallel()
	ctx, f := newMigrateFixture(t)
	archive := spotifyExportZip(t)
	staged, err := f.svc.StageMigrationExport(ctx, f.uc, bytes.NewReader(archive), 0)
	if err != nil {
		t.Fatal(err)
	}
	row, err := f.svc.db.MigrationExportByID(ctx, staged.PID)
	if err != nil {
		t.Fatal(err)
	}
	path := f.svc.migrationExportPath(row.FileName)
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("staged file: %v", err)
	}

	// Not yet: a sweep at the wrong moment would take an export
	// somebody is about to import from.
	f.svc.SweepMigrationExports(ctx)
	if _, err := f.svc.db.MigrationExportByID(ctx, staged.PID); err != nil {
		t.Fatalf("a live export was swept: %v", err)
	}

	row.ExpiresAtNS = time.Now().Add(-time.Minute).UnixNano()
	if err := f.svc.db.DeleteMigrationExport(ctx, row.ID); err != nil {
		t.Fatal(err)
	}
	if err := f.svc.db.InsertMigrationExport(ctx, row); err != nil {
		t.Fatal(err)
	}
	f.svc.SweepMigrationExports(ctx)
	if _, err := f.svc.db.MigrationExportByID(ctx, staged.PID); err == nil {
		t.Fatal("an expired export survived the sweep")
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatalf("the expired export's file survived: %v", err)
	}

	// An archive with no row behind it, which a crash between the write
	// and the insert leaves: half a gigabyte on the volume the databases
	// share, addressable by nothing.
	orphan := f.svc.migrationExportPath("mx-01JZX5N8QW3F4V9T2B7KD3M9R6.zip")
	if err := os.WriteFile(orphan, archive, 0o600); err != nil {
		t.Fatal(err)
	}
	inFlight := f.svc.migrationExportPath(".mx-something.zip.tmp123")
	if err := os.WriteFile(inFlight, []byte("uploading"), 0o600); err != nil {
		t.Fatal(err)
	}
	// A stage writes the archive and then the row that names it, so an
	// archive written moments ago is not yet evidence of anything.
	f.svc.SweepMigrationExports(ctx)
	if _, err := os.Stat(orphan); err != nil {
		t.Fatalf("the sweep took an archive a stage may still be placing: %v", err)
	}
	aged := time.Now().Add(-migrateExportOrphanGrace - time.Minute)
	if err := os.Chtimes(orphan, aged, aged); err != nil {
		t.Fatal(err)
	}
	f.svc.SweepMigrationExports(ctx)
	if _, err := os.Stat(orphan); !os.IsNotExist(err) {
		t.Fatalf("an orphaned archive survived the sweep: %v", err)
	}
	// And an upload still being written is not an orphan.
	if _, err := os.Stat(inFlight); err != nil {
		t.Fatalf("the sweep took an upload in flight: %v", err)
	}

	// Discarding one by hand does the same, and an id nothing names is
	// a not-found rather than a silent success.
	staged, err = f.svc.StageMigrationExport(ctx, f.uc, bytes.NewReader(archive), 0)
	if err != nil {
		t.Fatal(err)
	}
	if err := f.svc.DiscardMigrationExport(ctx, f.uc, staged.PID); err != nil {
		t.Fatal(err)
	}
	if err := f.svc.DiscardMigrationExport(ctx, f.uc, staged.PID); KindOf(err) != KindNotFound {
		t.Fatalf("discarding twice: kind = %v, want not-found", KindOf(err))
	}
}

// An import announces the items it wrote to, once each. A row and a
// device wake per play would have every client re-polling the sync
// delta continuously for as long as the import runs, and a history is
// the same few hundred tracks over and over.
func TestMigrateAnnouncesOncePerItem(t *testing.T) {
	t.Parallel()
	ctx, f := newMigrateFixture(t)
	ts := newFakeLastfm(t, "demo")
	if _, err := f.svc.LastfmConfigPut(ctx, f.uc, "test-key", "test-secret"); err != nil {
		t.Fatal(err)
	}
	f.svc.lastfmClient().BaseURL = ts.URL + "/2.0/"

	before, _, err := f.svc.db.EventsSince(ctx, f.uc.ID, 0, 1000)
	if err != nil {
		t.Fatal(err)
	}
	sum := f.runMigration(t, ctx, MigrationRequest{
		Source: "lastfm", Username: "demo",
		Stars: true, Ratings: true, History: true, Progress: true,
	})
	// Three plays of one track, which is one item to announce.
	if sum.Listens != 3 {
		t.Fatalf("summary = %+v, want the three scrobbles", sum)
	}
	after, _, err := f.svc.db.EventsSince(ctx, f.uc.ID, 0, 1000)
	if err != nil {
		t.Fatal(err)
	}
	// One per item, not one per play: three plays of one track announce
	// that track once. The loved track is a second item and announces
	// itself, which is a change of its own.
	seen := map[string]int{}
	for _, e := range after[len(before):] {
		if e.Kind == eventPlayState {
			seen[e.ItemPID]++
		}
	}
	for pid, n := range seen {
		if n != 1 {
			t.Fatalf("%s was announced %d times: %v", pid, n, seen)
		}
	}
	if len(seen) != 2 {
		t.Fatalf("announced %v, want the played track and the loved one", seen)
	}
}

// TestMigrateLastfmWalksByCountAndByRows pins both halves of how the
// walk decides it has reached the end, each of which used to stop it at
// the first page and report what landed as the whole history.
//
// Page one carries no @attr at all, so there is no count to go on and
// the row count has to say the page was full. Page two carries its
// count as a JSON number, which the service has shipped alongside the
// string form; read as zero, the row count would say "full, keep
// going" and the walk would ask for a page that is not there.
func TestMigrateLastfmWalksByCountAndByRows(t *testing.T) {
	ctx, f := newMigrateFixture(t)
	alpha := f.itemPID(t, ctx, model.KindTrack, "Alpha Song")

	prev := migrateLastfmPageSize
	migrateLastfmPageSize = 2
	t.Cleanup(func() { migrateLastfmPageSize = prev })

	scrobble := func(uts string) string {
		return `{"name":"Alpha Song","mbid":"","artist":{"#text":"Fixture Artist"},` +
			`"album":{"#text":"Fixture Album"},"date":{"uts":"` + uts + `"}}`
	}
	page1 := `{"track":[` + scrobble("1767411845") + `,` + scrobble("1767325445") + `]}`
	page2 := `{"track":[` + scrobble("1767239045") + `,` + scrobble("1767152645") +
		`],"@attr":{"totalPages":2,"page":"2"}}`
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		r.ParseForm()
		w.Header().Set("Content-Type", "application/json")
		switch {
		case r.Form.Get("method") != "user.getRecentTracks":
			fmt.Fprint(w, `{"lovedtracks":{"track":[],"@attr":{"totalPages":"1"}}}`)
		case r.Form.Get("page") == "1":
			fmt.Fprintf(w, `{"recenttracks":%s}`, page1)
		case r.Form.Get("page") == "2":
			fmt.Fprintf(w, `{"recenttracks":%s}`, page2)
		default:
			// Nothing here, so a walk that came this far stops rather
			// than running to the page cap; the complaint is the point.
			t.Errorf("the walk asked for page %s past the count the service gave", r.Form.Get("page"))
			fmt.Fprint(w, `{"recenttracks":{"track":[],"@attr":{"totalPages":2}}}`)
		}
	}))
	t.Cleanup(ts.Close)
	if _, err := f.svc.LastfmConfigPut(ctx, f.uc, "test-key", "test-secret"); err != nil {
		t.Fatal(err)
	}
	f.svc.lastfmClient().BaseURL = ts.URL + "/2.0/"

	sum := f.runMigration(t, ctx, MigrationRequest{
		Source: "lastfm", Username: "demo", History: true,
	})
	if sum.Listens != 4 {
		t.Fatalf("listens = %d, want all four across the two pages: %+v", sum.Listens, sum)
	}
	if st := f.playState(t, ctx, alpha); st.PlayCount != 4 {
		t.Fatalf("alpha play count = %d, want 4", st.PlayCount)
	}
}

// spotifyHistoryZip wraps one extended history file, for a test about
// what the rows in it mean rather than about the whole archive.
func spotifyHistoryZip(t *testing.T, rows string) []byte {
	t.Helper()
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	w, err := zw.Create("Spotify Account Data/Streaming_History_Audio_2026_1.json")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := io.WriteString(w, rows); err != nil {
		t.Fatal(err)
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

// TestMigrateSpotifySkipIsNotAPlay pins that a measured zero is the
// measurement. An account export is full of instant skips and failed
// starts, and reading those as "nothing recorded, so assume the whole
// track" makes every one of them a finished play: the count bumps, the
// played mark goes on, and the stored session says something that did
// not happen. The deterministic ids mean a corrected re-import cannot
// displace the rows either.
func TestMigrateSpotifySkipIsNotAPlay(t *testing.T) {
	t.Parallel()
	ctx, f := newMigrateFixture(t)
	alpha := f.itemPID(t, ctx, model.KindTrack, "Alpha Song")

	const row = `{"ts":"2026-02-0%dT10:00:00Z","ms_played":%d,
		"master_metadata_track_name":"Alpha Song",
		"master_metadata_album_artist_name":"Fixture Artist",
		"master_metadata_album_album_name":"Fixture Album"}`
	archive := spotifyHistoryZip(t, "["+
		fmt.Sprintf(row, 1, 2000)+","+
		fmt.Sprintf(row, 2, 0)+","+
		// Nothing an export ever holds, and the file is a user upload:
		// subtracted from the stop time, a negative dates the play in
		// the future and an enormous one overflows the duration.
		fmt.Sprintf(row, 3, -5)+"]")
	staged, err := f.svc.StageMigrationExport(ctx, f.uc, bytes.NewReader(archive), 0)
	if err != nil {
		t.Fatal(err)
	}

	sum := f.runMigration(t, ctx, MigrationRequest{
		Source: "spotify", ExportID: staged.PID, History: true, Stars: true,
	})
	if sum.Listens != 3 {
		t.Fatalf("listens = %d, want every play recorded: %+v", sum.Listens, sum)
	}
	// Recorded, all three; counted, only the one that was actually
	// listened to.
	if st := f.playState(t, ctx, alpha); st.PlayCount != 1 {
		t.Fatalf("play count = %d, want the one real play", st.PlayCount)
	}
	rows, err := f.svc.db.ListenLog(ctx, f.uc.ID, "", 0, 0, 10)
	if err != nil {
		t.Fatal(err)
	}
	for _, r := range rows {
		if r.StartedAt.After(time.Now()) {
			t.Fatalf("a play landed in the future: %v", r.StartedAt)
		}
	}
}

// TestMigrateSpotifyKeepsWhatItDidNotRead pins that the archive is the
// household's, not the run's. The per-file gate skips the library file
// on a run with stars turned off and every history file on one with
// history off, and deleting the upload afterwards destroyed a decade of
// listening the run was told to leave alone - recoverable only by
// asking Spotify for the export again.
func TestMigrateSpotifyKeepsWhatItDidNotRead(t *testing.T) {
	t.Parallel()
	ctx, f := newMigrateFixture(t)
	archive := spotifyExportZip(t)
	staged, err := f.svc.StageMigrationExport(ctx, f.uc, bytes.NewReader(archive), 0)
	if err != nil {
		t.Fatal(err)
	}

	f.runMigration(t, ctx, MigrationRequest{
		Source: "spotify", ExportID: staged.PID, History: true,
	})
	if _, err := f.svc.db.MigrationExportByID(ctx, staged.PID); err != nil {
		t.Fatalf("a run that read only the history destroyed the archive: %v", err)
	}
	// And the id stays on the finished task, because it still names
	// something: the screen that ordered the import let go of its own
	// copy as soon as the task was accepted.
	sum := f.runMigration(t, ctx, MigrationRequest{
		Source: "spotify", ExportID: staged.PID, Stars: true, History: true,
	})
	if sum.Stars != 1 {
		t.Fatalf("the second run read no saved tracks: %+v", sum)
	}
	if _, err := f.svc.db.MigrationExportByID(ctx, staged.PID); err == nil {
		t.Fatal("the run that read all of it kept the archive")
	}
}

// TestMigrationExportOutlivesAnUnrecordedCompletion pins that the
// upload is disposed of by the task, not by the importer.
//
// The archive used to go as the importer's last act, before the task's
// own terminal state reached disk. That write is a warning rather than
// an error, and an ordinary restart lands between the two just as
// easily: either left the next attempt opening a row that was already
// gone, so a successful import reported as permanently failed with the
// household's listening history deleted behind it.
func TestMigrationExportOutlivesAnUnrecordedCompletion(t *testing.T) {
	t.Parallel()
	ctx, f := newMigrateFixture(t)
	archive := spotifyExportZip(t)
	staged, err := f.svc.StageMigrationExport(ctx, f.uc, bytes.NewReader(archive), 0)
	if err != nil {
		t.Fatal(err)
	}
	req := MigrationRequest{
		Source: "spotify", ExportID: staged.PID, Stars: true, History: true,
	}
	dto, err := f.svc.StartMigration(ctx, f.uc, req)
	if err != nil {
		t.Fatal(err)
	}
	row, err := f.svc.db.ToolTaskByID(ctx, dto.ID)
	if err != nil {
		t.Fatal(err)
	}
	if err := f.svc.runMigrationTask(ctx, &row); err != nil {
		t.Fatal(err)
	}

	// The completion write never landed, so what is on disk is still a
	// task that has not finished. Settling reads that rather than the
	// caller's copy, and leaves everything where a retry needs it.
	f.svc.settleMigrationExport(ctx, row.ID)
	if _, err := f.svc.db.MigrationExportByID(ctx, staged.PID); err != nil {
		t.Fatalf("the archive went before the task's own completion did: %v", err)
	}

	// And once the completion is on disk, the upload goes with it.
	f.finishTask(t, ctx, row)
	if _, err := f.svc.db.MigrationExportByID(ctx, staged.PID); err == nil {
		t.Fatal("the archive outlived the import that read all of it")
	}
}

// TestMigrationExportIsReadByOneImportAtATime pins the claim. Two tasks
// naming one upload - a dry run queued beside the real import, or the
// same order submitted twice - would both open the archive, and the
// first to finish would take it away from the other. A claim left
// behind by a task that is no longer live is stale, which is what keeps
// a crashed import re-runnable rather than locked out until its day is
// up.
func TestMigrationExportIsReadByOneImportAtATime(t *testing.T) {
	t.Parallel()
	ctx, f := newMigrateFixture(t)
	archive := spotifyExportZip(t)
	staged, err := f.svc.StageMigrationExport(ctx, f.uc, bytes.NewReader(archive), 0)
	if err != nil {
		t.Fatal(err)
	}
	req := MigrationRequest{
		Source: "spotify", ExportID: staged.PID, Stars: true, History: true,
	}
	start := func() wdb.ToolTask {
		t.Helper()
		dto, err := f.svc.StartMigration(ctx, f.uc, req)
		if err != nil {
			t.Fatal(err)
		}
		row, err := f.svc.db.ToolTaskByID(ctx, dto.ID)
		if err != nil {
			t.Fatal(err)
		}
		return row
	}
	first, second := start(), start()

	if err := f.svc.runMigrationTask(ctx, &first); err != nil {
		t.Fatal(err)
	}
	// The first task is still live on disk, so the archive is its own.
	err = f.svc.runMigrationTask(ctx, &second)
	if err == nil || !strings.Contains(err.Error(), "another import is reading") {
		t.Fatalf("the second import = %v, want a refusal naming the first", err)
	}
	if !errors.Is(err, errToolPermanent) {
		t.Fatalf("the refusal is %v, want a permanent one: retrying cannot help", err)
	}

	// The process died with the first task's claim on the row: it is
	// over, so the claim is stale and the next import takes it.
	first.State = taskStateFailed
	first.FinishedAtNS = time.Now().UnixNano()
	if err := f.svc.db.UpdateToolTask(ctx, first); err != nil {
		t.Fatal(err)
	}
	if err := f.svc.runMigrationTask(ctx, &second); err != nil {
		t.Fatalf("the second import after the first was over: %v", err)
	}
}

// TestMigrateSpotifyReadsAnOlderExportNaming pins the two namings each
// package has had. An extended history requested before the rename is
// `endsong_0.json` and an older account-data one leaves the medium out
// of the middle; both hold the rows this import already reads, and both
// used to be refused at the upload as "nothing in that archive is an
// account export this server can read".
func TestMigrateSpotifyReadsAnOlderExportNaming(t *testing.T) {
	t.Parallel()
	ctx, f := newMigrateFixture(t)
	alpha := f.itemPID(t, ctx, model.KindTrack, "Alpha Song")

	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	add := func(name, body string) {
		t.Helper()
		w, err := zw.Create(name)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := io.WriteString(w, body); err != nil {
			t.Fatal(err)
		}
	}
	add("MyData/endsong_0.json", `[
		{"ts":"2026-02-01T10:00:00Z","ms_played":2000,
		 "master_metadata_track_name":"Alpha Song",
		 "master_metadata_album_artist_name":"Fixture Artist",
		 "master_metadata_album_album_name":"Fixture Album"}
	]`)
	// The basic package's older naming, which the extended one beside it
	// supersedes exactly as the newer pair do.
	add("MyData/StreamingHistory0.json", `[
		{"endTime":"2026-01-02 03:04","artistName":"Fixture Artist","trackName":"Alpha Song","msPlayed":2000}
	]`)
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}

	staged, err := f.svc.StageMigrationExport(ctx, f.uc, bytes.NewReader(buf.Bytes()), 0)
	if err != nil {
		t.Fatalf("an older export naming: %v", err)
	}
	if len(staged.Files) != 1 || !strings.HasSuffix(staged.Files[0], "endsong_0.json") {
		t.Fatalf("staged files = %v, want the extended history alone", staged.Files)
	}
	sum := f.runMigration(t, ctx, MigrationRequest{
		Source: "spotify", ExportID: staged.PID, History: true, Stars: true,
	})
	if sum.Listens != 1 {
		t.Fatalf("listens = %d, want the one play: %+v", sum.Listens, sum)
	}
	if st := f.playState(t, ctx, alpha); st.PlayCount != 1 {
		t.Fatalf("play count = %d, want 1", st.PlayCount)
	}
}

// TestMigrateSpotifyFailsOnAReadThatStopped pins that a history file
// which cannot be read to the end fails the run.
//
// json.Decoder.More answers false for a read that failed exactly as it
// does for a list that ended, so a loop that trusts it stops with a
// fraction of the plays and no error at all - and the run then reports
// success and deletes the only copy of the export. The read is stopped
// here by putting this import's own byte budget on the boundary between
// two rows, which is the one place the two are indistinguishable; a zip
// entry failing its checksum partway reaches the decoder the same way.
func TestMigrateSpotifyFailsOnAReadThatStopped(t *testing.T) {
	ctx, f := newMigrateFixture(t)
	const play = `{"ts":"2026-02-01T10:00:00Z","ms_played":1000,` +
		`"master_metadata_track_name":"Alpha Song",` +
		`"master_metadata_album_artist_name":"Fixture Artist"}`
	archive := spotifyHistoryZip(t, "["+play+","+play+","+play+"]")
	staged, err := f.svc.StageMigrationExport(ctx, f.uc, bytes.NewReader(archive), 0)
	if err != nil {
		t.Fatal(err)
	}
	prev := spotifyReadMaxBytes
	// Exactly the opening bracket and the first row: the decoder has a
	// complete value and an empty buffer, so the next thing it does is
	// ask the reader whether the list goes on.
	spotifyReadMaxBytes = int64(len("[" + play))
	t.Cleanup(func() { spotifyReadMaxBytes = prev })

	dto, err := f.svc.StartMigration(ctx, f.uc, MigrationRequest{
		Source: "spotify", ExportID: staged.PID, History: true, Stars: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	row, err := f.svc.db.ToolTaskByID(ctx, dto.ID)
	if err != nil {
		t.Fatal(err)
	}
	err = f.svc.runMigrationTask(ctx, &row)
	if err == nil {
		t.Fatal("a history that could not be read to the end reported success")
	}
	if strings.Contains(err.Error(), "not the shape this import reads") {
		t.Fatalf("failure = %v, want one naming the read rather than the file's shape", err)
	}
	// And the archive is still there, because a run that failed is not a
	// run that consumed it.
	f.svc.settleMigrationExport(ctx, row.ID)
	if _, err := f.svc.db.MigrationExportByID(ctx, staged.PID); err != nil {
		t.Fatalf("the archive went with the failed import: %v", err)
	}
}

// TestMigrateJellyfinWalksEveryPage pins that the walk does not stop at
// the first page when the server sends no total.
//
// TotalRecordCount is what the server says the query holds, and one
// that did not arrive decodes as zero - which after the first page read
// as "that was all of it". A forty-thousand-item library imported five
// hundred of them and reported success, with no error and nothing in
// the summary saying the rest had been skipped.
func TestMigrateJellyfinWalksEveryPage(t *testing.T) {
	ctx, f := newMigrateFixture(t)
	alpha := f.itemPID(t, ctx, model.KindTrack, "Alpha Song")
	bravo := f.itemPID(t, ctx, model.KindTrack, "Bravo Song")

	prev := jellyfinPageSize
	jellyfinPageSize = 1
	t.Cleanup(func() { jellyfinPageSize = prev })

	song := func(id, title string) string {
		return fmt.Sprintf(`{"Id":%q,"Name":%q,"Album":"Fixture Album",`+
			`"AlbumArtist":"Fixture Artist","Artists":["Fixture Artist"],`+
			`"RunTimeTicks":30000000,"ProviderIds":{},`+
			`"UserData":{"IsFavorite":true,"PlayCount":0}}`, id, title)
	}
	rows := []string{song("jf-1", "Alpha Song"), song("jf-2", "Bravo Song")}
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/Users":
			fmt.Fprint(w, `[{"Id":"jf-user","Name":"demo"}]`)
		case "/Items":
			q := r.URL.Query()
			if q.Get("SortBy") == "" {
				// Offset paging over a query with no order can answer
				// the same rows twice or skip one between requests.
				t.Error("the items walk pages by offset with no order")
			}
			start, _ := strconv.Atoi(q.Get("StartIndex"))
			limit, _ := strconv.Atoi(q.Get("Limit"))
			var out []string
			if q.Get("IncludeItemTypes") == "Audio" && q.Get("Filters") == "" {
				for i := start; i < len(rows) && len(out) < limit; i++ {
					out = append(out, rows[i])
				}
			}
			// No total at all, which is the case the walk has to survive.
			fmt.Fprintf(w, `{"Items":[%s]}`, strings.Join(out, ","))
		default:
			http.Error(w, "unknown path "+r.URL.Path, http.StatusNotFound)
		}
	}))
	t.Cleanup(ts.Close)

	sum := f.runMigration(t, ctx, MigrationRequest{
		Source: "jellyfin", ServerURL: ts.URL, Username: "demo",
		Token: "api-key", Stars: true,
	})
	if sum.Stars != 2 {
		t.Fatalf("stars = %d, want both pages walked: %+v", sum.Stars, sum)
	}
	for _, pid := range []string{alpha, bravo} {
		if st := f.playState(t, ctx, pid); !st.Starred {
			t.Fatalf("%s was not reached by the walk", pid)
		}
	}
}
