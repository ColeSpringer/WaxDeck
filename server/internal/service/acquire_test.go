package service

import (
	"context"
	"errors"
	"io"
	"sync/atomic"
	"testing"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/source"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/waxtapsource"
)

// The capability is matched by method alone, so a rename on the provider
// would quietly send acquisitions back through the subscription's poll.
var _ onceEnumerator = (*waxtapsource.Provider)(nil)

// onceSource answers its subscription listing and its one-shot listing
// with different entries, so a test can tell which one was read.
type onceSource struct{}

func (onceSource) SourceType() model.SourceType { return model.SourceYouTube }

func (onceSource) Resolve(context.Context, source.Request) (*source.Resolved, error) {
	return nil, errors.New("not used")
}

func (onceSource) Enumerate(context.Context, source.Request) (*source.Enumeration, error) {
	return listingOf("subscription poll"), nil
}

func (onceSource) EnumerateOnce(context.Context, source.Request) (*source.Enumeration, error) {
	return listingOf("one-shot read"), nil
}

func (onceSource) Fetch(context.Context, source.FetchRequest, io.Writer) (*source.FetchResult, error) {
	return nil, errors.New("not used")
}

func listingOf(title string) *source.Enumeration {
	return &source.Enumeration{Feed: &model.Feed{Episodes: []model.FeedEpisode{
		{Title: title, EnclosureURL: "https://tube.example/watch?v=one"},
	}}}
}

// Acquiring a channel is a one-shot read, so it takes the listing that
// leaves a subscription's state alone where the provider offers one: the
// YouTube poll's listing can hand over, and forget, a premiere the
// subscription is waiting on.
func TestAcquisitionReadsTheOneShotListing(t *testing.T) {
	l := bareLibrary(&core{})
	l.Ingest.sourceProviders = []source.Provider{onceSource{}}
	_, items, err := l.Ingest.acquireList(context.Background(), "https://tube.example/@channel")
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 1 || items[0].Title != "one-shot read" {
		t.Errorf("items = %+v, want the one-shot read's entry", items)
	}
}

// countedSource counts the listings asked of it.
type countedSource struct {
	onceSource
	listed *atomic.Int32
}

func (s countedSource) EnumerateOnce(ctx context.Context, req source.Request) (*source.Enumeration, error) {
	s.listed.Add(1)
	return s.onceSource.EnumerateOnce(ctx, req)
}

// An acquisition queued by an account that can no longer sign in, or
// that is gone, fails for good before anything is asked of the source.
func TestAnAcquisitionAsksNothingForAnAccountThatCannotSignIn(t *testing.T) {
	t.Parallel()
	var listed atomic.Int32
	ctx, svc, _ := newCatalogFixtureWith(t, catalogFixtureOptions{sources: []source.Provider{countedSource{listed: &listed}}})
	acct, _ := memberAs(t, ctx, svc, AccountCreate{Username: "digger", UploadEnabled: true})
	off := true
	if _, err := svc.Identity.UpdateAccount(ctx, acct.User.ID, AccountUpdate{Disabled: &off}); err != nil {
		t.Fatal(err)
	}
	for who, id := range map[string]string{"disabled": acct.User.ID, "deleted": "us-nobody"} {
		_, err := svc.Ingest.runAcquire(ctx, &wdb.ToolTask{UserID: id}, toolTaskParams{URL: "https://tube.example/@channel"})
		if !permanentToolErr(err) {
			t.Errorf("an acquisition for a %s account = %v, want a failure no retry is owed", who, err)
		}
	}
	if n := listed.Load(); n != 0 {
		t.Errorf("the source was listed %d times for accounts that cannot sign in", n)
	}
}

// A failed read of the account says nothing about it. A run cut off
// there, as by the server stopping, is left to run again rather than
// failed for good as an account that is gone.
func TestAnAcquisitionRunsAgainAfterAFailedAccountRead(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	stopping, stop := context.WithCancel(ctx)
	stop()
	_, err := svc.Ingest.runAcquire(stopping, &wdb.ToolTask{UserID: admin.ID}, toolTaskParams{URL: "https://tube.example/@channel"})
	if err == nil {
		t.Fatal("an acquisition whose account could not be read finished clean")
	}
	if permanentToolErr(err) {
		t.Fatalf("a failed read of the account = %v, which fails the task for good", err)
	}
}
