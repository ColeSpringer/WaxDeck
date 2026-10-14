package auth

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"errors"
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
	key []byte
	ttl time.Duration
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
	return &MediaTokens{key: mac.Sum(nil), ttl: ttl}
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
