package service

import (
	"context"
	"errors"
	"net/http"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/waxerr"
)

// registered registers each device for the account.
func registered(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, devices ...string) {
	t.Helper()
	for _, d := range devices {
		if err := svc.GpodderUpsertDevice(ctx, uc, d, "", ""); err != nil {
			t.Fatal(err)
		}
	}
}

// A device told that a show is gone lets go of what it called the show:
// by a delta read from past the removal, or a list read that no longer
// carries the show. One that never held the show is not held to the
// removal's URL either. When the account follows the show again by
// another URL, each of them is told that one.
func TestAShowFollowedAgainIsToldByItsNewURL(t *testing.T) {
	ctx, svc, uc, _ := openPodcastFixture(t)
	registered(t, ctx, svc, uc, "phone", "laptop", "desk")
	host := newGuidShowHost(t)
	a, b := host.URL+"/a.xml", host.URL+"/b.xml"
	if out, err := svc.GpodderApplyChanges(ctx, uc, "phone", []string{a}, nil); err != nil || out[a] != GpodderLanded {
		t.Fatalf("the phone's add = %v (%v)", out, err)
	}
	if urls, err := svc.GpodderFeedURLs(ctx, uc, "desk"); err != nil || !slices.Equal(urls, []string{a}) {
		t.Fatalf("the desk's list = %v (%v), want %s", urls, err, a)
	}
	if err := svc.Unsubscribe(ctx, uc, apiPID(PrefixPodcast, model.PID(theOnlyShow(t, ctx, svc, uc))), false); err != nil {
		t.Fatal(err)
	}
	// The phone reads the removal, then reads again from past it.
	evs, _, err := svc.GpodderSubChangesSince(ctx, uc, "phone", 0)
	if err != nil || len(evs) != 1 || evs[0].Action != "remove" || evs[0].FeedURL != a {
		t.Fatalf("the phone's delta = %+v (%v), want the removal of %s", evs, err, a)
	}
	if _, _, err := svc.GpodderSubChangesSince(ctx, uc, "phone", evs[0].TsSec); err != nil {
		t.Fatal(err)
	}
	if evs, _, err := svc.GpodderSubChangesSince(ctx, uc, "laptop", 0); err != nil || len(evs) != 1 || evs[0].Action != "remove" {
		t.Fatalf("the laptop's delta = %+v (%v), want the removal", evs, err)
	}
	if urls, err := svc.GpodderFeedURLs(ctx, uc, "desk"); err != nil || len(urls) != 0 {
		t.Fatalf("the desk's list after the leave = %v (%v), want none", urls, err)
	}

	host.failWith("/a.xml", http.StatusNotFound)
	if _, _, err := svc.Subscribe(ctx, uc, SubscribeRequest{URL: b}); err != nil {
		t.Fatal(err)
	}
	for _, d := range []string{"phone", "laptop", "desk"} {
		if urls, err := svc.GpodderFeedURLs(ctx, uc, d); err != nil || !slices.Equal(urls, []string{b}) {
			t.Errorf("the %s's list after the account followed by %s = %v (%v)", d, b, urls, err)
		}
	}
}

