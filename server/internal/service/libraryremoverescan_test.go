package service

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/colespringer/waxbin/model"
)

// scansOf lists the catalog's scan jobs that walked the library.
func scansOf(t *testing.T, ctx context.Context, svc *Library, lib model.PID) []*model.Job {
	t.Helper()
	jobs, err := svc.lib.Jobs(ctx, 100)
	if err != nil {
		t.Fatal(err)
	}
	var out []*model.Job
	for _, j := range jobs {
		if j.Kind != "scan" || j.State == model.JobRunning || j.Result == "" {
			continue
		}
		var res struct {
			Runs []struct{ LibraryPID model.PID }
		}
		if json.Unmarshal([]byte(j.Result), &res) == nil && len(res.Runs) == 1 && res.Runs[0].LibraryPID == lib {
			out = append(out, j)
		}
	}
	return out
}

// A removal that stopped with the library still held may have let go of
// the files of the batches it ran: the library is scanned when its end is
// followed up, which takes them back.
func TestARemovalStoppedPartWayScansTheLibraryItLeft(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := openServiceAt(t, t.TempDir(), nil)
	dir := t.TempDir()
	spare, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "spare", Path: dir})
	if err != nil {
		t.Fatal(err)
	}
	_, bare, _ := parseAPIPID(spare.PID)
	waitFor(t, func() bool {
		running, err := svc.catalogJobRunning(ctx)
		return err == nil && !running
	}, "the create's scan to end")
	before := len(scansOf(t, ctx, svc, bare))
	failed := endedRemoval(t, ctx, svc, uc, spare, dir, model.JobFailed, nil)
	svc.settleJobOrigin(ctx, failed)
	waitFor(t, func() bool { return len(scansOf(t, ctx, svc, bare)) > before }, "a scan of the library the removal left")
}

// scanCount counts the catalog's scan jobs, running or ended.
func scanCount(t *testing.T, ctx context.Context, svc *Library) int {
	t.Helper()
	jobs, err := svc.lib.Jobs(ctx, 100)
	if err != nil {
		t.Fatal(err)
	}
	n := 0
	for _, j := range jobs {
		if j.Kind == "scan" {
			n++
		}
	}
	return n
}

// spareLibrary adds a library and waits out its create's scan.
func spareLibrary(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx) (LibraryInfo, string) {
	t.Helper()
	dir := t.TempDir()
	spare, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "spare", Path: dir})
	if err != nil {
		t.Fatal(err)
	}
	waitFor(t, func() bool {
		running, err := svc.catalogJobRunning(ctx)
		return err == nil && !running
	}, "the create's scan to end")
	return spare, dir
}

// A removal that stopped before it let go of any file leaves nothing for
// a scan to take back, so its end starts none; one that let go of files
// has them taken back.
func TestARemovalScansTheLibraryItLeftOnlyWhenItLetGoOfFiles(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		name     string
		detached int
		scans    bool
	}{
		{"nothing let go of", 0, false},
		{"files let go of", 3, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			ctx, svc, uc, _ := openServiceAt(t, t.TempDir(), nil)
			spare, dir := spareLibrary(t, ctx, svc, uc)
			before := scanCount(t, ctx, svc)
			failed := endedRemoval(t, ctx, svc, uc, spare, dir, model.JobFailed,
				&model.RemoveRootReport{Root: dir, FilesDetached: tc.detached})
			svc.settleJobOrigin(ctx, failed)
			if scanned := scanCount(t, ctx, svc) > before; scanned != tc.scans {
				t.Fatalf("scanned = %v, want %v", scanned, tc.scans)
			}
		})
	}
}

// A removal the last stop cut short is settled at this start, whose
// startup scan walks every library: the settle starts no scan of its own
// to race that one for the catalog. With no startup scan, the settle's is
// the one that takes the files back.
func TestARemovalTheLastStopCutShortIsLeftToTheStartupScan(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		name        string
		startupScan bool
		scans       bool
	}{
		{"a startup scan runs", true, false},
		{"no startup scan runs", false, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			ctx, svc, uc, _ := openServiceAt(t, t.TempDir(), nil)
			spare, dir := spareLibrary(t, ctx, svc, uc)
			svc.startupScan = tc.startupScan
			before := scanCount(t, ctx, svc)
			crashed := endedRemoval(t, ctx, svc, uc, spare, dir, model.JobCrashed, nil)
			crashed.FinishedAt = svc.openedAtNS - 1
			svc.settleJobOrigin(ctx, crashed)
			if scanned := scanCount(t, ctx, svc) > before; scanned != tc.scans {
				t.Fatalf("scanned = %v, want %v", scanned, tc.scans)
			}
		})
	}
}
