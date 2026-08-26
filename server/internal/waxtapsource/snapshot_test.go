package waxtapsource

import (
	"context"
	"errors"
	"log/slog"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/syncsource"

	waxtap "github.com/colespringer/waxtap/v3"
)

func snapshotProvider(f *fakeTap, maxItems int) *Provider {
	return newProvider(f, Config{WorkDir: "unused", MaxItems: maxItems},
		slog.New(slog.DiscardHandler), nil)
}

func TestPlaylistSnapshotKeepsOrderAndFlagsUnavailable(t *testing.T) {
	f := &fakeTap{
		playlist: waxtap.Playlist{
			ID: "PL1", Title: "Road Tapes", Author: "someone",
			Entries: []waxtap.PlaylistEntry{
				{VideoID: "vid-a", Title: "a", Index: 0, Duration: 2 * time.Minute},
				{VideoID: "vid-b", Title: "b", Index: 1},
				{VideoID: "vid-c", Title: "c", Index: 2},
			},
		},
		infos: map[string]*waxtap.Video{
			"vid-a": {ID: "vid-a", Title: "Track A", Thumbnails: []waxtap.Thumbnail{{URL: "https://img/a"}}},
			"vid-c": {ID: "vid-c", Title: "Track C", Thumbnails: []waxtap.Thumbnail{{URL: "https://img/c"}}},
		},
		infoErrs: map[string]error{"vid-b": waxtap.ErrMembersOnly},
	}
	snap, err := snapshotProvider(f, 0).PlaylistSnapshot(context.Background(), "https://youtube.example/pl", syncsource.SnapshotOptions{})
	if err != nil {
		t.Fatal(err)
	}
	if snap.ID != "PL1" || snap.Title != "Road Tapes" || snap.Author != "someone" {
		t.Fatalf("playlist identity: %+v", snap)
	}
	if len(snap.Entries) != 3 {
		t.Fatalf("an unavailable entry was dropped: %+v", snap.Entries)
	}
	for i, want := range []string{"vid-a", "vid-b", "vid-c"} {
		if snap.Entries[i].ID != want || snap.Entries[i].Index != i {
			t.Fatalf("order broke at %d: %+v", i, snap.Entries[i])
		}
	}
	b := snap.Entries[1]
	if !b.Unavailable || !b.AvailabilityKnown {
		t.Fatalf("members-only entry not flagged: %+v", b)
	}
	if b.Title != "b" {
		t.Fatalf("unavailable entry lost its listing title: %+v", b)
	}
	a := snap.Entries[0]
	if a.Unavailable || !a.AvailabilityKnown || a.Title != "Track A" || a.ThumbnailURL != "https://img/a" {
		t.Fatalf("enriched entry: %+v", a)
	}
	if snap.Truncated {
		t.Fatal("nothing was truncated")
	}
}

func TestPlaylistSnapshotCoverIsFirstAvailableThumbnail(t *testing.T) {
	f := &fakeTap{
		playlist: waxtap.Playlist{
			ID: "PL1",
			Entries: []waxtap.PlaylistEntry{
				{VideoID: "vid-gone", Index: 0},
				{VideoID: "vid-a", Index: 1},
			},
		},
		infos: map[string]*waxtap.Video{
			"vid-a": {ID: "vid-a", Thumbnails: []waxtap.Thumbnail{{URL: "https://img/a"}}},
		},
		infoErrs: map[string]error{"vid-gone": waxtap.ErrVideoUnavailable},
	}
	snap, err := snapshotProvider(f, 0).PlaylistSnapshot(context.Background(), "u", syncsource.SnapshotOptions{})
	if err != nil {
		t.Fatal(err)
	}
	if snap.CoverURL != "https://img/a" {
		t.Fatalf("cover skipped past the dead first entry: %q", snap.CoverURL)
	}
}

