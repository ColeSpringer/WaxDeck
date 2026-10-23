package service

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"

	"github.com/colespringer/waxdeck/fixtures"
)

// landingShow is a show of four episodes followed by the administrator,
// the oldest three on the server and the newest fetchable from its host.
type landingShow struct {
	ctx      context.Context
	svc      *Library
	admin    *UserCtx
	feed     string
	show     string            // the api pid
	episodes map[string]string // api pid by title
}

func newLandingShow(t *testing.T) landingShow {
	t.Helper()
	dir := t.TempDir()
	ctx, svc, admin, _ := openServiceAt(t, dir, func(cfg *Config) {
		cfg.PodcastDir = filepath.Join(dir, "podcasts")
		cfg.PodcastRootName = "podcasts"
		cfg.AllowPrivateFeedHosts = true
	})
	paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
		Name: "landing", Codec: fixtures.CodecMP3, Container: fixtures.ContainerMP3, Duration: time.Second,
	})
	if err != nil {
		t.Fatal(err)
	}
	audio, err := os.ReadFile(paths[0])
	if err != nil {
		t.Fatal(err)
	}
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, ".mp3") {
			w.Header().Set("Content-Type", "audio/mpeg")
			_, _ = w.Write(audio)
			return
		}
		w.Header().Set("Content-Type", "application/rss+xml")
		fmt.Fprint(w, `<?xml version="1.0"?><rss version="2.0"><channel><title>Landing Show</title>`)
		for n := 1; n <= 4; n++ {
			fmt.Fprintf(w, `<item><title>Episode %d</title><guid>landing-%d</guid><pubDate>%s</pubDate>`+
				`<enclosure url="http://%s/%d.mp3" type="audio/mpeg" length="1"/></item>`,
				n, n, time.Date(2026, 6, n, 8, 0, 0, 0, time.UTC).Format(time.RFC1123Z), r.Host, n)
		}
		fmt.Fprint(w, `</channel></rss>`)
	}))
	t.Cleanup(ts.Close)
	s := landingShow{ctx: ctx, svc: svc, admin: admin, feed: ts.URL + "/feed.xml", episodes: map[string]string{}}
	sub, _, err := svc.Subscribe(ctx, admin, SubscribeRequest{URL: s.feed})
	if err != nil {
		t.Fatal(err)
	}
	s.show = sub.Show.PID
	eps, _, err := svc.Episodes(ctx, admin, s.show, "", 10)
	if err != nil || len(eps) != 4 {
		t.Fatalf("episodes = %+v (%v), want four", eps, err)
	}
	for _, ep := range eps {
		s.episodes[ep.Title] = ep.PID
		if ep.Title == "Episode 4" {
			continue
		}
		file := filepath.Join(t.TempDir(), "episode.mp3")
		if err := os.WriteFile(file, audio, 0o644); err != nil {
			t.Fatal(err)
		}
		_, bare, _ := parseAPIPID(ep.PID)
		if _, err := svc.lib.Podcasts().ImportEpisodeFile(ctx, bare, file, false); err != nil {
			t.Fatal(err)
		}
	}
	return s
}

// downloaded names the show's episodes on the server, newest first.
func (s landingShow) downloaded(t *testing.T) []string {
	t.Helper()
	eps, _, err := s.svc.Episodes(s.ctx, s.admin, s.show, "", 10)
	if err != nil {
		t.Fatal(err)
	}
	var out []string
	for _, ep := range eps {
		if ep.Downloaded {
			out = append(out, ep.Title)
		}
	}
	return out
}

// A download that lands while a sweep is between reading what keeps its
// candidates and applying the cut cannot move the cut onto an episode
// whose guards were never read: the starred episode just inside the
// kept window stays, and the landing waits for the sweep.
func TestALandingCannotMoveARetentionSweepsCut(t *testing.T) {
	s := newLandingShow(t)
	if _, err := s.svc.SetStar(s.ctx, s.admin, s.episodes["Episode 2"], true, nil); err != nil {
		t.Fatal(err)
	}
	keep := int64(2)
	if _, err := s.svc.PutSubscriptionSettings(s.ctx, s.admin, s.show, SubscriptionSettings{RetentionKeep: &keep}); err != nil {
		t.Fatal(err)
	}
	if err := s.svc.QueueEpisodeFetch(s.ctx, s.admin, s.episodes["Episode 4"]); err != nil {
		t.Fatal(err)
	}
	landed := make(chan bool, 1)
	s.svc.retentionStatesHook = func(ctx context.Context, pids []model.PID) (map[model.PID][]model.PlayState, error) {
		s.svc.retentionStatesHook = nil
		go func() { landed <- s.svc.DrainFetchQueue(s.ctx) }()
		select {
		case <-landed:
			landed <- true
		case <-time.After(time.Second):
		}
		return s.svc.lib.PlayStatesForItems(ctx, pids)
	}
	s.svc.SweepRetention(s.ctx)
	<-landed
	if got := s.downloaded(t); !slices.Contains(got, "Episode 2") {
		t.Fatalf("downloads after a landing inside the sweep = %v, want the starred Episode 2 kept", got)
	}
	// The landing queues the show again, so the next sweep cuts it back to
	// what it keeps.
	if _, err := s.svc.SetStar(s.ctx, s.admin, s.episodes["Episode 2"], false, nil); err != nil {
		t.Fatal(err)
	}
	s.svc.SweepRetention(s.ctx)
	if got := s.downloaded(t); !slices.Equal(got, []string{"Episode 4", "Episode 3"}) {
		t.Errorf("downloads after the sweep the landing queued = %v, want the newest two", got)
	}
}

