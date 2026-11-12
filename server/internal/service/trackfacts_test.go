package service

import (
	"context"
	"errors"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/waxerr"
	"github.com/colespringer/waxdeck/fixtures"
	"github.com/oklog/ulid/v2"
)

// The sweep carries what musicFolderId and the per-song file facts key
// on: the library holding the primary file and that file's pid.
func TestTrackFactsCarryLibraryAndFile(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	libs, err := svc.Roots.Libraries(ctx)
	if err != nil || len(libs) != 1 {
		t.Fatalf("libraries = %+v (%v), want the fixture root", libs, err)
	}
	rows, err := svc.Reads.TrackFacts(ctx, uc)
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) == 0 {
		t.Fatal("no rows")
	}
	for _, tr := range rows {
		if tr.LibraryPID != libs[0].PID {
			t.Errorf("%s library = %q, want %q", tr.Title, tr.LibraryPID, libs[0].PID)
		}
		if !strings.HasPrefix(tr.FilePID, PrefixFile+"-") || tr.Virtual {
			t.Errorf("%s file = %q virtual %v, want a whole file's pid", tr.Title, tr.FilePID, tr.Virtual)
		}
	}
}

// An album's year is the catalog's rule over all its members, not
// whichever member a sweep reached first.
func TestEntityFactsCarryTheAlbumYear(t *testing.T) {
	t.Parallel()
	dated := func(name, title, date string) fixtures.Spec {
		return fixtures.Spec{Name: name, Codec: fixtures.CodecFLAC, Duration: time.Second, Tags: map[string]string{
			"TITLE": title, "ARTIST": "Year Band", "ALBUM": "Reissue", "DATE": date,
		}}
	}
	ctx, svc, uc := newCatalogFixtureWith(t, catalogFixtureOptions{extra: func(t *testing.T, dir string) {
		if _, err := fixtures.Generate(dir,
			dated("r1", "Remastered", "2021"), dated("r2", "Original One", "1999"), dated("r3", "Original Two", "1999"),
		); err != nil {
			t.Fatal(err)
		}
	}})
	rows, err := svc.Reads.TrackFacts(ctx, uc)
	if err != nil {
		t.Fatal(err)
	}
	var album, artist string
	for _, tr := range rows {
		if tr.Album == "Reissue" {
			album, artist = tr.AlbumPID, tr.AlbumArtistPID
		}
	}
	if album == "" || artist == "" {
		t.Fatal("the dated album is not in the sweep")
	}
	facts, err := svc.Reads.EntityFacts(ctx, []string{album, artist, "nonsense"})
	if err != nil {
		t.Fatal(err)
	}
	if f := facts[album]; f.Name != "Reissue" || f.Year != 1999 {
		t.Errorf("album facts = %+v, want Reissue from 1999", f)
	}
	if f := facts[artist]; f.Name != "Year Band" || f.Year != 0 {
		t.Errorf("artist facts = %+v, want Year Band with no year", f)
	}
	if got := AlbumYear([]int{2021, 1999, 1999, 0}); got != 1999 {
		t.Errorf("AlbumYear = %d, want the shared 1999", got)
	}
}

