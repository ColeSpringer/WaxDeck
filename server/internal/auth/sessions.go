package auth

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"slices"
	"sync"
	"time"

	"github.com/oklog/ulid/v2"

	"github.com/colespringer/waxdeck/server/internal/db"
)

// Session lifetimes. Both slide: every touched request pushes expiry
// out to a full TTL again, so an active device never re-authenticates
// while an abandoned one ages out.
const (
	webSessionTTL    = 14 * 24 * time.Hour
	deviceSessionTTL = 90 * 24 * time.Hour
	// touchInterval coalesces last-seen writes: a session row is touched
	// at most this often, never per request.
	touchInterval = 5 * time.Minute
	// rotateOverlap keeps the pre-rotation token valid briefly so requests
	// already in flight when the client rotated do not 401.
	rotateOverlap = 30 * time.Second
)

// Principal is the authenticated caller: the account plus the session
// that authenticated it and how the credential arrived (cookie-borne
// credentials need CSRF proof on mutations, header-borne ones do not).
type Principal struct {
	User       *db.User
	Session    *db.Session
	FromCookie bool
}

// IsAdmin reports whether the principal holds the admin role.
func (p *Principal) IsAdmin() bool {
	for _, r := range p.User.Roles {
		if r == "admin" {
			return true
		}
	}
	return false
}

// DefaultSessionCap is how many live sessions one account may hold
// unless the operator says otherwise: generous, since every browser tab
// that signs in and every device holds one.
const DefaultSessionCap = 250

// Sessions manages opaque session tokens over the store: creation,
// lookup with sliding expiry, rotation, and revocation. Tokens are
// 32-byte random values stored only as SHA-256 hashes; a database leak
// yields no usable credentials.
type Sessions struct {
	store *db.DB
	cap   int

	mu       sync.Mutex
	onRevoke []func(RevokeEvent)
}

// NewSessions builds the session manager.
func NewSessions(store *db.DB) *Sessions {
	return &Sessions{store: store, cap: DefaultSessionCap}
}

// LimitPerAccount sets how many live sessions one account may hold; a
// sign-in past it ends the account's least recently used session. Zero
// or less keeps the default.
func (s *Sessions) LimitPerAccount(n int) {
	if n > 0 {
		s.cap = n
	}
}

// RevokeEvent names what a revoke ended: one session (SessionID), or
// every session of an account but KeepID (UserID, KeepID "" for all).
type RevokeEvent struct {
	SessionID string
	UserID    string
	KeepID    string
}

// OnRevoke registers a listener every revoke through this manager calls,
// synchronously, after the rows are gone. What a session opened (a
// socket) outlives its row, and this is how it hears.
func (s *Sessions) OnRevoke(fn func(RevokeEvent)) {
	s.mu.Lock()
	s.onRevoke = append(s.onRevoke, fn)
	s.mu.Unlock()
}

func (s *Sessions) notify(e RevokeEvent) {
	s.mu.Lock()
	listeners := slices.Clone(s.onRevoke)
	s.mu.Unlock()
	for _, fn := range listeners {
		fn(e)
	}
}

// Alive reports whether a session can still authenticate: its row is
// there and unexpired, and its account exists and may sign in. The
// backstop for whatever a revoke did not reach (an expiry, a row deleted
// behind the manager's back). An error is a read that failed, which says
// nothing about the session either way.
func (s *Sessions) Alive(ctx context.Context, sessionID string) (bool, error) {
	if sessionID == "" {
		return false, nil
	}
	sess, err := s.store.SessionByID(ctx, sessionID)
	if errors.Is(err, db.ErrNotFound) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	if !time.Now().Before(sess.ExpiresAt) {
		return false, nil
	}
	user, err := s.store.UserByID(ctx, sess.UserID)
	if errors.Is(err, db.ErrNotFound) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return !user.Disabled && !user.Pending, nil
}

// Created is a freshly established session with its one-time-visible
// secrets.
type Created struct {
	Session   *db.Session
	Token     string
	CSRFToken string
}

// Create establishes a session for the account. kind is "web" or
// "device"; deviceName and client label it in the device list.
func (s *Sessions) Create(ctx context.Context, userID, kind, deviceName, client string) (*Created, error) {
	token, hash, err := newToken()
	if err != nil {
		return nil, err
	}
	csrf, _, err := newToken()
	if err != nil {
		return nil, err
	}
	ttl := webSessionTTL
	if kind == "device" {
		ttl = deviceSessionTTL
	}
	sess := &db.Session{
		ID:         "se-" + ulid.Make().String(),
		UserID:     userID,
		Kind:       kind,
		TokenHash:  hash,
		CSRFToken:  csrf,
		DeviceName: deviceName,
		Client:     client,
		ExpiresAt:  time.Now().Add(ttl),
	}
	if err := s.store.CreateSession(ctx, sess); err != nil {
		return nil, fmt.Errorf("auth: creating session: %w", err)
	}
	s.enforceCap(ctx, userID, sess.ID)
	return &Created{Session: sess, Token: token, CSRFToken: csrf}, nil
}

// enforceCap ends the account's least recently used sessions past the
// cap, sparing the one just made. Best effort: a sign-in never fails
// over the housekeeping behind it.
func (s *Sessions) enforceCap(ctx context.Context, userID, keepID string) {
	live, err := s.ListForUser(ctx, userID)
	if err != nil || len(live) <= s.cap {
		return
	}
	slices.SortFunc(live, func(a, b *db.Session) int { return a.LastSeenAt.Compare(b.LastSeenAt) })
	for _, sess := range live[:len(live)-s.cap] {
		if sess.ID == keepID {
			continue
		}
		if err := s.Revoke(ctx, sess.ID); err != nil && !errors.Is(err, db.ErrNotFound) {
			return
		}
	}
}

