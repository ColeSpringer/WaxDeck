package service

import (
	"context"
	"log/slog"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/colespringer/waxbin/model"
)

// libraryAt is the listing's entry for the library at path.
func libraryAt(t *testing.T, ctx context.Context, svc *Library, path string) LibraryInfo {
	t.Helper()
	libs, err := svc.Libraries(ctx)
	if err != nil {
		t.Fatal(err)
	}
	for _, lib := range libs {
		if lib.Path == path {
			return lib
		}
	}
	t.Fatalf("no library at %s", path)
	return LibraryInfo{}
}

// scanAndSettle runs a whole scan as a job and waits until the follower
// has taken its end in hand.
func scanAndSettle(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx) Job {
	t.Helper()
	waitFor(t, func() bool {
		running, err := svc.catalogJobRunning(ctx)
		return err == nil && !running
	}, "no catalog job running before the scan")
	job, err := svc.RescanFor(ctx, uc, false)
	if err != nil {
		t.Fatal(err)
	}
	_, pid, _ := parseAPIPID(job.PID)
	waitFor(t, func() bool {
		svc.jobs.mu.Lock()
		defer svc.jobs.mu.Unlock()
		_, running := svc.jobs.running[pid]
		j, err := svc.lib.Job(ctx, pid)
		return err == nil && j.State != model.JobRunning && !running
	}, "the scan to end")
	ended, err := svc.JobStatus(ctx, job.PID)
	if err != nil {
		t.Fatal(err)
	}
	return ended
}

// A library the server's configuration names lists as configured; one
// added in the console does not.
func TestALibraryListsWhetherTheConfigurationNamesIt(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	ctx, svc, uc, _ := openServiceAt(t, dataDir, nil)
	runtimeDir := t.TempDir()
	if _, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "runtime", Path: runtimeDir}); err != nil {
		t.Fatal(err)
	}
	if lib := libraryAt(t, ctx, svc, filepath.Join(dataDir, "configured")); !lib.Configured {
		t.Errorf("the configured root lists %+v, want configured", lib)
	}
	if lib := libraryAt(t, ctx, svc, runtimeDir); lib.Configured {
		t.Errorf("the console's root lists %+v, want it not configured", lib)
	}
}

// A root whose folder was not there at its scan lists as unreachable,
// the scan's job names it, and the log says so once however many scans
// find it gone. Once the folder is back the next scan clears it.
func TestAnUnreachableRootIsListedNamedAndLoggedOnce(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	gone := filepath.Join(dataDir, "unmounted")
	var logged lockedBuffer
	ctx, svc, uc, _ := openServiceAt(t, dataDir, func(c *Config) {
		c.Roots = append(c.Roots, Root{Name: "unmounted", Path: gone})
		c.Logger = slog.New(slog.NewTextHandler(&logged, nil))
	})
	const said = "library root is not reachable; its items stay listed and play once it is back"
	job := scanAndSettle(t, ctx, svc, uc)
	if job.Scan == nil || !slices.Equal(job.Scan.RootsUnreachable, []string{"unmounted"}) {
		t.Fatalf("the scan's job = %+v, want it naming unmounted unreachable", job.Scan)
	}
	waitFor(t, func() bool { return libraryAt(t, ctx, svc, gone).Unreachable }, "the root to list unreachable")
	if lib := libraryAt(t, ctx, svc, filepath.Join(dataDir, "configured")); lib.Unreachable {
		t.Errorf("the reachable root lists %+v, want it reachable", lib)
	}
	scanAndSettle(t, ctx, svc, uc)

	if err := os.Mkdir(gone, 0o755); err != nil {
		t.Fatal(err)
	}
	job = scanAndSettle(t, ctx, svc, uc)
	if len(job.Scan.RootsUnreachable) != 0 {
		t.Errorf("the scan after the folder came back names %v unreachable", job.Scan.RootsUnreachable)
	}
	waitFor(t, func() bool { return !libraryAt(t, ctx, svc, gone).Unreachable }, "the root to list reachable again")
	if n := strings.Count(logged.String(), said); n != 1 {
		t.Errorf("the log says the root is unreachable %d times, want once:\n%s", n, logged.String())
	}
	for _, line := range strings.Split(logged.String(), "\n") {
		if strings.Contains(line, said) && (!strings.Contains(line, "library=unmounted") || !strings.Contains(line, "path="+gone)) {
			t.Errorf("the line %q does not name the library and its path", line)
		}
	}
}

