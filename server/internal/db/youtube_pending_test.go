package db

import (
	"context"
	"slices"
	"testing"
	"time"
)

const day = int64(24 * time.Hour)

// mustPending lists at a time every stamp in these tests is within the
// horizon of.
func mustPending(t *testing.T, d *DB, source string) []string {
	t.Helper()
	return mustPendingAt(t, d, source, 0)
}

func mustPendingAt(t *testing.T, d *DB, source string, nowNS int64) []string {
	t.Helper()
	ids, err := d.YouTubePending(context.Background(), source, nowNS)
	if err != nil {
		t.Fatalf("listing %s: %v", source, err)
	}
	return ids
}

// The rotation rests on the order: the entry looked at longest ago comes
// first, so a few probes per poll reach every held entry in turn.
func TestYouTubePendingListsTheLeastRecentlyProbedFirst(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	if err := d.RememberYouTubePending(ctx, "UUa", []string{"v1", "v2", "v3"}, 10); err != nil {
		t.Fatal(err)
	}
	if err := d.RememberYouTubePending(ctx, "UUb", []string{"v9"}, 5); err != nil {
		t.Fatal(err)
	}
	if err := d.MarkYouTubePendingProbed(ctx, "UUa", "v1", 30); err != nil {
		t.Fatal(err)
	}
	if err := d.MarkYouTubePendingProbed(ctx, "UUa", "v2", 20); err != nil {
		t.Fatal(err)
	}
	if got, want := mustPending(t, d, "UUa"), []string{"v3", "v2", "v1"}; !slices.Equal(got, want) {
		t.Errorf("UUa pending = %v, want %v", got, want)
	}
	if got, want := mustPending(t, d, "UUb"), []string{"v9"}; !slices.Equal(got, want) {
		t.Errorf("UUb pending = %v, want %v", got, want)
	}
}

// An entry a listing last showed live more than 90 days ago is no
// longer looked for, whether or not the prune has run.
func TestYouTubePendingHidesEntriesPastTheHorizon(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	if err := d.RememberYouTubePending(ctx, "UUa", []string{"v1"}, 1*day); err != nil {
		t.Fatal(err)
	}
	if err := d.RememberYouTubePending(ctx, "UUa", []string{"v2"}, 60*day); err != nil {
		t.Fatal(err)
	}
	if got, want := mustPendingAt(t, d, "UUa", 90*day), []string{"v1", "v2"}; !slices.Equal(got, want) {
		t.Errorf("pending at day 90 = %v, want %v", got, want)
	}
	if got, want := mustPendingAt(t, d, "UUa", 92*day), []string{"v2"}; !slices.Equal(got, want) {
		t.Errorf("pending at day 92 = %v, want %v", got, want)
	}
}

// A live entry is remembered again on every poll that lists it, and the
// horizon runs from the last of those sightings: one passed over late in
// a long wait still gets the whole horizon of lookups.
func TestYouTubePendingCountsTheHorizonFromTheLastSighting(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	if err := d.RememberYouTubePending(ctx, "UUa", []string{"v1"}, 1*day); err != nil {
		t.Fatal(err)
	}
	if err := d.RememberYouTubePending(ctx, "UUa", []string{"v1"}, 50*day); err != nil {
		t.Fatal(err)
	}
	if got := mustPendingAt(t, d, "UUa", 92*day); !slices.Equal(got, []string{"v1"}) {
		t.Errorf("pending at day 92 = %v, want the re-sighted entry", got)
	}
	if n, err := d.PruneYouTubePending(ctx, 92*day); err != nil || n != 0 {
		t.Errorf("prune at day 92 = (%d, %v), want nothing", n, err)
	}
	if n, err := d.PruneYouTubePending(ctx, 141*day); err != nil || n != 1 {
		t.Errorf("prune at day 141 = (%d, %v), want the entry", n, err)
	}
}

