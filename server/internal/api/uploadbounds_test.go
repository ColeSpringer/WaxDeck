package api

import (
	"testing"
	"time"
)

// The bucket at the size it ships at, driven on a clock the test holds:
// what matters is that a burst the size of a folder upload passes, that
// a client which never stops asking is eventually refused, and that
// waiting is what gets it back in.
func TestUploadGatePacesOneAccount(t *testing.T) {
	clock := time.Now()
	g := &uploadGate{now: func() time.Time { return clock }}

	for i := range uploadBurst {
		if !g.allow("us-1") {
			t.Fatalf("request %d of the burst was refused", i+1)
		}
	}
	if g.allow("us-1") {
		t.Fatal("the burst was spent and the next request was still allowed")
	}

	// Another account is untouched: the bound is per caller, so one
	// client in a loop never stops anybody else uploading.
	if !g.allow("us-2") {
		t.Fatal("a second account paid for the first one's loop")
	}

	// A second of waiting buys a second's worth back, and no more.
	clock = clock.Add(time.Second)
	for i := range uploadRefill {
		if !g.allow("us-1") {
			t.Fatalf("refilled request %d was refused", i+1)
		}
	}
	if g.allow("us-1") {
		t.Fatal("the refill handed out more than a second's worth")
	}

	// An account away for an hour comes back with a full burst, not an
	// hour of tokens.
	clock = clock.Add(time.Hour)
	for i := range uploadBurst {
		if !g.allow("us-1") {
			t.Fatalf("request %d after a long wait was refused", i+1)
		}
	}
	if g.allow("us-1") {
		t.Fatal("a long wait refilled past the burst")
	}
}