func TestPlaylistSnapshotBoundsEnrichmentNotTheListing(t *testing.T) {
	var entries []waxtap.PlaylistEntry
	for i := 0; i < enrichLimit+10; i++ {
		entries = append(entries, waxtap.PlaylistEntry{
			VideoID: string(rune('a'+i%26)) + "-vid", Index: i, Title: "t",
		})
	}
	// Distinct ids so the info-call count is honest.
	for i := range entries {
		entries[i].VideoID = "vid-" + string(rune('a'+i/26)) + string(rune('a'+i%26))
	}
	f := &fakeTap{playlist: waxtap.Playlist{ID: "PL1", Entries: entries}}
	snap, err := snapshotProvider(f, 0).PlaylistSnapshot(context.Background(), "u", syncsource.SnapshotOptions{})
	if err != nil {
		t.Fatal(err)
	}
	if len(snap.Entries) != enrichLimit+10 {
		t.Fatalf("listing was capped: %d", len(snap.Entries))
	}
	if len(f.infoCalls) != enrichLimit {
		t.Fatalf("info calls: %d want %d", len(f.infoCalls), enrichLimit)
	}
	tail := snap.Entries[enrichLimit]
	if tail.AvailabilityKnown || tail.Unavailable {
		t.Fatalf("past the budget availability must be unknown: %+v", tail)
	}
}

func TestPlaylistSnapshotHardErrorFailsTheRun(t *testing.T) {
	wire := errors.New("network down")
	f := &fakeTap{
		playlist: waxtap.Playlist{ID: "PL1", Entries: []waxtap.PlaylistEntry{{VideoID: "vid-a"}}},
		infoErrs: map[string]error{"vid-a": wire},
	}
	if _, err := snapshotProvider(f, 0).PlaylistSnapshot(context.Background(), "u", syncsource.SnapshotOptions{}); !errors.Is(err, wire) {
		t.Fatalf("hard error swallowed: %v", err)
	}
}

func TestPlaylistSnapshotHonorsProbeOptions(t *testing.T) {
	f := &fakeTap{
		playlist: waxtap.Playlist{
			ID: "PL1", Title: "Road Tapes",
			Entries: []waxtap.PlaylistEntry{
				{VideoID: "vid-a", Index: 0},
				{VideoID: "vid-b", Index: 1},
				{VideoID: "vid-c", Index: 2},
			},
		},
		infos: map[string]*waxtap.Video{
			"vid-a": {ID: "vid-a", Thumbnails: []waxtap.Thumbnail{{URL: "https://img/a"}}},
		},
	}
	// The bind-time probe: a couple of entries, one lookup, and the
	// identity plus cover are in hand without paging the source.
	snap, err := snapshotProvider(f, 0).PlaylistSnapshot(context.Background(), "u",
		syncsource.SnapshotOptions{MaxEntries: 2, EnrichLimit: 1})
	if err != nil {
		t.Fatal(err)
	}
	if snap.IdentityKey != "youtube:PL1" || snap.CoverURL != "https://img/a" {
		t.Fatalf("probe identity/cover: %+v", snap)
	}
	if len(snap.Entries) != 2 || len(f.infoCalls) != 1 {
		t.Fatalf("probe bounds: %d entries, %d lookups", len(snap.Entries), len(f.infoCalls))
	}
}

func TestPlaylistSnapshotReportsTruncation(t *testing.T) {
	f := &fakeTap{
		playlist: waxtap.Playlist{
			ID: "PL1",
			Entries: []waxtap.PlaylistEntry{
				{VideoID: "vid-a", Index: 0},
				{VideoID: "vid-b", Index: 1},
				{VideoID: "vid-c", Index: 2},
			},
		},
	}
	snap, err := snapshotProvider(f, 2).PlaylistSnapshot(context.Background(), "u", syncsource.SnapshotOptions{})
	if err != nil {
		t.Fatal(err)
	}
	if len(snap.Entries) != 2 || !snap.Truncated {
		t.Fatalf("cap not reported: %d entries, truncated=%v", len(snap.Entries), snap.Truncated)
	}
}
