package service

import (
	"context"
	"errors"
	"sync/atomic"
	"testing"

	"github.com/colespringer/waxbin/model"
)

// countShowReads routes showSourceType's show reads through a counter,
// failing them while fail is set.
func countShowReads(svc *Library, fail *atomic.Bool) *atomic.Int64 {
	var n atomic.Int64
	svc.showReadHook = func(ctx context.Context, pid model.PID) (*model.Podcast, error) {
		n.Add(1)
		if fail.Load() {
			return nil, errors.New("the catalog is busy")
		}
		return svc.lib.Podcasts().Get(ctx, pid)
	}
	return &n
}

// A page of one show's episodes reads the show's source once, and the
// next page not at all; a read that fails says no episode has audio to
// relay, as the relay itself would, and is not remembered.
func TestEpisodeRowsReadTheirShowOnce(t *testing.T) {
	t.Parallel()
	feed := &stubFeed{kind: model.SourceRSS, n: 50, prefix: "Episode"}
	f := openStubFeeds(t, feed)
	f.subscribe(t, "https://feeds.example/fifty", "rss")
	f.svc.showSources.Clear()
	var fail atomic.Bool
	reads := countShowReads(f.svc, &fail)
	page := func(cursor string) ([]EpisodeSummary, string) {
		t.Helper()
		rows, next, err := f.svc.SubscribedEpisodes(f.ctx, f.uc, EpisodesLatest, cursor, 25)
		if err != nil {
			t.Fatal(err)
		}
		return rows, next
	}

	fail.Store(true)
	rows, _ := page("")
	for _, r := range rows {
		if r.HasEnclosure {
			t.Fatalf("%s says it has audio to relay while its show cannot be read", r.Title)
		}
	}
	fail.Store(false)
	reads.Store(0)
	rows, next := page("")
	if got := reads.Load(); got != 1 {
		t.Errorf("a page of %d rows read the show %d times, want once", len(rows), got)
	}
	if !rows[0].HasEnclosure {
		t.Errorf("%s has no audio once its show reads", rows[0].Title)
	}
	page(next)
	if got := reads.Load(); got != 1 {
		t.Errorf("the next page read the show again: %d reads", got)
	}
}
