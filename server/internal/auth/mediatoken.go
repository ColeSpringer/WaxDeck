package auth

import (
	"crypto/cipher"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"hash"
	"slices"
	"strconv"
	"strings"
	"time"
)

// MediaTokens mints and verifies the short-TTL query tokens that
// authenticate media fetches. A token binds what it was minted for -
// account, credential, route, item, stream parameters, expiry - and the
// fetch checks every one; whether the account may still have it is
// re-checked by the fetch's own authorization, on every request.
type MediaTokens struct {
	key   []byte
	ttl   time.Duration
	query *AADSealer
	// nonce keys the nonce a sealed query is enciphered under, apart from
	// the key that enciphers it (SealQuery).
	nonce []byte
}

// DefaultMediaTokenTTL bounds how long a minted stream URL stays
// playable. Clients re-request play-info on expiry.
const DefaultMediaTokenTTL = 15 * time.Minute

// Media token purposes: a token opens only the route it was minted for.
const (
	PurposeStream    = "stream"
	PurposeDownload  = "download"
	PurposeArt       = "art"
	PurposeEnclosure = "enclosure"
	PurposeRadio     = "radio"
	PurposeProbe     = "probe"
	PurposeHLS       = "hls"
)

// MediaClaims is what a media token was minted for.
//
// Cred names what the mint ran under, and the token dies with it:
// "se:<session id>" for the REST API, "ap:<app password id>" for the
// compatibility APIs, "re:<epoch>" for a timeline (the account's reach
// when it was minted, comma-joined with the session's when the REST API
// minted it), and empty for a token the server minted on an account's
// behalf (a cast queue), which dies with the account. Shape is the
// stream parameters the mint chose, empty off the stream route.
type MediaClaims struct {
	User    string
	Cred    string
	Purpose string
	PID     string
	Shape   string
	Exp     time.Time
}

// MediaWant is what a fetch accepts: one of Purposes, the PID unless
// AnyPID (a surface whose resource lives inside the token), and exactly
// Shape.
type MediaWant struct {
	Purposes []string
	PID      string
	AnyPID   bool
	Shape    string
}

// ErrBadToken reports a token that failed verification for any reason
// (malformed, forged, expired, minted for something else). Callers treat
// all cases identically.
var ErrBadToken = errors.New("auth: invalid media token")

// ErrMediaRevoked is a fetch's refusal of a valid token whose account or
// credential is gone, answered exactly like a bad token.
var ErrMediaRevoked = errors.New("auth: the media token's account or credential is no longer valid")

// NewMediaTokens derives the media-token subkey from the server secret.
// ttl of 0 selects the default. The label names the token format, so a
// token of an earlier format fails outright.
func NewMediaTokens(secret []byte, ttl time.Duration) *MediaTokens {
	if ttl <= 0 {
		ttl = DefaultMediaTokenTTL
	}
	mac := hmac.New(sha256.New, secret)
	mac.Write([]byte("waxdeck-media-token-v2"))
	key := mac.Sum(nil)
	query, err := NewAADSealer(key, "waxdeck-media-query-v1")
	if err != nil {
		// AES-256 takes any 32-byte key, which an HMAC-SHA256 always is.
		panic(err)
	}
	nonce := hmac.New(sha256.New, key)
	nonce.Write([]byte("waxdeck-media-query-nonce-v1"))
	return &MediaTokens{key: key, ttl: ttl, query: query, nonce: nonce.Sum(nil)}
}

// SealQuery hides a query a media URL has to carry from the listener the
// URL is handed to, bound to the token beside it: the HLS proxy's child
// URLs name the engine's signed queries, file paths and identities among
// them. Only OpenQuery with the same token reads it back.
//
// The same query beside the same token seals the same every time, so a
// playlist fetched again lists the same URIs: the nonce is drawn from the
// two under a key of its own (a synthetic nonce), and equal inputs are all
// one sealed form shows of another. Distinct inputs take distinct nonces
// but for a collision of 96-bit digests.
func (m *MediaTokens) SealQuery(token, query string) string {
	return string(m.QuerySealer(token).Append(nil, []byte(query)))
}

