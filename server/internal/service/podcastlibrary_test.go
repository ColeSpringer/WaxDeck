package service

import (
	"context"
	"slices"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"
)

// Until the first episode download there is no podcast library, so every
// visibility check of a restricted reader misses it. A miss reloads the
// library table at most once a second, or a page of episodes would cost
// a catalog read per row.
func TestAPodcastLibraryMissReloadsAtMostOnceASecond(t *testing.T) {
	t.Parallel()
	f := openStubFeeds(t)
	restricted := &UserCtx{ID: f.uc.ID, CatalogPID: f.uc.CatalogPID, Libraries: map[string]bool{"elsewhere": true}}
	table := func() []libraryDir {
		f.svc.Grants.libDirs.mu.Lock()
		defer f.svc.Grants.libDirs.mu.Unlock()
		return f.svc.Grants.libDirs.dirs
	}
	missed := func(set func(*time.Time)) time.Time {
		f.svc.Grants.libDirs.mu.Lock()
		defer f.svc.Grants.libDirs.mu.Unlock()
		if set != nil {
			set(&f.svc.Grants.libDirs.missed)
		}
		return f.svc.Grants.libDirs.missed
	}
	// Loaded once first, so a reload is a new table rather than the first.
	if dirs, err := f.svc.Grants.attribution(f.ctx, false); err != nil || len(dirs) == 0 {
		t.Fatalf("the library table = %v, %v; want the configured root", dirs, err)
	}
	reloaded := func() bool {
		t.Helper()
		before := table()
		if f.svc.Grants.podcastsVisible(f.ctx, restricted) {
			t.Fatal("a server with no podcast library shows podcasts to a restricted reader")
		}
		return &before[0] != &table()[0]
	}
	if !reloaded() {
		t.Error("the first miss did not reload the library table")
	}
	for range 50 {
		if reloaded() {
			t.Fatal("a miss within the second reloaded the library table again")
		}
	}
	missed(func(at *time.Time) { *at = time.Now().Add(-2 * time.Second) })
	if !reloaded() {
		t.Error("a miss a second later did not reload the library table")
	}
	f.svc.Grants.invalidateAttribution()
	if !missed(nil).IsZero() {
		t.Error("dropping the library table kept the last miss, so the next one would wait")
	}
}

// A reload that failed leaves a table of unknown age, so what the throttle
// answers from it is no judgment until a load works again.
func TestAFailedReloadJudgesNothingUntilALoadWorks(t *testing.T) {
	t.Parallel()
	f := openStubFeeds(t)
	restricted := &UserCtx{ID: f.uc.ID, CatalogPID: f.uc.CatalogPID, Libraries: map[string]bool{"elsewhere": true}}
	due := func() {
		f.svc.Grants.libDirs.mu.Lock()
		f.svc.Grants.libDirs.missed = time.Now().Add(-2 * time.Second)
		f.svc.Grants.libDirs.mu.Unlock()
	}
	if _, read := f.svc.Grants.podcastLibrary(f.ctx); !read {
		t.Fatal("a load that worked answered unread")
	}
	due()
	canceled, cancel := context.WithCancel(f.ctx)
	cancel()
	if _, read := f.svc.Grants.podcastLibrary(canceled); read {
		t.Fatal("a reload that failed answered read")
	}
	if _, judged := f.svc.Grants.podcastsJudged(f.ctx, restricted); judged {
		t.Error("within the second after a failed reload, the throttle answered a judgment")
	}
	due()
	if _, read := f.svc.Grants.podcastLibrary(f.ctx); !read {
		t.Fatal("a reload that worked answered unread")
	}
	if _, judged := f.svc.Grants.podcastsJudged(f.ctx, restricted); !judged {
		t.Error("after a reload worked, the throttle still answered no judgment")
	}
}

// A start that cannot continue its feed position reads the catalog's
// history back, the configured root's row among it. The library table is
// read from the catalog that row was already in, so a row from before the
// start drops no table: dropped under a request, it would answer that the
// server has no podcast library.
func TestARowFromBeforeTheStartKeepsTheLibraryTable(t *testing.T) {
	t.Parallel()
	f := openStubFeeds(t)
	feedCaughtUp(t, f.ctx, f.svc)
	rows, err := f.svc.lib.Changes(f.ctx, 0)
	if err != nil {
		t.Fatal(err)
	}
	i := slices.IndexFunc(rows, func(ch model.Change) bool { return ch.EntityType == "library" })
	if i < 0 {
		t.Fatal("the catalog holds no row for the configured root")
	}
	f.svc.feed.mu.Lock()
	history := rows[i].TS <= f.svc.feed.bootTS
	f.svc.feed.mu.Unlock()
	if !history {
		t.Fatal("the root's row is not from before the start; the start continued its position")
	}
	if dirs, err := f.svc.Grants.attribution(f.ctx, false); err != nil || len(dirs) == 0 {
		t.Fatalf("the library table = %v, %v; want the configured root", dirs, err)
	}

	f.svc.advanceFeed(f.ctx, rows[i])
	f.svc.Grants.libDirs.mu.Lock()
	dropped := f.svc.Grants.libDirs.dirs == nil
	f.svc.Grants.libDirs.mu.Unlock()
	if dropped {
		t.Error("a row from before the start dropped the library table")
	}
}
