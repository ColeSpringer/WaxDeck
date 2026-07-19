package subsonic

import (
	"testing"

	"github.com/colespringer/waxdeck/server/internal/service"
)

func TestEpisodeShape(t *testing.T) {
	base := service.EpisodeSummary{
		ItemSummary: service.ItemSummary{
			PID: "ep-01JZX5N8QW3F4V9T2B7KD3M9R6", Title: "Pilot",
			Artist: "The Show", DurationMS: 61000,
		},
		ShowPID:     "pc-01JZX5N8QW3F4V9T2B7KD3M9R7",
		PublishedNS: 1_700_000_000_000_000_000,
	}

	downloaded := base
	downloaded.Downloaded = true
	got := episodeShape(downloaded, downloaded.ShowPID)
	if got.Status != "completed" || got.StreamID != downloaded.PID {
		t.Fatalf("downloaded episode = %+v", got)
	}
	if got.ChannelID != downloaded.ShowPID || got.Parent != downloaded.ShowPID {
		t.Fatalf("channel linkage = %+v", got)
	}
	if got.Duration != 61 || got.PublishDate == "" || got.Type != "podcast" {
		t.Fatalf("episode fields = %+v", got)
	}

	// An unfetched enclosure cannot stream through this server, so it
	// must not carry a streamId a client would try to play.
	undownloaded := base
	if got := episodeShape(undownloaded, base.ShowPID); got.Status != "skipped" || got.StreamID != "" {
		t.Fatalf("undownloaded episode = %+v", got)
	}
	failed := base
	failed.FetchState = "failed"
	if got := episodeShape(failed, base.ShowPID); got.Status != "error" || got.StreamID != "" {
		t.Fatalf("failed episode = %+v", got)
	}
	queued := base
	queued.FetchState = "queued"
	if got := episodeShape(queued, base.ShowPID); got.Status != "downloading" {
		t.Fatalf("queued episode = %+v", got)
	}
}