// The same when the account follows the show again before the device's
// next read: a device that took the read telling it of the removal lets
// go of what it called the show whatever the change log says of the show
// now, at its next delta, read from that read's answer or from past the
// removal, or its next list.
func TestAShowFollowedAgainBeforeTheNextReadIsToldByItsNewURL(t *testing.T) {
	for _, next := range []string{"a delta from its read's answer", "a delta from past the removal", "its list"} {
		t.Run(next, func(t *testing.T) {
			t.Parallel()
			ctx, svc, uc, _ := openPodcastFixture(t)
			registered(t, ctx, svc, uc, "phone")
			host := newGuidShowHost(t)
			a, b := host.URL+"/a.xml", host.URL+"/b.xml"
			if out, err := svc.GpodderApplyChanges(ctx, uc, "phone", []string{a}, nil); err != nil || out[a] != GpodderLanded {
				t.Fatalf("the phone's add = %v (%v)", out, err)
			}
			if err := svc.Unsubscribe(ctx, uc, apiPID(PrefixPodcast, model.PID(theOnlyShow(t, ctx, svc, uc))), false); err != nil {
				t.Fatal(err)
			}
			evs, answer, err := svc.GpodderSubChangesSince(ctx, uc, "phone", 0)
			if err != nil || len(evs) != 1 || evs[0].Action != "remove" || evs[0].FeedURL != a {
				t.Fatalf("the phone's delta = %+v (%v), want the removal of %s", evs, err, a)
			}
			since := answer
			if next == "a delta from past the removal" {
				since = evs[0].TsSec
				time.Sleep(time.Until(time.Unix(since+1, 10_000_000)))
			}
			host.failWith("/a.xml", http.StatusNotFound)
			if _, _, err := svc.Subscribe(ctx, uc, SubscribeRequest{URL: b}); err != nil {
				t.Fatal(err)
			}
			if next == "its list" {
				if urls, err := svc.GpodderFeedURLs(ctx, uc, "phone"); err != nil || !slices.Equal(urls, []string{b}) {
					t.Errorf("the phone's list = %v (%v), want %s", urls, err, b)
				}
			} else {
				evs, _, err := svc.GpodderSubChangesSince(ctx, uc, "phone", since)
				if err != nil || len(evs) != 1 || evs[0].Action != "add" || evs[0].FeedURL != b {
					t.Errorf("the phone's next delta = %+v (%v), want the add of %s", evs, err, b)
				}
			}
			if urls, err := svc.db.GpodderDeviceURLs(ctx, uc.ID, "phone"); err != nil || len(urls) != 1 ||
				urls[0].FeedURL != b || urls[0].RemovedSec != 0 {
				t.Errorf("the phone calls the show %+v (%v), want %s", urls, err, b)
			}
			if urls, err := svc.GpodderFeedURLs(ctx, uc, "phone"); err != nil || !slices.Equal(urls, []string{b}) {
				t.Errorf("the phone's list = %v (%v), want %s", urls, err, b)
			}
		})
	}
}

// A device that leaves a show itself, by a change naming it or a list
// without it, lets go of what it called the show at once: when the account
// follows the show again by another URL, the device is told that one.
func TestADeviceThatLeftAShowIsToldItsNewURL(t *testing.T) {
	for _, how := range []string{"a change", "a list"} {
		t.Run(how, func(t *testing.T) {
			t.Parallel()
			ctx, svc, uc, feed := openPodcastFixture(t)
			registered(t, ctx, svc, uc, "phone")
			host := newGuidShowHost(t)
			a, b := host.URL+"/a.xml", host.URL+"/b.xml"
			if out, err := svc.GpodderApplyChanges(ctx, uc, "phone", []string{a, feed}, nil); err != nil ||
				out[a] != GpodderLanded || out[feed] != GpodderLanded {
				t.Fatalf("the phone's adds = %v (%v)", out, err)
			}
			if how == "a change" {
				if _, err := svc.GpodderApplyChanges(ctx, uc, "phone", nil, []string{a}); err != nil {
					t.Fatal(err)
				}
			} else if res, err := svc.GpodderReplaceDeviceList(ctx, uc, "phone", []string{feed}); err != nil || res.Released != 1 {
				t.Fatalf("the phone's list = %+v (%v), want the show of %s released", res, err, a)
			}
			host.failWith("/a.xml", http.StatusNotFound)
			if _, _, err := svc.Subscribe(ctx, uc, SubscribeRequest{URL: b}); err != nil {
				t.Fatal(err)
			}
			evs, _, err := svc.GpodderSubChangesSince(ctx, uc, "phone", 0)
			if err != nil {
				t.Fatal(err)
			}
			var told []string
			for _, ev := range evs {
				told = append(told, ev.Action+" "+ev.FeedURL)
			}
			if !slices.Contains(told, "add "+b) || slices.ContainsFunc(told, func(s string) bool { return strings.HasSuffix(s, " "+a) }) {
				t.Errorf("the phone's delta = %v, want the add of %s and nothing of %s", told, b, a)
			}
			if urls, err := svc.GpodderFeedURLs(ctx, uc, "phone"); err != nil || !slices.Contains(urls, b) || slices.Contains(urls, a) {
				t.Errorf("the phone's list = %v (%v), want %s and not %s", urls, err, b, a)
			}
		})
	}
}

