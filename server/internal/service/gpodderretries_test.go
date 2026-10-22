package service

import (
	"context"
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// failedAddRows is the account's inbox rows for adds that did not land.
func failedAddRows(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx) []InboxNotification {
	t.Helper()
	page, err := svc.Notifications(ctx, uc, "", 100)
	if err != nil {
		t.Fatal(err)
	}
	var out []InboxNotification
	for _, n := range page.Notifications {
		if n.Event == "subscription-failed" {
			out = append(out, n)
		}
	}
	return out
}

// scriptedHost answers its requests with the statuses given, in order,
// and a feed after them, saying when it served the feed.
func scriptedHost(t *testing.T, statuses ...int) (string, *atomic.Bool) {
	t.Helper()
	var hits atomic.Int32
	var served atomic.Bool
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if n := int(hits.Add(1)); n <= len(statuses) {
			http.Error(w, "scripted", statuses[n-1])
			return
		}
		served.Store(true)
		w.Header().Set("Content-Type", "application/rss+xml")
		fmt.Fprintf(w, `<?xml version="1.0"?><rss version="2.0"><channel><title>Scripted %s</title>
<item><title>One</title><guid>scripted-%s</guid><enclosure url="http://%s/one.mp3" type="audio/mpeg" length="1"/></item>
</channel></rss>`, r.Host, r.Host, r.Host)
	}))
	t.Cleanup(ts.Close)
	return ts.URL + "/feed.xml", &served
}

// podcastListener is an account granted the configured library and the
// podcast library, which an administrator's first fetch creates; grant
// sets what it is granted from then on.
func podcastListener(t *testing.T, ctx context.Context, svc *Library, admin *UserCtx, feed string) (uc *UserCtx, grant func(podcasts bool)) {
	t.Helper()
	known, _, err := svc.Subscribe(ctx, admin, SubscribeRequest{URL: feed})
	if err != nil {
		t.Fatal(err)
	}
	fetchOneEpisode(t, ctx, svc, admin, known.Show.PID)
	podcastLib, _ := svc.podcastLibrary(ctx)
	podcasts := apiPID(PrefixLibrary, model.PID(podcastLib))
	var music string
	for _, r := range svc.libraryRoots() {
		if r.Name == "configured" {
			music = apiPID(PrefixLibrary, model.PID(r.PID))
		}
	}
	if podcasts == apiPID(PrefixLibrary, "") || music == "" {
		t.Fatalf("libraries = %q and %q, want both", music, podcasts)
	}
	acct, err := svc.CreateAccount(ctx, AccountCreate{Username: "carol", Password: "correct-horse",
		AccessMode: "granted", LibraryPIDs: []string{music, podcasts}})
	if err != nil {
		t.Fatal(err)
	}
	if uc, err = svc.UserCtx(ctx, acct.User); err != nil {
		t.Fatal(err)
	}
	mode := "granted"
	return uc, func(on bool) {
		t.Helper()
		libs := []string{music}
		if on {
			libs = append(libs, podcasts)
		}
		if _, err := svc.UpdateAccount(ctx, uc.ID, AccountUpdate{AccessMode: &mode, LibraryPIDs: libs}); err != nil {
			t.Fatal(err)
		}
	}
}

