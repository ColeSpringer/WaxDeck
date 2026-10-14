package flow

import (
	"context"
	"errors"
	"net/http"

	"github.com/colespringer/waxdeck/server/internal/auth"
)

// TranscodeKind names what a slot is being held for, so the activity
// read can say how much of a count is one thing or the other. The caps
// do not distinguish: a slot is a slot, and this is only ever reporting.
type TranscodeKind string

const (
	// TranscodeStream is one engine-backed progressive stream.
	TranscodeStream TranscodeKind = "stream"
	// TranscodeTimeline is one listener's gapless queue rendering. One
	// slot covers every timeline they hold live at once, because a queue
	// edit mints another while the one playing is still being fetched
	// and refusing that would stall the music the edit was made in.
	TranscodeTimeline TranscodeKind = "timeline"
)

// TranscodeGate admits or refuses engine-backed sessions. The
// implementation lives with the service layer, which knows the acting
// user's permissions and the admin-set limits; the bridge only asks.
type TranscodeGate interface {
	// Acquire reserves a session slot for the user, returning a release
	// the caller runs when the session ends. ErrTranscodeLimited when a
	// limit is reached. The context is the request's.
	Acquire(ctx context.Context, user string, kind TranscodeKind) (release func(), err error)
	// MaxBitrateKbps reports the user's transcode bitrate ceiling in
	// kbit/s; 0 means none.
	MaxBitrateKbps(ctx context.Context, user string) int
	// AuthorizeMedia re-runs a media token's mint-time check on a fetch.
	// An error wrapping auth.ErrMediaRevoked refuses the token's account
	// or credential, one wrapping ErrMediaRefused refuses the item, one
	// wrapping ErrCatalogMaintenance is the catalog briefly unavailable,
	// and any other is a check that could not be made.
	AuthorizeMedia(ctx context.Context, c auth.MediaClaims) error
}

// ErrTranscodeLimited is the gate's refusal.
var ErrTranscodeLimited = errors.New("transcode session limit reached")

// ErrMediaRefused is the gate's refusal of the item a media token names:
// gone, or no longer within its account's reach.
var ErrMediaRefused = errors.New("the media token's item is not available to its account")

// ErrCatalogMaintenance is a check the gate could not make because the
// catalog is handed to a maintenance operation for the moment.
var ErrCatalogMaintenance = errors.New("the catalog is in maintenance")

// Up reports whether the streaming engine serves streams, false for a
// server without one. Every site that picks between the engine and the
// original bytes asks this, so a runtime notion of "up" lands in one
// place.
func (b *Bridge) Up() bool { return b != nil }

// SetTranscodeGate wires the session gate. Without one (the default)
// sessions are admitted and uncapped, but no media token is served: the
// per-fetch check is the gate's, and a bridge that cannot ask it refuses
// rather than serving revoked tokens. Called once at startup, before
// the bridge serves.
func (b *Bridge) SetTranscodeGate(g TranscodeGate) { b.gate = g }

// authorize re-runs the token's mint-time check through the gate,
// answering the request itself on refusal: a token whose account or
// credential is gone is as bad as no token, and an item it may no
// longer have is not found. A check that failed is the server's own
// trouble, which a player retries rather than reading as a verdict.
func (b *Bridge) authorize(ctx context.Context, w http.ResponseWriter, c auth.MediaClaims) bool {
	if b.gate == nil {
		writeJSONError(w, http.StatusInternalServerError, "internal", "media tokens cannot be checked on this server")
		return false
	}
	err := b.gate.AuthorizeMedia(ctx, c)
	switch {
	case err == nil:
		return true
	case errors.Is(err, auth.ErrMediaRevoked):
		writeJSONError(w, http.StatusUnauthorized, "unauthenticated", "invalid or expired media token")
	case errors.Is(err, ErrMediaRefused):
		writeJSONError(w, http.StatusNotFound, "not-found", "no streamable item with pid "+c.PID)
	case errors.Is(err, ErrCatalogMaintenance):
		writeJSONError(w, http.StatusServiceUnavailable, "catalog-maintenance", "the catalog is in maintenance; retry shortly")
	default:
		writeJSONError(w, http.StatusInternalServerError, "internal", "checking the media token failed")
	}
	return false
}

// admit reserves a session slot, answering the request itself on
// refusal. The returned release is non-nil exactly when admitted.
// Callers gate only engine-backed shapes: direct-played originals
// (byte-range seekable passthrough) never count, both because the
// contract says so and because players probe seekable URLs with
// several concurrent range requests that must not eat session slots.
func (b *Bridge) admit(ctx context.Context, w http.ResponseWriter, user string) (func(), bool) {
	if b.gate == nil {
		return func() {}, true
	}
	release, err := b.gate.Acquire(ctx, user, TranscodeStream)
	if err != nil {
		writeJSONError(w, http.StatusTooManyRequests, "transcode-limited",
			"the server's transcode session limit is reached; retry when a stream ends, or play a direct-play format")
		return nil, false
	}
	return release, true
}

// lossyBitrateFormats are the outputs a bitrate ceiling applies to;
// lossless outputs carry no bitrate parameter.
var lossyBitrateFormats = map[string]bool{
	"mp3": true, "opus": true, "vorbis": true, "aac": true,
}
