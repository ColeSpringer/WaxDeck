package service

import (
	"context"
	"io"
	"log/slog"
	"path/filepath"
	"strconv"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxdeck/fixtures"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// discoveryFixture is a catalog with a library root a test can add files
// to and rescan, which is what a scan discovering loose files looks like
// from the outside.
type discoveryFixture struct {
	ctx    context.Context
	svc    *Library
	uc     *UserCtx
	libDir string
}

// discoveryTrack takes its duration explicitly, and every call site in
// this file passes a different one. The fixtures synthesize a fixed
// 440 Hz tone, so duration is the only thing that distinguishes two
// files' audio - and the catalog keys items by audio essence, so two
// fixtures of the same length come back as one item with two files and
// a test written on them measures nothing.
func discoveryTrack(
	name, title, album string,
	trackNo int,
	ms int,
) fixtures.Spec {
	return fixtures.Spec{
		Name:     name,
		Codec:    fixtures.CodecFLAC,
		Duration: time.Duration(ms) * time.Millisecond,
		Tags: map[string]string{
			"TITLE":       title,
			"ARTIST":      "Loose Files",
			"ALBUM":       album,
			"ALBUMARTIST": "Loose Files",
			"TRACKNUMBER": strconv.Itoa(trackNo),
		},
	}
}

func newDiscoveryFixture(t *testing.T) discoveryFixture {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	log := slog.New(slog.NewTextHandler(io.Discard, nil))

	libDir := t.TempDir()
	if _, err := fixtures.Generate(libDir,
		discoveryTrack("seed", "Seed", "Already Here", 1, 900),
	); err != nil {
		t.Fatalf("generating fixtures: %v", err)
	}

	dataDir := t.TempDir()
	store, err := wdb.Open(ctx, filepath.Join(dataDir, "waxdeck.db"))
	if err != nil {
		t.Fatal(err)
	}
	group := supervise.NewGroup(log)
	svc, err := Open(ctx, Config{
		DataDir: dataDir,
		Roots:   []Root{{Name: "lib", Path: libDir}},
		Logger:  log,
	}, store, group)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		cancel()
		group.Wait()
		svc.Close()
		store.Close()
	})
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatalf("scanning fixture library: %v", err)
	}
	acct, err := svc.CreateAccount(ctx, AccountCreate{
		Username: "admin", Password: "correct-horse", Roles: []string{"admin"},
	})
	if err != nil {
		t.Fatal(err)
	}
	uc, err := svc.UserCtx(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	return discoveryFixture{ctx: ctx, svc: svc, uc: uc, libDir: libDir}
}

// sweepToQuiet drains the sweeper the way the supervised worker does.
func (f discoveryFixture) sweepToQuiet(t *testing.T) DiscoverySweepReport {
	t.Helper()
	var last DiscoverySweepReport
	for i := 0; i < 20; i++ {
		rep, err := f.svc.SweepDiscoveries(f.ctx)
		if err != nil {
			t.Fatalf("discovery sweep: %v", err)
		}
		last = rep
		if !rep.More {
			return last
		}
	}
	t.Fatal("the discovery sweeper never reported itself caught up")
	return last
}

func (f discoveryFixture) pendingEntries(t *testing.T) []wdb.ReviewEntry {
	t.Helper()
	entries, err := f.svc.db.ListReviewEntries(f.ctx, reviewPending, "", 0, "", 100)
	if err != nil {
		t.Fatalf("listing review entries: %v", err)
	}
	return entries
}

// The catalog already on disk when the sweeper first runs is not swept
// into the review queue: the first pass anchors at the tail, so an
// upgrade does not drop an existing library into somebody's inbox.
func TestDiscoveryFirstPassSkipsTheExistingCatalog(t *testing.T) {
	t.Parallel()
	f := newDiscoveryFixture(t)

	f.sweepToQuiet(t)
	if got := len(f.pendingEntries(t)); got != 0 {
		t.Fatalf("%d review entries opened for a catalog that was already there; want 0", got)
	}
}

// What a later scan discovers does become an entry, and an album's files
// make one entry between them rather than one each.
func TestDiscoveryOpensOneEntryPerAlbum(t *testing.T) {
	t.Parallel()
	f := newDiscoveryFixture(t)
	f.sweepToQuiet(t)

	if _, err := fixtures.Generate(f.libDir,
		discoveryTrack("newa", "New One", "Found Later", 1, 1200),
		discoveryTrack("newb", "New Two", "Found Later", 2, 1500),
		discoveryTrack("newc", "New Three", "Found Later", 3, 1800),
	); err != nil {
		t.Fatalf("generating the discovered files: %v", err)
	}
	if _, err := f.svc.lib.Scan(f.ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatalf("rescanning: %v", err)
	}

	f.sweepToQuiet(t)
	entries := f.pendingEntries(t)
	if len(entries) != 1 {
		t.Fatalf("%d review entries for one discovered album; want 1", len(entries))
	}
	entry := entries[0]
	if entry.Origin != reviewOriginScan {
		t.Fatalf("entry origin = %q, want %q", entry.Origin, reviewOriginScan)
	}
	if entry.Title != "Found Later" {
		t.Fatalf("entry title = %q, want the album name", entry.Title)
	}
	if entry.TrackCount != 3 {
		t.Fatalf("entry trackCount = %d, want the album's 3 files", entry.TrackCount)
	}

	// A second sweep with nothing new opens nothing: the cursor moved,
	// and the pending-unit guard covers a re-read either way.
	f.sweepToQuiet(t)
	if got := len(f.pendingEntries(t)); got != 1 {
		t.Fatalf("a quiet sweep changed the queue to %d entries; want the same 1", got)
	}
}

