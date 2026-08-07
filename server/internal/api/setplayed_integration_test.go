package api

import (
	"testing"
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
