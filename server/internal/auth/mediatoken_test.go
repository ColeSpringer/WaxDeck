package auth

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"strings"
	"testing"
	"time"
)

const testMediaSecret = "test-secret-test-secret-test-sec"

func streamClaims() MediaClaims {
	return MediaClaims{
		User: "us-1", Cred: "se:se-01JZX5N8QW3F4V9T2B7KDEXAMPL", Purpose: PurposeStream,
		PID: "tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE", Shape: "br=64&fmt=opus",
	}
}

func streamWant() MediaWant {
	return MediaWant{
		Purposes: []string{PurposeStream}, PID: "tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE", Shape: "br=64&fmt=opus",
	}
}

func TestMediaTokenRoundTrip(t *testing.T) {
	m := NewMediaTokens([]byte(testMediaSecret), time.Minute)
	token, exp := m.MintFor(streamClaims(), 0)
	if time.Until(exp) <= 0 {
		t.Fatal("token already expired at mint")
	}
	got, err := m.Verify(token, streamWant())
	if err != nil {
		t.Fatal(err)
	}
	if !got.Exp.Equal(exp) {
		t.Errorf("exp = %v, want %v", got.Exp, exp)
	}
	got.Exp = time.Time{}
	if got != streamClaims() {
		t.Fatalf("claims = %+v, want %+v", got, streamClaims())
	}
}

// A token opens only what it was minted for: its item, its route, the
// stream parameters the mint chose, within its lifetime and under the
// key that signed it.
func TestMediaTokenRejections(t *testing.T) {
	m := NewMediaTokens([]byte(testMediaSecret), time.Minute)
	token, _ := m.MintFor(streamClaims(), 0)
	other := NewMediaTokens([]byte("other-secret-other-secret-other!"), time.Minute)
	foreign, _ := other.MintFor(streamClaims(), 0)
	expired, _ := (&MediaTokens{key: m.key, ttl: -time.Minute}).MintFor(streamClaims(), 0)

	with := func(edit func(*MediaWant)) MediaWant {
		w := streamWant()
		edit(&w)
		return w
	}
	cases := map[string]struct {
		token string
		want  MediaWant
	}{
		"wrong pid":       {token, with(func(w *MediaWant) { w.PID = "tr-B" })},
		"wrong purpose":   {token, with(func(w *MediaWant) { w.Purposes = []string{PurposeDownload} })},
		"edited shape":    {token, with(func(w *MediaWant) { w.Shape = "fmt=flac" })},
		"stripped shape":  {token, with(func(w *MediaWant) { w.Shape = "" })},
		"empty token":     {"", streamWant()},
		"garbage":         {"not.a.token", streamWant()},
		"no separator":    {strings.ReplaceAll(token, ".", ""), streamWant()},
		"tampered body":   {"x" + token, streamWant()},
		"another key":     {foreign, streamWant()},
		"expired":         {expired, streamWant()},
		"tampered cred":   {retokenize(t, m, token, "se:se-01JZX5N8QW3F4V9T2B7KDEXAMPL", "se:se-SOMEBODYELSE"), streamWant()},
		"version 1 token": {v1Token(testMediaSecret, "us-1", "tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE"), streamWant()},
	}
	for name, c := range cases {
		if _, err := m.Verify(c.token, c.want); err == nil {
			t.Errorf("%s: Verify accepted", name)
		}
	}
}

// A route that serves two purposes names both, and a fetch surface whose
// resource lives inside the token takes any pid.
func TestMediaTokenPurposeSetsAndAnyPID(t *testing.T) {
	m := NewMediaTokens([]byte(testMediaSecret), time.Minute)
	stream, _ := m.MintFor(MediaClaims{User: "us-1", Purpose: PurposeStream, PID: "tr-A"}, 0)
	both := MediaWant{Purposes: []string{PurposeDownload, PurposeStream}, PID: "tr-A"}
	if got, err := m.Verify(stream, both); err != nil || got.Purpose != PurposeStream {
		t.Errorf("a stream token on a stream-or-download route = %+v, %v", got, err)
	}
	hls, _ := m.MintFor(MediaClaims{User: "us-1", Purpose: PurposeHLS, PID: "tl-abc"}, 0)
	got, err := m.Verify(hls, MediaWant{Purposes: []string{PurposeHLS}, AnyPID: true})
	if err != nil || got.PID != "tl-abc" {
		t.Errorf("an any-pid verify = %+v, %v", got, err)
	}
	if _, err := m.Verify(stream, MediaWant{Purposes: []string{PurposeHLS}, AnyPID: true}); err == nil {
		t.Error("a stream token opened the hls surface")
	}
}

// retokenize swaps one payload field and re-encodes the token with the
// original signature: what an attacker editing a token can produce.
func retokenize(t *testing.T, m *MediaTokens, token, from, to string) string {
	t.Helper()
	body, sig, _ := strings.Cut(token, ".")
	raw, err := base64.RawURLEncoding.DecodeString(body)
	if err != nil {
		t.Fatal(err)
	}
	edited := strings.Replace(string(raw), from, to, 1)
	if edited == string(raw) {
		t.Fatalf("%q is not in the payload %q", from, raw)
	}
	return base64.RawURLEncoding.EncodeToString([]byte(edited)) + "." + sig
}

