package db

import (
	"context"
	"testing"
)

// Storing an entry with its links is all or nothing: a file already in an
// entry, or no longer staged, stores nothing, and an identifying entry is
// queued with it.
func TestAnEntryStoredWithItsLinksIsAllOrNothing(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	if err := d.CreateUser(ctx, mkUser("us-1", "u1", nil), false); err != nil {
		t.Fatal(err)
	}
	for _, u := range []Upload{
		{ID: "up-free", UserID: "us-1", FileName: "a.flac", MediaType: "music", State: "staged", CreatedAtNS: 1},
		{ID: "up-taken", UserID: "us-1", FileName: "b.flac", MediaType: "music", State: "staged", CreatedAtNS: 1, ReviewEntryID: "re-other"},
		{ID: "up-gone", UserID: "us-1", FileName: "c.flac", MediaType: "music", State: "imported", CreatedAtNS: 1},
	} {
		if err := d.InsertUpload(ctx, u); err != nil {
			t.Fatal(err)
		}
	}
	entry := func(id string) ReviewEntry {
		return ReviewEntry{ID: id, Kind: "import", Status: "pending", MediaType: "music", UploadedBy: "us-1", Identifying: true, CreatedAtNS: 1}
	}
	count := func(q string, args ...any) int {
		t.Helper()
		var n int
		if err := d.Reader().QueryRowContext(ctx, q, args...).Scan(&n); err != nil {
			t.Fatal(err)
		}
		return n
	}
	for _, other := range []string{"up-taken", "up-gone"} {
		if err := d.InsertReviewEntryLinked(ctx, entry("re-"+other), []string{"up-free", other}); err == nil {
			t.Errorf("linking %s stored the entry, want it refused", other)
		}
		if n := count(`SELECT COUNT(*) FROM review_entries WHERE id = ?`, "re-"+other); n != 0 {
			t.Errorf("a refused link with %s left its entry stored", other)
		}
		if n := count(`SELECT COUNT(*) FROM match_queue WHERE entry_id = ?`, "re-"+other); n != 0 {
			t.Errorf("a refused link with %s left its entry queued", other)
		}
		if n := count(`SELECT COUNT(*) FROM uploads WHERE id = 'up-free' AND review_entry_id <> ''`); n != 0 {
			t.Errorf("a refused link with %s linked the free file", other)
		}
	}
	if err := d.InsertReviewEntryLinked(ctx, entry("re-ok"), []string{"up-free"}); err != nil {
		t.Fatal(err)
	}
	if n := count(`SELECT COUNT(*) FROM uploads WHERE id = 'up-free' AND review_entry_id = 're-ok'`); n != 1 {
		t.Error("the free file is not linked to its entry")
	}
	if n := count(`SELECT COUNT(*) FROM match_queue WHERE entry_id = 're-ok'`); n != 1 {
		t.Error("the identifying entry is not queued")
	}
}
