package api

import (
	"context"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	waxlabel "github.com/colespringer/waxlabel"
	"github.com/colespringer/waxlabel/tag"

	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxdeck/server/internal/match"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// tagOnDisk reads one tag off a file.
func tagOnDisk(t *testing.T, path string, key tag.Key) string {
	t.Helper()
	doc, err := waxlabel.ParseFile(context.Background(), path)
	if err != nil {
		t.Fatalf("reading %s: %v", filepath.Base(path), err)
	}
	if vals, ok := doc.Get(key); ok && len(vals) > 0 {
		return vals[0]
	}
	return ""
}

// nightfallLibrary scans the messy album into a server answering the
// canned release, and answers the first track and its file.
func nightfallLibrary(t *testing.T, mutate func([]fixtures.Spec)) (*harness, string, string) {
	t.Helper()
	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.MatchSource = &cannedSource{releases: []*match.Release{nightfallRelease()}}
	})
	specs := messyNightfallSpecs()
	if mutate != nil {
		mutate(specs)
	}
	paths, err := fixtures.Generate(filepath.Join(h.library, "nightfall"), specs...)
	if err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	return h, h.itemTitled(t, h.token, "Harbor Lights").Pid, paths[0]
}

// rematchAndWait asks for a match and lets the identify worker answer.
func (h *harness) rematchAndWait(t *testing.T, pid string) string {
	t.Helper()
	id := decodeStatus[RematchResult](t, h.postJSON(t, "/api/v1/items/"+pid+"/rematch", nil), 202, "rematch").ReviewEntryId
	drainMatches(t, h)
	return id
}

// An approved match is written into the files as well as the catalog,
// so a rescan reads back what the catalog holds and nothing stays owed.
func TestApprovedMatchIsWrittenToTheFiles(t *testing.T) {
	t.Parallel()
	h, pid, path := nightfallLibrary(t, nil)
	if e := getReview(t, h, h.rematchAndWait(t, pid)); e.Status != "auto-applied" {
		t.Fatalf("entry = %s, want auto-applied", e.Status)
	}
	if got := tagOnDisk(t, path, tag.Artist); got != "The Cardinal Waves" {
		t.Fatalf("artist on disk = %q, want the release's", got)
	}
	if got := tagOnDisk(t, path, tag.MBRecordingID); got != "00000000-0000-4000-8000-000000000001" {
		t.Fatalf("recording id on disk = %q, want the pairing's", got)
	}
	owed := decode[FileDiagnosticPage](t, get(t, h.ts, "/api/v1/library/diagnostics?code=tag_write_owed", h.token))
	for _, d := range owed.Diagnostics {
		if strings.Contains(d.Path, "nightfall") {
			t.Fatalf("a value is still owed to %s: %+v", d.Path, d)
		}
	}
}

// A revert writes the snapshot back to the files too, and a file's own
// recording id survives the round trip rather than being blanked.
func TestRevertWritesTheSnapshotBackAndKeepsAFilesOwnMBID(t *testing.T) {
	t.Parallel()
	const own = "00000000-0000-4000-8000-0000000000ff"
	h, pid, path := nightfallLibrary(t, func(specs []fixtures.Spec) {
		specs[0].Tags["MUSICBRAINZ_TRACKID"] = own
	})
	entry := h.rematchAndWait(t, pid)
	if got := tagOnDisk(t, path, tag.MBRecordingID); got == own {
		t.Fatal("the apply left the file's recording id alone")
	}
	wantStatus(t, h.postJSON(t, "/api/v1/review/queue/"+entry+"/revert", nil), 200, "revert")
	if got := tagOnDisk(t, path, tag.MBRecordingID); got != own {
		t.Fatalf("recording id on disk after the revert = %q, want the file's own", got)
	}
	if got := tagOnDisk(t, path, tag.Artist); got != "The Cardnal Waves" {
		t.Fatalf("artist on disk after the revert = %q, want the tag it had", got)
	}
	if item := decode[Item](t, get(t, h.ts, "/api/v1/items/"+pid, h.token)); item.Mbid == nil || *item.Mbid != own {
		t.Fatalf("catalog recording id after the revert = %v, want the file's own", item.Mbid)
	}
}

