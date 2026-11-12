package service

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"

	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// mappingJobs is a jobs surface that answers every analysis with one
// silence span.
type mappingJobs struct{ stubFlowJobs }

func (mappingJobs) AnalyzeSilence(context.Context, string) (flow.SilenceAnalysis, error) {
	return flow.SilenceAnalysis{Version: "v1", Rate: 1000, DurationSeconds: 1,
		Spans: []flow.SilenceSpan{{FromSample: 0, ToSample: 250}}}, nil
}

// refetchShow is a one-episode show followed by the administrator, whose
// host answers each download of the episode with the next of its audio
// files, and the last one from then on.
type refetchShow struct {
	ctx           context.Context
	svc           *Library
	admin         *UserCtx
	logs          *syncBuffer
	show, episode string // api pids
	bare          model.PID
}

func newRefetchShow(t *testing.T, audio ...[]byte) refetchShow {
	t.Helper()
	dir := t.TempDir()
	logs := &syncBuffer{}
	ctx, svc, admin, _ := openServiceAt(t, dir, func(cfg *Config) {
		cfg.PodcastDir = filepath.Join(dir, "podcasts")
		cfg.PodcastRootName = "podcasts"
		cfg.AllowPrivateFeedHosts = true
		cfg.Logger = slog.New(slog.NewTextHandler(logs, &slog.HandlerOptions{Level: slog.LevelDebug}))
	})
	svc.Tools.SetFlowJobs(mappingJobs{stubFlowJobs{jobs: true, version: "v1"}})
	var downloads atomic.Int32
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, ".mp3") {
			w.Header().Set("Content-Type", "audio/mpeg")
			_, _ = w.Write(audio[min(int(downloads.Add(1)), len(audio))-1])
			return
		}
		w.Header().Set("Content-Type", "application/rss+xml")
		fmt.Fprintf(w, `<?xml version="1.0"?><rss version="2.0"><channel><title>Refetch Show</title>`+
			`<item><title>Episode</title><guid>refetch-1</guid>`+
			`<enclosure url="http://%s/episode.mp3" type="audio/mpeg" length="1"/></item></channel></rss>`, r.Host)
	}))
	t.Cleanup(ts.Close)
	sub, _, err := svc.Podcasts.Subscribe(ctx, admin, SubscribeRequest{URL: ts.URL + "/feed.xml"})
	if err != nil {
		t.Fatal(err)
	}
	eps, _, err := svc.Podcasts.Episodes(ctx, admin, sub.Show.PID, "", 10)
	if err != nil || len(eps) != 1 {
		t.Fatalf("episodes = %+v (%v), want one", eps, err)
	}
	_, bare, _ := parseAPIPID(eps[0].PID)
	return refetchShow{ctx: ctx, svc: svc, admin: admin, logs: logs, show: sub.Show.PID, episode: eps[0].PID, bare: bare}
}

// podcastAudio is an MP3 episode's bytes, lasting d.
func podcastAudio(t *testing.T, d time.Duration) []byte {
	t.Helper()
	paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
		Name: "episode", Codec: fixtures.CodecMP3, Container: fixtures.ContainerMP3, Duration: d,
	})
	if err != nil {
		t.Fatal(err)
	}
	b, err := os.ReadFile(paths[0])
	if err != nil {
		t.Fatal(err)
	}
	return b
}

// fetch lands the episode, which queues its analysis.
func (s refetchShow) fetch(t *testing.T) {
	t.Helper()
	if err := s.svc.Podcasts.QueueEpisodeFetch(s.ctx, s.admin, s.episode); err != nil {
		t.Fatal(err)
	}
	if !s.svc.Podcasts.DrainFetchQueue(s.ctx) || !s.downloaded(t) {
		t.Fatal("the fetch did not land")
	}
}

func (s refetchShow) unfetch(t *testing.T) {
	t.Helper()
	if err := s.svc.Podcasts.RemoveEpisodeDownload(s.ctx, s.admin, s.episode); err != nil {
		t.Fatal(err)
	}
}

func (s refetchShow) downloaded(t *testing.T) bool {
	t.Helper()
	eps, _, err := s.svc.Podcasts.Episodes(s.ctx, s.admin, s.show, "", 10)
	if err != nil || len(eps) != 1 {
		t.Fatalf("episodes = %+v (%v), want one", eps, err)
	}
	return eps[0].Downloaded
}

// essence is the audio essence of the episode's file in the catalog now.
func (s refetchShow) essence(t *testing.T) string {
	t.Helper()
	it, err := s.svc.lib.Get(s.ctx, s.bare)
	if err != nil {
		t.Fatal(err)
	}
	f, err := s.svc.lib.File(s.ctx, it.FilePID)
	if err != nil {
		t.Fatal(err)
	}
	return f.EssenceHash
}

