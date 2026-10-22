package service

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"slices"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"
)

// guidShowHost serves one show under a podcast:guid at any path and query,
// the way a premium feed answers each listener's own address. A path set
// to fail answers that status instead.
type guidShowHost struct {
	URL  string
	mu   sync.Mutex
	fail map[string]int
	hits map[string]int
}

func newGuidShowHost(t *testing.T) *guidShowHost {
	t.Helper()
	h := &guidShowHost{fail: map[string]int{}, hits: map[string]int{}}
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h.mu.Lock()
		h.hits[r.URL.Path]++
		status := h.fail[r.URL.Path]
		h.mu.Unlock()
		if status != 0 {
			http.Error(w, "not now", status)
			return
		}
		w.Header().Set("Content-Type", "application/rss+xml")
		fmt.Fprintf(w, `<?xml version="1.0"?><rss version="2.0" xmlns:podcast="https://podcastindex.org/namespace/1.0"><channel><title>Guid Show</title>
<podcast:guid>917393e3-1b1e-5cef-ace4-edaa54e1f810</podcast:guid>
<item><title>One</title><guid>guid-1</guid><enclosure url="http://%s/one.mp3" type="audio/mpeg" length="1"/></item>
</channel></rss>`, r.Host)
	}))
	t.Cleanup(ts.Close)
	h.URL = ts.URL
	return h
}

// failWith makes path answer status, 0 for the feed again.
func (h *guidShowHost) failWith(path string, status int) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.fail[path] = status
}

func (h *guidShowHost) hitsOf(path string) int {
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.hits[path]
}

// theOnlyShow answers the one show the account follows.
func theOnlyShow(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx) string {
	t.Helper()
	subs, err := svc.db.SubscriptionsByUser(ctx, uc.ID)
	if err != nil || len(subs) != 1 {
		t.Fatalf("subscriptions = %+v (%v), want one", subs, err)
	}
	return subs[0].ShowPID
}

// catalogURL answers the feed URL the catalog holds the show under.
func catalogURL(t *testing.T, ctx context.Context, svc *Library, show string) string {
	t.Helper()
	pod, err := svc.lib.Podcasts().Get(ctx, model.PID(show))
	if err != nil {
		t.Fatal(err)
	}
	return pod.FeedURL
}

// changeLog renders the account's change log as one device that never
// named a show is told it.
func changeLog(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx) []string {
	t.Helper()
	evs, _, err := svc.GpodderSubChangesSince(ctx, uc, "", 0)
	if err != nil {
		t.Fatal(err)
	}
	var out []string
	for _, ev := range evs {
		out = append(out, ev.Action+" "+ev.FeedURL)
	}
	return out
}

// A show is one entry in the change log however the catalog spells its
// feed meanwhile: a device reading from the start is told the account
// left it, under the account's own URL, and a year on nothing is left to
// tell, not the add.
func TestAShowIsOneChangeWhateverTheCatalogCallsIt(t *testing.T) {
	for _, how := range []string{"in the apps", "from the phone"} {
		t.Run(how, func(t *testing.T) {
			ctx, svc, uc, feed := openPodcastFixture(t)
			respelled := feed + "/"
			if out, err := svc.GpodderApplyChanges(ctx, uc, "phone", []string{feed}, nil); err != nil || out[feed] != GpodderLanded {
				t.Fatalf("the phone's add = %v (%v)", out, err)
			}
			show := theOnlyShow(t, ctx, svc, uc)
			if _, _, err := svc.Subscribe(ctx, secondListener(t, ctx, svc), SubscribeRequest{URL: respelled}); err != nil {
				t.Fatal(err)
			}
			if got := catalogURL(t, ctx, svc, show); got != respelled {
				t.Fatalf("the catalog holds the show as %q, want the other subscriber's %q", got, respelled)
			}
			switch how {
			case "in the apps":
				if err := svc.Unsubscribe(ctx, uc, apiPID(PrefixPodcast, model.PID(show)), false); err != nil {
					t.Fatal(err)
				}
			default:
				if _, err := svc.GpodderApplyChanges(ctx, uc, "phone", nil, []string{feed}); err != nil {
					t.Fatal(err)
				}
			}
			if got := changeLog(t, ctx, svc, uc); !slices.Equal(got, []string{"remove " + feed}) {
				t.Errorf("the change log = %v, want the one removal under the account's %q", got, feed)
			}
			if _, err := svc.db.PruneGpodderSubEvents(ctx, time.Now().Add(time.Hour).Unix()); err != nil {
				t.Fatal(err)
			}
			if got := changeLog(t, ctx, svc, uc); len(got) != 0 {
				t.Errorf("the change log after the year's prune = %v, want nothing: the account left the show", got)
			}
		})
	}
}

