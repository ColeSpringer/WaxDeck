package api

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"

	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// syncCatalog pulls one page of /sync/catalog with the given query.
func (h *harness) syncCatalog(t *testing.T, query string) (CatalogSyncPage, int) {
	t.Helper()
	resp := get(t, h.ts, "/api/v1/sync/catalog"+query, h.token)
	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		return CatalogSyncPage{}, mustErrStatus(t, resp.StatusCode, body)
	}
	return decode[CatalogSyncPage](t, resp), 200
}

func mustErrStatus(t *testing.T, status int, body []byte) int {
	t.Helper()
	var e Error
	if err := json.Unmarshal(body, &e); err != nil {
		t.Fatalf("non-200 response is not a structured error: %s", body)
	}
	return status
}

// mirror runs a full snapshot and returns the mirrored entries by pid
// plus the minted change cursor.
func (h *harness) mirror(t *testing.T, limit int) (map[string]ItemSummary, string) {
	t.Helper()
	items := make(map[string]ItemSummary)
	since := ""
	cursor := ""
	for {
		q := fmt.Sprintf("?limit=%d", limit)
		if cursor != "" {
			q += "&cursor=" + cursor
		}
		page, status := h.syncCatalog(t, q)
		if status != 200 {
			t.Fatalf("snapshot page status = %d", status)
		}
		if page.NextSince == "" {
			t.Fatal("snapshot page carries no nextSince")
		}
		if since == "" {
			since = page.NextSince
		} else if since != page.NextSince {
			t.Fatalf("snapshot pages disagree on nextSince: %q vs %q", since, page.NextSince)
		}
		for _, e := range page.Entries {
			if e.Op != "upsert" || e.Item == nil {
				t.Fatalf("snapshot entry op = %q item nil = %v, want hydrated upserts", e.Op, e.Item == nil)
			}
			items[e.Pid] = *e.Item
		}
		if page.NextCursor == nil {
			return items, since
		}
		cursor = *page.NextCursor
	}
}

// deleteReasons drains the delta from `since` and answers each
// tombstone's reason by pid. Read-only: it does not advance the caller's
// cursor, so the assertion and the mirror stay independent.
func (h *harness) deleteReasons(t *testing.T, since string) map[string]string {
	t.Helper()
	out := map[string]string{}
	for {
		page, status := h.syncCatalog(t, "?since="+since)
		if status != 200 {
			t.Fatalf("delta status = %d", status)
		}
		for _, e := range page.Entries {
			if e.Op != "delete" {
				continue
			}
			// Tombstones carry the track prefix whatever the item was, so
			// the map keys on the ULID's own pid form the caller holds.
			if e.Reason != nil {
				out[e.Pid] = *e.Reason
			}
		}
		since = page.NextSince
		if page.More == nil || !*page.More {
			return out
		}
	}
}

// applyDelta folds delta pages into the mirror until the stream is
// drained, returning the advanced cursor.
func (h *harness) applyDelta(t *testing.T, items map[string]ItemSummary, since string) string {
	t.Helper()
	for {
		page, status := h.syncCatalog(t, "?since="+since)
		if status != 200 {
			t.Fatalf("delta status = %d", status)
		}
		for _, e := range page.Entries {
			switch e.Op {
			case "upsert":
				items[e.Pid] = *e.Item
			case "delete":
				// Tombstones match on the ULID: the kind is unknowable
				// once an item is gone.
				ulid := e.Pid[strings.Index(e.Pid, "-")+1:]
				for pid := range items {
					if strings.HasSuffix(pid, ulid) {
						delete(items, pid)
					}
				}
			default:
				t.Fatalf("unknown delta op %q", e.Op)
			}
		}
		since = page.NextSince
		if page.More == nil || !*page.More {
			return since
		}
	}
}

