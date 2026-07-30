package api

import (
	"context"
	"fmt"
	"math/rand/v2"
	"strings"
	"testing"
	"time"
)

// The sync model fuzzer: random interleavings of offline mutations,
// reconnects, concurrent edits by another device, forced change-log
// pruning, and (behind-only) clock skew, driven against the real
// server. An independent model reimplements the contract's per-medium
// reconciliation policy from its text and predicts the final state;
// divergence is a bug in one of them. Assertions per run: every
// device's view converges to the server's; the model's expected
// winners survive (no lost writes, no resurrections); replayed listen
// queues never double-count.
//
// Client clocks only run behind in the fuzz (skew is negative), so the
// server's future-clamp never fires and the model stays exact; the
// clamp itself is pinned by TestClampFutureRecordedAt.

// fuzzGuard mirrors the contract's recency guard for furthest-wins
// media, restated here independently of the implementation constant.
const fuzzGuard = 10 * time.Minute

// sameRating reports whether two optional ratings hold the same value,
// an unset pair included: the value-identical test the change stamp
// hangs off.
func sameRating(a, b *int) bool {
	if a == nil || b == nil {
		return a == nil && b == nil
	}
	return *a == *b
}

// modelState is the model's per-item expected outcome.
type modelState struct {
	positionMS int64
	posStamp   time.Time
	starred    bool
	starStamp  time.Time
	rating     *int
	ratingStmp time.Time
}

// device is one simulated client: its outbox while offline and its
// last-known play states.
type device struct {
	name    string
	online  bool
	skew    time.Duration
	outbox  []fuzzMutation
	listens []string // queued listen session ids
}

type fuzzMutation struct {
	kind       string // position | star | rating
	pid        string
	positionMS int64
	starred    bool
	rating     *int
	recordedAt time.Time
}

func TestSyncModelFuzz(t *testing.T) {
	if testing.Short() {
		t.Skip("model fuzz is not a -short test")
	}
	for seed := range 5 {
		t.Run(fmt.Sprintf("seed-%d", seed), func(t *testing.T) {
			runSyncModelFuzz(t, uint64(seed))
		})
	}
}