// A match applied in a read-only library changes the catalog and leaves
// the files as they are, owing them the values.
func TestAnAutoApplyInAReadOnlyLibraryStaysCatalogOnly(t *testing.T) {
	t.Parallel()
	h, pid, path := nightfallLibrary(t, nil)
	lib := decode[Libraries](t, get(t, h.ts, "/api/v1/libraries", h.token)).Libraries[0].Pid
	wantStatus(t, h.putJSON(t, "/api/v1/libraries/"+lib+"/read-only", map[string]any{"readOnly": true}), 200, "read-only")
	if e := getReview(t, h, h.rematchAndWait(t, pid)); e.Status != "auto-applied" {
		t.Fatalf("entry = %s, want auto-applied", e.Status)
	}
	if got := tagOnDisk(t, path, tag.Artist); got != "The Cardnal Waves" {
		t.Fatalf("artist on disk = %q, want the file untouched", got)
	}
	if item := decode[Item](t, get(t, h.ts, "/api/v1/items/"+pid, h.token)); item.Artist == nil || *item.Artist != "The Cardinal Waves" {
		t.Fatalf("catalog artist = %v, want the release's", item.Artist)
	}
	owed := decode[FileDiagnosticPage](t, get(t, h.ts, "/api/v1/library/diagnostics?code=tag_write_owed", h.token))
	var listed bool
	for _, d := range owed.Diagnostics {
		listed = listed || strings.Contains(d.Path, "nightfall")
	}
	if !listed {
		t.Fatalf("owed = %+v, want the file listed as owing the release's tags", owed.Diagnostics)
	}
}

// A file that cannot be written leaves the approval standing and says so
// by the file's name, never its place on the server.
func TestApprovalWarnsWithoutPathsWhenAFileCannotBeWritten(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritablePaths(t)
	h, pid, path := nightfallLibrary(t, nil)
	lib := decode[Libraries](t, get(t, h.ts, "/api/v1/libraries", h.token)).Libraries[0].Pid
	wantStatus(t, h.putJSON(t, "/api/v1/libraries/"+lib+"/matching", map[string]any{"mode": "review"}), 200, "review matching")
	entry := h.rematchAndWait(t, pid)
	dir := filepath.Dir(path)
	if err := os.Chmod(path, 0o444); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(dir, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(dir, 0o755); _ = os.Chmod(path, 0o644) })

	res := decodeStatus[ReviewDecideResult](t, h.postJSON(t, "/api/v1/review/queue/"+entry+"/decide",
		map[string]any{"action": "approve", "candidateMbid": "rel-nightfall"}), 200, "approve")
	if res.Entry.Status != "applied" || res.Warnings == nil {
		t.Fatalf("decide = %+v, want applied with warnings", res)
	}
	var named bool
	for _, w := range *res.Warnings {
		if strings.Contains(w, h.library) || strings.Contains(w, string(filepath.Separator)+"nightfall") {
			t.Fatalf("warning %q names a server path", w)
		}
		named = named || strings.HasPrefix(w, filepath.Base(path)+": tags not written")
	}
	if !named {
		t.Fatalf("warnings = %v, want the unwritable file named", *res.Warnings)
	}
}

// Marking an upload unofficial writes the release status into its file.
func TestUnofficialMarkIsWrittenToTheFile(t *testing.T) {
	t.Parallel()
	h := newHarnessWith(t, func(cfg *service.Config) {
		for i := range cfg.Roots {
			cfg.Roots[i].Managed = true
		}
	})
	paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
		Name: "bootleg", Codec: fixtures.CodecFLAC, Duration: 3 * time.Second,
		Tags: map[string]string{"TITLE": "Live Somewhere", "ARTIST": "Tape Trader", "ALBUM": "Bootleg"},
	})
	if err != nil {
		t.Fatal(err)
	}
	up := uploadFile(t, h, h.token, paths[0], "music", "")
	drainMatches(t, h)
	wantStatus(t, h.postJSON(t, "/api/v1/review/queue/"+*up.ReviewEntryId+"/decide",
		map[string]any{"action": "unofficial"}), 200, "unofficial")
	pid := *getReview(t, h, *up.ReviewEntryId).Tracks[0].Pid
	files := h.itemFiles(t, h.token, pid)
	if got := tagOnDisk(t, *files[0].Path, tag.Key("RELEASESTATUS")); got != "unofficial" {
		t.Fatalf("release status on disk = %q, want unofficial", got)
	}
}

