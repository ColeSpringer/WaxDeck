package service

import (
	"context"
	"encoding/json"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/syncsource"
)

// droppingLister lists without "one" once drop is set.
type droppingLister struct {
	stallingLister
	drop atomic.Bool
}

func (s *droppingLister) PlaylistSnapshot(ctx context.Context, id string, opts syncsource.SnapshotOptions) (*syncsource.PlaylistSnapshot, error) {
	snap, err := s.stallingLister.PlaylistSnapshot(ctx, id, opts)
	if err == nil && s.drop.Load() {
		snap.Entries = snap.Entries[1:]
	}
	return snap, err
}

// A playlist sync whose waits run out says how much it staged before, as
// one a verdict cuts short does, counting what it staged that the source
// no longer lists.
func TestASyncWhoseWaitsRunOutSaysWhatStaged(t *testing.T) {
	t.Parallel()
	for name, drop := range map[string]bool{"listed": false, "dropped by the source": true} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			src := &droppingLister{stallingLister: stallingLister{eventfulSource{
				events: map[string][]syncsource.FetchEvent{"three": {{Phase: syncsource.PhaseDownloading}}},
				hold:   "three", release: make(chan struct{}),
			}}}
			ctx, svc, uc := acquireFixture(t, src)
			svc.Ingest.acquireStallWindow = 100 * time.Millisecond
			pid := boundPlaylist(t, ctx, svc, uc)
			task, err := svc.Playlists.SyncPlaylistSourceNow(ctx, uc, pid)
			if err != nil {
				t.Fatal(err)
			}
			at := time.Now()
			for range toolSourceWaits + 1 {
				drainTaskAt(t, ctx, svc, at)
				src.drop.Store(drop)
				if storedTask(t, ctx, svc, task.ID).State != taskStateRunning {
					break
				}
				at = at.Add(24 * time.Hour)
			}
			row := storedTask(t, ctx, svc, task.ID)
			var params map[string]string
			_ = json.Unmarshal([]byte(row.ErrorParams), &params)
			if row.State != taskStateFailed || row.ErrorCode != "source-refused" || params["reason"] != reasonStalled ||
				!strings.HasPrefix(row.Error, "2 of 3 items staged before: ") {
				t.Errorf("sync = %s, code %q %v, error %q, want it failed as source-refused for stalled saying two of three staged",
					row.State, row.ErrorCode, params, row.Error)
			}
		})
	}
}

// A cut-short batch counts the task's staged items against the batch and
// the staged items it no longer lists.
func TestACutShortBatchCountsWhatEarlierRunsStaged(t *testing.T) {
	t.Parallel()
	fetched := []fetchedItem{{Key: "one"}, {Key: "two"}}
	for name, batch := range map[string][]acquireItem{
		"all listed":        {{GUID: "one"}, {GUID: "two"}, {GUID: "three"}},
		"staged not listed": {{GUID: "three"}},
		"one of them":       {{GUID: "two"}, {GUID: "three"}},
	} {
		if got := cutShort(fetched, batch, nil); got.staged != 2 || got.total != 3 {
			t.Errorf("%s: %d of %d, want 2 of 3", name, got.staged, got.total)
		}
	}
}
