package service

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/colespringer/waxdeck/server/internal/providers"
)

// PodcastDirectoryEntry is one directory match, ready to subscribe to.
type PodcastDirectoryEntry struct {
	Name         string
	FeedURL      string
	Author       string
	ArtworkURL   string
	Genre        string
	EpisodeCount int
}

// podcastDirectorySearch builds the directory client on first use. The
// base is a config override so a test can point it at a fake, exactly
// as the radio directory's is.
func (l *Library) podcastDirectorySearch() *providers.PodcastDirectory {
	l.podcastDirectoryOnce.Do(func() {
		l.podcastDirectory = providers.NewPodcastDirectory(providers.PodcastDirectoryConfig{
			BaseURL: l.podcastDirectoryBase,
		})
	})
	return l.podcastDirectory
}

// SearchPodcastDirectory queries the public podcast directory by show
// name, so a listener can subscribe without finding a feed URL first.
//
// Every failure below is one thing to a caller -- the directory did not
// answer -- so all of them land on KindDirectory and the 502 the chip
// already knows how to draw. That includes a throttle: providers.core
// turns 429 and 503 into ErrThrottled, and an untranslated ErrThrottled
// would reach the client as a 500, which reads as this server being
// broken rather than as a busy directory to try again.
func (l *Library) SearchPodcastDirectory(ctx context.Context, q string, limit int) ([]PodcastDirectoryEntry, error) {
	q = strings.TrimSpace(q)
	if q == "" {
		return nil, &Error{Kind: KindInvalid, Msg: "a search query is required"}
	}
	callCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	hits, err := l.podcastDirectorySearch().Search(callCtx, q, limit)
	if err != nil {
		if errors.Is(err, providers.ErrThrottled) {
			return nil, &Error{
				Kind: KindDirectory,
				Msg:  "the podcast directory is busy; try again shortly",
				Err:  err,
			}
		}
		return nil, &Error{
			Kind: KindDirectory,
			Msg:  "the podcast directory could not be reached",
			Err:  err,
		}
	}
	out := make([]PodcastDirectoryEntry, 0, len(hits))
	for _, h := range hits {
		out = append(out, PodcastDirectoryEntry{
			Name:         h.Name,
			FeedURL:      h.FeedURL,
			Author:       h.Author,
			ArtworkURL:   h.ArtworkURL,
			Genre:        h.Genre,
			EpisodeCount: h.EpisodeCount,
		})
	}
	return out, nil
}
