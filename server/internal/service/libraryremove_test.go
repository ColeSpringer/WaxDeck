package service

import (
	"context"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/podcast"
	"github.com/colespringer/waxdeck/fixtures"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// removalAudit is the library.remove entry for the library, nil while
// there is none.
func removalAudit(t *testing.T, ctx context.Context, svc *Library, apiLibraryPID string) *AuditEventDTO {
	t.Helper()
	page, err := svc.AuditEvents(ctx, wdb.AuditFilter{Action: "library.remove"}, "", 50)
	if err != nil {
		t.Fatal(err)
	}
	for _, e := range page.Events {
		if e.TargetPID == apiLibraryPID {
			return &e
		}
	}
	return nil
}

// memberCtx makes an account granted only the libraries named.
func memberCtx(t *testing.T, ctx context.Context, svc *Library, name string, libraryPIDs ...string) *UserCtx {
	t.Helper()
	acct, err := svc.CreateAccount(ctx, AccountCreate{
		Username: name, Password: "long-enough-pw", AccessMode: "granted", LibraryPIDs: libraryPIDs,
	})
	if err != nil {
		t.Fatal(err)
	}
	uc, err := svc.UserCtx(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	return uc
}

// Removing a library takes it out of the catalog and every place WaxDeck
// keeps it: its stored name, the grants naming it, the bridge's mount and
// what the bridge refused of it. Its files stay, the removal is audited
// under whoever asked with what it did, and they hear it ended.
func TestRemoveLibraryDetachesAndUnmountsTheBridge(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	ctx, svc, uc, _ := openServiceAt(t, dataDir, nil)
	flow := &fakeFlowRoots{names: []string{"configured"}}
	svc.SetFlowRoots(flow)
	books := t.TempDir()
	tracks, err := fixtures.Generate(books, fixtures.Spec{
		Name: "kept", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
		Tags: map[string]string{"TITLE": "Kept On Disk", "ARTIST": "Remover"},
	})
	if err != nil {
		t.Fatal(err)
	}
	lib, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "books", Path: books})
	if err != nil {
		t.Fatal(err)
	}
	configured := libraryAt(t, ctx, svc, filepath.Join(dataDir, "configured")).PID
	member := memberCtx(t, ctx, svc, "member", configured, lib.PID)
	invite, err := svc.CreateInvite(ctx, uc, InviteCreate{AccessMode: "granted", LibraryPIDs: []string{lib.PID}})
	if err != nil {
		t.Fatal(err)
	}
	svc.flowSyncMu.Lock()
	svc.flowRefused = map[string]flowRefusal{"books": {path: books}}
	svc.flowSyncMu.Unlock()
	waitFor(t, func() bool {
		running, err := svc.catalogJobRunning(ctx)
		return err == nil && !running
	}, "the create's scan to end")

	job, err := svc.RemoveLibrary(ctx, uc, lib.PID)
	if err != nil {
		t.Fatalf("RemoveLibrary: %v", err)
	}
	if job.Kind != "remove-root" || job.Target == nil || job.Target.Type != "library" || job.Target.PID != lib.PID {
		t.Fatalf("job = %+v, want a remove-root job on %s", job, lib.PID)
	}
	waitFor(t, func() bool { return removalAudit(t, ctx, svc, lib.PID) != nil }, "the removal audited")

	audit := removalAudit(t, ctx, svc, lib.PID)
	if audit.ActorID != uc.ID || audit.TargetName != "books" || audit.Detail["name"] != "books" || audit.Detail["path"] != books ||
		audit.Detail["filesDetached"] != float64(1) || audit.Detail["itemsArchived"] != float64(1) || audit.Detail["trashRowsDropped"] != float64(0) {
		t.Errorf("audit = %+v, want books removed by %s with one file detached and one item archived", audit, uc.ID)
	}
	libs, err := svc.Libraries(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if slices.ContainsFunc(libs, func(l LibraryInfo) bool { return l.PID == lib.PID }) {
		t.Errorf("libraries = %+v, want books gone", libs)
	}
	if stored, err := svc.db.LibraryRootsList(ctx); err != nil || slices.ContainsFunc(stored, func(r wdb.LibraryRoot) bool { return r.Name == "books" }) {
		t.Errorf("stored names = %+v (%v), want books' gone", stored, err)
	}
	flow.mu.Lock()
	removed, names := slices.Clone(flow.removed), slices.Clone(flow.names)
	flow.mu.Unlock()
	if !slices.Equal(removed, []string{"books"}) || slices.Contains(names, "books") {
		t.Errorf("the bridge removed %v and maps %v, want books unmounted", removed, names)
	}
	svc.flowSyncMu.Lock()
	_, refused := svc.flowRefused["books"]
	svc.flowSyncMu.Unlock()
	if refused {
		t.Error("the bridge's refusal of books is still remembered")
	}
	if acct, err := svc.Account(ctx, member.ID); err != nil || !slices.Equal(acct.LibraryPIDs, []string{configured}) {
		t.Errorf("the member's grants = %v (%v), want only %s", acct.LibraryPIDs, err, configured)
	}
	invites, err := svc.Invites(ctx)
	if err != nil {
		t.Fatal(err)
	}
	for _, iv := range invites {
		if iv.ID == invite.ID && len(iv.LibraryPIDs) != 0 {
			t.Errorf("the invite still grants %v", iv.LibraryPIDs)
		}
	}
	if _, err := os.Stat(tracks[0]); err != nil {
		t.Errorf("the library's file is gone from disk: %v", err)
	}

	ended, err := svc.JobStatus(ctx, job.PID)
	if err != nil {
		t.Fatal(err)
	}
	if ended.State != string(model.JobDone) || ended.Target == nil || ended.Target.Name != "books" ||
		ended.RemoveRoot == nil || ended.RemoveRoot.FilesDetached != 1 || ended.RemoveRoot.ItemsArchived != 1 {
		t.Errorf("the ended job = %+v (target %+v, tally %+v), want books' removal done with its counts", ended, ended.Target, ended.RemoveRoot)
	}
	waitFor(t, func() bool {
		page, err := svc.Notifications(ctx, uc, "", 20)
		if err != nil {
			return false
		}
		return slices.ContainsFunc(page.Notifications, func(n InboxNotification) bool {
			return n.TargetPID == job.PID && n.Title == "Library removed" && strings.Contains(n.Body, "books")
		})
	}, "the starter told the removal ended")
}

// A removal the CLI starts is followed up all the same, with no account
// to name.
func TestARemovalStartedElsewhereIsFollowedUp(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := openServiceAt(t, t.TempDir(), nil)
	flow := &fakeFlowRoots{names: []string{"configured"}}
	svc.SetFlowRoots(flow)
	lib, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "stray", Path: t.TempDir()})
	if err != nil {
		t.Fatal(err)
	}
	_, bare, _ := parseAPIPID(lib.PID)
	waitFor(t, func() bool {
		running, err := svc.catalogJobRunning(ctx)
		return err == nil && !running
	}, "the create's scan to end")
	if _, err := svc.lib.StartRemoveRoot(ctx, bare, waxbin.RemoveRootOptions{}); err != nil {
		t.Fatal(err)
	}
	waitFor(t, func() bool { return removalAudit(t, ctx, svc, lib.PID) != nil }, "the removal audited")
	if audit := removalAudit(t, ctx, svc, lib.PID); audit.ActorID != "" || audit.TargetName != "stray" {
		t.Errorf("audit = %+v, want stray with no actor", audit)
	}
	flow.mu.Lock()
	defer flow.mu.Unlock()
	if !slices.Equal(flow.removed, []string{"stray"}) {
		t.Errorf("the bridge removed %v, want stray", flow.removed)
	}
}

