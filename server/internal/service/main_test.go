package service

import (
	"os"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/auth"
)

func TestMain(m *testing.M) {
	// The tests here mint accounts freely through CreateAccount; at
	// production argon2 cost each one is seconds of memory-hard hashing
	// under the race detector, and none of these tests are about KDF
	// strength.
	auth.WeakenKDFForTesting()
	os.Exit(m.Run())
}
