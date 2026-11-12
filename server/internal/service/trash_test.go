package service

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"

	"github.com/colespringer/waxdeck/fixtures"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// skipWithoutUnwritablePaths skips where a folder cannot be made
// unwritable to this process, so a refused write cannot be set up.
func skipWithoutUnwritablePaths(t *testing.T) {
	t.Helper()
	if runtime.GOOS == "windows" {
		t.Skip("windows os.Chmod cannot make a folder unwritable")
	}
	if os.Geteuid() == 0 {
		t.Skip("root ignores permissions, so the unwritable setup cannot fail")
	}
}

// lockFolder makes dir unwritable until the test ends.
func lockFolder(t *testing.T, dir string) {
	t.Helper()
	if err := os.Chmod(dir, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(dir, 0o755) })
}

// trashTrack is one scanned track of a deletion fixture.
type trashTrack struct {
	pid  string
	item model.PID
	path string
}

// newTrashFixture opens a managed library holding, for each album named,
// one track in a folder of its own under the root.
func newTrashFixture(t *testing.T, albums ...string) (context.Context, *Library, *UserCtx, string, map[string]trashTrack) {
	t.Helper()
	var root string
	ctx, svc, admin := openEnrichFixture(t, func(c *Config) {
		c.Roots[0].Managed = true
		root = c.Roots[0].Path
	})
	for i, album := range albums {
		if _, err := fixtures.Generate(filepath.Join(root, album), fixtures.Spec{
			Name: "track", Codec: fixtures.CodecFLAC, Duration: time.Duration(2+i) * time.Second,
			Tags: map[string]string{"TITLE": album + " Song", "ARTIST": "Trasher", "ALBUM": album, "TRACKNUMBER": "1"},
		}); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	items, err := svc.lib.Query(ctx, query.New(query.EntityItems).Build(), "")
	if err != nil || len(items) != len(albums) {
		t.Fatalf("items = %d (%v), want %d", len(items), err, len(albums))
	}
	out := map[string]trashTrack{}
	for _, it := range items {
		out[it.Album] = trashTrack{pid: apiPID(PrefixTrack, it.PID), item: it.PID, path: string(it.Path)}
	}
	return ctx, svc, admin, root, out
}

// auditDetails reads the detail of every audit row of one action, newest
// first.
func auditDetails(t *testing.T, ctx context.Context, svc *Library, action string) []map[string]any {
	t.Helper()
	rows, err := svc.db.ListAudit(ctx, wdb.AuditFilter{Action: action}, 0, 20)
	if err != nil {
		t.Fatal(err)
	}
	out := make([]map[string]any, 0, len(rows))
	for _, r := range rows {
		var d map[string]any
		if err := json.Unmarshal([]byte(r.Detail), &d); err != nil {
			t.Fatalf("audit detail %q: %v", r.Detail, err)
		}
		out = append(out, d)
	}
	return out
}

// A delete whose every move the filesystem refused answers that the
// library cannot be written, keeps the item, records nothing in the
// trash, and is audited as refused rather than as a delete.
func TestADeleteThatMovedNothingIsRefused(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritablePaths(t)
	for _, whole := range []bool{true, false} {
		ctx, svc, admin, root, tracks := newTrashFixture(t, "Locked")
		tr := tracks["Locked"]
		lockFolder(t, filepath.Join(root, "Locked"))
		var err error
		action := "items.delete-files"
		if whole {
			action = "items.delete"
			_, err = svc.Tools.DeleteItems(ctx, admin, []string{tr.pid}, "trash", false)
		} else {
			refs, ferr := svc.lib.ItemFiles(ctx, tr.item)
			if ferr != nil || len(refs) != 1 {
				t.Fatalf("files = %+v (%v)", refs, ferr)
			}
			_, err = svc.Tools.DeleteItemFiles(ctx, admin, tr.pid, []string{string(refs[0].FilePID)}, "trash", false)
		}
		if KindOf(err) != KindStorageUnwritable {
			t.Fatalf("whole %v: delete = %v (kind %q), want storage-unwritable", whole, err, KindOf(err))
		}
		if msg := err.Error(); !strings.Contains(msg, "permission denied") || strings.Contains(msg, root) {
			t.Errorf("whole %v: message %q, want the refusal in words and no server folder", whole, msg)
		}
		trashFileStillThere(t, tr.path, "the refused track")
		if refs, err := svc.lib.ItemFiles(ctx, tr.item); err != nil || len(refs) != 1 {
			t.Errorf("whole %v: files after the refusal = %+v (%v), want the track kept", whole, refs, err)
		}
		if entries, err := svc.lib.Trash(ctx, true, 10); err != nil || len(entries) != 0 {
			t.Errorf("whole %v: trash = %+v (%v), want nothing journaled", whole, entries, err)
		}
		if got := auditDetails(t, ctx, svc, action); len(got) != 0 {
			t.Errorf("whole %v: %s audited %v for a delete that moved nothing", whole, action, got)
		}
		refused := auditDetails(t, ctx, svc, action+".refused")
		if len(refused) != 1 || !strings.Contains(refused[0]["error"].(string), "permission denied") {
			t.Errorf("whole %v: %s.refused = %v, want the refusal recorded with its cause", whole, action, refused)
		}
	}
}

// A delete some of whose moves the filesystem refused answers what went,
// says per item what stayed and why, and audits both.
func TestADeleteReportsItsFailuresPerEntry(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritablePaths(t)
	ctx, svc, admin, root, tracks := newTrashFixture(t, "Open", "Locked")
	open, locked := tracks["Open"], tracks["Locked"]
	lockFolder(t, filepath.Join(root, "Locked"))
	res, err := svc.Tools.DeleteItems(ctx, admin, []string{open.pid, locked.pid}, "trash", false)
	if err != nil {
		t.Fatalf("a half-refused delete = %v, want what went answered", err)
	}
	if !res.Applied || res.Trashed != 1 || res.Failed != 1 || res.Deleted != 0 {
		t.Fatalf("result = applied %v trashed %d failed %d deleted %d, want 1 trashed and 1 failed",
			res.Applied, res.Trashed, res.Failed, res.Deleted)
	}
	byPID := map[string]DeletePlanDTO{}
	for _, e := range res.Entries {
		byPID[e.PID] = e
	}
	if e := byPID[open.pid]; e.Files != 1 || e.Failed != 0 || e.ItemSurvives {
		t.Errorf("the trashed item's entry = %+v, want its one file gone", e)
	}
	e, ok := byPID[locked.pid]
	if !ok || e.Files != 0 || e.Failed != 1 || !e.ItemSurvives || !strings.Contains(e.Error, "permission denied") ||
		strings.Contains(e.Error, root) {
		t.Errorf("the refused item's entry = %+v (present %v), want one failed file, why, and the item kept", e, ok)
	}
	trashFileStillThere(t, locked.path, "the refused track")
	got := auditDetails(t, ctx, svc, "items.delete")
	if len(got) != 1 {
		t.Fatalf("items.delete audits = %v, want one", got)
	}
	failures, _ := got[0]["failures"].([]any)
	if got[0]["trashed"] != float64(1) || got[0]["failed"] != float64(1) || len(failures) != 1 {
		t.Fatalf("audit detail = %v, want 1 trashed, 1 failed and the failure named", got[0])
	}
	if f := failures[0].(map[string]any); f["pid"] != locked.pid || !strings.Contains(f["reason"].(string), "permission denied") {
		t.Errorf("audited failure = %v, want the refused track and why", f)
	}
}

// The plan says where each file is, relative to its library, so two
// files of one name read apart; it never names a server folder.
func TestADeletePlanNamesItsFiles(t *testing.T) {
	t.Parallel()
	ctx, svc, admin, root, tracks := newTrashFixture(t, "First", "Second")
	plan, err := svc.Tools.DeleteItems(ctx, admin, []string{tracks["First"].pid, tracks["Second"].pid}, "trash", true)
	if err != nil {
		t.Fatal(err)
	}
	if plan.Applied || plan.Trashed != 0 || plan.Failed != 0 {
		t.Fatalf("plan = %+v, want a dry run with no counts", plan)
	}
	want := map[string]string{tracks["First"].pid: "First/track.flac", tracks["Second"].pid: "Second/track.flac"}
	for _, e := range plan.Entries {
		if len(e.Paths) != 1 || e.Paths[0] != want[e.PID] || len(e.FileList) != 1 {
			t.Errorf("entry %s paths = %q, want [%s] beside its one file", e.PID, e.Paths, want[e.PID])
		}
		for _, p := range e.Paths {
			if filepath.IsAbs(p) || strings.Contains(p, root) {
				t.Errorf("path %q names the server's folder", p)
			}
		}
	}
}

// A delete that moved nothing for a reason other than a refused write
// is the server's failure, said without the server's folders.
func TestADeleteThatFailedOtherwiseIsInternal(t *testing.T) {
	t.Parallel()
	ctx, svc, admin, root, tracks := newTrashFixture(t, "Vanishing")
	tr := tracks["Vanishing"]
	svc.Tools.deleteApplyHook = func(context.Context) {
		if err := os.Remove(tr.path); err != nil {
			t.Error(err)
		}
	}
	_, err := svc.Tools.DeleteItems(ctx, admin, []string{tr.pid}, "trash", false)
	if KindOf(err) != KindInternal {
		t.Fatalf("delete of a vanished file = %v (kind %q), want internal", err, KindOf(err))
	}
	var se *Error
	if !errors.As(err, &se) || !strings.HasPrefix(se.Msg, "the delete failed: ") || strings.Contains(se.Msg, root) ||
		!strings.Contains(se.Msg, "no such file") {
		t.Fatalf("message = %q, want the cause in words and no server folder", err)
	}
	if refused := auditDetails(t, ctx, svc, "items.delete.refused"); len(refused) != 1 {
		t.Errorf("items.delete.refused = %v, want the failed delete recorded", refused)
	}
}

// The trash names each file by its place in its library, as the contract
// says, never by the server's folders.
func TestTrashEntriesNameFilesWithinTheirLibrary(t *testing.T) {
	t.Parallel()
	ctx, svc, admin, root, tracks := newTrashFixture(t, "Shelf")
	if _, err := svc.Tools.DeleteItems(ctx, admin, []string{tracks["Shelf"].pid}, "trash", false); err != nil {
		t.Fatal(err)
	}
	entries, err := svc.Tools.TrashEntries(ctx, admin, false, 10)
	if err != nil || len(entries) != 1 {
		t.Fatalf("trash = %+v (%v), want the one file", entries, err)
	}
	if got := entries[0].Name; got != "Shelf/track.flac" || strings.Contains(got, root) {
		t.Fatalf("trash entry name = %q, want Shelf/track.flac", got)
	}
}

// coverInTrash reports whether a file named cover.jpg sits anywhere in a
// library's trash.
func coverInTrash(t *testing.T, root string) bool {
	t.Helper()
	found := false
	err := filepath.WalkDir(filepath.Join(root, model.TrashDirName), func(path string, d os.DirEntry, err error) error {
		if err == nil && !d.IsDir() && d.Name() == "cover.jpg" {
			found = true
		}
		return err
	})
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		t.Fatal(err)
	}
	return found
}

