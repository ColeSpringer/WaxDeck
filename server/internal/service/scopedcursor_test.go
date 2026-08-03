package service

import "testing"

// The version byte is a guard rail for a change that has not happened
// yet, so what it must prove is the behaviour on the day it does: a
// token from a retired version reaches the catalog instead of being read
// as a scope mismatch, and one from a version nobody retired is still
// refused outright.
//
// Not parallel: the subtests stub the package-level retired-version set.
func TestScopedCursorVersions(t *testing.T) {
	const scope = "abcd1234"
	mint := func(version, atScope, token string) string {
		return encodeOpaqueCursor(version + "|" + atScope + "|" + token)
	}

	t.Run("current version, right scope", func(t *testing.T) {
		got, err := decodeScopedCursor(encodeScopedCursor(scope, "token"), scope)
		if err != nil {
			t.Fatalf("decoding a cursor this build minted: %v", err)
		}
		if got != "token" {
			t.Errorf("token = %q, want the catalog's own", got)
		}
	})

	t.Run("current version, wrong scope", func(t *testing.T) {
		_, err := decodeScopedCursor(encodeScopedCursor(scope, "token"), "other")
		if KindOf(err) != KindInvalid {
			t.Fatalf("reusing a cursor under another scope = %v, want invalid", err)
		}
	})

	t.Run("unretired old version", func(t *testing.T) {
		// Nothing says what s0's scope hash covered, so the only honest
		// answer is a refusal.
		_, err := decodeScopedCursor(mint("s0", scope, "token"), scope)
		if KindOf(err) != KindInvalid {
			t.Fatalf("an unknown version = %v, want invalid", err)
		}
	})

	t.Run("retired old version", func(t *testing.T) {
		oldCursorVersions["s0"] = true
		defer delete(oldCursorVersions, "s0")

		// Whatever scope it was minted under, retired means the hash is
		// not this build's to compare, so the token goes through.
		for _, at := range []string{scope, "some-other-scope"} {
			got, err := decodeScopedCursor(mint("s0", at, "token"), scope)
			if err != nil {
				t.Fatalf("a retired-version cursor at %q: %v", at, err)
			}
			if got != "token" {
				t.Errorf("token = %q, want it handed to the catalog", got)
			}
		}
	})

	t.Run("malformed", func(t *testing.T) {
		for _, bad := range []string{"not base64 at all!", encodeOpaqueCursor("s1|only-two")} {
			if _, err := decodeScopedCursor(bad, scope); KindOf(err) != KindInvalid {
				t.Errorf("decoding %q = %v, want invalid", bad, err)
			}
		}
	})

	t.Run("empty is the first page", func(t *testing.T) {
		got, err := decodeScopedCursor("", scope)
		if err != nil || got != "" {
			t.Fatalf("empty cursor = (%q, %v), want the head", got, err)
		}
	})
}
