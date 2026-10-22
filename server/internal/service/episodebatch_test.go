package service

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"path/filepath"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/source"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// stubFeed is a feed of n episodes behind a stand-in provider for its
// source type, so a test can catalog hundreds of episodes, retitle them
// and name their enclosures without a feed host.
type stubFeed struct {
	kind model.SourceType
	mu   sync.Mutex
	n    int
	// prefix starts every title; changing it makes a refresh update
	// every episode.
	prefix string
	// enclosure names episode i's enclosure; nil serves a plain mp3 URL.
	enclosure func(i int) (url, mimeType string)
}

func (f *stubFeed) SourceType() model.SourceType { return f.kind }

func (f *stubFeed) Resolve(_ context.Context, req source.Request) (*source.Resolved, error) {
	return &source.Resolved{IdentityKey: string(f.kind) + ":" + req.URL, SourceID: req.URL, SourceType: f.kind, Title: req.URL}, nil
}

func (f *stubFeed) Enumerate(_ context.Context, req source.Request) (*source.Enumeration, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	feed := &model.Feed{Title: "Stub Cast " + req.URL}
	base := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	for i := range f.n {
		url, mimeType := fmt.Sprintf("https://cdn.example/stub-%03d.mp3", i), "audio/mpeg"
		if f.enclosure != nil {
			url, mimeType = f.enclosure(i)
		}
		feed.Episodes = append(feed.Episodes, model.FeedEpisode{
			GUID:          fmt.Sprintf("stub-%03d", i),
			Title:         fmt.Sprintf("%s %03d", f.prefix, i),
			PubDateNS:     base.Add(time.Duration(i) * time.Hour).UnixNano(),
			DurationMS:    60_000,
			EnclosureURL:  url,
			EnclosureType: mimeType,
		})
	}
	return &source.Enumeration{Feed: feed, IdentityKey: string(f.kind) + ":" + req.URL}, nil
}

func (f *stubFeed) Fetch(context.Context, source.FetchRequest, io.Writer) (*source.FetchResult, error) {
	return nil, errors.New("no media")
}

func (f *stubFeed) retitle(prefix string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.prefix = prefix
}

// stubFeedFixture is a library cataloging episodes from stand-in
// providers, with an administrator to read them as.
type stubFeedFixture struct {
	ctx context.Context
	svc *Library
	uc  *UserCtx
}

