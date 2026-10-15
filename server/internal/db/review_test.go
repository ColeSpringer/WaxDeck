package db

import (
	"context"
	"testing"
)

func TestListReviewEntriesDecidedFilter(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()

	ins := func(id, status string, createdNS int64) {
		t.Helper()
		if err := d.InsertReviewEntry(ctx, ReviewEntry{
			ID: id, Kind: "import", Status: status, MediaType: "music",
			Origin: "upload", CreatedAtNS: createdNS,
		}); err != nil {
			t.Fatalf("insert %s: %v", id, err)
		}
	}

	// Decided entries are older; a head of pending entries would strand them
	// under a client-side filter, which is what the "decided" pseudo-status
	// fixes server-side.
	ins("rv-applied", "applied", 100)
	ins("rv-asis", "as-is", 200)
	ins("rv-p1", "pending", 300)
	ins("rv-p2", "pending", 400)

	got, err := d.ListReviewEntries(ctx, "decided", "", 0, "", 50)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 {
		t.Fatalf("decided count = %d, want 2 (non-pending only)", len(got))
	}
	for _, e := range got {
		if e.Status == "pending" {
			t.Fatalf("decided filter returned a pending entry: %s", e.ID)
		}
	}

	if got, err := d.ListReviewEntries(ctx, "pending", "", 0, "", 50); err != nil || len(got) != 2 {
		t.Fatalf("pending count = %d (err %v), want 2", len(got), err)
	}
	if got, err := d.ListReviewEntries(ctx, "", "", 0, "", 50); err != nil || len(got) != 4 {
		t.Fatalf("unfiltered count = %d (err %v), want 4", len(got), err)
	}
}

// The stats count what the queue lists: an uploader's own entries, or
// every entry for the unscoped read, with decided covering every status
// but pending.
func TestReviewStatsScopedToUploader(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	for i, e := range []struct{ id, status, by string }{
		{"rv-a1", "applied", "us-a"},
		{"rv-a2", "reverted", "us-a"},
		{"rv-a3", "pending", "us-a"},
		{"rv-b1", "discarded", "us-b"},
		{"rv-b2", "pending", "us-b"},
		{"rv-scan", "pending", ""},
	} {
		if err := d.InsertReviewEntry(ctx, ReviewEntry{
			ID: e.id, Kind: "import", Status: e.status, MediaType: "music",
			Origin: "upload", UploadedBy: e.by, CreatedAtNS: int64(i + 1),
		}); err != nil {
			t.Fatalf("insert %s: %v", e.id, err)
		}
	}
	for _, c := range []struct {
		uploader                  string
		pending, decided, applied int
	}{{"", 3, 3, 1}, {"us-a", 1, 2, 1}, {"us-b", 1, 1, 0}, {"us-c", 0, 0, 0}} {
		s, err := d.ReviewStatsNow(ctx, c.uploader)
		if err != nil {
			t.Fatal(err)
		}
		if s.Pending != c.pending || s.Decided != c.decided || s.Applied != c.applied {
			t.Fatalf("stats for %q = %+v, want pending %d, decided %d, applied %d",
				c.uploader, s, c.pending, c.decided, c.applied)
		}
	}
}