// v1Token is a token as the previous release minted it: its own subkey
// and payload.
func v1Token(secret, user, pid string) string {
	sub := hmac.New(sha256.New, []byte(secret))
	sub.Write([]byte("waxdeck-media-token-v1"))
	payload := fmt.Sprintf("v1|%s|%s|%d", user, pid, time.Now().Add(time.Minute).Unix())
	mac := hmac.New(sha256.New, sub.Sum(nil))
	mac.Write([]byte(payload))
	enc := base64.RawURLEncoding
	return enc.EncodeToString([]byte(payload)) + "." + enc.EncodeToString(mac.Sum(nil))
}

// A query sealed beside a token opens with that token alone: another
// token, another server's key, or an edited value opens nothing, and the
// sealed form shows nothing of what it carries.
func TestSealedQueryOpensOnlyBesideItsToken(t *testing.T) {
	m := NewMediaTokens([]byte(testMediaSecret), time.Minute)
	token, _ := m.MintFor(streamClaims(), 0)
	other, _ := m.MintFor(MediaClaims{User: "us-2", Purpose: PurposeHLS, PID: "tr-2"}, 0)
	const descriptor = "eyJzcmMiOiJsaWIvQXJ0aXN0L0FsYnVtLzAxLmZsYWMifQ"
	query := "v=" + descriptor + "&sig=abc"
	sealed := m.SealQuery(token, query)
	// Read by its structure, not by short words: the sealed form is random
	// base64, where any three letters turn up now and then. It is a nonce,
	// the query enciphered, and the tag, and no longer than that, so nothing
	// rides beside the ciphertext; and the query is in it in neither form.
	raw, err := base64.RawURLEncoding.DecodeString(sealed)
	if err != nil {
		t.Fatalf("sealed %q is not base64url: %v", sealed, err)
	}
	if want := 12 + len(query) + 16; len(raw) != want {
		t.Fatalf("sealed %d bytes, want %d: a nonce, the query enciphered and the tag", len(raw), want)
	}
	if strings.Contains(string(raw), query) || strings.Contains(string(raw), descriptor) || strings.Contains(sealed, descriptor) {
		t.Fatalf("sealed %q shows what it carries", sealed)
	}
	if got, err := m.OpenQuery(token, sealed); err != nil || got != query {
		t.Fatalf("open = %q, %v; want the query back", got, err)
	}
	elsewhere := NewMediaTokens([]byte("another-secret-another-secret-12"), time.Minute)
	edited := []byte(sealed)
	edited[len(edited)/2] ^= 1
	for name, open := range map[string]func() (string, error){
		"another token":   func() (string, error) { return m.OpenQuery(other, sealed) },
		"another server":  func() (string, error) { return elsewhere.OpenQuery(token, sealed) },
		"an edited value": func() (string, error) { return m.OpenQuery(token, string(edited)) },
		"not base64":      func() (string, error) { return m.OpenQuery(token, "%%%") },
		"nothing":         func() (string, error) { return m.OpenQuery(token, "") },
	} {
		if got, err := open(); err == nil {
			t.Errorf("%s opened as %q", name, got)
		}
	}
}

// One query sealed beside one token seals the same every time, so a
// playlist fetched again lists the same URIs; beside another token, or
// another query, it seals otherwise, under a nonce of its own.
func TestASealedQuerySealsTheSameEveryTime(t *testing.T) {
	m := NewMediaTokens([]byte(testMediaSecret), time.Minute)
	token, _ := m.MintFor(streamClaims(), 0)
	other, _ := m.MintFor(MediaClaims{User: "us-2", Purpose: PurposeHLS, PID: "tr-2"}, 0)
	const query = "v=eyJzcmMiOiJsaWIvQXJ0aXN0L0FsYnVtLzAxLmZsYWMifQ&sig=abc"
	seal := func(token, query string) []byte {
		t.Helper()
		raw, err := base64.RawURLEncoding.DecodeString(m.SealQuery(token, query))
		if err != nil {
			t.Fatal(err)
		}
		return raw
	}
	first := seal(token, query)
	if again := seal(token, query); !bytes.Equal(again, first) {
		t.Fatalf("one query beside one token sealed %x, then %x", first, again)
	}
	for name, sealed := range map[string][]byte{
		"another token": seal(other, query),
		"another query": seal(token, query+"d"),
	} {
		if bytes.Equal(sealed[:12], first[:12]) {
			t.Errorf("%s sealed under the same nonce", name)
		}
	}
	// A playlist's worth through one sealer, its buffers reused, seals
	// each as SealQuery does and opens back to each.
	s := m.QuerySealer(token)
	var buf []byte
	for _, q := range []string{query, "v=x&sig=" + strings.Repeat("long", 100), "", query} {
		buf = s.Append(buf[:0], []byte(q))
		if string(buf) != m.SealQuery(token, q) {
			t.Errorf("%q sealed %q in a run, %q alone", q, buf, m.SealQuery(token, q))
		}
		if got, err := m.OpenQuery(token, string(buf)); err != nil || got != q {
			t.Errorf("%q opened as %q, %v", q, got, err)
		}
	}
}
