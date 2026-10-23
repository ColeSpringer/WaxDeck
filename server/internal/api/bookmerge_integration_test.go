package api

import (
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
)

// booksLibrary adds to a tool harness a second, in-place audiobook
// library, created at runtime and holding the three-part fixture book:
// what a book merge must keep in its own library. It answers the
// library's root, the book's folder and the book.
func booksLibrary(t *testing.T, h *harness) (string, string, ItemSummary) {
	t.Helper()
	root := t.TempDir()
	bookDir, err := fixtures.GenerateBook(root)
	if err != nil {
		t.Fatal(err)
	}
	lib := decodeStatus[Library](t, h.postJSON(t, "/api/v1/libraries", map[string]any{
		"name": "books", "path": root, "media": "audiobook",
	}), 201, "a books library")
	// The harness wires no root sync; the server's own teaches the
	// streaming bridge a new library the same way.
	h.bridge.AddRoot(lib.Name, root)
	var books []ItemSummary
	for deadline := time.Now().Add(30 * time.Second); len(books) != 1; time.Sleep(50 * time.Millisecond) {
		if time.Now().After(deadline) {
			t.Fatalf("audiobooks = %+v, want the fixture book scanned", books)
		}
		books = h.items(t, "?mediaType=audiobook").Items
	}
	waitForScans(t, h)
	return root, bookDir, books[0]
}

// memberOfLib creates an account granted only the harness's own library
// and answers its token.
func memberOfLib(t *testing.T, h *harness) string {
	t.Helper()
	acct := decodeStatus[UserAccount](t, h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "sam", "password": testPassword,
	}), 201, "create sam")
	var lib string
	for _, l := range decode[Libraries](t, get(t, h.ts, "/api/v1/libraries", h.token)).Libraries {
		if l.Name == "lib" {
			lib = l.Pid
		}
	}
	wantStatus(t, h.patchJSON(t, "/api/v1/users/"+acct.Id, map[string]any{
		"libraryAccess": map[string]any{"mode": "granted", "libraryPids": []string{lib}},
	}), 200, "grant sam the lib library alone")
	return loginAs(t, h.ts, "sam", testPassword).Token
}

// runMerge merges a book and drains the task, answering it.
func runMerge(t *testing.T, h *harness, pid string, body map[string]any) ToolTask {
	t.Helper()
	task := decodeStatus[ToolTask](t, h.postJSON(t, "/api/v1/books/"+pid+"/merge", body), 202, "queue the merge")
	drainToolTasks(t, h)
	return h.toolTask(t, task.Id)
}

// folderNames lists a folder's entries by name.
func folderNames(t *testing.T, dir string) []string {
	t.Helper()
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	var out []string
	for _, e := range entries {
		out = append(out, e.Name())
	}
	return out
}

