package service

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/source"

	"github.com/colespringer/waxdeck/fixtures"
)

// The podcast library is known by what it is, not by matching the
// configured directory against the root the catalog stored. Where the
// platform folds case the catalog keeps the spelling it first saw, so a
// directory configured under another spelling (here an alias of it)
// would otherwise hide every episode from accounts granted it.
func TestThePodcastLibraryIsKnownByWhatItIs(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	podcasts := filepath.Join(dataDir, "podcasts")
	alias := filepath.Join(dataDir, "alias")
	if err := os.MkdirAll(podcasts, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(podcasts, alias); err != nil {
		t.Skipf("no symlinks here: %v", err)
	}
	feed := &stubFeed{kind: model.SourceRSS, n: 1, prefix: "Episode"}
	open := func(dir string) (*Library, func()) {
		t.Helper()
		_, svc, _, stop := openServiceAt(t, dataDir, func(cfg *Config) {
			cfg.PodcastDir, cfg.PodcastRootName = dir, "podcasts"
			cfg.SourceProviders = []source.Provider{feed}
		})
		return svc, stop
	}

	svc, stop := open(podcasts)
	f := stubFeedFixture{ctx: t.Context(), svc: svc, uc: mustAdmin(t, svc)}
	sub := f.subscribe(t, "https://feeds.example/one", "rss")
	paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
		Name: "one", Codec: fixtures.CodecMP3, Container: fixtures.ContainerMP3, Duration: 2 * time.Second,
	})
	if err != nil {
		t.Fatal(err)
	}
	_, bare, _ := parseAPIPID(showEpisodePIDs(t, f, sub.Show.PID)[0])
	if _, err := svc.lib.Podcasts().ImportEpisodeFile(f.ctx, bare, paths[0], false); err != nil {
		t.Fatal(err)
	}
	want, _ := svc.podcastLibrary(f.ctx)
	if want == "" {
		t.Fatal("no podcast library after a fetch")
	}
	stop()

	svc, _ = open(alias)
	if got, _ := svc.podcastLibrary(t.Context()); got != want {
		t.Errorf("the podcast library under another spelling of its directory = %q, want %q", got, want)
	}
}

// mustAdmin answers the service's administrator.
func mustAdmin(t *testing.T, svc *Library) *UserCtx {
	t.Helper()
	u, err := svc.UserByName(t.Context(), "admin")
	if err != nil {
		t.Fatal(err)
	}
	uc, err := svc.UserCtx(t.Context(), u)
	if err != nil {
		t.Fatal(err)
	}
	return uc
}

// A podcast library created at a moved directory is picked up through
// the same lookup and its throttle, without a restart: until one sits at
// the configured directory, the one found stands in for it, and a lookup
// a second later looks again.
func TestAPodcastLibraryAtAMovedDirectoryIsPickedUp(t *testing.T) {
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
	feed := &stubFeed{kind: model.SourceRSS, n: 2, prefix: "Episode"}
	open := func(dir string) (*Library, func()) {
		t.Helper()
		_, svc, _, stop := openServiceAt(t, dataDir, func(cfg *Config) {
			cfg.PodcastDir, cfg.PodcastRootName = dir, "podcasts"
			cfg.SourceProviders = []source.Provider{feed}
		})
		return svc, stop
	}
	fetch := func(svc *Library, f stubFeedFixture, apiPID string) {
		t.Helper()
		paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
			Name: "ep", Codec: fixtures.CodecMP3, Container: fixtures.ContainerMP3, Duration: 2 * time.Second,
		})
		if err != nil {
			t.Fatal(err)
		}
		_, bare, _ := parseAPIPID(apiPID)
		if _, err := svc.lib.Podcasts().ImportEpisodeFile(f.ctx, bare, paths[0], false); err != nil {
			t.Fatal(err)
		}
	}

	svc, stop := open(podcasts)
	f := stubFeedFixture{ctx: t.Context(), svc: svc, uc: mustAdmin(t, svc)}
	sub := f.subscribe(t, "https://feeds.example/two", "rss")
	episodes := showEpisodePIDs(t, f, sub.Show.PID)
	fetch(svc, f, episodes[0])
	old, _ := svc.podcastLibrary(f.ctx)
	stop()

	svc, _ = open(moved)
	f.svc = svc
	if got, _ := svc.podcastLibrary(f.ctx); got != old {
		t.Fatalf("before anything lands at the moved directory = %q, want the old library %q", got, old)
	}
	fetch(svc, f, episodes[1])
	libs, err := svc.lib.Libraries(f.ctx)
	if err != nil {
		t.Fatal(err)
	}
	var fresh string
	for _, lib := range libs {
		if lib.Mode == model.ModePodcast && string(lib.PID) != old {
			fresh = string(lib.PID)
		}
	}
	if fresh == "" {
		t.Fatal("the fetch at the moved directory made no library of its own")
	}
	svc.libDirs.mu.Lock()
	svc.libDirs.missed = time.Now().Add(-2 * time.Second)
	svc.libDirs.mu.Unlock()
	if got, _ := svc.podcastLibrary(f.ctx); got != fresh {
		t.Errorf("a second after a library landed at the moved directory = %q, want it, %q", got, fresh)
	}
}
