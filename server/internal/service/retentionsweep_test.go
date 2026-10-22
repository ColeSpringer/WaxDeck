package service

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"slices"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"

	"github.com/colespringer/waxdeck/fixtures"
)

// retentionShow is a show the administrator and a listener granted the
// music and podcast libraries both follow, its three episodes on the
// server.
type retentionShow struct {
	ctx      context.Context
	svc      *Library
	admin    *UserCtx
	listener *UserCtx
	feed     string
	show     string            // the api pid
	episodes map[string]string // api pid by title
}

func newRetentionShow(t *testing.T) retentionShow {
	t.Helper()
	dir := t.TempDir()
	ctx, svc, admin, _ := openServiceAt(t, dir, func(cfg *Config) {
		cfg.PodcastDir = filepath.Join(dir, "podcasts")
		cfg.PodcastRootName = "podcasts"
		cfg.AllowPrivateFeedHosts = true
	})
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/rss+xml")
		fmt.Fprint(w, `<?xml version="1.0"?><rss version="2.0"><channel><title>Kept Show</title>`)
		for n := 1; n <= 3; n++ {
			fmt.Fprintf(w, `<item><title>Episode %d</title><guid>kept-%d</guid><pubDate>%s</pubDate>`+
				`<enclosure url="http://%s/%d.mp3" type="audio/mpeg" length="1"/></item>`,
				n, n, time.Date(2026, 6, n, 8, 0, 0, 0, time.UTC).Format(time.RFC1123Z), r.Host, n)
		}
		fmt.Fprint(w, `</channel></rss>`)
	}))
	t.Cleanup(ts.Close)
	s := retentionShow{ctx: ctx, svc: svc, admin: admin, feed: ts.URL + "/feed.xml", episodes: map[string]string{}}
	sub, _, err := svc.Subscribe(ctx, admin, SubscribeRequest{URL: s.feed})
	if err != nil {
		t.Fatal(err)
	}
	s.show = sub.Show.PID
	eps, _, err := svc.Episodes(ctx, admin, s.show, "", 10)
	if err != nil || len(eps) != 3 {
		t.Fatalf("episodes = %+v (%v), want three", eps, err)
	}
	for i, ep := range eps {
		s.episodes[ep.Title] = ep.PID
		paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
			Name: fmt.Sprintf("kept-%d", i), Codec: fixtures.CodecMP3, Container: fixtures.ContainerMP3,
			Duration: time.Duration(i+1) * time.Second,
		})
		if err != nil {
			t.Fatal(err)
		}
		_, bare, _ := parseAPIPID(ep.PID)
		if _, err := svc.lib.Podcasts().ImportEpisodeFile(ctx, bare, paths[0], false); err != nil {
			t.Fatal(err)
		}
	}
	podcastLib, _ := svc.podcastLibrary(ctx)
	grants := []string{apiPID(PrefixLibrary, model.PID(podcastLib))}
	for _, r := range svc.libraryRoots() {
		if r.Name == "configured" {
			grants = append(grants, apiPID(PrefixLibrary, model.PID(r.PID)))
		}
	}
	acct, err := svc.CreateAccount(ctx, AccountCreate{
		Username: "listener", Password: "correct-horse", AccessMode: "granted", LibraryPIDs: grants,
	})
	if err != nil {
		t.Fatal(err)
	}
	if s.listener, err = svc.UserCtx(ctx, acct.User); err != nil {
		t.Fatal(err)
	}
	if _, _, err := svc.Subscribe(ctx, s.listener, SubscribeRequest{URL: s.feed}); err != nil {
		t.Fatal(err)
	}
	return s
}

// keep sets how many downloads uc keeps, which queues the show's sweep.
func (s retentionShow) keep(t *testing.T, uc *UserCtx, n int64) {
	t.Helper()
	if _, err := s.svc.PutSubscriptionSettings(s.ctx, uc, s.show, SubscriptionSettings{RetentionKeep: &n}); err != nil {
		t.Fatal(err)
	}
}