// A root the server's configuration names comes back at every start, so
// the console refuses it and says where it is removed instead.
func TestRemovingAConfiguredLibraryIsRefused(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	ctx, svc, uc, _ := openServiceAt(t, dataDir, nil)
	configured := libraryAt(t, ctx, svc, filepath.Join(dataDir, "configured")).PID
	_, err := svc.RemoveLibrary(ctx, uc, configured)
	if KindOf(err) != KindConflict || err.Error() !=
		"this library is configured in WAXDECK_LIBRARY_ROOTS; take it out of the configuration and restart, then remove it here" {
		t.Fatalf("removing the configured root = %v, want it refused for the configuration", err)
	}
	jobs, err := svc.lib.Jobs(ctx, 20)
	if err != nil {
		t.Fatal(err)
	}
	if slices.ContainsFunc(jobs, func(j *model.Job) bool { return j.Kind == "remove-root" }) {
		t.Error("a refused removal started a job")
	}
}

// The podcast library follows the podcast folder and is not removed.
func TestRemovingThePodcastLibraryIsRefused(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := openServiceAt(t, t.TempDir(), func(c *Config) { c.PodcastDir = t.TempDir() })
	show, err := svc.lib.Podcasts().AddManual(ctx, "Show", podcast.ManualOptions{})
	if err != nil {
		t.Fatal(err)
	}
	ep, err := svc.lib.Podcasts().AddEpisode(ctx, show.PID, model.FeedEpisode{GUID: "one", Title: "One"}, false)
	if err != nil {
		t.Fatal(err)
	}
	_, _ = svc.lib.Podcasts().ImportEpisodeFile(ctx, ep.EpisodePID, filepath.Join(t.TempDir(), "absent.mp3"), true)
	libs, err := svc.lib.Libraries(ctx)
	if err != nil {
		t.Fatal(err)
	}
	var pid model.PID
	for _, lib := range libs {
		if lib.Mode == model.ModePodcast {
			pid = lib.PID
		}
	}
	if pid == "" {
		t.Fatal("no podcast library")
	}
	_, err = svc.RemoveLibrary(ctx, uc, apiPID(PrefixLibrary, pid))
	if KindOf(err) != KindInvalid || !strings.Contains(err.Error(), "podcast") {
		t.Fatalf("removing the podcast library = %v, want it refused", err)
	}
}

