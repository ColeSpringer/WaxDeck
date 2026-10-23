package service

import (
	"path/filepath"
	"strings"
	"testing"
)

// The book tools find the root a file is under as the rest of the server
// does: the podcast folder is one, so a copy kept beside a file at its top
// stays inside it as in any library's; and a path is under a root, or
// shares a folder, only by the exact spelling.
func TestBookToolsFindAFilesRootAsTheServerDoes(t *testing.T) {
	t.Parallel()
	podcasts := filepath.Join(t.TempDir(), "Podcasts")
	_, svc, _ := openEnrichFixture(t, func(c *Config) { c.PodcastDir = podcasts })
	lib := svc.libraryRoots()[0]
	root := filepath.Clean(lib.Path)

	for _, top := range []string{root, podcasts} {
		book := filepath.Base(top)
		got := svc.splitFolder(filepath.Join(top, book+".m4b"), book, true)
		if want := filepath.Join(top, book+splitMark); got != want {
			t.Errorf("a kept split at the top of %s goes to %s, want %s", top, got, want)
		}
	}

	other := strings.ToUpper(root)
	if other == root {
		t.Fatalf("the root %s has no other spelling", root)
	}
	for path, want := range map[string]string{
		filepath.Join(root, "Author", "Book", "01.m4b"):  lib.Name,
		filepath.Join(podcasts, "Show", "episode.mp3"):   "",
		filepath.Join(other, "Author", "Book", "01.m4b"): "",
	} {
		if got := svc.libraryNameOf(path); got != want {
			t.Errorf("library of %s = %q, want %q", path, got, want)
		}
	}

	book := filepath.Join(root, "Author", "Book")
	discs := []string{filepath.Join(book, "CD1", "01.m4b"), filepath.Join(book, "CD2", "02.m4b")}
	if got := partsFolder(root, discs); got != book {
		t.Errorf("parts folder = %s, want the book's folder %s", got, book)
	}
	respelled := []string{discs[0], filepath.Join(other, "Author", "Book", "CD2", "02.m4b")}
	if got, want := partsFolder(root, respelled), filepath.Dir(discs[0]); got != want {
		t.Errorf("parts folder across two spellings of the root = %s, want the first part's %s", got, want)
	}
}