// respellers re-point the catalog's URL for a show to b, by another
// account's subscribe or by the account's own in the apps, which makes b
// the account's URL too.
var respellers = map[string]func(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, b string){
	"another account": func(t *testing.T, ctx context.Context, svc *Library, _ *UserCtx, b string) {
		t.Helper()
		if _, _, err := svc.Subscribe(ctx, secondListener(t, ctx, svc), SubscribeRequest{URL: b}); err != nil {
			t.Fatal(err)
		}
	},
	"the apps": func(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, b string) {
		t.Helper()
		if _, _, err := svc.Subscribe(ctx, uc, SubscribeRequest{URL: b}); err != nil {
			t.Fatal(err)
		}
	},
}

// A list that names a show by the device's own URL names that show,
// without a fetch, after the catalog and even the account took up another
// URL: the host failing or gone costs the device nothing.
func TestAListNamesAShowByTheDevicesOwnURL(t *testing.T) {
	for who, respell := range respellers {
		t.Run(who, func(t *testing.T) {
			ctx, svc, uc, _ := openPodcastFixture(t)
			if err := svc.GpodderUpsertDevice(ctx, uc, "desk", "", ""); err != nil {
				t.Fatal(err)
			}
			host := newGuidShowHost(t)
			a, b := host.URL+"/a.xml", host.URL+"/b.xml"
			if res, err := svc.GpodderReplaceDeviceList(ctx, uc, "desk", []string{a}); err != nil || res.Outcomes[a] != GpodderLanded {
				t.Fatalf("the desk's list = %+v (%v)", res, err)
			}
			show := theOnlyShow(t, ctx, svc, uc)
			if _, err := svc.PutSubscriptionSettings(ctx, uc, apiPID(PrefixPodcast, model.PID(show)), SubscriptionSettings{Folder: "Keep"}); err != nil {
				t.Fatal(err)
			}
			respell(t, ctx, svc, uc, b)
			if got := catalogURL(t, ctx, svc, show); got != b {
				t.Fatalf("the catalog holds the show as %q, want %q", got, b)
			}
			for _, status := range []int{http.StatusServiceUnavailable, http.StatusNotFound} {
				host.failWith("/a.xml", status)
				hits := host.hitsOf("/a.xml")
				res, err := svc.GpodderReplaceDeviceList(ctx, uc, "desk", []string{a})
				if err != nil || res.Outcomes[a] != GpodderLanded || res.Released != 0 {
					t.Errorf("with a's host answering %d the desk's list = %+v (%v), want a landed and nothing released", status, res, err)
				}
				if got := host.hitsOf("/a.xml"); got != hits {
					t.Errorf("with a's host answering %d the list fetched a %d times, want no fetch", status, got-hits)
				}
				if held, err := svc.db.GpodderHeldBy(ctx, uc.ID, "desk"); err != nil || !slices.Equal(held, []string{show}) {
					t.Errorf("with a's host answering %d the desk holds %v (%v), want the show", status, held, err)
				}
				if sub, err := svc.db.SubscriptionFor(ctx, uc.ID, show); err != nil || sub.Folder != "Keep" {
					t.Errorf("with a's host answering %d the subscription = %+v (%v), want it kept with its folder", status, sub, err)
				}
			}
		})
	}
}