// downloaded names the show's episodes on the server, newest first.
func (s retentionShow) downloaded(t *testing.T) []string {
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

// catalogKeep is the keep-newest-N the catalog holds for the show.
func (s retentionShow) catalogKeep(t *testing.T) int {
	t.Helper()
	_, bare, _ := parseAPIPID(s.show)
	pod, err := s.svc.lib.Podcasts().Get(s.ctx, bare)
	if err != nil {
		t.Fatal(err)
	}
	return pod.RetentionKeep
}

// waiting reports whether the show waits in the retention queue, leaving
// the queue as it found it.
func (s retentionShow) waiting(t *testing.T) bool {
	t.Helper()
	shows, err := s.svc.db.TakeRetentionQueue(s.ctx)
	if err != nil {
		t.Fatal(err)
	}
	for _, show := range shows {
		if err := s.svc.db.EnqueueRetention(s.ctx, show, time.Now().UnixNano()); err != nil {
			t.Fatal(err)
		}
	}
	_, bare, _ := parseAPIPID(s.show)
	return slices.Contains(shows, string(bare))
}

// A sweep that cannot read one follower's account cannot know that
// follower's vote, which may be the one keeping what the rest let go: it
// stores no retention, removes nothing and waits the show for the next
// sweep, which applies the union once the account reads.
func TestARetentionSweepWaitsForEveryFollowersVote(t *testing.T) {
	s := newRetentionShow(t)
	s.keep(t, s.admin, 1)
	s.keep(t, s.listener, 0)
	s.svc.listenerReadHook = func(ctx context.Context, userID string) (*UserCtx, error) {
		if userID == s.listener.ID {
			return nil, &Error{Kind: KindInternal, Err: errors.New("database is locked")}
		}
		return s.svc.userCtxByID(ctx, userID)
	}
	had := s.catalogKeep(t)
	s.svc.SweepRetention(s.ctx)
	if got := s.downloaded(t); len(got) != 3 {
		t.Errorf("downloads after a sweep missing a vote = %v, want all three", got)
	}
	if got := s.catalogKeep(t); got != had {
		t.Errorf("the catalog keeps %d after a sweep missing a vote, want the %d it had", got, had)
	}
	if !s.waiting(t) {
		t.Fatal("the show does not wait for the next sweep")
	}

	s.svc.listenerReadHook = nil
	s.svc.SweepRetention(s.ctx)
	if got := s.downloaded(t); len(got) != 3 {
		t.Errorf("downloads once every vote reads = %v, want all three by the listener's keep-all", got)
	}
	if s.waiting(t) {
		t.Error("the show still waits after a sweep that read every vote")
	}
}

// A granted follower whose account reads is still not judged while the
// podcast library cannot be: not finding the library is not finding that
// the account cannot see it.
func TestAGrantedFollowerIsUnjudgedWhileThePodcastLibraryCannotBeRead(t *testing.T) {
	s := newRetentionShow(t)
	_, bare, _ := parseAPIPID(s.show)
	subs, err := s.svc.db.SubscribersByShow(s.ctx, string(bare))
	if err != nil || len(subs) != 2 {
		t.Fatalf("subscribers = %+v (%v), want two", subs, err)
	}
	// The accounts read; the catalog's list of libraries, read afresh
	// under a canceled context, does not.
	s.svc.listenerReadHook = func(_ context.Context, userID string) (*UserCtx, error) {
		return s.svc.userCtxByID(s.ctx, userID)
	}
	s.svc.invalidateAttribution()
	failing, cancel := context.WithCancel(s.ctx)
	cancel()
	listening, judged := s.svc.podcastListeners(failing, subs)
	if judged {
		t.Error("every follower judged while the podcast library could not be read")
	}
	if len(listening) != 1 || listening[0].UserID != s.admin.ID {
		t.Errorf("listening = %+v, want the administrator alone", listening)
	}

	listening, judged = s.svc.podcastListeners(s.ctx, subs)
	if !judged || len(listening) != 2 {
		t.Errorf("once the library reads: listening = %+v, judged = %v, want both judged", listening, judged)
	}
}

// A sweep that cannot read what keeps its candidates moves no pin and
// removes nothing, and waits the show for the next sweep: a follower's
// starred episode stays when the stars cannot be read.
func TestARetentionSweepWaitsForEveryGuard(t *testing.T) {
	s := newRetentionShow(t)
	s.keep(t, s.admin, 1)
	s.keep(t, s.listener, 1)
	if _, err := s.svc.SetStar(s.ctx, s.listener, s.episodes["Episode 1"], true, nil); err != nil {
		t.Fatal(err)
	}
	s.svc.SweepRetention(s.ctx)
	kept := []string{"Episode 3", "Episode 1"}
	if got := s.downloaded(t); !slices.Equal(got, kept) {
		t.Fatalf("downloads = %v, want the newest and the starred one", got)
	}

	s.svc.retentionStatesHook = func(context.Context, []model.PID) (map[model.PID][]model.PlayState, error) {
		return nil, errors.New("database is locked")
	}
	s.keep(t, s.admin, 1)
	s.svc.SweepRetention(s.ctx)
	if got := s.downloaded(t); !slices.Equal(got, kept) {
		t.Errorf("downloads after a sweep that could not read the stars = %v, want %v", got, kept)
	}
	if !s.waiting(t) {
		t.Fatal("the show does not wait for the next sweep")
	}

	s.svc.retentionStatesHook = nil
	s.svc.SweepRetention(s.ctx)
	if got := s.downloaded(t); !slices.Equal(got, kept) {
		t.Errorf("downloads once the stars read = %v, want %v", got, kept)
	}
	if s.waiting(t) {
		t.Error("the show still waits after a sweep that read every guard")
	}
}

// A pin that could not be set protects nothing, so the sweep that wanted
// it removes nothing and waits the show for the next one.
func TestARetentionSweepWaitsForItsPins(t *testing.T) {
	s := newRetentionShow(t)
	s.keep(t, s.admin, 1)
	s.keep(t, s.listener, 1)
	if _, err := s.svc.SetStar(s.ctx, s.listener, s.episodes["Episode 1"], true, nil); err != nil {
		t.Fatal(err)
	}
	s.svc.pinHook = func(context.Context, model.PID, *model.Episode, bool) error {
		return errors.New("database is locked")
	}
	s.svc.SweepRetention(s.ctx)
	if got := s.downloaded(t); len(got) != 3 {
		t.Errorf("downloads after a sweep whose pin failed = %v, want all three", got)
	}
	if !s.waiting(t) {
		t.Fatal("the show does not wait for the next sweep")
	}

	s.svc.pinHook = nil
	s.svc.SweepRetention(s.ctx)
	if got := s.downloaded(t); !slices.Equal(got, []string{"Episode 3", "Episode 1"}) {
		t.Errorf("downloads once the pin lands = %v, want the newest and the starred one", got)
	}
}

// An unpin that could not be written leaves the episode pinned, so kept:
// the sweep reclaims the rest instead of waiting the show on it.
func TestAFailedUnpinHoldsNothingBack(t *testing.T) {
	s := newRetentionShow(t)
	s.keep(t, s.admin, 2)
	s.keep(t, s.listener, 2)
	if _, err := s.svc.SetStar(s.ctx, s.listener, s.episodes["Episode 1"], true, nil); err != nil {
		t.Fatal(err)
	}
	s.svc.SweepRetention(s.ctx)
	if got := s.downloaded(t); len(got) != 3 {
		t.Fatalf("downloads = %v, want all three, the oldest pinned by its star", got)
	}

	if _, err := s.svc.SetStar(s.ctx, s.listener, s.episodes["Episode 1"], false, nil); err != nil {
		t.Fatal(err)
	}
	s.svc.pinHook = func(_ context.Context, _ model.PID, _ *model.Episode, pinned bool) error {
		if pinned {
			t.Error("the sweep pinned an episode nobody keeps")
		}
		return errors.New("database is locked")
	}
	s.keep(t, s.admin, 1)
	s.keep(t, s.listener, 1)
	s.svc.SweepRetention(s.ctx)
	s.svc.pinHook = nil
	if got := s.downloaded(t); !slices.Equal(got, []string{"Episode 3", "Episode 1"}) {
		t.Errorf("downloads after a sweep whose unpin failed = %v, want the newest and the still-pinned one", got)
	}
	if s.waiting(t) {
		t.Error("a failed unpin waited the show for the next sweep")
	}
}

// Anyone listening holds the sweep, a reader who follows nothing too: the
// file is shared, and removing it cuts whoever is playing it.
func TestARetentionSweepWaitsForAListenerWhoFollowsNothing(t *testing.T) {
	s := newRetentionShow(t)
	s.keep(t, s.admin, 1)
	s.keep(t, s.listener, 1)
	acct, err := s.svc.CreateAccount(s.ctx, AccountCreate{Username: "visitor", Password: "correct-horse"})
	if err != nil {
		t.Fatal(err)
	}
	visitor, err := s.svc.UserCtx(s.ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.svc.Checkpoint(s.ctx, visitor, s.episodes["Episode 1"], 500, nil); err != nil {
		t.Fatal(err)
	}
	s.svc.SweepRetention(s.ctx)
	if got := s.downloaded(t); len(got) != 3 {
		t.Errorf("downloads while a reader plays one = %v, want all three", got)
	}
	if !s.waiting(t) {
		t.Error("the show does not wait for the next sweep")
	}
}

// A remote session's position reaches the catalog as buffered ticks, not
// as a write to the stored state, and a renderer playing an episode holds
// the sweep as a local player does: the tick is the listener.
func TestARetentionSweepWaitsForARemoteSessionsTicks(t *testing.T) {
	s := newRetentionShow(t)
	s.keep(t, s.admin, 1)
	s.keep(t, s.listener, 1)
	acct, err := s.svc.CreateAccount(s.ctx, AccountCreate{Username: "caster", Password: "correct-horse"})
	if err != nil {
		t.Fatal(err)
	}
	s.svc.PlayerProgress(acct.User.ID, s.episodes["Episode 1"], 500)
	s.svc.SweepRetention(s.ctx)
	if got := s.downloaded(t); len(got) != 3 {
		t.Errorf("downloads while a renderer plays one = %v, want all three", got)
	}
	if !s.waiting(t) {
		t.Error("the show does not wait for the next sweep")
	}
}

// Removing a download by hand refuses while a renderer plays it, as it
// does while a local player does.
func TestRemovingADownloadWaitsForARemoteSession(t *testing.T) {
	s := newRetentionShow(t)
	acct, err := s.svc.CreateAccount(s.ctx, AccountCreate{Username: "caster", Password: "correct-horse"})
	if err != nil {
		t.Fatal(err)
	}
	s.svc.PlayerProgress(acct.User.ID, s.episodes["Episode 2"], 500)
	if err := s.svc.RemoveEpisodeDownload(s.ctx, s.admin, s.episodes["Episode 2"]); KindOf(err) != KindConflict {
		t.Errorf("removing a download a renderer plays = %v, want a conflict", err)
	}
	if got := s.downloaded(t); len(got) != 3 {
		t.Errorf("downloads after the refused removal = %v, want all three", got)
	}
}
