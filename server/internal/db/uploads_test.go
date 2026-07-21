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
