package api

import (
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// m3uDoc is an M3U8 document of the given path lines.
func m3uDoc(paths ...string) string {
	return "#EXTM3U\n" + strings.Join(paths, "\n") + "\n"
}

// filePaths lists an item's files by path, as an administrator reads them.
func (h *harness) filePaths(t *testing.T, pid string) []string {
	t.Helper()
	var out []string
	for _, f := range h.itemFiles(t, h.token, pid) {
		if f.Path == nil {
			t.Fatalf("file %s of %s has no path for an administrator", f.FilePid, pid)
		}
		out = append(out, *f.Path)
	}
	return out
}

// playlistCount is how many playlists the caller can see.
func playlistCount(t *testing.T, h *harness, token string) int {
	t.Helper()
	return len(decodeStatus[PlaylistPage](t, reqAs(t, h, "GET", "/api/v1/playlists", token, nil), 200, "list playlists").Playlists)
}

// previewM3u previews a document as the caller.
func previewM3u(t *testing.T, h *harness, token, doc string) M3uPreview {
	t.Helper()
	return decodeStatus[M3uPreview](t, reqAs(t, h, "POST", "/api/v1/playlists/m3u/preview", token,
		map[string]any{"content": doc}), 200, "preview")
}

// The preview answers every line in document order - a match, a second
// file of the item before it, a path naming nothing - creates nothing,
// and the import that follows reads the document the same way.
func TestM3uPreviewReadsEveryLineAndCreatesNothing(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	copyFixture(t, h.library, "bravo", filepath.Join(h.library, "copies"))
	h.rescanAndWait(t)
	alpha := h.itemTitled(t, h.token, "Alpha Song").Pid
	bravo := h.itemTitled(t, h.token, "Bravo Song").Pid
	bravoFiles := h.filePaths(t, bravo)
	if len(bravoFiles) != 2 {
		t.Fatalf("bravo's files = %v, want the file and its copy", bravoFiles)
	}
	lines := []string{h.filePaths(t, alpha)[0], bravoFiles[0], bravoFiles[1], "/nowhere/missing.flac"}
	doc := m3uDoc(lines...)
	before := playlistCount(t, h, h.token)

	got := previewM3u(t, h, h.token, doc)
	want := []struct {
		outcome M3uPreviewEntryOutcome
		pid     string
	}{
		{M3uPreviewEntryOutcomeMatched, alpha},
		{M3uPreviewEntryOutcomeMatched, bravo},
		{M3uPreviewEntryOutcomeMerged, bravo},
		{M3uPreviewEntryOutcomeUnmatched, ""},
	}
	if got.Matched != 2 || got.Merged != 1 || got.Unmatched != 1 || len(got.Entries) != len(want) {
		t.Fatalf("preview = %+v, want 2 matched, 1 merged, 1 unmatched over 4 lines", got)
	}
	for i, w := range want {
		e := got.Entries[i]
		pid := ""
		if e.Item != nil {
			pid = e.Item.Pid
		}
		if e.Path != lines[i] || e.Outcome != w.outcome || pid != w.pid {
			t.Errorf("line %d = %s %s %q, want %s %s %q", i, e.Path, e.Outcome, pid, lines[i], w.outcome, w.pid)
		}
	}
	if n := playlistCount(t, h, h.token); n != before {
		t.Fatalf("playlists after the preview = %d, want %d", n, before)
	}

	res := decodeStatus[M3uImportResult](t, h.postJSON(t, "/api/v1/playlists/m3u",
		map[string]any{"name": "Previewed", "content": doc}), 201, "import")
	if res.Matched != got.Matched || res.Unmatched != got.Unmatched ||
		res.UnmatchedPaths == nil || !slices.Equal(*res.UnmatchedPaths, []string{"/nowhere/missing.flac"}) {
		t.Fatalf("import = %+v, want the preview's counts", res)
	}
	if members := entryPids(playlistItems(t, h, h.token, res.Playlist.Pid)); !slices.Equal(members, []string{alpha, bravo}) {
		t.Fatalf("imported members = %v, want the matched lines' items %v", members, []string{alpha, bravo})
	}
}

// A line naming an item in a library the caller is not granted reads
// unmatched and carries no item, in the preview and the import alike;
// the administrator, who sees both libraries, matches it.
func TestM3uPreviewReadsAHiddenItemAsUnmatched(t *testing.T) {
	t.Parallel()
	elsewhere := t.TempDir()
	if _, err := fixtures.Generate(elsewhere, fixtures.Spec{
		Name: "echo", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
		Tags: map[string]string{"TITLE": "Echo Song", "ARTIST": "Echo Artist", "ALBUM": "Elsewhere Album"},
	}); err != nil {
		t.Fatal(err)
	}
	h := newHarness(t, service.Root{Name: "elsewhere", Path: elsewhere})
	var home string
	for _, l := range decode[Libraries](t, get(t, h.ts, "/api/v1/libraries", h.token)).Libraries {
		if l.Name != "elsewhere" {
			home = l.Pid
		}
	}
	wantStatus(t, h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "gil", "password": testPassword,
		"libraryAccess": map[string]any{"mode": "granted", "libraryPids": []string{home}},
	}), 201, "a reader of the home library alone")
	gil := loginAs(t, h.ts, "gil", testPassword).Token
	alpha := h.itemTitled(t, h.token, "Alpha Song").Pid
	echo := h.itemTitled(t, h.token, "Echo Song").Pid
	doc := m3uDoc(h.filePaths(t, alpha)[0], h.filePaths(t, echo)[0])

	got := previewM3u(t, h, gil, doc)
	if got.Matched != 1 || got.Unmatched != 1 || len(got.Entries) != 2 ||
		got.Entries[0].Item == nil || got.Entries[0].Item.Pid != alpha ||
		got.Entries[1].Outcome != M3uPreviewEntryOutcomeUnmatched || got.Entries[1].Item != nil {
		t.Fatalf("gil's preview = %+v, want alpha matched and the hidden line unmatched with no item", got)
	}
	if admin := previewM3u(t, h, h.token, doc); admin.Matched != 2 || admin.Entries[1].Item == nil || admin.Entries[1].Item.Pid != echo {
		t.Fatalf("the administrator's preview = %+v, want both lines matched", admin)
	}
	res := decodeStatus[M3uImportResult](t, reqAs(t, h, "POST", "/api/v1/playlists/m3u", gil,
		map[string]any{"name": "Gil's", "content": doc}), 201, "gil's import")
	if res.Matched != got.Matched || res.Unmatched != got.Unmatched {
		t.Fatalf("gil's import = matched %d unmatched %d, want the preview's %d/%d",
			res.Matched, res.Unmatched, got.Matched, got.Unmatched)
	}
}