// A parked feed that comes due while its account cannot see the podcast
// library waits for the grant: not fetched, no attempt counted, nothing
// said, and landed once the grant is back. Past its week it is given up as
// any park is.
func TestAParkWaitsOutAWithdrawnGrant(t *testing.T) {
	ctx, svc, admin, fixture := openPodcastFixture(t)
	uc, grant := podcastListener(t, ctx, svc, admin, fixture)
	feed, hits := downThenUp(t, 1)
	if out, err := svc.GpodderApplyChanges(ctx, uc, "phone", []string{feed}, nil); err != nil || out[feed] != GpodderParked {
		t.Fatalf("outcomes = %v (%v), want the feed parked", out, err)
	}
	grant(false)
	due := time.Now().Add(6 * time.Minute)
	svc.RetryPendingGpodderAt(ctx, due)
	parks, err := svc.db.GpodderParks(ctx, uc.ID)
	if err != nil || len(parks) != 1 || parks[0].Attempts != 0 || parks[0].NextTryNS <= due.UnixNano() {
		t.Fatalf("parks = %+v (%v), want the park waiting, no attempt counted, its next try later", parks, err)
	}
	if hits.Load() != 1 {
		t.Errorf("the host saw %d requests, want none during the withdrawal", hits.Load())
	}
	if rows := failedAddRows(t, ctx, svc, uc); len(rows) != 0 {
		t.Errorf("inbox = %+v, want nothing said of a park that waits", rows)
	}

	grant(true)
	svc.RetryPendingGpodderAt(ctx, due.Add(15*time.Minute))
	if subs, err := svc.db.SubscriptionsByUser(ctx, uc.ID); err != nil || len(subs) != 1 {
		t.Fatalf("subscriptions once the grant is back = %+v (%v), want the parked feed landed", subs, err)
	}

	gone, _ := downThenUp(t, 100)
	if out, err := svc.GpodderApplyChanges(ctx, uc, "phone", []string{gone}, nil); err != nil || out[gone] != GpodderParked {
		t.Fatalf("outcomes = %v (%v), want the feed parked", out, err)
	}
	grant(false)
	svc.RetryPendingGpodderAt(ctx, time.Now().Add(8*24*time.Hour))
	if parks, _ := svc.db.GpodderParks(ctx, uc.ID); len(parks) != 0 {
		t.Errorf("parks a week on = %+v, want the waiting one given up", parks)
	}
	if rows := failedAddRows(t, ctx, svc, uc); len(rows) != 1 {
		t.Errorf("inbox = %+v, want the give-up said once", rows)
	}
}

// A retry that gives a park up drops only the asks it read before its
// fetch: an ask parked while the fetch ran stays parked, and nothing is
// said of an ask withdrawn meanwhile.
func TestAnAskParkedDuringAGiveUpStaysParked(t *testing.T) {
	ctx, svc, uc, _ := openPodcastFixture(t)
	arrived, gate := make(chan struct{}), make(chan struct{})
	var hits atomic.Int32
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if hits.Add(1) == 2 {
			close(arrived)
			<-gate
		}
		http.Error(w, "down", http.StatusServiceUnavailable)
	}))
	t.Cleanup(ts.Close)
	t.Cleanup(func() {
		select {
		case <-gate:
		default:
			close(gate)
		}
	})
	feed := ts.URL + "/feed.xml"
	if out, err := svc.GpodderApplyChanges(ctx, uc, "phone", []string{feed}, nil); err != nil || out[feed] != GpodderParked {
		t.Fatalf("outcomes = %v (%v), want the feed parked", out, err)
	}
	done := make(chan struct{})
	go func() {
		defer close(done)
		svc.RetryPendingGpodderAt(ctx, time.Now().Add(8*24*time.Hour))
	}()
	<-arrived
	// While the week's last try is on the wire, the phone lets go of the
	// feed and the tablet asks for it afresh.
	if _, err := svc.GpodderReplaceDeviceList(ctx, uc, "phone", nil); err != nil {
		t.Fatal(err)
	}
	if out, err := svc.GpodderApplyChanges(ctx, uc, "tablet", []string{feed}, nil); err != nil || out[feed] != GpodderParked {
		t.Fatalf("the tablet's outcomes = %v (%v), want the feed parked afresh", out, err)
	}
	close(gate)
	<-done
	parks, err := svc.db.GpodderParks(ctx, uc.ID)
	if err != nil || len(parks) != 1 || strings.Join(parks[0].Devices, ",") != "tablet" {
		t.Fatalf("parks = %+v (%v), want the tablet's fresh ask", parks, err)
	}
	if rows := failedAddRows(t, ctx, svc, uc); len(rows) != 0 {
		t.Fatalf("inbox = %+v, want nothing said of the ask the phone withdrew", rows)
	}
}