// While a feed a list names is parked the list cannot say which shows it
// means, so it lets go of nothing; the next list after the park lands
// decides.
func TestAListWithAParkedFeedLetsGoOfNothing(t *testing.T) {
	ctx, svc, uc, feed := openPodcastFixture(t)
	if res, err := svc.GpodderReplaceDeviceList(ctx, uc, "desk", []string{feed}); err != nil || res.Outcomes[feed] != GpodderLanded {
		t.Fatalf("the desk's first list = %+v (%v)", res, err)
	}
	kept := theOnlyShow(t, ctx, svc, uc)
	flaky, _ := downThenUp(t, 1)
	res, err := svc.GpodderReplaceDeviceList(ctx, uc, "desk", []string{flaky})
	if err != nil || res.Outcomes[flaky] != GpodderParked || res.Released != 0 {
		t.Fatalf("the desk's list naming a feed that is down = %+v (%v), want it parked and nothing released", res, err)
	}
	if _, err := svc.db.SubscriptionFor(ctx, uc.ID, kept); err != nil {
		t.Fatalf("the show the list stopped naming went while a feed it names was parked: %v", err)
	}
	svc.RetryPendingGpodderAt(ctx, time.Now().Add(6*time.Minute))
	res, err = svc.GpodderReplaceDeviceList(ctx, uc, "desk", []string{flaky})
	if err != nil || res.Outcomes[flaky] != GpodderLanded || res.Released != 1 {
		t.Fatalf("the desk's list once the park landed = %+v (%v), want the old show let go", res, err)
	}
	if _, err := svc.db.SubscriptionFor(ctx, uc.ID, kept); err == nil {
		t.Error("the account still follows the show the desk's list stopped naming")
	}
}

// A remove names a show by the device's own URL too, whatever the
// catalog and the account call it now.
func TestARemoveNamesAShowByTheDevicesOwnURL(t *testing.T) {
	for who, respell := range respellers {
		t.Run(who, func(t *testing.T) {
			ctx, svc, uc, _ := openPodcastFixture(t)
			if err := svc.GpodderUpsertDevice(ctx, uc, "phone", "", ""); err != nil {
				t.Fatal(err)
			}
			host := newGuidShowHost(t)
			a, b := host.URL+"/a.xml", host.URL+"/b.xml"
			if out, err := svc.GpodderApplyChanges(ctx, uc, "phone", []string{a}, nil); err != nil || out[a] != GpodderLanded {
				t.Fatalf("the phone's add = %v (%v)", out, err)
			}
			show := theOnlyShow(t, ctx, svc, uc)
			respell(t, ctx, svc, uc, b)
			if got := catalogURL(t, ctx, svc, show); got != b {
				t.Fatalf("the catalog holds the show as %q, want %q", got, b)
			}
			if _, err := svc.GpodderApplyChanges(ctx, uc, "phone", nil, []string{a}); err != nil {
				t.Fatal(err)
			}
			if subs, err := svc.db.SubscriptionsByUser(ctx, uc.ID); err != nil || len(subs) != 0 {
				t.Errorf("subscriptions after the phone removed its own URL = %+v (%v), want none", subs, err)
			}
		})
	}
}

// Leaving a show withdraws the parked asks of every URL the account and
// its devices call it by.
func TestAnUnsubscribeWithdrawsAParkOfAKnownURL(t *testing.T) {
	for _, whose := range []string{"the account's", "a device's"} {
		t.Run(whose, func(t *testing.T) {
			ctx, svc, uc, _ := openPodcastFixture(t)
			if err := svc.GpodderUpsertDevice(ctx, uc, "tablet", "", ""); err != nil {
				t.Fatal(err)
			}
			host := newGuidShowHost(t)
			a, b, d := host.URL+"/a.xml", host.URL+"/b.xml", host.URL+"/d.xml"
			known := a
			if whose == "a device's" {
				known = d
			}
			host.failWith("/a.xml/", http.StatusServiceUnavailable)
			host.failWith("/d.xml/", http.StatusServiceUnavailable)
			if out, err := svc.GpodderApplyChanges(ctx, uc, "phone", []string{known + "/"}, nil); err != nil || out[known+"/"] != GpodderParked {
				t.Fatalf("the phone's add = %v (%v), want it parked", out, err)
			}
			if out, err := svc.GpodderApplyChanges(ctx, uc, "tablet", []string{d}, nil); err != nil || out[d] != GpodderLanded {
				t.Fatalf("the tablet's add = %v (%v)", out, err)
			}
			sub, _, err := svc.Subscribe(ctx, uc, SubscribeRequest{URL: a})
			if err != nil {
				t.Fatal(err)
			}
			if _, _, err := svc.Subscribe(ctx, secondListener(t, ctx, svc), SubscribeRequest{URL: b}); err != nil {
				t.Fatal(err)
			}
			if err := svc.Unsubscribe(ctx, uc, sub.Show.PID, false); err != nil {
				t.Fatal(err)
			}
			if parks, err := svc.db.GpodderParks(ctx, uc.ID); err != nil || len(parks) != 0 {
				t.Errorf("parks after the unsubscribe = %+v (%v), want the ask under %s spelling withdrawn", parks, err, whose)
			}
		})
	}
}

