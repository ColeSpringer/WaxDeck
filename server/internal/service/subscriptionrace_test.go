package service

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"slices"
	"sync"
	"testing"
	"time"
)

// openPodcastFixture is a service with podcasts on, its admin, and one
// small feed on the loopback.
func openPodcastFixture(t *testing.T) (context.Context, *Library, *UserCtx, string) {
	t.Helper()
	dir := t.TempDir()
	ctx, svc, uc, _ := openServiceAt(t, dir, func(cfg *Config) {
		cfg.PodcastDir = filepath.Join(dir, "podcasts")
		cfg.PodcastRootName = "podcasts"
		cfg.AllowPrivateFeedHosts = true
	})
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/rss+xml")
		fmt.Fprintf(w, `<?xml version="1.0"?><rss version="2.0"><channel><title>Race Show</title>
<item><title>One</title><guid>race-1</guid><enclosure url="http://%s/one.mp3" type="audio/mpeg" length="1"/></item>
</channel></rss>`, r.Host)
	}))
	t.Cleanup(ts.Close)
	return ctx, svc, uc, ts.URL + "/feed.xml"
}

// stallAt holds the first membership change that reaches step until
// released, saying when one got there.
func stallAt(t *testing.T, step string) (<-chan struct{}, func()) {
	t.Helper()
	arrived, gate := make(chan struct{}), make(chan struct{})
	var first, open sync.Once
	testHookMembership = func(s string) {
		if s == step {
			first.Do(func() {
				close(arrived)
				<-gate
			})
		}
	}
	release := func() { open.Do(func() { close(gate) }) }
	t.Cleanup(func() {
		release()
		testHookMembership = nil
	})
	return arrived, release
}

// wantMembershipAgrees checks that the account follows the show exactly
// when something holds it, and that the change log's last word on the
// feed says the same.
func wantMembershipAgrees(t *testing.T, ctx context.Context, l *Library, uc *UserCtx, apiShow, feed string, want bool) {
	t.Helper()
	_, bare, _ := parseAPIPID(apiShow)
	_, err := l.db.SubscriptionFor(ctx, uc.ID, string(bare))
	subscribed := err == nil
	held, err := l.db.GpodderHeldBy(ctx, uc.ID, "")
	if err != nil {
		t.Fatal(err)
	}
	if subscribed != want || slices.Contains(held, string(bare)) != want {
		t.Fatalf("subscribed = %v, held by the apps = %v, want both %v", subscribed, slices.Contains(held, string(bare)), want)
	}
	events, err := l.db.GpodderSubEventsSince(ctx, uc.ID, 0)
	if err != nil {
		t.Fatal(err)
	}
	last := ""
	for _, ev := range events {
		if ev.FeedURL == feed {
			last = ev.Action
		}
	}
	if wantLast := map[bool]string{true: "add", false: "remove"}[want]; last != wantLast {
		t.Fatalf("the change log's last word on the feed = %q, want %q", last, wantLast)
	}
}

// waitBriefly gives a racing call the chance to run into the window, and
// answers whether it finished there.
func waitBriefly(done <-chan error) (error, bool) {
	select {
	case err := <-done:
		return err, true
	case <-time.After(300 * time.Millisecond):
		return nil, false
	}
}

// A subscribe sent while an unsubscribe is halfway through, its row gone
// and its remove not yet filed, waits for it and lands after it, held,
// never in its middle: the unsubscribe's clearing of the holds cannot
// take the new subscription's hold with it, nor its remove outlast the
// add.
func TestAResubscribeCannotLandInsideAnUnsubscribe(t *testing.T) {
	ctx, svc, uc, feed := openPodcastFixture(t)
	sub, _, err := svc.Subscribe(ctx, uc, SubscribeRequest{URL: feed})
	if err != nil {
		t.Fatal(err)
	}
	arrived, release := stallAt(t, "unsubscribe")
	unsubscribed := make(chan error, 1)
	go func() { unsubscribed <- svc.Unsubscribe(ctx, uc, sub.Show.PID, false) }()
	<-arrived
	subscribed := make(chan error, 1)
	go func() {
		_, _, err := svc.Subscribe(ctx, uc, SubscribeRequest{URL: feed})
		subscribed <- err
	}()
	subErr, early := waitBriefly(subscribed)
	release()
	if early {
		t.Errorf("the subscribe finished (%v) while the unsubscribe was halfway through", subErr)
	}
	if err := <-unsubscribed; err != nil {
		t.Fatal(err)
	}
	if !early {
		subErr = <-subscribed
	}
	if subErr != nil {
		t.Fatal(subErr)
	}
	wantMembershipAgrees(t, ctx, svc, uc, sub.Show.PID, feed, true)
}

