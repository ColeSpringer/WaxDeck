package service

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"

	"github.com/colespringer/waxdeck/fixtures"
)

// dormantFollower is a show of two episodes whose one follower, carol,
// can be narrowed to the music library, its first episode on the server
// and its feed host counting the times it is asked for the feed.
type dormantFollower struct {
	ctx      context.Context
	svc      *Library
	carolID  string
	feed     string
	show     string
	episodes map[string]string // api pid by title
	asked    *atomic.Int64
	music    string // api pid
}

func newDormantFollower(t *testing.T) dormantFollower {
	t.Helper()
	dir := t.TempDir()
	ctx, svc, admin, _ := openServiceAt(t, dir, func(cfg *Config) {
		cfg.PodcastDir = filepath.Join(dir, "podcasts")
		cfg.PodcastRootName = "podcasts"
		cfg.AllowPrivateFeedHosts = true
	})
	paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
		Name: "dormant", Codec: fixtures.CodecMP3, Container: fixtures.ContainerMP3, Duration: time.Second,
	})
	if err != nil {
		t.Fatal(err)
	}
	audio, err := os.ReadFile(paths[0])
	if err != nil {
		t.Fatal(err)
	}
	asked := &atomic.Int64{}
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, ".mp3") {
			w.Header().Set("Content-Type", "audio/mpeg")
			_, _ = w.Write(audio)
			return
		}
		asked.Add(1)
		w.Header().Set("Content-Type", "application/rss+xml")
		fmt.Fprint(w, `<?xml version="1.0"?><rss version="2.0"><channel><title>Dormant Show</title>`)
		for n := 1; n <= 2; n++ {
			fmt.Fprintf(w, `<item><title>Episode %d</title><guid>dormant-%d</guid><pubDate>%s</pubDate>`+
				`<enclosure url="http://%s/%d.mp3" type="audio/mpeg" length="1"/></item>`,
				n, n, time.Date(2026, 6, n, 8, 0, 0, 0, time.UTC).Format(time.RFC1123Z), r.Host, n)
		}
		fmt.Fprint(w, `</channel></rss>`)
	}))
	t.Cleanup(ts.Close)
	d := dormantFollower{ctx: ctx, svc: svc, feed: ts.URL + "/feed.xml", episodes: map[string]string{}, asked: asked}
	sub, _, err := svc.Subscribe(ctx, admin, SubscribeRequest{URL: d.feed})
	if err != nil {
		t.Fatal(err)
	}
	d.show = sub.Show.PID
	eps, _, err := svc.Episodes(ctx, admin, d.show, "", 10)
	if err != nil || len(eps) != 2 {
		t.Fatalf("episodes = %+v (%v), want two", eps, err)
	}
	for _, ep := range eps {
		d.episodes[ep.Title] = ep.PID
	}
	_, first, _ := parseAPIPID(d.episodes["Episode 1"])
	if _, err := svc.lib.Podcasts().ImportEpisodeFile(ctx, first, paths[0], false); err != nil {
		t.Fatal(err)
	}
	podcastLib, _ := svc.podcastLibrary(ctx)
	grants := []string{apiPID(PrefixLibrary, model.PID(podcastLib))}
	for _, r := range svc.libraryRoots() {
		if r.Name == "configured" {
			d.music = apiPID(PrefixLibrary, model.PID(r.PID))
			grants = append(grants, d.music)
		}
	}
	acct, err := svc.CreateAccount(ctx, AccountCreate{
		Username: "carol", Password: "correct-horse", AccessMode: "granted", LibraryPIDs: grants,
	})
	if err != nil {
		t.Fatal(err)
	}
	d.carolID = acct.User.ID
	if _, _, err := svc.Subscribe(ctx, d.carol(t), SubscribeRequest{URL: d.feed}); err != nil {
		t.Fatal(err)
	}
	if err := svc.Unsubscribe(ctx, admin, d.show, false); err != nil {
		t.Fatal(err)
	}
	asked.Store(0)
	return d
}

// carol reads the follower's account as it stands.
func (d dormantFollower) carol(t *testing.T) *UserCtx {
	t.Helper()
	uc, err := d.svc.userCtxByID(d.ctx, d.carolID)
	if err != nil {
		t.Fatal(err)
	}
	return uc
}

// narrow leaves carol the music library alone.
func (d dormantFollower) narrow(t *testing.T) {
	t.Helper()
	mode := "granted"
	if _, err := d.svc.UpdateAccount(d.ctx, d.carolID, AccountUpdate{AccessMode: &mode, LibraryPIDs: []string{d.music}}); err != nil {
		t.Fatal(err)
	}
}

// A download a follower queued still lands once the follower can no
// longer see podcasts, but tells them nothing: no inbox row, and no
// marker on their stream.
func TestAFetchLandingForADormantFollowerTellsThemNothing(t *testing.T) {
	d := newDormantFollower(t)
	if err := d.svc.QueueEpisodeFetch(d.ctx, d.carol(t), d.episodes["Episode 2"]); err != nil {
		t.Fatal(err)
	}
	d.narrow(t)
	since, err := d.svc.MintServerCursor(d.ctx)
	if err != nil {
		t.Fatal(err)
	}
	if !d.svc.DrainFetchQueue(d.ctx) {
		t.Fatal("the queued fetch did not run")
	}
	_, bare, _ := parseAPIPID(d.episodes["Episode 2"])
	det, err := d.svc.lib.Podcasts().Episode(d.ctx, bare)
	if err != nil || !det.Episode.Downloaded {
		t.Fatalf("episode 2 after the drain = %+v (%v), want it downloaded", det, err)
	}
	page, err := d.svc.Notifications(d.ctx, d.carol(t), "", 50)
	if err != nil {
		t.Fatal(err)
	}
	for _, n := range page.Notifications {
		if n.Event == "episode-downloaded" {
			t.Errorf("the dormant follower's inbox holds %+v", n)
		}
	}
	delta, err := d.svc.SyncServerDelta(d.ctx, d.carol(t), since, 100)
	if err != nil {
		t.Fatal(err)
	}
	for _, ev := range delta.Events {
		if ev.Kind == eventEpisodeDownloaded {
			t.Errorf("the dormant follower's stream carries %+v", ev)
		}
	}
}

// A show whose every follower is dormant is fetched for nobody, so the
// scheduler leaves it alone, and so does a chain notification naming it.
func TestAShowFollowedOnlyByTheDormantIsNotPolled(t *testing.T) {
	d := newDormantFollower(t)
	d.narrow(t)
	d.svc.NotePodping(d.ctx, d.feed)
	if n := d.asked.Load(); n != 0 {
		t.Errorf("a ping had the feed's host asked %d times for a show nobody can hear", n)
	}
	d.asked.Store(0)
	d.svc.RefreshDueFeeds(d.ctx, 0)
	if n := d.asked.Load(); n != 0 {
		t.Errorf("the scheduler asked the feed's host %d times for a show nobody can hear", n)
	}
}

// A follower who cannot be judged may be listening, so the show is still
// polled for them.
func TestAShowWithAnUnjudgedFollowerIsPolled(t *testing.T) {
	d := newDormantFollower(t)
	d.svc.listenerReadHook = func(context.Context, string) (*UserCtx, error) {
		return nil, &Error{Kind: KindInternal, Err: errors.New("database is locked")}
	}
	d.svc.RefreshDueFeeds(d.ctx, 0)
	if n := d.asked.Load(); n != 1 {
		t.Errorf("the scheduler asked the feed's host %d times with a follower unjudged, want once", n)
	}
}
