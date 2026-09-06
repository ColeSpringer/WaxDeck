package service

import (
	"context"
	"testing"
	"time"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// strandListen claims a listen row directly, the way ingest does, and
// leaves its outcome unwritten - the state a crash between the mark
// and the statement recording it produces.
func strandListen(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, sessionID, itemPID string, at time.Time) {
	t.Helper()
	ins, err := svc.db.InsertListens(ctx, []wdb.ListenSession{{
		UserID:    uc.ID,
		SessionID: sessionID,
		ItemPID:   itemPID,
		MediaType: "music",
		StartedAt: at,
		MsPlayed:  2000,
		Finished:  true,
		Source:    "live",
	}})
	if err != nil || !ins[0] {
		t.Fatalf("claiming %s = (%v, %v)", sessionID, ins, err)
	}
}

// sweepNow runs a pass with the arrival grace bypassed: every claim on
// the log counts as stranded. The grace itself is what
// TestSweepListenMarksLeavesFreshClaimsAlone covers.
func sweepNow(t *testing.T, ctx context.Context, svc *Library) ListenMarkSweep {
	t.Helper()
	rep, err := svc.sweepListenMarks(ctx, time.Now().Add(time.Minute).UnixNano())
	if err != nil {
		t.Fatalf("sweepListenMarks: %v", err)
	}
	return rep
}

// TestSweepListenMarksCountsAStrandedClaimOnce pins the safety net: a
// claim whose mark never landed is re-run at the session's own time,
// and the row it settles is not swept again.
func TestSweepListenMarksCountsAStrandedClaimOnce(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	pid, catalogPID := fixtureTrackPID(t, ctx, svc, uc, "Amber Waves")

	at := time.Now().UTC().Add(-time.Hour).Truncate(time.Second)
	strandListen(t, ctx, svc, uc, "stranded-1", string(catalogPID), at)

	rep := sweepNow(t, ctx, svc)
	if rep.Scanned != 1 || rep.Marked != 1 {
		t.Fatalf("sweep = %+v, want one row scanned and marked", rep)
	}
	st, err := svc.PlayState(ctx, uc, pid)
	if err != nil {
		t.Fatal(err)
	}
	if st.PlayCount != 1 || !st.Played {
		t.Fatalf("state = %+v, want the stranded play counted once", st)
	}
	wantAt := at.Add(2 * time.Second)
	if diff := st.LastPlayedAt.Sub(wantAt); diff < -time.Second || diff > time.Second {
		t.Fatalf("lastPlayedAt = %v, want the session's own end %v", st.LastPlayedAt, wantAt)
	}

	// And only once: the recorded outcome takes the row out of reach.
	rep = sweepNow(t, ctx, svc)
	if rep.Scanned != 0 {
		t.Fatalf("second sweep = %+v, want nothing left to do", rep)
	}
	st, err = svc.PlayState(ctx, uc, pid)
	if err != nil {
		t.Fatal(err)
	}
	if st.PlayCount != 1 {
		t.Fatalf("play count = %d after a second sweep, want 1", st.PlayCount)
	}
}

// A claim that has only just arrived belongs to a batch that may still
// be marking its rows; sweeping it would mark a listen a second time
// for no reason at all. The play's own date is a year ago, which is
// what a history import or an offline queue looks like: the grace has
// to read arrival, or exactly those rows go unprotected.
func TestSweepListenMarksLeavesFreshClaimsAlone(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	pid, catalogPID := fixtureTrackPID(t, ctx, svc, uc, "Basalt Steps")
	strandListen(t, ctx, svc, uc, "fresh-1", string(catalogPID),
		time.Now().UTC().AddDate(-1, 0, 0))

	rep, err := svc.SweepListenMarks(ctx)
	if err != nil {
		t.Fatalf("SweepListenMarks: %v", err)
	}
	if rep.Scanned != 0 {
		t.Fatalf("sweep = %+v, want the just-arrived claim left alone", rep)
	}
	st, err := svc.PlayState(ctx, uc, pid)
	if err != nil {
		t.Fatal(err)
	}
	if st.PlayCount != 0 {
		t.Fatalf("play count = %d, want the fresh claim uncounted", st.PlayCount)
	}
}

// A row whose mark can never apply settles rather than being retried
// forever: the item is gone, and the listen survives it as data.
func TestSweepListenMarksSettlesAVanishedItem(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	strandListen(t, ctx, svc, uc, "gone-1", "01JZX5N8QW3F4V9T2B7KDEXAMPLE",
		time.Now().UTC().Add(-time.Hour))

	rep := sweepNow(t, ctx, svc)
	if rep.Scanned != 1 || rep.Marked != 0 || rep.Settled != 1 {
		t.Fatalf("sweep = %+v, want the row settled unmarked", rep)
	}
	if rep = sweepNow(t, ctx, svc); rep.Scanned != 0 {
		t.Fatalf("second sweep = %+v, want nothing left", rep)
	}
}

// An account that is gone settles its rows; one the sweep could not
// read leaves them standing. Collapsing the two - which is what
// userCtxByID does, since it answers not-found for every failure -
// would write the play off permanently on a busy database, which is
// the loss this whole safety net exists to prevent.
func TestSweepListenMarksKeepsClaimsWhenAnAccountCannotBeRead(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	_, catalogPID := fixtureTrackPID(t, ctx, svc, uc, "Delta Groove")
	strandListen(t, ctx, svc, uc, "unreadable-1", string(catalogPID),
		time.Now().UTC().Add(-time.Hour))

	// A cancelled context is a read failure, not a missing account.
	dead, cancel := context.WithCancel(ctx)
	cancel()
	if _, err := svc.sweepListenMarks(dead, time.Now().Add(time.Minute).UnixNano()); err == nil {
		// The page read itself may fail first, which is also fine: the
		// claim has to survive either way.
		t.Log("the pending read answered under a cancelled context")
	}

	// The claim is still there for a healthy pass, and it marks.
	rep := sweepNow(t, ctx, svc)
	if rep.Scanned != 1 || rep.Marked != 1 {
		t.Fatalf("sweep = %+v, want the claim still standing and then marked", rep)
	}
}

// The ordinary ingest path records its own outcomes, so nothing it
// wrote ever reaches the sweep - the crossed listen and the one that
// did not cross alike.
func TestIngestListensLeavesNothingForTheSweep(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	crossed, _ := fixtureTrackPID(t, ctx, svc, uc, "Cobalt Sky")
	short, _ := fixtureTrackPID(t, ctx, svc, uc, "Delta Groove")

	at := time.Now().UTC().Add(-time.Hour)
	res, err := svc.IngestListens(ctx, uc, []ListenSession{
		{SessionID: "ok-1", PID: crossed, StartedAt: at, MsPlayed: 3000, Finished: true},
		{SessionID: "ok-2", PID: short, StartedAt: at, MsPlayed: 10},
	})
	if err != nil || res.Accepted != 2 {
		t.Fatalf("ingest = %+v (%v), want two accepted", res, err)
	}
	if rep := sweepNow(t, ctx, svc); rep.Scanned != 0 {
		t.Fatalf("sweep = %+v, want ingest to have accounted for both rows", rep)
	}
}