// Removal is an administrator's, refused while the server is read-only,
// and a pid that names no library is not found.
func TestRemovingALibraryNeedsAnAdministratorAndAWritableServer(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := openServiceAt(t, t.TempDir(), nil)
	lib, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "spare", Path: t.TempDir()})
	if err != nil {
		t.Fatal(err)
	}
	member := memberCtx(t, ctx, svc, "member", lib.PID)
	if _, err := svc.RemoveLibrary(ctx, member, lib.PID); KindOf(err) != KindForbidden {
		t.Errorf("a member removing = %v, want forbidden", err)
	}
	for _, pid := range []string{"lb-" + string(model.NewPID()), "tr-" + string(model.NewPID()), "nonsense"} {
		if _, err := svc.RemoveLibrary(ctx, uc, pid); KindOf(err) != KindNotFound {
			t.Errorf("removing %s = %v, want not found", pid, err)
		}
	}
	st, err := svc.AdminSettingsGet(ctx)
	if err != nil {
		t.Fatal(err)
	}
	st.ReadOnly = true
	if _, err := svc.AdminSettingsPut(ctx, uc, st); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.RemoveLibrary(ctx, uc, lib.PID); KindOf(err) != KindReadOnly {
		t.Errorf("removing on a read-only server = %v, want read-only", err)
	}
}

// An ended removal stays in the jobs list; a later start, which keeps
// nothing of the library it took out, names it from the removal's audit
// row.
func TestAnEndedRemovalIsNamedAfterARestart(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	ctx, svc, uc, stop := openServiceAt(t, dataDir, nil)
	dir := t.TempDir()
	lib, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "spare", Path: dir})
	if err != nil {
		t.Fatal(err)
	}
	waitFor(t, func() bool {
		running, err := svc.catalogJobRunning(ctx)
		return err == nil && !running
	}, "the create's scan to end")
	job, err := svc.RemoveLibrary(ctx, uc, lib.PID)
	if err != nil {
		t.Fatal(err)
	}
	waitFor(t, func() bool { return removalAudit(t, ctx, svc, lib.PID) != nil }, "the removal audited")
	stop()

	ctx, svc, uc, _ = openServiceAt(t, dataDir, nil)
	jobs, err := svc.Jobs(ctx, uc, 20)
	if err != nil {
		t.Fatal(err)
	}
	i := slices.IndexFunc(jobs, func(j Job) bool { return j.PID == job.PID })
	if i < 0 {
		t.Fatalf("jobs = %+v, want the ended removal listed", jobs)
	}
	if got := jobs[i].Target; got == nil || got.PID != lib.PID || got.Name != "spare" {
		t.Errorf("target = %+v, want %s named spare", got, lib.PID)
	}
}