// An analysis a landing queued outlives an unfetch of the episode, and the
// worker can run it as the episode is fetched again. The refetch lands
// where it does in that race, between the catalog's check that the episode
// has no audio and the write that marks it missing, if the analysis gets
// that far.
func TestAStaleAnalysisLeavesARefetchedEpisodeDownloaded(t *testing.T) {
	t.Parallel()
	s := newRefetchShow(t, podcastAudio(t, time.Second))
	s.fetch(t)
	s.unfetch(t)
	if err := s.svc.Podcasts.QueueEpisodeFetch(s.ctx, s.admin, s.episode); err != nil {
		t.Fatal(err)
	}

	landed := false
	s.svc.Tools.markMissingHook = func(ctx context.Context, pid model.PID) (model.MarkMissingOutcome, error) {
		s.svc.Tools.markMissingHook = nil
		// MarkMissing's check: an unfetched episode has no file to stat, so
		// the state its write reads decides, and the refetch commits first.
		if refs, err := s.svc.lib.ItemFiles(ctx, pid); err != nil || len(refs) != 0 {
			t.Errorf("the unfetched episode's files = %+v (%v), want none", refs, err)
		}
		landed = s.svc.Podcasts.DrainFetchQueue(ctx)
		// The write alone.
		return s.svc.lib.MarkMissing(ctx, pid, waxbin.MarkMissingOptions{Force: true})
	}
	if !s.svc.Tools.DrainAnalysisQueue(s.ctx) {
		t.Fatal("the first landing queued no analysis")
	}
	if !landed && !s.svc.Podcasts.DrainFetchQueue(s.ctx) {
		t.Fatal("the refetch did not land")
	}
	if !s.downloaded(t) {
		t.Fatalf("the refetched episode reads not downloaded; log:\n%s", s.logs)
	}
	if logs := s.logs.String(); !strings.Contains(logs, `no longer holds its audio" key=`+s.essence(t)+" item="+string(s.bare)) {
		t.Errorf("the stale analysis was dropped without a log naming its key and item:\n%s", logs)
	}

	// The refetch still gets its skip map.
	for s.svc.Tools.DrainAnalysisQueue(s.ctx) {
	}
	sm, err := s.svc.Tools.SkipMapFor(s.ctx, s.admin, s.episode, 0)
	if err != nil || sm.State != skipStateReady {
		t.Errorf("skip map after the refetch's analysis = %+v (%v), want ready", sm, err)
	}
}

// A stale analysis measures nothing that replaced its audio either: a host
// that changes the file between downloads lands other bytes, and their
// silences filed under the audio the analysis was queued for would trim
// speech wherever that audio plays.
func TestAStaleAnalysisNeverMeasuresTheAudioThatReplacedIt(t *testing.T) {
	t.Parallel()
	s := newRefetchShow(t, podcastAudio(t, time.Second), podcastAudio(t, 2*time.Second))
	s.fetch(t)
	was := s.essence(t)
	s.unfetch(t)
	s.fetch(t)
	now := s.essence(t)
	if now == was {
		t.Fatalf("both downloads have essence %s; the host has to change the audio", now)
	}

	for s.svc.Tools.DrainAnalysisQueue(s.ctx) {
	}
	if m, err := s.svc.db.SilenceMapFor(s.ctx, was); !errors.Is(err, wdb.ErrNotFound) {
		t.Errorf("the replaced audio's silence map = %+v (%v), want none: it measured the download that replaced it", m, err)
	}
	if _, err := s.svc.db.SilenceMapFor(s.ctx, now); err != nil {
		t.Errorf("the refetched audio's silence map: %v", err)
	}
}

// The audio can change while the engine measures it, after the drain
// checked the item: what the engine measured may be either, so it is filed
// under neither essence.
func TestASilenceMapOvertakenByARewriteIsFiledNowhere(t *testing.T) {
	t.Parallel()
	s := newRewrittenTrack(t)
	was := s.queueSilence(t, func(ctx context.Context, path string) (flow.SilenceAnalysis, error) {
		s.rewrite(t)
		return oneSpan(ctx, path)
	})

	for s.svc.Tools.DrainAnalysisQueue(s.ctx) {
	}
	if m, err := s.svc.db.SilenceMapFor(s.ctx, was); !errors.Is(err, wdb.ErrNotFound) {
		t.Errorf("the replaced audio's silence map = %+v (%v), want none: it may measure the audio that replaced it", m, err)
	}
	if _, err := silenceRowFree(t, s.ctx, s.svc); !errors.Is(err, wdb.ErrNotFound) {
		t.Errorf("the overtaken analysis stays queued (%v)", err)
	}
}