// A park's attempt is counted before its try, so one whose try panics
// every time moves back in the queue and the next pass tries the rest,
// and what a pass said before the panic is still said.
func TestAParkThatPanicsGoesToTheBackOfTheQueue(t *testing.T) {
	ctx, svc, uc, _ := openPodcastFixture(t)
	gone, _ := scriptedHost(t, http.StatusServiceUnavailable, http.StatusNotFound)
	poison, served := scriptedHost(t, http.StatusServiceUnavailable)
	other, _ := scriptedHost(t, http.StatusServiceUnavailable)
	for _, feed := range []string{gone, poison, other} {
		if out, err := svc.GpodderApplyChanges(ctx, uc, "phone", []string{feed}, nil); err != nil || out[feed] != GpodderParked {
			t.Fatalf("outcomes = %v (%v), want %s parked", out, err, feed)
		}
		time.Sleep(time.Millisecond)
	}
	testHookMembership = func(step string) {
		if step == "landing" && served.Swap(false) {
			panic("a poisoned landing")
		}
	}
	t.Cleanup(func() { testHookMembership = nil })
	pass := func(at time.Time) (panicked bool) {
		defer func() { panicked = recover() != nil }()
		svc.RetryPendingGpodderAt(ctx, at)
		return false
	}
	at := time.Now().Add(6 * time.Minute)
	if !pass(at) {
		t.Fatal("the poisoned landing did not panic")
	}
	if rows := failedAddRows(t, ctx, svc, uc); len(rows) != 1 {
		t.Errorf("inbox = %+v, want the refusal the pass made before the panic", rows)
	}
	parks, err := svc.db.GpodderParks(ctx, uc.ID)
	if err != nil {
		t.Fatal(err)
	}
	for _, p := range parks {
		if p.FeedURL == poison && p.NextTryNS <= at.UnixNano() {
			t.Errorf("the poisoned park is due at %d, want it moved past the pass at %d", p.NextTryNS, at.UnixNano())
		}
	}
	if pass(at) {
		t.Fatal("the next pass at the same time reached the poisoned park again")
	}
	subs, err := svc.db.SubscriptionsByUser(ctx, uc.ID)
	if err != nil || len(subs) != 1 {
		t.Fatalf("subscriptions = %+v (%v), want the park behind the poisoned one landed", subs, err)
	}
}

// A notice names a feed by its host, or by no address at all when its URL
// has none: never the URL, whose credentials, path or query can be the
// feed's own secret.
func TestANoticeNamesNoAddress(t *testing.T) {
	ctx, svc, uc, _ := openPodcastFixture(t)
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := ln.Addr().(*net.TCPAddr).Port
	ln.Close()
	hostless := fmt.Sprintf("http://user:pw@:%d/feed?token=s3cr3t", port)
	if _, err := svc.GpodderApplyChanges(ctx, uc, "phone", []string{hostless}, nil); err != nil {
		t.Fatal(err)
	}
	svc.RetryPendingGpodderAt(ctx, time.Now().Add(8*24*time.Hour))
	rows := failedAddRows(t, ctx, svc, uc)
	if len(rows) != 1 {
		t.Fatalf("inbox = %+v, want the add said once", rows)
	}
	for _, leak := range []string{"s3cr3t", "user:pw", "/feed", fmt.Sprint(port)} {
		if strings.Contains(rows[0].Title+rows[0].Body, leak) {
			t.Errorf("the notice %q / %q names %q", rows[0].Title, rows[0].Body, leak)
		}
	}
}

