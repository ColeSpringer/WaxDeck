package auth

import (
	"sync"
	"time"
)

// Rate-limit policy: after freeAttempts failures within the window, a
// key is locked out for a backoff that doubles per further failure, up
// to maxBackoff. Success clears the key. Keys are caller-chosen
// (source IP, and IP+username), so one guessed account never locks the
// whole server and one noisy address cannot spray the account space.
const (
	freeAttempts  = 5
	failureWindow = 15 * time.Minute
	baseBackoff   = 30 * time.Second
	maxBackoff    = 15 * time.Minute
	// limiterCap bounds the tracked-key map; when exceeded, the oldest
	// expired entries are swept and, if still over, new keys are simply
	// not tracked (fail open: an attacker forcing millions of keys melts
	// the map, not the server).
	limiterCap = 65536
)

type failureState struct {
	failures    int
	windowStart time.Time
	lockedUntil time.Time
}

// RateLimiter tracks authentication failures per key in memory. State
// resets on restart, which is acceptable: the argon2 work factor is the
// floor, this is the ceiling on top of it.
type RateLimiter struct {
	mu  sync.Mutex
	m   map[string]*failureState
	now func() time.Time // test seam
}

// NewRateLimiter builds an empty limiter.
func NewRateLimiter() *RateLimiter {
	return &RateLimiter{m: make(map[string]*failureState), now: time.Now}
}

// Allowed reports whether the key may attempt authentication now.
func (l *RateLimiter) Allowed(key string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	st, ok := l.m[key]
	if !ok {
		return true
	}
	now := l.now()
	if now.Sub(st.windowStart) > failureWindow && now.After(st.lockedUntil) {
		delete(l.m, key)
		return true
	}
	return !now.Before(st.lockedUntil) || st.lockedUntil.IsZero()
}

// Failure records a failed attempt against the key.
func (l *RateLimiter) Failure(key string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := l.now()
	st, ok := l.m[key]
	if !ok || now.Sub(st.windowStart) > failureWindow {
		if !ok {
			if len(l.m) >= limiterCap {
				l.sweepLocked(now)
				if len(l.m) >= limiterCap {
					return
				}
			}
			st = &failureState{}
			l.m[key] = st
		}
		st.failures = 0
		st.windowStart = now
		st.lockedUntil = time.Time{}
	}
	st.failures++
	if st.failures >= freeAttempts {
		backoff := maxBackoff
		// Cap the exponent before shifting; a large shift would wrap.
		if extra := st.failures - freeAttempts; extra < 10 {
			if b := baseBackoff << extra; b < maxBackoff {
				backoff = b
			}
		}
		st.lockedUntil = now.Add(backoff)
	}
}

// Success clears the key's failure state.
func (l *RateLimiter) Success(key string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	delete(l.m, key)
}

// sweepLocked drops entries whose window and lockout both lapsed.
// Caller holds the mutex.
func (l *RateLimiter) sweepLocked(now time.Time) {
	for k, st := range l.m {
		if now.Sub(st.windowStart) > failureWindow && now.After(st.lockedUntil) {
			delete(l.m, k)
		}
	}
}
