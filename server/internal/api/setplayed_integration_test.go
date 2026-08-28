package api

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"sync"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
)

// TestUnmarkFinishedClearsTheFlags is the mark-finished undo.
//
// Marking a book finished writes a position at its end, which sets
// played and finished; the snack's Undo wrote the old position back and
// nothing cleared either flag, because nothing could - the checkpoint
// body carries positionMs and recordedAt only, and the completion rules
// are monotonic by construction. So a mis-tap put a book in the Finished
// shelf permanently and the hub's unfinished filter hid it forever.
func TestUnmarkFinishedClearsTheFlags(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	items := h.items(t, "")
	if len(items.Items) == 0 {
		t.Fatal("fixture library is empty")
	}
	pid := items.Items[0].Pid

	// Mark it played and finished the way a completion does, then undo.
	st := putPlayed(t, h, pid, map[string]any{"played": true, "finished": true})
	if !st.Played || !st.Finished || st.PlayCount == 0 {
		t.Fatalf("after marking = %+v, want played, finished, and a nonzero count", st)
	}

	// The undo clears both flags and the play the mis-tap added. A nil
	// playCount would keep the count, which is the offline-replay case,
	// not this one.
	zero := 0
	st = putPlayed(t, h, pid, map[string]any{
		"played": false, "finished": false, "playCount": zero,
	})
	if st.Played || st.Finished || st.PlayCount != 0 {
		t.Fatalf("after the undo = %+v, want cleared", st)
	}
	// And it stays cleared on the next read, which is the half that was
	// broken: a further position-0 write used to leave finished true.
	got := decode[PlayState](t, get(t, h.ts, "/api/v1/items/"+pid+"/play-state", h.token))
	if got.Played || got.Finished {
		t.Errorf("re-read state = %+v, want cleared", got)
	}
}

// TestSetPlayedRefusesIncoherentStates pins the three guards as
// invalid-request rather than as internal errors, since each of them is
// a client sending something it should not.
func TestSetPlayedRefusesIncoherentStates(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	items := h.items(t, "")
	if len(items.Items) == 0 {
		t.Fatal("fixture library is empty")
	}
	pid := items.Items[0].Pid

	for _, tc := range []struct {
		name string
		body map[string]any
	}{
		{"negative count", map[string]any{"played": true, "finished": false, "playCount": -1}},
		{"finished but unplayed", map[string]any{"played": false, "finished": true}},
		{"played with a zero count", map[string]any{"played": true, "finished": false, "playCount": 0}},
		{"negative position", map[string]any{"played": false, "finished": false, "positionMs": -1}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			resp := h.putJSON(t, "/api/v1/items/"+pid+"/played", tc.body)
			wantStatus(t, resp, 400, tc.name)
		})
	}
}

func putPlayed(t *testing.T, h *harness, pid string, body map[string]any) PlayState {
	t.Helper()
	resp := h.putJSON(t, "/api/v1/items/"+pid+"/played", body)
	if resp.StatusCode != 200 {
		t.Fatalf("setPlayed status = %d", resp.StatusCode)
	}
	return decode[PlayState](t, resp)
}

// bookForPlayedRaces scans the multi-part audiobook fixture and returns
// its summary. Spoken word is the medium the completion rules derive on,
// so it is the one where a checkpoint and an undo can contradict.
func bookForPlayedRaces(t *testing.T, h *harness) ItemSummary {
	t.Helper()
	if _, err := fixtures.GenerateBook(h.library); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	books := h.items(t, "?mediaType=audiobook")
	if len(books.Items) != 1 {
		t.Fatalf("audiobooks = %d, want 1", len(books.Items))
	}
	if books.Items[0].DurationMs <= 0 {
		t.Fatal("the book fixture has no duration; the completion rules never fire")
	}
	return books.Items[0]
}

