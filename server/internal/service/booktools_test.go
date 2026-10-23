package service

import (
	"path/filepath"
	"testing"
)

// A book tool writes where the book is: into the book's own folder when
// one is named for it, else a folder named for what it writes beside the
// book's files; a copy beside a kept original gets a folder of its own,
// and nothing climbs out of the library.
func TestABookToolWritesBesideTheBook(t *testing.T) {
	t.Parallel()
	root := filepath.Join(string(filepath.Separator), "srv", "books")
	at := func(parts ...string) string { return filepath.Join(append([]string{root}, parts...)...) }
	for _, c := range []struct {
		name, dir, book, title, want string
	}{
		{"a split into the folder named for the book", at("Ada", "Tide"), "Tide", "Tide", at("Ada", "Tide")},
		{"a folder named for the book in another case", at("Ada", "tide"), "Tide", "Tide", at("Ada", "tide")},
		{"a split of a file loose in its author's folder", at("Ada"), "Tide", "Tide", at("Ada", "Tide")},
		{"a kept original's split beside its folder", at("Ada", "Tide"), "Tide", "Tide (Split)", at("Ada", "Tide (Split)")},
		{"a kept original's split beside a loose file", at("Ada"), "Tide", "Tide (Split)", at("Ada", "Tide (Split)")},
		{"a kept original's merge beside its folder", at("Ada", "Tide"), "Tide", "Tide (Merged)", at("Ada", "Tide (Merged)")},
		{"a book at the library's root stays inside it", root, "books", "books (Merged)", at("books (Merged)")},
		{"a title no folder may carry", at("Ada"), "Tide: A Story", "Tide: A Story", at("Ada", "Tide_ A Story")},
	} {
		if got := toolBookFolder(root, c.dir, c.book, c.title); got != c.want {
			t.Errorf("%s: folder = %s, want %s", c.name, got, c.want)
		}
	}
}

// A merge writes where its parts are: the folder holding them all, the
// book's own above its disc folders, and never above the library.
func TestAMergeWritesWhereItsPartsAre(t *testing.T) {
	t.Parallel()
	root := filepath.Join(string(filepath.Separator), "srv", "books")
	at := func(parts ...string) string { return filepath.Join(append([]string{root}, parts...)...) }
	for _, c := range []struct {
		name  string
		parts []string
		want  string
	}{
		{"one folder", []string{at("Ada", "Tide", "01.m4b"), at("Ada", "Tide", "02.m4b")}, at("Ada", "Tide")},
		{"disc folders", []string{at("Ada", "Tide", "CD1", "01.mp3"), at("Ada", "Tide", "CD2", "01.mp3")}, at("Ada", "Tide")},
		{"loose at the root", []string{at("01.mp3"), at("02.mp3")}, root},
		{"across libraries", []string{at("Ada", "01.mp3"), filepath.Join(string(filepath.Separator), "srv", "other", "02.mp3")}, at("Ada")},
	} {
		if got := partsFolder(root, c.parts); got != c.want {
			t.Errorf("%s: folder = %s, want %s", c.name, got, c.want)
		}
	}
}
