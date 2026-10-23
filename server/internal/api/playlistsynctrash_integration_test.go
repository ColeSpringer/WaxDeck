package api

import (
	"os"
	"path/filepath"
	"testing"
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
