package service

import (
	"context"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// A star or rating write emits a sync event only when it changed
// something. Safe because the delta builder is a pure projection of
// stored events: nothing treats one as a heartbeat.

// eventsAfter returns the caller's server events appended after id.
func eventsAfter(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, id int64) []wdb.Event {
	t.Helper()
	evs, _, err := svc.db.EventsSince(ctx, uc.ID, id, 1000)
	if err != nil {
		t.Fatalf("reading events: %v", err)
	}
	return evs
}

// eventTail is the id of the caller's newest server event, 0 when the
// stream is empty.
func eventTail(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx) int64 {
	t.Helper()
	evs := eventsAfter(t, ctx, svc, uc, 0)
	if len(evs) == 0 {
		return 0
	}
	return evs[len(evs)-1].ID
}

func TestStarEmitsOnlyOnChange(t *testing.T) {
	ctx, svc, uc := newCatalogFixture(t)
	pid, _ := fixtureTrackPID(t, ctx, svc, uc, "Amber Waves")

	tail := eventTail(t, ctx, svc, uc)
	if st, err := svc.SetStar(ctx, uc, pid, true, nil); err != nil || !st.Starred {
		t.Fatalf("star: %+v (%v), want starred", st, err)
	}
	evs := eventsAfter(t, ctx, svc, uc, tail)
	if len(evs) != 1 || evs[0].Kind != eventPlayState {
		t.Fatalf("a real flip emitted %+v, want one play-state event", evs)
	}

	// The same value again: no delta, so no event.
	tail = evs[0].ID
	st, err := svc.SetStar(ctx, uc, pid, true, nil)
	if err != nil || !st.Starred {
		t.Fatalf("re-star: %+v (%v), want starred", st, err)
	}
	if evs := eventsAfter(t, ctx, svc, uc, tail); len(evs) != 0 {
		t.Fatalf("a value-identical re-star emitted %+v, want nothing", evs)
	}

	// Unstarring is a change; unstarring twice is not.
	if _, err := svc.SetStar(ctx, uc, pid, false, nil); err != nil {
		t.Fatalf("unstar: %v", err)
	}
	if evs := eventsAfter(t, ctx, svc, uc, tail); len(evs) != 1 {
		t.Fatalf("the unstar emitted %+v, want one event", evs)
	}
	tail = eventTail(t, ctx, svc, uc)
	if _, err := svc.SetStar(ctx, uc, pid, false, nil); err != nil {
		t.Fatalf("second unstar: %v", err)
	}
	if evs := eventsAfter(t, ctx, svc, uc, tail); len(evs) != 0 {
		t.Fatalf("unstarring an unstarred item emitted %+v, want nothing", evs)
	}
}

func TestRatingEmitsOnlyOnChange(t *testing.T) {
	ctx, svc, uc := newCatalogFixture(t)
	pid, _ := fixtureTrackPID(t, ctx, svc, uc, "Basalt Steps")

	tail := eventTail(t, ctx, svc, uc)
	forty := 40
	if _, err := svc.SetRating(ctx, uc, pid, &forty, nil); err != nil {
		t.Fatalf("rating: %v", err)
	}
	if evs := eventsAfter(t, ctx, svc, uc, tail); len(evs) != 1 || evs[0].Kind != eventPlayState {
		t.Fatalf("a real rating emitted %+v, want one play-state event", evs)
	}

	tail = eventTail(t, ctx, svc, uc)
	same := 40
	if st, err := svc.SetRating(ctx, uc, pid, &same, nil); err != nil || st.Rating == nil || *st.Rating != 40 {
		t.Fatalf("re-rating: %+v (%v)", st, err)
	}
	if evs := eventsAfter(t, ctx, svc, uc, tail); len(evs) != 0 {
		t.Fatalf("a value-identical re-rating emitted %+v, want nothing", evs)
	}
}

// The case suppression has to get right: the catalog drops the stale
// replay, so no device is told anything, and the replaying client learns
// the truth from the response body.
func TestStaleReplayEmitsNothingButReportsTruth(t *testing.T) {
	ctx, svc, uc := newCatalogFixture(t)
	pid, catalogPID := fixtureTrackPID(t, ctx, svc, uc, "Cobalt Sky")

	old := time.Now().Add(-2 * time.Hour)
	if _, err := svc.SetStar(ctx, uc, pid, true, &old); err != nil {
		t.Fatalf("first replay: %v", err)
	}
	if _, err := svc.lib.Playback().SetStar(ctx, model.PID(uc.CatalogPID), catalogPID, false, nil); err != nil {
		t.Fatalf("out-of-band unstar: %v", err)
	}

	tail := eventTail(t, ctx, svc, uc)
	stale := time.Now().Add(-time.Hour)
	st, err := svc.SetStar(ctx, uc, pid, true, &stale)
	if err != nil {
		t.Fatalf("stale replay: %v", err)
	}
	if st.Starred {
		t.Fatal("the stale replay resurrected the star")
	}
	if evs := eventsAfter(t, ctx, svc, uc, tail); len(evs) != 0 {
		t.Fatalf("a dropped replay emitted %+v, want nothing", evs)
	}
}

func TestEntityStarEmitsOnlyOnChange(t *testing.T) {
	ctx, svc, uc, albumPID, _, _ := entityFixture(t)

	tail := eventTail(t, ctx, svc, uc)
	if st, err := svc.SetEntityStar(ctx, uc, albumPID, true, nil); err != nil || !st.Starred {
		t.Fatalf("star: %+v (%v), want starred", st, err)
	}
	evs := eventsAfter(t, ctx, svc, uc, tail)
	if len(evs) != 1 || evs[0].Kind != eventEntityState {
		t.Fatalf("a real flip emitted %+v, want one entity-state event", evs)
	}

	tail = evs[0].ID
	if st, err := svc.SetEntityStar(ctx, uc, albumPID, true, nil); err != nil || !st.Starred {
		t.Fatalf("re-star: %+v (%v), want starred", st, err)
	}
	if evs := eventsAfter(t, ctx, svc, uc, tail); len(evs) != 0 {
		t.Fatalf("a value-identical entity re-star emitted %+v, want nothing", evs)
	}

	sixty := 60
	if _, err := svc.SetEntityRating(ctx, uc, albumPID, &sixty, nil); err != nil {
		t.Fatalf("rating: %v", err)
	}
	tail = eventTail(t, ctx, svc, uc)
	same := 60
	if _, err := svc.SetEntityRating(ctx, uc, albumPID, &same, nil); err != nil {
		t.Fatalf("re-rating: %v", err)
	}
	if evs := eventsAfter(t, ctx, svc, uc, tail); len(evs) != 0 {
		t.Fatalf("a value-identical entity re-rating emitted %+v, want nothing", evs)
	}
}

// The switch in the delta builder is the whole mechanism: a kind missing
// from it is silently dropped, and nothing else would notice.
func TestAnnouncementMarkersReachTheDelta(t *testing.T) {
	ctx, svc, uc := newCatalogFixture(t)

	since, err := svc.MintServerCursor(ctx)
	if err != nil {
		t.Fatalf("minting a cursor: %v", err)
	}

	const show = "pc-01JZX5N8QW3F4V9T2B7KD3M9R6"
	svc.emitUserEvent(ctx, uc.ID, eventFeedDisabled, show)
	svc.emitUserEvent(ctx, uc.ID, eventImportCompleted, "rv-01JZX5N8QW3F4V9T2B7KD3M9R6")

	delta, err := svc.SyncServerDelta(ctx, uc, since, 100)
	if err != nil {
		t.Fatalf("reading the delta: %v", err)
	}
	if len(delta.Events) != 2 {
		t.Fatalf("events = %+v, want both announcements", delta.Events)
	}
	if delta.Events[0].Kind != eventFeedDisabled || delta.Events[0].PID != show {
		t.Fatalf("feed-disabled event = %+v, want the api show pid", delta.Events[0])
	}
	if delta.Events[1].Kind != eventImportCompleted {
		t.Fatalf("second event = %+v, want import-completed", delta.Events[1])
	}
	// A marker hydrates nothing.
	if delta.Events[0].Subscription != nil || delta.Events[0].PlayState != nil {
		t.Fatalf("a marker carried a payload: %+v", delta.Events[0])
	}
}
