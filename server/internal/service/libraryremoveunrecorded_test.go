package service

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"slices"
	"sync/atomic"
	"testing"

	"github.com/colespringer/waxbin"
)

// killedFlowRoots is a bridge whose removal never returns: the server is
// killed while the sidecar reloads, which ends the follow-up where it
// stands.
type killedFlowRoots struct {
	fakeFlowRoots
	asked atomic.Bool
}

func (f *killedFlowRoots) RemoveRoot(context.Context, string) error {
	f.asked.Store(true)
	panic("the server is killed here")
}

// A removal no origin records, the CLI's, keeps one with what it knows of
// the library before its follow-up drops anything: killed part way, the
// follow-up is done at the next start, under the library's own name
// rather than its folder's.
func TestAnUnrecordedRemovalKilledMidFollowUpIsDoneAtTheNextStart(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	ctx, svc, uc, stop := openServiceAt(t, dataDir, nil)
	killed := &killedFlowRoots{fakeFlowRoots: fakeFlowRoots{names: []string{"configured"}}}
	svc.SetFlowRoots(killed)
	folder := filepath.Join(t.TempDir(), "shelf")
	if err := os.MkdirAll(folder, 0o755); err != nil {
		t.Fatal(err)
	}
	lib, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "books", Path: folder})
	if err != nil {
		t.Fatal(err)
	}
	_, bare, _ := parseAPIPID(lib.PID)
	waitFor(t, func() bool {
		running, err := svc.catalogJobRunning(ctx)
		return err == nil && !running
	}, "the create's scan to end")
	job, err := svc.lib.StartRemoveRoot(ctx, bare, waxbin.RemoveRootOptions{})
	if err != nil {
		t.Fatal(err)
	}
	waitFor(t, killed.asked.Load, "the follow-up to reach the bridge")
	o, err := svc.db.JobOriginGet(ctx, string(job))
	if err != nil {
		t.Fatalf("the removal's origin = %v, want one kept while its follow-up runs", err)
	}
	var facts removalFacts
	if err := json.Unmarshal([]byte(o.Detail), &facts); err != nil || facts.Name != "books" || facts.Path != folder {
		t.Fatalf("the origin's facts = %q (%v), want books at %s", o.Detail, err, folder)
	}
	stop()

	ctx, svc, _, _ = openServiceAt(t, dataDir, nil)
	fresh := &fakeFlowRoots{names: []string{"configured", "books"}}
	svc.SetFlowRoots(fresh)
	waitFor(t, func() bool { return slices.Equal(fresh.removedNames(), []string{"books"}) },
		"the next start's bridge to let go of books")
	waitFor(t, func() bool { return removalAudit(t, ctx, svc, lib.PID) != nil }, "the removal audited")
	if audit := removalAudit(t, ctx, svc, lib.PID); audit.TargetName != "books" || audit.ActorID != "" {
		t.Errorf("audit = %+v, want books with no actor", audit)
	}
}
