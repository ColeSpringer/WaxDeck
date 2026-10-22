package service

import (
	"os"
	"path/filepath"
	"slices"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/source"

	"github.com/colespringer/waxdeck/fixtures"
)

// Search decides an episode by the podcast library at the configured
// directory, as the listings do, whichever library its file sits in: once
// the directory has moved, an account granted the new library finds an
// episode fetched under the old one, and an account granted only the old
// one finds nothing it could not open.
func TestSearchFollowsThePodcastLibraryRule(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	podcasts := filepath.Join(dataDir, "podcasts")
	moved := filepath.Join(dataDir, "moved")
	if err := os.MkdirAll(podcasts, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(podcasts, moved); err != nil {
		t.Skipf("no symlinks here: %v", err)
	}
	feed := &stubFeed{kind: model.SourceRSS, n: 2, prefix: "Wax"}
	open := func(dir string) (*Library, func()) {
		t.Helper()
		_, svc, _, stop := openServiceAt(t, dataDir, func(cfg *Config) {
			cfg.PodcastDir, cfg.PodcastRootName = dir, "podcasts"
			cfg.SourceProviders = []source.Provider{feed}
		})
		return svc, stop
	}
	fetch := func(f stubFeedFixture, apiPID string) {
		t.Helper()
		paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
			Name: "ep", Codec: fixtures.CodecMP3, Container: fixtures.ContainerMP3, Duration: 2 * time.Second,
		})
		if err != nil {
			t.Fatal(err)
		}
		_, bare, _ := parseAPIPID(apiPID)
		if _, err := f.svc.lib.Podcasts().ImportEpisodeFile(f.ctx, bare, paths[0], false); err != nil {
			t.Fatal(err)
		}
	}
	follower := func(f stubFeedFixture, name string, libs ...string) *UserCtx {
		t.Helper()
		grants := make([]string, 0, len(libs))
		for _, lib := range libs {
			grants = append(grants, apiPID(PrefixLibrary, model.PID(lib)))
		}
		acct, err := f.svc.CreateAccount(f.ctx, AccountCreate{
			Username: name, Password: "correct-horse", AccessMode: "granted", LibraryPIDs: grants,
		})
		if err != nil {
			t.Fatal(err)
		}
		uc, err := f.svc.UserCtx(f.ctx, acct.User)
		if err != nil {
			t.Fatal(err)
		}
		if _, _, err := f.svc.Subscribe(f.ctx, uc, SubscribeRequest{URL: "https://feeds.example/moved", SourceType: "rss"}); err != nil {
			t.Fatal(err)
		}
		return uc
	}

	svc, stop := open(podcasts)
	f := stubFeedFixture{ctx: t.Context(), svc: svc, uc: mustAdmin(t, svc)}
	sub := f.subscribe(t, "https://feeds.example/moved", "rss")
	episodes := showEpisodePIDs(t, f, sub.Show.PID)
	underOld := episodes[1]
	fetch(f, underOld)
	old, _ := svc.podcastLibrary(f.ctx)
	oldOnly := follower(f, "old-only", old)
	stop()

	svc, _ = open(moved)
	f.svc = svc
	fetch(f, episodes[0])
	svc.libDirs.mu.Lock()
	svc.libDirs.missed = time.Now().Add(-2 * time.Second)
	svc.libDirs.mu.Unlock()
	fresh, _ := svc.podcastLibrary(f.ctx)
	if fresh == "" || fresh == old {
		t.Fatalf("the podcast library after the move = %q, want a new one beside %q", fresh, old)
	}
	newOnly := follower(f, "new-only", fresh)
	if oldOnly, err := svc.userCtxByID(f.ctx, oldOnly.ID); err != nil {
		t.Fatal(err)
	} else {
		f.uc = oldOnly
	}

	hits := func(uc *UserCtx) []string {
		t.Helper()
		res, err := svc.Search(f.ctx, uc, "Wax", 20)
		if err != nil {
			t.Fatal(err)
		}
		var out []string
		for _, h := range res.Episodes {
			out = append(out, h.PID)
		}
		return out
	}
	if _, err := svc.EpisodeDetailFor(f.ctx, newOnly, underOld); err != nil {
		t.Fatalf("the new library's account opening the episode = %v, want it", err)
	}
	if got := hits(newOnly); !slices.Contains(got, underOld) {
		t.Errorf("the new library's account searching = %v, want the episode its listing shows, %s", got, underOld)
	}
	if got := hits(f.uc); len(got) != 0 {
		t.Errorf("the old library's account searching = %v, want nothing, as it can open nothing", got)
	}
}

// An account that follows no show can be shown no episode, so its search
// asks nothing of the unfetched backlog: a backlog over the pool does not
// make its answer read as cut short.
func TestASearchByAFollowerOfNothingSkipsTheBacklog(t *testing.T) {
	t.Parallel()
	g := newGrantedSearcher(t, 6, 0)
	if err := g.f.svc.Unsubscribe(g.f.ctx, g.listener, g.show, false); err != nil {
		t.Fatal(err)
	}
	res := g.search(t)
	if len(res.Episodes) != 0 {
		t.Errorf("episode hits for a follower of nothing = %+v, want none", res.Episodes)
	}
	if res.Truncated {
		t.Error("a follower of nothing reads as cut short by a backlog it can never see")
	}
}
