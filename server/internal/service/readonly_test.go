package service

import (
	"bytes"
	"context"
	"os"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
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

// The trash lives under each library's root, so a read-only library's
// trashed files are neither restored nor purged, by hand or by the
// retention sweep.
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
	setLibrariesReadOnly(t, ctx, svc, uc, true)
	if err := svc.RestoreTrashEntry(ctx, uc, entries[0].ID); KindOf(err) != KindReadOnly {
		t.Errorf("restore: err = %v, want read-only", err)
	}
	if _, err := svc.PurgeTrashEntry(ctx, uc, entries[0].ID); KindOf(err) != KindReadOnly {
		t.Errorf("purge: err = %v, want read-only", err)
	}
	if _, err := svc.EmptyTrash(ctx, uc); KindOf(err) != KindReadOnly {
		t.Errorf("empty: err = %v, want read-only", err)
	}
	if got, err := svc.PurgeTrashOlderThan(ctx, time.Nanosecond); err != nil || got.Purged != 0 {
		t.Errorf("retention sweep = %+v (%v), want nothing purged", got, err)
	}
	if after, err := svc.TrashEntries(ctx, uc, false, 0); err != nil || len(after) != 2 {
		t.Fatalf("trash after = %+v (%v), want both tracks still there", after, err)
	}
}

// An album, release group or artist edit can write into files in any
// library, so while one library is read-only the write-back is refused
// and a catalog-only edit still goes through.
func TestEntityWriteBackIsRefusedWhileALibraryIsReadOnly(t *testing.T) {
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
	writeBack := MetadataEditParams{WriteBack: true}
	if _, err := svc.EditEntity(ctx, "album", album, map[string]string{"label": "Nowhere"}, writeBack); KindOf(err) != KindReadOnly {
		t.Errorf("edit: err = %v, want read-only", err)
	}
	if _, err := svc.RenameEntity(ctx, "album", album, map[string]string{"album": "Roam"}, writeBack); KindOf(err) != KindReadOnly {
		t.Errorf("rename: err = %v, want read-only", err)
	}
	if _, err := svc.SetEntityArtwork(ctx, uc, "album", album, "front", coverPNG(t, 40), true); KindOf(err) != KindReadOnly {
		t.Errorf("cover: err = %v, want read-only", err)
	}
	if after, err := os.ReadFile(path); err != nil || !bytes.Equal(before, after) {
		t.Fatalf("an entity write reached a read-only library's file (%v)", err)
	}
	if _, err := svc.EditEntity(ctx, "album", album, map[string]string{"label": "Nowhere"}, MetadataEditParams{}); err != nil {
		t.Fatalf("a catalog-only edit: %v", err)
	}
}

// A read-only flag left by a library the catalog no longer has, which a
// catalog reset leaves behind, does not stop tag write-back.
func TestAForgottenLibrarysFlagLeavesWriteBackOn(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _, _ := managedTrackFixture(t)
	for key, value := range map[string]string{
		settingEnrichWriteTags:        "true",
		readOnlyLibPrefix + "gone-01": "true",
	} {
		if err := svc.db.SettingSet(ctx, key, value, time.Now().UnixNano()); err != nil {
			t.Fatal(err)
		}
	}
	svc.loadRuntimeToggles(ctx)
	if !svc.enrichWritesTags(ctx) {
		t.Fatal("write-back is off over a library the catalog does not have")
	}
	setLibrariesReadOnly(t, ctx, svc, uc, true)
	if svc.enrichWritesTags(ctx) {
		t.Fatal("write-back is on while a library is read-only")
	}
	setLibrariesReadOnly(t, ctx, svc, uc, false)
	setServerReadOnly(t, ctx, svc, true)
	if svc.enrichWritesTags(ctx) {
		t.Fatal("write-back is on while the server is read-only")
	}
}
