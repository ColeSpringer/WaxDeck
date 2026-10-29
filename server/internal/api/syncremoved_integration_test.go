package api

import (
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// removedAs asks which of pids the caller's token may drop the bytes for.
func (h *harness) removedAs(t *testing.T, token string, pids ...string) []string {
	t.Helper()
	resp := reqAs(t, h, "POST", "/api/v1/sync/catalog/removed", token, map[string]any{"pids": pids})
	return decodeStatus[RemovedItemList](t, resp, 200, "removed items").Pids
}

// A device that re-mirrors from a snapshot, which carries no tombstones,
// asks which of the items it holds bytes for are gone for good. The answer
// is the one the caller's own delta would have given the same items: a
// permanent delete is named, an item in the trash with its undo journal
// and one carried out of their sight are not, and a purge moves the
// trashed one across.
func TestSyncCatalogRemovedMatchesTheCallersDelta(t *testing.T) {
	t.Parallel()
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
	user := decodeStatus[UserAccount](t, h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "scoped", "password": "scoped-pass",
		"libraryAccess": map[string]any{"mode": "granted", "libraryPids": []string{grantPID}},
	}), 201, "create user")
	token := loginAs(t, h.ts, "scoped", "scoped-pass").Token

	snap := decode[CatalogSyncPage](t, get(t, h.ts, "/api/v1/sync/catalog?limit=100", token))
	pids := map[string]string{}
	for _, e := range snap.Entries {
		if e.Item != nil {
			pids[e.Item.Title] = e.Pid
		}
	}
	rehomed, trashed, erased, kept := pids["Alpha Song"], pids["Bravo Song"], pids["Charlie Song"], pids["Delta Song"]
	if rehomed == "" || trashed == "" || erased == "" || kept == "" {
		t.Fatalf("the scoped snapshot is missing a fixture: %v", pids)
	}

	// Everything below happens while the device is away.
	wantStatus(t, h.postJSON(t, "/api/v1/library/items/delete", map[string]any{
		"pids": []string{trashed}, "mode": "trash",
	}), 200, "delete to trash")
	wantStatus(t, h.postJSON(t, "/api/v1/library/items/delete", map[string]any{
		"pids": []string{erased}, "mode": "permanent",
	}), 200, "permanent delete")
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

	// What the caller's own delta says of each, as the rule to match.
	reasons := map[string]string{}
	since := snap.NextSince
	for {
		page := decode[CatalogSyncPage](t, get(t, h.ts, "/api/v1/sync/catalog?since="+since, token))
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
	for pid, want := range map[string]string{rehomed: "hidden", trashed: "hidden", erased: "removed"} {
		if reasons[pid] != want {
			t.Fatalf("the caller's delta reason for %s = %q, want %q (all: %v)", pid, reasons[pid], want, reasons)
		}
	}

	// A pid this catalog holds no row for may be another server's, so it
	// is not named.
	unknown := "tr-01JZX5N8QW3F4V9T2B7KD3M9R6"
	got := h.removedAs(t, token, kept, rehomed, trashed, erased, unknown, "al-"+strings.TrimPrefix(erased, "tr-"), "garbage")
	if want := []string{erased}; !slices.Equal(got, want) {
		t.Fatalf("named %v, want %v", got, want)
	}
	for _, pid := range []string{kept, rehomed, trashed, erased} {
		if named, removed := slices.Contains(got, pid), reasons[pid] == "removed"; named != removed {
			t.Errorf("%s: named = %v but the caller's delta reason is %q", pid, named, reasons[pid])
		}
	}
	// The administrator's answer is the same: the rule does not depend on
	// who asks.
	if admin := h.removedAs(t, h.token, kept, rehomed, trashed, erased); !slices.Equal(admin, []string{erased}) {
		t.Fatalf("the administrator was told %v, want only %s", admin, erased)
	}

	// Purging what sat in the trash is what makes it unrecoverable.
	ulid := trashed[strings.Index(trashed, "-")+1:]
	var trashID string
	for _, e := range decode[TrashList](t, get(t, h.ts, "/api/v1/admin/trash", h.token)).Entries {
		if e.ItemPid != nil && strings.HasSuffix(*e.ItemPid, ulid) {
			trashID = e.Id
		}
	}
	if trashID == "" {
		t.Fatalf("no trash entry for %s", trashed)
	}
	wantStatus(t, h.deleteReq(t, "/api/v1/admin/trash/"+trashID), 200, "purge the trash entry")
	if got := h.removedAs(t, token, kept, rehomed, trashed, erased); !slices.Equal(got, []string{trashed, erased}) {
		t.Fatalf("after the purge named %v, want %v", got, []string{trashed, erased})
	}

	// A grant narrowed to nothing retires the caller's cursors and leaves
	// their re-snapshot empty, yet every item is still there: nothing a
	// grant hid is named, and what was already gone still is.
	wantStatus(t, h.patchJSON(t, "/api/v1/users/"+user.Id, map[string]any{
		"libraryAccess": map[string]any{"mode": "granted", "libraryPids": []string{}},
	}), 200, "narrow the grants")
	if resnap := decode[CatalogSyncPage](t, get(t, h.ts, "/api/v1/sync/catalog?limit=100", token)); len(resnap.Entries) != 0 {
		t.Fatalf("the narrowed caller's snapshot holds %d entries, want 0", len(resnap.Entries))
	}
	if got := h.removedAs(t, token, kept, rehomed, trashed, erased); !slices.Equal(got, []string{trashed, erased}) {
		t.Fatalf("after the grants narrowed named %v, want %v", got, []string{trashed, erased})
	}
}

// The request is a page of pids: it is refused empty or past five hundred,
// refused unauthenticated, and answers a list even when nothing is named.
func TestSyncCatalogRemovedRequestShape(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	path := "/api/v1/sync/catalog/removed"

	wantStatus(t, reqAs(t, h, "POST", path, h.token, map[string]any{"pids": []string{}}), 400, "an empty list")
	wantStatus(t, reqAs(t, h, "POST", path, h.token, map[string]any{}), 400, "no list")
	tooMany := make([]string, 501)
	for i := range tooMany {
		tooMany[i] = "tr-01JZX5N8QW3F4V9T2B7KD3M9R6"
	}
	wantStatus(t, reqAs(t, h, "POST", path, h.token, map[string]any{"pids": tooMany}), 400, "501 pids")
	wantStatus(t, reqAs(t, h, "POST", path, "not-a-token", map[string]any{"pids": tooMany[:1]}), 401, "a bad token")

	item := h.items(t, "?mediaType=music").Items[0].Pid
	resp := reqAs(t, h, "POST", path, h.token, map[string]any{"pids": []string{item}})
	raw := decodeStatus[map[string]any](t, resp, 200, "an item still present")
	if list, ok := raw["pids"].([]any); !ok || len(list) != 0 {
		t.Fatalf("nothing named = %v, want an empty list", raw)
	}
}