// Deleting a managed folder's last track prunes the folder and counts
// it. Its cover is the folder's, not a sidecar of the track: trashed in
// a trash delete, gone in a permanent one.
func TestADeleteOfAFoldersLastTrackPrunesTheFolder(t *testing.T) {
	t.Parallel()
	for _, mode := range []string{"trash", "permanent"} {
		ctx, svc, admin, root, tracks := newTrashFixture(t, "Words")
		pid := tracks["Words"].pid
		folder := filepath.Join(root, "Words")
		touchSidecarFiles(t, folder, "cover.jpg")

		plan, err := svc.Tools.DeleteItems(ctx, admin, []string{pid}, mode, true)
		if err != nil {
			t.Fatal(err)
		}
		if got := sidecarsAcross(plan); len(got) != 0 {
			t.Errorf("%s plan sidecars = %q, want none: the cover belongs to the folder", mode, got)
		}
		res, err := svc.Tools.DeleteItems(ctx, admin, []string{pid}, mode, false)
		if err != nil {
			t.Fatal(err)
		}
		if res.DirsPruned != 1 {
			t.Errorf("%s delete pruned %d folders, want the one it emptied", mode, res.DirsPruned)
		}
		if got := sidecarsAcross(res); len(got) != 0 {
			t.Errorf("%s delete sidecars = %q, want none: the cover belongs to the folder", mode, got)
		}
		if _, err := os.Stat(folder); !errors.Is(err, os.ErrNotExist) {
			t.Errorf("%s delete left the emptied folder (%v)", mode, err)
		}
		if kept := coverInTrash(t, root); kept != (mode == "trash") {
			t.Errorf("%s delete left the cover in the trash = %v", mode, kept)
		}
	}
}