// A park whose URL names the show only once fetched lands on nothing when
// the account left that show after the ask: the retry is not a subscribe.
func TestAParkOfAnotherURLDoesNotUndoAnUnsubscribe(t *testing.T) {
	ctx, svc, uc, _ := openPodcastFixture(t)
	host := newGuidShowHost(t)
	a, c := host.URL+"/a.xml", host.URL+"/c.xml"
	host.failWith("/c.xml", http.StatusServiceUnavailable)
	sub, _, err := svc.Subscribe(ctx, uc, SubscribeRequest{URL: a})
	if err != nil {
		t.Fatal(err)
	}
	if out, err := svc.GpodderApplyChanges(ctx, uc, "phone", []string{c}, nil); err != nil || out[c] != GpodderParked {
		t.Fatalf("the phone's add of another URL = %v (%v), want it parked", out, err)
	}
	if err := svc.Unsubscribe(ctx, uc, sub.Show.PID, false); err != nil {
		t.Fatal(err)
	}
	host.failWith("/c.xml", 0)
	svc.RetryPendingGpodderAt(ctx, time.Now().Add(6*time.Minute))
	if subs, err := svc.db.SubscriptionsByUser(ctx, uc.ID); err != nil || len(subs) != 0 {
		t.Errorf("subscriptions after the retry = %+v (%v), want none: the account left the show after the ask", subs, err)
	}
	if parks, err := svc.db.GpodderParks(ctx, uc.ID); err != nil || len(parks) != 0 {
		t.Errorf("parks after the retry = %+v (%v), want the stale ask gone", parks, err)
	}
}

// An ask made after the account left a show is a fresh one, and lands.
func TestAParkAskedAfterLeavingTheShowLands(t *testing.T) {
	ctx, svc, uc, _ := openPodcastFixture(t)
	host := newGuidShowHost(t)
	a, c := host.URL+"/a.xml", host.URL+"/c.xml"
	sub, _, err := svc.Subscribe(ctx, uc, SubscribeRequest{URL: a})
	if err != nil {
		t.Fatal(err)
	}
	if err := svc.Unsubscribe(ctx, uc, sub.Show.PID, false); err != nil {
		t.Fatal(err)
	}
	time.Sleep(time.Until(time.Now().Truncate(time.Second).Add(time.Second + 10*time.Millisecond)))
	host.failWith("/c.xml", http.StatusServiceUnavailable)
	if out, err := svc.GpodderApplyChanges(ctx, uc, "phone", []string{c}, nil); err != nil || out[c] != GpodderParked {
		t.Fatalf("the phone's add = %v (%v), want it parked", out, err)
	}
	host.failWith("/c.xml", 0)
	svc.RetryPendingGpodderAt(ctx, time.Now().Add(6*time.Minute))
	show := theOnlyShow(t, ctx, svc, uc)
	if held, err := svc.db.GpodderHeldBy(ctx, uc.ID, "phone"); err != nil || !slices.Equal(held, []string{show}) {
		t.Errorf("the phone holds %v (%v), want the show its later ask landed", held, err)
	}
}