// putFromGoroutine is putJSON without the t.Fatal, for the racing halves
// of the tests below: a Fatal off the test goroutine does not fail the
// test it was written for.
func putFromGoroutine(h *harness, method, path string, body any) (int, error) {
	raw, err := json.Marshal(body)
	if err != nil {
		return 0, err
	}
	req, err := http.NewRequest(method, h.ts.URL+path, bytes.NewReader(raw))
	if err != nil {
		return 0, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+h.token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()
	_, _ = io.Copy(io.Discard, resp.Body)
	return resp.StatusCode, nil
}

// TestUndoRacesACompletionCheckpoint is the bug the atomic undo exists
// for, run as a race.
//
// The undo used to be two writes - the position back, then the flags
// beside it - and an end-of-book checkpoint from another device landing
// between them was refused its finished mark, because `played` still
// stood when the crossing was evaluated; the flags clear then landed
// last, leaving the book at 100 percent, unfinished, nothing counted.
// That state is neither of the two sequential outcomes, which is what
// makes it a bug rather than a race the user could have caused.
//
// With position and flags in one write, serialized against the
// checkpoint's own read-decide-write, every outcome is one of the two.
func TestUndoRacesACompletionCheckpoint(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	book := bookForPlayedRaces(t, h)
	end := book.DurationMs
	resume := end / 10

	for i := 0; i < 200; i++ {
		putPlayed(t, h, book.Pid, map[string]any{
			"played": false, "finished": false, "playCount": 0, "positionMs": resume,
		})

		start := make(chan struct{})
		var wg sync.WaitGroup
		codes := [2]int{}
		errs := [2]error{}
		wg.Add(2)
		go func() {
			defer wg.Done()
			<-start
			codes[0], errs[0] = putFromGoroutine(h, "PUT",
				"/api/v1/items/"+book.Pid+"/play-state",
				map[string]any{"positionMs": end})
		}()
		go func() {
			defer wg.Done()
			<-start
			codes[1], errs[1] = putFromGoroutine(h, "PUT",
				"/api/v1/items/"+book.Pid+"/played",
				map[string]any{
					"played": false, "finished": false, "playCount": 0,
					"positionMs": resume,
				})
		}()
		close(start)
		wg.Wait()
		for j, err := range errs {
			if err != nil {
				t.Fatalf("round %d writer %d: %v", i, j, err)
			}
			if codes[j] != 200 && codes[j] != 204 {
				t.Fatalf("round %d writer %d status = %d", i, j, codes[j])
			}
		}

		st := decode[PlayState](t, get(t, h.ts, "/api/v1/items/"+book.Pid+"/play-state", h.token))
		undoLast := st.PositionMs == resume && !st.Played && !st.Finished && st.PlayCount == 0
		checkpointLast := st.PositionMs == end && st.Played && st.Finished && st.PlayCount == 1
		if !undoLast && !checkpointLast {
			t.Fatalf("round %d settled on neither sequential outcome: %+v "+
				"(want position %d cleared, or position %d played+finished once)",
				i, st, resume, end)
		}
	}
}

// TestUndoDoesNotRederiveCompletion pins the suppression: the position
// an undo restores is being put back, not reached, so the spoken-word
// rules must not read it and re-mark what the undo just cleared. A book
// restored to a past-threshold position is the case that would.
func TestUndoDoesNotRederiveCompletion(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	book := bookForPlayedRaces(t, h)

	// Reach the end the way a listener does, so the mark is the
	// completion rules' own rather than one this test wrote.
	wantStatus(t, h.putJSON(t, "/api/v1/items/"+book.Pid+"/play-state",
		map[string]any{"positionMs": book.DurationMs}), 204, "checkpoint at the end")
	st := decode[PlayState](t, get(t, h.ts, "/api/v1/items/"+book.Pid+"/play-state", h.token))
	if !st.Played || !st.Finished {
		t.Fatalf("the end-of-book checkpoint did not mark: %+v", st)
	}

	st = putPlayed(t, h, book.Pid, map[string]any{
		"played": false, "finished": false, "playCount": 0,
		"positionMs": book.DurationMs,
	})
	if st.Played || st.Finished || st.PlayCount != 0 {
		t.Fatalf("the undo re-marked from the position it restored: %+v", st)
	}
	if st.PositionMs != book.DurationMs {
		t.Fatalf("positionMs = %d, want the restored %d", st.PositionMs, book.DurationMs)
	}
	// And it stays cleared: nothing runs after the write to re-derive.
	got := decode[PlayState](t, get(t, h.ts, "/api/v1/items/"+book.Pid+"/play-state", h.token))
	if got.Played || got.Finished {
		t.Errorf("re-read state = %+v, want cleared", got)
	}
}

// TestUndoRacesAListenIngest covers the other decide-act on the same
// state: a listen report reads the stored position, derives the crossing
// from it, and marks. Interleaved with an undo it could mark from a
// position the undo is about to replace, or have its mark cleared by
// flags written from a state read before it.
func TestUndoRacesAListenIngest(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	book := bookForPlayedRaces(t, h)
	end := book.DurationMs
	resume := end / 10

	for i := 0; i < 60; i++ {
		// The listen's crossing reads the stored position, so the book
		// starts at its end with the flags clear: exactly the state where
		// an ingest is due to mark.
		putPlayed(t, h, book.Pid, map[string]any{
			"played": false, "finished": false, "playCount": 0, "positionMs": end,
		})

		start := make(chan struct{})
		var wg sync.WaitGroup
		codes := [2]int{}
		errs := [2]error{}
		wg.Add(2)
		go func() {
			defer wg.Done()
			<-start
			codes[0], errs[0] = putFromGoroutine(h, "POST", "/api/v1/listens",
				map[string]any{"sessions": []map[string]any{{
					"sessionId": fmt.Sprintf("undo-race-%d", i),
					"pid":       book.Pid,
					"startedAt": time.Now().UTC().Format(time.RFC3339),
					"msPlayed":  end,
					"finished":  true,
				}}})
		}()
		go func() {
			defer wg.Done()
			<-start
			codes[1], errs[1] = putFromGoroutine(h, "PUT",
				"/api/v1/items/"+book.Pid+"/played",
				map[string]any{
					"played": false, "finished": false, "playCount": 0,
					"positionMs": resume,
				})
		}()
		close(start)
		wg.Wait()
		for j, err := range errs {
			if err != nil {
				t.Fatalf("round %d writer %d: %v", i, j, err)
			}
			if codes[j] != 200 && codes[j] != 204 {
				t.Fatalf("round %d writer %d status = %d", i, j, codes[j])
			}
		}

		st := decode[PlayState](t, get(t, h.ts, "/api/v1/items/"+book.Pid+"/play-state", h.token))
		// One outcome either way, and only one, because the ingest
		// writes no position of its own. Ingest first: it marks from the
		// end position, and the undo then clears the mark and puts the
		// position back. Undo first: the ingest's own read sees the
		// restored position, which is short of the threshold, so it
		// marks nothing. So the flags and the position always agree, and
		// the failure this catches is the mark landing beside the undo's
		// position - which is exactly the torn state.
		if st.PositionMs != resume || st.Played || st.Finished || st.PlayCount != 0 {
			t.Fatalf("round %d = %+v, want position %d with the flags cleared", i, st, resume)
		}
	}
}

// TestUndoRacesAReplayedCheckpoint covers the checkpoint's other
// read-decide-write: an offline replay reads the stored position stamp,
// decides on the strength of it, and then rewrites it.
//
// Both writers here want the same slot. Sequentially there is only one
// outcome whichever runs first: the replay running first applies and is
// then undone, and the replay running second reads the undo's newer
// stamp and is dropped as stale. Deciding outside the stripe produced a
// third - the replay reading a pre-undo stamp, blocking, and then
// landing its end position, its older stamp, and a fresh mark on top of
// an undo that had already finished.
func TestUndoRacesAReplayedCheckpoint(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	book := bookForPlayedRaces(t, h)
	end := book.DurationMs
	resume := end / 10

	for i := 0; i < 120; i++ {
		putPlayed(t, h, book.Pid, map[string]any{
			"played": false, "finished": false, "playCount": 0, "positionMs": resume,
		})
		// Newer than the stamp the reset just wrote, so the replay is
		// due to apply when it reads first, and stale when it reads
		// after the undo's own stamp.
		recordedAt := time.Now().UTC().Format(time.RFC3339Nano)

		start := make(chan struct{})
		var wg sync.WaitGroup
		codes := [2]int{}
		errs := [2]error{}
		wg.Add(2)
		go func() {
			defer wg.Done()
			<-start
			codes[0], errs[0] = putFromGoroutine(h, "PUT",
				"/api/v1/items/"+book.Pid+"/play-state",
				map[string]any{"positionMs": end, "recordedAt": recordedAt})
		}()
		go func() {
			defer wg.Done()
			<-start
			codes[1], errs[1] = putFromGoroutine(h, "PUT",
				"/api/v1/items/"+book.Pid+"/played",
				map[string]any{
					"played": false, "finished": false, "playCount": 0,
					"positionMs": resume,
				})
		}()
		close(start)
		wg.Wait()
		for j, err := range errs {
			if err != nil {
				t.Fatalf("round %d writer %d: %v", i, j, err)
			}
			if codes[j] != 200 && codes[j] != 204 {
				t.Fatalf("round %d writer %d status = %d", i, j, codes[j])
			}
		}

		st := decode[PlayState](t, get(t, h.ts, "/api/v1/items/"+book.Pid+"/play-state", h.token))
		if st.PositionMs != resume || st.Played || st.Finished || st.PlayCount != 0 {
			t.Fatalf("round %d = %+v, want position %d with the flags cleared: "+
				"the replay either loses to the undo or is undone by it",
				i, st, resume)
		}
	}
}

// TestSetPlayedRefusesAReplayedPosition pins the one combination the
// position field does not take. It applies unconditionally and stamps
// at server-now, which is only honest for a live write; a queued
// offline position belongs on the checkpoint surface, which reconciles
// it per medium rather than applying it blindly.
func TestSetPlayedRefusesAReplayedPosition(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	pid := h.items(t, "").Items[0].Pid

	resp := h.putJSON(t, "/api/v1/items/"+pid+"/played", map[string]any{
		"played": false, "finished": false, "positionMs": 1000,
		"recordedAt": time.Now().UTC().Format(time.RFC3339),
	})
	wantStatus(t, resp, 400, "a position with a recorded time")

	// Either alone is fine.
	resp = h.putJSON(t, "/api/v1/items/"+pid+"/played", map[string]any{
		"played": false, "finished": false, "positionMs": 1000,
	})
	wantStatus(t, resp, 200, "a live position")
	resp = h.putJSON(t, "/api/v1/items/"+pid+"/played", map[string]any{
		"played": false, "finished": false,
		"recordedAt": time.Now().UTC().Format(time.RFC3339),
	})
	wantStatus(t, resp, 200, "a replayed flag change")
}

// TestFlagsOnlyWriteRacesACheckpointMark is why the stripe is taken for
// a flags-only write too.
//
// The checkpoint's crossing reads the played flag and marks on the
// strength of what it read - one mark per listen-through, so a played
// item is owed none. A direct flag write landing between that read and
// its mark counts the same listen twice: whichever order the two run
// in, exactly one of them counts a play, and the interleaving that
// counts two is reachable from neither.
func TestFlagsOnlyWriteRacesACheckpointMark(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	book := bookForPlayedRaces(t, h)
	end := book.DurationMs

	for i := 0; i < 120; i++ {
		// At the end with the flags clear, so the checkpoint below is
		// due a mark rather than a no-op.
		putPlayed(t, h, book.Pid, map[string]any{
			"played": false, "finished": false, "playCount": 0, "positionMs": end,
		})

		start := make(chan struct{})
		var wg sync.WaitGroup
		codes := [2]int{}
		errs := [2]error{}
		wg.Add(2)
		go func() {
			defer wg.Done()
			<-start
			codes[0], errs[0] = putFromGoroutine(h, "PUT",
				"/api/v1/items/"+book.Pid+"/play-state",
				map[string]any{"positionMs": end})
		}()
		go func() {
			defer wg.Done()
			<-start
			codes[1], errs[1] = putFromGoroutine(h, "PUT",
				"/api/v1/items/"+book.Pid+"/played",
				map[string]any{"played": true, "finished": true, "playCount": 1})
		}()
		close(start)
		wg.Wait()
		for j, err := range errs {
			if err != nil {
				t.Fatalf("round %d writer %d: %v", i, j, err)
			}
			if codes[j] != 200 && codes[j] != 204 {
				t.Fatalf("round %d writer %d status = %d", i, j, codes[j])
			}
		}

		st := decode[PlayState](t, get(t, h.ts, "/api/v1/items/"+book.Pid+"/play-state", h.token))
		if !st.Played || !st.Finished || st.PlayCount != 1 {
			t.Fatalf("round %d = %+v, want played and finished counted once", i, st)
		}
	}
}