// The mirror: an unsubscribe sent while a subscribe is halfway through
// lands after it, so the show ends unfollowed with nothing holding it.
func TestAnUnsubscribeCannotLandInsideASubscribe(t *testing.T) {
	ctx, svc, uc, feed := openPodcastFixture(t)
	sub, _, err := svc.Subscribe(ctx, uc, SubscribeRequest{URL: feed})
	if err != nil {
		t.Fatal(err)
	}
	if err := svc.Unsubscribe(ctx, uc, sub.Show.PID, false); err != nil {
		t.Fatal(err)
	}
	arrived, release := stallAt(t, "attach")
	subscribed := make(chan error, 1)
	go func() {
		_, _, err := svc.Subscribe(ctx, uc, SubscribeRequest{URL: feed})
		subscribed <- err
	}()
	<-arrived
	unsubscribed := make(chan error, 1)
	go func() { unsubscribed <- svc.Unsubscribe(ctx, uc, sub.Show.PID, false) }()
	unsubErr, early := waitBriefly(unsubscribed)
	release()
	if err := <-subscribed; err != nil {
		t.Fatal(err)
	}
	if !early {
		unsubErr = <-unsubscribed
	}
	if unsubErr != nil {
		t.Fatal(unsubErr)
	}
	wantMembershipAgrees(t, ctx, svc, uc, sub.Show.PID, feed, false)
}

// Two uploads at once asking for the same feed that cannot land file one
// inbox row between them: checking for the row and filing it is one step.
func TestTwoUploadsAtOnceFileOneRow(t *testing.T) {
	ctx, svc, uc, _ := openPodcastFixture(t)
	gone := feedHost(t).URL + "/status/404"
	arrived, release := stallAt(t, "notice")
	first := make(chan error, 1)
	go func() {
		_, err := svc.GpodderApplyChanges(ctx, uc, "phone", []string{gone}, nil)
		first <- err
	}()
	<-arrived
	second := make(chan error, 1)
	go func() {
		_, err := svc.GpodderApplyChanges(ctx, uc, "phone", []string{gone}, nil)
		second <- err
	}()
	err2, early := waitBriefly(second)
	release()
	if err := <-first; err != nil {
		t.Fatal(err)
	}
	if !early {
		err2 = <-second
	}
	if err2 != nil {
		t.Fatal(err2)
	}
	page, err := svc.Notifications(ctx, uc, "", 50)
	if err != nil {
		t.Fatal(err)
	}
	rows := 0
	for _, n := range page.Notifications {
		if n.Event == "subscription-failed" {
			rows++
		}
	}
	if rows != 1 {
		t.Fatalf("inbox rows for the refused feed = %d, want one", rows)
	}
}

// A settings write that read the subscription before an unsubscribe
// landed cannot bring the show back: it ends unfollowed, nothing holding
// it, and the settings write says it found nothing to change.
func TestASettingsWriteCannotResubscribe(t *testing.T) {
	ctx, svc, uc, feed := openPodcastFixture(t)
	sub, _, err := svc.Subscribe(ctx, uc, SubscribeRequest{URL: feed})
	if err != nil {
		t.Fatal(err)
	}
	arrived, release := stallAt(t, "settings")
	written := make(chan error, 1)
	go func() {
		_, err := svc.PutSubscriptionSettings(ctx, uc, sub.Show.PID, SubscriptionSettings{Folder: "News"})
		written <- err
	}()
	<-arrived
	unsubscribed := make(chan error, 1)
	go func() { unsubscribed <- svc.Unsubscribe(ctx, uc, sub.Show.PID, false) }()
	unsubErr, early := waitBriefly(unsubscribed)
	release()
	if err := <-written; err != nil && KindOf(err) != KindNotFound {
		t.Fatal(err)
	}
	if !early {
		unsubErr = <-unsubscribed
	}
	if unsubErr != nil {
		t.Fatal(unsubErr)
	}
	wantMembershipAgrees(t, ctx, svc, uc, sub.Show.PID, feed, false)
}

// A panic inside a membership change, recovered by its caller, leaves the
// account's lock free: the account's next change goes through.
func TestAPanicInsideAMembershipChangeFreesTheLock(t *testing.T) {
	ctx, svc, uc, feed := openPodcastFixture(t)
	sub, _, err := svc.Subscribe(ctx, uc, SubscribeRequest{URL: feed})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { testHookMembership = nil })
	for _, c := range []struct {
		step   string
		change func()
	}{
		{"unsubscribe", func() { _ = svc.Unsubscribe(ctx, uc, sub.Show.PID, false) }},
		{"attach", func() { _, _, _ = svc.Subscribe(ctx, uc, SubscribeRequest{URL: feed}) }},
		{"settings", func() { _, _ = svc.PutSubscriptionSettings(ctx, uc, sub.Show.PID, SubscriptionSettings{}) }},
	} {
		testHookMembership = func(s string) {
			if s == c.step {
				panic("a bug inside the change")
			}
		}
		func() {
			defer func() { _ = recover() }()
			c.change()
		}()
		testHookMembership = nil
		next := make(chan struct{})
		go func() {
			defer close(next)
			_, _ = svc.PutSubscriptionSettings(ctx, uc, sub.Show.PID, SubscriptionSettings{})
		}()
		select {
		case <-next:
		case <-time.After(5 * time.Second):
			t.Fatalf("after a panic at %q the account's next change waited on its lock", c.step)
		}
	}
}
