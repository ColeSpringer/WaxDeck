package service

import (
	"fmt"
	"slices"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"
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
	valid := ListenSession{
		SessionID: "s-1",
		PID:       "tr-01JZX5N8QW3F4V9T2B7KD3M9R6",
		StartedAt: time.Now().UTC(),
	}
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
		{"a decade ago", func(s *ListenSession) { s.StartedAt = time.Now().AddDate(-10, 0, 0) }, false},
		{"a clock an hour fast", func(s *ListenSession) { s.StartedAt = time.Now().Add(time.Hour) }, false},
		{"no start at all", func(s *ListenSession) { s.StartedAt = time.Time{} }, true},
		{"before there were files", func(s *ListenSession) { s.StartedAt = time.Unix(-1, 0) }, true},
		{"dated next year", func(s *ListenSession) { s.StartedAt = time.Now().AddDate(1, 0, 0) }, true},
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

// TestIngestResolvesEachItemOnce pins the shape a history import
// depends on. Every session in a batch that names one item shares a
// single resolve - the catalog read, the library attribution and the
// content rules behind it run once, not once per play - and a pid that
// resolves to nothing is refused once per session naming it, so a
// client can still drop exactly the sessions it was told about.
func TestIngestResolvesEachItemOnce(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	amber, _ := fixtureTrackPID(t, ctx, svc, uc, "Amber Waves")
	basalt, _ := fixtureTrackPID(t, ctx, svc, uc, "Basalt Steps")
	const absent = "tr-01JZX5N8QW3F4V9T2B7KD3M9R6"

	var sessions []ListenSession
	for i, pid := range []string{amber, absent, amber, basalt, absent, amber} {
		sessions = append(sessions, ListenSession{
			SessionID: fmt.Sprintf("s-%d", i),
			PID:       pid,
			StartedAt: time.Now().UTC(),
			MsPlayed:  1500,
		})
	}
	rows, rejected, err := svc.resolveListens(ctx, uc, sessions)
	if err != nil {
		t.Fatalf("resolveListens: %v", err)
	}
	if len(rows) != 4 {
		t.Fatalf("resolved %d sessions, want 4", len(rows))
	}
	// A fresh read allocates a fresh view, so sharing the pointer is
	// what says the answer was remembered rather than re-read.
	for _, i := range []int{1, 3} {
		if rows[i].it != rows[0].it {
			t.Fatalf("session %s re-resolved %s", rows[i].s.SessionID, rows[i].s.PID)
		}
	}
	if rows[2].it == rows[0].it {
		t.Fatalf("two different items share one resolve")
	}
	if len(rejected) != 2 {
		t.Fatalf("rejected %+v, want one per session naming the absent item", rejected)
	}
	for _, r := range rejected {
		if r.Code != "not-found" || r.SessionID == "" {
			t.Fatalf("rejection = %+v, want a not-found carrying its session", r)
		}
	}
}

// TestIngestBatchRecordsEveryPlay pins that sharing one resolve across a
// batch shares nothing else: each session is its own play, a session id
// repeated inside one batch is the replay it looks like, and the item's
// count is what actually landed.
func TestIngestBatchRecordsEveryPlay(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	amber, _ := fixtureTrackPID(t, ctx, svc, uc, "Amber Waves")

	var sessions []ListenSession
	for i := range 4 {
		sessions = append(sessions, ListenSession{
			SessionID: fmt.Sprintf("play-%d", i),
			PID:       amber,
			StartedAt: time.Now().UTC().Add(time.Duration(-i) * time.Hour),
			MsPlayed:  1500,
			Finished:  true,
		})
	}
	// The offline queue flushing a session the live report already
	// carries: both ride the same call.
	sessions = append(sessions, sessions[0])

	res, err := svc.IngestListens(ctx, uc, sessions)
	if err != nil {
		t.Fatalf("ingest: %v", err)
	}
	if res.Accepted != 4 || res.Duplicates != 1 || len(res.Rejected) != 0 {
		t.Fatalf("ingest = %+v, want four accepted and one duplicate", res)
	}
	st, err := svc.PlayState(ctx, uc, amber)
	if err != nil {
		t.Fatal(err)
	}
	if st.PlayCount != 4 {
		t.Fatalf("play count = %d, want 4", st.PlayCount)
	}
}

// TestUnmarkedTail pins the compensating delete's reach. A fatal mark
// leaves its own row and everything behind it claimed without a mark,
// and a retry would read those claims as duplicates and skip the mark
// forever, so they come back out. What was already marked stays, and so
// does a row this call did not claim: that one belongs to an earlier
// ingest that marked it, and taking it back out would let the retry
// count its play a second time.
func TestUnmarkedTail(t *testing.T) {
	t.Parallel()
	rows := make([]resolvedListen, 5)
	for i := range rows {
		rows[i].s.SessionID = fmt.Sprintf("s-%d", i)
	}
	// s-3 was already recorded by an earlier ingest.
	claimed := []bool{true, true, true, false, true}

	got := unmarkedTail(rows, claimed, 2)
	want := []string{"s-2", "s-4"}
	if !slices.Equal(got, want) {
		t.Fatalf("tail from the third row = %v, want %v", got, want)
	}
	if got := unmarkedTail(rows, claimed, 0); len(got) != 4 {
		t.Fatalf("tail from the first row = %v, want every claim", got)
	}
	if got := unmarkedTail(rows, claimed, len(rows)); len(got) != 0 {
		t.Fatalf("tail past the last row = %v, want nothing", got)
	}
}

// TestConnectListenLands pins that a session played out on a remote
// device reaches the record. It rides the same ingest a client's own
// report does, so the source it declares has to be one that ingest
// accepts: anything else is a per-session refusal the caller only logs,
// and the listen is gone without anything saying so.
func TestConnectListenLands(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	amber, _ := fixtureTrackPID(t, ctx, svc, uc, "Amber Waves")

	svc.PlayerListen(ctx, uc.ID, amber, 2000, time.Now().UTC().Add(-2*time.Second))

	st, err := svc.PlayState(ctx, uc, amber)
	if err != nil {
		t.Fatal(err)
	}
	if st.PlayCount != 1 || !st.Played {
		t.Fatalf("play state = %+v, want one counted play", st)
	}
}

// TestListenMarksStampTheSessionsOwnTime pins the rule the catalog's
// recency now follows: a play is stamped when it happened, not when it
// was reported. A history moved in from another service therefore
// leaves last-played on the plays' own dates, and because the catalog
// never moves a stamp backwards, a listen that arrives late cannot
// regress one that arrived on time.
func TestListenMarksStampTheSessionsOwnTime(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	pid, _ := fixtureTrackPID(t, ctx, svc, uc, "Amber Waves")

	lastYear := time.Now().UTC().AddDate(-1, 0, 0).Truncate(time.Second)
	res, err := svc.IngestListens(ctx, uc, []ListenSession{{
		SessionID: "s-import",
		PID:       pid,
		StartedAt: lastYear,
		MsPlayed:  2000,
		Finished:  true,
		Source:    "import",
	}})
	if err != nil || res.Accepted != 1 {
		t.Fatalf("ingest = %+v (%v), want one accepted", res, err)
	}
	st, err := svc.PlayState(ctx, uc, pid)
	if err != nil {
		t.Fatal(err)
	}
	if st.PlayCount != 1 {
		t.Fatalf("play count = %d, want 1", st.PlayCount)
	}
	// The end of the session, which is where the play actually
	// finished; anywhere near now would be the import instant leaking
	// into the record.
	wantAt := lastYear.Add(2 * time.Second)
	if diff := st.LastPlayedAt.Sub(wantAt); diff < -time.Second || diff > time.Second {
		t.Fatalf("lastPlayedAt = %v, want the session's own end %v", st.LastPlayedAt, wantAt)
	}

	// A later live listen still advances it: the stamp follows the
	// newest play, and this one is newer than last year's.
	before := time.Now().UTC().Add(-time.Second)
	res, err = svc.IngestListens(ctx, uc, []ListenSession{{
		SessionID: "s-live",
		PID:       pid,
		StartedAt: time.Now().UTC(),
		MsPlayed:  2000,
		Finished:  true,
	}})
	if err != nil || res.Accepted != 1 {
		t.Fatalf("live ingest = %+v (%v), want one accepted", res, err)
	}
	st, err = svc.PlayState(ctx, uc, pid)
	if err != nil {
		t.Fatal(err)
	}
	if st.PlayCount != 2 {
		t.Fatalf("play count = %d, want 2", st.PlayCount)
	}
	if st.LastPlayedAt.Before(before) {
		t.Fatalf("lastPlayedAt = %v, want the live play at or after %v", st.LastPlayedAt, before)
	}

	// And the older one arriving last does not drag the stamp back.
	res, err = svc.IngestListens(ctx, uc, []ListenSession{{
		SessionID: "s-import-late",
		PID:       pid,
		StartedAt: lastYear.Add(time.Hour),
		MsPlayed:  2000,
		Finished:  true,
		Source:    "import",
	}})
	if err != nil || res.Accepted != 1 {
		t.Fatalf("late ingest = %+v (%v), want one accepted", res, err)
	}
	st, err = svc.PlayState(ctx, uc, pid)
	if err != nil {
		t.Fatal(err)
	}
	if st.LastPlayedAt.Before(before) {
		t.Fatalf("a late import dragged lastPlayedAt back to %v", st.LastPlayedAt)
	}
	if st.PlayCount != 3 {
		t.Fatalf("play count = %d, want the late play counted too", st.PlayCount)
	}
}

// TestReplayedCheckpointStampsItsRecordedTime pins the other half of
// the recorded-time work: a checkpoint flushed from an offline outbox
// records progress when it was taken, so the item keeps its rank on
// the in-progress shelf instead of jumping to the top of it.
func TestReplayedCheckpointStampsItsRecordedTime(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	pid, catalogPID := fixtureTrackPID(t, ctx, svc, uc, "Cobalt Sky")

	yesterday := time.Now().UTC().Add(-24 * time.Hour).Truncate(time.Second)
	applied, err := svc.Checkpoint(ctx, uc, pid, 1200, &yesterday)
	if err != nil || !applied {
		t.Fatalf("replayed checkpoint = %v (%v), want applied", applied, err)
	}
	st, err := svc.lib.Playback().State(ctx, model.PID(uc.CatalogPID), catalogPID)
	if err != nil || st == nil {
		t.Fatalf("catalog state = %+v (%v)", st, err)
	}
	at := time.Unix(0, st.LastProgressAt).UTC()
	if diff := at.Sub(yesterday); diff < -time.Second || diff > time.Second {
		t.Fatalf("lastProgressAt = %v, want the recorded time %v", at, yesterday)
	}

	// A live checkpoint after it stamps now, and the catalog's
	// never-backwards rule means the replay cannot pull it back.
	before := time.Now().UTC().Add(-time.Second)
	if _, err := svc.Checkpoint(ctx, uc, pid, 1800, nil); err != nil {
		t.Fatal(err)
	}
	st, err = svc.lib.Playback().State(ctx, model.PID(uc.CatalogPID), catalogPID)
	if err != nil || st == nil {
		t.Fatalf("catalog state = %+v (%v)", st, err)
	}
	if at := time.Unix(0, st.LastProgressAt).UTC(); at.Before(before) {
		t.Fatalf("lastProgressAt = %v, want the live checkpoint at or after %v", at, before)
	}
}
