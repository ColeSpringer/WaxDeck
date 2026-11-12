package service

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
)

// toolBookFolder is the folder a book tool writes title's files into,
// for a book named book whose files are in dir, in the library rooted at
// root: dir itself when it is named for the book and title is that name,
// else a folder named for title in the folder that holds the book's - the
// parent of a folder named for the book, or dir itself - which keeps a
// marked copy out of the original's folder and never leaves the library.
func toolBookFolder(root, dir, book, title string) string {
	home := dir
	if !samePath(dir, root) && strings.EqualFold(filepath.Base(dir), safeFileName(book)) {
		if strings.EqualFold(filepath.Base(dir), safeFileName(title)) {
			return dir
		}
		home = filepath.Dir(dir)
	}
	return filepath.Join(home, safeFileName(title))
}

// partsFolder is the deepest folder holding every part of a book, in the
// library rooted at root: the book's own folder above disc folders. Parts
// that share no folder inside the library answer the first part's.
func partsFolder(root string, parts []string) string {
	first := filepath.Dir(parts[0])
	if root == "" {
		root = first
	}
	dir := first
	for _, p := range parts[1:] {
		for !pathsOverlap(dir, p) {
			if samePath(dir, root) || dir == filepath.Dir(dir) {
				return first
			}
			dir = filepath.Dir(dir)
		}
	}
	return dir
}

// libraryNameOf is the name of the library holding path, or "".
func (l *Tools) libraryNameOf(path string) string {
	root := l.storageRootFor(path)
	for _, r := range l.Roots.libraryRoots() {
		if root != "" && filepath.Clean(r.Path) == root {
			return r.Name
		}
	}
	return ""
}

// mergeFolder is where a book merge writes: beside the parts, or with the
// originals kept, a folder of its own beside the book.
func (l *Tools) mergeFolder(parts []string, book string, keepOriginals bool) string {
	root := l.storageRootFor(parts[0])
	dir := partsFolder(root, parts)
	if !keepOriginals {
		return dir
	}
	return toolBookFolder(root, dir, book, book+mergedMark)
}

// splitFolder is where a book split writes its pieces: the book's folder
// when one is named for it, else a new folder named for the book beside
// its file, or with the original kept, a folder of their own beside it.
func (l *Tools) splitFolder(src, book string, keepOriginals bool) string {
	title := book
	if keepOriginals {
		title += splitMark
	}
	return toolBookFolder(l.storageRootFor(src), filepath.Dir(src), book, title)
}

// The marks a kept original's copy carries in its title. The catalog
// identifies a book by author and title, so an unmarked copy would join
// the surviving original as more parts of the same item.
const (
	mergedMark = " (Merged)"
	splitMark  = " (Split)"
)

// probeToolFolders refuses a book tool when a folder it writes in will
// not take a file, before the task is queued and again before its trash
// runs: each folder named, or for one not made yet, the folder it would
// be made in.
func (l *Tools) probeToolFolders(dirs ...string) error {
	seen := map[string]bool{}
	for _, dir := range dirs {
		for {
			if _, err := os.Stat(dir); !errors.Is(err, os.ErrNotExist) || dir == filepath.Dir(dir) {
				break
			}
			dir = filepath.Dir(dir)
		}
		if seen[dir] {
			continue
		}
		seen[dir] = true
		// Permanent for a task that probes as it runs: a folder that will
		// not take a file does not mend between attempts.
		if err := probeWritable(dir); err != nil {
			if cause := l.Roots.storageRefused(err.Error()); cause != "" {
				e := errStorageUnwritable(cause)
				e.Err = errToolPermanent
				return e
			}
			return &Error{Kind: KindInternal, Err: errToolPermanent,
				Msg: "the book's folder could not be written: " + l.failureCause(err.Error())}
		}
	}
	return nil
}
