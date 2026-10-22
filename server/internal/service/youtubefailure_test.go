package service

import (
	"fmt"
	"path/filepath"
	"testing"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/source"
	"github.com/colespringer/waxbin/waxerr"
	waxtap "github.com/colespringer/waxtap/v3"

	"github.com/colespringer/waxdeck/server/internal/waxtapsource"
)

// A YouTube address that names no channel or playlist is the caller's to
// change, read off the cause the real provider passes up through its wrap
// and the catalog's, not answered as the host's trouble.
func TestAYouTubeAddressThatNamesNoChannelIsRefused(t *testing.T) {
	provider, err := waxtapsource.New(waxtapsource.Config{WorkDir: t.TempDir()})
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	ctx, svc, admin, _ := openServiceAt(t, dir, func(cfg *Config) {
		cfg.PodcastDir = filepath.Join(dir, "podcasts")
		cfg.PodcastRootName = "podcasts"
		cfg.SourceProviders = []source.Provider{provider}
	})
	_, _, err = svc.Subscribe(ctx, admin, SubscribeRequest{URL: "https://feeds.example/not-a-channel", SourceType: "youtube"})
	if KindOf(err) != KindInvalid || FeedFailureReason(err) != reasonNotAFeed {
		t.Errorf("subscribing to an address that names no channel = %v (kind %s, reason %q), want an invalid request, not-a-feed",
			err, KindOf(err), FeedFailureReason(err))
	}
}

// What only YouTube itself can answer, wrapped as the provider and the
// catalog wrap it: a playlist that is private or gone will not come back,
// a sign-in wall is a refusal, and only the host's own trouble can pass.
func TestFeedFailureReasonOfAYouTubeSource(t *testing.T) {
	t.Parallel()
	tap := func(err error) error {
		return &source.ProviderError{SourceType: model.SourceYouTube, Op: "enumerate",
			Err: waxerr.Wrap(waxerr.CodeIO, "waxtapsource.Enumerate", err)}
	}
	for _, c := range []struct {
		name string
		err  error
		want string
	}{
		{"a private or deleted playlist", tap(&waxtap.PlaylistUnavailableError{Reason: "This playlist is private."}), reasonHostMissing},
		{"a channel with no uploads feed", tap(fmt.Errorf("channel UC123: %w", waxtap.ErrPlaylistUnavailable)), reasonHostMissing},
		{"a playlist with no videos", tap(waxtap.ErrPlaylistEmpty), reasonNotAFeed},
		{"a Shorts shelf", tap(waxtap.ErrShortsPlaylist), reasonNotAFeed},
		{"a malformed playlist id", tap(waxtap.ErrInvalidPlaylistID), reasonNotAFeed},
		{"a sign-in wall", tap(waxtap.ErrLoginRequired), reasonHostRefused},
		{"a page YouTube says is gone", tap(&waxtap.HTTPStatusError{StatusCode: 404}), reasonHostMissing},
		{"YouTube having trouble", tap(&waxtap.HTTPStatusError{StatusCode: 503}), reasonHostError},
		{"a throttle", tap(&waxtap.RateLimitError{StatusCode: 429}), reasonHostError},
		{"a page shape the parser does not know", tap(waxtap.ErrPlaylistParse), reasonHostError},
	} {
		if reason, _ := feedFailureReason(c.err); reason != c.want {
			t.Errorf("%s: reason %q, want %q", c.name, reason, c.want)
		}
	}
}
