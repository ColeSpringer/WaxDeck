package service

import (
	"bytes"
	"context"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"

	"github.com/colespringer/waxdeck/fixtures"
)

// twoTrackFixture opens a library holding two scanned tracks and
// answers their paths and API pids, the pids in path order.
func twoTrackFixture(t *testing.T) (context.Context, *Library, *UserCtx, []string, []string) {
	t.Helper()
	var paths []string
	ctx, svc, uc := openEnrichFixture(t, func(c *Config) {
		var err error
		if paths, err = fixtures.Generate(c.Roots[0].Path,
			fixtures.Spec{Name: "a-lossless", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
				Tags: map[string]string{"TITLE": "Twice", "ARTIST": "Echo", "ALBUM": "Again", "TRACKNUMBER": "1"}},
			fixtures.Spec{Name: "b-lossy", Codec: fixtures.CodecMP3, Duration: 2 * time.Second,
				Tags: map[string]string{"TITLE": "Twice", "ARTIST": "Echo", "ALBUM": "Again", "TRACKNUMBER": "1"}},
		); err != nil {
			t.Fatal(err)
		}
	})
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	items, err := svc.lib.Query(ctx, query.New(query.EntityItems).Build(), "")
	if err != nil || len(items) != 2 {
		t.Fatalf("items = %v (%v), want the two tracks", items, err)
	}
	pids := make([]string, len(paths))
	for _, it := range items {
		for i, p := range paths {
			if string(it.Path) == p {
				pids[i] = apiPID(PrefixTrack, it.PID)
			}
		}
	}
	return ctx, svc, uc, paths, pids
}

// Resolving an upgrade trashes files, so a read-only library refuses it.
func TestResolvingAnUpgradeInAReadOnlyLibraryIsRefused(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, paths, pids := twoTrackFixture(t)
	setLibrariesReadOnly(t, ctx, svc, uc, true)
	if _, err := svc.ResolveUpgrade(ctx, uc, pids[0], []string{pids[1]}); KindOf(err) != KindReadOnly {
		t.Fatalf("err = %v, want read-only", err)
	}
	if _, err := os.Stat(paths[1]); err != nil {
		t.Fatalf("the lossy copy went to the trash: %v", err)
	}
}

// The trash lives under each library's root: a read-only library's
// entries are neither restored nor purged by hand, and emptying the trash
// or the retention sweep leave them and count them.
func TestAReadOnlyLibrarysTrashStaysAsItIs(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _, pids := twoTrackFixture(t)
	if _, err := svc.DeleteItems(ctx, uc, pids, "trash", false); err != nil {
		t.Fatal(err)
	}
	entries, err := svc.TrashEntries(ctx, uc, false, 0)
	if err != nil || len(entries) != 2 {
		t.Fatalf("trash = %+v (%v), want both tracks", entries, err)
	}
	lib := svc.libraryRoots()[0]
	for _, e := range entries {
		if e.LibraryPID != apiPID(PrefixLibrary, model.PID(lib.PID)) || e.LibraryName != lib.Name {
			t.Errorf("entry library = %s %q, want %s %q", e.LibraryPID, e.LibraryName, lib.PID, lib.Name)
		}
	}
	setLibrariesReadOnly(t, ctx, svc, uc, true)
	if err := svc.RestoreTrashEntry(ctx, uc, entries[0].ID); KindOf(err) != KindReadOnly {
		t.Errorf("restore: err = %v, want read-only", err)
	}
	if _, err := svc.PurgeTrashEntry(ctx, uc, entries[0].ID); KindOf(err) != KindReadOnly {
		t.Errorf("purge: err = %v, want read-only", err)
	}
	if got, err := svc.EmptyTrash(ctx, uc); err != nil || got.Purged != 0 || got.SkippedReadOnly != 2 {
		t.Errorf("empty = %+v (%v), want both entries skipped as read-only", got, err)
	}
	if got, err := svc.PurgeTrashOlderThan(ctx, time.Nanosecond); err != nil || got.Purged != 0 || got.SkippedReadOnly != 2 {
		t.Errorf("retention sweep = %+v (%v), want both entries skipped as read-only", got, err)
	}
	if after, err := svc.TrashEntries(ctx, uc, false, 0); err != nil || len(after) != 2 {
		t.Fatalf("trash after = %+v (%v), want both tracks still there", after, err)
	}
}

