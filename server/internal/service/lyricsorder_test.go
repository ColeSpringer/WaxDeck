package service

import (
	"context"
	"fmt"
	"slices"
	"strings"
	"testing"

	"github.com/colespringer/waxbin/enrich"
	"github.com/colespringer/waxbin/model"
)

// storedLines is synced lines as a bridge provider or the catalog's IPC
// set_lyrics hands them over: in arrival order, half of them at one time,
// between the others. A hundred is well past the few lines an unstable
// sort keeps in order, so only a stable one keeps equal times as stored.
func storedLines() []model.SyncedLine {
	lines := make([]model.SyncedLine, 100)
	for i := range lines {
		lines[i] = model.SyncedLine{TimeMS: []int64{3000, 1000, 2000, 1000}[i%4], Text: fmt.Sprintf("line %d", i)}
	}
	return lines
}

// timeOrdered is lines by time, equal times in stored order, built
// without a sort.
func timeOrdered(lines []model.SyncedLine) []model.SyncedLine {
	var out []model.SyncedLine
	for _, at := range []int64{1000, 2000, 3000} {
		for _, l := range lines {
			if l.TimeMS == at {
				out = append(out, l)
			}
		}
	}
	return out
}

// storeOutOfOrderLyrics stores storedLines on a track. It answers the
// track's catalog and API pids.
func storeOutOfOrderLyrics(t *testing.T) (context.Context, *Library, *UserCtx, model.PID, string) {
	t.Helper()
	ctx, svc, uc, track := openLyricsFixture(t)
	err := svc.lib.SetLyrics(ctx, track, &model.Lyrics{
		Source: model.SourceEnrichment, Provider: "remote", Synced: storedLines(),
	}, model.LockUnchanged, false)
	if err != nil {
		t.Fatal(err)
	}
	return ctx, svc, uc, track, apiPID(PrefixTrack, track)
}

// Synced lines read back in time order whatever order they were stored in,
// and lines at one time keep their stored order.
func TestItemLyricsServesSyncedLinesInTimeOrder(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _, pid := storeOutOfOrderLyrics(t)
	got, err := svc.Reads.ItemLyrics(ctx, uc, pid)
	if err != nil {
		t.Fatal(err)
	}
	var want []SyncedLine
	for _, l := range timeOrdered(storedLines()) {
		want = append(want, SyncedLine{l.TimeMS, l.Text})
	}
	if !slices.Equal(got.Synced, want) {
		t.Fatalf("synced = %v, want %v", got.Synced, want)
	}
}

// The editor's working text of synced lyrics is in time order too.
func TestItemMetadataRendersSyncedLyricsInTimeOrder(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _, pid := storeOutOfOrderLyrics(t)
	md, err := svc.Editor.ItemMetadataFor(ctx, uc, pid)
	if err != nil {
		t.Fatal(err)
	}
	var lrc []string
	for _, l := range timeOrdered(storedLines()) {
		lrc = append(lrc, fmt.Sprintf("[00:%02d.000] %s", l.TimeMS/1000, l.Text))
	}
	if want := strings.Join(lrc, "\n"); md.Lyrics == nil || md.Lyrics.LRC != want {
		t.Fatalf("lyrics = %+v, want the lrc %q", md.Lyrics, want)
	}
}

// unsortedLyricist answers with synced lines in arrival order, as a bridge
// provider does.
type unsortedLyricist struct{}

func (unsortedLyricist) Name() string                    { return "unsorted" }
func (unsortedLyricist) Capabilities() enrich.Capability { return enrich.CapLyrics }
func (unsortedLyricist) Enrich(context.Context, enrich.Request) (*enrich.Candidate, error) {
	return &enrich.Candidate{Lyrics: &model.Lyrics{Synced: storedLines()}}, nil
}

// A provider's synced lines are proposed in time order too, equal times in
// the order the provider sent them, so the preview reads as the stored
// lyrics will once committed.
func TestAnEnrichmentPreviewProposesSyncedLyricsInTimeOrder(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := openLyricsFixture(t, unsortedLyricist{})
	pid, _ := fixtureTrackPID(t, ctx, svc, uc, "Amber Waves")
	pre, err := svc.Enrichment.EnrichPreviewFor(ctx, uc, pid, []string{enrichWantLyrics})
	if err != nil {
		t.Fatal(err)
	}
	var lrc []string
	for _, l := range timeOrdered(storedLines()) {
		lrc = append(lrc, fmt.Sprintf("[00:%02d.000] %s", l.TimeMS/1000, l.Text))
	}
	if len(pre.Fields) != 1 || pre.Fields[0].Name != "lyrics" || pre.Fields[0].Proposed != strings.Join(lrc, "\n") {
		t.Fatalf("preview = %+v (skipped %v), want the lyrics in time order", pre.Fields, pre.Skipped)
	}
}