func TestSyncCatalogMirror(t *testing.T) {
	h := newHarness(t)

	// Snapshot with a page size smaller than the library so paging is
	// exercised; every page repeats the same minted cursor.
	items, since := h.mirror(t, 3)
	if len(items) != 4 {
		t.Fatalf("mirrored %d items, want 4", len(items))
	}
	for pid, it := range items {
		if !strings.HasPrefix(pid, "tr-") || it.Title == "" || it.DurationMs == 0 {
			t.Fatalf("bad mirrored summary %q: %+v", pid, it)
		}
	}

	// A drained stream deltas to nothing.
	page, status := h.syncCatalog(t, "?since="+since)
	if status != 200 || len(page.Entries) != 0 {
		t.Fatalf("empty delta status = %d entries = %d", status, len(page.Entries))
	}
	since = page.NextSince

	// A new file appears in the library; the delta upserts it.
	if _, err := fixtures.Generate(h.library, fixtures.Spec{
		Name: "echo", Codec: fixtures.CodecFLAC, Duration: 4200 * time.Millisecond,
		Tags: map[string]string{"TITLE": "Echo Song", "ARTIST": "Fixture Artist", "ALBUM": "Fixture Album"},
	}); err != nil {
		t.Fatalf("generating new fixture: %v", err)
	}
	h.rescanAndWait(t)
	since = h.applyDelta(t, items, since)
	if len(items) != 5 {
		t.Fatalf("after add, mirror holds %d items, want 5", len(items))
	}
	var echoPID string
	for pid, it := range items {
		if it.Title == "Echo Song" {
			echoPID = pid
		}
	}
	if echoPID == "" {
		t.Fatal("Echo Song did not arrive through the delta")
	}

	// The file vanishes. The catalog marks the item missing rather than
	// deleting it (deletes come from trash and retention operations), so
	// the mirror keeps the row, exactly like the online item listing;
	// the mark still lands on the stream as an upsert.
	if err := os.Remove(filepath.Join(h.library, "echo.flac")); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	since = h.applyDelta(t, items, since)
	if _, alive := items[echoPID]; !alive {
		t.Fatal("missing-state item dropped from the mirror; only true deletions tombstone")
	}

	// Trashing is the state that does leave the mirror. Archiving emits
	// an update rather than a delete on the catalog stream, so without
	// ADR-0048's tombstone an offline client keeps a track the online
	// listing has already dropped.
	var doomed string
	for pid, it := range items {
		if it.Title == "Alpha Song" {
			doomed = pid
		}
	}
	if doomed == "" {
		t.Fatal("no Alpha Song in the mirror to trash")
	}
	resp := h.postJSON(t, "/api/v1/library/items/delete", map[string]any{
		"pids": []string{doomed}, "mode": "trash",
	})
	wantStatus(t, resp, 200, "delete to trash")
	trashed := h.deleteReasons(t, since)
	since = h.applyDelta(t, items, since)
	if _, alive := items[doomed]; alive {
		t.Fatal("trashed item survived in the mirror; archiving must tombstone")
	}
	// Hidden, not removed: the row goes and the bytes stay, because a
	// restore would otherwise cost the whole download again (ADR-0048).
	if got := trashed[doomed]; got != "hidden" {
		t.Fatalf("trash tombstone reason = %q, want hidden", got)
	}

	// And a client mirroring from scratch never hears about it at all:
	// the snapshot drops archived items rather than paying a delete per
	// trashed row for a mirror that never held one. h.mirror fails on any
	// entry that is not a hydrated upsert, which is that assertion.
	fresh, _ := h.mirror(t, 3)
	if _, there := fresh[doomed]; there {
		t.Fatal("a fresh snapshot carried the trashed item")
	}

	// A permanent delete is the other tombstone, and the one that lets a
	// client reclaim what it downloaded: this one cannot be taken back.
	// A different item, because the first is already archived and its
	// bytes are in the trash.
	var erased string
	for pid, it := range items {
		if it.Title == "Bravo Song" {
			erased = pid
		}
	}
	if erased == "" {
		t.Fatalf("no Bravo Song in the mirror to delete: %v", items)
	}
	resp = h.postJSON(t, "/api/v1/library/items/delete", map[string]any{
		"pids": []string{erased}, "mode": "permanent",
	})
	wantStatus(t, resp, 200, "permanent delete")
	reasons := h.deleteReasons(t, since)
	if got := reasons[erased]; got != "removed" {
		t.Fatalf("permanent-delete tombstone reason = %q, want removed", got)
	}

	// Parameter validation.
	resp = get(t, h.ts, "/api/v1/sync/catalog?since=notacursor", h.token)
	if resp.StatusCode != 400 {
		t.Fatalf("malformed cursor status = %d, want 400", resp.StatusCode)
	}
	resp.Body.Close()
	resp = get(t, h.ts, "/api/v1/sync/catalog?since="+since+"&cursor=abc", h.token)
	if resp.StatusCode != 400 {
		t.Fatalf("since+cursor status = %d, want 400", resp.StatusCode)
	}
	resp.Body.Close()
}