// A merge writes the merged file beside the parts, in the book's own
// library, so a member who cannot see that library cannot see the merged
// book either; the parts go to the trash under the merge's reason, and
// the merge is audited.
func TestABookMergeStaysInItsLibrary(t *testing.T) {
	t.Parallel()
	h := newToolHarness(t)
	_, bookDir, book := booksLibrary(t, h)
	sam := memberOfLib(t, h)

	queued := decodeStatus[ToolTask](t, h.postJSON(t, "/api/v1/books/"+book.Pid+"/merge", map[string]any{}), 202, "queue the merge")
	if queued.ItemTitle == nil || *queued.ItemTitle != "The Fixture Book" {
		t.Fatalf("queued task title = %v, want the book's", queued.ItemTitle)
	}
	drainToolTasks(t, h)
	done := h.toolTask(t, queued.Id)
	if done.State != "done" || done.ResultPids == nil || len(*done.ResultPids) != 1 {
		t.Fatalf("task = %+v (error %q), want it done with the merged book", done, deref(done.Error))
	}
	merged := (*done.ResultPids)[0]
	files := h.itemFiles(t, h.token, merged)
	if len(files) != 1 || files[0].Path == nil || *files[0].Path != filepath.Join(bookDir, "The Fixture Book.m4b") {
		t.Fatalf("merged files = %+v, want one file beside the parts in %s", files, bookDir)
	}
	if names := folderNames(t, bookDir); !slices.Equal(names, []string{"The Fixture Book.m4b"}) {
		t.Fatalf("the book's folder holds %q, want the merged file alone", names)
	}
	wantStatus(t, reqAs(t, h, "GET", "/api/v1/books/"+merged, sam, nil), 404, "the merged book for a member of lib alone")

	trash := decode[TrashList](t, get(t, h.ts, "/api/v1/admin/trash", h.token)).Entries
	if len(trash) != 3 {
		t.Fatalf("trash = %+v, want the three parts", trash)
	}
	for _, e := range trash {
		if e.Reason != "book-merge" {
			t.Errorf("trashed part %s reason = %q, want book-merge", e.Name, e.Reason)
		}
	}
	events := decode[AuditEventPage](t, get(t, h.ts, "/api/v1/admin/audit?action=book.merge", h.token)).Events
	if len(events) != 1 || events[0].Detail == nil {
		t.Fatalf("book.merge audits = %+v, want one", events)
	}
	if d := *events[0].Detail; d["result"] != merged || d["parts"] != float64(3) || d["trashed"] != float64(3) ||
		d["library"] != "books" || d["keepOriginals"] != false {
		t.Fatalf("audit detail = %v, want the result, its parts, the library and what went", d)
	}
}

// A merge that keeps the originals writes its copy, marked, into a
// folder of its own beside the original, which stays whole.
func TestAKeptOriginalsMergeLandsInItsOwnFolder(t *testing.T) {
	t.Parallel()
	h := newToolHarness(t)
	_, bookDir, book := booksLibrary(t, h)
	done := runMerge(t, h, book.Pid, map[string]any{"keepOriginals": true})
	if done.State != "done" || done.ResultPids == nil || len(*done.ResultPids) != 1 {
		t.Fatalf("task = %+v (error %q), want it done", done, deref(done.Error))
	}
	merged := (*done.ResultPids)[0]
	if merged == book.Pid {
		t.Fatal("the kept-originals merge joined the original book")
	}
	ownDir := filepath.Join(filepath.Dir(bookDir), "The Fixture Book (Merged)")
	files := h.itemFiles(t, h.token, merged)
	if len(files) != 1 || files[0].Path == nil || *files[0].Path != filepath.Join(ownDir, "The Fixture Book (Merged).m4b") {
		t.Fatalf("merged files = %+v, want one file in %s", files, ownDir)
	}
	original := decode[BookDetail](t, get(t, h.ts, "/api/v1/books/"+book.Pid, h.token))
	if len(original.Parts) != 3 || len(folderNames(t, bookDir)) != 3 {
		t.Fatalf("the original after a kept merge has %d parts, its folder %q; want it whole",
			len(original.Parts), folderNames(t, bookDir))
	}
	if trash := decode[TrashList](t, get(t, h.ts, "/api/v1/admin/trash", h.token)).Entries; len(trash) != 0 {
		t.Fatalf("trash = %+v, want nothing trashed", trash)
	}
}

