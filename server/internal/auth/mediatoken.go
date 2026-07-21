package auth

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"
)

// MediaTokens mints and verifies the short-TTL query tokens that
// authenticate media fetches. A token binds user, item, and expiry; the
// server derives every stream parameter itself on each fetch, so the
// token authorizes nothing beyond "this user may hear this item until
// exp".
type MediaTokens struct {
	key []byte
	ttl time.Duration
}

// DefaultMediaTokenTTL bounds how long a minted stream URL stays
// playable. Clients re-request play-info on expiry.
const DefaultMediaTokenTTL = 15 * time.Minute

// ErrBadToken reports a token that failed verification for any reason
// (malformed, forged, expired). Callers treat all cases identically.
var ErrBadToken = errors.New("auth: invalid media token")

// NewMediaTokens derives the media-token subkey from the server secret.
// ttl of 0 selects the default.
func NewMediaTokens(secret []byte, ttl time.Duration) *MediaTokens {
	if ttl <= 0 {
		ttl = DefaultMediaTokenTTL
	}
	mac := hmac.New(sha256.New, secret)
	mac.Write([]byte("waxdeck-media-token-v1"))
	return &MediaTokens{key: mac.Sum(nil), ttl: ttl}
}

// Mint returns a token for user and pid, and its expiry time.
func (m *MediaTokens) Mint(user, pid string) (token string, exp time.Time) {
	return m.MintFor(user, pid, m.ttl)
}

// MintFor mints with an explicit lifetime. Long-running deliveries
// (queue timelines, whole-queue casts) size the token to the content
// so playback never dies mid-listen; ttl of 0 selects the default.
func (m *MediaTokens) MintFor(user, pid string, ttl time.Duration) (token string, exp time.Time) {
	if ttl <= 0 {
		ttl = m.ttl
	}
	exp = time.Now().Add(ttl).UTC().Truncate(time.Second)
	payload := payloadString(user, pid, exp.Unix())
	sig := m.sign(payload)
	enc := base64.RawURLEncoding
	return enc.EncodeToString([]byte(payload)) + "." + enc.EncodeToString(sig), exp
}

// Verify checks token against pid and returns the user it was minted
// for. The pid must match the one the token binds: a valid token for
// one item authorizes nothing else.
func (m *MediaTokens) Verify(token, pid string) (user string, err error) {
	enc := base64.RawURLEncoding
	payloadB64, sigB64, ok := strings.Cut(token, ".")
	if !ok {
		return "", ErrBadToken
	}
	payload, err := enc.DecodeString(payloadB64)
	if err != nil {
		return "", ErrBadToken
	}
	sig, err := enc.DecodeString(sigB64)
	if err != nil {
		return "", ErrBadToken
	}
	if !hmac.Equal(sig, m.sign(string(payload))) {
		return "", ErrBadToken
	}
	parts := strings.Split(string(payload), "|")
	if len(parts) != 4 || parts[0] != "v1" {
		return "", ErrBadToken
	}
	expUnix, err := strconv.ParseInt(parts[3], 10, 64)
	if err != nil || time.Now().Unix() > expUnix {
		return "", ErrBadToken
	}
	if parts[2] != pid {
		return "", ErrBadToken
	}
	return parts[1], nil
}

// VerifyAny validates a token without a pid expectation and returns
// both the user and the pid it binds. For fetch surfaces where the
// resource identity lives inside the token itself (HLS child fetches
// name segments, not pids); callers must still check the returned pid
// names something they are willing to serve.
func (m *MediaTokens) VerifyAny(token string) (user, pid string, err error) {
	enc := base64.RawURLEncoding
	payloadB64, sigB64, ok := strings.Cut(token, ".")
	if !ok {
		return "", "", ErrBadToken
	}
	payload, err := enc.DecodeString(payloadB64)
	if err != nil {
		return "", "", ErrBadToken
	}
	sig, err := enc.DecodeString(sigB64)
	if err != nil {
		return "", "", ErrBadToken
	}
	if !hmac.Equal(sig, m.sign(string(payload))) {
		return "", "", ErrBadToken
	}
	parts := strings.Split(string(payload), "|")
	if len(parts) != 4 || parts[0] != "v1" {
		return "", "", ErrBadToken
	}
	expUnix, err := strconv.ParseInt(parts[3], 10, 64)
	if err != nil || time.Now().Unix() > expUnix {
		return "", "", ErrBadToken
	}
	return parts[1], parts[2], nil
}

// payloadString builds the signed payload. PIDs and user IDs are ULID
// derived and never contain the separator.
func payloadString(user, pid string, expUnix int64) string {
	return fmt.Sprintf("v1|%s|%s|%d", user, pid, expUnix)
}

func (m *MediaTokens) sign(payload string) []byte {
	mac := hmac.New(sha256.New, m.key)
	mac.Write([]byte(payload))
	return mac.Sum(nil)
}
