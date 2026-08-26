package db

import (
	"context"
	"errors"
	"testing"
	"time"
)

func testBinding(pid string, now int64) PlaylistSourceRow {
	return PlaylistSourceRow{
		PlaylistPID: pid, Source: "youtube", Live: true,
		URL: "https://youtube.example/playlist?list=PL1", IdentityKey: "youtube:PL1",
		SourceID: "PL1", Title: "Road Tapes", Mode: "mirror", IntervalHours: 6,
		CreatedAtNS: now, UpdatedAtNS: now,
	}
}

func TestPlaylistSourceBindingRoundTrip(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	now := time.Now().UnixNano()

	if _, err := d.PlaylistSourceFor(ctx, "pl-1"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("unbound playlist read: %v", err)
	}

	in := testBinding("pl-1", now)
	if err := d.PutPlaylistSource(ctx, in); err != nil {
		t.Fatal(err)
	}
	got, err := d.PlaylistSourceFor(ctx, "pl-1")
	if err != nil {
		t.Fatal(err)
	}
	if got != in {
		t.Fatalf("round trip: got %+v want %+v", got, in)
	}

	// A replace overwrites the settings whole and starts health over.
	if _, err := d.RecordPlaylistSyncFailure(ctx, "pl-1", "boom", now, 10); err != nil {
		t.Fatal(err)
	}
	in.Mode = "append"
	in.IntervalHours = 24
	if err := d.PutPlaylistSource(ctx, in); err != nil {
		t.Fatal(err)
	}
	got, err = d.PlaylistSourceFor(ctx, "pl-1")
	if err != nil {
		t.Fatal(err)
	}
	if got.Mode != "append" || got.IntervalHours != 24 {
		t.Fatalf("replace kept old settings: %+v", got)
	}
	if got.ConsecutiveFailures != 0 || got.LastError != "" {
		t.Fatalf("replace kept old health: %+v", got)
	}
}

func TestDeletePlaylistSourceKeepsTheSharedMap(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	now := time.Now().UnixNano()

	if err := d.PutPlaylistSource(ctx, testBinding("pl-1", now)); err != nil {
		t.Fatal(err)
	}
	if err := d.SetPlaylistSourceEntryState(ctx, "pl-1", "vid-a", PlaylistEntryAttached, now); err != nil {
		t.Fatal(err)
	}
	if err := d.PutPlaylistSourceMapPending(ctx, "youtube", "vid-a", "up-1", now); err != nil {
		t.Fatal(err)
	}

	if err := d.DeletePlaylistSource(ctx, "pl-1"); err != nil {
		t.Fatal(err)
	}
	if _, err := d.PlaylistSourceFor(ctx, "pl-1"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("binding survived delete: %v", err)
	}
	states, err := d.PlaylistSourceEntryStates(ctx, "pl-1")
	if err != nil {
		t.Fatal(err)
	}
	if len(states) != 0 {
		t.Fatalf("entry states survived delete: %v", states)
	}
	m, err := d.PlaylistSourceMapFor(ctx, "youtube", []string{"vid-a"})
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := m["vid-a"]; !ok {
		t.Fatal("shared map row went with the binding")
	}
}

func TestDuePlaylistSourcesHonorsIntervalDisabledAndLive(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	now := time.Now().UnixNano()
	hour := int64(time.Hour)

	put := func(pid string, mutate func(*PlaylistSourceRow)) {
		t.Helper()
		row := testBinding(pid, now)
		row.IntervalHours = 1
		mutate(&row)
		if err := d.PutPlaylistSource(ctx, row); err != nil {
			t.Fatal(err)
		}
	}
	put("pl-due", func(r *PlaylistSourceRow) { r.LastAttemptNS = now - 2*hour })
	put("pl-never-run", func(r *PlaylistSourceRow) {})
	put("pl-fresh", func(r *PlaylistSourceRow) { r.LastAttemptNS = now - hour/2 })
	put("pl-disabled", func(r *PlaylistSourceRow) {
		r.LastAttemptNS = now - 2*hour
		r.Disabled = true
	})
	put("pl-matched", func(r *PlaylistSourceRow) {
		r.Live = false
		r.Source = "spotify"
		r.IntervalHours = 0
	})

	due, err := d.DuePlaylistSources(ctx, now)
	if err != nil {
		t.Fatal(err)
	}
	got := map[string]bool{}
	for _, row := range due {
		got[row.PlaylistPID] = true
	}
	want := map[string]bool{"pl-due": true, "pl-never-run": true}
	if len(got) != len(want) || !got["pl-due"] || !got["pl-never-run"] {
		t.Fatalf("due set: got %v want %v", got, want)
	}
}

func TestPlaylistSyncFailureAccountingDisablesOnTheEdge(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	now := time.Now().UnixNano()

	if err := d.PutPlaylistSource(ctx, testBinding("pl-1", now)); err != nil {
		t.Fatal(err)
	}
	for i := 1; i <= 3; i++ {
		st, err := d.RecordPlaylistSyncFailure(ctx, "pl-1", "boom", now, 3)
		if err != nil {
			t.Fatal(err)
		}
		if st.ConsecutiveFailures != i {
			t.Fatalf("failure %d: counter %d", i, st.ConsecutiveFailures)
		}
		if wantDisabled := i >= 3; st.Disabled != wantDisabled {
			t.Fatalf("failure %d: disabled=%v", i, st.Disabled)
		}
		if st.LastError != "boom" {
			t.Fatalf("failure %d: lastError %q", i, st.LastError)
		}
	}

	// A success is the recovery path: counters reset, disable lifts,
	// and the run's counts land.
	counts := PlaylistSyncCounts{Added: 2, Removed: 1, Queued: 3, Unavailable: 1}
	if err := d.RecordPlaylistSyncSuccess(ctx, "pl-1", now+1, counts); err != nil {
		t.Fatal(err)
	}
	st, err := d.PlaylistSourceFor(ctx, "pl-1")
	if err != nil {
		t.Fatal(err)
	}
	if st.Disabled || st.ConsecutiveFailures != 0 || st.LastError != "" {
		t.Fatalf("success did not recover: %+v", st)
	}
	if st.LastCounts != counts {
		t.Fatalf("run counts: got %+v want %+v", st.LastCounts, counts)
	}
	if st.LastSyncedNS != now+1 || st.LastAttemptNS != now+1 {
		t.Fatalf("timestamps: %+v", st)
	}
}