func runSyncModelFuzz(t *testing.T, seed uint64) {
	h := newHarness(t)
	rng := rand.New(rand.NewPCG(seed, seed^0x9e3779b9))
	page := h.items(t, "")
	pids := make([]string, 0, len(page.Items))
	for _, it := range page.Items {
		pids = append(pids, it.Pid)
	}

	model := make(map[string]*modelState)
	stateOf := func(pid string) *modelState {
		if model[pid] == nil {
			model[pid] = &modelState{}
		}
		return model[pid]
	}

	devices := []*device{
		{name: "phone", online: true},
		{name: "laptop", online: true},
	}

	// applyModel folds one mutation into the model exactly as the
	// contract says the server must: live writes always apply; replays
	// reconcile per medium (the fixture library is short music, so
	// furthest-wins governs positions).
	//
	// Stars and ratings order on their change stamp, and the stamp moves
	// only when the value moves: a write storing the value already held
	// is a silent no-op that preserves the stamp, so re-starring a
	// starred item keeps "starred since" truthful and an idempotent
	// re-rate never masquerades as a newer change to a syncing client.
	// Positions carry no such rule - every checkpoint is a real
	// observation - so their stamp bumps unconditionally.
	applyModel := func(m fuzzMutation, replay bool) {
		st := stateOf(m.pid)
		now := time.Now()
		switch m.kind {
		case "position":
			if !replay {
				st.positionMS, st.posStamp = m.positionMS, now
				return
			}
			apply := m.recordedAt.After(st.posStamp) ||
				(m.positionMS > st.positionMS && st.posStamp.Sub(m.recordedAt) <= fuzzGuard)
			if apply {
				st.positionMS = m.positionMS
				// The stamp never rewinds: a further-but-older replay
				// takes the position while the stamp keeps the newest
				// observation time.
				if m.recordedAt.After(st.posStamp) {
					st.posStamp = m.recordedAt
				}
			}
		case "star":
			if m.starred == st.starred {
				return
			}
			if !replay {
				st.starred, st.starStamp = m.starred, now
				return
			}
			if m.recordedAt.After(st.starStamp) {
				st.starred, st.starStamp = m.starred, m.recordedAt
			}
		case "rating":
			if sameRating(m.rating, st.rating) {
				return
			}
			if !replay {
				st.rating, st.ratingStmp = m.rating, now
				return
			}
			if m.recordedAt.After(st.ratingStmp) {
				st.rating, st.ratingStmp = m.rating, m.recordedAt
			}
		}
	}

	sendMutation := func(m fuzzMutation, replay bool) {
		t.Helper()
		body := map[string]any{}
		var path string
		switch m.kind {
		case "position":
			path = "/api/v1/items/" + m.pid + "/play-state"
			body["positionMs"] = m.positionMS
		case "star":
			path = "/api/v1/items/" + m.pid + "/star"
			body["starred"] = m.starred
		case "rating":
			path = "/api/v1/items/" + m.pid + "/rating"
			body["rating"] = m.rating
		}
		if replay {
			body["recordedAt"] = m.recordedAt.UTC().Format(time.RFC3339Nano)
		}
		resp := h.putJSON(t, path, body)
		if resp.StatusCode != 200 && resp.StatusCode != 204 {
			t.Fatalf("%s replay=%v status = %d", m.kind, replay, resp.StatusCode)
		}
		resp.Body.Close()
	}

	randMutation := func(d *device) fuzzMutation {
		m := fuzzMutation{pid: pids[rng.IntN(len(pids))]}
		// The device's skewed clock stamps the mutation; some queues are
		// old enough to fall past the recency guard.
		age := time.Duration(rng.IntN(120)) * time.Second
		if rng.IntN(4) == 0 {
			age = time.Duration(20+rng.IntN(40)) * time.Minute
		}
		m.recordedAt = time.Now().Add(-age).Add(d.skew)
		switch rng.IntN(3) {
		case 0:
			m.kind = "position"
			m.positionMS = int64(rng.IntN(200000))
		case 1:
			m.kind = "star"
			m.starred = rng.IntN(2) == 0
		default:
			m.kind = "rating"
			if rng.IntN(4) == 0 {
				m.rating = nil
			} else {
				r := rng.IntN(101)
				m.rating = &r
			}
		}
		return m
	}

	flush := func(d *device) {
		t.Helper()
		for _, m := range d.outbox {
			sendMutation(m, true)
			applyModel(m, true)
		}
		d.outbox = nil
		// The listen queue flushes with idempotency ids; a coin flip
		// replays the whole batch again (a retry), which must never
		// double-count.
		if len(d.listens) > 0 {
			flushListens := func() {
				sessions := make([]map[string]any, 0, len(d.listens))
				for _, sid := range d.listens {
					sessions = append(sessions, map[string]any{
						"sessionId": sid,
						"pid":       pids[0],
						"startedAt": time.Now().Add(-time.Hour).UTC().Format(time.RFC3339),
						"msPlayed":  1000,
					})
				}
				resp := h.postJSON(t, "/api/v1/listens", map[string]any{"sessions": sessions})
				if resp.StatusCode != 200 {
					t.Fatalf("listen flush status = %d", resp.StatusCode)
				}
				resp.Body.Close()
			}
			flushListens()
			if rng.IntN(2) == 0 {
				flushListens()
			}
			d.listens = nil
		}
	}

	allListenIDs := make(map[string]bool)
	steps := 60
	for step := 0; step < steps; step++ {
		d := devices[rng.IntN(len(devices))]
		switch rng.IntN(10) {
		case 0, 1: // connectivity flip
			if d.online {
				d.online = false
				d.skew = -time.Duration(rng.IntN(600)) * time.Second
			} else {
				d.online = true
				flush(d)
			}
		case 2, 3, 4, 5, 6: // a mutation, live or queued
			m := randMutation(d)
			if d.online {
				m.recordedAt = time.Time{}
				sendMutation(m, false)
				applyModel(m, false)
			} else {
				d.outbox = append(d.outbox, m)
			}
		case 7: // a listen session ends on this device
			sid := fmt.Sprintf("fz%d-%s-%d", seed, d.name, step)
			allListenIDs[sid] = true
			if d.online {
				resp := h.postJSON(t, "/api/v1/listens", map[string]any{"sessions": []map[string]any{{
					"sessionId": sid, "pid": pids[0],
					"startedAt": time.Now().UTC().Format(time.RFC3339), "msPlayed": 1000,
				}}})
				if resp.StatusCode != 200 {
					t.Fatalf("live listen status = %d", resp.StatusCode)
				}
				resp.Body.Close()
			} else {
				d.listens = append(d.listens, sid)
			}
		case 8: // forced pruning: continuity loss is a first-class path
			if _, err := h.svc.PruneCatalogChanges(context.Background(), 1); err != nil {
				t.Fatalf("prune catalog: %v", err)
			}
			if _, err := h.svc.PruneServerEvents(context.Background(), 1); err != nil {
				t.Fatalf("prune events: %v", err)
			}
		case 9: // concurrent edit from an always-online actor
			m := randMutation(devices[0])
			m.recordedAt = time.Time{}
			sendMutation(m, false)
			applyModel(m, false)
		}
	}

	// Quiescence: every device reconnects and flushes.
	for _, d := range devices {
		if !d.online {
			d.online = true
			flush(d)
		}
	}

	// Convergence: the server's state for every touched item matches
	// the model's expected winner.
	for pid, want := range model {
		resp := get(t, h.ts, "/api/v1/items/"+pid+"/play-state", h.token)
		got := decode[PlayState](t, resp)
		if got.PositionMs != want.positionMS {
			t.Errorf("seed run: %s position = %d, model wants %d", pid, got.PositionMs, want.positionMS)
		}
		if got.Starred != want.starred {
			t.Errorf("%s starred = %v, model wants %v", pid, got.Starred, want.starred)
		}
		switch {
		case want.rating == nil && got.Rating != nil:
			t.Errorf("%s rating = %d, model wants none", pid, *got.Rating)
		case want.rating != nil && (got.Rating == nil || *got.Rating != *want.rating):
			t.Errorf("%s rating = %v, model wants %d", pid, got.Rating, *want.rating)
		}
	}

	// No double counting: distinct session ids, exactly once each.
	admin := decode[SessionInfo](t, get(t, h.ts, "/api/v1/auth/session", h.token))
	bare := strings.TrimPrefix(pids[0], "tr-")
	n, err := h.store.ListenCount(context.Background(), admin.User.Id, bare)
	if err != nil {
		t.Fatal(err)
	}
	if n != len(allListenIDs) {
		t.Errorf("listen rows = %d, want %d distinct sessions", n, len(allListenIDs))
	}

	// A fresh mirror converges through snapshot plus delta even after
	// the pruning steps above.
	items, since := h.mirror(t, 100)
	if len(items) != len(pids) {
		t.Errorf("final mirror = %d items, want %d", len(items), len(pids))
	}
	pageAfter, status := h.syncCatalog(t, "?since="+since)
	if status != 200 || len(pageAfter.Entries) != 0 {
		t.Errorf("post-quiescence delta status = %d entries = %d", status, len(pageAfter.Entries))
	}
}

// TestClampFutureRecordedAt pins the server-side clamp the fuzzer's
// behind-only clocks never exercise: a future-dated replay behaves as
// if recorded now, so it wins over any older stamp.
func TestClampFutureRecordedAt(t *testing.T) {
	h := newHarness(t)
	pid := h.items(t, "").Items[0].Pid

	resp := h.putJSON(t, "/api/v1/items/"+pid+"/play-state", map[string]any{"positionMs": 9000})
	resp.Body.Close()

	future := time.Now().Add(24 * time.Hour)
	resp = h.putJSON(t, "/api/v1/items/"+pid+"/play-state", map[string]any{
		"positionMs": 1000, "recordedAt": future.UTC().Format(time.RFC3339Nano),
	})
	if resp.StatusCode != 204 {
		t.Fatalf("future replay status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	st := decode[PlayState](t, get(t, h.ts, "/api/v1/items/"+pid+"/play-state", h.token))
	if st.PositionMs != 1000 {
		t.Fatalf("future-dated replay lost: position = %d, want 1000 (clamped to now, newest wins)", st.PositionMs)
	}
}
