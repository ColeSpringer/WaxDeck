package service

import (
	"context"
	"slices"
	"testing"
	"time"
)

// secondListener is another account on the server, for a show the catalog
// should hold before the test's own account asks again.
func secondListener(t *testing.T, ctx context.Context, svc *Library) *UserCtx {
	t.Helper()
	acct, err := svc.CreateAccount(ctx, AccountCreate{Username: "bob", Password: "correct-horse-2"})
	if err != nil {
		t.Fatal(err)
	}
	bob, err := svc.UserCtx(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	return bob
}

// A parked feed that one device's ask lands, once the catalog holds its
// show, is held for every device that asked: the next device to let go
// leaves the account following it for the others.
func TestALandedParkKeepsEveryDevicesAsk(t *testing.T) {
	ctx, svc, uc, _ := openPodcastFixture(t)
	feed, _ := downThenUp(t, 1)
	for _, device := range []string{"phone", "tablet"} {
		res, err := svc.GpodderReplaceDeviceList(ctx, uc, device, []string{feed})
		if err != nil || res.Outcomes[feed] != GpodderParked {
			t.Fatalf("%s's list = %+v (%v), want the feed parked", device, res, err)
		}
	}
	if _, _, err := svc.Subscribe(ctx, secondListener(t, ctx, svc), SubscribeRequest{URL: feed}); err != nil {
		t.Fatal(err)
	}
	if res, err := svc.GpodderReplaceDeviceList(ctx, uc, "phone", []string{feed}); err != nil || res.Outcomes[feed] != GpodderLanded {
		t.Fatalf("the phone's next list = %+v (%v), want the feed landed", res, err)
	}
	if _, err := svc.GpodderReplaceDeviceList(ctx, uc, "phone", nil); err != nil {
		t.Fatal(err)
	}
	subs, err := svc.db.SubscriptionsByUser(ctx, uc.ID)
	if err != nil || len(subs) != 1 {
		t.Fatalf("subscriptions = %+v (%v): the account left a show the tablet asked for when the phone let go", subs, err)
	}
	if held, err := svc.db.GpodderHeldBy(ctx, uc.ID, "tablet"); err != nil || !slices.Contains(held, subs[0].ShowPID) {
		t.Errorf("the tablet holds %v (%v), want the show", held, err)
	}
	if parks, err := svc.db.GpodderParks(ctx, uc.ID); err != nil || len(parks) != 0 {
		t.Errorf("parks = %+v (%v), want the landed one gone", parks, err)
	}
}

// Leaving a show in the apps withdraws every device's parked ask for its
// feed, so the retry that comes later follows nothing again and no device
// is told to add it.
func TestAnUnsubscribeWithdrawsParkedAsks(t *testing.T) {
	ctx, svc, uc, _ := openPodcastFixture(t)
	feed, _ := downThenUp(t, 1)
	if out, err := svc.GpodderApplyChanges(ctx, uc, "phone", []string{feed}, nil); err != nil || out[feed] != GpodderParked {
		t.Fatalf("outcomes = %v (%v), want the feed parked", out, err)
	}
	sub, _, err := svc.Subscribe(ctx, uc, SubscribeRequest{URL: feed})
	if err != nil {
		t.Fatal(err)
	}
	if err := svc.Unsubscribe(ctx, uc, sub.Show.PID, false); err != nil {
		t.Fatal(err)
	}
	if parks, err := svc.db.GpodderParks(ctx, uc.ID); err != nil || len(parks) != 0 {
		t.Errorf("parks after the unsubscribe = %+v (%v), want none", parks, err)
	}
	svc.RetryPendingGpodderAt(ctx, time.Now().Add(6*time.Minute))
	if subs, err := svc.db.SubscriptionsByUser(ctx, uc.ID); err != nil || len(subs) != 0 {
		t.Errorf("subscriptions after the retry = %+v (%v), want none", subs, err)
	}
	// The change log keeps each show's latest change, which every device's
	// next delta reads.
	evs, _, err := svc.GpodderSubChangesSince(ctx, uc, "", 0)
	if err != nil || len(evs) != 1 || evs[0].Action != "remove" {
		t.Errorf("the change log = %+v (%v), want the feed's removal last", evs, err)
	}
}

// A retry pass reads its parks up front and fetches each in turn, so a
// park a device let go of meanwhile is not landed when the pass reaches
// it.
func TestAWithdrawnParkIsNotLanded(t *testing.T) {
	ctx, svc, uc, _ := openPodcastFixture(t)
	feed, _ := downThenUp(t, 1)
	if out, err := svc.GpodderApplyChanges(ctx, uc, "phone", []string{feed}, nil); err != nil || out[feed] != GpodderParked {
		t.Fatalf("outcomes = %v (%v), want the feed parked", out, err)
	}
	later := time.Now().Add(6 * time.Minute)
	due, err := svc.db.DueGpodderParks(ctx, later.UnixNano(), 100)
	if err != nil || len(due) != 1 {
		t.Fatalf("due parks = %+v (%v), want the one", due, err)
	}
	if _, err := svc.GpodderApplyChanges(ctx, uc, "phone", nil, []string{feed}); err != nil {
		t.Fatal(err)
	}
	if _, notice := svc.retryGpodderPark(ctx, due[0], later); notice != nil {
		t.Errorf("the retry filed %+v for a park nobody asks for", notice)
	}
	if subs, err := svc.db.SubscriptionsByUser(ctx, uc.ID); err != nil || len(subs) != 0 {
		t.Errorf("subscriptions = %+v (%v), want none: the phone let go before the pass reached it", subs, err)
	}
}
