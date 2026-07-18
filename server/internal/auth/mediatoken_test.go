package auth

import (
	"strings"
	"testing"
	"time"
)

func TestMediaTokenRoundTrip(t *testing.T) {
	m := NewMediaTokens([]byte("test-secret-test-secret-test-sec"), time.Minute)
	token, exp := m.Mint("us-1", "tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE")
	if time.Until(exp) <= 0 {
		t.Fatal("token already expired at mint")
	}
	user, err := m.Verify(token, "tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE")
	if err != nil || user != "us-1" {
		t.Fatalf("Verify = (%q, %v)", user, err)
	}
}

func TestMediaTokenRejections(t *testing.T) {
	m := NewMediaTokens([]byte("test-secret-test-secret-test-sec"), time.Minute)
	token, _ := m.Mint("us-1", "tr-A")

	cases := map[string]struct{ token, pid string }{
		"wrong pid":     {token, "tr-B"},
		"empty token":   {"", "tr-A"},
		"garbage":       {"not.a.token", "tr-A"},
		"no separator":  {strings.ReplaceAll(token, ".", ""), "tr-A"},
		"tampered body": {"x" + token, "tr-A"},
	}
	for name, c := range cases {
		if _, err := m.Verify(c.token, c.pid); err == nil {
			t.Errorf("%s: Verify accepted", name)
		}
	}

	// A token from a different key never verifies.
	other := NewMediaTokens([]byte("other-secret-other-secret-other!"), time.Minute)
	foreign, _ := other.Mint("us-1", "tr-A")
	if _, err := m.Verify(foreign, "tr-A"); err == nil {
		t.Error("cross-key token accepted")
	}
}

func TestMediaTokenExpiry(t *testing.T) {
	m := NewMediaTokens([]byte("test-secret-test-secret-test-sec"), -1)
	// ttl <= 0 selects the default; build an expired token by hand
	// through a second instance with a tiny ttl.
	short := &MediaTokens{key: m.key, ttl: -time.Minute}
	token, _ := short.Mint("us-1", "tr-A")
	if _, err := m.Verify(token, "tr-A"); err == nil {
		t.Error("expired token accepted")
	}
}
