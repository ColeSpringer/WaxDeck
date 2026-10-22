package service

import (
	"context"
	"testing"

	"github.com/colespringer/waxbin/model"
)

// subscriptionEvents is what one account's server stream says about a
// show after since: each subscription event, its payload or nil.
func subscriptionEvents(t *testing.T, d dormantFollower, since string) []*Subscription {
	t.Helper()
	delta, err := d.svc.SyncServerDelta(d.ctx, d.carol(t), since, 100)
	if err != nil {
		t.Fatal(err)
	}
	var out []*Subscription
	for _, ev := range delta.Events {
		if ev.Kind == eventSubscription && ev.PID == d.show {
			out = append(out, ev.Subscription)
		}
	}
	return out
}

// An account that cannot see the podcast library follows nothing on its
// server stream either: a subscription event reads as absent there, as
// the listing, the show and the exports all answer.
func TestADormantSubscriptionReadsAbsentOnTheServerStream(t *testing.T) {
	d := newDormantFollower(t)
	since, err := d.svc.MintServerCursor(d.ctx)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := d.svc.PutSubscriptionSettings(d.ctx, d.carol(t), d.show, SubscriptionSettings{Folder: "News"}); err != nil {
		t.Fatal(err)
	}
	d.narrow(t)
	events := subscriptionEvents(t, d, since)
	if len(events) == 0 {
		t.Fatal("the stream says nothing of the show")
	}
	for _, sub := range events {
		if sub != nil {
			t.Errorf("a narrowed account's stream hydrates %+v, want the subscription absent", sub)
		}
	}
}

// A grant change tells the account's devices about every show it
// follows, so each reads the subscription as the new grant has it:
// absent once narrowed, back once regranted.
func TestAGrantChangeAnnouncesTheAccountsSubscriptions(t *testing.T) {
	d := newDormantFollower(t)
	d.narrow(t)
	since, err := d.svc.MintServerCursor(d.ctx)
	if err != nil {
		t.Fatal(err)
	}
	podcastLib, _ := d.svc.podcastLibrary(d.ctx)
	mode := "granted"
	if _, err := d.svc.UpdateAccount(d.ctx, d.carolID, AccountUpdate{
		AccessMode: &mode, LibraryPIDs: []string{d.music, apiPID(PrefixLibrary, model.PID(podcastLib))},
	}); err != nil {
		t.Fatal(err)
	}
	events := subscriptionEvents(t, d, since)
	if len(events) != 1 || events[0] == nil || events[0].Show.PID != d.show {
		t.Fatalf("the regranted account's stream = %+v, want the show's subscription back", events)
	}
}

// What an access change retires and announces does not hang on the
// request that made it: an administrator's request canceled once the
// grant is written still ends the account's cursors and tells its
// devices of every show it follows.
func TestAnAccessChangeOutlivesItsRequest(t *testing.T) {
	d := newDormantFollower(t)
	since, err := d.svc.MintServerCursor(d.ctx)
	if err != nil {
		t.Fatal(err)
	}
	before, err := d.svc.grantEpoch(d.ctx, d.carolID)
	if err != nil {
		t.Fatal(err)
	}
	canceled, cancel := context.WithCancel(d.ctx)
	cancel()
	d.svc.reachChanged(canceled, d.carolID)
	if after, err := d.svc.grantEpoch(d.ctx, d.carolID); err != nil || after == before {
		t.Errorf("grant epoch after a canceled access change = %d (%v), want it moved past %d", after, err, before)
	}
	if events := subscriptionEvents(t, d, since); len(events) != 1 {
		t.Errorf("subscription events after a canceled access change = %d, want one for the show", len(events))
	}
}