// A device that never took the read telling it of a removal still holds
// the show by its own URL: told the show again under that URL, from before
// the removal, it is told by that URL from then on.
func TestARemovalNeverTakenKeepsTheDevicesURL(t *testing.T) {
	ctx, svc, uc, _ := openPodcastFixture(t)
	registered(t, ctx, svc, uc, "phone")
	host := newGuidShowHost(t)
	a, b := host.URL+"/a.xml", host.URL+"/b.xml"
	if out, err := svc.GpodderApplyChanges(ctx, uc, "phone", []string{a}, nil); err != nil || out[a] != GpodderLanded {
		t.Fatalf("the phone's add = %v (%v)", out, err)
	}
	show := apiPID(PrefixPodcast, model.PID(theOnlyShow(t, ctx, svc, uc)))
	if err := svc.Unsubscribe(ctx, uc, show, false); err != nil {
		t.Fatal(err)
	}
	// The answer telling the phone of the removal never reaches it.
	if _, _, err := svc.GpodderSubChangesSince(ctx, uc, "phone", 0); err != nil {
		t.Fatal(err)
	}
	if _, _, err := svc.Subscribe(ctx, uc, SubscribeRequest{URL: b}); err != nil {
		t.Fatal(err)
	}
	evs, answer, err := svc.GpodderSubChangesSince(ctx, uc, "phone", 0)
	if err != nil || len(evs) != 1 || evs[0].Action != "add" || evs[0].FeedURL != a {
		t.Fatalf("the phone's read from before the removal = %+v (%v), want the add of its own %s", evs, err, a)
	}
	if _, answer, err = svc.GpodderSubChangesSince(ctx, uc, "phone", answer); err != nil {
		t.Fatal(err)
	}
	if err := svc.Unsubscribe(ctx, uc, show, false); err != nil {
		t.Fatal(err)
	}
	if evs, _, err := svc.GpodderSubChangesSince(ctx, uc, "phone", answer); err != nil || len(evs) != 1 || evs[0].Action != "remove" || evs[0].FeedURL != a {
		t.Errorf("the phone's delta after the account left again = %+v (%v), want the removal of its own %s", evs, err, a)
	}
}

// A device told the account left a show that adds the show back by its own
// URL holds that URL, though the account followed the show again by
// another meanwhile: its next read from past the removal tells it nothing
// of the other.
func TestADeviceAddingAShowBackKeepsItsOwnURL(t *testing.T) {
	ctx, svc, uc, _ := openPodcastFixture(t)
	registered(t, ctx, svc, uc, "phone")
	host := newGuidShowHost(t)
	a, b := host.URL+"/a.xml", host.URL+"/b.xml"
	if out, err := svc.GpodderApplyChanges(ctx, uc, "phone", []string{a}, nil); err != nil || out[a] != GpodderLanded {
		t.Fatalf("the phone's add = %v (%v)", out, err)
	}
	if err := svc.Unsubscribe(ctx, uc, apiPID(PrefixPodcast, model.PID(theOnlyShow(t, ctx, svc, uc))), false); err != nil {
		t.Fatal(err)
	}
	_, answer, err := svc.GpodderSubChangesSince(ctx, uc, "phone", 0)
	if err != nil {
		t.Fatal(err)
	}
	if _, _, err := svc.Subscribe(ctx, uc, SubscribeRequest{URL: b}); err != nil {
		t.Fatal(err)
	}
	if out, err := svc.GpodderApplyChanges(ctx, uc, "phone", []string{a}, nil); err != nil || out[a] != GpodderLanded {
		t.Fatalf("the phone's add back = %v (%v)", out, err)
	}
	evs, _, err := svc.GpodderSubChangesSince(ctx, uc, "phone", answer)
	if err != nil {
		t.Fatal(err)
	}
	for _, ev := range evs {
		if ev.FeedURL != a {
			t.Errorf("the phone's next delta = %+v, want nothing under any URL but its own %s", evs, a)
		}
	}
	if urls, err := svc.GpodderFeedURLs(ctx, uc, "phone"); err != nil || !slices.Equal(urls, []string{a}) {
		t.Errorf("the phone's list = %v (%v), want its own %s", urls, err, a)
	}
}

