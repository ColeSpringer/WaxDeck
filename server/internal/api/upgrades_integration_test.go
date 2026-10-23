package api

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// twoEncodings writes one recording as a FLAC and a Vorbis file the library
// keeps under one item, tied by their recording id, and scans them in.
// Vorbis rather than MP3: both carry the id as the Vorbis comment the
// fixtures write verbatim.
func twoEncodings(t *testing.T, h *harness) string {
	t.Helper()
	tags := map[string]string{
		"TITLE": "Upgrade Me", "ARTIST": "Encoders", "ALBUM": "Two Ways",
		"MUSICBRAINZ_TRACKID": "00000000-0000-4000-8000-0000000000aa",
	}
	if _, err := fixtures.Generate(h.library,
		fixtures.Spec{Name: "upgrade", Codec: fixtures.CodecFLAC, Duration: 3 * time.Second, Tags: tags},
		fixtures.Spec{Name: "upgrade", Codec: fixtures.CodecVorbis, Duration: 3 * time.Second, Tags: tags},
	); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	return h.itemTitled(t, h.token, "Upgrade Me").Pid
}

// memberPath is where an upgrade member's file sits, read from the
// item's files.
func memberPath(t *testing.T, h *harness, m UpgradeMember) string {
	t.Helper()
	for _, f := range h.itemFiles(t, h.token, m.ItemPid) {
		if f.FilePid == m.FilePid && f.Path != nil {
			return *f.Path
		}
	}
	t.Fatalf("no file %s on %s", m.FilePid, m.ItemPid)
	return ""
}

// The listing names each encoding by its file: an item holding a lesser
// encoding of its recording is a group of its own, before and after the
// library is analyzed.
func TestUpgradesListAfterAnalyze(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	pid := twoEncodings(t, h)
	check := func(label string) {
		t.Helper()
		groups := decodeStatus[UpgradeGroups](t, get(t, h.ts, "/api/v1/library/upgrades", h.token), 200, label).Groups
		if len(groups) != 1 || len(groups[0].Members) != 2 {
			t.Fatalf("%s: groups = %+v, want the one item's two encodings", label, groups)
		}
		best, lesser := groups[0].Members[0], groups[0].Members[1]
		if best.ItemPid != pid || lesser.ItemPid != pid || best.FilePid == lesser.FilePid ||
			!best.Best || best.Codec != "flac" || lesser.Codec != "vorbis" {
			t.Fatalf("%s: members = %+v, want the FLAC kept over the Vorbis of %s by file", label, groups[0].Members, pid)
		}
		// Told apart by codec, neither needs its path read.
		if best.Path != nil || lesser.Path != nil {
			t.Fatalf("%s: members = %+v, want no paths where the codecs differ", label, groups[0].Members)
		}
	}
	check("scanned")
	analyzeAndWait(t, h)
	check("analyzed")
}

// One item's lesser encoding is trashed by its file, leaving the item on
// the kept one; a resolve naming the keeper for removal, or a file of
// another item, refuses before anything moves.
func TestUpgradesResolveByFile(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	pid := twoEncodings(t, h)
	members := decode[UpgradeGroups](t, get(t, h.ts, "/api/v1/library/upgrades", h.token)).Groups[0].Members
	keep, lose := members[0].FilePid, members[1].FilePid
	if !strings.HasPrefix(keep, "fl-") || !strings.HasPrefix(lose, "fl-") {
		t.Fatalf("members = %+v, want their file pids prefixed", members)
	}
	other := h.itemFiles(t, h.token, h.itemTitled(t, h.token, "Alpha Song").Pid)[0].FilePid
	wantStatus(t, h.postJSON(t, "/api/v1/library/upgrades/resolve", map[string]any{
		"keepItemPid": pid, "keepFilePid": keep, "removeFilePids": []string{strings.TrimPrefix(lose, "fl-")},
	}), 400, "a file pid without its prefix")

	wantStatus(t, h.postJSON(t, "/api/v1/library/upgrades/resolve", map[string]any{
		"keepItemPid": pid, "keepFilePid": keep, "removeFilePids": []string{keep, lose},
	}), 400, "keeping a file it removes")
	wantStatus(t, h.postJSON(t, "/api/v1/library/upgrades/resolve", map[string]any{
		"keepItemPid": pid, "keepFilePid": keep, "removeFilePids": []string{other},
	}), 404, "a file of another item")
	wantStatus(t, h.postJSON(t, "/api/v1/library/upgrades/resolve", map[string]any{
		"keepItemPid": pid, "keepFilePid": keep,
	}), 400, "no removals")
	wantStatus(t, h.postJSON(t, "/api/v1/library/upgrades/resolve", map[string]any{
		"keepItemPid": pid, "keepFilePid": keep, "removeFilePids": []string{lose}, "removeItemPids": []string{pid},
	}), 400, "both removal lists")

	res := decodeStatus[UpgradeResolveResult](t, h.postJSON(t, "/api/v1/library/upgrades/resolve", map[string]any{
		"keepItemPid": pid, "keepFilePid": keep, "removeFilePids": []string{lose},
	}), 200, "resolve by file")
	if res.Trashed != 1 {
		t.Fatalf("trashed = %d, want the Vorbis file", res.Trashed)
	}
	if files := h.itemFiles(t, h.token, pid); len(files) != 1 || files[0].FilePid != keep {
		t.Fatalf("files = %+v, want the kept FLAC alone", files)
	}
	if groups := decode[UpgradeGroups](t, get(t, h.ts, "/api/v1/library/upgrades", h.token)).Groups; len(groups) != 0 {
		t.Fatalf("groups after the resolve = %+v, want none", groups)
	}
}

