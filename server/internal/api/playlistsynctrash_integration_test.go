package api

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// A mirror-trash run counts what the trash took, not what it asked for:
// a removed entry whose folder refused the move keeps its file and stays
// owed, and the run after the folder is fixed trashes it.
func TestAMirrorTrashCountsOnlyWhatTheTrashTook(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritablePaths(t)
	media := t.TempDir()
	src := &fakeSyncSource{playlistURL: "https://tube.example/playlist?list=PLsync", title: "Sync Tapes"}
	entries := syncFixtureEntries(t, media, 3)
	src.setEntries(entries...)
	h := syncHarness(t, src)
	pl := createStaticPlaylist(t, h, "Mirror")
	wantStatus(t, h.putJSON(t, "/api/v1/playlists/"+pl.Pid+"/source", map[string]any{
		"url": src.playlistURL, "mode": "mirror-trash", "intervalHours": 6,
	}), 200, "bind mirror-trash")
	for _, run := range []string{"download", "attach"} {
		if task := syncNow(t, h, pl.Pid); task.State != "done" {
			t.Fatalf("the %s sync = %+v", run, task)
		}
	}
	if members := playlistItems(t, h, h.token, pl.Pid); len(members) != 3 {
		t.Fatalf("members = %v, want the three entries", entryPids(members))
	}
	held := h.itemTitled(t, h.token, entries[2].title)
	files := h.itemFiles(t, h.token, held.Pid)
	if len(files) != 1 || files[0].Path == nil {
		t.Fatalf("files of %s = %+v", entries[2].title, files)
	}
	locked := filepath.Dir(*files[0].Path)
	if err := os.Chmod(locked, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(locked, 0o755) })

	src.setEntries(entries[0])
	if task := syncNow(t, h, pl.Pid); task.State != "done" {
		t.Fatalf("the removal sync = %+v", task)
	}
	if run := getSource(t, h, pl.Pid).LastRun; run == nil || run.Trashed != 1 {
		t.Fatalf("removal run = %+v, want the one file the trash took", run)
	}
	if _, err := os.Stat(*files[0].Path); err != nil {
		t.Fatalf("the refused file moved: %v", err)
	}

	if err := os.Chmod(locked, 0o755); err != nil {
		t.Fatal(err)
	}
	if task := syncNow(t, h, pl.Pid); task.State != "done" {
		t.Fatalf("the sync after the fix = %+v", task)
	}
	if run := getSource(t, h, pl.Pid).LastRun; run == nil || run.Trashed != 1 {
		t.Fatalf("run after the fix = %+v, want the owed file trashed", run)
	}
	if _, err := os.Stat(*files[0].Path); err == nil {
		t.Fatal("the owed file is still in the library")
	}
}

// A removed entry whose item has a copy in a read-only library loses its
// own file to the trash and stays through the copy, as a delete leaves
// an item: the run counts it as staying, not trashed, and it stays owed,
// so the run after the flag is lifted trashes the copy too.
func TestAMirrorTrashCountsAnItemACopyKeepsAsStaying(t *testing.T) {
	t.Parallel()
	media := t.TempDir()
	archive := t.TempDir()
	src := &fakeSyncSource{playlistURL: "https://tube.example/playlist?list=PLsync", title: "Sync Tapes"}
	entries := syncFixtureEntries(t, media, 2)
	src.setEntries(entries...)
	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.SourceProviders = append(cfg.SourceProviders, src)
		for i := range cfg.Roots {
			cfg.Roots[i].Managed = cfg.Roots[i].Name != "archive"
		}
		cfg.AllowPrivateFeedHosts = true
	}, service.Root{Name: "archive", Path: archive})
	wantStatus(t, h.putJSON(t, "/api/v1/users/me/prefs", map[string]any{"identifyOptOut": true}), 200, "decline identify")
	pl := createStaticPlaylist(t, h, "Mirror")
	wantStatus(t, h.putJSON(t, "/api/v1/playlists/"+pl.Pid+"/source", map[string]any{
		"url": src.playlistURL, "mode": "mirror-trash", "intervalHours": 6,
	}), 200, "bind mirror-trash")
	for _, run := range []string{"download", "attach"} {
		if task := syncNow(t, h, pl.Pid); task.State != "done" {
			t.Fatalf("the %s sync = %+v", run, task)
		}
	}
	held := h.itemTitled(t, h.token, entries[1].title)
	files := h.itemFiles(t, h.token, held.Pid)
	if len(files) != 1 || files[0].Path == nil {
		t.Fatalf("files of %s = %+v", entries[1].title, files)
	}
	raw, err := os.ReadFile(*files[0].Path)
	if err != nil {
		t.Fatal(err)
	}
	kept := filepath.Join(archive, filepath.Base(*files[0].Path))
	if err := os.WriteFile(kept, raw, 0o644); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	if got := h.itemFiles(t, h.token, held.Pid); len(got) != 2 {
		t.Fatalf("files of %s with the archive's copy = %+v, want two", entries[1].title, got)
	}
	for _, lib := range decode[Libraries](t, get(t, h.ts, "/api/v1/libraries", h.token)).Libraries {
		if lib.Name == "archive" {
			wantStatus(t, h.putJSON(t, "/api/v1/libraries/"+lib.Pid+"/read-only", map[string]any{"readOnly": true}),
				200, "flag the archive read-only")
		}
	}

	src.setEntries(entries[0])
	if task := syncNow(t, h, pl.Pid); task.State != "done" {
		t.Fatalf("the removal sync = %+v", task)
	}
	if run := getSource(t, h, pl.Pid).LastRun; run == nil || run.Trashed != 0 {
		t.Fatalf("removal run = %+v, want the item its read-only copy keeps counted as staying", run)
	}
	if _, err := os.Stat(*files[0].Path); err == nil {
		t.Fatal("the item's own file was not trashed")
	}
	if _, err := os.Stat(kept); err != nil {
		t.Fatalf("the read-only copy moved: %v", err)
	}

	for _, lib := range decode[Libraries](t, get(t, h.ts, "/api/v1/libraries", h.token)).Libraries {
		if lib.Name == "archive" {
			wantStatus(t, h.putJSON(t, "/api/v1/libraries/"+lib.Pid+"/read-only", map[string]any{"readOnly": false}),
				200, "lift the archive's flag")
		}
	}
	if task := syncNow(t, h, pl.Pid); task.State != "done" {
		t.Fatalf("the sync after the flag is lifted = %+v", task)
	}
	if run := getSource(t, h, pl.Pid).LastRun; run == nil || run.Trashed != 1 {
		t.Fatalf("run after the flag is lifted = %+v, want the owed item trashed", run)
	}
	if _, err := os.Stat(kept); err == nil {
		t.Fatal("the owed copy is still in the archive")
	}
}

