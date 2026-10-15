package api

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/colespringer/waxdeck/fixtures"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// copyFixture copies one generated file of the library byte for byte
// into dir, returning the copy's path.
func copyFixture(t *testing.T, library, name, dir string) string {
	t.Helper()
	matches, err := filepath.Glob(filepath.Join(library, name+".*"))
	if err != nil || len(matches) != 1 {
		t.Fatalf("fixture %s = %v (%v), want one file", name, matches, err)
	}
	raw, err := os.ReadFile(matches[0])
	if err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	dst := filepath.Join(dir, filepath.Base(matches[0]))
	if err := os.WriteFile(dst, raw, 0o644); err != nil {
		t.Fatal(err)
	}
	return dst
}

// scanResult reads a finished scan's counts.
func (h *harness) scanResult(t *testing.T, jobPID string) map[string]any {
	t.Helper()
	job := decode[Job](t, get(t, h.ts, "/api/v1/jobs/"+jobPID, h.token))
	if job.Result == nil {
		t.Fatalf("scan %s recorded no result", jobPID)
	}
	return *job.Result
}

// count reads one count of a job result, failing on a key it lacks.
func count(t *testing.T, r map[string]any, key string) int {
	t.Helper()
	v, ok := r[key].(float64)
	if !ok {
		t.Fatalf("result %v has no count %q", r, key)
	}
	return int(v)
}

// A scan's counts partition what it saw: every audio file is added,
// updated, a sidecar change, a copy, unchanged or errored, and every file
// is audio or skipped. A byte-identical copy is counted as a copy, and a
// forced rescan reads every audio file in full.
func TestScanTallyAddsUp(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	copyFixture(t, h.library, "alpha", filepath.Join(h.library, "copies"))
	if err := os.WriteFile(filepath.Join(h.library, "copies", "booklet.jpg"), []byte("not audio"), 0o644); err != nil {
		t.Fatal(err)
	}
	check := func(label string, r map[string]any) {
		t.Helper()
		audio := count(t, r, "audioFiles")
		if sum := count(t, r, "created") + count(t, r, "updated") + count(t, r, "sidecarsUpdated") +
			count(t, r, "copies") + count(t, r, "unchanged") + count(t, r, "errored"); sum != audio {
			t.Errorf("%s: audio files %d, partition sums to %d: %v", label, audio, sum, r)
		}
		if seen := count(t, r, "filesSeen"); seen != audio+count(t, r, "skipped") {
			t.Errorf("%s: files seen %d, want audio %d and skipped %d: %v", label, seen, audio, count(t, r, "skipped"), r)
		}
		for _, key := range []string{"relinked", "reread", "missing", "promoted", "dropped", "walkErrors"} {
			count(t, r, key)
		}
		if r["rootUnreachable"] != false || r["subPathGone"] != false {
			t.Errorf("%s: root flags = %v, %v, want false", label, r["rootUnreachable"], r["subPathGone"])
		}
	}

	first := h.scanResult(t, h.rescanAndWait(t))
	check("plain", first)
	if got := count(t, first, "audioFiles"); got != 5 {
		t.Errorf("audio files = %d, want the four tracks and the copy", got)
	}
	if got := count(t, first, "copies"); got != 1 {
		t.Errorf("copies = %d, want 1", got)
	}
	if got := count(t, first, "skipped"); got < 1 {
		t.Errorf("skipped = %d, want the booklet", got)
	}
	runs, ok := first["runs"].([]any)
	if !ok || len(runs) != 1 {
		t.Fatalf("runs = %v, want the one library's", first["runs"])
	}
	run := runs[0].(map[string]any)
	if run["library"] != "lib" || count(t, run, "copies") != 1 {
		t.Errorf("run = %v, want the library by name with its copy", run)
	}

	forced := h.scanResult(t, h.rescanAndWaitWith(t, `{"force": true}`))
	check("forced", forced)
	if got, audio := count(t, forced, "reread"), count(t, forced, "audioFiles"); got != audio {
		t.Errorf("forced reread = %d, want every audio file (%d)", got, audio)
	}
}

// itemTitled finds the one visible item with a title.
func (h *harness) itemTitled(t *testing.T, token, title string) ItemSummary {
	t.Helper()
	var found []ItemSummary
	for _, it := range decode[ItemPage](t, get(t, h.ts, "/api/v1/library/items?limit=500", token)).Items {
		if it.Title == title {
			found = append(found, it)
		}
	}
	if len(found) != 1 {
		t.Fatalf("items titled %q = %+v, want one", title, found)
	}
	return found[0]
}