// The preview writes nothing, so the server's read-only switch does not
// stand in its way.
func TestM3uPreviewAnswersWhileReadOnly(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	settings := decode[AdminSettings](t, get(t, h.ts, "/api/v1/admin/settings", h.token))
	settings.ReadOnly = true
	wantStatus(t, h.putJSON(t, "/api/v1/admin/settings", settings), 200, "turn read-only on")
	alpha := h.itemTitled(t, h.token, "Alpha Song").Pid
	if got := previewM3u(t, h, h.token, m3uDoc(h.filePaths(t, alpha)[0])); got.Matched != 1 {
		t.Fatalf("preview while read-only = %+v, want the line matched", got)
	}
}

// Both readings of a document refuse one past the character bound the
// contract declares, one naming more paths than the cap, and one whose
// line is too long to read, as the caller's mistake rather than a server
// failure, and make no playlist doing so. The character bound counts
// characters as maxLength does, not bytes, and a document at the path
// cap is read.
func TestM3uDocumentsPastTheBoundAreRefused(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	before := playlistCount(t, h, h.token)
	for what, content := range map[string]string{
		// Two lines, each short enough to read, so only the character
		// count refuses it.
		"past the bound":  strings.Repeat("x", 524289) + "\n" + strings.Repeat("x", 524288),
		"past the cap":    strings.Repeat("a\n", 2001),
		"a line too long": strings.Repeat("a", 1<<20),
	} {
		for _, path := range []string{"/api/v1/playlists/m3u/preview", "/api/v1/playlists/m3u"} {
			e := decodeStatus[Error](t, h.postJSON(t, path, map[string]any{"name": "Too long", "content": content}),
				400, what+" at "+path)
			if e.Code != "invalid-request" {
				t.Errorf("%s at %s = %+v, want invalid-request", what, path, e)
			}
			if what == "past the cap" && !strings.Contains(e.Message, "in parts") {
				t.Errorf("past the cap at %s says %q, want the way forward named", path, e.Message)
			}
		}
	}
	if n := playlistCount(t, h, h.token); n != before {
		t.Fatalf("playlists after the refusals = %d, want %d", n, before)
	}

	// About two megabytes, and under the bound in characters.
	wide := strings.Repeat(strings.Repeat("\u00e9", 262143)+"\n", 3) + strings.Repeat("\u00e9", 262143)
	if got := previewM3u(t, h, h.token, wide); got.Unmatched != 4 || len(got.Entries) != 4 {
		t.Fatalf("a multi-byte document under the bound = %d unmatched of %d lines, want 4 of 4", got.Unmatched, len(got.Entries))
	}
	if got := previewM3u(t, h, h.token, strings.Repeat("a\n", 2000)); got.Unmatched != 2000 {
		t.Fatalf("a document at the path cap = %d unmatched, want 2000", got.Unmatched)
	}
}