func TestPlaylistSourceMapPendingCompleteAndHeal(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	now := time.Now().UnixNano()

	if err := d.PutPlaylistSourceMapPending(ctx, "youtube", "vid-a", "up-1", now); err != nil {
		t.Fatal(err)
	}
	// Completion keys on the upload row, not the entry: the settle path
	// knows nothing about sources.
	changed, err := d.CompletePlaylistSourceMap(ctx, "up-1", "tr-1", "ess-1", now+1)
	if err != nil {
		t.Fatal(err)
	}
	if !changed {
		t.Fatal("completion missed the pending row")
	}
	changed, err = d.CompletePlaylistSourceMap(ctx, "up-unrelated", "tr-9", "ess-9", now+1)
	if err != nil {
		t.Fatal(err)
	}
	if changed {
		t.Fatal("an unrelated upload completed a map row")
	}
	if changed, err = d.CompletePlaylistSourceMap(ctx, "", "tr-9", "ess-9", now+1); err != nil || changed {
		t.Fatalf("empty upload id must be a no-op: %v %v", changed, err)
	}

	m, err := d.PlaylistSourceMapFor(ctx, "youtube", []string{"vid-a", "vid-b"})
	if err != nil {
		t.Fatal(err)
	}
	if len(m) != 1 || m["vid-a"].ItemPID != "tr-1" || m["vid-a"].Essence != "ess-1" {
		t.Fatalf("map read: %+v", m)
	}

	// A re-download must not erase what the entry once resolved to.
	if err := d.PutPlaylistSourceMapPending(ctx, "youtube", "vid-a", "up-2", now+2); err != nil {
		t.Fatal(err)
	}
	m, err = d.PlaylistSourceMapFor(ctx, "youtube", []string{"vid-a"})
	if err != nil {
		t.Fatal(err)
	}
	if m["vid-a"].UploadID != "up-2" || m["vid-a"].ItemPID != "tr-1" {
		t.Fatalf("re-download clobbered the resolution: %+v", m["vid-a"])
	}

	// Self-heal rewrites the item; forgetting makes the entry new again.
	if err := d.SetPlaylistSourceMapItem(ctx, "youtube", "vid-a", "tr-2", "ess-1", now+3); err != nil {
		t.Fatal(err)
	}
	m, _ = d.PlaylistSourceMapFor(ctx, "youtube", []string{"vid-a"})
	if m["vid-a"].ItemPID != "tr-2" {
		t.Fatalf("self-heal: %+v", m["vid-a"])
	}
	if err := d.DeletePlaylistSourceMap(ctx, "youtube", "vid-a"); err != nil {
		t.Fatal(err)
	}
	m, _ = d.PlaylistSourceMapFor(ctx, "youtube", []string{"vid-a"})
	if len(m) != 0 {
		t.Fatalf("row survived delete: %+v", m)
	}
}

func TestPlaylistSourceEntryStates(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	now := time.Now().UnixNano()

	if err := d.SetPlaylistSourceEntryState(ctx, "pl-1", "vid-a", PlaylistEntryAttached, now); err != nil {
		t.Fatal(err)
	}
	if err := d.SetPlaylistSourceEntryState(ctx, "pl-1", "vid-b", PlaylistEntryAttached, now); err != nil {
		t.Fatal(err)
	}
	// The same entry under another playlist is independent state.
	if err := d.SetPlaylistSourceEntryState(ctx, "pl-2", "vid-a", PlaylistEntryTombstoned, now); err != nil {
		t.Fatal(err)
	}
	if err := d.SetPlaylistSourceEntryState(ctx, "pl-1", "vid-b", PlaylistEntryTombstoned, now+1); err != nil {
		t.Fatal(err)
	}
	states, err := d.PlaylistSourceEntryStates(ctx, "pl-1")
	if err != nil {
		t.Fatal(err)
	}
	if len(states) != 2 || states["vid-a"] != PlaylistEntryAttached || states["vid-b"] != PlaylistEntryTombstoned {
		t.Fatalf("states: %v", states)
	}

	if err := d.DeletePlaylistSourceEntryState(ctx, "pl-1", "vid-a"); err != nil {
		t.Fatal(err)
	}
	if err := d.ClearPlaylistSourceEntries(ctx, "pl-1"); err != nil {
		t.Fatal(err)
	}
	states, err = d.PlaylistSourceEntryStates(ctx, "pl-1")
	if err != nil {
		t.Fatal(err)
	}
	if len(states) != 0 {
		t.Fatalf("clear left rows: %v", states)
	}
	other, err := d.PlaylistSourceEntryStates(ctx, "pl-2")
	if err != nil {
		t.Fatal(err)
	}
	if other["vid-a"] != PlaylistEntryTombstoned {
		t.Fatalf("clear crossed playlists: %v", other)
	}
}