// itemFiles lists an item's files as a caller sees them.
func (h *harness) itemFiles(t *testing.T, token, pid string) []ItemFile {
	t.Helper()
	return decodeStatus[ItemFiles](t, reqAs(t, h, "GET", "/api/v1/items/"+pid+"/files", token, nil), 200, "item files").Files
}

// A byte-identical copy joins the item it copies: the item keeps its
// title, album and download, lists the copy after its file, and a
// diagnostic names it. Deleting the copy leaves the item on its file;
// deleting the primary gives its place to a copy, and the item stays.
func TestACopyJoinsItsItem(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	copyFixture(t, h.library, "alpha", filepath.Join(h.library, "copies"))
	h.rescanAndWait(t)

	pid := h.itemTitled(t, h.token, "Alpha Song").Pid
	item := decode[Item](t, get(t, h.ts, "/api/v1/items/"+pid, h.token))
	if item.Copies == nil || *item.Copies != 1 || item.Album == nil || *item.Album != "Fixture Album" {
		t.Fatalf("item = copies %v, album %v; want one copy and its own album", item.Copies, item.Album)
	}
	files := h.itemFiles(t, h.token, pid)
	if len(files) != 2 || files[0].Role != "primary" || files[1].Role != "alternate" {
		t.Fatalf("files = %+v, want the primary then the copy", files)
	}
	cp := files[1]
	if cp.Reason == nil || *cp.Reason != "same-audio" || cp.Name != "alpha.flac" || cp.Path == nil ||
		!strings.Contains(*cp.Path, "copies") || cp.SizeBytes == nil || *cp.SizeBytes == 0 || cp.LibraryPid == nil {
		t.Fatalf("copy = %+v, want a same-audio alpha.flac under copies/", cp)
	}
	if dl := decode[DownloadInfo](t, get(t, h.ts, "/api/v1/items/"+pid+"/download-info", h.token)); len(dl.Files) != 1 {
		t.Fatalf("download-info files = %d, want the item's own one", len(dl.Files))
	}
	diags := decode[FileDiagnosticPage](t, get(t, h.ts, "/api/v1/library/diagnostics?code=duplicate_copy", h.token))
	if len(diags.Diagnostics) != 1 || !strings.Contains(diags.Diagnostics[0].Path, "copies") {
		t.Fatalf("duplicate_copy diagnostics = %+v, want the copy", diags.Diagnostics)
	}

	// The dry run names the copy and says the track stays.
	dry := decodeStatus[DeleteItemsResult](t, h.postJSON(t, "/api/v1/items/"+pid+"/files/delete",
		map[string]any{"filePids": []string{cp.FilePid}, "dryRun": true}), 200, "plan the copy's delete")
	if dry.Applied || len(dry.Entries) != 1 || dry.Entries[0].FileList == nil || len(*dry.Entries[0].FileList) != 1 ||
		(*dry.Entries[0].FileList)[0].Name != "alpha.flac" || (*dry.Entries[0].FileList)[0].Role != "alternate" ||
		dry.Entries[0].ItemSurvives == nil || !*dry.Entries[0].ItemSurvives {
		t.Fatalf("dry run = %+v, want the copy named and the item surviving", dry)
	}
	done := decodeStatus[DeleteItemsResult](t, h.postJSON(t, "/api/v1/items/"+pid+"/files/delete",
		map[string]any{"filePids": []string{cp.FilePid}}), 200, "delete the copy")
	if !done.Applied || done.Warnings != nil {
		t.Fatalf("delete = %+v, want applied with nothing to say", done)
	}
	if _, err := os.Stat(*cp.Path); !os.IsNotExist(err) {
		t.Fatalf("the copy is still on disk (%v)", err)
	}
	if files := h.itemFiles(t, h.token, pid); len(files) != 1 || files[0].Role != "primary" {
		t.Fatalf("files after deleting the copy = %+v, want the primary alone", files)
	}
	if item := decode[Item](t, get(t, h.ts, "/api/v1/items/"+pid, h.token)); item.Copies != nil {
		t.Fatalf("copies after deleting the copy = %v, want none", *item.Copies)
	}

	// With a copy again, deleting the primary gives the copy its place.
	copyFixture(t, h.library, "alpha", filepath.Join(h.library, "copies again"))
	h.rescanAndWait(t)
	files = h.itemFiles(t, h.token, pid)
	if len(files) != 2 {
		t.Fatalf("files = %+v, want the primary and a new copy", files)
	}
	primary, again := files[0], files[1]
	res := decodeStatus[DeleteItemsResult](t, h.postJSON(t, "/api/v1/items/"+pid+"/files/delete",
		map[string]any{"filePids": []string{primary.FilePid}}), 200, "delete the primary")
	if res.Warnings == nil || len(*res.Warnings) != 1 || !strings.Contains((*res.Warnings)[0], "alpha.flac is now the item's main file") {
		t.Fatalf("delete warnings = %v, want the copy's promotion", res.Warnings)
	}
	files = h.itemFiles(t, h.token, pid)
	if len(files) != 1 || files[0].FilePid != again.FilePid || files[0].Role != "primary" {
		t.Fatalf("files after deleting the primary = %+v, want the copy as primary", files)
	}
	if got := h.itemTitled(t, h.token, "Alpha Song").Pid; got != pid {
		t.Fatalf("the item moved from %s to %s", pid, got)
	}
}

