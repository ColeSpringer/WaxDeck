package auth

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
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

// Sessions manages opaque session tokens over the store: creation,
// lookup with sliding expiry, rotation, and revocation. Tokens are
// 32-byte random values stored only as SHA-256 hashes; a database leak
// yields no usable credentials.
type Sessions struct {
	store *db.DB
}

// NewSessions builds the session manager.
func NewSessions(store *db.DB) *Sessions {
	return &Sessions{store: store}
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
	return &Created{Session: sess, Token: token, CSRFToken: csrf}, nil
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

// Revoke ends one session immediately.
func (s *Sessions) Revoke(ctx context.Context, sessionID string) error {
	return s.store.DeleteSession(ctx, sessionID)
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
	return s.store.DeleteUserSessions(ctx, userID, keepID)
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