func openStubFeeds(t *testing.T, feeds ...*stubFeed) stubFeedFixture {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	dataDir := t.TempDir()
	store, err := wdb.Open(ctx, filepath.Join(dataDir, "waxdeck.db"))
	if err != nil {
		t.Fatal(err)
	}
	providers := make([]source.Provider, 0, len(feeds))
	for _, f := range feeds {
		providers = append(providers, f)
	}
	group := supervise.NewGroup(log)
	svc, err := Open(ctx, Config{
		DataDir:         dataDir,
		Roots:           []Root{{Name: "lib", Path: t.TempDir()}},
		PodcastDir:      t.TempDir(),
		PodcastRootName: "podcasts",
		Logger:          log,
		SourceProviders: providers,
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
	acct, err := svc.CreateAccount(ctx, AccountCreate{Username: "admin", Password: "correct-horse", Roles: []string{"admin"}})
	if err != nil {
		t.Fatal(err)
	}
	uc, err := svc.UserCtx(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	return stubFeedFixture{ctx: ctx, svc: svc, uc: uc}
}

func (f stubFeedFixture) subscribe(t *testing.T, url, sourceType string) Subscription {
	t.Helper()
	sub, _, err := f.svc.Subscribe(f.ctx, f.uc, SubscribeRequest{URL: url, SourceType: sourceType})
	if err != nil {
		t.Fatalf("subscribing to %s: %v", url, err)
	}
	return sub
}

// countEpisodeReads routes the library's episode reads through a counter.
func countEpisodeReads(svc *Library) *atomic.Int64 {
	var n atomic.Int64
	svc.episodeReadHook = func(ctx context.Context, pids []model.PID) ([]*model.Episode, error) {
		n.Add(1)
		return svc.lib.Podcasts().EpisodesByPIDs(ctx, pids)
	}
	return &n
}

// A cross-show listing hydrates the page it cut in one catalog read,
// whatever the page holds.
func TestEpisodeRowsReadTheCatalogOncePerPage(t *testing.T) {
	t.Parallel()
	feed := &stubFeed{kind: model.SourceRSS, n: 60, prefix: "Episode"}
	f := openStubFeeds(t, feed)
	f.subscribe(t, "https://feeds.example/sixty", "rss")
	reads := countEpisodeReads(f.svc)

	rows, next, err := f.svc.SubscribedEpisodes(f.ctx, f.uc, EpisodesLatest, "", 25)
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 25 || next == "" {
		t.Fatalf("first page = %d rows (next %q), want 25 and more to come", len(rows), next)
	}
	if got := reads.Load(); got != 1 {
		t.Errorf("the first page read the catalog %d times, want once", got)
	}
	if rows[0].Title != "Episode 059" || !rows[0].HasEnclosure || rows[0].ShowPID == "" {
		t.Errorf("first row = %+v, want the newest episode with its show and enclosure", rows[0])
	}
	rows, _, err = f.svc.SubscribedEpisodes(f.ctx, f.uc, EpisodesLatest, next, 25)
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 25 || reads.Load() != 2 {
		t.Errorf("second page = %d rows after %d reads, want 25 after 2", len(rows), reads.Load())
	}
}

// A first mirror of a large podcast library reads its episodes a page
// at a time, and so does the delta that follows a refresh touching all
// of them, rather than one catalog read per episode.
func TestSyncSnapshotEpisodesBatch(t *testing.T) {
	t.Parallel()
	feed := &stubFeed{kind: model.SourceRSS, n: 300, prefix: "Episode"}
	f := openStubFeeds(t, feed)
	sub := f.subscribe(t, "https://feeds.example/three-hundred", "rss")
	reads := countEpisodeReads(f.svc)

	const limit = 100
	episodes := map[string]EpisodeSummary{}
	cursor, since := "", ""
	itemPages := 0
	for range 20 {
		page, err := f.svc.SyncCatalogSnapshot(f.ctx, f.uc, cursor, limit)
		if err != nil {
			t.Fatal(err)
		}
		since = page.NextSince
		for _, e := range page.Entries {
			if e.Item == nil {
				continue
			}
			if e.Episode == nil {
				t.Fatalf("episode %s mirrored without its episode payload", e.PID)
			}
			episodes[e.PID] = *e.Episode
		}
		if len(page.Entries) > 0 && page.Entries[0].Item != nil {
			itemPages++
		}
		if page.NextCursor == "" {
			break
		}
		cursor = page.NextCursor
	}
	if len(episodes) != 300 {
		t.Fatalf("mirrored %d episodes, want 300", len(episodes))
	}
	for pid, ep := range episodes {
		if ep.ShowPID != sub.Show.PID || !ep.HasEnclosure {
			t.Fatalf("episode %s = %+v, want its show and its enclosure", pid, ep)
		}
	}
	if got := reads.Load(); got != int64(itemPages) {
		t.Errorf("the snapshot read the catalog %d times over %d pages, want once a page", got, itemPages)
	}

	feed.retitle("Remastered")
	if _, err := f.svc.RefreshPodcast(f.ctx, f.uc, sub.Show.PID); err != nil {
		t.Fatal(err)
	}
	reads.Store(0)
	delta, err := f.svc.SyncCatalogDelta(f.ctx, f.uc, since, 500)
	if err != nil {
		t.Fatal(err)
	}
	retitled := 0
	for _, e := range delta.Entries {
		if e.Episode != nil && e.Episode.Title[:10] == "Remastered" {
			retitled++
		}
	}
	if retitled != 300 {
		t.Errorf("the delta carried %d retitled episodes, want 300", retitled)
	}
	if got := reads.Load(); got != 1 {
		t.Errorf("the delta read the catalog %d times, want once", got)
	}
}