// File facts are read per primary file at most once per catalog position
// and at most fileFactsReadCap per call.
func TestFileFactsAreBoundedAndCached(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	rows, err := svc.Reads.TrackFacts(ctx, uc)
	if err != nil {
		t.Fatal(err)
	}
	var reads atomic.Int64
	svc.Reads.fileReadHook = func(ctx context.Context, pid model.PID) (*model.File, error) {
		reads.Add(1)
		return svc.lib.File(ctx, pid)
	}
	pids := make([]string, 0, len(rows))
	for _, tr := range rows {
		pids = append(pids, tr.FilePID)
	}
	facts := svc.Reads.FileFacts(ctx, pids)
	if len(facts) != len(rows) {
		t.Fatalf("facts for %d of %d files", len(facts), len(rows))
	}
	for pid, f := range facts {
		if f.SizeBytes <= 0 || f.BitrateKbps <= 0 || time.Since(f.AddedAt) < 0 || time.Since(f.AddedAt) > time.Hour {
			t.Errorf("%s facts = %+v, want a size, a bitrate and a first-seen time within the hour", pid, f)
		}
	}
	if n := reads.Load(); n != int64(len(rows)) {
		t.Fatalf("reads = %d, want one per file", n)
	}
	svc.Reads.FileFacts(ctx, pids)
	if n := reads.Load(); n != int64(len(rows)) {
		t.Fatalf("a second call read %d more files, want none", n-int64(len(rows)))
	}
	// A play anywhere moves the catalog's feed position; it changes no
	// file, so it does not empty the cache.
	tail := svc.CatalogTailSeq()
	if _, err := svc.Playback.Checkpoint(ctx, uc, rows[0].PID, 1000, nil); err != nil {
		t.Fatal(err)
	}
	for deadline := time.Now().Add(10 * time.Second); svc.CatalogTailSeq() == tail; {
		if time.Now().After(deadline) {
			t.Fatal("the feed position never moved after a checkpoint")
		}
		time.Sleep(10 * time.Millisecond)
	}
	svc.Reads.FileFacts(ctx, pids)
	if n := reads.Load(); n != int64(len(rows)) {
		t.Fatalf("a call after a play read %d more files, want none", n-int64(len(rows)))
	}

	unknown := make([]string, 0, fileFactsReadCap+50)
	for range fileFactsReadCap + 50 {
		unknown = append(unknown, FileAPIPID(ulid.Make().String()))
	}
	reads.Store(0)
	if got := svc.Reads.FileFacts(ctx, unknown); len(got) != 0 {
		t.Fatalf("facts for files that do not exist: %v", got)
	}
	if n := reads.Load(); n != fileFactsReadCap {
		t.Fatalf("one call read %d files, want the cap of %d", n, fileFactsReadCap)
	}
}

// The compatibility surface's caches key on a position only the
// catalog's content moves: a play changes no track, so the cached sweep
// stays, while a content change still refills it.
func TestTrackFactsSurviveAPlay(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	// While the feed still trails the fixture's scan the key is the
	// feed's position, which every row it reads moves: sweep once it has
	// caught up, so the play is the only thing left to move it.
	feedCaughtUp(t, ctx, svc)
	rows, err := svc.Reads.TrackFacts(ctx, uc)
	if err != nil || len(rows) == 0 {
		t.Fatalf("rows = %d (%v)", len(rows), err)
	}
	tail := svc.CatalogTailSeq()
	if _, err := svc.Playback.Checkpoint(ctx, uc, rows[0].PID, 1000, nil); err != nil {
		t.Fatal(err)
	}
	feedCaughtUp(t, ctx, svc)
	if svc.CatalogTailSeq() == tail {
		t.Fatal("the feed position never moved after a checkpoint")
	}
	again, err := svc.Reads.TrackFacts(ctx, uc)
	if err != nil {
		t.Fatal(err)
	}
	if &again[0] != &rows[0] {
		t.Fatal("a play re-swept the catalog")
	}
	if _, err := svc.Roots.AddLibrary(ctx, uc, AddLibraryInput{Name: "more", Path: t.TempDir(), Media: "music"}); err != nil {
		t.Fatal(err)
	}
	third, err := svc.Reads.TrackFacts(ctx, uc)
	if err != nil {
		t.Fatal(err)
	}
	if &third[0] == &again[0] {
		t.Fatal("a new library left the sweep cached")
	}
}

// While the feed trails the log, the content position answers the feed's:
// the caches a restricted build reads follow the feed (the tag spellings
// a content rule matches), so nothing may be filed under a position newer
// than they are, and the answer moves again once the feed catches up.
func TestContentPositionWaitsForTheFeed(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	album, _ := fixtureEntityPIDs(t, ctx, svc, uc)
	before := svc.Reads.CatalogContentSeq(ctx)
	if _, err := svc.Editor.EditEntity(ctx, "album", album, map[string]string{"label": "Night Shift"}, MetadataEditParams{}); err != nil {
		t.Fatal(err)
	}
	svc.Reads.trackFacts.feedHook = func() int64 { return before }
	gap := svc.Reads.CatalogContentSeq(ctx)
	svc.Reads.trackFacts.feedHook = nil
	var caught int64
	for deadline := time.Now().Add(10 * time.Second); ; {
		if caught = svc.Reads.CatalogContentSeq(ctx); caught != before {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("the edit never moved the content position")
		}
		time.Sleep(10 * time.Millisecond)
	}
	if gap == caught {
		t.Fatal("the key read while the feed trailed the edit is the key after it caught up, so a build in the gap would be served afterwards")
	}
}