// A resolve whose every move the filesystem refused says the library
// cannot be written, and is audited as refused rather than as a delete.
func TestAnUpgradeTheTrashCouldNotTakeIsRefused(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritablePaths(t)
	h := newHarness(t)
	pid := twoEncodings(t, h)
	members := decode[UpgradeGroups](t, get(t, h.ts, "/api/v1/library/upgrades", h.token)).Groups[0].Members
	if err := os.Chmod(h.library, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(h.library, 0o755) })
	resp := h.postJSON(t, "/api/v1/library/upgrades/resolve", map[string]any{
		"keepItemPid": pid, "keepFilePid": members[0].FilePid, "removeFilePids": []string{members[1].FilePid},
	})
	if resp.StatusCode != 409 {
		t.Fatalf("resolve into an unwritable folder = %d, want 409", resp.StatusCode)
	}
	if e := decode[Error](t, resp); e.Code != "storage-unwritable" || strings.Contains(e.Message, h.library) {
		t.Fatalf("refusal = %+v, want storage-unwritable without the server's folder", e)
	}
	refused := decode[AuditEventPage](t, get(t, h.ts, "/api/v1/admin/audit?action=items.delete-files.refused", h.token)).Events
	done := decode[AuditEventPage](t, get(t, h.ts, "/api/v1/admin/audit?action=items.delete-files", h.token)).Events
	if len(refused) != 1 || len(done) != 0 {
		t.Fatalf("audit refused %d, deleted %d, want the refusal alone", len(refused), len(done))
	}
}

// A copy of the removed encoding's audio in a read-only library stays
// where it is rather than refusing the resolve: nobody named it, and the
// kept encoding, in a writable library, still takes the item.
func TestAnUpgradeLeavesAReadOnlyCopyOfTheRemovedAudio(t *testing.T) {
	t.Parallel()
	archive := t.TempDir()
	h := newHarness(t, service.Root{Name: "archive", Path: archive})
	pid := twoEncodings(t, h)
	members := decode[UpgradeGroups](t, get(t, h.ts, "/api/v1/library/upgrades", h.token)).Groups[0].Members
	keep, lose := members[0], members[1]
	losePath := memberPath(t, h, lose)
	raw, err := os.ReadFile(losePath)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(archive, filepath.Base(losePath)), raw, 0o644); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	if files := h.itemFiles(t, h.token, pid); len(files) != 3 {
		t.Fatalf("files = %+v, want both encodings and the archived copy", files)
	}
	for _, lib := range decode[Libraries](t, get(t, h.ts, "/api/v1/libraries", h.token)).Libraries {
		if lib.Name == "archive" {
			wantStatus(t, h.putJSON(t, "/api/v1/libraries/"+lib.Pid+"/read-only", map[string]any{"readOnly": true}),
				200, "flag the archive read-only")
		}
	}

	res := decodeStatus[UpgradeResolveResult](t, h.postJSON(t, "/api/v1/library/upgrades/resolve", map[string]any{
		"keepItemPid": pid, "keepFilePid": keep.FilePid, "removeFilePids": []string{lose.FilePid},
	}), 200, "resolve with a read-only copy")
	if res.Trashed != 1 {
		t.Fatalf("trashed = %d, want the named Vorbis file alone", res.Trashed)
	}
	files := h.itemFiles(t, h.token, pid)
	if len(files) != 2 || files[0].FilePid != keep.FilePid || files[0].Role != "primary" ||
		files[1].Path == nil || !strings.HasPrefix(*files[1].Path, archive) {
		t.Fatalf("files = %+v, want the kept FLAC as primary beside the archived copy", files)
	}
}

