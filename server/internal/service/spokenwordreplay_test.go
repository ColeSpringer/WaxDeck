package service

import (
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"
)

// TestReplayedCrossingsDoNotCountPerCheckpoint pins the interaction
// between the recorded-time mark and the once-per-listen-through
// dedupe.
//
// The dedupe reads the stored played flag. The catalog only sets that
// flag when the mark's recorded time is not older than the last flag
// change, but it increments the play count either way - so a listener
// who un-marks a book on one device, then flushes an offline queue of
// earlier checkpoints past the finished bar, would have every one of
// them count a play while the item never reads played. There is no
// session id bounding this path, so the count would climb per
// checkpoint.
func TestReplayedCrossingsDoNotCountPerCheckpoint(t *testing.T) {
	t.Parallel()
	ctx, f := newMigrateFixture(t)
	svc, uc := f.svc, f.uc
	book := f.itemPID(t, ctx, model.KindBook, "The Fixture Book")

	it, err := svc.getItem(ctx, book)
	if err != nil {
		t.Fatal(err)
	}
	if it.DurationMS <= 0 {
		t.Fatalf("the book fixture reports no duration: %+v", it)
	}
	// Past the finished bar, so every checkpoint below crosses.
	past := it.DurationMS

	// Marked played by hand and then un-marked: the flags clear, the
	// count is kept, and the flag change is stamped at now. Deliberately
	// no live checkpoint - one would leave a position stamp newer than
	// the replays below, and the replay guard would drop them before
	// they ever reached a crossing.
	if _, err := svc.SetPlayed(ctx, uc, book, true, true, nil, nil, nil); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.SetPlayed(ctx, uc, book, false, false, nil, nil, nil); err != nil {
		t.Fatal(err)
	}
	st := f.playState(t, ctx, book)
	if st.Played {
		t.Fatalf("the un-mark did not clear played: %+v", st)
	}
	before := st.PlayCount

	// Now an offline queue flushes checkpoints recorded before the
	// un-mark, each past the bar. The un-mark is the newer decision, so
	// none of them may count.
	recorded := time.Now().Add(-2 * time.Hour)
	for i := range 4 {
		at := recorded.Add(time.Duration(i) * time.Minute)
		if _, err := svc.Checkpoint(ctx, uc, book, past, &at); err != nil {
			t.Fatalf("replayed checkpoint %d: %v", i, err)
		}
	}
	st = f.playState(t, ctx, book)
	if st.PlayCount != before {
		t.Fatalf("play count = %d after four replayed crossings, want %d: "+
			"the catalog keeps the cleared flag and counts anyway, so the "+
			"crossing has to defer to the later un-mark", st.PlayCount, before)
	}
	if st.Played {
		t.Fatalf("a replayed crossing resurrected the flag the listener cleared: %+v", st)
	}
}