// QuerySealer seals queries beside one token as SealQuery does, for a
// caller sealing many of them, a playlist's children: the token's share
// of the work is done once, and its buffers serve every query. Not safe
// for concurrent use.
type QuerySealer struct {
	aead cipher.AEAD
	// mac is keyed by the token's own nonce key.
	mac   hash.Hash
	token []byte
	sum   [sha256.Size]byte
	out   []byte
}

// QuerySealer starts sealing beside token.
func (m *MediaTokens) QuerySealer(token string) *QuerySealer {
	key := hmac.New(sha256.New, m.nonce)
	key.Write([]byte(token))
	return &QuerySealer{aead: m.query.aead, mac: hmac.New(sha256.New, key.Sum(nil)), token: []byte(token)}
}

// Append appends query sealed, base64url, to dst: the nonce, the query
// enciphered and the tag.
func (s *QuerySealer) Append(dst, query []byte) []byte {
	s.mac.Reset()
	s.mac.Write(query)
	nonce := s.mac.Sum(s.sum[:0])[:s.aead.NonceSize()]
	s.out = s.aead.Seal(append(s.out[:0], nonce...), nonce, query, s.token)
	return base64.RawURLEncoding.AppendEncode(dst, s.out)
}

// OpenQuery answers the query SealQuery sealed beside token. Anything
// else - another token, another key, an edit - is ErrBadToken.
func (m *MediaTokens) OpenQuery(token, sealed string) (string, error) {
	raw, err := base64.RawURLEncoding.DecodeString(sealed)
	if err != nil {
		return "", ErrBadToken
	}
	query, err := m.query.Open([]byte(token), raw)
	if err != nil {
		return "", ErrBadToken
	}
	return string(query), nil
}

// MintFor mints a token for the claims (Exp is set here). Long-running
// deliveries (queue timelines, whole-queue casts) size the token to the
// content so playback never dies mid-listen; ttl of 0 selects the
// default.
func (m *MediaTokens) MintFor(c MediaClaims, ttl time.Duration) (token string, exp time.Time) {
	if ttl <= 0 {
		ttl = m.ttl
	}
	exp = time.Now().Add(ttl).UTC().Truncate(time.Second)
	// IDs are ULID derived and the shape is query-escaped, so none of
	// them carries the separator; one that did would shift the fields
	// and fail verification rather than verify as something else.
	payload := strings.Join([]string{
		"v2", c.User, c.Cred, c.Purpose, c.PID, strconv.FormatInt(exp.Unix(), 10), c.Shape,
	}, "|")
	enc := base64.RawURLEncoding
	return enc.EncodeToString([]byte(payload)) + "." + enc.EncodeToString(m.sign(payload)), exp
}

// Verify checks a token against what the fetch accepts and returns its
// claims.
func (m *MediaTokens) Verify(token string, want MediaWant) (MediaClaims, error) {
	enc := base64.RawURLEncoding
	payloadB64, sigB64, ok := strings.Cut(token, ".")
	if !ok {
		return MediaClaims{}, ErrBadToken
	}
	payload, err := enc.DecodeString(payloadB64)
	if err != nil {
		return MediaClaims{}, ErrBadToken
	}
	sig, err := enc.DecodeString(sigB64)
	if err != nil || !hmac.Equal(sig, m.sign(string(payload))) {
		return MediaClaims{}, ErrBadToken
	}
	parts := strings.SplitN(string(payload), "|", 7)
	if len(parts) != 7 || parts[0] != "v2" {
		return MediaClaims{}, ErrBadToken
	}
	expUnix, err := strconv.ParseInt(parts[5], 10, 64)
	if err != nil || time.Now().Unix() > expUnix {
		return MediaClaims{}, ErrBadToken
	}
	c := MediaClaims{
		User: parts[1], Cred: parts[2], Purpose: parts[3], PID: parts[4],
		Exp: time.Unix(expUnix, 0).UTC(), Shape: parts[6],
	}
	if !slices.Contains(want.Purposes, c.Purpose) ||
		(!want.AnyPID && c.PID != want.PID) || c.Shape != want.Shape {
		return MediaClaims{}, ErrBadToken
	}
	return c, nil
}

func (m *MediaTokens) sign(payload string) []byte {
	mac := hmac.New(sha256.New, m.key)
	mac.Write([]byte(payload))
	return mac.Sum(nil)
}