// An entity edit writes back wherever it may: a read-only library's file
// keeps its bytes and comes back refused, and the catalog edit stands.
func TestAnEntityWriteBackLeavesAReadOnlyLibrarysFileAlone(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, path, pid := readOnlyFixture(t)
	it, err := svc.getVisibleItem(ctx, uc, pid)
	if err != nil {
		t.Fatal(err)
	}
	album := apiPID(PrefixAlbum, it.AlbumPID)
	before, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	refused := func(what string, failures []WriteBackFailureDTO, err error) {
		t.Helper()
		if err != nil || len(failures) != 1 || !strings.Contains(failures[0].Reason, "read-only") {
			t.Errorf("%s = %+v (%v), want the file refused as read-only", what, failures, err)
		}
	}
	writeBack := MetadataEditParams{WriteBack: true}
	out, err := svc.EditEntity(ctx, "album", album, map[string]string{"label": "Nowhere"}, writeBack)
	refused("edit", out.Failures, err)
	renamed, err := svc.RenameEntity(ctx, "album", album, map[string]string{"album": "Roam"}, writeBack)
	refused("rename", renamed.Failures, err)
	out, err = svc.SetEntityArtwork(ctx, uc, "album", album, "front", coverPNG(t, 40), true)
	refused("cover", out.Failures, err)
	if after, err := os.ReadFile(path); err != nil || !bytes.Equal(before, after) {
		t.Fatalf("an entity write reached a read-only library's file (%v)", err)
	}
	if got, err := svc.getVisibleItem(ctx, uc, pid); err != nil || got.Album != "Roam" {
		t.Errorf("album after the rename = %q (%v), want the catalog edit standing", got.Album, err)
	}
}

// The catalog owns the flag: one flipped by the CLI reaches the write
// checks through the feed, the listing reports it, and a flag the server
// kept in its settings before is dropped at start.
func TestTheCatalogsReadOnlyFlagIsTheOneThatCounts(t *testing.T) {
	t.Parallel()
	ctx, svc, _, _, _ := managedTrackFixture(t)
	lib := svc.libraryRoots()[0]
	if _, err := svc.lib.SetLibraryReadOnly(ctx, model.PID(lib.PID), true); err != nil {
		t.Fatal(err)
	}
	waitFor(t, func() bool { return svc.libraryReadOnly(lib.PID) },
		"the CLI's flag reaching the write checks")
	if err := svc.CheckWritable(ctx, lib.PID); KindOf(err) != KindReadOnly {
		t.Errorf("a write into the library = %v, want read-only", err)
	}
	infos, err := svc.Libraries(ctx)
	if err != nil || len(infos) != 1 || !infos[0].ReadOnly || !infos[0].Managed || infos[0].Profile == "" {
		t.Errorf("libraries = %+v (%v), want the library read-only, managed, with its profile", infos, err)
	}
	if err := svc.db.SettingSet(ctx, settingEnrichWriteTags, "true", time.Now().UnixNano()); err != nil {
		t.Fatal(err)
	}
	svc.loadRuntimeToggles(ctx)
	if !svc.enrichWritesTags(ctx) {
		t.Error("write-back is off while one library is read-only; the catalog skips its files")
	}
	setServerReadOnly(t, ctx, svc, true)
	if svc.enrichWritesTags(ctx) {
		t.Error("write-back is on while the server is read-only")
	}
}

// A library flag set anywhere, the CLI or the console, tells every
// account to re-read the libraries once; a refresh that changes nothing
// tells nobody.
func TestALibraryFlagTellsEveryAccountOnce(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _, _ := managedTrackFixture(t)
	since, err := svc.MintServerCursor(ctx)
	if err != nil {
		t.Fatal(err)
	}
	// markers walks the stream the way a client does, moving since on.
	markers := func() (n int) {
		delta, err := svc.SyncServerDelta(ctx, uc, since, 100)
		if err != nil {
			t.Fatal(err)
		}
		since = delta.NextSince
		for _, e := range delta.Events {
			if e.Kind == eventLibraries {
				n++
			}
		}
		return n
	}
	svc.refreshLibraryState(ctx)
	if n := markers(); n != 0 {
		t.Fatalf("markers before any change = %d, want none", n)
	}
	lib := svc.libraryRoots()[0]
	if _, err := svc.lib.SetLibraryReadOnly(ctx, model.PID(lib.PID), true); err != nil {
		t.Fatal(err)
	}
	waitFor(t, func() bool { return markers() == 1 }, "the CLI's flag telling every account")
	if err := svc.LibraryReadOnlySet(ctx, uc, apiPID(PrefixLibrary, model.PID(lib.PID)), false); err != nil {
		t.Fatal(err)
	}
	waitFor(t, func() bool { return markers() == 1 }, "the console's flag telling every account")
	svc.refreshLibraryState(ctx)
	if n := markers(); n != 0 {
		t.Errorf("markers after a refresh that changed nothing = %d, want none", n)
	}
}
