package auth

import (
	"strings"
	"testing"
)

func TestShareTokenRoundTrip(t *testing.T) {
	tokens := NewShareTokens([]byte("0123456789abcdef0123456789abcdef"))
	const shareID = "01JZX5N8QW3F4V9T2B7KDEXAMPLE"
	tok := tokens.Mint(shareID)
	if !strings.HasPrefix(tok, shareID+".") {
		t.Fatalf("token %q does not carry the share id", tok)
	}
	got, err := tokens.Verify(tok)
	if err != nil || got != shareID {
		t.Fatalf("Verify = (%q, %v), want (%q, nil)", got, err, shareID)
	}
	// Minting is deterministic: the owner's listing recomputes the same
	// URL every time.
	if again := tokens.Mint(shareID); again != tok {
		t.Fatalf("second mint = %q, want %q", again, tok)
	}
}

func TestShareTokenTamperRefused(t *testing.T) {
	tokens := NewShareTokens([]byte("0123456789abcdef0123456789abcdef"))
	const shareID = "01JZX5N8QW3F4V9T2B7KDEXAMPLE"
	tok := tokens.Mint(shareID)

	// A flipped signature byte fails verification.
	id, sig, _ := strings.Cut(tok, ".")
	flipped := sig[:len(sig)-1]
	if strings.HasSuffix(sig, "A") {
		flipped += "B"
	} else {
		flipped += "A"
	}
	if _, err := tokens.Verify(id + "." + flipped); err == nil {
		t.Fatal("tampered signature verified")
	}
	// A valid signature over a different id must not transfer.
	other := tokens.Mint("01JZX5N8QW3F4V9T2B7KDOTHER00")
	_, otherSig, _ := strings.Cut(other, ".")
	if _, err := tokens.Verify(shareID + "." + otherSig); err == nil {
		t.Fatal("signature from another share id verified")
	}
	// A token minted under another server key is refused.
	strangers := NewShareTokens([]byte("ffffffffffffffffffffffffffffffff"))
	if _, err := tokens.Verify(strangers.Mint(shareID)); err == nil {
		t.Fatal("token from another key verified")
	}
}

func TestShareTokenGarbageRefused(t *testing.T) {
	tokens := NewShareTokens([]byte("0123456789abcdef0123456789abcdef"))
	for _, bad := range []string{
		"",
		"no-separator",
		"id.%%%not-base64",
		".signature-with-empty-id",
		tokens.Mint(""), // an empty share id never verifies
	} {
		if id, err := tokens.Verify(bad); err == nil {
			t.Errorf("token %q verified as %q, want refusal", bad, id)
		}
	}
}