// An ask that parks a feed while a retry is landing it, its device's
// request having found no park and its own fetch failing, is not lost with
// the park the landing ends: it waits for the landing and parks anew.
func TestAnAskParkingDuringALandingIsKept(t *testing.T) {
	ctx, svc, uc, _ := openPodcastFixture(t)
	var hits atomic.Int32
	tabletFetch, tabletGo := make(chan struct{}), make(chan struct{})
	host := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch hits.Add(1) {
		case 1: // the tablet's fetch, held until the landing is
			close(tabletFetch)
			<-tabletGo
		case 3: // the retry's fetch lands it
			w.Header().Set("Content-Type", "application/rss+xml")
			fmt.Fprintf(w, `<?xml version="1.0"?><rss version="2.0"><channel><title>Landing</title>
<item><title>One</title><guid>landing-1</guid><enclosure url="http://%s/one.mp3" type="audio/mpeg" length="1"/></item>
</channel></rss>`, r.Host)
			return
		}
		http.Error(w, "down", http.StatusServiceUnavailable)
	}))
	t.Cleanup(host.Close)
	t.Cleanup(func() {
		select {
		case <-tabletGo:
		default:
			close(tabletGo)
		}
	})
	feed := host.URL + "/feed.xml"
	tablet := make(chan error, 1)
	go func() {
		_, err := svc.GpodderApplyChanges(ctx, uc, "tablet", []string{feed}, nil)
		tablet <- err
	}()
	<-tabletFetch
	if out, err := svc.GpodderApplyChanges(ctx, uc, "phone", []string{feed}, nil); err != nil || out[feed] != GpodderParked {
		t.Fatalf("the phone's add = %v (%v), want it parked", out, err)
	}
	atLanding, landingGo, atPark := make(chan struct{}), make(chan struct{}), make(chan struct{})
	var landingOnce, parkOnce sync.Once
	testHookMembership = func(step string) {
		switch step {
		case "landing":
			landingOnce.Do(func() { close(atLanding); <-landingGo })
		case "park":
			parkOnce.Do(func() { close(atPark) })
		}
	}
	t.Cleanup(func() { testHookMembership = nil })
	retried := make(chan struct{})
	go func() {
		defer close(retried)
		svc.RetryPendingGpodderAt(ctx, time.Now().Add(6*time.Minute))
	}()
	<-atLanding
	close(tabletGo)
	<-atPark
	// The tablet's park either waits for the landing or slips inside it.
	select {
	case err := <-tablet:
		tablet <- err
	case <-time.After(300 * time.Millisecond):
	}
	close(landingGo)
	<-retried
	if err := <-tablet; err != nil {
		t.Fatal(err)
	}
	testHookMembership = nil
	if parks, err := svc.db.GpodderParks(ctx, uc.ID); err != nil || len(parks) != 1 || strings.Join(parks[0].Devices, ",") != "tablet" {
		t.Fatalf("parks after the landing = %+v (%v), want the tablet's ask", parks, err)
	}
}

// An ask that joins a park while a retry is landing it is not lost with
// the park: the device holds the show afterwards.
func TestAnAskJoiningALandingParkIsKept(t *testing.T) {
	ctx, svc, uc, _ := openPodcastFixture(t)
	feed, _ := downThenUp(t, 1)
	if out, err := svc.GpodderApplyChanges(ctx, uc, "phone", []string{feed}, nil); err != nil || out[feed] != GpodderParked {
		t.Fatalf("the phone's add = %v (%v), want it parked", out, err)
	}
	// The tablet decides to join the park before the retry fetches the
	// feed, and asks while the landing reads who asked.
	atPark, atLanding := make(chan struct{}), make(chan struct{})
	parkGo, landingGo := make(chan struct{}), make(chan struct{})
	var parkOnce, landingOnce sync.Once
	testHookMembership = func(step string) {
		switch step {
		case "park":
			parkOnce.Do(func() { close(atPark); <-parkGo })
		case "landing":
			landingOnce.Do(func() { close(atLanding); <-landingGo })
		}
	}
	t.Cleanup(func() { testHookMembership = nil })
	joined := make(chan error, 1)
	go func() {
		_, err := svc.GpodderApplyChanges(ctx, uc, "tablet", []string{feed}, nil)
		joined <- err
	}()
	<-atPark
	retried := make(chan struct{})
	go func() {
		defer close(retried)
		svc.RetryPendingGpodderAt(ctx, time.Now().Add(6*time.Minute))
	}()
	<-atLanding
	close(parkGo)
	// The tablet's ask either waits for the landing or slips inside it.
	select {
	case err := <-joined:
		joined <- err
	case <-time.After(300 * time.Millisecond):
	}
	close(landingGo)
	<-retried
	if err := <-joined; err != nil {
		t.Fatal(err)
	}
	testHookMembership = nil
	svc.RetryPendingGpodderAt(ctx, time.Now().Add(12*time.Minute))
	if _, err := svc.GpodderReplaceDeviceList(ctx, uc, "phone", nil); err != nil {
		t.Fatal(err)
	}
	if subs, err := svc.db.SubscriptionsByUser(ctx, uc.ID); err != nil || len(subs) != 1 {
		t.Fatalf("subscriptions after the phone let go = %+v (%v), want the show the tablet asked for", subs, err)
	}
}