// keepTwo has the show keep its newest two downloads and sweeps it there.
func (s landingShow) keepTwo(t *testing.T) {
	t.Helper()
	keep := int64(2)
	if _, err := s.svc.PutSubscriptionSettings(s.ctx, s.admin, s.show, SubscriptionSettings{RetentionKeep: &keep}); err != nil {
		t.Fatal(err)
	}
	s.svc.SweepRetention(s.ctx)
	if got := s.downloaded(t); !slices.Equal(got, []string{"Episode 3", "Episode 2"}) {
		t.Fatalf("downloads after keeping two = %v, want the newest two", got)
	}
}

// sweep queues the show and sweeps it, whatever queued it before.
func (s landingShow) sweep(t *testing.T) {
	t.Helper()
	_, bare, _ := parseAPIPID(s.show)
	if err := s.svc.db.EnqueueRetention(s.ctx, string(bare), time.Now().UnixNano()); err != nil {
		t.Fatal(err)
	}
	s.svc.SweepRetention(s.ctx)
}

// A download a subscriber asked for is theirs to hear before retention
// takes it: an older episode fetched on request survives the sweeps after
// it lands, and goes with the sweep after its requester finishes it.
func TestARequestedDownloadWaitsForItsRequester(t *testing.T) {
	s := newLandingShow(t)
	s.keepTwo(t)
	if err := s.svc.QueueEpisodeFetch(s.ctx, s.admin, s.episodes["Episode 1"]); err != nil {
		t.Fatal(err)
	}
	if !s.svc.DrainFetchQueue(s.ctx) {
		t.Fatal("the fetch did not run")
	}
	s.svc.SweepRetention(s.ctx)
	s.sweep(t)
	if got := s.downloaded(t); !slices.Equal(got, []string{"Episode 3", "Episode 2", "Episode 1"}) {
		t.Fatalf("downloads after sweeps past the requested landing = %v, want Episode 1 kept for its requester", got)
	}
	if _, err := s.svc.SetPlayed(s.ctx, s.admin, s.episodes["Episode 1"], true, true, nil, nil, nil); err != nil {
		t.Fatal(err)
	}
	s.svc.SweepRetention(s.ctx)
	if got := s.downloaded(t); !slices.Equal(got, []string{"Episode 3", "Episode 2"}) {
		t.Errorf("downloads after its requester finished it = %v, want the newest two", got)
	}
}

