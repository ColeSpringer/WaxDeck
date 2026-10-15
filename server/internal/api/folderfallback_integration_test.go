package api

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
)

// A library's folder fallback is the catalog's: switched on, an untagged
// file two folders down is named from them on its next full read; a
// managed library refuses it, since its folders are the catalog's own.
func TestALibrarysFolderFallbackIsTheCatalogs(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	lib := decode[Libraries](t, get(t, h.ts, "/api/v1/libraries", h.token)).Libraries[0]
	if lib.FolderFallback == nil || *lib.FolderFallback {
		t.Fatalf("library = %+v, want the fallback reported off", lib)
	}
	dir := filepath.Join(h.library, "Folder Artist", "Folder Album (2001)")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if _, err := fixtures.Generate(dir, fixtures.Spec{
		Name: "untagged", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
		Tags: map[string]string{"TITLE": "Nameless"},
	}); err != nil {
		t.Fatal(err)
	}

	got := decodeStatus[LibraryFolderFallback](t, h.putJSON(t, "/api/v1/libraries/"+lib.Pid+"/folder-fallback",
		map[string]any{"folderFallback": true}), 200, "switch the fallback on")
	if !got.FolderFallback || got.LibraryPid == nil || *got.LibraryPid != lib.Pid {
		t.Fatalf("answer = %+v, want it on", got)
	}
	h.rescanAndWait(t)
	item := decode[Item](t, get(t, h.ts, "/api/v1/items/"+h.itemTitled(t, h.token, "Nameless").Pid, h.token))
	if item.Artist == nil || *item.Artist != "Folder Artist" || item.Album == nil || *item.Album != "Folder Album" {
		t.Fatalf("named = %v / %v, want the folders' names", item.Artist, item.Album)
	}
	if now := decode[Libraries](t, get(t, h.ts, "/api/v1/libraries", h.token)).Libraries[0]; now.FolderFallback == nil || !*now.FolderFallback {
		t.Fatalf("library = %+v, want the fallback reported on", now)
	}

	managed := decodeStatus[Library](t, h.postJSON(t, "/api/v1/libraries", map[string]any{
		"name": "placed", "path": t.TempDir(), "managed": true,
	}), 201, "a managed library")
	refusal := decodeStatus[Error](t, h.putJSON(t, "/api/v1/libraries/"+managed.Pid+"/folder-fallback",
		map[string]any{"folderFallback": true}), 400, "a managed library's fallback")
	if refusal.Message != "only a library that keeps its files in place takes a folder fallback; a managed library names its folders itself" {
		t.Fatalf("refusal = %q, want it in WaxDeck's words", refusal.Message)
	}
}
