package api

import (
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/colespringer/waxbin/proxy"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// The check reads a planted drift, the repair is one task at a time that
// clears it and says so in its summary, and both are an administrator's.
func TestCatalogCheckAndRepair(t *testing.T) {
	t.Parallel()
	var dataDir string
	h := newHarnessWith(t, func(c *service.Config) { dataDir = c.DataDir })
	check := func() CatalogConsistency {
		t.Helper()
		return decodeStatus[CatalogConsistency](t, get(t, h.ts, "/api/v1/admin/catalog/consistency", h.token), 200, "check")
	}
	if c := check(); !c.Consistent || c.Reclaimable || c.SortKeyDrift != 0 {
		t.Fatalf("a fresh catalog's check = %+v, want it clean", c)
	}
	db, err := sql.Open("sqlite", "file:"+filepath.Join(dataDir, "waxbin.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	if _, err := db.Exec("UPDATE artist SET sort_key = 'zzzz stale'"); err != nil {
		t.Fatal(err)
	}
	if c := check(); c.Consistent || c.SortKeyDrift != 1 {
		t.Fatalf("the check after a planted key = %+v, want the one artist drifted", c)
	}

	task := decodeStatus[ToolTask](t, h.postJSON(t, "/api/v1/admin/catalog/repair", nil), 202, "repair")
	if task.Type != "catalog-repair" || task.State != "queued" {
		t.Fatalf("the repair = %+v, want a queued catalog-repair task", task)
	}
	refused := decodeStatus[Error](t, h.postJSON(t, "/api/v1/admin/catalog/repair", nil), 409, "second repair")
	if refused.Code != "conflict" || refused.Params == nil || (*refused.Params)["task"] != task.Id ||
		(*refused.Params)["reason"] != "task-running" {
		t.Fatalf("the second repair = %+v, want a conflict naming %s", refused, task.Id)
	}

	for h.svc.Tools.DrainLongToolTasks(context.Background()) {
	}
	done := decodeStatus[ToolTask](t, get(t, h.ts, "/api/v1/tools/tasks/"+task.Id, h.token), 200, "the repair task")
	if done.State != "done" || done.Summary == nil {
		t.Fatalf("the repair = %+v, want it done with a summary", done)
	}
	sum := *done.Summary
	after, _ := sum["after"].(map[string]any)
	if sum["sortKeysRewritten"] != float64(1) || after["consistent"] != true || after["sortKeyDrift"] != float64(0) {
		t.Fatalf("the repair's summary = %v, want the key rewritten and the check clean after", sum)
	}
	if c := check(); !c.Consistent || c.SortKeyDrift != 0 {
		t.Fatalf("the check after the repair = %+v, want it clean", c)
	}

	wantStatus(t, h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "listener", "password": "long-enough-pw",
	}), 201, "create a member")
	member := loginAs(t, h.ts, "listener", "long-enough-pw").Token
	wantStatus(t, get(t, h.ts, "/api/v1/admin/catalog/consistency", member), 403, "a member's check")
	wantStatus(t, reqAs(t, h, "POST", "/api/v1/admin/catalog/repair", member, nil), 403, "a member's repair")
}