// A requester who stops following the show, or cannot see the podcast
// library any more, holds nothing back.
func TestARequestedDownloadGoesWithItsRequestersFollow(t *testing.T) {
	s := newLandingShow(t)
	acct, err := s.svc.CreateAccount(s.ctx, AccountCreate{Username: "asker", Password: "correct-horse"})
	if err != nil {
		t.Fatal(err)
	}
	asker, err := s.svc.UserCtx(s.ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	if _, _, err := s.svc.Subscribe(s.ctx, asker, SubscribeRequest{URL: s.feed}); err != nil {
		t.Fatal(err)
	}
	keep := int64(2)
	if _, err := s.svc.PutSubscriptionSettings(s.ctx, asker, s.show, SubscriptionSettings{RetentionKeep: &keep}); err != nil {
		t.Fatal(err)
	}
	s.keepTwo(t)
	if err := s.svc.QueueEpisodeFetch(s.ctx, asker, s.episodes["Episode 1"]); err != nil {
		t.Fatal(err)
	}
	if !s.svc.DrainFetchQueue(s.ctx) {
		t.Fatal("the fetch did not run")
	}
	s.sweep(t)
	if got := s.downloaded(t); len(got) != 3 {
		t.Fatalf("downloads with the requester following = %v, want Episode 1 kept", got)
	}
	if err := s.svc.Unsubscribe(s.ctx, asker, s.show, false); err != nil {
		t.Fatal(err)
	}
	s.svc.SweepRetention(s.ctx)
	if got := s.downloaded(t); !slices.Equal(got, []string{"Episode 3", "Episode 2"}) {
		t.Errorf("downloads after the requester stopped following = %v, want the newest two", got)
	}
	_, bare, _ := parseAPIPID(s.show)
	if holds, err := s.svc.db.FetchHoldsByShow(s.ctx, string(bare)); err != nil || len(holds) != 0 {
		t.Errorf("holds after the requested file went = %+v (%v), want none", holds, err)
	}
}

// An automatic fetch's landing still queues the show, so a show under
// auto-download comes back to what it keeps rather than one past it.
func TestAnAutomaticLandingQueuesItsShow(t *testing.T) {
	s := newLandingShow(t)
	s.keepTwo(t)
	_, bare, _ := parseAPIPID(s.episodes["Episode 4"])
	if err := s.svc.db.EnqueueFetch(s.ctx, string(bare), "", time.Now().UnixNano(), fetchMaxAttempts); err != nil {
		t.Fatal(err)
	}
	if !s.svc.DrainFetchQueue(s.ctx) {
		t.Fatal("the fetch did not run")
	}
	s.svc.SweepRetention(s.ctx)
	if got := s.downloaded(t); !slices.Equal(got, []string{"Episode 4", "Episode 3"}) {
		t.Errorf("downloads after an automatic landing's sweep = %v, want the newest two", got)
	}
}

// A hold runs from the ask to a finish after it: an episode its requester
// had heard before asking (to hear again) is held, and goes once they
// have heard it through again.
func TestAHeardEpisodeAskedForAgainIsHeldUntilHeardAgain(t *testing.T) {
	s := newLandingShow(t)
	s.keepTwo(t)
	if _, err := s.svc.SetPlayed(s.ctx, s.admin, s.episodes["Episode 1"], true, true, nil, nil, nil); err != nil {
		t.Fatal(err)
	}
	if err := s.svc.QueueEpisodeFetch(s.ctx, s.admin, s.episodes["Episode 1"]); err != nil {
		t.Fatal(err)
	}
	if !s.svc.DrainFetchQueue(s.ctx) {
		t.Fatal("the fetch did not run")
	}
	s.sweep(t)
	if got := s.downloaded(t); !slices.Contains(got, "Episode 1") {
		t.Fatalf("downloads after a sweep past the requested landing = %v, want the episode asked for again kept", got)
	}
	eps, _, err := s.svc.Episodes(s.ctx, s.admin, s.show, "", 10)
	if err != nil {
		t.Fatal(err)
	}
	var end int64
	for _, ep := range eps {
		if ep.Title == "Episode 1" {
			end = ep.DurationMS
		}
	}
	if end <= 0 {
		t.Fatal("Episode 1 has no duration to reach the end of")
	}
	if _, err := s.svc.Checkpoint(s.ctx, s.admin, s.episodes["Episode 1"], end, nil); err != nil {
		t.Fatal(err)
	}
	s.sweep(t)
	if got := s.downloaded(t); slices.Contains(got, "Episode 1") {
		t.Errorf("downloads once its requester heard it through again = %v, want it gone", got)
	}
}

// An account deleted while the fetch ran holds nothing, and holds nothing
// back for the others who asked: the remaining requester's download is
// kept for them.
func TestADeletedRequesterLeavesTheOthersHeld(t *testing.T) {
	s := newLandingShow(t)
	s.keepTwo(t)
	var askers []*UserCtx
	for _, name := range []string{"first", "second"} {
		acct, err := s.svc.CreateAccount(s.ctx, AccountCreate{Username: name, Password: "correct-horse"})
		if err != nil {
			t.Fatal(err)
		}
		uc, err := s.svc.UserCtx(s.ctx, acct.User)
		if err != nil {
			t.Fatal(err)
		}
		if _, _, err := s.svc.Subscribe(s.ctx, uc, SubscribeRequest{URL: s.feed}); err != nil {
			t.Fatal(err)
		}
		keep := int64(2)
		if _, err := s.svc.PutSubscriptionSettings(s.ctx, uc, s.show, SubscriptionSettings{RetentionKeep: &keep}); err != nil {
			t.Fatal(err)
		}
		if err := s.svc.QueueEpisodeFetch(s.ctx, uc, s.episodes["Episode 1"]); err != nil {
			t.Fatal(err)
		}
		askers = append(askers, uc)
	}
	// Whichever sorts first is the one that goes, so a missing account
	// stops nothing after it either.
	gone, kept := askers[0], askers[1]
	if kept.ID < gone.ID {
		gone, kept = kept, gone
	}
	if _, err := s.svc.DeleteAccount(s.ctx, nil, gone.ID, AccountDeletion{}); err != nil {
		t.Fatal(err)
	}
	if !s.svc.DrainFetchQueue(s.ctx) {
		t.Fatal("the fetch did not run")
	}
	s.sweep(t)
	if got := s.downloaded(t); !slices.Contains(got, "Episode 1") {
		t.Errorf("downloads after a sweep = %v, want Episode 1 kept for the requester who remains", got)
	}
	_, bare, _ := parseAPIPID(s.show)
	holds, err := s.svc.db.FetchHoldsByShow(s.ctx, string(bare))
	if err != nil || len(holds) != 1 || holds[0].UserID != kept.ID {
		t.Errorf("holds = %+v (%v), want the remaining requester's alone", holds, err)
	}
}

// Asking for an episode already on the server holds it for the asker as
// a fetch would.
func TestAskingForAnEpisodeAlreadyHereHoldsIt(t *testing.T) {
	s := newLandingShow(t)
	s.keepTwo(t)
	if err := s.svc.QueueEpisodeFetch(s.ctx, s.admin, s.episodes["Episode 2"]); err != nil {
		t.Fatal(err)
	}
	_, bare, _ := parseAPIPID(s.episodes["Episode 4"])
	if err := s.svc.db.EnqueueFetch(s.ctx, string(bare), "", time.Now().UnixNano(), fetchMaxAttempts); err != nil {
		t.Fatal(err)
	}
	if !s.svc.DrainFetchQueue(s.ctx) {
		t.Fatal("the fetch did not run")
	}
	s.svc.SweepRetention(s.ctx)
	if got := s.downloaded(t); !slices.Equal(got, []string{"Episode 4", "Episode 3", "Episode 2"}) {
		t.Errorf("downloads after an automatic landing's sweep = %v, want Episode 2 kept for its asker", got)
	}
}

// A requester who cannot see the podcast library holds nothing back: the
// sweep takes the file, and the one after drops the hold on a file no
// longer on the server.
func TestADormantRequestersHoldKeepsNothing(t *testing.T) {
	s := newLandingShow(t)
	podcastLib, _ := s.svc.podcastLibrary(s.ctx)
	var music string
	for _, r := range s.svc.libraryRoots() {
		if r.Name == "configured" {
			music = apiPID(PrefixLibrary, model.PID(r.PID))
		}
	}
	acct, err := s.svc.CreateAccount(s.ctx, AccountCreate{
		Username: "asker", Password: "correct-horse", AccessMode: "granted",
		LibraryPIDs: []string{music, apiPID(PrefixLibrary, model.PID(podcastLib))},
	})
	if err != nil {
		t.Fatal(err)
	}
	asker, err := s.svc.UserCtx(s.ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	if _, _, err := s.svc.Subscribe(s.ctx, asker, SubscribeRequest{URL: s.feed}); err != nil {
		t.Fatal(err)
	}
	keep := int64(2)
	if _, err := s.svc.PutSubscriptionSettings(s.ctx, asker, s.show, SubscriptionSettings{RetentionKeep: &keep}); err != nil {
		t.Fatal(err)
	}
	s.keepTwo(t)
	if err := s.svc.QueueEpisodeFetch(s.ctx, asker, s.episodes["Episode 1"]); err != nil {
		t.Fatal(err)
	}
	if !s.svc.DrainFetchQueue(s.ctx) {
		t.Fatal("the fetch did not run")
	}
	mode := "granted"
	if _, err := s.svc.UpdateAccount(s.ctx, acct.User.ID, AccountUpdate{AccessMode: &mode, LibraryPIDs: []string{music}}); err != nil {
		t.Fatal(err)
	}
	s.sweep(t)
	if got := s.downloaded(t); !slices.Equal(got, []string{"Episode 3", "Episode 2"}) {
		t.Errorf("downloads after a sweep with the requester narrowed = %v, want the newest two", got)
	}
	s.sweep(t)
	_, bare, _ := parseAPIPID(s.show)
	if holds, err := s.svc.db.FetchHoldsByShow(s.ctx, string(bare)); err != nil || len(holds) != 0 {
		t.Errorf("holds once the file went = %+v (%v), want none", holds, err)
	}
}
