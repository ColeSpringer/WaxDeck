package api

import (
	"path/filepath"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
)

// The stats count what each caller's queue lists: an uploader's counts
// cover the entries their own uploads produced, and decided takes in
// discarded entries the per-status counts never named.
func TestReviewStatsFollowTheQueueScope(t *testing.T) {
	t.Parallel()
	h, bob := joinHarness(t)
	wantStatus(t, h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "cy", "password": testPassword, "uploadEnabled": true,
	}), 201, "a second uploader")
	cy := loginAs(t, h.ts, "cy", testPassword).Token
	dir := t.TempDir()
	var entries []string
	for i, token := range []string{bob, bob, cy} {
		paths, err := fixtures.Generate(filepath.Join(dir, string(rune('a'+i))), fixtures.Spec{
			Name: "scoped", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
			Tags: map[string]string{"TITLE": "Scoped " + string(rune('A'+i)), "ARTIST": "Counted", "ALBUM": "Scope " + string(rune('A'+i))},
		})
		if err != nil {
			t.Fatal(err)
		}
		entries = append(entries, *uploadFile(t, h, token, paths[0], "music", "").ReviewEntryId)
	}
	drainMatches(t, h)
	decideAs(t, h, bob, entries[0], map[string]any{"action": "discard"})

	stats := func(token string) ReviewStats {
		t.Helper()
		return decodeStatus[ReviewStats](t, reqAs(t, h, "GET", "/api/v1/review/stats", token, nil), 200, "stats")
	}
	listed := func(token, status string) int {
		t.Helper()
		return len(decodeStatus[ReviewEntryPage](t, reqAs(t, h, "GET", "/api/v1/review/queue?status="+status, token, nil), 200, "queue").Entries)
	}
	for _, c := range []struct {
		who              string
		token            string
		pending, decided int
	}{{"bob", bob, 1, 1}, {"cy", cy, 1, 0}, {"admin", h.token, 2, 1}} {
		s := stats(c.token)
		if s.Pending != c.pending || s.Decided != c.decided {
			t.Fatalf("%s stats = pending %d, decided %d; want %d, %d", c.who, s.Pending, s.Decided, c.pending, c.decided)
		}
		if p, d := listed(c.token, "pending"), listed(c.token, "decided"); p != s.Pending || d != s.Decided {
			t.Fatalf("%s lists %d pending, %d decided against stats %+v", c.who, p, d, s)
		}
	}
}

// A rematch an uploader asks for is theirs to open, and covers only the
// tracks they may curate, not album siblings someone else brought in.
func TestARematchBelongsToTheCuratorWhoAskedForIt(t *testing.T) {
	t.Parallel()
	h, bob := joinHarness(t)
	tags := func(title string) map[string]string {
		return map[string]string{"TITLE": title, "ARTIST": "Shared Hands", "ALBUM": "Shared Album"}
	}
	if _, err := fixtures.Generate(filepath.Join(h.library, "shared"), fixtures.Spec{
		Name: "theirs", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second, Tags: tags("Scanned In"),
	}); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
		Name: "mine", Codec: fixtures.CodecFLAC, Duration: 3 * time.Second, Tags: tags("Uploaded In"),
	})
	if err != nil {
		t.Fatal(err)
	}
	pid := importAs(t, h, bob, paths[0], "music")

	entry := decodeStatus[RematchResult](t, postJSONAs(t, h, bob, "/api/v1/items/"+pid+"/rematch", nil), 202, "rematch").ReviewEntryId
	tracks := reviewAs(t, h, bob, entry).Tracks
	if len(tracks) != 1 || tracks[0].Pid == nil || *tracks[0].Pid != pid {
		t.Fatalf("rematch tracks = %+v, want the uploader's own track alone", tracks)
	}
	// Where the library keeps its files is the administrators' to read.
	if p := tracks[0].Path; p != filepath.Base(p) {
		t.Fatalf("rematch track path = %q, want its base name alone", p)
	}
	admin := decodeStatus[RematchResult](t, h.postJSON(t, "/api/v1/items/"+pid+"/rematch", nil), 202, "admin rematch").ReviewEntryId
	if n := len(reviewAs(t, h, h.token, admin).Tracks); n != 2 {
		t.Fatalf("admin rematch holds %d tracks, want the album's two", n)
	}
}
