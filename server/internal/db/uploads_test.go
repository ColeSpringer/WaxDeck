package db

import (
	"context"
	"testing"
)

func TestContentDuplicateByHash(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	if err := d.CreateUser(ctx, mkUser("us-1", "u1", nil), false); err != nil {
		t.Fatal(err)
	}

	ins := func(id, sha, state, dupPID string, createdNS int64) {
		t.Helper()
		if err := d.InsertUpload(ctx, Upload{
			ID: id, UserID: "us-1", FileName: id + ".flac", MediaType: "music",
			SHA256: sha, State: state, DuplicatePID: dupPID, CreatedAtNS: createdNS,
		}); err != nil {
			t.Fatalf("insert %s: %v", id, err)
		}
	}

	// The matching session is the oldest; newer non-matching sessions pile on
	// top of it, so a recency- or count-bounded scan would miss it.
	ins("up-match", "hashA", "imported", "tr-01KY0000000000000000000001", 100)
	for i := int64(0); i < 5; i++ {
		ins("up-other-"+string(rune('a'+i)), "hashB", "imported", "tr-other", 200+i)
	}

	pid, ok, err := d.ContentDuplicateByHash(ctx, "hashA", "imported")
	if err != nil {
		t.Fatalf("lookup: %v", err)
	}
	if !ok || pid != "tr-01KY0000000000000000000001" {
		t.Fatalf("hashA lookup = (%q, %v), want the older imported match", pid, ok)
	}

	// A hash with no imported-and-resolved session is a clean miss.
	if _, ok, err := d.ContentDuplicateByHash(ctx, "hashB", "imported"); err != nil || !ok {
		// hashB rows carry a duplicate_pid, so they DO match.
		t.Fatalf("hashB should match its own rows: ok=%v err=%v", ok, err)
	}
	if _, ok, err := d.ContentDuplicateByHash(ctx, "missing", "imported"); err != nil || ok {
		t.Fatalf("unknown hash should miss: ok=%v err=%v", ok, err)
	}

	// A matching hash whose only session is still staged (not imported) misses.
	ins("up-staged", "hashC", "staged", "tr-staged", 300)
	if _, ok, err := d.ContentDuplicateByHash(ctx, "hashC", "imported"); err != nil || ok {
		t.Fatalf("staged-only hash should miss under state=imported: ok=%v err=%v", ok, err)
	}

	// A matching, imported hash with no resolved duplicate misses (nothing to
	// point the new upload at).
	ins("up-noresolve", "hashD", "imported", "", 400)
	if _, ok, err := d.ContentDuplicateByHash(ctx, "hashD", "imported"); err != nil || ok {
		t.Fatalf("imported-but-unresolved hash should miss: ok=%v err=%v", ok, err)
	}
}

// The quota is a ceiling on what waits in staging, so only the states
// that are still waiting count: an import releases its bytes, which is
// what keeps a filled quota from being permanent.
func TestUploadBytesInUseChargesOnlyStagedSessions(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	if err := d.CreateUser(ctx, mkUser("us-1", "u1", nil), false); err != nil {
		t.Fatal(err)
	}
	if err := d.CreateUser(ctx, mkUser("us-2", "u2", nil), false); err != nil {
		t.Fatal(err)
	}

	ins := func(id, userID, state string, size int64) {
		t.Helper()
		if err := d.InsertUpload(ctx, Upload{
			ID: id, UserID: userID, FileName: id + ".flac", MediaType: "music",
			SizeBytes: size, State: state, CreatedAtNS: 1,
		}); err != nil {
			t.Fatalf("insert %s: %v", id, err)
		}
	}

	ins("up-receiving", "us-1", "receiving", 100)
	ins("up-staged", "us-1", "staged", 200)
	ins("up-imported", "us-1", "imported", 4000)
	ins("up-discarded", "us-1", "discarded", 8000)
	// Another account's staging is not this one's problem.
	ins("up-other", "us-2", "staged", 16000)

	used, err := d.UploadBytesInUse(ctx, "us-1")
	if err != nil {
		t.Fatalf("summing: %v", err)
	}
	if used != 300 {
		t.Fatalf("bytesInUse = %d, want 300 (receiving + staged only)", used)
	}

	// An account whose sessions all left staging is back to zero rather
	// than charged for good.
	if used, err := d.UploadBytesInUse(ctx, "us-2"); err != nil || used != 16000 {
		t.Fatalf("us-2 bytesInUse = %d (%v), want 16000", used, err)
	}
}

