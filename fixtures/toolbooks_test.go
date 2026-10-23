package fixtures_test

import (
	"context"
	"path/filepath"
	"testing"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/config"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"

	"github.com/colespringer/waxdeck/fixtures"
)

// The tool books scan as two books, each alone in a folder named for it:
// what a book merge and a refused delete act on without touching any
// other fixture's folder.
func TestToolBooksScanAsTwoBooksInFoldersOfTheirOwn(t *testing.T) {
	ctx := context.Background()
	root := t.TempDir()
	dirs, err := fixtures.GenerateToolBooks(root)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{filepath.Join(root, "Tool Shelf", "The Merge Book"), filepath.Join(root, "Tool Shelf", "The Locked Book")}
	if len(dirs) != 2 || dirs[0] != want[0] || dirs[1] != want[1] {
		t.Fatalf("folders = %q, want %q", dirs, want)
	}
	lib, err := waxbin.Open(ctx, waxbin.Options{
		DBPath: filepath.Join(t.TempDir(), "catalog.db"),
		Roots:  []config.Root{{Path: root, Mode: model.ModeInPlace}},
	})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = lib.Close() })
	if _, err := lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	books, err := lib.Query(ctx, query.New(query.EntityItems).Where("kind", query.OpIs, "book").Build(), "")
	if err != nil {
		t.Fatal(err)
	}
	parts := map[string]int{}
	for _, b := range books {
		detail, err := lib.Book(ctx, b.PID)
		if err != nil {
			t.Fatal(err)
		}
		parts[b.Title] = len(detail.Files)
	}
	if len(parts) != 2 || parts["The Merge Book"] != 2 || parts["The Locked Book"] != 1 {
		t.Fatalf("books = %v, want The Merge Book in two parts and The Locked Book in one", parts)
	}
}