// While the catalog is handed off, the check and the repair answer the
// maintenance 503, and the refused repair leaves no task behind.
func TestACatalogHandOffRefusesTheCheckAndTheRepair(t *testing.T) {
	t.Parallel()
	// Short, so the hand-off's socket fits beside the catalog.
	dataDir, err := os.MkdirTemp("", "wdrepair")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(dataDir) })
	h := newHarnessWith(t, func(c *service.Config) { c.DataDir = dataDir })
	ctx := context.Background()
	var c *proxy.Client
	for deadline := time.Now().Add(5 * time.Second); ; {
		if c, err = proxy.Dial(filepath.Join(dataDir, service.SocketFileName)); err == nil {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal(err)
		}
		time.Sleep(10 * time.Millisecond)
	}
	defer c.Close()
	if err := c.MaintenanceBegin(ctx); err != nil {
		t.Fatal(err)
	}
	check := get(t, h.ts, "/api/v1/admin/catalog/consistency", h.token)
	repair := h.postJSON(t, "/api/v1/admin/catalog/repair", nil)
	if err := c.MaintenanceEnd(ctx); err != nil {
		t.Fatal(err)
	}
	for what, resp := range map[string]*http.Response{"the check": check, "the repair": repair} {
		if e := decodeStatus[Error](t, resp, 503, what); e.Code != "catalog-maintenance" {
			t.Errorf("%s during a hand-off = %+v, want catalog-maintenance", what, e)
		}
	}
	for _, task := range decode[ToolTaskPage](t, get(t, h.ts, "/api/v1/tools/tasks", h.token)).Tasks {
		if task.Type == "catalog-repair" {
			t.Errorf("the refused repair left %+v", task)
		}
	}
}

// Every count lands in its own field on the wire.
func TestCatalogConsistencyWire(t *testing.T) {
	t.Parallel()
	raw, err := json.Marshal(catalogConsistencyJSON(service.CatalogConsistencyDTO{
		ItemsMissingFromSearch: 1, OrphanSearchRows: 2, ArtistRollupDrift: 3, GenreRollupDrift: 4,
		ReleaseGroupRollupDrift: 5, SortKeyDrift: 6, BookDurationDrift: 7, BookISBNKeyDrift: 8,
		AlbumYearDrift: 9, ReleaseYearDrift: 10, PlaylistPositionDrift: 11, OrphanArtSources: 12,
		OrphanThumbnails: 13, OrphanTagProvenance: 14, StrandedTagRows: 15, Reclaimable: true,
	}))
	if err != nil {
		t.Fatal(err)
	}
	var got map[string]any
	if err := json.Unmarshal(raw, &got); err != nil {
		t.Fatal(err)
	}
	want := map[string]any{
		"itemsMissingFromSearch": 1.0, "orphanSearchRows": 2.0, "artistRollupDrift": 3.0,
		"genreRollupDrift": 4.0, "releaseGroupRollupDrift": 5.0, "sortKeyDrift": 6.0,
		"bookDurationDrift": 7.0, "bookIsbnKeyDrift": 8.0, "albumYearDrift": 9.0,
		"releaseYearDrift": 10.0, "playlistPositionDrift": 11.0, "orphanArtSources": 12.0,
		"orphanThumbnails": 13.0, "orphanTagProvenance": 14.0, "strandedTagRows": 15.0,
		"consistent": false, "reclaimable": true,
	}
	if len(got) != len(want) {
		t.Fatalf("the wire form = %v, want %v", got, want)
	}
	for k, v := range want {
		if got[k] != v {
			t.Errorf("%s = %v, want %v", k, got[k], v)
		}
	}
	// A repair's summary carries the service's form as it is, so the two
	// spell every field alike.
	svcRaw, err := json.Marshal(service.CatalogConsistencyDTO{
		ItemsMissingFromSearch: 1, OrphanSearchRows: 2, ArtistRollupDrift: 3, GenreRollupDrift: 4,
		ReleaseGroupRollupDrift: 5, SortKeyDrift: 6, BookDurationDrift: 7, BookISBNKeyDrift: 8,
		AlbumYearDrift: 9, ReleaseYearDrift: 10, PlaylistPositionDrift: 11, OrphanArtSources: 12,
		OrphanThumbnails: 13, OrphanTagProvenance: 14, StrandedTagRows: 15, Reclaimable: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	var svcForm map[string]any
	if err := json.Unmarshal(svcRaw, &svcForm); err != nil {
		t.Fatal(err)
	}
	if !jsonEqual(svcForm, got) {
		t.Errorf("the service form %v, want the wire form %v", svcForm, got)
	}
}