func TestSyncCatalogResetPaths(t *testing.T) {
	h := newHarness(t)
	_, since := h.mirror(t, 100)

	// Add a change so the log has rows past the mirror cursor, then
	// prune the log to almost nothing: the cursor falls below the floor.
	if _, err := fixtures.Generate(h.library, fixtures.Spec{
		Name: "foxtrot", Codec: fixtures.CodecMP3, Duration: 4700 * time.Millisecond,
		Tags: map[string]string{"TITLE": "Foxtrot Song", "ARTIST": "Fixture Artist", "ALBUM": "Fixture Album"},
	}); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	if _, err := h.svc.PruneCatalogChanges(context.Background(), 1); err != nil {
		t.Fatalf("pruning change log: %v", err)
	}

	resp := get(t, h.ts, "/api/v1/sync/catalog?since="+since, h.token)
	body, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != 410 {
		t.Fatalf("pruned-cursor status = %d, want 410 (body %s)", resp.StatusCode, body)
	}
	var e Error
	if json.Unmarshal(body, &e) != nil || e.Code != "sync-reset" {
		t.Fatalf("pruned-cursor error = %s, want sync-reset", body)
	}

	// The documented recovery: a fresh snapshot works and includes the
	// item whose change rows were pruned away.
	items, _ := h.mirror(t, 100)
	if len(items) != 5 {
		t.Fatalf("post-reset mirror holds %d items, want 5", len(items))
	}
}

func TestSyncCatalogGrantEpoch(t *testing.T) {
	h := newHarness(t)

	// A restricted user with access to the only library.
	libs := decode[Libraries](t, get(t, h.ts, "/api/v1/libraries", h.token))
	if len(libs.Libraries) != 1 {
		t.Fatalf("libraries = %d, want 1", len(libs.Libraries))
	}
	resp := h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "restricted", "password": "restricted-pass",
		"libraryAccess": map[string]any{"mode": "granted", "libraryPids": []string{libs.Libraries[0].Pid}},
	})
	if resp.StatusCode != 201 {
		t.Fatalf("create user status = %d", resp.StatusCode)
	}
	user := decode[UserAccount](t, resp)
	rToken := loginAs(t, h.ts, "restricted", "restricted-pass").Token

	rGet := func(path string) *http.Response { return get(t, h.ts, path, rToken) }
	snap := decode[CatalogSyncPage](t, rGet("/api/v1/sync/catalog?limit=100"))
	if len(snap.Entries) != 4 {
		t.Fatalf("restricted snapshot entries = %d, want 4", len(snap.Entries))
	}

	// The admin narrows the account's visibility: the outstanding
	// cursor answers sync-reset.
	resp = h.patchJSON(t, "/api/v1/users/"+user.Id, map[string]any{
		"libraryAccess": map[string]any{"mode": "granted", "libraryPids": []string{}},
	})
	if resp.StatusCode != 200 {
		t.Fatalf("narrow grants status = %d", resp.StatusCode)
	}
	resp.Body.Close()

	resp = rGet("/api/v1/sync/catalog?since=" + snap.NextSince)
	if resp.StatusCode != 410 {
		t.Fatalf("post-grant-change delta status = %d, want 410", resp.StatusCode)
	}
	resp.Body.Close()

	// And the re-snapshot reflects the new (empty) visibility.
	snap = decode[CatalogSyncPage](t, rGet("/api/v1/sync/catalog?limit=100"))
	if len(snap.Entries) != 0 {
		t.Fatalf("re-snapshot entries = %d, want 0", len(snap.Entries))
	}
}

