package auth

import (
	"strings"
	"testing"
	"time"
)

// TestProductionKDFCost pins what a shipped server hashes with. The
// weakening knob exists so test binaries do not spend seconds per
// account on memory-hard work; nothing else may move these numbers, and
// a hash records them, so a leak would be silent and permanent - every
// account created under weak parameters keeps them until its password
// changes.
func TestProductionKDFCost(t *testing.T) {
	if got := currentParams(); got != (argonParams{memory: 64 * 1024, time: 3, threads: 1}) {
		t.Fatalf("production params = %+v, want m=65536,t=3,p=1", got)
	}
	hash, err := HashPassword("correct horse battery staple")
	if err != nil {
		t.Fatal(err)
	}
	// The encoded cost, which is the half that outlives the process.
	if !strings.Contains(hash, "$m=65536,t=3,p=1$") {
		t.Fatalf("hash = %q, want the production cost encoded in it", hash)
	}
}

func TestPasswordHashRoundTrip(t *testing.T) {
	hash, err := HashPassword("correct horse battery staple")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(hash, "$argon2id$") {
		t.Fatalf("hash = %q, want argon2id PHC string", hash)
	}
	if !VerifyPassword(hash, "correct horse battery staple") {
		t.Fatal("correct password does not verify")
	}
	if VerifyPassword(hash, "wrong password") {
		t.Fatal("wrong password verifies")
	}
	// Same password, new salt, different hash.
	hash2, err := HashPassword("correct horse battery staple")
	if err != nil {
		t.Fatal(err)
	}
	if hash == hash2 {
		t.Fatal("two hashes of the same password are identical (salt reuse)")
	}
}

func TestVerifyPasswordMalformedHashes(t *testing.T) {
	for _, h := range []string{
		"",
		"plaintext",
		"$argon2id$",
		"$argon2i$v=19$m=65536,t=3,p=1$c2FsdA$aGFzaA",
		"$argon2id$v=19$m=0,t=0,p=0$c2FsdA$aGFzaA",
		"$argon2id$v=19$m=65536,t=3,p=1$!!$aGFzaA",
	} {
		if VerifyPassword(h, "anything") {
			t.Fatalf("malformed hash %q verified", h)
		}
	}
}

func TestRateLimiterLocksOutAndRecovers(t *testing.T) {
	l := NewRateLimiter()
	now := time.Now()
	l.now = func() time.Time { return now }

	key := "login-ip:203.0.113.7"
	for range freeAttempts - 1 {
		l.Failure(key)
		if !l.Allowed(key) {
			t.Fatal("locked out before the free attempts were spent")
		}
	}
	l.Failure(key)
	if l.Allowed(key) {
		t.Fatal("not locked out after the free attempts")
	}

	// The backoff lapses.
	now = now.Add(baseBackoff + time.Second)
	if !l.Allowed(key) {
		t.Fatal("still locked out after the backoff lapsed")
	}

	// Success clears everything.
	l.Success(key)
	if !l.Allowed(key) {
		t.Fatal("not allowed after success")
	}

	// Isolation: another key is untouched by this key's failures.
	for range freeAttempts + 3 {
		l.Failure(key)
	}
	if l.Allowed(key) {
		t.Fatal("expected lockout")
	}
	if !l.Allowed("login-ip:198.51.100.9") {
		t.Fatal("an unrelated key was locked out")
	}
}

func TestRateLimiterWindowExpiry(t *testing.T) {
	l := NewRateLimiter()
	now := time.Now()
	l.now = func() time.Time { return now }

	key := "login-acct:frodo"
	for range freeAttempts {
		l.Failure(key)
	}
	if l.Allowed(key) {
		t.Fatal("expected lockout")
	}
	// After the window and backoff both lapse, the slate is clean.
	now = now.Add(failureWindow + maxBackoff + time.Second)
	if !l.Allowed(key) {
		t.Fatal("stale failure state still locking out")
	}
}