// Free space says what landed, never what is coming, so the staging
// check reads this: every byte a session still receiving has been
// promised and has not written yet, across all accounts.
func TestUploadBytesOutstandingCountsOnlyWhatIsStillComing(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	if err := d.CreateUser(ctx, mkUser("us-1", "u1", nil), false); err != nil {
		t.Fatal(err)
	}
	if err := d.CreateUser(ctx, mkUser("us-2", "u2", nil), false); err != nil {
		t.Fatal(err)
	}

	// Opened "now" for the window's sake; the stale one below is what
	// the window is there to drop.
	const now = 1_000_000_000_000
	ins := func(id, userID, state string, size, received int64) {
		t.Helper()
		if err := d.InsertUpload(ctx, Upload{
			ID: id, UserID: userID, FileName: id + ".flac", MediaType: "music",
			SizeBytes: size, ReceivedBytes: received, State: state, CreatedAtNS: now,
		}); err != nil {
			t.Fatalf("insert %s: %v", id, err)
		}
	}

	// Half arrived, so half is still owed.
	ins("up-half", "us-1", "receiving", 1000, 400)
	// Nothing yet, so all of it is.
	ins("up-fresh", "us-2", "receiving", 250, 0)
	// Everything arrived: the bytes are on the volume, and free space
	// already counts them.
	ins("up-full", "us-1", "receiving", 90, 90)
	// Past receiving entirely, whichever way it went.
	ins("up-staged", "us-1", "staged", 5000, 5000)
	ins("up-imported", "us-1", "imported", 7000, 7000)
	ins("up-discarded", "us-2", "discarded", 9000, 0)

	owed, err := d.UploadBytesOutstanding(ctx, now)
	if err != nil {
		t.Fatalf("summing: %v", err)
	}
	if owed != 850 {
		t.Fatalf("outstanding = %d, want 850 (600 + 250)", owed)
	}

	// A session that opened before the window is not counted, however
	// much it still owes: a promise made by a transfer nobody is
	// running would otherwise reserve the volume until a janitor swept
	// it, which is a week under the default retention.
	if err := d.InsertUpload(ctx, Upload{
		ID: "up-stale", UserID: "us-1", FileName: "stale.flac", MediaType: "music",
		SizeBytes: 1 << 30, State: "receiving", CreatedAtNS: now - 1,
	}); err != nil {
		t.Fatal(err)
	}
	if owed, err := d.UploadBytesOutstanding(ctx, now); err != nil || owed != 850 {
		t.Fatalf("outstanding with a stale session = %d (%v), want 850", owed, err)
	}
	// And is counted again by a window wide enough to reach it, which
	// is what says the bound is the window rather than the row.
	if owed, err := d.UploadBytesOutstanding(ctx, now-1); err != nil || owed != 850+(1<<30) {
		t.Fatalf("outstanding over a wider window = %d (%v)", owed, err)
	}
}

func TestAdvanceUploadReceivedIsACompareAndSet(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	if err := d.CreateUser(ctx, mkUser("us-1", "u1", nil), false); err != nil {
		t.Fatal(err)
	}
	for id, state := range map[string]string{"up-receiving": "receiving", "up-staged": "staged"} {
		if err := d.InsertUpload(ctx, Upload{
			ID: id, UserID: "us-1", FileName: id + ".flac", MediaType: "music",
			SizeBytes: 100, ReceivedBytes: 10, State: state, CreatedAtNS: 1, ReceivedAtNS: 1,
		}); err != nil {
			t.Fatalf("insert %s: %v", id, err)
		}
	}

	// The time bytes last arrived moves with the count and only with it.
	for _, tc := range []struct {
		name, id   string
		from, to   int64
		at         int64
		want       bool
		stored, ns int64
	}{
		{"wrong from", "up-receiving", 5, 20, 50, false, 10, 1},
		{"not receiving", "up-staged", 10, 20, 50, false, 10, 1},
		{"missing row", "up-nope", 10, 20, 50, false, 0, 0},
		{"match", "up-receiving", 10, 20, 60, true, 20, 60},
		{"match again from the old count", "up-receiving", 10, 30, 70, false, 20, 60},
	} {
		moved, err := d.AdvanceUploadReceived(ctx, tc.id, tc.from, tc.to, tc.at)
		if err != nil {
			t.Fatalf("%s: %v", tc.name, err)
		}
		if moved != tc.want {
			t.Fatalf("%s: moved = %v, want %v", tc.name, moved, tc.want)
		}
		if tc.id == "up-nope" {
			continue
		}
		u, err := d.UploadByID(ctx, tc.id)
		if err != nil {
			t.Fatal(err)
		}
		if u.ReceivedBytes != tc.stored || u.ReceivedAtNS != tc.ns {
			t.Fatalf("%s: stored %d at %d, want %d at %d", tc.name, u.ReceivedBytes, u.ReceivedAtNS, tc.stored, tc.ns)
		}
	}
}

// A touch records bytes that arrived without being kept: it only ever
// moves the time forward, and only on a session still receiving.
func TestTouchUploadReceivedOnlyMovesForward(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	if err := d.CreateUser(ctx, mkUser("us-1", "u1", nil), false); err != nil {
		t.Fatal(err)
	}
	for id, state := range map[string]string{"up-receiving": "receiving", "up-staged": "staged"} {
		if err := d.InsertUpload(ctx, Upload{
			ID: id, UserID: "us-1", FileName: id + ".flac", MediaType: "music",
			SizeBytes: 100, State: state, CreatedAtNS: 1, ReceivedAtNS: 50,
		}); err != nil {
			t.Fatalf("insert %s: %v", id, err)
		}
	}
	for _, tc := range []struct {
		name, id string
		at, want int64
	}{
		{"later", "up-receiving", 80, 80},
		{"earlier", "up-receiving", 60, 80},
		{"not receiving", "up-staged", 90, 50},
	} {
		if err := d.TouchUploadReceived(ctx, tc.id, tc.at); err != nil {
			t.Fatalf("%s: %v", tc.name, err)
		}
		u, err := d.UploadByID(ctx, tc.id)
		if err != nil {
			t.Fatal(err)
		}
		if u.ReceivedAtNS != tc.want {
			t.Fatalf("%s: received at %d, want %d", tc.name, u.ReceivedAtNS, tc.want)
		}
	}
}
