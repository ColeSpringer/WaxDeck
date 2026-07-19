package auth

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"errors"
	"fmt"
)

// Sealer encrypts small secrets for at-rest storage in waxdeck.db,
// for credentials that must be recoverable (the Subsonic token scheme
// verifies md5(password+salt), so the server has to hold the password
// itself). AES-256-GCM under a purpose-bound subkey of the server
// secret; the nonce rides in front of the ciphertext.
type Sealer struct {
	aead cipher.AEAD
}

// NewSealer derives the sealing subkey from the server secret. The
// purpose string namespaces subkeys so no two subsystems share one.
func NewSealer(secret []byte, purpose string) (*Sealer, error) {
	mac := hmac.New(sha256.New, secret)
	mac.Write([]byte(purpose))
	block, err := aes.NewCipher(mac.Sum(nil))
	if err != nil {
		return nil, fmt.Errorf("auth: sealing cipher: %w", err)
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("auth: sealing cipher: %w", err)
	}
	return &Sealer{aead: aead}, nil
}

// Seal encrypts plaintext.
func (s *Sealer) Seal(plaintext []byte) ([]byte, error) {
	nonce := make([]byte, s.aead.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return nil, fmt.Errorf("auth: sealing: %w", err)
	}
	return s.aead.Seal(nonce, nonce, plaintext, nil), nil
}

// Open decrypts a sealed value.
func (s *Sealer) Open(sealed []byte) ([]byte, error) {
	if len(sealed) < s.aead.NonceSize() {
		return nil, errors.New("auth: sealed value too short")
	}
	nonce, ct := sealed[:s.aead.NonceSize()], sealed[s.aead.NonceSize():]
	pt, err := s.aead.Open(nil, nonce, ct, nil)
	if err != nil {
		return nil, fmt.Errorf("auth: unsealing: %w", err)
	}
	return pt, nil
}

// AADSealer is the Sealer shape for consumers whose envelope binds
// ciphertext to a context string via additional authenticated data:
// the catalog's secret store passes each secret's key as AAD, so a
// sealed value copied onto another key refuses to open. Same
// construction as Sealer (AES-256-GCM under a purpose-bound subkey).
type AADSealer struct {
	aead cipher.AEAD
}

// NewAADSealer derives the sealing subkey from the server secret.
func NewAADSealer(secret []byte, purpose string) (*AADSealer, error) {
	mac := hmac.New(sha256.New, secret)
	mac.Write([]byte(purpose))
	block, err := aes.NewCipher(mac.Sum(nil))
	if err != nil {
		return nil, fmt.Errorf("auth: sealing cipher: %w", err)
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("auth: sealing cipher: %w", err)
	}
	return &AADSealer{aead: aead}, nil
}

// Seal encrypts plaintext bound to aad.
func (s *AADSealer) Seal(aad, plaintext []byte) ([]byte, error) {
	nonce := make([]byte, s.aead.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return nil, fmt.Errorf("auth: sealing: %w", err)
	}
	return s.aead.Seal(nonce, nonce, plaintext, aad), nil
}

// Open decrypts a sealed value bound to aad.
func (s *AADSealer) Open(aad, sealed []byte) ([]byte, error) {
	if len(sealed) < s.aead.NonceSize() {
		return nil, errors.New("auth: sealed value too short")
	}
	nonce, ct := sealed[:s.aead.NonceSize()], sealed[s.aead.NonceSize():]
	pt, err := s.aead.Open(nil, nonce, ct, aad)
	if err != nil {
		return nil, fmt.Errorf("auth: unsealing: %w", err)
	}
	return pt, nil
}

// crockford is the ULID alphabet: unambiguous, case-insensitive,
// double-click selectable.
const crockford = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

// NewAppPasswordSecret mints a generated app password: 26 characters of
// Crockford base32 (130 bits), the documented format.
func NewAppPasswordSecret() (string, error) {
	buf := make([]byte, 26)
	if _, err := rand.Read(buf); err != nil {
		return "", fmt.Errorf("auth: minting app password: %w", err)
	}
	for i, b := range buf {
		buf[i] = crockford[int(b)%len(crockford)]
	}
	return string(buf), nil
}
