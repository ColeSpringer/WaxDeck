package service

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"
)

// The as-of tests pin the ordering the catalog now owns. WaxDeck used to
// mirror per-field change times in waxdeck.db and drop stale replays
// itself, which could only order a replay against writes that came
// through the service; a change applied straight to the catalog was
// invisible once the mirror held a stamp of its own. Passing the
// recorded time down moves the decision to the one place that sees
// every write.

// fixtureTrackPID returns one scanned fixture track by title, as both
// the API pid the service takes and the catalog pid the out-of-band
// writes below address.
func fixtureTrackPID(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, title string) (string, model.PID) {
	t.Helper()
	page, err := svc.Items(ctx, uc, ItemFilter{MediaType: "music"}, "", 50)
	if err != nil {
		t.Fatalf("listing items: %v", err)
	}
	for _, it := range page.Items {
		if it.Title != title {
			continue
		}
		_, pid, ok := parseAPIPID(it.PID)
		if !ok {
			t.Fatalf("unparseable item pid %q", it.PID)
		}
		return it.PID, pid
	}
	t.Fatalf("fixture track %q not found", title)
	return "", ""
}

// TestTrackFactsCarryEntityPIDs pins the identity the compatibility
// surface groups on. The fixture tracks tag ARTIST but not ALBUMARTIST,
// which is exactly the trap: the catalog's own album-artist handle
// resolves a book's author and does not fall back to the track artist,
// so without the mirror of the display fallback these rows would carry
// no album-artist identity and drop out of the artist index.
func TestTrackFactsCarryEntityPIDs(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	rows, err := svc.TrackFacts(ctx, uc)
	if err != nil {
		t.Fatalf("TrackFacts: %v", err)
	}
	if len(rows) != 4 {
		t.Fatalf("rows = %d, want the 4 fixture tracks", len(rows))
	}
	byArtist := map[string]string{}
	for _, tr := range rows {
		// Every fixture track tags ARTIST but not ALBUMARTIST, so the
		// album-artist handle here is entirely the fallback at work.
		if tr.AlbumArtistPID == "" || !strings.HasPrefix(tr.AlbumArtistPID, PrefixArtist+"-") {
			t.Errorf("%q album-artist pid = %q, want the track artist it falls back to",
				tr.Title, tr.AlbumArtistPID)
		}
		if tr.AlbumPID == "" || !strings.HasPrefix(tr.AlbumPID, PrefixAlbum+"-") {
			t.Errorf("%q album pid = %q", tr.Title, tr.AlbumPID)
		}
		if prev, ok := byArtist[tr.Artist]; ok && prev != tr.AlbumArtistPID {
			t.Errorf("artist %q resolved to two pids: %q and %q", tr.Artist, prev, tr.AlbumArtistPID)
		}
		byArtist[tr.Artist] = tr.AlbumArtistPID
	}
	if len(byArtist) != 2 {
		t.Fatalf("distinct artists = %d, want 2", len(byArtist))
	}
}

func TestReplayedStarLosesToLaterOutOfBandChange(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	pid, catalogPID := fixtureTrackPID(t, ctx, svc, uc, "Amber Waves")

	// An offline star recorded two hours ago replays first and applies.
	old := time.Now().Add(-2 * time.Hour)
	if st, err := svc.SetStar(ctx, uc, pid, true, &old); err != nil || !st.Starred {
		t.Fatalf("first replay: %+v (%v), want starred", st, err)
	}

	// The user then unstars from a surface that never touches WaxDeck's
	// own state. This is the write the retired mirror could not see.
	if _, err := svc.lib.Playback().SetStar(ctx, model.PID(uc.CatalogPID), catalogPID, false, nil); err != nil {
		t.Fatalf("out-of-band unstar: %v", err)
	}

	// A queue flushed afterwards, still carrying an hour-old star, must
	// not resurrect it.
	stale := time.Now().Add(-time.Hour)
	st, err := svc.SetStar(ctx, uc, pid, true, &stale)
	if err != nil {
		t.Fatalf("stale replay: %v", err)
	}
	if st.Starred {
		t.Fatal("a replay older than the out-of-band unstar resurrected the star")
	}

	// A live toggle carries no recorded time and always wins.
	if st, err := svc.SetStar(ctx, uc, pid, true, nil); err != nil || !st.Starred {
		t.Fatalf("live star: %+v (%v), want starred", st, err)
	}
}

func TestReplayedRatingLosesToLaterOutOfBandChange(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	pid, catalogPID := fixtureTrackPID(t, ctx, svc, uc, "Basalt Steps")

	old := time.Now().Add(-2 * time.Hour)
	forty := 40
	if st, err := svc.SetRating(ctx, uc, pid, &forty, &old); err != nil || st.Rating == nil || *st.Rating != 40 {
		t.Fatalf("first replay: %+v (%v), want rating 40", st, err)
	}

	ninety := 90
	if _, err := svc.lib.Playback().SetRating(ctx, model.PID(uc.CatalogPID), catalogPID, &ninety, nil); err != nil {
		t.Fatalf("out-of-band rating: %v", err)
	}

	stale := time.Now().Add(-time.Hour)
	sixty := 60
	st, err := svc.SetRating(ctx, uc, pid, &sixty, &stale)
	if err != nil {
		t.Fatalf("stale replay: %v", err)
	}
	if st.Rating == nil || *st.Rating != 90 {
		t.Fatalf("rating = %v, want the out-of-band 90 to survive", st.Rating)
	}
}

// TestStarLandsInRecordedTime pins the property the importers ride: a
// star carrying a recorded time is stored at that time, so a starred-list
// ordered by star time reflects when the user actually starred it.
func TestStarLandsInRecordedTime(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	pid, catalogPID := fixtureTrackPID(t, ctx, svc, uc, "Cobalt Sky")

	when := time.Date(2024, 3, 4, 5, 6, 7, 0, time.UTC)
	if _, err := svc.SetStar(ctx, uc, pid, true, &when); err != nil {
		t.Fatalf("SetStar: %v", err)
	}
	st, err := svc.lib.Playback().State(ctx, model.PID(uc.CatalogPID), catalogPID)
	if err != nil {
		t.Fatal(err)
	}
	if st == nil || !st.Starred {
		t.Fatalf("state = %+v, want starred", st)
	}
	if got := time.Unix(0, st.StarredAt).UTC(); !got.Equal(when) {
		t.Errorf("starred at %v, want the recorded %v", got, when)
	}
}

// TestFutureRecordedStarClamps keeps the skew clamp WaxDeck still owns:
// the catalog trusts the as-of it is handed, so a client clock running
// ahead must be pulled back here or its write becomes unbeatable.
func TestFutureRecordedStarClamps(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	pid, catalogPID := fixtureTrackPID(t, ctx, svc, uc, "Delta Groove")

	future := time.Now().Add(72 * time.Hour)
	before := time.Now()
	if _, err := svc.SetStar(ctx, uc, pid, true, &future); err != nil {
		t.Fatalf("SetStar: %v", err)
	}
	st, err := svc.lib.Playback().State(ctx, model.PID(uc.CatalogPID), catalogPID)
	if err != nil {
		t.Fatal(err)
	}
	got := time.Unix(0, st.StarredAt)
	if got.Before(before) || got.After(time.Now()) {
		t.Errorf("starred at %v, want it clamped into [%v, now]", got, before)
	}

	// Clamped, so an ordinary live unstar right after still wins.
	if st, err := svc.SetStar(ctx, uc, pid, false, nil); err != nil || st.Starred {
		t.Fatalf("live unstar: %+v (%v), want unstarred", st, err)
	}
}
