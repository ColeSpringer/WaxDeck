package service

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/colespringer/waxbin/model"
)

// snapshotEpisodes pages a caller's whole sync snapshot, answering the
// episode pids it mirrored and the cursor its delta starts from.
func snapshotEpisodes(t *testing.T, f stubFeedFixture, uc *UserCtx) (map[string]bool, string, error) {
	t.Helper()
	got := map[string]bool{}
	cursor, since := "", ""
	for range 50 {
		page, err := f.svc.SyncCatalogSnapshot(f.ctx, uc, cursor, 100)
		if err != nil {
			return nil, "", err
		}
		since = page.NextSince
		for _, e := range page.Entries {
			if e.Episode != nil {
				got[e.PID] = true
			}
		}
		if page.NextCursor == "" {
			return got, since, nil
		}
		cursor = page.NextCursor
	}
	t.Fatal("the snapshot never ended")
	return nil, "", nil
}

// deltaEpisodes answers the episode pids a caller's delta carried.
func deltaEpisodes(f stubFeedFixture, uc *UserCtx, since string) (map[string]bool, error) {
	delta, err := f.svc.SyncCatalogDelta(f.ctx, uc, since, 500)
	if err != nil {
		return nil, err
	}
	got := map[string]bool{}
	for _, e := range delta.Entries {
		if e.Episode != nil {
			got[e.PID] = true
		}
	}
	return got, nil
}

// A caller who cannot see the podcast library has no episode read for
// it: the sync's pages, first mirror and delta alike, hydrate only rows
// the caller will be sent.
func TestASyncWithoutPodcastsReadsNoEpisodes(t *testing.T) {
	t.Parallel()
	feed := &stubFeed{kind: model.SourceRSS, n: 30, prefix: "Episode"}
	f := openStubFeeds(t, feed)
	sub := f.subscribe(t, "https://feeds.example/thirty", "rss")
	music := grantedUploader(t, f.ctx, f.svc, "listener", "lib")
	reads := countEpisodeReads(f.svc)

	got, since, err := snapshotEpisodes(t, f, music)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 0 || reads.Load() != 0 {
		t.Errorf("a music-only snapshot carried %d episodes after %d episode reads, want none of either", len(got), reads.Load())
	}
	feed.retitle("Remastered")
	if _, err := f.svc.RefreshPodcast(f.ctx, f.uc, sub.Show.PID); err != nil {
		t.Fatal(err)
	}
	if _, err := deltaEpisodes(f, music, since); err != nil {
		t.Fatal(err)
	}
	if got := reads.Load(); got != 0 {
		t.Errorf("a music-only delta read episodes %d times, want none", got)
	}
}

// Batching kept what the per-row reads did: an episode the read leaves
// out is skipped and the rest of the page still served, and a read that
// fails fails the page rather than serving one that looks complete.
func TestEpisodePagesSkipAMissingEpisodeAndFailOnAFailedRead(t *testing.T) {
	t.Parallel()
	feed := &stubFeed{kind: model.SourceRSS, n: 10, prefix: "Episode"}
	f := openStubFeeds(t, feed)
	sub := f.subscribe(t, "https://feeds.example/ten", "rss")
	all := showEpisodePIDs(t, f, sub.Show.PID)
	_, since, err := snapshotEpisodes(t, f, f.uc)
	if err != nil {
		t.Fatal(err)
	}
	feed.retitle("Remastered")
	if _, err := f.svc.RefreshPodcast(f.ctx, f.uc, sub.Show.PID); err != nil {
		t.Fatal(err)
	}
	gone := all[3]
	_, goneBare, _ := parseAPIPID(gone)
	broken := errors.New("the episode read broke")
	var fail bool
	f.svc.episodeReadHook = func(ctx context.Context, pids []model.PID) ([]*model.Episode, error) {
		if fail {
			return nil, broken
		}
		eps, err := f.svc.lib.Podcasts().EpisodesByPIDs(ctx, pids)
		kept := eps[:0]
		for _, ep := range eps {
			if ep.PID != goneBare {
				kept = append(kept, ep)
			}
		}
		return kept, err
	}
	surfaces := map[string]func() (map[string]bool, error){
		"the cross-show listing": func() (map[string]bool, error) {
			rows, _, err := f.svc.SubscribedEpisodes(f.ctx, f.uc, EpisodesLatest, "", 25)
			got := map[string]bool{}
			for _, r := range rows {
				got[r.PID] = true
			}
			return got, err
		},
		"the sync snapshot": func() (map[string]bool, error) {
			got, _, err := snapshotEpisodes(t, f, f.uc)
			return got, err
		},
		"the sync delta": func() (map[string]bool, error) { return deltaEpisodes(f, f.uc, since) },
	}
	for name, read := range surfaces {
		fail = false
		got, err := read()
		if err != nil {
			t.Errorf("%s with one episode left out: %v", name, err)
			continue
		}
		if got[gone] {
			t.Errorf("%s served the episode the read left out", name)
		}
		if len(got) != len(all)-1 {
			t.Errorf("%s served %d episodes, want the other %d", name, len(got), len(all)-1)
		}
		fail = true
		if _, err := read(); err == nil || !strings.Contains(err.Error(), broken.Error()) {
			t.Errorf("%s with the read failing: %v, want the failure", name, err)
		}
	}
}