// What the last scan found stays known across a restart, which says so
// at start, before any scan runs.
func TestAnUnreachableRootIsKnownAfterARestart(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	gone := filepath.Join(dataDir, "unmounted")
	withGone := func(c *Config) { c.Roots = append(c.Roots, Root{Name: "unmounted", Path: gone}) }
	ctx, svc, uc, stop := openServiceAt(t, dataDir, withGone)
	scanAndSettle(t, ctx, svc, uc)
	stop()

	var logged lockedBuffer
	ctx, svc, _, _ = openServiceAt(t, dataDir, func(c *Config) {
		withGone(c)
		c.Logger = slog.New(slog.NewTextHandler(&logged, nil))
	})
	if lib := libraryAt(t, ctx, svc, gone); !lib.Unreachable {
		t.Errorf("after a restart the root lists %+v, want it unreachable", lib)
	}
	if n := strings.Count(logged.String(), "library root is not reachable"); n != 1 {
		t.Errorf("the start says the root is unreachable %d times, want once:\n%s", n, logged.String())
	}
}

// A managed root the server cannot write lists as not writable and the
// start warns of it once, however often the libraries are read again.
// A writable managed root and an in-place one list as writable.
func TestAnUnwritableManagedRootIsFlaggedAtBoot(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritableDirs(t)
	dataDir := t.TempDir()
	locked, open := filepath.Join(dataDir, "locked"), filepath.Join(dataDir, "open")
	for _, dir := range []string{locked, open} {
		if err := os.Mkdir(dir, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	chmodFor(t, locked, 0o555)
	var logged lockedBuffer
	ctx, svc, _, _ := openServiceAt(t, dataDir, func(c *Config) {
		c.Roots = append(c.Roots,
			Root{Name: "locked", Path: locked, Managed: true},
			Root{Name: "open", Path: open, Managed: true})
		c.Logger = slog.New(slog.NewTextHandler(&logged, nil))
	})
	const said = "a managed library root is not writable by the server; uploads, organize moves and deletes into it will fail"
	waitFor(t, func() bool {
		w := libraryAt(t, ctx, svc, locked).Writable
		return w != nil && !*w
	}, "the locked root to list not writable")
	svc.refreshLibraryState(ctx)
	waitFor(t, func() bool { return svc.rootProbe.idle() }, "the probe after a refresh")
	if n := strings.Count(logged.String(), said); n != 1 {
		t.Errorf("the log warns %d times, want once:\n%s", n, logged.String())
	}
	for _, line := range strings.Split(logged.String(), "\n") {
		if strings.Contains(line, said) && (!strings.Contains(line, "level=WARN") ||
			!strings.Contains(line, "library=locked") || !strings.Contains(line, "path="+locked) || !strings.Contains(line, "err=")) {
			t.Errorf("the warning %q does not name the library, path and error", line)
		}
	}
	if w := libraryAt(t, ctx, svc, open).Writable; w == nil || !*w {
		t.Errorf("the writable managed root lists writable %v, want true", w)
	}
	if w := libraryAt(t, ctx, svc, filepath.Join(dataDir, "configured")).Writable; w != nil {
		t.Errorf("the in-place root lists writable %v, want it unsaid", *w)
	}
	if entries, err := os.ReadDir(open); err != nil || len(entries) != 0 {
		t.Errorf("the probed root holds %v (%v), want the probe gone", entries, err)
	}
}