// A pass that stops at its unit cap leaves the cursor on the item it
// stopped at, not at the start of the batch: the next pass picks up the
// albums it did not reach without re-reading the change rows or
// rebuilding the units it already opened.
func TestDiscoveryCappedPassAdvancesToWhereItStopped(t *testing.T) {
	t.Parallel()
	f := newDiscoveryFixture(t)
	f.sweepToQuiet(t)

	// More albums than one pass will open, one file each so the units
	// are the albums.
	const albums = discoveryUnitsPerPass + 4
	specs := make([]fixtures.Spec, 0, albums)
	for i := 0; i < albums; i++ {
		specs = append(
			specs,
			discoveryTrack("found"+strconv.Itoa(i), "Track "+strconv.Itoa(i),
				"Album "+strconv.Itoa(i), i+1, 2400+i*250),
		)
	}
	if _, err := fixtures.Generate(f.libDir, specs...); err != nil {
		t.Fatalf("generating the discovered files: %v", err)
	}
	if _, err := f.svc.lib.Scan(f.ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatalf("rescanning: %v", err)
	}

	first, err := f.svc.SweepDiscoveries(f.ctx)
	if err != nil {
		t.Fatalf("first pass: %v", err)
	}
	if first.Opened != discoveryUnitsPerPass {
		t.Fatalf("first pass opened %d units, want the cap of %d",
			first.Opened, discoveryUnitsPerPass)
	}
	if !first.More {
		t.Fatal("a capped pass must report there is more to do")
	}

	// The stored cursor moved: rewinding to the start of the batch is
	// what this test exists to catch, because it costs a re-read of
	// every change row and every album unit on every tick.
	raw, err := f.svc.db.SyncStateGet(f.ctx, discoveryCursorKey)
	if err != nil {
		t.Fatal(err)
	}
	after, ok := parseSweepCursor(raw)
	if !ok || after == 0 {
		t.Fatalf("cursor after a capped pass = %q, want a real position", raw)
	}

	f.sweepToQuiet(t)
	entries := f.pendingEntries(t)
	if len(entries) != albums {
		t.Fatalf("%d entries after draining; want one per discovered album (%d)",
			len(entries), albums)
	}
	// One per album and no duplicates: the pending-unit guard and the
	// cursor agree about what has been handled.
	titles := map[string]bool{}
	for _, entry := range entries {
		if titles[entry.Title] {
			t.Fatalf("%q opened twice", entry.Title)
		}
		titles[entry.Title] = true
	}
}

// An accented album finds its own pending entry. The guard folds case
// in Go, on both sides; folding one side in SQL instead would leave
// "ÉTÉ" as "ÉtÉ" against Go's "été", so the album would miss its entry
// and open a fresh one on every tick, forever.
func TestDiscoveryGuardFoldsNonAsciiTitles(t *testing.T) {
	t.Parallel()
	f := newDiscoveryFixture(t)
	f.sweepToQuiet(t)

	accented := func(name, title string, trackNo, ms int) fixtures.Spec {
		spec := discoveryTrack(name, title, "ÉTÉ SANS FIN", trackNo, ms)
		spec.Tags["ARTIST"] = "ÎLE"
		spec.Tags["ALBUMARTIST"] = "ÎLE"
		return spec
	}
	if _, err := fixtures.Generate(f.libDir,
		accented("acc1", "Un", 1, 3100),
		accented("acc2", "Deux", 2, 3400),
	); err != nil {
		t.Fatalf("generating the discovered files: %v", err)
	}
	if _, err := f.svc.lib.Scan(f.ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatalf("rescanning: %v", err)
	}

	f.sweepToQuiet(t)
	if got := len(f.pendingEntries(t)); got != 1 {
		t.Fatalf("%d entries for one accented album; want 1", got)
	}

	// The guard, exercised directly: a second look at the same unit must
	// find it. Rewinding the cursor to the start of the log is what a
	// real re-read does - it also exposes the seed album the first pass
	// deliberately skipped, so the count is scoped to this album.
	if err := f.svc.db.SyncStateSet(f.ctx, discoveryCursorKey, "0"); err != nil {
		t.Fatal(err)
	}
	f.sweepToQuiet(t)
	accentedEntries := 0
	for _, entry := range f.pendingEntries(t) {
		if entry.Title == "ÉTÉ SANS FIN" {
			accentedEntries++
		}
	}
	if accentedEntries != 1 {
		t.Fatalf("a re-read opened %d entries for the accented album; want the same 1",
			accentedEntries)
	}
}

// A library set to match nothing is left alone: the mode exists to say
// "this collection is already curated", and filling the queue with
// entries nobody will decide is the touching it forbids.
func TestDiscoveryRespectsMatchingOff(t *testing.T) {
	t.Parallel()
	f := newDiscoveryFixture(t)
	f.sweepToQuiet(t)

	libs, err := f.svc.Libraries(f.ctx)
	if err != nil || len(libs) == 0 {
		t.Fatalf("listing libraries: %v (%d)", err, len(libs))
	}
	if err := f.svc.SetLibraryMatchingMode(f.ctx, f.uc, libs[0].PID, matchingOff); err != nil {
		t.Fatalf("setting matching mode: %v", err)
	}

	if _, err := fixtures.Generate(f.libDir,
		discoveryTrack("asis", "Left Alone", "Curated", 1, 2100),
	); err != nil {
		t.Fatalf("generating the discovered file: %v", err)
	}
	if _, err := f.svc.lib.Scan(f.ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatalf("rescanning: %v", err)
	}

	f.sweepToQuiet(t)
	if got := len(f.pendingEntries(t)); got != 0 {
		t.Fatalf("%d entries opened in an as-is library; want 0", got)
	}
}