// A sighting is not a lookup, so it leaves the rotation's order alone.
func TestYouTubePendingKeepsTheProbeStampOnASighting(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	if err := d.RememberYouTubePending(ctx, "UUa", []string{"v1", "v2"}, 10); err != nil {
		t.Fatal(err)
	}
	if err := d.MarkYouTubePendingProbed(ctx, "UUa", "v1", 30); err != nil {
		t.Fatal(err)
	}
	if err := d.RememberYouTubePending(ctx, "UUa", []string{"v1", "v2"}, 40); err != nil {
		t.Fatal(err)
	}
	if got, want := mustPending(t, d, "UUa"), []string{"v2", "v1"}; !slices.Equal(got, want) {
		t.Errorf("pending = %v, want %v", got, want)
	}
}

// A hand-over is confirmed by its own token: entries handed over by
// another answer, or held by another playlist, stay.
func TestYouTubePendingConfirmsOnlyTheNamedHandOver(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	if err := d.RememberYouTubePending(ctx, "UUa", []string{"v1", "v2", "v3", "v4"}, 10); err != nil {
		t.Fatal(err)
	}
	if err := d.RememberYouTubePending(ctx, "UUb", []string{"v1"}, 10); err != nil {
		t.Fatal(err)
	}
	if err := d.HandOverYouTubePending(ctx, "UUa", []string{"v1", "v2"}, 20); err != nil {
		t.Fatal(err)
	}
	if err := d.HandOverYouTubePending(ctx, "UUa", []string{"v3"}, 30); err != nil {
		t.Fatal(err)
	}
	if err := d.HandOverYouTubePending(ctx, "UUb", []string{"v1"}, 20); err != nil {
		t.Fatal(err)
	}
	if err := d.ConfirmYouTubePending(ctx, "UUa", 20); err != nil {
		t.Fatal(err)
	}
	// Handed over but not confirmed is still held, to be offered again.
	if got := mustPending(t, d, "UUa"); !slices.Equal(got, []string{"v3", "v4"}) {
		t.Errorf("UUa pending = %v, want [v3 v4]", got)
	}
	if got := mustPending(t, d, "UUb"); !slices.Equal(got, []string{"v1"}) {
		t.Errorf("UUb pending = %v, want [v1]", got)
	}
}

// The prune reaches every playlist, including one nobody polls any more.
func TestYouTubePendingPrunesAcrossPlaylists(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	for _, row := range []struct {
		source string
		id     string
		seen   int64
	}{
		{"UUa", "old-a", 1 * day}, {"UUa", "new-a", 10 * day},
		{"UUb", "old-b", 2 * day}, {"UUb", "new-b", 20 * day},
	} {
		if err := d.RememberYouTubePending(ctx, row.source, []string{row.id}, row.seen); err != nil {
			t.Fatal(err)
		}
	}
	n, err := d.PruneYouTubePending(ctx, 95*day)
	if err != nil {
		t.Fatal(err)
	}
	if n != 2 {
		t.Errorf("pruned %d rows, want 2", n)
	}
	if got := mustPending(t, d, "UUa"); !slices.Equal(got, []string{"new-a"}) {
		t.Errorf("UUa pending = %v, want [new-a]", got)
	}
	if got := mustPending(t, d, "UUb"); !slices.Equal(got, []string{"new-b"}) {
		t.Errorf("UUb pending = %v, want [new-b]", got)
	}
}

func TestYouTubePendingForgetsOnlyTheNamedPlaylistsIDs(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	if err := d.RememberYouTubePending(ctx, "UUa", []string{"v1", "v2", "v3"}, 10); err != nil {
		t.Fatal(err)
	}
	if err := d.RememberYouTubePending(ctx, "UUb", []string{"v1"}, 10); err != nil {
		t.Fatal(err)
	}
	if err := d.ForgetYouTubePending(ctx, "UUa", []string{"v1", "v3"}); err != nil {
		t.Fatal(err)
	}
	if got := mustPending(t, d, "UUa"); !slices.Equal(got, []string{"v2"}) {
		t.Errorf("UUa pending = %v, want [v2]", got)
	}
	// The same video under another playlist is that playlist's to forget.
	if got := mustPending(t, d, "UUb"); !slices.Equal(got, []string{"v1"}) {
		t.Errorf("UUb pending = %v, want [v1]", got)
	}
}