// A YouTube channel is no feed a podcast app can follow: no list, change
// or play action a gpodder client reads names one.
func TestYouTubeShowsStayOffTheGpodderSurface(t *testing.T) {
	youtube := &stubFeed{kind: model.SourceYouTube, n: 1, prefix: "Video", enclosure: watchPage}
	rss := &stubFeed{kind: model.SourceRSS, n: 1, prefix: "Episode"}
	f := openStubFeeds(t, youtube, rss)
	channel, feed := "https://www.youtube.com/@stubchannel", "https://feeds.example/stub.xml"
	for _, s := range []struct{ url, kind string }{{channel, "youtube"}, {feed, "rss"}} {
		sub := f.subscribe(t, s.url, s.kind)
		eps, _, err := f.svc.Episodes(f.ctx, f.uc, sub.Show.PID, "", 1)
		if err != nil || len(eps) != 1 {
			t.Fatalf("episodes of %s = %+v (%v)", s.url, eps, err)
		}
		if _, err := f.svc.Checkpoint(f.ctx, f.uc, eps[0].PID, 30_000, nil); err != nil {
			t.Fatal(err)
		}
	}
	urls, err := f.svc.GpodderFeedURLs(f.ctx, f.uc, "")
	if err != nil || !slices.Equal(urls, []string{feed}) {
		t.Errorf("the subscription list = %v (%v), want the feed alone", urls, err)
	}
	if got := changeLog(t, f.ctx, f.svc, f.uc); !slices.Equal(got, []string{"add " + feed}) {
		t.Errorf("the change log = %v, want the feed's add alone", got)
	}
	actions, _, err := f.svc.GpodderActionsSince(f.ctx, f.uc, "", 0, "", "")
	if err != nil {
		t.Fatal(err)
	}
	for _, a := range actions {
		if a.PodcastURL != feed {
			t.Errorf("a play action names %q, want only the feed's", a.PodcastURL)
		}
	}
	if len(actions) != 1 {
		t.Errorf("play actions = %+v, want the feed's one", actions)
	}
}

// A device is told a show by the URL it was told it by before, however the
// account calls the show since; one that never heard of it is told the
// account's, which a device's own spelling of a followed show, never
// fetched, leaves as it was.
func TestADeviceKeepsTheURLItWasTold(t *testing.T) {
	ctx, svc, uc, feed := openPodcastFixture(t)
	for _, device := range []string{"laptop", "phone", "watch"} {
		if err := svc.GpodderUpsertDevice(ctx, uc, device, "", ""); err != nil {
			t.Fatal(err)
		}
	}
	if _, _, err := svc.Subscribe(ctx, uc, SubscribeRequest{URL: feed}); err != nil {
		t.Fatal(err)
	}
	if urls, err := svc.GpodderFeedURLs(ctx, uc, "laptop"); err != nil || !slices.Equal(urls, []string{feed}) {
		t.Fatalf("the laptop's list = %v (%v), want the account's %q", urls, err, feed)
	}
	respelled := feed + "/"
	if out, err := svc.GpodderApplyChanges(ctx, uc, "phone", []string{respelled}, nil); err != nil || out[respelled] != GpodderLanded {
		t.Fatalf("the phone's add = %v (%v)", out, err)
	}
	if urls, err := svc.GpodderFeedURLs(ctx, uc, "laptop"); err != nil || !slices.Equal(urls, []string{feed}) {
		t.Errorf("the laptop's list after the phone's spelling = %v (%v), want what it was told", urls, err)
	}
	if err := svc.Unsubscribe(ctx, uc, apiPID(PrefixPodcast, model.PID(theOnlyShow(t, ctx, svc, uc))), false); err != nil {
		t.Fatal(err)
	}
	for device, want := range map[string]string{"laptop": feed, "phone": respelled, "watch": feed} {
		evs, _, err := svc.GpodderSubChangesSince(ctx, uc, device, 0)
		if err != nil || len(evs) != 1 || evs[0].Action != "remove" || evs[0].FeedURL != want {
			t.Errorf("the %s's delta = %+v (%v), want the removal under %q", device, evs, err, want)
		}
	}
}