// Lookup resolves a presented token to its principal, enforcing expiry,
// the rotation overlap, and the account's enabled state. It slides the
// session's expiry (coalesced) as a side effect. Misses of every flavor
// return nil, nil: the caller treats them all as "not authenticated"
// without distinguishing why.
func (s *Sessions) Lookup(ctx context.Context, token string) (*Principal, error) {
	hash := tokenHash(token)
	sess, err := s.store.SessionByTokenHash(ctx, hash)
	if err != nil {
		if errors.Is(err, db.ErrNotFound) {
			return nil, nil
		}
		return nil, err
	}
	now := time.Now()
	if now.After(sess.ExpiresAt) {
		return nil, nil
	}
	// A pre-rotation token is honored only inside the overlap window.
	if sess.PrevTokenHash != nil {
		if bytes.Equal(hash, sess.PrevTokenHash) {
			if sess.RotatedAt.IsZero() || now.After(sess.RotatedAt.Add(rotateOverlap)) {
				return nil, nil
			}
		} else if !sess.RotatedAt.IsZero() && now.After(sess.RotatedAt.Add(rotateOverlap)) {
			// Overlap over: retire the old hash so it stops matching lookups.
			if err := s.store.ClearPrevToken(ctx, sess.ID); err != nil {
				return nil, err
			}
		}
	}
	user, err := s.store.UserByID(ctx, sess.UserID)
	if err != nil {
		if errors.Is(err, db.ErrNotFound) {
			return nil, nil
		}
		return nil, err
	}
	if user.Disabled {
		return nil, nil
	}
	if now.Sub(sess.LastSeenAt) > touchInterval {
		ttl := webSessionTTL
		if sess.Kind == "device" {
			ttl = deviceSessionTTL
		}
		if err := s.store.TouchSession(ctx, sess.ID, now.Add(ttl)); err != nil {
			return nil, err
		}
	}
	return &Principal{User: user, Session: sess}, nil
}

// Rotate replaces the session's token, keeping the old one valid for
// the overlap window. Returns the new token.
func (s *Sessions) Rotate(ctx context.Context, sess *db.Session) (string, error) {
	token, hash, err := newToken()
	if err != nil {
		return "", err
	}
	ttl := webSessionTTL
	if sess.Kind == "device" {
		ttl = deviceSessionTTL
	}
	if err := s.store.RotateSessionToken(ctx, sess.ID, hash, time.Now().Add(ttl)); err != nil {
		return "", fmt.Errorf("auth: rotating session: %w", err)
	}
	return token, nil
}

// Revoke ends one session immediately. Listeners hear it even when the
// row was already gone.
func (s *Sessions) Revoke(ctx context.Context, sessionID string) error {
	err := s.store.DeleteSession(ctx, sessionID)
	if err == nil || errors.Is(err, db.ErrNotFound) {
		s.notify(RevokeEvent{SessionID: sessionID})
	}
	return err
}

// Rename relabels one session in the device list. The caller validates
// the name; this is the store passthrough.
func (s *Sessions) Rename(ctx context.Context, sessionID, deviceName string) error {
	return s.store.RenameSession(ctx, sessionID, deviceName)
}

// ListForUser returns the account's live sessions, newest first.
// Expired rows awaiting the janitor are filtered out.
func (s *Sessions) ListForUser(ctx context.Context, userID string) ([]*db.Session, error) {
	all, err := s.store.SessionsByUser(ctx, userID)
	if err != nil {
		return nil, err
	}
	now := time.Now()
	live := all[:0]
	for _, sess := range all {
		if now.Before(sess.ExpiresAt) {
			live = append(live, sess)
		}
	}
	return live, nil
}

// Get fetches one session row.
func (s *Sessions) Get(ctx context.Context, sessionID string) (*db.Session, error) {
	return s.store.SessionByID(ctx, sessionID)
}

// RevokeAllForUser ends every session of the account except keepID
// (pass "" to keep none).
func (s *Sessions) RevokeAllForUser(ctx context.Context, userID, keepID string) error {
	if err := s.store.DeleteUserSessions(ctx, userID, keepID); err != nil {
		return err
	}
	s.notify(RevokeEvent{UserID: userID, KeepID: keepID})
	return nil
}

// newToken mints an opaque credential and its storage hash.
func newToken() (token string, hash []byte, err error) {
	buf := make([]byte, 32)
	if _, err := rand.Read(buf); err != nil {
		return "", nil, fmt.Errorf("auth: reading token entropy: %w", err)
	}
	token = base64.RawURLEncoding.EncodeToString(buf)
	return token, tokenHash(token), nil
}

// tokenHash is the storage form of a token.
func tokenHash(token string) []byte {
	sum := sha256.Sum256([]byte(token))
	return sum[:]
}

// TokenHash exposes the storage hash derivation for callers that store
// their own one-time codes (the OIDC completion path).
func TokenHash(token string) []byte { return tokenHash(token) }

// NewOpaqueToken mints a random URL-safe token with its storage hash
// (the OIDC one-time completion codes ride this).
func NewOpaqueToken() (token string, hash []byte, err error) { return newToken() }
