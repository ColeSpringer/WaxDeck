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
