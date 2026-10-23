package service

import (
	"errors"
	"fmt"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"

	"github.com/colespringer/waxdeck/fixtures"
)

// toolBook writes one part of "Tool Book" by Tess Tool into dir.
func toolBook(t *testing.T, dir string, part int) {
	t.Helper()
	if _, err := fixtures.GenerateM4B(dir, fixtures.Spec{
		Name: fmt.Sprintf("part %d", part), Duration: time.Duration(2+part) * time.Second,
		Tags: map[string]string{"TITLE": fmt.Sprintf("Part %d", part), "ALBUM": "Tool Book",
			"ARTIST": "Tess Tool", "ALBUMARTIST": "Tess Tool", "TRACKNUMBER": fmt.Sprint(part)},
	}); err != nil {
		t.Fatal(err)
	}
}

// theToolBook answers the one book a fixture scanned, with its parts.
func theToolBook(t *testing.T, svc *Library) (model.PID, int) {
	t.Helper()
	ctx := t.Context()
	items, err := svc.lib.Query(ctx, query.New(query.EntityItems).Where("kind", query.OpIs, string(model.KindBook)).Build(), "")
	if err != nil || len(items) != 1 {
		t.Fatalf("books = %d (%v), want one", len(items), err)
	}
	bd, err := svc.lib.Book(ctx, items[0].PID)
	if err != nil {
		t.Fatal(err)
	}
	return items[0].PID, len(bd.Files)
}

// A tool's trash that some of a book's files refuse fails as no retry
// mends, saying which file stayed and why, with the rest in the trash
// under the tool's reason for the run to put back.
func TestAToolTrashThatLeavesAPartSaysWhichPartStayed(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritablePaths(t)
	var root string
	ctx, svc, _ := openEnrichFixture(t, func(c *Config) { root = c.Roots[0].Path })
	toolBook(t, filepath.Join(root, "Tool Book", "CD1"), 1)
	toolBook(t, filepath.Join(root, "Tool Book", "CD2"), 2)
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	book, parts := theToolBook(t, svc)
	if parts != 2 {
		t.Fatalf("parts = %d, want the two discs as one book", parts)
	}
	lockFolder(t, filepath.Join(root, "Tool Book", "CD2"))
	trashed, err := svc.trashToolFiles(ctx, partFiles(t, ctx, svc, book), taskTypeBookMerge)
	if KindOf(err) != KindStorageUnwritable || !errors.Is(err, errToolPermanent) || trashed != 1 {
		t.Fatalf("trash = %d, %v (kind %q), want one trashed and a permanent refusal", trashed, err, KindOf(err))
	}
	msg := err.Error()
	for _, want := range []string{"1 of 2 files", "Tool Book/CD2/part 2.m4b", "permission denied"} {
		if !strings.Contains(msg, want) {
			t.Errorf("message %q does not say %q", msg, want)
		}
	}
	if strings.Contains(msg, root) {
		t.Errorf("message %q names the server's folder", msg)
	}
	entries, err := svc.lib.Trash(ctx, false, 10)
	if err != nil || len(entries) != 1 || entries[0].Reason != taskTypeBookMerge {
		t.Fatalf("trash = %+v (%v), want the one part under book-merge", entries, err)
	}
}

// A merge of a book a part of which is in a read-only library is refused
// before it is queued.
func TestAMergeOfABookPartlyInAReadOnlyLibraryIsRefused(t *testing.T) {
	t.Parallel()
	var root, other string
	ctx, svc, uc := openEnrichFixture(t, func(c *Config) {
		root = c.Roots[0].Path
		other = t.TempDir()
		c.Roots = append(c.Roots, Root{Name: "other", Path: other})
	})
	toolBook(t, filepath.Join(root, "Tool Book"), 1)
	toolBook(t, filepath.Join(other, "Tool Book"), 2)
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	book, parts := theToolBook(t, svc)
	if parts != 2 {
		t.Skipf("the catalog keeps a book's parts in two libraries apart (%d parts)", parts)
	}
	libs, err := svc.lib.Libraries(ctx)
	if err != nil {
		t.Fatal(err)
	}
	for _, lib := range libs {
		if samePath(lib.DisplayRoot, other) {
			if _, err := svc.lib.SetLibraryReadOnly(ctx, lib.PID, true); err != nil {
				t.Fatal(err)
			}
		}
	}
	svc.SetFlowJobs(newFakeBookEngine(t))
	if _, err := svc.StartBookMerge(ctx, uc, apiPID(PrefixBook, book), nil, false); KindOf(err) != KindReadOnly {
		t.Fatalf("merge = %v (kind %q), want read-only", err, KindOf(err))
	}
	if tasks, _, err := svc.ListToolTasksFor(ctx, uc, "", 10); err != nil || len(tasks) != 0 {
		t.Fatalf("tasks = %+v (%v), want nothing queued", tasks, err)
	}
}

// A cue split whose rip the trash cannot take fails for good, saying the
// rip stays beside the tracks split from it.
func TestACueSplitWhoseRipStaysFailsSayingSo(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritablePaths(t)
	ctx, svc, uc := newCueFixture(t)
	one, _, _ := carvedTracks(t, ctx, svc, uc)
	seed, err := svc.getVisibleItem(ctx, uc, one)
	if err != nil {
		t.Fatal(err)
	}
	rip, _, err := svc.cueRip(ctx, seed)
	if err != nil {
		t.Fatal(err)
	}
	file, err := svc.lib.File(ctx, rip)
	if err != nil {
		t.Fatal(err)
	}
	lockFolder(t, filepath.Dir(string(file.Path)))
	err = svc.trashRip(ctx, rip)
	if !errors.Is(err, errToolPermanent) || KindOf(err) != KindStorageUnwritable ||
		!strings.Contains(err.Error(), "Rip Album.flac") || !strings.Contains(err.Error(), "the rip stays beside the tracks split from it") {
		t.Fatalf("trash of the rip = %v (kind %q), want a permanent refusal saying the rip stays", err, KindOf(err))
	}
	if entries, err := svc.lib.Trash(ctx, false, 10); err != nil || len(entries) != 0 {
		t.Fatalf("trash = %+v (%v), want nothing moved", entries, err)
	}
}
