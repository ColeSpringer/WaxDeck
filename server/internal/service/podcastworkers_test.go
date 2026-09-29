package service

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"path/filepath"
	"testing"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/podcast"
	"github.com/colespringer/waxbin/source"
	"github.com/colespringer/waxbin/waxerr"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// failingSource serves each show a feed on subscribe, then answers its
// syncs with what fails[url] holds.
type failingSource struct {
	fails map[string]error
	armed bool
}

func (s *failingSource) SourceType() model.SourceType { return model.SourceYouTube }

func (s *failingSource) Resolve(_ context.Context, req source.Request) (*source.Resolved, error) {
	return &source.Resolved{IdentityKey: "youtube:" + req.URL, SourceID: req.URL, SourceType: model.SourceYouTube, Title: req.URL}, nil
}

func (s *failingSource) Enumerate(_ context.Context, req source.Request) (*source.Enumeration, error) {
	if s.armed {
		return nil, s.fails[req.URL]
	}
	return &source.Enumeration{Feed: &model.Feed{Title: req.URL}, ETag: "cursor", IdentityKey: "youtube:" + req.URL}, nil
}

func (s *failingSource) Fetch(context.Context, source.FetchRequest, io.Writer) (*source.FetchResult, error) {
	return nil, errors.New("no media")
}

// Only the feed's own failure walks the disable counter; the catalog's
// trouble, a switched-off integration or a canceled sync answers by its
// own kind. Either way the attempt is stamped, spacing the next one out.
func TestASyncFailureCountsOnlyWhenTheFeedIsAtFault(t *testing.T) {
	cases := []struct {
		url    string
		err    error
		counts bool
		kind   ErrorKind
	}{
		{"https://tube.example/network", waxerr.New(waxerr.CodeIO, "fetch", "connection refused"), true, KindUpstream},
		{"https://tube.example/gone", waxerr.New(waxerr.CodeNotFound, "fetch", "returned HTTP 404"), true, KindUpstream},
		{"https://tube.example/html", waxerr.New(waxerr.CodeInvalid, "parse", "not a recognizable RSS podcast feed"), true, KindUpstream},
		{"https://tube.example/provider", waxerr.Wrap(waxerr.CodeIO, "waxtapsource.Enumerate", errors.New("channel does not exist")), true, KindUpstream},
		// Neither a feed nor not-modified, which the catalog refuses as IO.
		{"https://tube.example/empty", nil, true, KindUpstream},
		// The catalog's store classes its own failures IO, like a feed's,
		// or returns them raw, and may join one to another.
		{"https://tube.example/catalog", waxerr.Wrap(waxerr.CodeIO, "store.writeTx", errors.New("database or disk is full")), false, KindInternal},
		{"https://tube.example/raw", errors.New("database or disk is full"), false, KindInternal},
		{"https://tube.example/joined", errors.Join(waxerr.Wrap(waxerr.CodeIO, "store.UpsertFeed", errors.New("disk I/O error")), errors.New("rollback failed")), false, KindInternal},
		{"https://tube.example/off", waxerr.New(waxerr.CodeUnsupported, "podcast", "no provider for youtube"), false, KindUnsupported},
		{"https://tube.example/canceled", context.Canceled, false, KindInternal},
		{"https://tube.example/maintenance", errors.New("sql: database is closed"), false, KindMaintenance},
	}

	src := &failingSource{fails: map[string]error{}}
	ctx, svc, store := openSyncFixture(t, src)

	shows := map[string]model.PID{}
	for _, c := range cases {
		pod, err := svc.lib.Podcasts().AddSource(ctx, c.url, model.SourceYouTube, podcast.AddOptions{})
		if err != nil {
			t.Fatalf("subscribing %s: %v", c.url, err)
		}
		shows[c.url] = pod.PID
		src.fails[c.url] = c.err
	}
	src.armed = true

	for _, c := range cases {
		_, err := svc.syncShow(ctx, shows[c.url], syncOwn)
		if got := KindOf(err); got != c.kind {
			t.Errorf("%s: sync answered %q (%v), want %q", c.url, got, err, c.kind)
		}
		st, err := store.FeedStateFor(ctx, string(shows[c.url]))
		if err != nil {
			t.Fatal(err)
		}
		if counted := st.ConsecutiveFailures == 1; counted != c.counts {
			t.Errorf("%s: %d failures counted, want the failure counted: %v", c.url, st.ConsecutiveFailures, c.counts)
		}
		if st.LastAttemptNS == 0 {
			t.Errorf("%s: the attempt was not stamped", c.url)
		}
	}

	// A show the catalog no longer holds, as after a catalog reset, is
	// still stamped, so it is not asked for every minute.
	gone := model.PID("01JZX5N8QW3F4V9T2B7KD3M9R6")
	if _, err := svc.syncShow(ctx, gone, syncOwn); KindOf(err) != KindNotFound {
		t.Errorf("a vanished show answered %v, want not-found", err)
	}
	if st, err := store.FeedStateFor(ctx, string(gone)); err != nil || st.LastAttemptNS == 0 || st.ConsecutiveFailures != 0 {
		t.Errorf("a vanished show's state = %+v (%v), want the attempt stamped and nothing counted", st, err)
	}
}

// openSyncFixture opens a service over an empty library with src as its
// only source provider, releasing everything it opened however it ends.
func openSyncFixture(t *testing.T, src source.Provider) (context.Context, *Library, *wdb.DB) {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	dataDir := t.TempDir()
	store, err := wdb.Open(ctx, filepath.Join(dataDir, "waxdeck.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { store.Close() })
	var svc *Library
	t.Cleanup(func() {
		if svc != nil {
			svc.Close()
		}
	})
	group := supervise.NewGroup(log)
	t.Cleanup(func() {
		cancel()
		group.Wait()
	})
	svc, err = Open(ctx, Config{
		DataDir:         dataDir,
		Roots:           []Root{{Name: "lib", Path: t.TempDir()}},
		Logger:          log,
		SourceProviders: []source.Provider{src},
	}, store, group)
	if err != nil {
		t.Fatal(err)
	}
	return ctx, svc, store
}

// Every path that reports a feed failure answers the same way for the
// same cause: the feed's own is feed-unreachable, a document that is not
// a feed is invalid (the refusal subscribing shows), the rest by kind.
func TestFeedErrorsAnswerByWhoseFaultTheyAre(t *testing.T) {
	t.Parallel()
	l := &Library{}
	for _, c := range []struct {
		name string
		err  error
		want ErrorKind
	}{
		{"a host that does not answer", waxerr.Wrap(waxerr.CodeIO, "netsafe.Do", errors.New("connection refused")), KindUpstream},
		{"a feed that is gone", waxerr.New(waxerr.CodeNotFound, "netsafe.Do", "returned HTTP 404"), KindUpstream},
		{"a document that is not a feed", waxerr.New(waxerr.CodeInvalid, "podcast.ParseFeed", "not a recognizable RSS podcast feed"), KindInvalid},
		{"the catalog's store", waxerr.Wrap(waxerr.CodeIO, "store.UpsertFeed", errors.New("disk I/O error")), KindInternal},
		{"a raw database error", errors.New("database or disk is full"), KindInternal},
		{"a switched-off source", waxerr.New(waxerr.CodeUnsupported, "podcast", "no provider for youtube"), KindUnsupported},
	} {
		if got := KindOf(l.classifyFeedErr(context.Background(), c.err, "https://feed.example/rss", false)); got != c.want {
			t.Errorf("%s answered %q, want %q", c.name, got, c.want)
		}
	}
}
