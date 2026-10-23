package service

import (
	"path/filepath"
	"testing"

	"github.com/colespringer/waxbin"
)

// A book tool refused up front because the book's folder will not take a
// file has the managed roots probed again, as a refused upload or delete
// does: the libraries say so without waiting for the timer.
func TestARefusedBookToolProbesTheRootsAgain(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritablePaths(t)
	var root string
	ctx, svc, uc := openEnrichFixture(t, func(c *Config) {
		c.Roots[0].Managed = true
		root = c.Roots[0].Path
	})
	dir := filepath.Join(root, "Tess Tool", "Tool Book")
	for part := 1; part <= 2; part++ {
		toolBook(t, dir, part)
	}
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	book, parts := theToolBook(t, svc)
	if parts != 2 {
		t.Fatalf("parts = %d, want the two as one book", parts)
	}
	svc.SetFlowJobs(newFakeBookEngine(t))
	waitFor(t, svc.rootProbe.idle, "the boot probe pass to end")
	lockFolder(t, dir)
	passes := countProbePasses(svc)
	if _, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false); KindOf(err) != KindStorageUnwritable {
		t.Fatalf("merge = %v, want storage-unwritable", err)
	}
	waitFor(t, func() bool { return passes.Load() >= 1 }, "a probe pass after the refused merge")
}
