package auth

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"strings"

	"golang.org/x/crypto/argon2"
)

// Argon2id parameters. RFC 9106's second recommended option (64 MiB,
// t=3, p=1 is the first; this trades one lane and more passes for a
// memory footprint a Raspberry-Pi-class host can absorb under a burst
// of concurrent logins, with the login rate limiter bounding the
// worst case).
const (
	argonTime    = 3
	argonMemory  = 64 * 1024 // KiB
	argonThreads = 1
	argonKeyLen  = 32
	argonSaltLen = 16
)

// HashPassword derives an argon2id hash in PHC string format.
func HashPassword(password string) (string, error) {
	salt := make([]byte, argonSaltLen)
	if _, err := rand.Read(salt); err != nil {
		return "", fmt.Errorf("auth: reading salt: %w", err)
	}
	key := argon2.IDKey([]byte(password), salt, argonTime, argonMemory, argonThreads, argonKeyLen)
	return fmt.Sprintf("$argon2id$v=%d$m=%d,t=%d,p=%d$%s$%s",
		argon2.Version, argonMemory, argonTime, argonThreads,
		base64.RawStdEncoding.EncodeToString(salt),
		base64.RawStdEncoding.EncodeToString(key)), nil
}

// VerifyPassword reports whether password matches the PHC-encoded hash.
// The stored parameters are honored, so hashes survive parameter
// changes. Malformed hashes verify false, never error out to a caller
// that would then have to decide what a broken hash means for a login.
func VerifyPassword(hash, password string) bool {
	params, salt, key, err := parsePHC(hash)
	if err != nil {
		return false
	}
	derived := argon2.IDKey([]byte(password), salt, params.time, params.memory, params.threads, uint32(len(key)))
	return subtle.ConstantTimeCompare(derived, key) == 1
}

type argonParams struct {
	memory  uint32
	time    uint32
	threads uint8
}

func parsePHC(hash string) (argonParams, []byte, []byte, error) {
	parts := strings.Split(hash, "$")
	// "", "argon2id", "v=19", "m=...,t=...,p=...", salt, key
	if len(parts) != 6 || parts[1] != "argon2id" {
		return argonParams{}, nil, nil, errors.New("auth: not an argon2id hash")
	}
	var version int
	if _, err := fmt.Sscanf(parts[2], "v=%d", &version); err != nil || version != argon2.Version {
		return argonParams{}, nil, nil, errors.New("auth: unsupported argon2 version")
	}
	var p argonParams
	if _, err := fmt.Sscanf(parts[3], "m=%d,t=%d,p=%d", &p.memory, &p.time, &p.threads); err != nil {
		return argonParams{}, nil, nil, errors.New("auth: malformed argon2 params")
	}
	if p.memory == 0 || p.time == 0 || p.threads == 0 {
		return argonParams{}, nil, nil, errors.New("auth: degenerate argon2 params")
	}
	salt, err := base64.RawStdEncoding.DecodeString(parts[4])
	if err != nil {
		return argonParams{}, nil, nil, err
	}
	key, err := base64.RawStdEncoding.DecodeString(parts[5])
	if err != nil {
		return argonParams{}, nil, nil, err
	}
	if len(key) == 0 {
		return argonParams{}, nil, nil, errors.New("auth: empty argon2 key")
	}
	return p, salt, key, nil
}
