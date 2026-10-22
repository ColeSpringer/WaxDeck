package service

import (
	"context"
	"testing"
	"time"
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
		f.svc.libDirs.mu.Lock()
		defer f.svc.libDirs.mu.Unlock()
		return f.svc.libDirs.dirs
	}
	missed := func(set func(*time.Time)) time.Time {
		f.svc.libDirs.mu.Lock()
		defer f.svc.libDirs.mu.Unlock()
		if set != nil {
			set(&f.svc.libDirs.missed)
		}
		return f.svc.libDirs.missed
	}
	// Loaded once first, so a reload is a new table rather than the first.
	if dirs, err := f.svc.attribution(f.ctx, false); err != nil || len(dirs) == 0 {
		t.Fatalf("the library table = %v, %v; want the configured root", dirs, err)
	}
	reloaded := func() bool {
		t.Helper()
		before := table()
		if f.svc.podcastsVisible(f.ctx, restricted) {
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
	f.svc.invalidateAttribution()
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
		f.svc.libDirs.mu.Lock()
		f.svc.libDirs.missed = time.Now().Add(-2 * time.Second)
		f.svc.libDirs.mu.Unlock()
	}
	if _, read := f.svc.podcastLibrary(f.ctx); !read {
		t.Fatal("a load that worked answered unread")
	}
	due()
	canceled, cancel := context.WithCancel(f.ctx)
	cancel()
	if _, read := f.svc.podcastLibrary(canceled); read {
		t.Fatal("a reload that failed answered read")
	}
	if _, judged := f.svc.podcastsJudged(f.ctx, restricted); judged {
		t.Error("within the second after a failed reload, the throttle answered a judgment")
	}
	due()
	if _, read := f.svc.podcastLibrary(f.ctx); !read {
		t.Fatal("a reload that worked answered unread")
	}
	if _, judged := f.svc.podcastsJudged(f.ctx, restricted); !judged {
		t.Error("after a reload worked, the throttle still answered no judgment")
	}
}
