package service

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/port"

	"github.com/colespringer/waxdeck/fixtures"
)

// journalReach is two libraries and a reader granted the first alone, the
// shape the library journal's tombstone decisions are pinned in.
type journalReach struct {
	ctx                context.Context
	svc                *Library
	admin, reader      *UserCtx
	seenDir, unseenDir string
}

func journalSong(name, title string) fixtures.Spec {
	return fixtures.Spec{Name: name, Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
		Tags: map[string]string{"TITLE": title, "ARTIST": "Journal Band", "ALBUM": title}}
}

func newJournalReach(t *testing.T) journalReach {
	t.Helper()
	seenDir, unseenDir := t.TempDir(), t.TempDir()
	if _, err := fixtures.Generate(seenDir, journalSong("seen", "Seen Song")); err != nil {
		t.Fatal(err)
	}
	if _, err := fixtures.Generate(unseenDir, journalSong("unseen", "Unseen Song")); err != nil {
		t.Fatal(err)
	}
	ctx, svc, admin := managedUploadFixture(t, Root{Name: "seen", Path: seenDir}, Root{Name: "unseen", Path: unseenDir})
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	var seenLib string
	for _, r := range svc.libraryRoots() {
		if r.Name == "seen" {
			seenLib = r.PID
		}
	}
	acct, err := svc.CreateAccount(ctx, AccountCreate{
		Username: "reader", Password: "correct-horse", AccessMode: "granted",
		LibraryPIDs: []string{apiPID(PrefixLibrary, model.PID(seenLib))},
	})
	if err != nil {
		t.Fatal(err)
	}
	reader, err := svc.UserCtx(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	return journalReach{ctx: ctx, svc: svc, admin: admin, reader: reader, seenDir: seenDir, unseenDir: unseenDir}
}

// item answers the api pid of the item titled title, waiting out a scan
// still running.
func (r journalReach) item(t *testing.T, title string) string {
	t.Helper()
	for deadline := time.Now().Add(30 * time.Second); ; time.Sleep(25 * time.Millisecond) {
		page, err := r.svc.Items(r.ctx, r.admin, ItemFilter{}, "", 200)
		if err != nil {
			t.Fatal(err)
		}
		for _, it := range page.Items {
			if it.Title == title {
				return it.PID
			}
		}
		if time.Now().After(deadline) {
			t.Fatalf("no item titled %q", title)
		}
	}
}

// grantedReader makes an account granted one library and answers its
// context.
func grantedReader(t *testing.T, ctx context.Context, svc *Library, name, libPID string) *UserCtx {
	t.Helper()
	acct, err := svc.CreateAccount(ctx, AccountCreate{
		Username: name, Password: "correct-horse", AccessMode: "granted",
		LibraryPIDs: []string{apiPID(PrefixLibrary, model.PID(libPID))},
	})
	if err != nil {
		t.Fatal(err)
	}
	uc, err := svc.UserCtx(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	return uc
}

// snapshot mirrors the catalog as the reader and answers its cursor.
func (r journalReach) snapshot(t *testing.T) string {
	t.Helper()
	return r.snapshotAs(t, r.reader)
}

// snapshotAs mirrors the catalog as uc and answers its cursor.
func (r journalReach) snapshotAs(t *testing.T, uc *UserCtx) string {
	t.Helper()
	cursor := ""
	for {
		page, err := r.svc.SyncCatalogSnapshot(r.ctx, uc, cursor, 500)
		if err != nil {
			t.Fatal(err)
		}
		if page.NextCursor == "" {
			return page.NextSince
		}
		cursor = page.NextCursor
	}
}

// delta reads the reader's changes since a cursor, to the end, as op and
// reason by bare pid.
func (r journalReach) delta(t *testing.T, since string) map[model.PID]string {
	t.Helper()
	return r.deltaAs(t, r.reader, since)
}

// deltaAs reads uc's changes since a cursor, to the end.
func (r journalReach) deltaAs(t *testing.T, uc *UserCtx, since string) map[model.PID]string {
	t.Helper()
	out := map[model.PID]string{}
	for {
		d, err := r.svc.SyncCatalogDelta(r.ctx, uc, since, 500)
		if err != nil {
			t.Fatal(err)
		}
		for _, e := range d.Entries {
			_, pid, _ := parseAPIPID(e.PID)
			out[pid] = e.Op + " " + e.Reason
		}
		since = d.NextSince
		if !d.More {
			return out
		}
	}
}

// startJournalOver makes the library journal start over from the catalog
// as it stands, as a fresh database or a replaced catalog does, walking
// as its follower would.
func (r journalReach) startJournalOver(t *testing.T) {
	t.Helper()
	r.svc.libJournal.mu.Lock()
	r.svc.libJournal.stale = true
	r.svc.libJournal.mu.Unlock()
	if _, err := r.svc.journalCatchUp(r.ctx); err != nil {
		t.Fatal(err)
	}
}

// move re-homes a file from one library's folder to another's and scans.
func (r journalReach) move(t *testing.T, name, from, to string) {
	t.Helper()
	raw, err := os.ReadFile(filepath.Join(from, name))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(to, name), raw, 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(filepath.Join(from, name)); err != nil {
		t.Fatal(err)
	}
	if _, err := r.svc.lib.Scan(r.ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
}

func bareOf(t *testing.T, apiPID string) model.PID {
	t.Helper()
	_, pid, ok := parseAPIPID(apiPID)
	if !ok {
		t.Fatalf("bad pid %q", apiPID)
	}
	return pid
}

// An item in the trash when the library journal starts over is placed in
// the library its trash rows name, so purging it later sends nothing to a
// reader that library is not granted to. The reader's own track purged
// still goes.
func TestTheJournalPlacesWhatTheTrashHoldsWhenItStartsOver(t *testing.T) {
	t.Parallel()
	r := newJournalReach(t)
	unseen, seen := r.item(t, "Unseen Song"), r.item(t, "Seen Song")
	if _, err := r.svc.DeleteItems(r.ctx, r.admin, []string{unseen, seen}, "trash", false); err != nil {
		t.Fatal(err)
	}
	r.startJournalOver(t)
	since := r.snapshot(t)
	entries, err := r.svc.TrashEntries(r.ctx, r.admin, false, 0)
	if err != nil || len(entries) != 2 {
		t.Fatalf("trash = %+v, %v; want both tracks", entries, err)
	}
	for _, e := range entries {
		if _, err := r.svc.PurgeTrashEntry(r.ctx, r.admin, e.ID); err != nil {
			t.Fatal(err)
		}
	}
	got := r.delta(t, since)
	if g, sent := got[bareOf(t, unseen)]; sent {
		t.Errorf("purging the other library's trashed track sends the reader %q", g)
	}
	if g := got[bareOf(t, seen)]; g != "delete removed" {
		t.Errorf("purging the reader's own trashed track sends %q, want a removed tombstone", g)
	}
}

// An item its library's removal archived, with nothing in the trash, sat in
// no library when the journal started over, so its return with the library
// sends nothing to a reader that library is not granted to.
func TestTheJournalPlacesAnItemItsLibraryTookAwayNowhere(t *testing.T) {
	t.Parallel()
	r := newJournalReach(t)
	spareDir := t.TempDir()
	if _, err := fixtures.Generate(spareDir, journalSong("spare", "Spare Song")); err != nil {
		t.Fatal(err)
	}
	info, err := r.svc.AddLibrary(r.ctx, r.admin, AddLibraryInput{Name: "spare", Path: spareDir})
	if err != nil {
		t.Fatal(err)
	}
	spare := r.item(t, "Spare Song")
	var job Job
	for deadline := time.Now().Add(time.Minute); ; time.Sleep(20 * time.Millisecond) {
		if job, err = r.svc.RemoveLibrary(r.ctx, r.admin, info.PID); err == nil {
			break
		}
		if KindOf(err) != KindCatalogBusy || time.Now().After(deadline) {
			t.Fatal(err)
		}
	}
	waitForJob(t, r.ctx, r.svc, bareOf(t, job.PID))
	r.startJournalOver(t)
	since := r.snapshot(t)
	if _, err := r.svc.AddLibrary(r.ctx, r.admin, AddLibraryInput{Name: "spare", Path: spareDir}); err != nil {
		t.Fatal(err)
	}
	for deadline := time.Now().Add(30 * time.Second); ; time.Sleep(25 * time.Millisecond) {
		it, err := r.svc.lib.Get(r.ctx, bareOf(t, spare))
		if err == nil && !archived(it) {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("the re-added library's track never came back")
		}
	}
	if g, sent := r.delta(t, since)[bareOf(t, spare)]; sent {
		t.Errorf("the track coming back with a library the reader is not granted sends it %q", g)
	}
}

// itemChangeRows counts the change rows naming one item after a position.
func itemChangeRows(t *testing.T, ctx context.Context, svc *Library, pid model.PID, after int64) int {
	t.Helper()
	n := 0
	for seq := after; ; {
		rows, err := svc.lib.Changes(ctx, seq)
		if err != nil {
			t.Fatal(err)
		}
		if len(rows) == 0 {
			return n
		}
		for _, ch := range rows {
			if ch.EntityType == "item" && ch.EntityPID == pid {
				n++
			}
		}
		seq = rows[len(rows)-1].Seq
	}
}

// A file re-homed between two libraries writes several change rows for
// its item in one scan, which the journal reads as one placement, where
// the item sits then. A reader granted neither library is sent nothing
// for it, one granted the library it left its tombstone, one granted the
// library it reached the item. The source root is padded: a scan keeps a
// root's only file where it was when it vanishes.
func TestARealReHomeIsTombstonedOnlyToTheLibraryItLeft(t *testing.T) {
	t.Parallel()
	seenDir, leftDir, rightDir := t.TempDir(), t.TempDir(), t.TempDir()
	if _, err := fixtures.Generate(seenDir, journalSong("seen", "Seen Song")); err != nil {
		t.Fatal(err)
	}
	specs := []fixtures.Spec{journalSong("mover", "Mover Song")}
	for i := range 5 {
		specs = append(specs, journalSong(fmt.Sprintf("pad%d", i), fmt.Sprintf("Pad %d", i)))
	}
	if _, err := fixtures.Generate(leftDir, specs...); err != nil {
		t.Fatal(err)
	}
	if _, err := fixtures.Generate(rightDir, journalSong("right", "Right Song")); err != nil {
		t.Fatal(err)
	}
	ctx, svc, admin := managedUploadFixture(t,
		Root{Name: "seen", Path: seenDir}, Root{Name: "left", Path: leftDir}, Root{Name: "right", Path: rightDir})
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	libs := map[string]string{}
	for _, root := range svc.libraryRoots() {
		libs[root.Name] = root.PID
	}
	r := journalReach{ctx: ctx, svc: svc, admin: admin}
	mover := bareOf(t, r.item(t, "Mover Song"))
	readers, since := map[string]*UserCtx{}, map[string]string{}
	for _, name := range []string{"seen", "left", "right"} {
		readers[name] = grantedReader(t, ctx, svc, name+"-reader", libs[name])
		since[name] = r.snapshotAs(t, readers[name])
	}
	head, err := svc.lib.LatestChangeSeq(ctx)
	if err != nil {
		t.Fatal(err)
	}
	r.move(t, "mover.flac", leftDir, rightDir)
	settleCatalogFeed(t, svc)
	if it, err := svc.lib.Get(ctx, mover); err != nil || string(it.LibraryPID) != libs["right"] {
		t.Fatalf("after the move the track sits in %q (%v), want the library it was moved to", it.LibraryPID, err)
	}
	if n := itemChangeRows(t, ctx, svc, mover, head); n < 2 {
		t.Fatalf("the re-home wrote %d change row(s) for the item, want several", n)
	}
	got := map[string]string{}
	for name, uc := range readers {
		got[name] = r.deltaAs(t, uc, since[name])[mover]
	}
	if g := got["seen"]; g != "" {
		t.Errorf("the reader granted neither library is sent %q for the re-homed track, want nothing", g)
	}
	if g := got["left"]; g != "delete hidden" {
		t.Errorf("the reader granted the library the track left is sent %q, want a hidden tombstone", g)
	}
	if g := got["right"]; g != "upsert " {
		t.Errorf("the reader granted the library the track reached is sent %q, want an upsert", g)
	}
}

// A journal held off through a scan of thousands of files into a library
// the reader is not granted, a backlog larger than one of its reads holds
// many times over, is caught up placing every item by its library: none
// is marked unsure, and the reader is sent nothing.
func TestAJournalFarBehindPlacesEveryItemItReads(t *testing.T) {
	t.Parallel()
	r := newJournalReach(t)
	since := r.snapshot(t)
	c, ok := decodeCatalogCursor(since)
	if !ok {
		t.Fatalf("bad cursor %q", since)
	}
	const n = 1600
	specs := make([]fixtures.Spec, 0, n)
	for i := range n {
		specs = append(specs, fixtures.Spec{Name: fmt.Sprintf("u%04d", i), Codec: fixtures.CodecFLAC, Duration: 100 * time.Millisecond,
			Tags: map[string]string{"TITLE": fmt.Sprintf("Unseen %04d", i), "ARTIST": fmt.Sprintf("Unseen Band %04d", i), "ALBUM": fmt.Sprintf("Unseen Album %04d", i)}})
	}
	if _, err := fixtures.Generate(r.unseenDir, specs...); err != nil {
		t.Fatal(err)
	}
	r.svc.libJournal.mu.Lock()
	_, err := r.svc.lib.Scan(r.ctx, waxbin.ScanRequest{})
	r.svc.libJournal.mu.Unlock()
	if err != nil {
		t.Fatal(err)
	}
	settleCatalogFeed(t, r.svc)
	rows := 0
	seen := map[model.PID]bool{}
	var pids []string
	for seq := c.seq; ; {
		ch, err := r.svc.lib.Changes(r.ctx, seq)
		if err != nil {
			t.Fatal(err)
		}
		if len(ch) == 0 {
			break
		}
		for _, x := range ch {
			rows++
			if x.EntityType == "item" && !seen[x.EntityPID] {
				seen[x.EntityPID] = true
				pids = append(pids, string(x.EntityPID))
			}
		}
		seq = ch[len(ch)-1].Seq
	}
	if rows <= 5000 {
		t.Fatalf("the scan wrote %d change rows, want a backlog past 5000", rows)
	}
	if _, err := r.svc.journalLibraries(r.ctx, journalToHead); err != nil {
		t.Fatal(err)
	}
	around, err := r.svc.db.ItemLibrariesAround(r.ctx, pids, c.seq)
	if err != nil {
		t.Fatal(err)
	}
	unsure, unplaced := 0, 0
	for _, pid := range pids {
		h := around[pid]
		switch {
		case slices.Contains(h.AtCursor, journalUnsure) || slices.Contains(h.Since, journalUnsure):
			unsure++
		case !h.Placed && len(h.Since) == 0:
			unplaced++
		}
	}
	if unsure > 0 || unplaced > 0 {
		t.Errorf("after catching up on %d changes the journal marks %d of %d items unsure and places %d nowhere, want every item placed", rows, unsure, len(pids), unplaced)
	}
	if got := r.delta(t, since); len(got) != 0 {
		t.Errorf("the reader's delta holds %d entries for a scan into a library it is not granted, want none", len(got))
	}
}

// A start-over walk that fails is the journal's follower's to try again,
// on its own schedule: a restricted caller's deltas meanwhile fail without
// walking (devices retry about once a second while it lasts), and once
// the walk goes through the deltas answer again.
func TestAFailingJournalWalkIsNotRerunPerClientRetry(t *testing.T) {
	t.Parallel()
	r := newJournalReach(t)
	since := r.snapshot(t)
	var walks atomic.Int32
	r.svc.libJournal.mu.Lock()
	r.svc.journalWalkHook = func() error {
		walks.Add(1)
		return errors.New("the walk cannot read")
	}
	r.svc.libJournal.stale = true
	r.svc.libJournal.mu.Unlock()
	for i := range 10 {
		if d, err := r.svc.SyncCatalogDelta(r.ctx, r.reader, since, 500); err == nil {
			t.Fatalf("delta %d answered %+v while the journal cannot start over, want it to fail", i, d)
		}
	}
	if n := walks.Load(); n > 1 {
		t.Errorf("the failing walk ran %d times for 10 client retries, want at most once", n)
	}
	r.svc.libJournal.mu.Lock()
	r.svc.journalWalkHook = nil
	r.svc.libJournal.mu.Unlock()
	// Once the walk is through the cursor answers: a delta, or a reset
	// where the journal started over past it.
	waitFor(t, func() bool {
		_, err := r.svc.SyncCatalogDelta(r.ctx, r.reader, since, 500)
		return err == nil || errors.Is(err, ErrSyncReset)
	}, "the delta answering once the walk goes through")
	if _, err := r.svc.SyncCatalogDelta(r.ctx, r.reader, r.snapshot(t), 500); err != nil {
		t.Errorf("a delta after the walk went through: %v", err)
	}
}

// snapshotPIDs mirrors the catalog as the reader and answers its cursor
// with the bare pids of the items the pages carried.
func (r journalReach) snapshotPIDs(t *testing.T) (string, map[model.PID]bool) {
	t.Helper()
	pids := map[model.PID]bool{}
	cursor := ""
	for {
		page, err := r.svc.SyncCatalogSnapshot(r.ctx, r.reader, cursor, 500)
		if err != nil {
			t.Fatal(err)
		}
		for _, e := range page.Entries {
			if _, pid, ok := parseAPIPID(e.PID); ok {
				pids[pid] = true
			}
		}
		if page.NextCursor == "" {
			return page.NextSince, pids
		}
		cursor = page.NextCursor
	}
}

// A reader caught up exactly at the head when the journal starts over, and
// a track re-homed out of its library while the walk runs: the walk reads
// the track where it landed, so the journal cannot tell the reader held
// it. Its cursor is reset instead, and the mirror it takes again is
// without the track. A walk nothing moves during leaves such a cursor as
// it was. The reader's root is padded: a scan keeps a root's only file
// where it was when it vanishes.
func TestAReaderCaughtUpAtTheWalksStartIsResetWhenATrackMovesDuringIt(t *testing.T) {
	t.Parallel()
	for _, moved := range []bool{true, false} {
		r := newJournalReach(t)
		for i := range 4 {
			if _, err := fixtures.Generate(r.seenDir, journalSong(fmt.Sprintf("pad%d", i), fmt.Sprintf("Pad %d", i))); err != nil {
				t.Fatal(err)
			}
		}
		if _, err := r.svc.lib.Scan(r.ctx, waxbin.ScanRequest{}); err != nil {
			t.Fatal(err)
		}
		seen := bareOf(t, r.item(t, "Seen Song"))
		feedCaughtUp(t, r.ctx, r.svc)
		since := r.snapshot(t)
		once := false
		r.svc.libJournal.mu.Lock()
		r.svc.libJournal.stale = true
		r.svc.journalWalkHook = func() error {
			if moved && !once {
				once = true
				r.move(t, "seen.flac", r.seenDir, r.unseenDir)
			}
			return nil
		}
		r.svc.libJournal.mu.Unlock()
		if _, err := r.svc.journalCatchUp(r.ctx); err != nil {
			t.Fatal(err)
		}
		r.svc.libJournal.mu.Lock()
		r.svc.journalWalkHook = nil
		r.svc.libJournal.mu.Unlock()
		_, err := r.svc.SyncCatalogDelta(r.ctx, r.reader, since, 500)
		if !moved {
			if err != nil {
				t.Errorf("after a walk nothing moved during, the caught-up reader's delta: %v, want it to answer", err)
			}
			continue
		}
		if !errors.Is(err, ErrSyncReset) {
			t.Errorf("after a walk the track moved out of its library during, the caught-up reader's delta answers %v, want a reset", err)
		}
		again, held := r.snapshotPIDs(t)
		if held[seen] {
			t.Error("the mirror taken again carries the track re-homed out of the reader's library")
		}
		if g, sent := r.delta(t, again)[seen]; sent {
			t.Errorf("the delta after the new mirror sends %q for the track, want nothing", g)
		}
	}
}

// A walk the journal is cut short in leaves it to start over at the next
// boot, rather than trusted there with part of the catalog placed.
func TestAJournalWalkCutShortStartsOverAtTheNextBoot(t *testing.T) {
	t.Parallel()
	r := newJournalReach(t)
	r.svc.libJournal.mu.Lock()
	r.svc.libJournal.stale = true
	r.svc.journalWalkHook = func() error { return errors.New("cut short") }
	r.svc.libJournal.mu.Unlock()
	if _, err := r.svc.journalCatchUp(r.ctx); err == nil {
		t.Fatal("the walk the hook cuts short reported nothing")
	}
	r.svc.libJournal.mu.Lock()
	r.svc.journalWalkHook = nil
	r.svc.libJournal.mu.Unlock()
	if err := r.svc.openLibraryJournal(r.ctx, true, 0); err != nil {
		t.Fatal(err)
	}
	r.svc.libJournal.mu.Lock()
	stale := r.svc.libJournal.stale
	r.svc.libJournal.mu.Unlock()
	if !stale {
		t.Error("a boot trusts a journal whose walk was cut short")
	}
}

// A restore that lands exactly at the journal's place (a backup, one
// change, the backup put back) leaves its read nothing to see; the
// catalog's new generation starts the journal over from the restored
// catalog, so nothing it read from the catalog before stays.
func TestARestoreAtTheJournalsPlaceStartsItOver(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	ctx, svc, uc, _ := openServiceAt(t, dataDir, nil)
	if _, err := fixtures.Generate(filepath.Join(dataDir, "configured"), journalSong("kept", "Kept Song")); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	page, err := svc.Items(ctx, uc, ItemFilter{}, "", 10)
	if err != nil || len(page.Items) != 1 {
		t.Fatalf("items = %+v, %v; want the one track", page.Items, err)
	}
	kept := page.Items[0].PID
	feedCaughtUp(t, ctx, svc)
	if _, err := svc.journalCatchUp(ctx); err != nil {
		t.Fatal(err)
	}
	backup := filepath.Join(t.TempDir(), "backup.db")
	if err := svc.lib.Backup(ctx, backup, port.BackupOptions{}); err != nil {
		t.Fatal(err)
	}
	before, err := svc.lib.LatestChangeSeq(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := svc.SetStar(ctx, uc, kept, true, nil); err != nil {
		t.Fatal(err)
	}
	head, err := svc.lib.LatestChangeSeq(ctx)
	if err != nil || head != before+1 {
		t.Fatalf("the change wrote rows to %d from %d (%v), want one", head, before, err)
	}
	if place, err := svc.journalCatchUp(ctx); err != nil || place.through != head {
		t.Fatalf("the journal read to %d (%v), want the change at %d", place.through, err, head)
	}
	restoreUnder(t, ctx, svc, dataDir, backup)
	if row := catalogRowSeq(t, ctx, svc); row != head {
		t.Fatalf("the restored catalog's row is at %d, want the journal's place %d", row, head)
	}
	if _, err := svc.journalCatchUp(ctx); err != nil {
		t.Fatal(err)
	}
	around, err := svc.db.ItemLibrariesAround(ctx, []string{string(bareOf(t, kept))}, before)
	if err != nil {
		t.Fatal(err)
	}
	if around[string(bareOf(t, kept))].Placed {
		t.Error("the journal keeps what it read from the catalog the restore replaced")
	}
}
