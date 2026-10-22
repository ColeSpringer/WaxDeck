package service

import (
	"context"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"
)

// A membership change whose request is canceled after the change landed
// still files what follows from it: the change log keeps the add, and the
// remove after it, so no device is left believing the old membership.
func TestAMembershipChangeCanceledAfterItsCommitKeepsItsEvents(t *testing.T) {
	ctx, svc, uc, feed := openPodcastFixture(t)
	// changeCanceledAfterCommit runs change on a request canceled once the
	// account's membership reads committed, held meanwhile just past the
	// commit by the podping index's lock.
	changeCanceledAfterCommit := func(committed func() bool, change func(context.Context)) {
		t.Helper()
		req, cancel := context.WithCancel(ctx)
		defer cancel()
		svc.podping.mu.Lock()
		done := make(chan struct{})
		go func() {
			defer close(done)
			change(req)
		}()
		deadline := time.Now().Add(10 * time.Second)
		for !committed() {
			if time.Now().After(deadline) {
				svc.podping.mu.Unlock()
				t.Fatal("the change never committed")
			}
			time.Sleep(5 * time.Millisecond)
		}
		cancel()
		svc.podping.mu.Unlock()
		<-done
	}
	follows := func() bool {
		shows, err := svc.db.SubscribedShowPIDsByUser(ctx, uc.ID)
		if err != nil {
			t.Fatal(err)
		}
		return len(shows) > 0
	}
	lastWord := func() string {
		t.Helper()
		events, err := svc.db.GpodderSubEventsSince(ctx, uc.ID, 0)
		if err != nil {
			t.Fatal(err)
		}
		last := ""
		for _, ev := range events {
			if ev.FeedURL == feed {
				last = ev.Action
			}
		}
		return last
	}

	changeCanceledAfterCommit(follows, func(req context.Context) {
		_, _, _ = svc.Subscribe(req, uc, SubscribeRequest{URL: feed})
	})
	if got := lastWord(); !follows() || got != "add" {
		t.Fatalf("after a subscribe canceled past its commit: follows = %v, the change log's last word = %q, want add", follows(), got)
	}
	shows, err := svc.db.SubscribedShowPIDsByUser(ctx, uc.ID)
	if err != nil || len(shows) != 1 {
		t.Fatalf("shows = %v (%v), want one", shows, err)
	}
	show := apiPID(PrefixPodcast, model.PID(shows[0]))
	changeCanceledAfterCommit(func() bool { return !follows() }, func(req context.Context) {
		_ = svc.Unsubscribe(req, uc, show, false)
	})
	if got := lastWord(); follows() || got != "remove" {
		t.Errorf("after an unsubscribe canceled past its commit: follows = %v, the change log's last word = %q, want remove", follows(), got)
	}
}
