package auth

import (
	"testing"
	"time"
)

// The policy these tests pin is a product decision rather than an
// implementation detail: it is what a household actually feels when
// several people sign in or sign up at once. It had no test, which is
// how the shape of the ladder came to be something you had to read the
// code to learn - and the `now` seam exists for exactly this.

func newAt(t time.Time) (*RateLimiter, *time.Time) {
	clock := t
	l := &RateLimiter{m: map[string]*failureState{}, now: func() time.Time { return clock }}
	return l, &clock
}

// The first freeAttempts cost nothing, and after them the wait doubles
// from baseBackoff. Walked the way a handler walks it: ask Allowed, and
// burn one only when it says yes.
func TestBackoffLadder(t *testing.T) {
	l, clock := newAt(time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC))
	const key = "signup-ip:198.51.100.7"

	want := []time.Duration{
		0, 0, 0, 0, 0, // freeAttempts, immediate
		30 * time.Second,
		time.Minute,
		2 * time.Minute,
		4 * time.Minute,
		8 * time.Minute,
		// By here the elapsed total has passed failureWindow, so the
		// counter restarts and the next attempts are free again. The
		// ladder never reaches maxBackoff on a steady drip; only a
		// caller hammering inside one window gets there.
		0,
		0,
	}
	for i, expect := range want {
		waited := time.Duration(0)
		for !l.Allowed(key) {
			*clock = clock.Add(time.Second)
			waited += time.Second
			if waited > 30*time.Minute {
				t.Fatalf("attempt %d was never allowed", i+1)
			}
		}
		if waited != expect {
			t.Errorf("attempt %d waited %v, want %v", i+1, waited, expect)
		}
		l.Failure(key)
	}
}

// Idling out the window returns a key to free, which is what stops a
// burst from costing anything an hour later.
func TestWindowReset(t *testing.T) {
	l, clock := newAt(time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC))
	const key = "login-ip:198.51.100.7"

	for range freeAttempts {
		l.Failure(key)
	}
	if l.Allowed(key) {
		t.Fatal("the key should be locked after freeAttempts failures")
	}
	*clock = clock.Add(failureWindow + time.Minute)
	if !l.Allowed(key) {
		t.Fatal("the key should be free again once the window has lapsed")
	}
	for range freeAttempts - 1 {
		l.Failure(key)
		if !l.Allowed(key) {
			t.Fatal("the counter should have restarted, not resumed")
		}
	}
}

// One success releases the key. This is the login path's own valve, and
// it is why a mistyped password strands nobody: the next correct one
// clears the address for everyone sharing it. Signup has no equivalent -
// it burns on every outcome by design - so its budget comes back only
// with the window.
func TestSuccessClears(t *testing.T) {
	l, clock := newAt(time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC))
	const key = "login-ip:198.51.100.7"

	for range freeAttempts {
		l.Failure(key)
	}
	if l.Allowed(key) {
		t.Fatal("the key should be locked after freeAttempts failures")
	}
	l.Success(key)
	if !l.Allowed(key) {
		t.Fatal("a success should release the key immediately")
	}
	*clock = clock.Add(time.Second)
	if !l.Allowed(key) {
		t.Fatal("and it should stay released")
	}
}

// Keys are independent: one guessed account never locks another, and one
// noisy address never locks a second one.
func TestKeysAreIndependent(t *testing.T) {
	l, _ := newAt(time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC))
	for range freeAttempts {
		l.Failure("login-acct:alice")
	}
	if l.Allowed("login-acct:alice") {
		t.Fatal("alice should be locked")
	}
	if !l.Allowed("login-acct:bob") {
		t.Fatal("bob should be untouched by alice's failures")
	}
	if !l.Allowed("login-ip:198.51.100.7") {
		t.Fatal("the address key should be untouched by an account key")
	}
}