// A removed entry whose library is flagged read-only is not the trash's
// to take, and one such entry does not fail the run: it counts as
// staying, not trashed, and stays owed, so the run after the flag is
// lifted trashes it.
func TestAMirrorTrashLeavesWhatAReadOnlyLibraryHolds(t *testing.T) {
	t.Parallel()
	media := t.TempDir()
	src := &fakeSyncSource{playlistURL: "https://tube.example/playlist?list=PLsync", title: "Sync Tapes"}
	entries := syncFixtureEntries(t, media, 2)
	src.setEntries(entries...)
	h := syncHarness(t, src)
	pl := createStaticPlaylist(t, h, "Mirror")
	wantStatus(t, h.putJSON(t, "/api/v1/playlists/"+pl.Pid+"/source", map[string]any{
		"url": src.playlistURL, "mode": "mirror-trash", "intervalHours": 6,
	}), 200, "bind mirror-trash")
	for _, run := range []string{"download", "attach"} {
		if task := syncNow(t, h, pl.Pid); task.State != "done" {
			t.Fatalf("the %s sync = %+v", run, task)
		}
	}
	held := h.itemTitled(t, h.token, entries[1].title)
	files := h.itemFiles(t, h.token, held.Pid)
	if len(files) != 1 || files[0].Path == nil {
		t.Fatalf("files of %s = %+v", entries[1].title, files)
	}
	readOnly := func(on bool) {
		for _, lib := range decode[Libraries](t, get(t, h.ts, "/api/v1/libraries", h.token)).Libraries {
			wantStatus(t, h.putJSON(t, "/api/v1/libraries/"+lib.Pid+"/read-only", map[string]any{"readOnly": on}),
				200, "flag "+lib.Name)
		}
	}
	readOnly(true)

	src.setEntries(entries[0])
	if task := syncNow(t, h, pl.Pid); task.State != "done" {
		t.Fatalf("the removal sync = %+v", task)
	}
	if run := getSource(t, h, pl.Pid).LastRun; run == nil || run.Trashed != 0 {
		t.Fatalf("removal run = %+v, want nothing trashed from a read-only library", run)
	}
	if _, err := os.Stat(*files[0].Path); err != nil {
		t.Fatalf("the read-only library's file moved: %v", err)
	}

	readOnly(false)
	if task := syncNow(t, h, pl.Pid); task.State != "done" {
		t.Fatalf("the sync after the flag is lifted = %+v", task)
	}
	if run := getSource(t, h, pl.Pid).LastRun; run == nil || run.Trashed != 1 {
		t.Fatalf("run after the flag is lifted = %+v, want the owed file trashed", run)
	}
	if _, err := os.Stat(*files[0].Path); err == nil {
		t.Fatal("the owed file is still in the library")
	}
}