// One change that adds a show's new address and removes its old one moves
// the device to the new address and keeps the show followed: the remove
// names the show the same change's add landed.
func TestAMoveInOneChangeKeepsTheShow(t *testing.T) {
	ctx, svc, uc, _ := openPodcastFixture(t)
	registered(t, ctx, svc, uc, "phone")
	host := newGuidShowHost(t)
	a, b := host.URL+"/a.xml", host.URL+"/b.xml"
	if out, err := svc.GpodderApplyChanges(ctx, uc, "phone", []string{a}, nil); err != nil || out[a] != GpodderLanded {
		t.Fatalf("the phone's add = %v (%v)", out, err)
	}
	out, err := svc.GpodderApplyChanges(ctx, uc, "phone", []string{b}, []string{a})
	if err != nil || out[b] != GpodderLanded {
		t.Fatalf("the move = %v (%v), want %s landed", out, err, b)
	}
	if subs, err := svc.db.SubscriptionsByUser(ctx, uc.ID); err != nil || len(subs) != 1 {
		t.Fatalf("subscriptions after the move = %+v (%v), want the show still followed", subs, err)
	}
	if urls, err := svc.GpodderFeedURLs(ctx, uc, "phone"); err != nil || !slices.Equal(urls, []string{b}) {
		t.Errorf("the phone's list after the move = %v (%v), want %s", urls, err, b)
	}
}

// What a device sends wins over what a read of its changes told it a
// moment before: a read only fills in a show the device has no URL for.
func TestAReadNeverOverwritesWhatADeviceSent(t *testing.T) {
	ctx, svc, uc, feed := openPodcastFixture(t)
	registered(t, ctx, svc, uc, "phone")
	if _, _, err := svc.Subscribe(ctx, uc, SubscribeRequest{URL: feed}); err != nil {
		t.Fatal(err)
	}
	arrived, release := stallAt(t, "told")
	read := make(chan error, 1)
	go func() {
		_, _, err := svc.GpodderSubChangesSince(ctx, uc, "phone", 0)
		read <- err
	}()
	<-arrived
	respelled := feed + "/"
	if out, err := svc.GpodderApplyChanges(ctx, uc, "phone", []string{respelled}, nil); err != nil || out[respelled] != GpodderLanded {
		t.Fatalf("the phone's add = %v (%v)", out, err)
	}
	release()
	if err := <-read; err != nil {
		t.Fatal(err)
	}
	if urls, err := svc.GpodderFeedURLs(ctx, uc, "phone"); err != nil || !slices.Equal(urls, []string{respelled}) {
		t.Errorf("the phone's list = %v (%v), want the spelling it sent, %s", urls, err, respelled)
	}
}

// A read for a device nobody registered keeps no URLs for it, so it takes
// no turn at the writer: it answers while a backup holds the writer.
func TestAnUnregisteredDevicesReadWritesNothing(t *testing.T) {
	ctx, svc, uc, feed := openPodcastFixture(t)
	if _, _, err := svc.Subscribe(ctx, uc, SubscribeRequest{URL: feed}); err != nil {
		t.Fatal(err)
	}
	tx, err := svc.db.Writer().BeginTx(ctx, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback()
	done := make(chan error, 1)
	go func() {
		if _, _, err := svc.GpodderSubChangesSince(ctx, uc, "ghost", 0); err != nil {
			done <- err
			return
		}
		_, err := svc.GpodderFeedURLs(ctx, uc, "ghost")
		done <- err
	}()
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(2 * time.Second):
		tx.Rollback()
		<-done
		t.Fatal("a read for an unregistered device waited for the writer")
	}
}

// A list read the catalog cannot answer fails, and says why: a device that
// mirrors the server's list must not read "you follow nothing" from a
// catalog hand-off. Only a show gone from the catalog is left out.
func TestAListReadFailsWhenTheCatalogCannotAnswer(t *testing.T) {
	ctx, svc, uc, feed := openPodcastFixture(t)
	if _, _, err := svc.Subscribe(ctx, uc, SubscribeRequest{URL: feed}); err != nil {
		t.Fatal(err)
	}
	svc.showReadHook = func(context.Context, model.PID) (*model.Podcast, error) {
		return nil, errors.New("sql: database is closed")
	}
	t.Cleanup(func() { svc.showReadHook = nil })
	if urls, err := svc.GpodderFeedURLs(ctx, uc, ""); KindOf(err) != KindMaintenance {
		t.Errorf("the list during a hand-off = %v (%v), want a maintenance error", urls, err)
	}
	svc.showReadHook = func(context.Context, model.PID) (*model.Podcast, error) {
		return nil, waxerr.New(waxerr.CodeNotFound, "podcast.Get", "no such podcast")
	}
	if urls, err := svc.GpodderFeedURLs(ctx, uc, ""); err != nil || len(urls) != 0 {
		t.Errorf("the list with its show gone = %v (%v), want empty", urls, err)
	}
}