// An unofficial mark on a rematched track in a read-only library stays
// in the catalog: the file is left alone, and no write is attempted to
// be reported as failed.
func TestAnUnofficialMarkInAReadOnlyLibraryStaysCatalogOnly(t *testing.T) {
	t.Parallel()
	h, pid, path := nightfallLibrary(t, nil)
	lib := decode[Libraries](t, get(t, h.ts, "/api/v1/libraries", h.token)).Libraries[0].Pid
	wantStatus(t, h.putJSON(t, "/api/v1/libraries/"+lib+"/matching", map[string]any{"mode": "review"}), 200, "review matching")
	entry := h.rematchAndWait(t, pid)
	wantStatus(t, h.putJSON(t, "/api/v1/libraries/"+lib+"/read-only", map[string]any{"readOnly": true}), 200, "read-only")

	res := decodeStatus[ReviewDecideResult](t, h.postJSON(t, "/api/v1/review/queue/"+entry+"/decide",
		map[string]any{"action": "unofficial"}), 200, "unofficial")
	if res.Warnings != nil {
		t.Fatalf("warnings = %v, want none: nothing was to be written", *res.Warnings)
	}
	if got := tagOnDisk(t, path, tag.Key("RELEASESTATUS")); got != "" {
		t.Fatalf("release status on disk = %q, want the file untouched", got)
	}
}

// A revert restores what the approval changed and nothing else: a total
// someone set and locked, which the approval's numbering left alone,
// keeps its value and its lock.
func TestARevertLeavesAFieldTheApprovalDidNotTouch(t *testing.T) {
	t.Parallel()
	h, pid, _ := nightfallLibrary(t, nil)
	ctx := context.Background()
	uc, err := h.svc.UserCtxByID(ctx, adminUserID(t, h))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := h.svc.EditItemMetadata(ctx, uc, pid, map[string]string{"track_total": "12"},
		service.MetadataEditParams{Lock: true}); err != nil {
		t.Fatal(err)
	}
	entry := h.rematchAndWait(t, pid)
	wantStatus(t, h.postJSON(t, "/api/v1/review/queue/"+entry+"/revert", nil), 200, "revert")
	md := decode[ItemMetadata](t, get(t, h.ts, "/api/v1/items/"+pid+"/metadata", h.token))
	if md.Fields["track_total"] != "12" || !slices.Contains(md.LockedFields, "track_total") {
		t.Fatalf("track total = %q, locked %v; want 12, still locked", md.Fields["track_total"], md.LockedFields)
	}
}

// A total the approval's numbering cleared is the approval's doing, and
// the revert puts it back.
func TestARevertRestoresATotalTheApprovalCleared(t *testing.T) {
	t.Parallel()
	h, pid, _ := nightfallLibrary(t, func(specs []fixtures.Spec) {
		specs[2].Tags["TRACKTOTAL"] = "2"
	})
	third := h.itemTitled(t, h.token, "Meridian Line").Pid
	read := func() string {
		return decode[ItemMetadata](t, get(t, h.ts, "/api/v1/items/"+third+"/metadata", h.token)).Fields["track_total"]
	}
	if got := read(); got != "2" {
		t.Fatalf("track total before = %q, want the file's 2", got)
	}
	entry := h.rematchAndWait(t, pid)
	if got := read(); got != "" {
		t.Fatalf("track total after the approval = %q, want it cleared by the new number 3", got)
	}
	wantStatus(t, h.postJSON(t, "/api/v1/review/queue/"+entry+"/revert", nil), 200, "revert")
	if got := read(); got != "2" {
		t.Fatalf("track total after the revert = %q, want 2 back", got)
	}
}

// A match over an album some of whose tracks sit in a read-only library
// is written into the files the other library takes; only the read-only
// ones stay as they are, owing the values.
func TestAMatchAcrossAReadOnlyLibraryWritesTheFilesItCan(t *testing.T) {
	t.Parallel()
	archive := t.TempDir()
	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.MatchSource = &cannedSource{releases: []*match.Release{nightfallRelease()}}
		cfg.Roots = append(cfg.Roots, service.Root{Name: "archive", Path: archive})
	})
	specs := messyNightfallSpecs()
	here, err := fixtures.Generate(filepath.Join(h.library, "nightfall"), specs[0])
	if err != nil {
		t.Fatal(err)
	}
	there, err := fixtures.Generate(filepath.Join(archive, "nightfall"), specs[1])
	if err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	for _, lib := range decode[Libraries](t, get(t, h.ts, "/api/v1/libraries", h.token)).Libraries {
		if lib.Name == "archive" {
			wantStatus(t, h.putJSON(t, "/api/v1/libraries/"+lib.Pid+"/read-only", map[string]any{"readOnly": true}), 200, "read-only")
		}
	}
	h.rematchAndWait(t, h.itemTitled(t, h.token, "Harbor Lights").Pid)
	if got := tagOnDisk(t, here[0], tag.Artist); got != "The Cardinal Waves" {
		t.Fatalf("artist on disk in the writable library = %q, want the release's", got)
	}
	if got := tagOnDisk(t, there[0], tag.Artist); got != "The Cardnal Waves" {
		t.Fatalf("artist on disk in the read-only library = %q, want the file untouched", got)
	}
}
