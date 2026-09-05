package service

import (
	"testing"
	"time"
)

func TestCrossedPlayedThreshold(t *testing.T) {
	t.Parallel()
	const minute = int64(60_000)
	cases := []struct {
		name       string
		mediaType  string
		msPlayed   int64
		durationMS int64
		want       bool
	}{
		{"music half of short track", "music", 500, 1000, true},
		{"music under half of short track", "music", 400, 1000, false},
		{"music four minutes of a long track", "music", 4 * minute, 10 * minute, true},
		{"music under both rules", "music", 3 * minute, 10 * minute, false},
		{"music two-hour set, four minutes is not enough", "music", 4 * minute, 120 * minute, false},
		{"music two-hour set, an hour counts", "music", 60 * minute, 120 * minute, true},
		{"podcast ninety percent", "podcast", 54 * minute, 60 * minute, true},
		{"podcast eighty percent", "podcast", 48 * minute, 60 * minute, false},
		{"audiobook complete", "audiobook", 594 * minute, 600 * minute, true},
		{"audiobook near complete", "audiobook", 580 * minute, 600 * minute, false},
		{"zero played", "music", 0, 1000, false},
		{"unknown duration", "music", 5 * minute, 0, false},
	}
	for _, c := range cases {
		if got := crossedPlayedThreshold(c.mediaType, c.msPlayed, c.durationMS); got != c.want {
			t.Errorf("%s: got %v, want %v", c.name, got, c.want)
		}
	}
}

func TestInvalidSession(t *testing.T) {
	t.Parallel()
	valid := ListenSession{SessionID: "s-1", PID: "tr-01JZX5N8QW3F4V9T2B7KD3M9R6"}
	cases := []struct {
		name   string
		mutate func(*ListenSession)
		reject bool
	}{
		{"well formed", func(*ListenSession) {}, false},
		{"live source", func(s *ListenSession) { s.Source = "live" }, false},
		{"import source", func(s *ListenSession) { s.Source = "import" }, false},
		{"missing session id", func(s *ListenSession) { s.SessionID = "" }, true},
		{"overlong session id", func(s *ListenSession) { s.SessionID = string(make([]byte, 65)) }, true},
		{"missing pid", func(s *ListenSession) { s.PID = "" }, true},
		{"negative msPlayed", func(s *ListenSession) { s.MsPlayed = -1 }, true},
		{"overlong client", func(s *ListenSession) { s.Client = string(make([]byte, 129)) }, true},
		{"unknown source", func(s *ListenSession) { s.Source = "scrobble" }, true},
	}
	for _, c := range cases {
		s := valid
		c.mutate(&s)
		reason := invalidSession(s)
		if got := reason != ""; got != c.reject {
			t.Errorf("%s: reject = %v (%q), want %v", c.name, got, reason, c.reject)
		}
	}
}

// TestLastPlayedAtFollowsCountedPlays pins what the play state's
// last-played stamp means: the listening record, not the flag's age. A
// counted listen sets it; a manual played mark, which exists so a
// listener can clear a backlog they heard elsewhere, deliberately does
// not - stamping it would put a play in the record that never happened.
func TestLastPlayedAtFollowsCountedPlays(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	played, _ := fixtureTrackPID(t, ctx, svc, uc, "Amber Waves")
	marked, _ := fixtureTrackPID(t, ctx, svc, uc, "Basalt Steps")

	for _, pid := range []string{played, marked} {
		st, err := svc.PlayState(ctx, uc, pid)
		if err != nil {
			t.Fatalf("play state for %s: %v", pid, err)
		}
		if !st.LastPlayedAt.IsZero() {
			t.Fatalf("a fresh state carries lastPlayedAt %v, want zero", st.LastPlayedAt)
		}
	}

	before := time.Now().UTC().Add(-time.Second)
	res, err := svc.IngestListens(ctx, uc, []ListenSession{{
		SessionID: "s-1",
		PID:       played,
		StartedAt: time.Now().UTC(),
		MsPlayed:  2000,
		Finished:  true,
	}})
	if err != nil || res.Accepted != 1 {
		t.Fatalf("ingest = %+v (%v), want one accepted", res, err)
	}
	st, err := svc.PlayState(ctx, uc, played)
	if err != nil {
		t.Fatal(err)
	}
	if st.PlayCount != 1 {
		t.Fatalf("play count = %d, want 1", st.PlayCount)
	}
	if st.LastPlayedAt.Before(before) {
		t.Fatalf("lastPlayedAt = %v, want at or after %v", st.LastPlayedAt, before)
	}

	if _, err := svc.SetPlayed(ctx, uc, marked, true, true, nil, nil, nil); err != nil {
		t.Fatalf("manual played mark: %v", err)
	}
	st, err = svc.PlayState(ctx, uc, marked)
	if err != nil {
		t.Fatal(err)
	}
	if !st.Played || !st.Finished {
		t.Fatalf("manual mark left %+v, want played and finished", st)
	}
	if !st.LastPlayedAt.IsZero() {
		t.Fatalf("a manual mark stamped lastPlayedAt %v, want zero", st.LastPlayedAt)
	}
	// And the pair a reader has to be told about: the catalog raises the
	// count to the smallest number consistent with the flag, so a hand
	// mark answers one play with no time attached. "Never played" is the
	// wrong reading of that, and so is a blank.
	if st.PlayCount != 1 {
		t.Fatalf("manual mark left play count %d, want 1 beside a zero stamp", st.PlayCount)
	}
}

// TestItemDetailCarriesRecordingIdentifiers pins the two identifier
// fields the detail read grew for the facts sheet: present on the
// tagged track, absent on the rest, which is what most of a scanned
// library looks like.
func TestItemDetailCarriesRecordingIdentifiers(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	tagged, _ := fixtureTrackPID(t, ctx, svc, uc, "Delta Groove")
	bare, _ := fixtureTrackPID(t, ctx, svc, uc, "Amber Waves")

	d, err := svc.Item(ctx, uc, tagged)
	if err != nil {
		t.Fatal(err)
	}
	if d.MBID != catalogFixtureMBID || d.ISRC != catalogFixtureISRC {
		t.Fatalf("identifiers = %q/%q, want %q/%q",
			d.MBID, d.ISRC, catalogFixtureMBID, catalogFixtureISRC)
	}

	d, err = svc.Item(ctx, uc, bare)
	if err != nil {
		t.Fatal(err)
	}
	if d.MBID != "" || d.ISRC != "" {
		t.Fatalf("an untagged track carries %q/%q, want neither", d.MBID, d.ISRC)
	}
}