// A server whose podcast directory is off takes no podcasts: every door
// that subscribes refuses for good as a feature the server is not running,
// so nothing parks, a park left from before is refused at its next try,
// the account is told once rather than per feed, and no feed is fetched.
func TestAServerWithoutAPodcastDirectoryRefusesEverySubscribe(t *testing.T) {
	ctx, svc, admin, _ := openServiceAt(t, t.TempDir(), func(cfg *Config) { cfg.AllowPrivateFeedHosts = true })
	feed, hits := downThenUp(t, 0)
	other, _ := downThenUp(t, 0)
	refused := func(door string, err error) {
		t.Helper()
		if KindOf(err) != KindFeature || !errors.Is(err, ErrPodcastsOff) {
			t.Errorf("%s = %v (kind %q), want podcasts refused as off", door, err, KindOf(err))
		}
	}
	_, _, err := svc.Subscribe(ctx, admin, SubscribeRequest{URL: feed})
	refused("a subscribe", err)
	_, err = svc.ImportOPML(ctx, admin, []byte(`<opml version="2.0"><body><outline type="rss" text="Back" xmlUrl="`+feed+`"/></body></opml>`))
	refused("an OPML import", err)
	if out, err := svc.GpodderApplyChanges(ctx, admin, "phone", []string{feed}, nil); err != nil || out[feed] != GpodderRefused {
		t.Errorf("a gpodder add = %v (%v), want it refused", out, err)
	}
	if res, err := svc.GpodderReplaceDeviceList(ctx, admin, "desk", []string{feed, other}); err != nil ||
		res.Outcomes[feed] != GpodderRefused || res.Outcomes[other] != GpodderRefused {
		t.Errorf("a gpodder list = %+v (%v), want its feeds refused", res, err)
	}
	now := time.Now()
	if _, err := svc.db.ParkGpodderPending(ctx, wdb.GpodderPending{UserID: admin.ID, FeedURL: feed, DeviceID: "tablet",
		CreatedAtNS: now.UnixNano(), NextTryNS: now.UnixNano(), LastError: "host-error"}, gpodderPendingPerUser); err != nil {
		t.Fatal(err)
	}
	svc.RetryPendingGpodderAt(ctx, now.Add(time.Minute))
	if subs, err := svc.db.SubscriptionsByUser(ctx, admin.ID); err != nil || len(subs) != 0 {
		t.Errorf("subscriptions = %+v (%v), want none", subs, err)
	}
	if parks, err := svc.db.GpodderParks(ctx, admin.ID); err != nil || len(parks) != 0 {
		t.Errorf("parks = %+v (%v), want none", parks, err)
	}
	if n := hits.Load(); n != 0 {
		t.Errorf("the feed's host was asked %d times, want never", n)
	}
	rows := failedAddRows(t, ctx, svc, admin)
	if len(rows) == 0 {
		t.Error("the inbox says nothing of the refused adds")
	}
	for _, row := range rows {
		if strings.Contains(row.Title+row.Body, "127.0.0.1") {
			t.Errorf("the inbox names a feed for a refusal of every feed: %q / %q", row.Title, row.Body)
		}
		if !strings.Contains(row.Body, "turned off on this server") || strings.Contains(row.Body, "account") {
			t.Errorf("the inbox says %q, want podcasts turned off on this server and nothing of the account", row.Body)
		}
	}
}

// A feed whose week of tries ran out is refused, neither fetched nor
// parked again, when a device asks for it in the month that follows, so
// a list naming it still lets go of what it no longer names, and the inbox
// says nothing more than it said at the give-up.
func TestADeadFeedDoesNotFreezeAList(t *testing.T) {
	ctx, svc, uc, feed := openPodcastFixture(t)
	var hits atomic.Int32
	dead := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits.Add(1)
		http.Error(w, "down", http.StatusServiceUnavailable)
	}))
	t.Cleanup(dead.Close)
	gone := dead.URL + "/gone.xml"
	res, err := svc.GpodderReplaceDeviceList(ctx, uc, "desk", []string{feed, gone})
	if err != nil || res.Outcomes[feed] != GpodderLanded || res.Outcomes[gone] != GpodderParked {
		t.Fatalf("the first list = %+v (%v), want the feed landed and the dead one parked", res, err)
	}
	svc.RetryPendingGpodderAt(ctx, time.Now().Add(8*24*time.Hour))
	tried := hits.Load()
	for range 2 {
		res, err = svc.GpodderReplaceDeviceList(ctx, uc, "desk", []string{gone})
		if err != nil || res.Outcomes[gone] != GpodderRefused {
			t.Fatalf("a list after the give-up = %+v (%v), want the dead feed refused", res, err)
		}
	}
	if subs, err := svc.db.SubscriptionsByUser(ctx, uc.ID); err != nil || len(subs) != 0 {
		t.Errorf("subscriptions = %+v (%v), want the show the desk no longer lists let go", subs, err)
	}
	if parks, err := svc.db.GpodderParks(ctx, uc.ID); err != nil || len(parks) != 0 {
		t.Errorf("parks = %+v (%v), want none", parks, err)
	}
	if hits.Load() != tried {
		t.Errorf("the dead host saw %d requests after the give-up, want none", hits.Load()-tried)
	}
	if rows := failedAddRows(t, ctx, svc, uc); len(rows) != 1 {
		t.Errorf("inbox = %+v, want the give-up alone", rows)
	}
}