// A merge whose parts the trash cannot take writes nothing: the parts
// stay the book they were, and no merged file or leftover is beside them.
func TestAMergeWhoseTrashFailsWritesNothing(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritablePaths(t)
	h := newToolHarness(t)
	root, bookDir, book := booksLibrary(t, h)
	task := decodeStatus[ToolTask](t, h.postJSON(t, "/api/v1/books/"+book.Pid+"/merge", map[string]any{}), 202, "queue the merge")
	// The book's folder still takes writes; the library's root, where
	// the trash would be made, stopped since the merge was queued.
	if err := os.Chmod(root, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(root, 0o755) })
	drainToolTasks(t, h)
	done := h.toolTask(t, task.Id)
	if done.State != "failed" || !strings.Contains(deref(done.Error), "permission denied") {
		t.Fatalf("task = %s (error %q), want it failed on the refused move", done.State, deref(done.Error))
	}
	if names := folderNames(t, bookDir); len(names) != 3 || slices.Contains(names, "The Fixture Book.m4b") {
		t.Fatalf("the book's folder holds %q, want the three parts alone", names)
	}
	detail := decode[BookDetail](t, get(t, h.ts, "/api/v1/books/"+book.Pid, h.token))
	if len(detail.Parts) != 3 {
		t.Fatalf("the book after a failed merge has %d parts, want 3", len(detail.Parts))
	}
	if trash := decode[TrashList](t, get(t, h.ts, "/api/v1/admin/trash", h.token)).Entries; len(trash) != 0 {
		t.Fatalf("trash = %+v, want nothing trashed", trash)
	}
	if events := decode[AuditEventPage](t, get(t, h.ts, "/api/v1/admin/audit?action=book.merge", h.token)).Events; len(events) != 0 {
		t.Fatalf("book.merge audits = %+v, want none for a merge that changed nothing", events)
	}
}

// A merge whose library's root will not take the trash's folder is
// refused before anything is queued.
func TestABookMergeRefusesALibraryWhoseTrashItCannotMake(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritablePaths(t)
	h := newToolHarness(t)
	root, _, book := booksLibrary(t, h)
	if err := os.Chmod(root, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(root, 0o755) })
	refusal := decodeStatus[Error](t, h.postJSON(t, "/api/v1/books/"+book.Pid+"/merge", map[string]any{}), 409, "merge with no room for the trash")
	if refusal.Code != "storage-unwritable" || strings.Contains(refusal.Message, root) {
		t.Fatalf("refusal = %+v, want storage-unwritable without the server's folder", refusal)
	}
	if tasks := decode[ToolTaskPage](t, get(t, h.ts, "/api/v1/tools/tasks", h.token)).Tasks; len(tasks) != 0 {
		t.Fatalf("tasks = %+v, want nothing queued", tasks)
	}
	// Keeping the originals trashes nothing, so it is not refused.
	decodeStatus[ToolTask](t, h.postJSON(t, "/api/v1/books/"+book.Pid+"/merge", map[string]any{"keepOriginals": true}),
		202, "a merge keeping the originals")
}

// A merge into a folder the server cannot write is refused before
// anything is queued.
func TestABookMergeRefusesAFolderItCannotWrite(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritablePaths(t)
	h := newToolHarness(t)
	_, bookDir, book := booksLibrary(t, h)
	if err := os.Chmod(bookDir, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(bookDir, 0o755) })
	refusal := decodeStatus[Error](t, h.postJSON(t, "/api/v1/books/"+book.Pid+"/merge", map[string]any{}), 409, "merge into a locked folder")
	if refusal.Code != "storage-unwritable" || strings.Contains(refusal.Message, bookDir) {
		t.Fatalf("refusal = %+v, want storage-unwritable without the server's folder", refusal)
	}
	if tasks := decode[ToolTaskPage](t, get(t, h.ts, "/api/v1/tools/tasks", h.token)).Tasks; len(tasks) != 0 {
		t.Fatalf("tasks = %+v, want nothing queued", tasks)
	}
}