// An item's files say why each copy is one: a byte-identical file holds
// the same audio as the item's own, and a file of the recording in
// another codec is another encoding of it.
func TestAnItemsFilesSayWhyEachCopyIsOne(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	pid := twoEncodings(t, h)
	raw, err := os.ReadFile(filepath.Join(h.library, "upgrade.flac"))
	if err != nil {
		t.Fatal(err)
	}
	copies := filepath.Join(h.library, "copies")
	if err := os.MkdirAll(copies, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(copies, "upgrade.flac"), raw, 0o644); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)

	reasons := map[string]string{}
	for _, f := range h.itemFiles(t, h.token, pid) {
		if f.Path == nil || f.Codec == nil {
			t.Fatalf("file = %+v, want its path and codec", f)
		}
		key := f.Role + " " + *f.Codec
		if strings.Contains(*f.Path, "copies") {
			key += " copy"
		}
		reasons[key] = "none"
		if f.Reason != nil {
			reasons[key] = *f.Reason
		}
	}
	want := map[string]string{
		"primary flac": "none", "alternate flac copy": "same-audio", "alternate vorbis": "other-encoding",
	}
	if len(reasons) != len(want) {
		t.Fatalf("files = %v, want the FLAC, its copy and the Vorbis", reasons)
	}
	for k, v := range want {
		if reasons[k] != v {
			t.Errorf("%s: reason %q, want %q (files %v)", k, reasons[k], v, reasons)
		}
	}
}

// What a caller reads of an item's files follows their reach: no list
// without the download right, no paths without the admin role, and no
// copy in a library they cannot see, which a whole-item delete of theirs
// leaves in place, keeping the item.
func TestItemFilesFollowTheCallersReach(t *testing.T) {
	t.Parallel()
	// The second library holds the demo library's charlie again, scanned
	// after the first, so the copy there joins the first's item.
	elsewhere := t.TempDir()
	for _, spec := range fixtures.DemoLibrary() {
		if spec.Name == "charlie" {
			if _, err := fixtures.Generate(elsewhere, spec); err != nil {
				t.Fatal(err)
			}
		}
	}
	h := newHarness(t, service.Root{Name: "elsewhere", Path: elsewhere})
	copyFixture(t, h.library, "bravo", filepath.Join(h.library, "copies"))
	h.rescanAndWait(t)
	var home string
	var lib Library
	for _, l := range decode[Libraries](t, get(t, h.ts, "/api/v1/libraries", h.token)).Libraries {
		if l.Name == "elsewhere" {
			lib = l
		} else {
			home = l.Pid
		}
	}

	grant := map[string]any{"mode": "granted", "libraryPids": []string{home}}
	wantStatus(t, h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "no-download", "password": testPassword, "libraryAccess": grant,
		"permissions": map[string]any{"download": false, "delete": false, "explicitContent": true},
	}), 201, "a reader without the download right")
	wantStatus(t, h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "curator", "password": testPassword, "libraryAccess": grant,
		"permissions": map[string]any{"download": true, "delete": true, "explicitContent": true},
	}), 201, "a reader with download and delete")
	reader := loginAs(t, h.ts, "no-download", testPassword).Token
	curator := loginAs(t, h.ts, "curator", testPassword).Token

	bravo := h.itemTitled(t, curator, "Bravo Song").Pid
	wantStatus(t, reqAs(t, h, "GET", "/api/v1/items/"+bravo+"/files", reader, nil), 403, "files without the download right")
	for _, f := range h.itemFiles(t, curator, bravo) {
		if f.Path != nil {
			t.Fatalf("a non-administrator read a path: %+v", f)
		}
	}

	charlie := h.itemTitled(t, curator, "Charlie Song").Pid
	if all := h.itemFiles(t, h.token, charlie); len(all) != 2 || all[1].LibraryPid == nil || *all[1].LibraryPid != lib.Pid {
		t.Fatalf("administrator's files = %+v, want the copy in the second library", all)
	}
	if mine := h.itemFiles(t, curator, charlie); len(mine) != 1 || mine[0].Role != "primary" {
		t.Fatalf("curator's files = %+v, want the primary alone", mine)
	}
	if item := decode[Item](t, get(t, h.ts, "/api/v1/items/"+charlie, curator)); item.Copies != nil {
		t.Fatalf("curator's copies = %v, want none counted", *item.Copies)
	}

	plan := decodeStatus[DeleteItemsResult](t, reqAs(t, h, "POST", "/api/v1/library/items/delete", curator,
		map[string]any{"pids": []string{charlie}, "dryRun": true}), 200, "plan the item's delete")
	e := plan.Entries[0]
	if e.Files != 1 || e.FileList == nil || len(*e.FileList) != 1 || (*e.FileList)[0].Role != "primary" ||
		e.ItemSurvives == nil || !*e.ItemSurvives {
		t.Fatalf("plan entry = %+v, want the primary alone and the item kept", e)
	}
	wantStatus(t, reqAs(t, h, "POST", "/api/v1/library/items/delete", curator,
		map[string]any{"pids": []string{charlie}}), 200, "delete the item")
	if _, err := os.Stat(filepath.Join(elsewhere, "charlie.opus")); err != nil {
		t.Fatalf("the copy in the library the curator cannot see is gone: %v", err)
	}
	if files := h.itemFiles(t, h.token, charlie); len(files) != 1 || files[0].LibraryPid == nil || *files[0].LibraryPid != lib.Pid {
		t.Fatalf("files after the curator's delete = %+v, want the item on its copy", files)
	}
}

