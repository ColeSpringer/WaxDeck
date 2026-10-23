package service

import (
	"context"
	"testing"

	"github.com/colespringer/waxbin/model"
)

// An unsubscribe whose request goes away just after it committed still
// files its change for the account's other devices: what follows the
// commit runs whether or not the request is there. Not parallel: it sets
// the package's membership hook.
func TestAnUnsubscribeCanceledRightAfterItsCommitFilesItsEvent(t *testing.T) {
	ctx, svc, uc, feed := openPodcastFixture(t)
	if _, _, err := svc.Subscribe(ctx, uc, SubscribeRequest{URL: feed}); err != nil {
		t.Fatal(err)
	}
	shows, err := svc.db.SubscribedShowPIDsByUser(ctx, uc.ID)
	if err != nil || len(shows) != 1 {
		t.Fatalf("shows = %v (%v), want one", shows, err)
	}
	req, cancel := context.WithCancel(ctx)
	defer cancel()
	testHookMembership = func(step string) {
		if step == "removed" {
			cancel()
		}
	}
	t.Cleanup(func() { testHookMembership = nil })
	if err := svc.Unsubscribe(req, uc, apiPID(PrefixPodcast, model.PID(shows[0])), false); err != nil {
		t.Errorf("an unsubscribe canceled past its commit = %v, want it done", err)
	}
	testHookMembership = nil
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
	if last != "remove" {
		t.Errorf("the change log's last word = %q, want remove", last)
	}
}