// A split of a book whose folder is named for it writes the pieces into
// that folder rather than a second one nested inside, trashes the
// original under the split's reason, and is audited.
func TestABookSplitInItsOwnFolderDoesNotNestAnother(t *testing.T) {
	t.Parallel()
	h := newToolHarness(t)
	root := t.TempDir()
	bookDir := filepath.Join(root, "Ada Author", "The Chaptered Fixture")
	if _, err := fixtures.GenerateChapteredBook(bookDir); err != nil {
		t.Fatal(err)
	}
	lib := decodeStatus[Library](t, h.postJSON(t, "/api/v1/libraries", map[string]any{
		"name": "books", "path": root, "media": "audiobook",
	}), 201, "a books library")
	h.bridge.AddRoot(lib.Name, root)
	var books []ItemSummary
	for deadline := time.Now().Add(30 * time.Second); len(books) != 1; time.Sleep(50 * time.Millisecond) {
		if time.Now().After(deadline) {
			t.Fatal("the chaptered book was not scanned")
		}
		books = h.items(t, "?mediaType=audiobook").Items
	}
	waitForScans(t, h)

	task := decodeStatus[ToolTask](t, h.postJSON(t, "/api/v1/books/"+books[0].Pid+"/split", map[string]any{}), 202, "queue the split")
	if task.ItemTitle == nil || *task.ItemTitle != "The Chaptered Fixture" {
		t.Fatalf("queued task title = %v, want the book's", task.ItemTitle)
	}
	drainToolTasks(t, h)
	done := h.toolTask(t, task.Id)
	if done.State != "done" || done.ResultPids == nil || len(*done.ResultPids) != 1 {
		t.Fatalf("task = %+v (error %q), want it done", done, deref(done.Error))
	}
	names := folderNames(t, bookDir)
	if len(names) != 3 || slices.ContainsFunc(names, func(n string) bool { return !strings.HasSuffix(n, ".m4b") }) {
		t.Fatalf("the book's folder holds %q, want the three pieces and no nested folder", names)
	}
	if trash := decode[TrashList](t, get(t, h.ts, "/api/v1/admin/trash", h.token)).Entries; len(trash) != 1 || trash[0].Reason != "book-split" {
		t.Fatalf("trash = %+v, want the original under book-split", trash)
	}
	events := decode[AuditEventPage](t, get(t, h.ts, "/api/v1/admin/audit?action=book.split", h.token)).Events
	if len(events) != 1 || events[0].Detail == nil || (*events[0].Detail)["pieces"] != float64(3) {
		t.Fatalf("book.split audits = %+v, want one naming its three pieces", events)
	}
}

// discBook writes a two-part book into disc folders of its own folder in
// a new in-place audiobook library, and answers the book's folder and the
// book.
func discBook(t *testing.T, h *harness) (string, ItemSummary) {
	t.Helper()
	root := t.TempDir()
	bookDir := filepath.Join(root, "Ada Author", "The Disc Book")
	for i, disc := range []string{"CD1", "CD2"} {
		if _, err := fixtures.GenerateM4B(filepath.Join(bookDir, disc), fixtures.Spec{
			Name: "part", Duration: time.Duration(3+i) * time.Second,
			Tags: map[string]string{"TITLE": disc, "ALBUM": "The Disc Book", "ARTIST": "Ada Author",
				"ALBUMARTIST": "Ada Author", "TRACKNUMBER": string(rune('1' + i))},
		}); err != nil {
			t.Fatal(err)
		}
	}
	lib := decodeStatus[Library](t, h.postJSON(t, "/api/v1/libraries", map[string]any{
		"name": "discs", "path": root, "media": "audiobook",
	}), 201, "a books library")
	h.bridge.AddRoot(lib.Name, root)
	var books []ItemSummary
	for deadline := time.Now().Add(30 * time.Second); len(books) != 1; time.Sleep(50 * time.Millisecond) {
		if time.Now().After(deadline) {
			t.Fatalf("audiobooks = %+v, want the disc book scanned", books)
		}
		books = h.items(t, "?mediaType=audiobook").Items
	}
	waitForScans(t, h)
	return bookDir, books[0]
}

