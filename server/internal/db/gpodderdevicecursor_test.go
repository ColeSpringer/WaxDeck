package db

import "testing"

// A device holds the timestamp its last subscription read was answered:
// zero until it reads, its own and no other's, whatever was answered last
// (lower included), untouched by registering again or being seen, and
// gone with the device.
func TestAGpodderDeviceHoldsItsSubscriptionCursor(t *testing.T) {
	d, ctx := gpodderFixture(t)
	if err := d.CreateUser(ctx, mkUser("us-B", "bob", []string{"user"}), false); err != nil {
		t.Fatal(err)
	}
	register := func(user, id string, at int64) {
		t.Helper()
		if _, err := d.RegisterGpodderDevice(ctx, GpodderDevice{UserID: user, DeviceID: id, CreatedAtNS: at, UpdatedAtNS: at}, 2); err != nil {
			t.Fatal(err)
		}
	}
	cursor := func(user, id string) int64 {
		t.Helper()
		got, err := d.GpodderDeviceCursor(ctx, user, id)
		if err != nil {
			t.Fatalf("reading the cursor of %s/%s: %v", user, id, err)
		}
		return got
	}
	store := func(user, id string, sec int64) {
		t.Helper()
		if err := d.SetGpodderDeviceCursor(ctx, user, id, sec); err != nil {
			t.Fatal(err)
		}
	}
	register("us-A", "phone", 1)
	register("us-A", "tablet", 2)
	register("us-B", "phone", 3)
	if got := cursor("us-A", "phone"); got != 0 {
		t.Errorf("a device that never read holds %d, want 0", got)
	}
	if got := cursor("us-A", "nowhere"); got != 0 {
		t.Errorf("a device nobody registered holds %d, want 0", got)
	}

	store("us-A", "phone", 1000)
	if a, b, c := cursor("us-A", "phone"), cursor("us-A", "tablet"), cursor("us-B", "phone"); a != 1000 || b != 0 || c != 0 {
		t.Errorf("cursors after one device read = %d, %d, %d, want 1000 for that device alone", a, b, c)
	}
	store("us-A", "phone", 400)
	if got := cursor("us-A", "phone"); got != 400 {
		t.Errorf("a read answered at 400 after 1000 left %d, want what was answered last", got)
	}

	store("us-A", "nowhere", 900)
	if ok, err := d.GpodderDeviceExists(ctx, "us-A", "nowhere"); err != nil || ok {
		t.Errorf("storing a cursor for a device nobody registered registered it (%v, %v)", ok, err)
	}
	if got := cursor("us-A", "nowhere"); got != 0 {
		t.Errorf("a device nobody registered holds %d after a store, want 0", got)
	}

	register("us-A", "phone", 5)
	if err := d.SeeGpodderDevice(ctx, "us-A", "phone", 6); err != nil {
		t.Fatal(err)
	}
	if got := cursor("us-A", "phone"); got != 400 {
		t.Errorf("registering again and being seen left %d, want 400 untouched", got)
	}

	// The account is at its two devices: a new one takes the stalest's
	// slot, and a device that comes back starts over.
	if err := d.SeeGpodderDevice(ctx, "us-A", "tablet", 7); err != nil {
		t.Fatal(err)
	}
	register("us-A", "watch", 8)
	if ok, err := d.GpodderDeviceExists(ctx, "us-A", "phone"); err != nil || ok {
		t.Fatalf("the stalest device is still registered (%v, %v)", ok, err)
	}
	register("us-A", "phone", 9)
	if got := cursor("us-A", "phone"); got != 0 {
		t.Errorf("a device registered again after it was removed holds %d, want 0", got)
	}
}