// A resolve that names whole items refuses before anything moves when
// one of them keeps a copy in a read-only library: the item could not
// go, only its writable file would.
func TestAWholeItemResolveRefusesAReadOnlyCopyBeforeAnythingMoves(t *testing.T) {
	t.Parallel()
	archive := t.TempDir()
	h := newHarness(t, service.Root{Name: "archive", Path: archive})
	paths, err := fixtures.Generate(h.library,
		fixtures.Spec{Name: "keep", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
			Tags: map[string]string{"TITLE": "Keep Me", "ARTIST": "Encoders"}},
		fixtures.Spec{Name: "drop", Codec: fixtures.CodecFLAC, Duration: 3 * time.Second,
			Tags: map[string]string{"TITLE": "Drop Me", "ARTIST": "Encoders"}},
	)
	if err != nil {
		t.Fatal(err)
	}
	raw, err := os.ReadFile(paths[1])
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(archive, filepath.Base(paths[1])), raw, 0o644); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	for _, lib := range decode[Libraries](t, get(t, h.ts, "/api/v1/libraries", h.token)).Libraries {
		if lib.Name == "archive" {
			wantStatus(t, h.putJSON(t, "/api/v1/libraries/"+lib.Pid+"/read-only", map[string]any{"readOnly": true}),
				200, "flag the archive read-only")
		}
	}
	keep, drop := h.itemTitled(t, h.token, "Keep Me").Pid, h.itemTitled(t, h.token, "Drop Me").Pid
	resp := h.postJSON(t, "/api/v1/library/upgrades/resolve", map[string]any{
		"keepItemPid": keep, "removeItemPids": []string{drop},
	})
	if resp.StatusCode != 409 {
		resp.Body.Close()
		t.Fatalf("resolve of an item with a read-only copy = %d, want 409", resp.StatusCode)
	}
	if e := decode[Error](t, resp); e.Code != "read-only" {
		t.Fatalf("refusal = %+v, want read-only", e)
	}
	if _, err := os.Stat(paths[1]); err != nil {
		t.Fatalf("the writable file moved before the refusal: %v", err)
	}
}

// A resolve the trash could take only part of still records what it
// moved.
func TestAPartlyTrashedUpgradeIsAudited(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritablePaths(t)
	h := newHarness(t)
	pid := twoEncodings(t, h)
	members := decode[UpgradeGroups](t, get(t, h.ts, "/api/v1/library/upgrades", h.token)).Groups[0].Members
	keep, lose := members[0], members[1]
	// A copy of the lesser encoding in a folder the server cannot write
	// goes with it, and is the move that fails.
	locked := filepath.Join(h.library, "locked")
	if err := os.MkdirAll(locked, 0o755); err != nil {
		t.Fatal(err)
	}
	losePath := memberPath(t, h, lose)
	raw, err := os.ReadFile(losePath)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(locked, filepath.Base(losePath)), raw, 0o644); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	if err := os.Chmod(locked, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(locked, 0o755) })
	resp := h.postJSON(t, "/api/v1/library/upgrades/resolve", map[string]any{
		"keepItemPid": pid, "keepFilePid": keep.FilePid, "removeFilePids": []string{lose.FilePid},
	})
	wantStatus(t, resp, 409, "a resolve the trash took half of")
	events := decode[AuditEventPage](t, get(t, h.ts, "/api/v1/admin/audit?action=items.delete-files", h.token)).Events
	if len(events) != 1 {
		t.Fatalf("audit events = %+v, want the half that moved recorded", events)
	}
}

// A resolve names at most a hundred files or items, as the contract says.
func TestAnUpgradeResolveNamesAtMostAHundred(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	pid := twoEncodings(t, h)
	many := make([]string, 101)
	for i := range many {
		many[i] = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
	}
	for _, field := range []string{"removeFilePids", "removeItemPids"} {
		body := map[string]any{"keepItemPid": pid, field: many}
		if field == "removeFilePids" {
			body["keepFilePid"] = "01ARZ3NDEKTSV4RRFFQ69G5FAW"
		}
		wantStatus(t, h.postJSON(t, "/api/v1/library/upgrades/resolve", body), 400, "101 "+field)
	}
}