// A change landing between two snapshot pages must fall inside the
// first delta: the change cursor is captured before the first page's
// read and repeated verbatim on every later page, so a moving feed
// tail can never swallow a mid-snapshot edit.
func TestSyncSnapshotFrozenCursor(t *testing.T) {
	h := newHarness(t)

	page1, status := h.syncCatalog(t, "?limit=3")
	if status != 200 {
		t.Fatalf("page 1 status = %d", status)
	}
	if page1.NextCursor == nil {
		t.Fatal("4 items at limit 3 should page")
	}

	// The catalog moves while the client is between pages.
	if _, err := fixtures.Generate(h.library, fixtures.Spec{
		Name: "golf", Codec: fixtures.CodecFLAC, Duration: 4400 * time.Millisecond,
		Tags: map[string]string{"TITLE": "Golf Song", "ARTIST": "Fixture Artist", "ALBUM": "Fixture Album"},
	}); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)

	page2, status := h.syncCatalog(t, "?limit=3&cursor="+*page1.NextCursor)
	if status != 200 {
		t.Fatalf("page 2 status = %d", status)
	}
	if page2.NextSince != page1.NextSince {
		t.Fatalf("page 2 nextSince %q != page 1 %q; later pages must repeat the frozen cursor",
			page2.NextSince, page1.NextSince)
	}

	// Wherever the pages left the mirror, the first delta from the
	// frozen cursor delivers the mid-snapshot addition.
	items := map[string]ItemSummary{}
	for _, e := range append(page1.Entries, page2.Entries...) {
		items[e.Pid] = *e.Item
	}
	h.applyDelta(t, items, page1.NextSince)
	found := false
	for _, it := range items {
		if it.Title == "Golf Song" {
			found = true
		}
	}
	if !found {
		t.Fatal("mid-snapshot change fell between the pages' cursors and never reached the mirror")
	}
}

// An item whose change leaves it outside a restricted caller's
// visibility tombstones on their delta instead of being silently
// skipped: skipping would strand a stale row in the offline mirror
// that the live listing hides. The transition here is a re-home: the
// file moves under a root the caller was never granted, which changes
// the item without touching their grants (so no epoch bump covers it).
func TestSyncDeltaInvisibleTombstone(t *testing.T) {
	lib2 := t.TempDir()
	h := newHarness(t, service.Root{Name: "lib2", Path: lib2})

	libs := decode[Libraries](t, get(t, h.ts, "/api/v1/libraries", h.token))
	var grantPID string
	for _, lib := range libs.Libraries {
		if lib.Name == "lib" {
			grantPID = lib.Pid
		}
	}
	if grantPID == "" {
		t.Fatalf("library named lib not in %+v", libs.Libraries)
	}
	resp := h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "scoped", "password": "scoped-pass",
		"libraryAccess": map[string]any{"mode": "granted", "libraryPids": []string{grantPID}},
	})
	if resp.StatusCode != 201 {
		t.Fatalf("create user status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	rToken := loginAs(t, h.ts, "scoped", "scoped-pass").Token

	snap := decode[CatalogSyncPage](t, get(t, h.ts, "/api/v1/sync/catalog?limit=100", rToken))
	var gonePID string
	for _, e := range snap.Entries {
		if e.Item != nil && e.Item.Title == "Alpha Song" {
			gonePID = e.Pid
		}
	}
	if gonePID == "" {
		t.Fatal("Alpha Song missing from the scoped snapshot")
	}

	// The move: same bytes, ungranted root.
	data, err := os.ReadFile(filepath.Join(h.library, "alpha.flac"))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(lib2, "alpha.flac"), data, 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(filepath.Join(h.library, "alpha.flac")); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)

	// The admin still sees the item; the scoped user's delta tombstones
	// it.
	if err := get(t, h.ts, "/api/v1/items/"+gonePID, h.token).Body.Close(); err != nil {
		t.Fatal(err)
	}
	delta := decode[CatalogSyncPage](t, get(t, h.ts, "/api/v1/sync/catalog?since="+snap.NextSince, rToken))
	tombstoned := false
	for _, e := range delta.Entries {
		if e.Pid == gonePID {
			if e.Op != "delete" {
				t.Fatalf("invisible transition surfaced as %q, want a delete tombstone", e.Op)
			}
			tombstoned = true
		}
	}
	if !tombstoned {
		t.Fatalf("visible-to-invisible transition emitted nothing (delta %+v); the mirror strands the stale row", delta.Entries)
	}
}

