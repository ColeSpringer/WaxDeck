package auth

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"flag"
	"fmt"
	"strings"
	"sync/atomic"

	"golang.org/x/crypto/argon2"
)

const (
	argonKeyLen  = 32
	argonSaltLen = 16
)

// productionParams is what a shipped server derives new hashes with:
// RFC 9106's second recommended option (64 MiB, t=3, p=1 is the first;
// this trades one lane and more passes for a memory footprint a
// Raspberry-Pi-class host can absorb under a burst of concurrent
// logins, with the login rate limiter bounding the worst case).
var productionParams = argonParams{memory: 64 * 1024, time: 3, threads: 1}

// hashParams is the override WeakenKDFForTesting installs, nil until
// it does. Atomic rather than a plain var: the tests that weaken it run
// in parallel, so a write racing the reads in every concurrent
// HashPassword would be a data race whatever the ordering happened to
// be. Verification honors whatever parameters a stored hash carries, so
// nothing here can strand a hash.
var hashParams atomic.Pointer[argonParams]

func currentParams() argonParams {
	if p := hashParams.Load(); p != nil {
		return *p
	}
	return productionParams
}

// WeakenKDFForTesting drops new hashes to argon2id's cheapest
// parameters, for test suites that mint accounts by the hundred and
// would otherwise spend seconds of memory-hard hashing per signup
// under the race detector. Call it from TestMain.
//
// The guard reads the test flag set rather than testing.Testing():
// importing testing here would link the test framework and the runtime
// tracer into the shipped server binary, which is the one host these
// parameters were chosen for. `flag` is already linked - the command
// parses its own - so this costs the binary nothing.
func WeakenKDFForTesting() {
	if flag.Lookup("test.v") == nil {
		panic("auth: WeakenKDFForTesting called outside a test binary")
	}
	hashParams.Store(&argonParams{memory: 8, time: 1, threads: 1})
}

// HashPassword derives an argon2id hash in PHC string format.
func HashPassword(password string) (string, error) {
	salt := make([]byte, argonSaltLen)
	if _, err := rand.Read(salt); err != nil {
		return "", fmt.Errorf("auth: reading salt: %w", err)
	}
	p := currentParams()
	key := argon2.IDKey([]byte(password), salt, p.time, p.memory, p.threads, argonKeyLen)
	return fmt.Sprintf("$argon2id$v=%d$m=%d,t=%d,p=%d$%s$%s",
		argon2.Version, p.memory, p.time, p.threads,
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
