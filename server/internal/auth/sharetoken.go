package auth

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"strings"
)

// ShareTokens mints and verifies public share capability tokens. A
// token is the share's ULID plus an HMAC over it, so the database
// stores no share secrets: the owner's listing recomputes the URL any
// time, revocation is row state checked after verification, and a
// leaked database exposes no working links. Unlike media tokens these
// carry no expiry of their own; the share row owns the lifetime.
type ShareTokens struct {
	key []byte
}

// NewShareTokens derives the share-token subkey from the server secret.
func NewShareTokens(secret []byte) *ShareTokens {
	mac := hmac.New(sha256.New, secret)
	mac.Write([]byte("waxdeck-share-token-v1"))
	return &ShareTokens{key: mac.Sum(nil)}
}

// shareSigBytes truncates the HMAC to 128 bits: standard for
// capability URLs, unforgeable in practice, and keeps links short.
const shareSigBytes = 16

// Mint returns the capability token for a share id.
func (s *ShareTokens) Mint(shareID string) string {
	return shareID + "." + base64.RawURLEncoding.EncodeToString(s.sign(shareID))
}

// Verify checks a token and returns the share id it names.
func (s *ShareTokens) Verify(token string) (shareID string, err error) {
	id, sigB64, ok := strings.Cut(token, ".")
	if !ok || id == "" {
		return "", ErrBadToken
	}
	sig, err := base64.RawURLEncoding.DecodeString(sigB64)
	if err != nil {
		return "", ErrBadToken
	}
	if !hmac.Equal(sig, s.sign(id)) {
		return "", ErrBadToken
	}
	return id, nil
}

func (s *ShareTokens) sign(id string) []byte {
	mac := hmac.New(sha256.New, s.key)
	mac.Write([]byte(id))
	return mac.Sum(nil)[:shareSigBytes]
}