// A park's age is its oldest ask still standing when the retry reaches it,
// not when the pass listed it: an ask two days old keeps waiting out a
// withdrawn grant though the week-old ask beside it went while the pass
// was on its way.
func TestAParkIsAsOldAsItsAsksWhenTried(t *testing.T) {
	ctx, svc, admin, fixture := openPodcastFixture(t)
	uc, grant := podcastListener(t, ctx, svc, admin, fixture)
	dead := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "down", http.StatusServiceUnavailable)
	}))
	t.Cleanup(dead.Close)
	feed := dead.URL + "/feed.xml"
	now := time.Now()
	for _, ask := range []struct {
		device string
		age    time.Duration
	}{{"phone", 8 * 24 * time.Hour}, {"tablet", 2 * 24 * time.Hour}} {
		if ok, err := svc.db.ParkGpodderPending(ctx, wdb.GpodderPending{UserID: uc.ID, FeedURL: feed, DeviceID: ask.device,
			CreatedAtNS: now.Add(-ask.age).UnixNano(), NextTryNS: now.Add(-time.Minute).UnixNano(), LastError: "host-error"}, 200); err != nil || !ok {
			t.Fatalf("parking the %s's ask = %v (%v)", ask.device, ok, err)
		}
	}
	grant(false)
	due, err := svc.db.DueGpodderParks(ctx, now.UnixNano(), 100)
	if err != nil || len(due) != 1 {
		t.Fatalf("due = %+v (%v)", due, err)
	}
	if err := svc.db.DropGpodderPendingFor(ctx, uc.ID, "phone", nil); err != nil {
		t.Fatal(err)
	}
	if _, notice := svc.retryGpodderPark(ctx, due[0], now); notice != nil {
		t.Errorf("the retry said %+v, want the tablet's ask waiting quietly", notice)
	}
	if parks, err := svc.db.GpodderParks(ctx, uc.ID); err != nil || len(parks) != 1 || strings.Join(parks[0].Devices, ",") != "tablet" ||
		parks[0].Attempts != due[0].Attempts {
		t.Errorf("parks = %+v (%v), want the tablet's ask waiting, no attempt counted", parks, err)
	}
}

// An ask parked afresh while a retry's fetch runs keeps its own schedule:
// the retry's backoff is the asks it read.
func TestAnAskParkedDuringARetryKeepsItsSchedule(t *testing.T) {
	ctx, svc, uc, _ := openPodcastFixture(t)
	arrived, gate := make(chan struct{}), make(chan struct{})
	var hits atomic.Int32
	host := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if hits.Add(1) == 2 {
			close(arrived)
			<-gate
		}
		http.Error(w, "down", http.StatusServiceUnavailable)
	}))
	t.Cleanup(host.Close)
	t.Cleanup(func() {
		select {
		case <-gate:
		default:
			close(gate)
		}
	})
	feed := host.URL + "/feed.xml"
	if out, err := svc.GpodderApplyChanges(ctx, uc, "phone", []string{feed}, nil); err != nil || out[feed] != GpodderParked {
		t.Fatalf("the phone's add = %v (%v), want it parked", out, err)
	}
	// Five tries made already: the next ones a day apart.
	asks, err := svc.db.GpodderParkAsks(ctx, uc.ID, feed)
	if err != nil {
		t.Fatal(err)
	}
	if err := svc.db.RescheduleGpodderParkAsks(ctx, uc.ID, feed, asks, 5, time.Now().UnixNano(), "host-error"); err != nil {
		t.Fatal(err)
	}
	done := make(chan struct{})
	go func() {
		defer close(done)
		svc.RetryPendingGpodderAt(ctx, time.Now().Add(time.Hour))
	}()
	<-arrived
	if _, err := svc.GpodderReplaceDeviceList(ctx, uc, "phone", nil); err != nil {
		t.Fatal(err)
	}
	if out, err := svc.GpodderApplyChanges(ctx, uc, "tablet", []string{feed}, nil); err != nil || out[feed] != GpodderParked {
		t.Fatalf("the tablet's add = %v (%v), want it parked afresh", out, err)
	}
	close(gate)
	<-done
	parks, err := svc.db.GpodderParks(ctx, uc.ID)
	if err != nil || len(parks) != 1 || parks[0].Attempts != 0 || time.Until(time.Unix(0, parks[0].NextTryNS)) > 10*time.Minute {
		t.Fatalf("parks = %+v (%v), want the tablet's fresh ask at its first try in minutes", parks, err)
	}
}