func TestSyncServerFlow(t *testing.T) {
	h := newHarness(t)
	items := h.items(t, "")
	pid := items.Items[0].Pid

	// Mint a cursor; the stream is empty from here.
	mint := decode[ServerSyncPage](t, get(t, h.ts, "/api/v1/sync/server", h.token))
	if len(mint.Events) != 0 || mint.NextSince == "" {
		t.Fatalf("mint = %+v, want no events and a cursor", mint)
	}

	// A star lands on the stream as a hydrated play-state event.
	resp := h.putJSON(t, "/api/v1/items/"+pid+"/star", map[string]any{"starred": true})
	if resp.StatusCode != 200 {
		t.Fatalf("star status = %d", resp.StatusCode)
	}
	resp.Body.Close()

	delta := decode[ServerSyncPage](t, get(t, h.ts, "/api/v1/sync/server?since="+mint.NextSince, h.token))
	if len(delta.Events) != 1 {
		t.Fatalf("events = %d, want 1", len(delta.Events))
	}
	ev := delta.Events[0]
	if ev.Kind != "play-state" || ev.Pid == nil || *ev.Pid != pid || ev.PlayState == nil || !ev.PlayState.Starred {
		t.Fatalf("event = %+v, want starred play-state for %s", ev, pid)
	}

	// Prefs changes ride the same stream.
	resp = h.putJSON(t, "/api/v1/users/me/prefs", map[string]any{"theme": "oled"})
	if resp.StatusCode != 200 {
		t.Fatalf("prefs status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	delta2 := decode[ServerSyncPage](t, get(t, h.ts, "/api/v1/sync/server?since="+delta.NextSince, h.token))
	if len(delta2.Events) != 1 || delta2.Events[0].Kind != "prefs" || delta2.Events[0].Prefs == nil {
		t.Fatalf("prefs delta = %+v", delta2.Events)
	}

	// Another user's activity never appears on this user's stream.
	resp = h.postJSON(t, "/api/v1/users", map[string]any{"username": "watcher", "password": "watcher-pass"})
	if resp.StatusCode != 201 {
		t.Fatalf("create user status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	wToken := loginAs(t, h.ts, "watcher", "watcher-pass").Token
	resp = putJSON(t, h.ts, "/api/v1/items/"+pid+"/star", wToken, map[string]any{"starred": true})
	if resp.StatusCode != 200 {
		t.Fatalf("watcher star status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	delta3 := decode[ServerSyncPage](t, get(t, h.ts, "/api/v1/sync/server?since="+delta2.NextSince, h.token))
	if len(delta3.Events) != 0 {
		t.Fatalf("saw another user's events: %+v", delta3.Events)
	}

	// A cursor from a different stream generation resets.
	forged := base64.RawURLEncoding.EncodeToString([]byte("s1|01WRONGGENWRONGGENWRONGGEN|0"))
	resp = get(t, h.ts, "/api/v1/sync/server?since="+forged, h.token)
	if resp.StatusCode != 410 {
		t.Fatalf("forged-generation status = %d, want 410", resp.StatusCode)
	}
	resp.Body.Close()
}

func TestOfflineReplayGuards(t *testing.T) {
	h := newHarness(t)
	items := h.items(t, "")
	pid := items.Items[0].Pid

	state := func() PlayState {
		return decode[PlayState](t, get(t, h.ts, "/api/v1/items/"+pid+"/play-state", h.token))
	}
	checkpoint := func(pos int64, rec *time.Time) {
		t.Helper()
		body := map[string]any{"positionMs": pos}
		if rec != nil {
			body["recordedAt"] = rec.UTC().Format(time.RFC3339Nano)
		}
		resp := h.putJSON(t, "/api/v1/items/"+pid+"/play-state", body)
		if resp.StatusCode != 204 {
			t.Fatalf("checkpoint status = %d", resp.StatusCode)
		}
		resp.Body.Close()
	}

	// Live checkpoint establishes the state and its stamp.
	checkpoint(5000, nil)
	if got := state().PositionMs; got != 5000 {
		t.Fatalf("position = %d, want 5000", got)
	}

	// A stale offline replay (recorded before the live write, nearer
	// position) is skipped: the live state wins.
	old := time.Now().Add(-time.Hour)
	checkpoint(2000, &old)
	if got := state().PositionMs; got != 5000 {
		t.Fatalf("stale replay applied: position = %d, want 5000", got)
	}

	// A further offline replay within the recency guard wins (music is
	// furthest-position).
	recent := time.Now().Add(-time.Minute)
	checkpoint(8000, &recent)
	if got := state().PositionMs; got != 8000 {
		t.Fatalf("further replay skipped: position = %d, want 8000", got)
	}

	// The applied older replay must not have rewound the stamp: a nearer
	// replay recorded after it but before the live write still loses. A
	// downgraded stamp would read this one as newest and apply it.
	between := time.Now().Add(-30 * time.Second)
	checkpoint(3000, &between)
	if got := state().PositionMs; got != 8000 {
		t.Fatalf("stamp rewound by applied replay: position = %d, want 8000", got)
	}

	// A further replay far past the guard loses to the recent state.
	checkpoint(9500, &old)
	if got := state().PositionMs; got != 8000 {
		t.Fatalf("ancient further replay applied: position = %d, want 8000", got)
	}

	// Star resurrection: star, unstar, then replay the old star. The
	// unstar's stamp wins and the star stays cleared.
	starAt := time.Now().Add(-30 * time.Minute)
	resp := h.putJSON(t, "/api/v1/items/"+pid+"/star", map[string]any{"starred": true})
	resp.Body.Close()
	resp = h.putJSON(t, "/api/v1/items/"+pid+"/star", map[string]any{"starred": false})
	resp.Body.Close()
	resp = h.putJSON(t, "/api/v1/items/"+pid+"/star",
		map[string]any{"starred": true, "recordedAt": starAt.UTC().Format(time.RFC3339Nano)})
	st := decode[PlayState](t, resp)
	if st.Starred {
		t.Fatal("stale offline star resurrected an undone star")
	}
}

func TestBatchPlayStates(t *testing.T) {
	h := newHarness(t)
	items := h.items(t, "")
	if len(items.Items) < 2 {
		t.Fatal("need two items")
	}
	touched, untouched := items.Items[0].Pid, items.Items[1].Pid
	resp := h.putJSON(t, "/api/v1/items/"+touched+"/star", map[string]any{"starred": true})
	resp.Body.Close()

	resp = h.postJSON(t, "/api/v1/play-states", map[string]any{"pids": []string{touched, untouched, "tr-01JZX5N8QW3F4V9T2B7KD3M9R6"}})
	if resp.StatusCode != 200 {
		t.Fatalf("batch status = %d", resp.StatusCode)
	}
	list := decode[PlayStateList](t, resp)
	if len(list.States) != 1 || list.States[0].Pid != touched || !list.States[0].Starred {
		t.Fatalf("batch states = %+v, want only the starred item", list.States)
	}
}

func TestDownloadOriginal(t *testing.T) {
	h := newHarness(t)
	items := h.items(t, "")
	var alpha ItemSummary
	for _, it := range items.Items {
		if it.Title == "Alpha Song" {
			alpha = it
		}
	}
	if alpha.Pid == "" {
		t.Fatal("no Alpha Song in the fixture library")
	}

	info := decode[DownloadInfo](t, get(t, h.ts, "/api/v1/items/"+alpha.Pid+"/download-info", h.token))
	if len(info.Files) != 1 {
		t.Fatalf("files = %d, want 1", len(info.Files))
	}
	f := info.Files[0]
	if f.MimeType != "audio/flac" || f.SizeBytes <= 0 || f.EssenceHash == "" || f.Etag == "" {
		t.Fatalf("bad download file: %+v", f)
	}
	if f.FileName != "alpha.flac" {
		t.Fatalf("fileName = %q, want alpha.flac", f.FileName)
	}
	if f.DurationMs == nil || *f.DurationMs != alpha.DurationMs {
		t.Fatalf("durationMs = %v, want the item's own %d", f.DurationMs, alpha.DurationMs)
	}
	if info.SpanStartMs != nil {
		t.Fatal("whole-file item carries a span")
	}

	// The full download: original bytes, strong validator, attachment.
	resp, err := http.Get(h.ts.URL + f.Url)
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != 200 || int64(len(body)) != f.SizeBytes {
		t.Fatalf("download status = %d size = %d, want 200 with %d bytes", resp.StatusCode, len(body), f.SizeBytes)
	}
	if got := resp.Header.Get("ETag"); got != `"`+f.Etag+`"` {
		t.Fatalf("ETag = %q, want %q", got, `"`+f.Etag+`"`)
	}
	if cd := resp.Header.Get("Content-Disposition"); !strings.Contains(cd, "attachment") || !strings.Contains(cd, "alpha.flac") {
		t.Fatalf("Content-Disposition = %q", cd)
	}
	onDisk, err := os.ReadFile(filepath.Join(h.library, "alpha.flac"))
	if err != nil {
		t.Fatal(err)
	}
	if string(body) != string(onDisk) {
		t.Fatal("downloaded bytes differ from the original file")
	}

	// Ranged resume.
	req, _ := http.NewRequest("GET", h.ts.URL+f.Url, nil)
	req.Header.Set("Range", "bytes=100-199")
	resp, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	part, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != 206 || len(part) != 100 || string(part) != string(onDisk[100:200]) {
		t.Fatalf("range status = %d len = %d", resp.StatusCode, len(part))
	}

	// A URL minted for different bytes answers the stale error.
	staleURL := strings.Replace(f.Url, "id="+f.Etag, "id=1-1", 1)
	if staleURL == f.Url {
		t.Fatalf("could not derive stale URL from %q", f.Url)
	}
	resp, err = http.Get(h.ts.URL + staleURL)
	if err != nil {
		t.Fatal(err)
	}
	staleBody, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != 410 || !strings.Contains(string(staleBody), "stream-stale") {
		t.Fatalf("stale download status = %d body = %s, want 410 stream-stale", resp.StatusCode, staleBody)
	}

	// A tampered token fails closed.
	resp, err = http.Get(h.ts.URL + strings.Replace(f.Url, "mt=", "mt=x", 1))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 401 {
		t.Fatalf("tampered token status = %d, want 401", resp.StatusCode)
	}
}

func TestAppPasswordLifecycle(t *testing.T) {
	h := newHarness(t)

	resp := h.postJSON(t, "/api/v1/users/me/app-passwords", map[string]any{"label": "Symfonium on Pixel"})
	if resp.StatusCode != 201 {
		t.Fatalf("create status = %d", resp.StatusCode)
	}
	created := decode[AppPasswordCreated](t, resp)
	if !strings.HasPrefix(created.Id, "ap-") || len(created.Secret) != 26 {
		t.Fatalf("created = %+v, want ap- id and a 26-char secret", created)
	}

	list := decode[AppPasswordList](t, get(t, h.ts, "/api/v1/users/me/app-passwords", h.token))
	if len(list.AppPasswords) != 1 || list.AppPasswords[0].Id != created.Id {
		t.Fatalf("list = %+v", list.AppPasswords)
	}

	// The secret round-trips through the verification paths the
	// Subsonic adapter will use.
	ctx := context.Background()
	if u, err := h.svc.VerifyAppPasswordKey(ctx, created.Secret); err != nil || u == nil {
		t.Fatalf("apiKey verify = (%v, %v), want the admin", u, err)
	}
	if u, _ := h.svc.VerifyAppPasswordKey(ctx, "WRONGWRONGWRONGWRONGWRONGW"); u != nil {
		t.Fatal("wrong apiKey verified")
	}

	resp = h.deleteReq(t, "/api/v1/users/me/app-passwords/"+created.Id)
	if resp.StatusCode != 204 {
		t.Fatalf("revoke status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	if u, _ := h.svc.VerifyAppPasswordKey(ctx, created.Secret); u != nil {
		t.Fatal("revoked app password still verifies")
	}
	resp = h.deleteReq(t, "/api/v1/users/me/app-passwords/"+created.Id)
	if resp.StatusCode != 404 {
		t.Fatalf("second revoke status = %d, want 404", resp.StatusCode)
	}
	resp.Body.Close()
}

func TestWebSocketInvalidations(t *testing.T) {
	h := newHarness(t)
	items := h.items(t, "")
	pid := items.Items[0].Pid

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	wsURL := "ws" + strings.TrimPrefix(h.ts.URL, "http") + "/api/v1/ws"
	conn, _, err := websocket.Dial(ctx, wsURL, &websocket.DialOptions{
		HTTPHeader: http.Header{"Authorization": []string{"Bearer " + h.token}},
	})
	if err != nil {
		t.Fatalf("dialing event channel: %v", err)
	}
	defer conn.Close(websocket.StatusNormalClosure, "")

	if err := conn.Write(ctx, websocket.MessageText, []byte(`{}`)); err != nil {
		t.Fatalf("subscribing: %v", err)
	}

	// waitFrame reads until the wanted frame arrives; frames for other
	// topics may interleave (the startup scan's catalog invalidation can
	// land after connect) and ordering across topics is not contractual.
	waitFrame := func(wantType, wantTopic string) {
		t.Helper()
		deadline := time.Now().Add(5 * time.Second)
		for time.Now().Before(deadline) {
			rctx, rcancel := context.WithDeadline(ctx, deadline)
			_, data, err := conn.Read(rctx)
			rcancel()
			if err != nil {
				t.Fatalf("waiting for %s/%s: %v", wantType, wantTopic, err)
			}
			var f struct{ Type, Topic string }
			if err := json.Unmarshal(data, &f); err != nil {
				t.Fatalf("frame %s: %v", data, err)
			}
			if f.Type == wantType && f.Topic == wantTopic {
				return
			}
		}
		t.Fatalf("no %s/%s frame arrived", wantType, wantTopic)
	}

	// A user-state mutation surfaces as a coalesced user invalidation.
	resp := h.putJSON(t, "/api/v1/items/"+pid+"/star", map[string]any{"starred": true})
	resp.Body.Close()
	waitFrame("invalidate", "user")

	// A catalog change surfaces on the catalog topic.
	if _, err := fixtures.Generate(h.library, fixtures.Spec{
		Name: "golf", Codec: fixtures.CodecFLAC, Duration: 5200 * time.Millisecond,
		Tags: map[string]string{"TITLE": "Golf Song", "ARTIST": "Fixture Artist", "ALBUM": "Fixture Album"},
	}); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	waitFrame("invalidate", "catalog")

	// An unauthenticated upgrade is refused before the handshake.
	if _, resp2, err := websocket.Dial(ctx, wsURL, nil); err == nil {
		t.Fatal("unauthenticated upgrade succeeded")
	} else if resp2 == nil || resp2.StatusCode != 401 {
		t.Fatalf("unauthenticated upgrade status = %v, want 401", resp2)
	}
}

// patchJSON and deleteReq round out the harness verbs.
func (h *harness) patchJSON(t *testing.T, path string, body any) *http.Response {
	t.Helper()
	raw, _ := json.Marshal(body)
	req, _ := http.NewRequest("PATCH", h.ts.URL+path, strings.NewReader(string(raw)))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+h.token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	return resp
}

func (h *harness) deleteReq(t *testing.T, path string) *http.Response {
	t.Helper()
	req, _ := http.NewRequest("DELETE", h.ts.URL+path, nil)
	req.Header.Set("Authorization", "Bearer "+h.token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	return resp
}

// A restricted caller gets the same tombstone reasons an administrator
// does, which is not free: archiving is what an item does when it loses
// its last file, so an archived view carries no path at all - and
// viewVisible answers false for every caller without AllLibraries the
// moment the path is empty. Decided in that order, every restricted
// caller took the visibility branch, every tombstone they saw said
// hidden, and the reclaim worked for administrators only.
func TestSyncCatalogTombstoneReasonsForARestrictedCaller(t *testing.T) {
	h := newHarness(t)

	libs := decode[Libraries](t, get(t, h.ts, "/api/v1/libraries", h.token))
	if len(libs.Libraries) != 1 {
		t.Fatalf("libraries = %d, want 1", len(libs.Libraries))
	}
	resp := h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "scoped", "password": "scoped-pass-123",
		"libraryAccess": map[string]any{
			"mode": "granted", "libraryPids": []string{libs.Libraries[0].Pid},
		},
	})
	if resp.StatusCode != 201 {
		t.Fatalf("create user status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	token := loginAs(t, h.ts, "scoped", "scoped-pass-123").Token

	snap := decode[CatalogSyncPage](t, get(t, h.ts, "/api/v1/sync/catalog?limit=100", token))
	mirrored := map[string]string{}
	for _, e := range snap.Entries {
		if e.Item != nil {
			mirrored[e.Item.Title] = e.Pid
		}
	}
	trashed, gone := mirrored["Alpha Song"], mirrored["Bravo Song"]
	if trashed == "" || gone == "" {
		t.Fatalf("restricted snapshot did not carry both fixtures: %v", mirrored)
	}

	// Both deletes run as the administrator; what is under test is what
	// the *restricted* caller's delta says about them.
	resp = h.postJSON(t, "/api/v1/library/items/delete", map[string]any{
		"pids": []string{trashed}, "mode": "trash",
	})
	wantStatus(t, resp, 200, "delete to trash")
	resp = h.postJSON(t, "/api/v1/library/items/delete", map[string]any{
		"pids": []string{gone}, "mode": "permanent",
	})
	wantStatus(t, resp, 200, "permanent delete")

	reasons := map[string]string{}
	since := snap.NextSince
	for {
		page := decode[CatalogSyncPage](t,
			get(t, h.ts, "/api/v1/sync/catalog?since="+since, token))
		for _, e := range page.Entries {
			if e.Op == "delete" && e.Reason != nil {
				reasons[e.Pid] = *e.Reason
			}
		}
		since = page.NextSince
		if page.More == nil || !*page.More {
			break
		}
	}
	if got := reasons[trashed]; got != "hidden" {
		t.Errorf("trash reason for a restricted caller = %q, want hidden", got)
	}
	if got := reasons[gone]; got != "removed" {
		t.Errorf("permanent-delete reason for a restricted caller = %q, want removed", got)
	}
}
