package service

import (
	"cmp"
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

// playlistShow is a followed show of two episodes whose host answers a
// playlist for both: "Declared" says so in its feed, "Disguised" is
// declared as mp3.
type playlistShow struct {
	ctx      context.Context
	svc      *Library
	admin    *UserCtx
	show     string
	episodes map[string]string // api pid by title
}

func newPlaylistShow(t *testing.T) playlistShow {
	t.Helper()
	dir := t.TempDir()
	ctx, svc, admin, _ := openServiceAt(t, dir, func(cfg *Config) {
		cfg.PodcastDir = filepath.Join(dir, "podcasts")
		cfg.PodcastRootName = "podcasts"
		cfg.AllowPrivateFeedHosts = true
	})
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, ".xml") {
			w.Header().Set("Content-Type", "application/rss+xml")
			fmt.Fprintf(w, `<?xml version="1.0"?><rss version="2.0"><channel><title>Playlist Show</title>`+
				`<item><title>Declared</title><guid>pl-1</guid><pubDate>%s</pubDate>`+
				`<enclosure url="http://%s/list.m3u" type="audio/x-mpegurl" length="1"/></item>`+
				`<item><title>Disguised</title><guid>pl-2</guid><pubDate>%s</pubDate>`+
				`<enclosure url="http://%s/ep.mp3" type="audio/mpeg" length="1"/></item>`+
				`</channel></rss>`,
				time.Date(2026, 6, 2, 8, 0, 0, 0, time.UTC).Format(time.RFC1123Z), r.Host,
				time.Date(2026, 6, 1, 8, 0, 0, 0, time.UTC).Format(time.RFC1123Z), r.Host)
			return
		}
		w.Header().Set("Content-Type", "audio/x-mpegurl")
		fmt.Fprint(w, "#EXTM3U\nhttp://stream.example/live.mp3\n")
	}))
	t.Cleanup(ts.Close)
	s := playlistShow{ctx: ctx, svc: svc, admin: admin, episodes: map[string]string{}}
	sub, _, err := svc.Subscribe(ctx, admin, SubscribeRequest{URL: ts.URL + "/feed.xml"})
	if err != nil {
		t.Fatal(err)
	}
	s.show = sub.Show.PID
	eps, _, err := svc.Episodes(ctx, admin, s.show, "", 10)
	if err != nil || len(eps) != 2 {
		t.Fatalf("episodes = %+v (%v), want two", eps, err)
	}
	for _, ep := range eps {
		s.episodes[ep.Title] = ep.PID
	}
	return s
}

// queued reports whether a fetch of the episode is queued.
func (s playlistShow) queued(t *testing.T, title string) bool {
	t.Helper()
	_, bare, _ := parseAPIPID(s.episodes[title])
	rows, err := s.svc.db.FetchQueueRows(s.ctx, []string{string(bare)})
	if err != nil {
		t.Fatal(err)
	}
	_, ok := rows[string(bare)]
	return ok
}

// An episode whose feed calls its enclosure a playlist has no audio to
// fetch: asking for it queues nothing, as the relay plays nothing.
func TestAPlaylistTheFeedDeclaresIsNeverQueued(t *testing.T) {
	s := newPlaylistShow(t)
	if err := s.svc.QueueEpisodeFetch(s.ctx, s.admin, s.episodes["Declared"]); KindOf(err) != KindNotFound {
		t.Errorf("queuing a declared playlist = %v, want not-found", err)
	}
	if s.queued(t, "Declared") {
		t.Error("a declared playlist sits in the fetch queue")
	}
}

// One the relay found its host answering with a playlist is refused the
// same way, though its feed called it audio.
func TestAPlaylistTheRelaySawIsNeverQueued(t *testing.T) {
	s := newPlaylistShow(t)
	src, err := s.svc.EnclosureStreamSource(s.ctx, s.admin.ID, s.episodes["Disguised"])
	if err != nil {
		t.Fatal(err)
	}
	req, err := http.NewRequestWithContext(s.ctx, http.MethodGet, src.URL, nil)
	if err != nil {
		t.Fatal(err)
	}
	resp, err := s.svc.FetchEnclosure(req, src)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if err := s.svc.QueueEpisodeFetch(s.ctx, s.admin, s.episodes["Disguised"]); KindOf(err) != KindNotFound {
		t.Errorf("queuing an episode its host answers with a playlist = %v, want not-found", err)
	}
	if s.queued(t, "Disguised") {
		t.Error("an answered playlist sits in the fetch queue")
	}
}