// A whole-item delete that a copy in a read-only library survives says
// which file holds the item now.
func TestDeletingAnItemNamesTheCopyThatKeepsIt(t *testing.T) {
	t.Parallel()
	archive := t.TempDir()
	h := newHarness(t, service.Root{Name: "archive", Path: archive})
	copyFixture(t, h.library, "alpha", archive)
	h.rescanAndWait(t)
	pid := h.itemTitled(t, h.token, "Alpha Song").Pid
	for _, lib := range decode[Libraries](t, get(t, h.ts, "/api/v1/libraries", h.token)).Libraries {
		if lib.Name == "archive" {
			wantStatus(t, h.putJSON(t, "/api/v1/libraries/"+lib.Pid+"/read-only", map[string]any{"readOnly": true}),
				200, "flag the archive read-only")
		}
	}
	res := decodeStatus[DeleteItemsResult](t, h.postJSON(t, "/api/v1/library/items/delete",
		map[string]any{"pids": []string{pid}, "mode": "trash"}), 200, "delete the item")
	if res.Warnings == nil || len(*res.Warnings) != 1 ||
		!strings.Contains((*res.Warnings)[0], "Alpha Song: alpha.flac is now the item's main file") {
		t.Fatalf("warnings = %v, want the archived copy named as the item's main file", res.Warnings)
	}
}

// A file the trash could not take is not reported deleted: the answer
// leaves it out of what went, and a warning says it stayed.
func TestADeleteTheTrashCouldNotTakeSaysTheFileStayed(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritablePaths(t)
	h := newHarness(t)
	locked := filepath.Join(h.library, "locked")
	dst := copyFixture(t, h.library, "alpha", locked)
	h.rescanAndWait(t)
	pid := h.itemTitled(t, h.token, "Alpha Song").Pid
	var copyPID string
	for _, f := range h.itemFiles(t, h.token, pid) {
		if f.Path != nil && *f.Path == dst {
			copyPID = f.FilePid
		}
	}
	if copyPID == "" {
		t.Fatal("the copy did not join the item")
	}
	if err := os.Chmod(locked, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(locked, 0o755) })
	res := decodeStatus[DeleteItemsResult](t, h.postJSON(t, "/api/v1/items/"+pid+"/files/delete",
		map[string]any{"filePids": []string{copyPID}}), 200, "delete the locked copy")
	for _, e := range res.Entries {
		if e.Files > 0 {
			t.Fatalf("entries = %+v, want nothing reported gone", res.Entries)
		}
	}
	if res.Warnings == nil || len(*res.Warnings) != 1 || !strings.Contains((*res.Warnings)[0], "alpha.flac stayed") {
		t.Fatalf("warnings = %v, want the copy named as staying", res.Warnings)
	}
	if _, err := os.Stat(dst); err != nil {
		t.Fatalf("the copy is gone after all: %v", err)
	}
}
