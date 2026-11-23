package service

import (
	"testing"
	"time"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// Two sessions of one item from one start and one client, as an untimed
// scrobble naming a song twice records, are two entries the log tells
// apart by their ids.
func TestTheListenLogAnswersEachSessionsOwnID(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := spellingLibrary(t, spellingTrack("twice", time.Second, map[string]string{"TITLE": "Twice"}))
	items := spellingWalk(t, ctx, svc, admin, 10)
	if len(items) != 1 {
		t.Fatalf("scanned %d items, want 1", len(items))
	}
	_, pid, _ := parseAPIPID(items[0].PID)
	at := time.Now().Add(-time.Minute).UTC()
	var sessions []wdb.ListenSession
	for _, id := range []string{"twice-a", "twice-b"} {
		sessions = append(sessions, wdb.ListenSession{UserID: admin.ID, SessionID: id, ItemPID: string(pid),
			MediaType: "music", StartedAt: at, MsPlayed: 1000, Client: "a-client"})
	}
	if _, err := svc.db.InsertListens(ctx, sessions); err != nil {
		t.Fatal(err)
	}
	log, err := svc.Reads.ListenLog(ctx, admin, "", "", 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(log.Sessions) != 2 {
		t.Fatalf("log = %+v, want two sessions", log.Sessions)
	}
	got := map[string]bool{log.Sessions[0].SessionID: true, log.Sessions[1].SessionID: true}
	if !got["twice-a"] || !got["twice-b"] {
		t.Fatalf("session ids = %q and %q, want twice-a and twice-b", log.Sessions[0].SessionID, log.Sessions[1].SessionID)
	}
}