// An in-place library's folder companions are the user's: the track goes
// and the folder, with its cover, stays.
func TestADeleteInAnInPlaceLibraryKeepsTheFolder(t *testing.T) {
	t.Parallel()
	var root string
	ctx, svc, admin := openEnrichFixture(t, func(c *Config) { root = c.Roots[0].Path })
	folder := filepath.Join(root, "Words")
	if _, err := fixtures.Generate(folder, fixtures.Spec{
		Name: "track", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
		Tags: map[string]string{"TITLE": "Words Song", "ARTIST": "Trasher", "ALBUM": "Words", "TRACKNUMBER": "1"},
	}); err != nil {
		t.Fatal(err)
	}
	touchSidecarFiles(t, folder, "cover.jpg")
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	res, err := svc.Tools.DeleteItems(ctx, admin, []string{itemPIDByTitle(t, ctx, svc, admin, "Words Song")}, "trash", false)
	if err != nil || res.Trashed != 1 || res.DirsPruned != 0 {
		t.Fatalf("delete = %+v (%v), want the track trashed and no folder pruned", res, err)
	}
	trashFileStillThere(t, filepath.Join(folder, "cover.jpg"), "the in-place folder's cover")
	if _, err := os.Stat(filepath.Join(folder, "track.flac")); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("the deleted track is still in its folder (%v)", err)
	}
}