// The content position moves with what changes the catalog's content and
// with nothing else: per-user state and accounts leave it, every kind of
// content change moves it.
func TestContentPositionFollowsContentOnly(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, survivor, loser := twoAlbumFixture(t)
	track, _ := fixtureTrackPID(t, ctx, svc, uc, "Amber Waves")
	trashed, _ := fixtureTrackPID(t, ctx, svc, uc, "Basalt Steps")
	kinded, _ := fixtureTrackPID(t, ctx, svc, uc, "Cobalt Sky")
	libs, err := svc.Roots.Libraries(ctx)
	if err != nil || len(libs) != 1 {
		t.Fatalf("libraries = %+v (%v)", libs, err)
	}
	// Read once the feed has read the log to its head, so the key is the
	// content position rather than the feed's.
	settled := func() int64 {
		t.Helper()
		head, err := svc.lib.LatestChangeSeq(ctx)
		if err != nil {
			t.Fatal(err)
		}
		for deadline := time.Now().Add(10 * time.Second); svc.CatalogTailSeq()&(1<<40-1) < head; {
			if time.Now().After(deadline) {
				t.Fatal("the feed never reached the log's head")
			}
			time.Sleep(5 * time.Millisecond)
		}
		return svc.Reads.CatalogContentSeq(ctx)
	}
	r := 60
	for _, op := range []struct {
		name  string
		moves bool
		do    func() error
	}{
		{"a checkpoint", false, func() error { _, err := svc.Playback.Checkpoint(ctx, uc, track, 1000, nil); return err }},
		{"an item star", false, func() error { _, err := svc.Playback.SetStar(ctx, uc, track, true, nil); return err }},
		{"an entity rating", false, func() error { _, err := svc.Identity.SetEntityRating(ctx, uc, survivor, &r, nil); return err }},
		{"an account", false, func() error {
			_, err := svc.Identity.CreateAccount(ctx, AccountCreate{Username: "someone", Password: "correct-horse-3"})
			return err
		}},
		{"an item edit", true, func() error {
			_, err := svc.Editor.EditItemMetadata(ctx, uc, track, map[string]string{"title": "Amber Waves Again"}, MetadataEditParams{})
			return err
		}},
		{"an entity edit", true, func() error {
			_, err := svc.Editor.EditEntity(ctx, "album", survivor, map[string]string{"label": "Night Shift"}, MetadataEditParams{})
			return err
		}},
		{"a merge", true, func() error {
			_, err := svc.Health.MergeDuplicates(ctx, uc, "album", survivor, []string{loser})
			return err
		}},
		{"a trash", true, func() error { _, err := svc.Tools.DeleteItems(ctx, uc, []string{trashed}, "trash", false); return err }},
		{"a kind change", true, func() error {
			job, err := svc.Reads.SetItemsKind(ctx, uc, []string{kinded}, "audiobook", false)
			if err != nil {
				return err
			}
			_, pid, _ := parseAPIPID(job.PID)
			waitForJob(t, ctx, svc, pid)
			return nil
		}},
		{"a new library", true, func() error {
			_, err := svc.Roots.AddLibrary(ctx, uc, AddLibraryInput{Name: "more", Path: t.TempDir()})
			return err
		}},
		{"a library's media", true, func() error { _, err := svc.Roots.SetLibraryMedia(ctx, uc, libs[0].PID, "music"); return err }},
	} {
		before := settled()
		if err := op.do(); err != nil {
			t.Fatalf("%s: %v", op.name, err)
		}
		if moved := settled() != before; moved != op.moves {
			t.Errorf("%s moved the content position: %v, want %v", op.name, moved, op.moves)
		}
	}
}