// A fetch queued before anyone knew is dropped when its turn comes, read
// as failed with the not-audio sentence, and the playlist is not stored
// as the episode.
func TestAQueuedPlaylistIsNotStoredAsTheEpisode(t *testing.T) {
	s := newPlaylistShow(t)
	_, bare, _ := parseAPIPID(s.episodes["Declared"])
	if err := s.svc.db.EnqueueFetch(s.ctx, string(bare), s.admin.ID, time.Now().UnixNano(), fetchMaxAttempts); err != nil {
		t.Fatal(err)
	}
	if !s.svc.DrainFetchQueue(s.ctx) {
		t.Fatal("the queued fetch did not run")
	}
	eps, _, err := s.svc.Episodes(s.ctx, s.admin, s.show, "", 10)
	if err != nil {
		t.Fatal(err)
	}
	for _, ep := range eps {
		if ep.Title != "Declared" {
			continue
		}
		if ep.Downloaded {
			t.Error("the playlist was stored as the episode")
		}
		if ep.FetchState != "failed" || ep.FetchError != downloadSentences[reasonNotAFeed] {
			t.Errorf("the dropped fetch reads %q (%q), want failed with the not-audio sentence", ep.FetchState, ep.FetchError)
		}
	}
}

// relayOnce sends one relay request for the episode at target, the
// feed's own address when target is empty, and answers its type.
func relayOnce(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, episode, target string) string {
	t.Helper()
	src, err := svc.EnclosureStreamSource(ctx, uc.ID, episode)
	if err != nil {
		t.Fatal(err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, cmp.Or(target, src.URL), nil)
	if err != nil {
		t.Fatal(err)
	}
	resp, err := svc.FetchEnclosure(req, src)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	return resp.Header.Get("Content-Type")
}

// changingHost serves a one-episode feed whose enclosure host answers
// each request with the next of answers (status and type), the last one
// for every request after.
func changingHost(t *testing.T, answers ...[2]any) (context.Context, *Library, *UserCtx, string, string) {
	t.Helper()
	dir := t.TempDir()
	ctx, svc, admin, _ := openServiceAt(t, dir, func(cfg *Config) {
		cfg.PodcastDir = filepath.Join(dir, "podcasts")
		cfg.PodcastRootName = "podcasts"
		cfg.AllowPrivateFeedHosts = true
	})
	var asked atomic.Int64
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, ".xml") {
			w.Header().Set("Content-Type", "application/rss+xml")
			fmt.Fprintf(w, `<?xml version="1.0"?><rss version="2.0"><channel><title>Changing</title>`+
				`<item><title>One</title><guid>ch-1</guid><pubDate>%s</pubDate>`+
				`<enclosure url="http://%s/ep.mp3" type="audio/mpeg" length="1"/></item></channel></rss>`,
				time.Date(2026, 6, 2, 8, 0, 0, 0, time.UTC).Format(time.RFC1123Z), r.Host)
			return
		}
		answer := answers[min(int(asked.Add(1)), len(answers))-1]
		w.Header().Set("Content-Type", answer[1].(string))
		w.WriteHeader(answer[0].(int))
		fmt.Fprint(w, "#EXTM3U\nhttp://stream.example/live.mp3\n")
	}))
	t.Cleanup(ts.Close)
	sub, _, err := svc.Subscribe(ctx, admin, SubscribeRequest{URL: ts.URL + "/feed.xml"})
	if err != nil {
		t.Fatal(err)
	}
	eps, _, err := svc.Episodes(ctx, admin, sub.Show.PID, "", 10)
	if err != nil || len(eps) != 1 {
		t.Fatalf("episodes = %+v (%v), want one", eps, err)
	}
	return ctx, svc, admin, eps[0].PID, ts.URL
}

// A host that answered a playlist once and audio since has audio to
// fetch: an answer the relay plays forgets the sighting.
func TestAPlaylistAnswerFollowedByAudioIsForgotten(t *testing.T) {
	ctx, svc, admin, episode, _ := changingHost(t,
		[2]any{http.StatusOK, "audio/x-mpegurl"}, [2]any{http.StatusOK, "audio/mpeg"})
	for range 3 {
		relayOnce(t, ctx, svc, admin, episode, "")
	}
	if err := svc.QueueEpisodeFetch(ctx, admin, episode); err != nil {
		t.Errorf("queuing an episode whose host now answers audio = %v, want it queued", err)
	}
}

// Only a playlist the feed's own address answered, with a body, is the
// episode's: a remembered chain end the relay distrusts, or a refusal
// typed as a playlist, says nothing about it.
func TestOnlyTheFeedsAddressAnsweringAPlaylistCounts(t *testing.T) {
	ctx, svc, admin, episode, host := changingHost(t, [2]any{http.StatusOK, "audio/x-mpegurl"})
	relayOnce(t, ctx, svc, admin, episode, host+"/chain-end.mp3")
	if err := svc.QueueEpisodeFetch(ctx, admin, episode); err != nil {
		t.Errorf("queuing after a chain end answered a playlist = %v, want it queued", err)
	}

	ctx, svc, admin, episode, _ = changingHost(t, [2]any{http.StatusNotFound, "audio/x-mpegurl"})
	relayOnce(t, ctx, svc, admin, episode, "")
	if err := svc.QueueEpisodeFetch(ctx, admin, episode); err != nil {
		t.Errorf("queuing after a refusal typed as a playlist = %v, want it queued", err)
	}
}
