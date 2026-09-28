package service

import (
	"context"
	"errors"
	"io"
	"testing"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/source"

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
	l := &Library{sourceProviders: []source.Provider{onceSource{}}}
	_, items, err := l.acquireList(context.Background(), "https://tube.example/@channel")
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 1 || items[0].Title != "one-shot read" {
		t.Errorf("items = %+v, want the one-shot read's entry", items)
	}
}