// A look at the log that fails answers the last position a good one gave
// and leaves the artist and album count where it was; a pruned log and
// one too far behind to read are taken to hold changes of every kind.
func TestCatalogWatchFailsClosed(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newCatalogFixture(t)
	svc.Reads.trackFacts.feedHook = func() int64 { return 1 << 50 }
	settledEpoch := func() uint64 {
		t.Helper()
		svc.Reads.CatalogContentSeq(ctx)
		epoch, _ := svc.Reads.entityEpoch(ctx)
		return epoch
	}

	epoch := settledEpoch()
	last := svc.Reads.CatalogContentSeq(ctx)
	head, err := svc.lib.LatestChangeSeq(ctx)
	if err != nil {
		t.Fatal(err)
	}
	svc.Reads.trackFacts.headHook = func(ctx context.Context) (int64, error) { return head + 1, nil }
	svc.Reads.trackFacts.changesHook = func(ctx context.Context, since int64) ([]model.Change, error) {
		return nil, errors.New("catalog busy")
	}
	if got := svc.Reads.CatalogContentSeq(ctx); got != last {
		t.Errorf("a failed look answered %d, want the last good %d", got, last)
	}
	// It says it could not tell, and leaves the count to the look that can.
	if got, ok := svc.Reads.entityEpoch(ctx); ok || got != epoch {
		t.Errorf("a failed look answered the entity count %d (told: %v), want %d and that it could not tell", got, ok, epoch)
	}

	svc.Reads.trackFacts.changesHook = func(ctx context.Context, since int64) ([]model.Change, error) {
		return nil, waxerr.New(waxerr.CodeNotFound, "test", "pruned")
	}
	if got, ok := svc.Reads.entityEpoch(ctx); !ok || got <= epoch {
		t.Errorf("a pruned log left the entity count at %d (told: %v), want it moved past %d", got, ok, epoch)
	}

	// Far behind: every page is state rows, more than one look reads.
	epoch = settledEpoch()
	svc.Reads.trackFacts.headHook = func(ctx context.Context) (int64, error) { return head + 10_000_000, nil }
	svc.Reads.trackFacts.changesHook = func(ctx context.Context, since int64) ([]model.Change, error) {
		rows := make([]model.Change, 1000)
		for i := range rows {
			rows[i] = model.Change{Seq: since + int64(i) + 1, EntityType: "play_state"}
		}
		return rows, nil
	}
	svc.Reads.trackFacts.feedHook = func() int64 { return 1 << 62 }
	if got := svc.Reads.CatalogContentSeq(ctx); got&(1<<40-1) != head+10_000_000 {
		t.Errorf("a log too far behind answered content %d, want its head %d", got&(1<<40-1), head+10_000_000)
	}
	if got, ok := svc.Reads.entityEpoch(ctx); !ok || got <= epoch {
		t.Errorf("a log too far behind left the entity count at %d (told: %v), want it moved past %d", got, ok, epoch)
	}
}

// With nothing written since the last look, a look costs the log one
// read, its head, whoever asks.
func TestCatalogWatchIdleLookReadsTheHead(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newCatalogFixture(t)
	svc.Reads.CatalogContentSeq(ctx)
	var heads, pages atomic.Int64
	svc.Reads.trackFacts.headHook = func(ctx context.Context) (int64, error) {
		heads.Add(1)
		return svc.lib.LatestChangeSeq(ctx)
	}
	svc.Reads.trackFacts.changesHook = func(ctx context.Context, since int64) ([]model.Change, error) {
		pages.Add(1)
		return svc.lib.Changes(ctx, since)
	}
	svc.Reads.CatalogContentSeq(ctx)
	svc.Reads.entityEpoch(ctx)
	if heads.Load() != 2 || pages.Load() != 0 {
		t.Fatalf("two idle looks read the head %d times and %d pages, want 2 and 0", heads.Load(), pages.Load())
	}
}
