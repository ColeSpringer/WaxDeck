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

// Canned Navidrome songs. Alpha matches the fixture catalog and
// carries an MBID plus play history; Bravo matches by descriptive
// metadata alone; Charlie appears only as a bookmark entry; Nowhere
// matches nothing local.
const (
	navSongAlpha   = `{"id":"s-alpha","title":"Alpha Song","artist":"Fixture Artist","album":"Fixture Album","duration":2,"playCount":3,"played":"2026-01-02T03:04:05.000Z","musicBrainzId":"5f2ab3d1-6f70-4d67-9028-53144d5f2f9c"}`
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
// starred song, and one bookmark, everything in the standard envelope.
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
			writeSubsonic(w, `"starred2":{"song":[`+navSongAlpha+`],"album":[],"artist":[]}`, true)
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

	// Re-running rewrites the same positions without error.
	again := f.runMigration(t, ctx, req)
	if again.Matched != 2 || again.Progress != 2 {
		t.Fatalf("re-run summary = %+v", again)
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