// A merge writes into the book's own folder above its disc folders, which
// the trash empties and removes.
func TestAMergeOfDiscFoldersWritesIntoTheBooksFolder(t *testing.T) {
	t.Parallel()
	h := newToolHarness(t)
	bookDir, book := discBook(t, h)
	done := runMerge(t, h, book.Pid, map[string]any{})
	if done.State != "done" {
		t.Fatalf("task = %s (error %q), want done", done.State, deref(done.Error))
	}
	if names := folderNames(t, bookDir); !slices.Equal(names, []string{"The Disc Book.m4b"}) {
		t.Fatalf("the book's folder holds %q, want the merged file alone", names)
	}
}

// A part's folder that stops taking writes after the merge was queued
// fails the merge before any part moves.
func TestAMergeChecksItsPartsFoldersBeforeTrashingAny(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritablePaths(t)
	h := newToolHarness(t)
	bookDir, book := discBook(t, h)
	task := decodeStatus[ToolTask](t, h.postJSON(t, "/api/v1/books/"+book.Pid+"/merge", map[string]any{}), 202, "queue the merge")
	locked := filepath.Join(bookDir, "CD2")
	if err := os.Chmod(locked, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(locked, 0o755) })
	drainToolTasks(t, h)
	done := h.toolTask(t, task.Id)
	if done.State != "failed" || !strings.Contains(deref(done.Error), "permission denied") {
		t.Fatalf("task = %s (error %q), want it failed on the locked folder", done.State, deref(done.Error))
	}
	if trash := decode[TrashList](t, get(t, h.ts, "/api/v1/admin/trash", h.token)).Entries; len(trash) != 0 {
		t.Fatalf("trash = %+v, want no part moved", trash)
	}
	if names := folderNames(t, bookDir); !slices.Equal(names, []string{"CD1", "CD2"}) {
		t.Fatalf("the book's folder holds %q, want its two disc folders alone", names)
	}
}

// A merge or split of a book another one is at work on is refused before
// it is queued, naming the task at work, which the client words.
func TestABookToolOnABookWithALiveTaskIsRefused(t *testing.T) {
	t.Parallel()
	h := newToolHarness(t)
	_, _, book := booksLibrary(t, h)
	first := decodeStatus[ToolTask](t, h.postJSON(t, "/api/v1/books/"+book.Pid+"/merge", map[string]any{}), 202, "queue the merge")
	for _, path := range []string{"/merge", "/split"} {
		refusal := decodeStatus[Error](t, h.postJSON(t, "/api/v1/books/"+book.Pid+path, map[string]any{}), 409, "a second tool on the book")
		if refusal.Code != "conflict" || refusal.Params == nil || (*refusal.Params)["reason"] != "task-running" ||
			(*refusal.Params)["task"] != first.Id {
			t.Fatalf("%s refusal = %+v, want conflict, reason task-running, naming %s", path, refusal, first.Id)
		}
	}
}

// A merge whose file's name another file holds is refused before it is
// queued, naming the file and its folder.
func TestAMergeIntoATakenNameIsRefused(t *testing.T) {
	t.Parallel()
	h := newToolHarness(t)
	_, bookDir, book := booksLibrary(t, h)
	own := filepath.Join(filepath.Dir(bookDir), "The Fixture Book (Merged)")
	if err := os.MkdirAll(own, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(own, "The Fixture Book (Merged).m4b"), []byte("not ours"), 0o644); err != nil {
		t.Fatal(err)
	}
	refusal := decodeStatus[Error](t, h.postJSON(t, "/api/v1/books/"+book.Pid+"/merge", map[string]any{"keepOriginals": true}), 409, "merge into a taken name")
	if refusal.Code != "conflict" || refusal.Params == nil || (*refusal.Params)["reason"] != "name-taken" ||
		(*refusal.Params)["name"] != "The Fixture Book (Merged).m4b" || strings.Contains((*refusal.Params)["folder"], own) {
		t.Fatalf("refusal = %+v, want name-taken naming the file and its folder in the library", refusal)
	}
}
