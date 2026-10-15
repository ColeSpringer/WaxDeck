package service

import (
	"context"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
)

// An item's detail reads the row of the file it entered with and of each
// copy, not of every part of a book: a book's other parts carry nothing
// it shows.
func TestAnItemsDetailReadsItsFileAndCopiesOnly(t *testing.T) {
	books := t.TempDir()
	ctx, svc, admin := managedUploadFixture(t, Root{Name: "books", Path: books, Media: "audiobook"})
	for i, d := range []time.Duration{2 * time.Second, 3 * time.Second, 4 * time.Second} {
		tomePart(t, books, "part"+string(rune('a'+i)), "Part", string(rune('1'+i)), d)
	}
	scan, err := svc.lib.StartScan(ctx, waxbin.ScanRequest{})
	if err != nil {
		t.Fatal(err)
	}
	waitForJob(t, ctx, svc, scan)
	book := itemPIDByTitle(t, ctx, svc, admin, "Shared Tome")
	reads := 0
	svc.fileReadHook = func(ctx context.Context, pid model.PID) (*model.File, error) {
		reads++
		return svc.lib.File(ctx, pid)
	}
	d, err := svc.Item(ctx, admin, book)
	if err != nil {
		t.Fatal(err)
	}
	if reads != 1 || d.Bitrate == 0 || d.AddedAt.IsZero() {
		t.Fatalf("file rows read %d, detail bitrate %d added %v; want the primary's alone, and what it gives", reads, d.Bitrate, d.AddedAt)
	}
}

// An item entered the library when its file did, or a copy of it the
// reader may see if that was found first.
func TestAnItemEnteredWithItsEarliestVisibleFile(t *testing.T) {
	c := newCopyReach(t)
	seen := map[model.PID]int64{c.primary.FilePID: 2e18, c.copy.FilePID: 1e18}
	c.svc.fileReadHook = func(ctx context.Context, pid model.PID) (*model.File, error) {
		f, err := c.svc.lib.File(ctx, pid)
		if err == nil {
			f.FirstSeen = seen[pid]
		}
		return f, err
	}
	for _, who := range []struct {
		uc   *UserCtx
		want int64
	}{{c.admin, 1e18}, {c.bob, 2e18}} {
		d, err := c.svc.Item(c.ctx, who.uc, itemAPIPID(c.item))
		if err != nil {
			t.Fatal(err)
		}
		if got := d.AddedAt.UnixNano(); got != who.want {
			t.Errorf("%s: added at %d, want %d", who.uc.ID, got, who.want)
		}
	}
}
