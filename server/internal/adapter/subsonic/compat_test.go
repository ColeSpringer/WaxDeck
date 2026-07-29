package subsonic

import (
	"testing"

	"github.com/colespringer/waxdeck/server/internal/service"
)

func TestEpisodeShape(t *testing.T) {
	show := service.PodcastShow{PID: "pc-01JZX5N8QW3F4V9T2B7KD3M9R7", Title: "The Show"}
	base := service.EpisodeSummary{
		ItemSummary: service.ItemSummary{
			PID: "ep-01JZX5N8QW3F4V9T2B7KD3M9R6", Title: "Pilot",
			Artist: "The Show", DurationMS: 61000,
		},
		ShowPID:     show.PID,
		PublishedNS: 1_700_000_000_000_000_000,
	}

	downloaded := base
	downloaded.Downloaded = true
	got := episodeShape(downloaded, show)
	if got.Status != "completed" || got.StreamID != downloaded.PID {
		t.Fatalf("downloaded episode = %+v", got)
	}
	if got.ChannelID != show.PID || got.Parent != show.PID {
		t.Fatalf("channel linkage = %+v", got)
	}
	if got.Duration != 61 || got.PublishDate == "" || got.Type != "podcast" {
		t.Fatalf("episode fields = %+v", got)
	}

	// An unfetched enclosure cannot stream through this server, so it
	// must not carry a streamId a client would try to play.
	undownloaded := base
	if got := episodeShape(undownloaded, show); got.Status != "skipped" || got.StreamID != "" {
		t.Fatalf("undownloaded episode = %+v", got)
	}
	failed := base
	failed.FetchState = "failed"
	if got := episodeShape(failed, show); got.Status != "error" || got.StreamID != "" {
		t.Fatalf("failed episode = %+v", got)
	}
	queued := base
	queued.FetchState = "queued"
	if got := episodeShape(queued, show); got.Status != "downloading" {
		t.Fatalf("queued episode = %+v", got)
	}

	// The advisory is reported only when the feed declared it. A false
	// flag means the feed was silent, not that it said clean, so the
	// field stays empty rather than claiming the opposite.
	explicit := base
	explicit.Explicit = true
	if got := episodeShape(explicit, show); got.ExplicitStatus != "explicit" {
		t.Fatalf("explicit episode advisory = %q, want explicit", got.ExplicitStatus)
	}
	if got := episodeShape(base, show); got.ExplicitStatus != "" {
		t.Fatalf("undeclared episode advisory = %q, want empty", got.ExplicitStatus)
	}

	// A channel-level advisory covers every episode under it, which is
	// how the server's own gating reads it: a show marked explicit is
	// withheld whole from an account without the permission, so an
	// episode of one must not report itself unrated here.
	explicitShow := show
	explicitShow.Explicit = true
	if got := episodeShape(base, explicitShow); got.ExplicitStatus != "explicit" {
		t.Fatalf("episode of an explicit show = %q, want explicit", got.ExplicitStatus)
	}
}
