package db

import "testing"

// What the account was told of a device's failed add is kept by device,
// feed and reason, apart from the inbox, until the prune lets it go.
func TestWhatTheAccountWasToldOfFailedAdds(t *testing.T) {
	d, ctx := gpodderFixture(t)
	gone := GpodderNotice{DeviceID: "phone", FeedKey: "feed:a.example/gone", Reason: "No feed was found at that address."}
	other := GpodderNotice{DeviceID: "tablet", FeedKey: gone.FeedKey, Reason: gone.Reason}
	if err := d.NoteGpodderNotices(ctx, "us-A", []GpodderNotice{gone}, 100); err != nil {
		t.Fatal(err)
	}
	if err := d.ClearNotifications(ctx, "us-A"); err != nil {
		t.Fatal(err)
	}
	said := func(since int64) map[GpodderNotice]bool {
		t.Helper()
		got, err := d.GpodderNoticesSaid(ctx, "us-A", []GpodderNotice{gone, other}, since)
		if err != nil {
			t.Fatal(err)
		}
		return got
	}
	if got := said(100); !got[gone] || got[other] {
		t.Fatalf("said since 100 = %v, want the phone's alone", got)
	}
	if got := said(101); len(got) != 0 {
		t.Fatalf("said since 101 = %v, want nothing", got)
	}
	if err := d.NoteGpodderNotices(ctx, "us-A", []GpodderNotice{gone}, 200); err != nil {
		t.Fatal(err)
	}
	if n, err := d.PruneGpodderNotices(ctx, 150); err != nil || n != 0 {
		t.Fatalf("prune before 150 = %d (%v), want the said-again notice kept", n, err)
	}
	if n, err := d.PruneGpodderNotices(ctx, 201); err != nil || n != 1 {
		t.Fatalf("prune before 201 = %d (%v), want it gone", n, err)
	}
}
